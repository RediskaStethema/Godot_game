class_name IsoGridRenderer
extends Node2D

# Рисует поле боя в духе 9 Kings: одна общая платформа с мелкой изометрической
# сеткой, на ней — плоты королевства игрока. Зона врага тайлами не рисуется
# (враги просто стоят на полу), только едва заметная подсветка.

var grid: IsoGrid

# --- Плоты королевства ---
const COLOR_NORMAL   = Color(0.30, 0.40, 0.58, 0.22)   # сталь
const COLOR_HOVER    = Color(0.94, 0.83, 0.55, 0.45)   # светлое золото
const COLOR_OCCUPIED = Color(0.79, 0.63, 0.29, 0.30)   # золото
const LINE_PLAYER    = Color(0.79, 0.63, 0.29, 0.45)
const BORDER_PLAYER  = Color(0.79, 0.63, 0.29, 0.95)
# --- Зона врага ---
const COLOR_ENEMY    = Color(0.56, 0.15, 0.13, 0.07)
const BORDER_ENEMY   = Color(0.78, 0.27, 0.23, 0.30)

# --- Платформа ---
const FLOOR_COLOR      = Color("2a2520")
const FLOOR_PATCH      = Color("221e1a")
const FLOOR_LINE       = Color(0.79, 0.63, 0.29, 0.05)   # мелкая сетка (1/4 тайла)
const FLOOR_LINE_MAJOR = Color(0.79, 0.63, 0.29, 0.10)   # границы тайлов
const FACE_LEFT        = Color("1d1915")
const FACE_RIGHT       = Color("14110e")
const FLOOR_PAD_TILES: float = 3.0     # поле шире раскладки на столько тайлов
const FLOOR_SUBDIV: int = 4             # клеток мелкой сетки на тайл
const PLATFORM_DEPTH: float = 40.0      # высота торца платформы, px
const PATCH_CHANCE: int = 7             # % клеток-«плит» потемнее

var hovered_tile: Vector2i = Vector2i(-1, -1)
var occupied_tiles_player: Dictionary = {}
var occupied_tiles_enemy: Dictionary = {}

var _floor: Node2D = null   # пол рисуется один раз, отдельно от подсветки плотов

func setup(iso_grid: IsoGrid) -> void:
	grid = iso_grid
	_floor = Node2D.new()
	_floor.show_behind_parent = true
	_floor.draw.connect(_draw_floor)
	add_child(_floor)

func _draw() -> void:
	if not grid:
		return
	_draw_enemy_zone()
	_draw_kingdom()

# -------------------------------------------------------
# ПЛАТФОРМА
# -------------------------------------------------------
# Границы поля в тайловых координатах королевства (углы тайлов — на ±0.5)
func _floor_bounds() -> Rect2:
	var u0 = -0.5 - FLOOR_PAD_TILES
	var v0 = -0.5 - FLOOR_PAD_TILES
	var u1 = grid.grid_width * 2 + grid.gap_tiles - 0.5 + FLOOR_PAD_TILES
	var v1 = grid.grid_height - 0.5 + FLOOR_PAD_TILES
	return Rect2(u0, v0, u1 - u0, v1 - v0)

func _draw_floor() -> void:
	var b = _floor_bounds()
	var u0 = b.position.x; var v0 = b.position.y
	var u1 = b.end.x; var v1 = b.end.y
	var p00 = grid.lattice_to_screen(u0, v0)
	var p10 = grid.lattice_to_screen(u1, v0)
	var p11 = grid.lattice_to_screen(u1, v1)
	var p01 = grid.lattice_to_screen(u0, v1)
	var down = Vector2(0, PLATFORM_DEPTH)

	# Торцы платформы (видны две нижние грани)
	_floor.draw_colored_polygon(PackedVector2Array([p01, p11, p11 + down, p01 + down]), FACE_LEFT)
	_floor.draw_colored_polygon(PackedVector2Array([p11, p10, p10 + down, p11 + down]), FACE_RIGHT)
	# Пол
	_floor.draw_colored_polygon(PackedVector2Array([p00, p10, p11, p01]), FLOOR_COLOR)

	# «Плиты» — детерминированно разбросанные тёмные клетки
	var step = 1.0 / FLOOR_SUBDIV
	var cells_u = int(round(b.size.x * FLOOR_SUBDIV))
	var cells_v = int(round(b.size.y * FLOOR_SUBDIV))
	for i in cells_u:
		for j in cells_v:
			if _hash(i, j) % 100 >= PATCH_CHANCE:
				continue
			var cu = u0 + i * step
			var cv = v0 + j * step
			_floor.draw_colored_polygon(PackedVector2Array([
				grid.lattice_to_screen(cu, cv),
				grid.lattice_to_screen(cu + step, cv),
				grid.lattice_to_screen(cu + step, cv + step),
				grid.lattice_to_screen(cu, cv + step),
			]), FLOOR_PATCH)

	# Мелкая сетка; каждая FLOOR_SUBDIV-я линия (граница тайла) — ярче
	for i in cells_u + 1:
		var u = u0 + i * step
		var c = FLOOR_LINE_MAJOR if i % FLOOR_SUBDIV == 0 else FLOOR_LINE
		_floor.draw_line(grid.lattice_to_screen(u, v0), grid.lattice_to_screen(u, v1), c, 1.0)
	for j in cells_v + 1:
		var v = v0 + j * step
		var c = FLOOR_LINE_MAJOR if j % FLOOR_SUBDIV == 0 else FLOOR_LINE
		_floor.draw_line(grid.lattice_to_screen(u0, v), grid.lattice_to_screen(u1, v), c, 1.0)

	# Кромка платформы
	_floor.draw_polyline(PackedVector2Array([p00, p10, p11, p01, p00]), Color(0.79, 0.63, 0.29, 0.25), 2.0, true)

func _hash(i: int, j: int) -> int:
	var h = (i * 73856093) ^ (j * 19349663)
	return absi(h)

# -------------------------------------------------------
# КОРОЛЕВСТВО И ЗОНА ВРАГА
# -------------------------------------------------------
func _draw_kingdom() -> void:
	for tile in grid.get_all_tiles():
		var color = COLOR_NORMAL
		if tile == hovered_tile:
			color = COLOR_HOVER
		elif occupied_tiles_player.has(tile):
			color = COLOR_OCCUPIED
		_draw_diamond(grid.tile_to_screen(tile, false), color, LINE_PLAYER)
	_draw_border(false, BORDER_PLAYER, 3.0)

func _draw_enemy_zone() -> void:
	var pts = _border_points(true)
	draw_colored_polygon(pts, COLOR_ENEMY)
	pts.append(pts[0])
	draw_polyline(pts, BORDER_ENEMY, 2.0, true)

func _border_points(is_enemy: bool) -> PackedVector2Array:
	var hw = IsoGrid.TILE_WIDTH / 2.0
	var hh = IsoGrid.TILE_HEIGHT / 2.0
	var w = grid.grid_width - 1
	var h = grid.grid_height - 1
	return PackedVector2Array([
		grid.tile_to_screen(Vector2i(0, 0), is_enemy) + Vector2(0, -hh),
		grid.tile_to_screen(Vector2i(w, 0), is_enemy) + Vector2(hw, 0),
		grid.tile_to_screen(Vector2i(w, h), is_enemy) + Vector2(0, hh),
		grid.tile_to_screen(Vector2i(0, h), is_enemy) + Vector2(-hw, 0),
	])

# Толстый контур всей сетки — по крайним углам угловых тайлов
func _draw_border(is_enemy: bool, color: Color, width: float) -> void:
	var pts = _border_points(is_enemy)
	pts.append(pts[0])
	draw_polyline(pts, color, width, true)

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
