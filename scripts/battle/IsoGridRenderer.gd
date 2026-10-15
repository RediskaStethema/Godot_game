class_name IsoGridRenderer
extends Node2D

# Рисует поле боя в духе 9 Kings: общая платформа, на ней — плиты королевства
# игрока, плиты зоны врага и декор. Плитки и декор — из темы расы игрока
# (FactionTheme.current()). Поверх — подсветка клеток королевства (наведение, занято, покупка) —
# только на расстановке (grid_overlay, решение пользователя): в бою видно только поле, здания,
# цитадель и бойцов. Зона врага не подсвечивается.

var grid: IsoGrid

# --- Плоты королевства (полупрозрачная подсветка поверх плит) ---
const COLOR_NORMAL   = Color(0.30, 0.40, 0.58, 0.10)   # сталь
const COLOR_HOVER    = Color(0.94, 0.83, 0.55, 0.40)   # светлое золото
const COLOR_OCCUPIED = Color(0.79, 0.63, 0.29, 0.22)   # золото
const COLOR_SAME_SQUAD = Color(0.98, 0.72, 0.29, 0.45)  # отряд карты под курсором (скамейка)
const LINE_SAME_SQUAD  = Color(1.0, 0.82, 0.45, 1.0)
const COLOR_EFFECT = Color(0.35, 0.85, 0.80, 0.30)     # зона действия здания (Казармы — соседи)
const LINE_EFFECT  = Color(0.45, 0.95, 0.90, 0.95)
const LINE_PLAYER    = Color(0.79, 0.63, 0.29, 0.45)
const BORDER_PLAYER  = Color(0.79, 0.63, 0.29, 0.95)
# --- Закрытые клетки рамки королевства ---
const LINE_LOCKED    = Color(0.79, 0.63, 0.29, 0.12)
const COLOR_BUYABLE  = Color(0.30, 0.55, 0.30, 0.25)   # можно купить
const COLOR_BUYABLE_HOVER = Color(0.45, 0.80, 0.45, 0.45)
const LINE_BUYABLE   = Color(0.55, 0.85, 0.55, 0.80)
const PRICE_FONT_SIZE: int = 15

# --- Платформа ---
const FLOOR_PAD_TILES: int = 5          # поле шире раскладки на столько тайлов (камера в бою отъезжает)
const FLOOR_TINT = Color(0.72, 0.70, 0.68)   # пол чуть темнее — юниты читаются лучше
const DECOR_CHANCE: int = 12            # % клеток вне боевой полосы с декором
const DECOR_FLAT_CHANCE: int = 4        # % клеток «ничьей земли» с кратером
# Реки (тема: "river") — прямые линии через всё поле, своя раскладка в каждом забеге (seed забега):
# первая поперёк ничьей земли, вторая (с этим шансом) вдоль поля в стороне от боевой полосы
const RIVER_SECOND_CHANCE: float = 0.5
# Местность (тема: "ground" / "features"): соседи клетки для роста групп деталей; группа, упёршаяся
# в край или реку, бросает расти с таким шансом на каждой неудачной попытке
const NEIGHBOURS = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const CLUSTER_GIVE_UP: float = 0.2

var grid_overlay: bool = true   # подсветка клеток королевства (в бою выключена)
var hovered_tile: Vector2i = Vector2i(-1, -1)
var occupied_tiles_player: Dictionary = {}
var occupied_tiles_enemy: Dictionary = {}
# Клетки отрядов карты под курсором на скамейке (BattleScene._on_bench_card_hovered)
var highlighted_tiles: Array[Vector2i] = []
# Зона действия здания под курсором / перетаскиваемой карты здания (Building.get_effect_tiles)
var effect_tiles: Array[Vector2i] = []
# Клетки, которые сейчас можно купить, и их цена (пусто — расширение недоступно)
var expansion_tiles: Array[Vector2i] = []
var expansion_cost: int = 0

var _floor: Node2D = null   # пол рисуется один раз, отдельно от подсветки плотов
var theme: Dictionary = {}  # FactionTheme расы игрока

func setup(iso_grid: IsoGrid) -> void:
	grid = iso_grid
	theme = FactionTheme.current()
	_floor = Node2D.new()
	_floor.show_behind_parent = true
	_floor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # пиксель-арт без размытия
	_floor.draw.connect(_draw_floor)
	add_child(_floor)

func _draw() -> void:
	if not grid or not grid_overlay:
		return
	_draw_kingdom()

# Подсветка клеток королевства: на расстановке — да, в бою — нет (BattleScene._on_start_pressed)
func set_grid_overlay(visible_overlay: bool) -> void:
	grid_overlay = visible_overlay
	queue_redraw()

# Пол перерисовывается только при изменении королевства (покупка клетки)
func refresh_floor() -> void:
	if _floor:
		_floor.queue_redraw()

# -------------------------------------------------------
# ПЛАТФОРМА
# -------------------------------------------------------
# Клетки пола в координатах королевства (col, row), от дальних к ближним
func _floor_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for u in range(-FLOOR_PAD_TILES, grid.get_layout_cols() + FLOOR_PAD_TILES):
		for v in range(-FLOOR_PAD_TILES, grid.get_layout_rows() + FLOOR_PAD_TILES):
			cells.append(Vector2i(u, v))
	# Блоки рисуем от дальних (меньше u+v) к ближним — передние перекрывают задние
	cells.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
	return cells

# Клетка зоны врага в координатах королевства
func _is_enemy_cell(c: Vector2i) -> bool:
	var start = grid.grid_width + grid.gap_tiles
	return c.x >= start and c.x < start + grid.enemy_width and c.y >= 0 and c.y < grid.enemy_height

# Плита линии (край, река) вдоль оси line_axis ("u" / "v"); у плиты темы "axis" — вдоль какой оси
# нарисована картинка, по другой оси — отражаем
func _draw_line_tile(variants: Array, c: Vector2i, top: Vector2, line_axis: String) -> void:
	var entry = TerrainTiles.pick_any(variants, c)
	var art_axis: String = entry.get("axis", line_axis) if entry is Dictionary else line_axis
	TerrainTiles.draw_theme_tile(_floor, entry, top, FLOOR_TINT, art_axis != line_axis)

# Клетки рек: клетка → ось русла ("u" / "v"). Реки не идут по королевству, цитадели и зоне врага
func _river_cells() -> Dictionary:
	var cells: Dictionary = {}
	if not theme.has("river"):
		return cells
	var rng = RandomNumberGenerator.new()
	rng.seed = hash([RunManager.rng.seed, "rivers"])
	var lo = -FLOOR_PAD_TILES + 1
	var cols = grid.get_layout_cols()
	var rows = grid.get_layout_rows()
	# Поперёк ничьей земли: u постоянно, русло вдоль v
	var u = rng.randi_range(grid.grid_width + 1, grid.grid_width + grid.gap_tiles - 2)
	for v in range(lo, rows + FLOOR_PAD_TILES - 1):
		cells[Vector2i(u, v)] = "v"
	# Вдоль поля в стороне от боевой полосы: v постоянно, русло вдоль u
	if rng.randf() < RIVER_SECOND_CHANCE:
		var v = rng.randi_range(lo + 1, -2) if rng.randf() < 0.5 \
			else rng.randi_range(rows + 1, rows + FLOOR_PAD_TILES - 3)
		for uu in range(lo, cols + FLOOR_PAD_TILES - 1):
			cells[Vector2i(uu, v)] = "u"
	for c in cells.keys():
		if grid.is_valid_tile(c) or c == grid.citadel_tile or _is_enemy_cell(c):
			cells.erase(c)
	return cells

# Естественная местность (тема: "ground" + "features"): клетка → [плитка, отражена ли].
# Основа — грунт (отражается по хэшу клетки, чтобы не было повторяющегося узора), поверх —
# редкие детали: группы {"clusters": N, "size": [от, до]} растут от случайной клетки в соседние,
# одиночные {"scatter": доля клеток}. Знамёна (тема: "flags") — count клеток на стороне игрока.
# Раскладка — от seed забега и не зависит от купленных клеток: рамка королевства в списке
# целиком (его клетки рисуются своей плиткой раньше), детали в неё не ставятся
func _terrain_cells(cells: Array[Vector2i], rivers: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if not theme.has("ground"):
		return result
	var free: Array[Vector2i] = []
	for c in cells:
		if not _is_floor_edge(c) and not rivers.has(c) and c != grid.citadel_tile:
			free.append(c)
			result[c] = [TerrainTiles.pick_any(theme["ground"], c), TerrainTiles.hash_cell(c, 53) % 2 == 1]
	var spots = free.filter(func(c): return not grid.is_in_bounds(c))
	if spots.is_empty():
		return result
	var rng = RandomNumberGenerator.new()
	rng.seed = hash([RunManager.rng.seed, "terrain"])
	var taken: Dictionary = {}
	for f in theme.get("features", []):
		if f.has("clusters"):
			for i in f["clusters"]:
				var cluster: Array[Vector2i] = [spots[rng.randi() % spots.size()]]
				var size = rng.randi_range(f["size"][0], f["size"][1])
				while cluster.size() < size:
					var from: Vector2i = cluster[rng.randi() % cluster.size()]
					var next: Vector2i = from + NEIGHBOURS[rng.randi() % NEIGHBOURS.size()]
					if result.has(next) and not grid.is_in_bounds(next) and not cluster.has(next):
						cluster.append(next)
					elif rng.randf() < CLUSTER_GIVE_UP:
						break   # упёрлись в край / реку — группа меньше
				for c in cluster:
					_put_feature(result, taken, c, f["tiles"])
		else:
			for c in spots:
				if rng.randf() < f["scatter"]:
					_put_feature(result, taken, c, f["tiles"])
	if theme.has("flags"):
		var player_side = spots.filter(func(c): return c.x < grid.grid_width + grid.gap_tiles / 2 \
			and not taken.has(c))
		for i in mini(theme["flags"]["count"], player_side.size()):
			_put_feature(result, taken, player_side.pop_at(rng.randi() % player_side.size()), theme["flags"]["tiles"])
	return result

func _put_feature(result: Dictionary, taken: Dictionary, c: Vector2i, tiles: Array) -> void:
	if taken.has(c):
		return
	taken[c] = true
	result[c] = [TerrainTiles.pick_any(tiles, c), false]

# Внешнее кольцо пола — край карты (тема: "edge")
func _is_floor_edge(c: Vector2i) -> bool:
	return c.x == -FLOOR_PAD_TILES or c.y == -FLOOR_PAD_TILES \
		or c.x == grid.get_layout_cols() + FLOOR_PAD_TILES - 1 or c.y == grid.get_layout_rows() + FLOOR_PAD_TILES - 1

# Боевая полоса: королевство, ничья земля и зона врага — здесь только плоский декор
func _is_battle_strip(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < grid.get_layout_cols() and c.y >= 0 and c.y < grid.get_layout_rows()

func _draw_floor() -> void:
	var cells = _floor_cells()
	var rivers = _river_cells()
	var terrain = _terrain_cells(cells, rivers)
	for c in cells:
		var top = grid.lattice_to_screen(c.x, c.y)
		if grid.is_valid_tile(c):
			TerrainTiles.draw_theme_tile(_floor, TerrainTiles.pick_any(theme["kingdom"], c), top)
		elif _is_floor_edge(c) and theme.has("edge"):
			# Края с постоянным u идут вдоль оси v, с постоянным v — вдоль u
			var along_v = c.x == -FLOOR_PAD_TILES or c.x == grid.get_layout_cols() + FLOOR_PAD_TILES - 1
			_draw_line_tile(theme["edge"], c, top, "v" if along_v else "u")
		elif rivers.has(c):
			_draw_line_tile(theme["river"], c, top, rivers[c])
		elif terrain.has(c):
			TerrainTiles.draw_theme_tile(_floor, terrain[c][0], top, FLOOR_TINT, terrain[c][1])
		elif _is_enemy_cell(c):
			TerrainTiles.draw_theme_tile(_floor, TerrainTiles.pick_any(theme["enemy"], c), top, FLOOR_TINT)
		else:
			TerrainTiles.draw_theme_tile(_floor, TerrainTiles.pick_any(theme["floor"], c), top, FLOOR_TINT)

	# Декор — поверх пола. В боевой полосе только плоские кратеры, и не на клетках королевства
	for c in cells:
		if grid.is_in_bounds(c) or c == grid.citadel_tile or rivers.has(c):
			continue
		var in_strip = _is_battle_strip(c)
		var roll = TerrainTiles.hash_cell(c, 7) % 100
		if roll >= (DECOR_FLAT_CHANCE if in_strip else DECOR_CHANCE):
			continue
		var options = theme["decorations"].filter(func(d): return d[1] or not in_strip)
		if options.is_empty():
			continue
		var deco = options[TerrainTiles.hash_cell(c, 13) % options.size()]
		var jitter = Vector2((TerrainTiles.hash_cell(c, 21) % 41) - 20, (TerrainTiles.hash_cell(c, 29) % 17) - 8)
		TerrainTiles.draw_decoration(_floor, TerrainTiles.decoration(deco[0]), grid.lattice_to_screen(c.x, c.y) + jitter)

# -------------------------------------------------------
# КОРОЛЕВСТВО И ЗОНА ВРАГА
# -------------------------------------------------------
func _draw_kingdom() -> void:
	# Закрытые клетки рамки — едва заметный контур: видно, куда можно расти
	for row in range(grid.grid_height):
		for col in range(grid.grid_width):
			var t = Vector2i(col, row)
			if not grid.is_valid_tile(t) and not expansion_tiles.has(t):
				_draw_diamond(grid.tile_to_screen(t, false), Color(0, 0, 0, 0), LINE_LOCKED)

	for tile in grid.get_all_tiles():
		var color = COLOR_NORMAL
		if tile == hovered_tile:
			color = COLOR_HOVER
		elif highlighted_tiles.has(tile):
			color = COLOR_SAME_SQUAD
		elif occupied_tiles_player.has(tile):
			color = COLOR_OCCUPIED
		_draw_diamond(grid.tile_to_screen(tile, false), color, LINE_PLAYER)
	_draw_kingdom_border(BORDER_PLAYER, 3.0)
	# Контур подсвеченных клеток — поверх общей рамки, чтобы читался и на краю королевства
	for tile in highlighted_tiles:
		_draw_diamond(grid.tile_to_screen(tile, false), Color(0, 0, 0, 0), LINE_SAME_SQUAD, 3.0)
	# Зона действия здания — только открытые клетки королевства
	for tile in effect_tiles:
		if grid.is_valid_tile(tile):
			_draw_diamond(grid.tile_to_screen(tile, false), COLOR_EFFECT, LINE_EFFECT, 2.5)

	var font = ThemeDB.fallback_font
	for tile in expansion_tiles:
		var center = grid.tile_to_screen(tile, false)
		var color = COLOR_BUYABLE_HOVER if tile == hovered_tile else COLOR_BUYABLE
		_draw_diamond(center, color, LINE_BUYABLE)
		var text = "+ %d Req" % expansion_cost
		var w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, PRICE_FONT_SIZE).x
		draw_string_outline(font, center + Vector2(-w / 2.0, PRICE_FONT_SIZE * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, PRICE_FONT_SIZE, 4, Color(0, 0, 0, 0.85))
		draw_string(font, center + Vector2(-w / 2.0, PRICE_FONT_SIZE * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, PRICE_FONT_SIZE, LINE_BUYABLE)

# Контур королевства — только внешние рёбра открытых клеток
# (после покупки клеток королевство может быть не прямоугольным)
func _draw_kingdom_border(color: Color, width: float) -> void:
	var hw = IsoGrid.TILE_WIDTH / 2.0
	var hh = IsoGrid.TILE_HEIGHT / 2.0
	var top = Vector2(0, -hh); var right = Vector2(hw, 0)
	var bottom = Vector2(0, hh); var left = Vector2(-hw, 0)
	# Сосед → ребро ромба, которое с ним граничит
	var edges = {
		Vector2i(0, -1): [top, right],    # row - 1
		Vector2i(1, 0):  [right, bottom], # col + 1
		Vector2i(0, 1):  [bottom, left],  # row + 1
		Vector2i(-1, 0): [left, top],     # col - 1
	}
	for tile in grid.get_all_tiles():
		var c = grid.tile_to_screen(tile, false)
		for n in edges:
			if not grid.is_valid_tile(tile + n):
				draw_line(c + edges[n][0], c + edges[n][1], color, width, true)

func set_expansion(tiles: Array[Vector2i], cost: int) -> void:
	expansion_tiles = tiles
	expansion_cost = cost
	queue_redraw()
	refresh_floor()

func _draw_diamond(center: Vector2, color: Color, line_color: Color, line_width: float = 1.5) -> void:
	var hw = IsoGrid.TILE_WIDTH / 2
	var hh = IsoGrid.TILE_HEIGHT / 2

	var points = PackedVector2Array([
		center + Vector2(0, -hh),
		center + Vector2(hw, 0),
		center + Vector2(0, hh),
		center + Vector2(-hw, 0),
	])

	draw_colored_polygon(points, color)
	draw_polyline(
		PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]),
		line_color,
		line_width,
		true
	)

func set_effect_tiles(tiles: Array[Vector2i]) -> void:
	if tiles == effect_tiles:
		return
	effect_tiles = tiles
	queue_redraw()

func set_highlighted(tiles: Array[Vector2i]) -> void:
	highlighted_tiles = tiles
	queue_redraw()

func update_hover(tile: Vector2i) -> void:
	hovered_tile = tile
	queue_redraw()

func set_occupied(tile: Vector2i, occupied: bool, is_enemy: bool = false) -> void:
	var dict = occupied_tiles_enemy if is_enemy else occupied_tiles_player
	if occupied:
		dict[tile] = true
	else:
		dict.erase(tile)
	queue_redraw()
