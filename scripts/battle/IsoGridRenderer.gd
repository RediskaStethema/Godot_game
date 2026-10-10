class_name IsoGridRenderer
extends Node2D

# Рисует поле боя в духе 9 Kings: общая платформа, на ней — плиты королевства
# игрока, плиты зоны врага и декор. Плитки и декор — из темы расы игрока
# (FactionTheme.current()). Поверх — подсветка клеток (наведение, занято, покупка).

var grid: IsoGrid

# --- Плоты королевства (полупрозрачная подсветка поверх плит) ---
const COLOR_NORMAL   = Color(0.30, 0.40, 0.58, 0.10)   # сталь
const COLOR_HOVER    = Color(0.94, 0.83, 0.55, 0.40)   # светлое золото
const COLOR_OCCUPIED = Color(0.79, 0.63, 0.29, 0.22)   # золото
const LINE_PLAYER    = Color(0.79, 0.63, 0.29, 0.45)
const BORDER_PLAYER  = Color(0.79, 0.63, 0.29, 0.95)
# --- Закрытые клетки рамки королевства ---
const LINE_LOCKED    = Color(0.79, 0.63, 0.29, 0.12)
const COLOR_BUYABLE  = Color(0.30, 0.55, 0.30, 0.25)   # можно купить
const COLOR_BUYABLE_HOVER = Color(0.45, 0.80, 0.45, 0.45)
const LINE_BUYABLE   = Color(0.55, 0.85, 0.55, 0.80)
const PRICE_FONT_SIZE: int = 15
# --- Зона врага ---
const COLOR_ENEMY    = Color(0.56, 0.15, 0.13, 0.10)
const BORDER_ENEMY   = Color(0.78, 0.27, 0.23, 0.35)

# --- Платформа ---
const FLOOR_PAD_TILES: int = 5          # поле шире раскладки на столько тайлов (камера в бою отъезжает)
const FLOOR_TINT = Color(0.72, 0.70, 0.68)   # пол чуть темнее — юниты читаются лучше
const DECOR_CHANCE: int = 12            # % клеток вне боевой полосы с декором
const DECOR_FLAT_CHANCE: int = 4        # % клеток «ничьей земли» с кратером

var hovered_tile: Vector2i = Vector2i(-1, -1)
var occupied_tiles_player: Dictionary = {}
var occupied_tiles_enemy: Dictionary = {}
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
	if not grid:
		return
	_draw_enemy_zone()
	_draw_kingdom()

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

# Боевая полоса: королевство, ничья земля и зона врага — здесь только плоский декор
func _is_battle_strip(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < grid.get_layout_cols() and c.y >= 0 and c.y < grid.get_layout_rows()

func _draw_floor() -> void:
	var cells = _floor_cells()
	for c in cells:
		var top = grid.lattice_to_screen(c.x, c.y)
		if grid.is_valid_tile(c):
			TerrainTiles.draw_theme_tile(_floor, TerrainTiles.pick_any(theme["kingdom"], c), top)
		elif _is_enemy_cell(c):
			TerrainTiles.draw_theme_tile(_floor, TerrainTiles.pick_any(theme["enemy"], c), top, FLOOR_TINT)
		else:
			TerrainTiles.draw_theme_tile(_floor, TerrainTiles.pick_any(theme["floor"], c), top, FLOOR_TINT)

	# Декор — поверх пола. В боевой полосе только плоские кратеры, и не на клетках королевства
	for c in cells:
		if grid.is_in_bounds(c) or c == grid.citadel_tile:
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
		elif occupied_tiles_player.has(tile):
			color = COLOR_OCCUPIED
		_draw_diamond(grid.tile_to_screen(tile, false), color, LINE_PLAYER)
	_draw_kingdom_border(BORDER_PLAYER, 3.0)

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

func _draw_enemy_zone() -> void:
	var pts = _border_points(true)
	draw_colored_polygon(pts, COLOR_ENEMY)
	pts.append(pts[0])
	draw_polyline(pts, BORDER_ENEMY, 2.0, true)

func _border_points(is_enemy: bool) -> PackedVector2Array:
	var hw = IsoGrid.TILE_WIDTH / 2.0
	var hh = IsoGrid.TILE_HEIGHT / 2.0
	var w = (grid.enemy_width if is_enemy else grid.grid_width) - 1
	var h = (grid.enemy_height if is_enemy else grid.grid_height) - 1
	return PackedVector2Array([
		grid.tile_to_screen(Vector2i(0, 0), is_enemy) + Vector2(0, -hh),
		grid.tile_to_screen(Vector2i(w, 0), is_enemy) + Vector2(hw, 0),
		grid.tile_to_screen(Vector2i(w, h), is_enemy) + Vector2(0, hh),
		grid.tile_to_screen(Vector2i(0, h), is_enemy) + Vector2(-hw, 0),
	])

func _draw_diamond(center: Vector2, color: Color, line_color: Color) -> void:
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
		1.5,
		true
	)

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
