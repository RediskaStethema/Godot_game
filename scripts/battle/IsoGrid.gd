class_name IsoGrid
extends RefCounted

# Размер одного тайла в пикселях
# 2:1 соотношение — стандарт для изометрии
const TILE_WIDTH: int = 128
const TILE_HEIGHT: int = 64

# Размер королевства игрока (будет расти с этапами).
# Зона врага такого же размера (её тайлы не рисуются — это места построения).
var grid_width: int = 3
var grid_height: int = 3
# Origin = центр тайла (0,0) каждой сетки на экране
var player_origin: Vector2   # королевство — сверху слева
var enemy_origin: Vector2    # зона врага — снизу справа, на той же диагонали

# Раскладка как в 9 Kings: одно общее поле, королевство и зона врага лежат
# на одной изометрической оси (ось col, экранное направление (2, 1)).
# Между ними — «ничья земля» в gap_tiles тайлов, где сходятся армии.
const DEFAULT_GAP_TILES: int = 3
const MIN_GAP_TILES: int = 1
var gap_tiles: int = DEFAULT_GAP_TILES

# play_area — свободная от UI область экрана. Пустая = весь экран.
# Вся раскладка (королевство + ничья земля + зона врага) центрируется в ней.
func setup(screen_size: Vector2, play_area: Rect2 = Rect2()) -> void:
	if play_area.size == Vector2.ZERO:
		play_area = Rect2(Vector2.ZERO, screen_size)

	# Большие сетки по высоте не влезают — сокращаем ничью землю
	gap_tiles = DEFAULT_GAP_TILES
	while gap_tiles > MIN_GAP_TILES and get_layout_size().y > play_area.size.y:
		gap_tiles -= 1

	var size = get_layout_size()
	var top_left = play_area.position + (play_area.size - size) / 2.0
	# Левый верхний угол рамки раскладки относительно player_origin
	player_origin = top_left - Vector2(-grid_height * TILE_WIDTH / 2.0, -TILE_HEIGHT / 2.0)
	enemy_origin = player_origin + get_enemy_shift()

	if size.x > play_area.size.x or size.y > play_area.size.y:
		push_warning("IsoGrid: раскладка %dx%d (%s px) не влезает в игровую область %s" \
			% [grid_width, grid_height, size, play_area.size])

# Сдвиг зоны врага от королевства — вдоль оси col (направление наступления)
func get_enemy_shift() -> Vector2:
	return (grid_width + gap_tiles) * Vector2(TILE_WIDTH / 2.0, TILE_HEIGHT / 2.0)

# Размер рамки всей раскладки: от левого угла королевства до правого угла зоны врага
func get_layout_size() -> Vector2:
	return Vector2(
		(grid_height + 2 * grid_width + gap_tiles) * TILE_WIDTH / 2.0,
		(grid_height + 2 * grid_width + gap_tiles) * TILE_HEIGHT / 2.0
	)

# Экранная точка по дробным тайловым координатам относительно королевства.
# Нужна для рисования общего поля: (u, v) = (col, row), центр тайла — целые числа.
func lattice_to_screen(u: float, v: float) -> Vector2:
	return player_origin + Vector2((u - v) * TILE_WIDTH / 2.0, (u + v) * TILE_HEIGHT / 2.0)

# Направление наступления армии игрока на экране (единичный вектор)
static func advance_direction() -> Vector2:
	return Vector2(TILE_WIDTH, TILE_HEIGHT).normalized()

# Ось шеренги — перпендикулярно наступлению в изометрии (ось row)
static func rank_direction() -> Vector2:
	return Vector2(-TILE_WIDTH, TILE_HEIGHT).normalized()

# Размер ромба всей сетки в пикселях
func get_grid_pixel_size() -> Vector2:
	return Vector2(
		(grid_width + grid_height) * TILE_WIDTH / 2.0,
		(grid_width + grid_height) * TILE_HEIGHT / 2.0
	)

# Ограничивающий прямоугольник сетки на экране (для проверок и UI)
func get_grid_rect(is_enemy: bool = false) -> Rect2:
	var origin = enemy_origin if is_enemy else player_origin
	var top_left = origin + Vector2(-grid_height * TILE_WIDTH / 2.0, -TILE_HEIGHT / 2.0)
	return Rect2(top_left, get_grid_pixel_size())

# tile = (col, row) в сетке
func tile_to_screen(tile: Vector2i, is_enemy: bool = false) -> Vector2:
	var origin = enemy_origin if is_enemy else player_origin
	var x = (tile.x - tile.y) * (TILE_WIDTH / 2)
	var y = (tile.x + tile.y) * (TILE_HEIGHT / 2)
	return origin + Vector2(x, y)

# Из экранных пикселей в тайловые координаты
func screen_to_tile(screen: Vector2, is_enemy: bool = false) -> Vector2i:
	var origin = enemy_origin if is_enemy else player_origin
	var local = screen - origin
	var col = (local.x / (TILE_WIDTH / 2) + local.y / (TILE_HEIGHT / 2)) / 2
	var row = (local.y / (TILE_HEIGHT / 2) - local.x / (TILE_WIDTH / 2)) / 2
	# tile_to_screen даёт ЦЕНТР тайла, поэтому округляем, а не отбрасываем дробь
	return Vector2i(roundi(col), roundi(row))

# -------------------------------------------------------
# УТИЛИТЫ
# -------------------------------------------------------

# Проверяет что тайл находится в пределах сетки
func is_valid_tile(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < grid_width and \
		   tile.y >= 0 and tile.y < grid_height

# Возвращает все тайлы сетки по порядку
func get_all_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for row in range(grid_height):
		for col in range(grid_width):
			tiles.append(Vector2i(col, row))
	return tiles

# Тайлы зоны врага от переднего края (col = 0, ближе к игроку) к тылу —
# враги сначала занимают фронт
func get_enemy_tiles_front_first() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for col in range(grid_width):
		for row in range(grid_height):
			tiles.append(Vector2i(col, row))
	return tiles

# Расстояние между двумя тайлами (для AI)
func tile_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

# Увеличиваем сетку с этапом
func expand_grid(stage: int) -> void:
	match stage:
		1: grid_width = 3; grid_height = 3   # 9 клеток — старт
		2: grid_width = 4; grid_height = 3   # 12 клеток
		3: grid_width = 4; grid_height = 4   # 16 клеток
		_: grid_width = 3; grid_height = 3   # дефолт
