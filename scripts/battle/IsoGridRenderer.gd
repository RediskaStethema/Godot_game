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
# Карта поля — одна на расу, не новая в каждом забеге (решение пользователя): раскладка реки,
# местности и знамён — от seed карты темы ("map_seed"), не от seed забега
const DEFAULT_MAP_SEED: int = 1
# Река (тема: "river") — одна прямая линия вдоль поля боя (решение пользователя), в стороне от
# боевой полосы и не у цитадели; ряд — от seed карты
# Местность (тема: "ground" / "features"): соседи клетки для роста групп деталей. Группа растёт
# только в свободные клетки, где её плитка допустима, и не касается других групп того же вида —
# иначе туман рвался на куски (кратеры раньше него) и группы сливались; не выросла за
# CLUSTER_TRIES попыток — остаётся меньше
const NEIGHBOURS = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const CLUSTER_TRIES: int = 40
# Вокруг цитадели (клетки в стольких шагах) — просто грунт: ни руин, ни тумана, ни декора (решение пользователя)
const CITADEL_CLEAR: int = 1
# Знамёна (плитки и декор темы с "flag") — только на стороне игрока; декор-знамя — лишь на каждой
# FLAG_DECOR_RARITY-й клетке, где выпал бы
const FLAG_DECOR_RARITY: int = 3

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

var _floor: Node2D = null   # пол — отдельный узел под подсветкой плотов
var theme: Dictionary = {}  # FactionTheme расы игрока
# Анимированные плиты темы ({"frames", "fps"} — кратеры с туманом): время anim_time, сдвиг клетки
# плавно растёт по полю — туман катится по местности волной, а не «дышит» разом;
# пол перерисовывается ANIM_REDRAW_FPS раз в секунду.
# Раскладка пола (клетки, реки, местность) считается один раз до refresh_floor
const ANIM_REDRAW_FPS: float = 12.0
const ANIM_WAVE = Vector2(0.25, 0.4)   # сдвиг времени клетки, с на шаг по u / v (соседи — почти в фазе)
var anim_time: float = 0.0
# Бурление реки (Vfx "river_splash", только вид): раз в RIVER_SPLASH_EVERY с — на случайной клетке русла
const RIVER_SPLASH_EVERY: float = 0.7
var _splash_left: float = RIVER_SPLASH_EVERY
var _animated: bool = false
var _anim_step: int = 0
var _layout: Dictionary = {}

func setup(iso_grid: IsoGrid) -> void:
	grid = iso_grid
	theme = FactionTheme.current()
	_floor = Node2D.new()
	_floor.show_behind_parent = true
	_floor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # пиксель-арт без размытия
	_floor.draw.connect(_draw_floor)
	add_child(_floor)
	refresh_floor()

# Время анимированных плит — по часам, не по тикам боя (декор идёт и на паузе, и на расстановке)
func _process(delta: float) -> void:
	if not _floor:
		return
	_tick_river_splash(delta)
	if not _animated:
		return
	var step := int(Time.get_ticks_msec() * ANIM_REDRAW_FPS / 1000.0)
	if step != _anim_step:
		_anim_step = step
		anim_time = step / ANIM_REDRAW_FPS
		_floor.queue_redraw()

func _draw() -> void:
	if not grid or not grid_overlay:
		return
	_draw_kingdom()

# Подсветка клеток королевства: на расстановке — да, в бою — нет (BattleScene._on_start_pressed)
func set_grid_overlay(visible_overlay: bool) -> void:
	grid_overlay = visible_overlay
	queue_redraw()

func _tick_river_splash(delta: float) -> void:
	_splash_left -= delta
	if _splash_left > 0.0 or not _layout.has("rivers") or _layout["rivers"].is_empty():
		return
	_splash_left = RIVER_SPLASH_EVERY * randf_range(0.5, 1.5)
	var cells: Array = _layout["rivers"].keys()
	var c: Vector2i = cells[randi() % cells.size()]
	var jitter := Vector2(randf_range(-20.0, 20.0), randf_range(-8.0, 8.0))
	var v := Vfx.spawn(self, "river_splash", to_global(grid.lattice_to_screen(c.x, c.y) + jitter))
	if v:
		v.z_index = 0   # на воде, под бойцами (Vfx.spawn ставит поверх)

# Пол пересчитывается при изменении королевства (покупка клетки) или темы;
# между ними — только смена кадра анимированных плит
func refresh_floor() -> void:
	_layout.clear()
	_animated = _theme_has_frames()
	if _floor:
		_floor.queue_redraw()

func _theme_has_frames() -> bool:
	var lists: Array = []
	for key in ["floor", "kingdom", "enemy", "ground", "edge", "river"]:
		lists.append(theme.get(key, []))
	for f in theme.get("features", []):
		lists.append(f["tiles"])
	if theme.has("flags"):
		lists.append(theme["flags"]["tiles"])
	lists.append(theme.get("decorations", []))
	var lm: Dictionary = theme.get("landmarks", {})   # анимированные ориентиры: костры, знамёна
	lists.append(lm.get("banners", []) + ([lm["campfire"]] if lm.has("campfire") else []))
	for tiles in lists:
		for entry in tiles:
			if entry is Dictionary and entry.has("frames"):
				return true
	return false

# Время анимированной плиты клетки — общее со сдвигом по положению (волна)
func _cell_time(c: Vector2i) -> float:
	return anim_time + c.x * ANIM_WAVE.x + c.y * ANIM_WAVE.y

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
	TerrainTiles.draw_theme_tile(_floor, entry, top, FLOOR_TINT, art_axis != line_axis, _cell_time(c))

# Плита реки: вдоль русла чередуются плита и её отражение (FactionTheme: "mirror") — у плиты русло
# к одному концу шире, у отражения — к другому: стыки широкий к широкому и узкий к узкому.
# Плита одна на всю реку (по хэшу реки): у разных плит узкие концы русла в разных местах —
# на их стыке получалась грунтовая перемычка
func _draw_river_tile(c: Vector2i, top: Vector2, line_axis: String) -> void:
	var tile := river_tile_for(c, line_axis)
	TerrainTiles.draw_theme_tile(_floor, tile[0], top, FLOOR_TINT, tile[1], _cell_time(c))

# [плита темы, отразить ли по горизонтали] для клетки реки
func river_tile_for(c: Vector2i, line_axis: String) -> Array:
	var variants: Array = theme["river"]
	var k: int = c.y if line_axis == "v" else c.x        # номер клетки вдоль русла
	var across: int = c.x if line_axis == "v" else c.y   # какая это река
	var entry = variants[TerrainTiles.hash_cell(Vector2i(across, map_seed() % 1000), 71) % variants.size()]
	var art_axis: String = line_axis
	if entry is Dictionary:
		art_axis = entry.get("axis", line_axis)
		if posmod(k, 2) == 1 and entry.has("mirror"):
			entry = entry["mirror"]
	return [entry, art_axis != line_axis]

# Клетки реки: клетка → ось русла ("u" / "v"). Одна река вдоль поля (v постоянно, русло вдоль u)
# сверху или снизу от боевой полосы; ряды у цитадели (CITADEL_CLEAR) не берёт — там просто грунт
func _river_cells() -> Dictionary:
	var cells: Dictionary = {}
	if not theme.has("river"):
		return cells
	var rng = RandomNumberGenerator.new()
	rng.seed = hash([map_seed(), "rivers"])
	var lo = -FLOOR_PAD_TILES + 1
	var cols = grid.get_layout_cols()
	var rows = grid.get_layout_rows()
	var options: Array[int] = []
	for v in range(lo + 1, -1) + range(rows + 1, rows + FLOOR_PAD_TILES - 2):
		if absi(v - grid.citadel_tile.y) > CITADEL_CLEAR:
			options.append(v)
	if options.is_empty():
		return cells
	var row: int = options[rng.randi() % options.size()]
	for u in range(lo, cols + FLOOR_PAD_TILES - 1):
		cells[Vector2i(u, row)] = "u"
	for c in cells.keys():
		if grid.is_valid_tile(c) or c == grid.citadel_tile or _is_enemy_cell(c):
			cells.erase(c)
	return cells

# Естественная местность (тема: "ground" + "features"): клетка → [плитка, отражена ли].
# Основа — грунт (отражается по хэшу клетки, чтобы не было повторяющегося узора), поверх —
# редкие детали: группы {"clusters": N, "size": [от, до]} растут от случайной клетки в соседние,
# одиночные {"scatter": доля клеток}. Знамёна (тема: "flags") — count клеток на стороне игрока.
# Раскладка — от seed карты и не зависит от купленных клеток: рамка королевства в списке
# целиком (его клетки рисуются своей плиткой раньше), детали в неё не ставятся
func _terrain_cells(cells: Array[Vector2i], rivers: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if not theme.has("ground"):
		return result
	var free: Array[Vector2i] = []
	for c in cells:
		if not _is_floor_edge(c) and not rivers.has(c):
			free.append(c)
			result[c] = [TerrainTiles.pick_any(theme["ground"], c), TerrainTiles.hash_cell(c, 53) % 2 == 1]
	var spots = free.filter(func(c): return not grid.is_in_bounds(c) and not _near_citadel(c))
	var spot_set: Dictionary = {}
	for c in spots:
		spot_set[c] = true
	if spots.is_empty():
		return result
	var rng = RandomNumberGenerator.new()
	rng.seed = hash([map_seed(), "terrain"])
	var taken: Dictionary = {}
	for f in theme.get("features", []):
		if f.has("clusters"):
			var kind: Dictionary = {}   # клетки прошлых групп этой детали
			for i in f["clusters"]:
				var starts = spots.filter(func(c): return _cluster_cell_ok(c, f["tiles"], taken, kind))
				if starts.is_empty():
					break
				var cluster: Array[Vector2i] = [starts[rng.randi() % starts.size()]]
				var size = rng.randi_range(f["size"][0], f["size"][1])
				for attempt in CLUSTER_TRIES:
					if cluster.size() >= size:
						break
					var from: Vector2i = cluster[rng.randi() % cluster.size()]
					var next: Vector2i = from + NEIGHBOURS[rng.randi() % NEIGHBOURS.size()]
					if spot_set.has(next) and not cluster.has(next) and _cluster_cell_ok(next, f["tiles"], taken, kind):
						cluster.append(next)
				for c in cluster:
					_put_feature(result, taken, c, f["tiles"])
					kind[c] = true
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

# Высокие руины ("tall" — постройки выше бойца) — не в боевой полосе: там бойцы ходят перед ними
# и за ними, а пол рисуется под бойцами. В полосе — только низкие варианты (нет таких — клетка пуста)
func _put_feature(result: Dictionary, taken: Dictionary, c: Vector2i, tiles: Array) -> void:
	if taken.has(c):
		return
	tiles = _tiles_allowed_at(c, tiles)
	if tiles.is_empty():
		return
	taken[c] = true
	result[c] = [TerrainTiles.pick_any(tiles, c), false]

# Seed карты расы: одна и та же карта в каждом забеге
func map_seed() -> int:
	return int(theme.get("map_seed", DEFAULT_MAP_SEED))

# Плитки, допустимые на клетке: высокие — не в боевой полосе, знамёна — только на стороне игрока
func _tiles_allowed_at(c: Vector2i, tiles: Array) -> Array:
	var in_strip := _is_battle_strip(c)
	var player_side := _is_player_side(c)
	return tiles.filter(func(t): return not (t is Dictionary and (
		(in_strip and t.get("tall", false)) or (not player_side and t.get("flag", false)))))

# Клетка годится группе: свободна, плитка на ней допустима, не касается прошлых групп того же вида
func _cluster_cell_ok(c: Vector2i, tiles: Array, taken: Dictionary, kind: Dictionary) -> bool:
	if taken.has(c) or _tiles_allowed_at(c, tiles).is_empty():
		return false
	for d in NEIGHBOURS:
		if kind.has(c + d):
			return false
	return true

func _near_citadel(c: Vector2i) -> bool:
	var d := (c - grid.citadel_tile).abs()
	return maxi(d.x, d.y) <= CITADEL_CLEAR

# Сторона игрока — от королевства до середины ничьей земли
func _is_player_side(c: Vector2i) -> bool:
	return c.x < grid.grid_width + grid.gap_tiles / 2

# Внешнее кольцо пола — край карты (тема: "edge")
func _is_floor_edge(c: Vector2i) -> bool:
	return c.x == -FLOOR_PAD_TILES or c.y == -FLOOR_PAD_TILES \
		or c.x == grid.get_layout_cols() + FLOOR_PAD_TILES - 1 or c.y == grid.get_layout_rows() + FLOOR_PAD_TILES - 1

# Боевая полоса: королевство, ничья земля и зона врага — здесь только плоский декор
func _is_battle_strip(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < grid.get_layout_cols() and c.y >= 0 and c.y < grid.get_layout_rows()

func _draw_floor() -> void:
	if _layout.is_empty():
		var floor_cells = _floor_cells()
		var river_cells = _river_cells()
		var terrain_cells = _terrain_cells(floor_cells, river_cells)
		_layout = {"cells": floor_cells, "rivers": river_cells, "terrain": terrain_cells,
			"landmarks": _landmark_cells(floor_cells, river_cells, terrain_cells)}
	var cells: Array[Vector2i] = _layout["cells"]
	var rivers: Dictionary = _layout["rivers"]
	var terrain: Dictionary = _layout["terrain"]
	for c in cells:
		var top = grid.lattice_to_screen(c.x, c.y)
		if grid.is_valid_tile(c):
			TerrainTiles.draw_theme_tile(_floor, TerrainTiles.pick_any(theme["kingdom"], c), top, Color.WHITE, false, _cell_time(c))
		elif _is_floor_edge(c) and theme.has("edge"):
			# Края с постоянным u идут вдоль оси v, с постоянным v — вдоль u
			var along_v = c.x == -FLOOR_PAD_TILES or c.x == grid.get_layout_cols() + FLOOR_PAD_TILES - 1
			_draw_line_tile(theme["edge"], c, top, "v" if along_v else "u")
		elif rivers.has(c):
			_draw_river_tile(c, top, rivers[c])
		elif terrain.has(c):
			TerrainTiles.draw_theme_tile(_floor, terrain[c][0], top, FLOOR_TINT, terrain[c][1], _cell_time(c))
		elif _is_enemy_cell(c):
			TerrainTiles.draw_theme_tile(_floor, TerrainTiles.pick_any(theme["enemy"], c), top, FLOOR_TINT, false, _cell_time(c))
		else:
			TerrainTiles.draw_theme_tile(_floor, TerrainTiles.pick_any(theme["floor"], c), top, FLOOR_TINT, false, _cell_time(c))
		_draw_cell_decoration(c, top, rivers, terrain)

# Ориентиры темы ("landmarks": {"campfire", "banners", "random_banners", "war_banners", "war_banner_count"},
# все ключи необязательны): клетка → объект.
# Костёр у базы — ближайшая к цитадели свободная клетка за её кольцом (из равных — перед крепостью); костёр за рекой — на дальнем от
# боевой полосы берегу, ближе к середине русла; знамя — рядом с костром у базы, ещё random_banners — в
# случайных свободных клетках на стороне игрока вне боевой полосы. Карта одна — от seed карты
const WAR_BANNER_GAP: int = 3   # большие знамёна — не ближе (клеток по Чебышёву) к другим ориентирам

func _landmark_cells(cells: Array[Vector2i], rivers: Dictionary, terrain: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if not theme.has("landmarks"):
		return out
	var lm: Dictionary = theme["landmarks"]
	var all: Dictionary = {}
	for c in cells:
		all[c] = true
	var free = func(c: Vector2i) -> bool:
		return all.has(c) and not out.has(c) and not grid.is_in_bounds(c) and not _near_citadel(c) \
			and not rivers.has(c) and not _is_floor_edge(c) and not _is_enemy_cell(c) \
			and not (terrain.has(c) and terrain[c][0] is Dictionary and (terrain[c][0].has("prop") \
				or terrain[c][0].get("no_decor", false) or terrain[c][0].get("flag", false)))
	# Костёр у базы
	var base_fire := Vector2i(-999, -999)
	var by_dist = cells.filter(free)
	by_dist.sort_custom(func(a, b): return _cheb(a - grid.citadel_tile) < _cheb(b - grid.citadel_tile) \
		or (_cheb(a - grid.citadel_tile) == _cheb(b - grid.citadel_tile) and (a.x + a.y > b.x + b.y 			or (a.x + a.y == b.x + b.y and a < b))))   # из равных — ближе к зрителю: не за крепостью и её HP
	if not by_dist.is_empty() and lm.has("campfire"):
		base_fire = by_dist[0]
		out[base_fire] = lm["campfire"]
	# Костёр за рекой: ряд по ту сторону русла от боевой полосы, ближе к середине
	if not rivers.is_empty() and lm.has("campfire"):
		var row: int = rivers.keys()[0].y
		var far: int = row - 1 if row < 0 else row + 1
		var us: Array = rivers.keys().map(func(c): return c.x)
		var mid: int = (us.min() + us.max()) / 2
		var shore = cells.filter(func(c): return c.y == far and free.call(c))
		shore.sort_custom(func(a, b): return absi(a.x - mid) < absi(b.x - mid))
		if not shore.is_empty():
			out[shore[0]] = lm["campfire"]
	var banners: Array = lm.get("banners", [])
	# Знамя у костра у базы
	if out.has(base_fire) and not banners.is_empty():
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			if free.call(base_fire + d):
				out[base_fire + d] = banners[0]
				break
	# Знамёна в случайных местах
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([map_seed(), "banners"])
	var spots = cells.filter(func(c): return _is_player_side(c) and not _is_battle_strip(c) and free.call(c))
	for i in mini(lm.get("random_banners", 0) if not banners.is_empty() else 0, spots.size()):
		out[spots.pop_at(rng.randi() % spots.size())] = banners[(i + 1) % banners.size()]
	# Большие знамёна (UI_assets.png) — порознь: не ближе WAR_BANNER_GAP к другим ориентирам
	var war: Array = lm.get("war_banners", [])
	rng.seed = hash([map_seed(), "war_banners"])
	for i in lm.get("war_banner_count", 0) if not war.is_empty() else 0:
		var apart = spots.filter(func(c): return free.call(c) and out.keys().all(func(o): return _cheb(o - c) >= WAR_BANNER_GAP))
		if apart.is_empty():
			break
		out[apart[rng.randi() % apart.size()]] = war[i % war.size()]
	return out

func _cheb(d: Vector2i) -> int:
	return maxi(absi(d.x), absi(d.y))

# Декор — на своей клетке сразу после её плиты (передние клетки перекрывают задний декор)
func _draw_cell_decoration(c: Vector2i, top: Vector2, rivers: Dictionary, terrain: Dictionary) -> void:
	if _layout.get("landmarks", {}).has(c):
		TerrainTiles.draw_prop(_floor, _layout["landmarks"][c], top, FLOOR_TINT, false, _cell_time(c))
		return
	var deco = decoration_for(c, rivers, terrain)
	if deco == null:
		return
	var jitter = Vector2((TerrainTiles.hash_cell(c, 21) % 41) - 20, (TerrainTiles.hash_cell(c, 29) % 17) - 8)
	TerrainTiles.draw_prop(_floor, deco, top + jitter, FLOOR_TINT, TerrainTiles.hash_cell(c, 37) % 2 == 1, _cell_time(c))

# Декор клетки (объект темы {"texture", "base", "scale", "flat", "flag"}) или null. Нет декора:
# королевство, цитадель и клетки вокруг, реки, край поля, руины, туман и большие кратеры ("no_decor").
# В боевой полосе — только плоский; знамёна — только на стороне игрока и реже прочего
func decoration_for(c: Vector2i, rivers: Dictionary, terrain: Dictionary) -> Variant:
	if grid.is_in_bounds(c) or _near_citadel(c) or rivers.has(c) or _is_floor_edge(c):
		return null
	if terrain.has(c) and terrain[c][0] is Dictionary:
		var tile: Dictionary = terrain[c][0]
		if tile.has("prop") or tile.get("no_decor", false):
			return null
	var in_strip = _is_battle_strip(c)
	if TerrainTiles.hash_cell(c, 7) % 100 >= (DECOR_FLAT_CHANCE if in_strip else DECOR_CHANCE):
		return null
	var flag_ok := _is_player_side(c) and TerrainTiles.hash_cell(c, 41) % FLAG_DECOR_RARITY == 0
	var options = theme.get("decorations", []).filter(func(d):
		return (d.get("flat", false) or not in_strip) and (flag_ok or not d.get("flag", false)))
	if options.is_empty():
		return null
	return options[TerrainTiles.hash_cell(c, 13) % options.size()]

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
