class_name TerrainTiles
extends RefCounted

# Пиксельный изометрический тайлсет луны (assets/sprites/map_sprite, 32×32).
# Верхняя грань куба — ромб 30×15 px с центром в (16, 7.5), боковая грань — 16 px.
# Масштабируем так, чтобы ромб совпал с тайлом сетки (IsoGrid.TILE_WIDTH × TILE_HEIGHT).

const DIR = "res://assets/sprites/map_sprite/"
const TOP_WIDTH_PX: float = 30.0
const TOP_CENTER_PX = Vector2(16.0, 7.5)
const SIDE_HEIGHT_PX: float = 16.0
const SPRITE_PX = Vector2(32, 32)
const SCALE: float = IsoGrid.TILE_WIDTH / TOP_WIDTH_PX

# Высота одного «этажа» блока на экране — для зданий из нескольких блоков
const LEVEL_HEIGHT: float = SIDE_HEIGHT_PX * SCALE

# Номера Tiles/Slice N.png по назначению
const FLOOR = [36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 10, 4]  # пол: в основном тёмный, изредка светлый и с кратерами
const KINGDOM = [16, 17, 18, 19, 20, 21, 22, 23, 24, 25] # плиты королевства: техно-панели
const ENEMY = [43, 44, 45, 46, 47]                     # зона врага: тёмные панели

# Декор пола: имя файла, плоский ли (плоский можно класть на «ничью землю» — не мешает виду боя)
const DECORATIONS = [
	["Small_rocks_1", false], ["Small_rocks_2", false], ["Small_rocks_3", false],
	["Medium_rocks_1", false], ["Medium_rocks_2", false], ["Medium_rocks_3", false],
	["Medium_rocks_4", false], ["Medium_rocks_5", false], ["Medium_rocks_6", false],
	["Big_rocks_1", false], ["Spike_rock_1", false], ["Spike_rock_2", false],
	["Small_Crater_hit_1", true], ["Small_Crater_hit_2", true], ["Big_Crater_hit_1", true],
	["small_asteroid_impact_1", true], ["small_asteroid_impact_2", true],
	["medium_asteroid_impact_1", true], ["Big_asteroid_impact_1", true], ["Big_asteroid_impact_2", true],
]

static var _cache: Dictionary = {}

static func tile(n: int) -> Texture2D:
	return _load(DIR + "Tiles/Slice %d.png" % n)

static func decoration(file_name: String) -> Texture2D:
	return _load(DIR + "Decorations_tiles/%s.png" % file_name)

static func _load(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]

# Детерминированный выбор варианта по клетке — пол не «мигает» между перерисовками
static func pick(variants: Array, cell: Vector2i, salt: int = 0) -> int:
	return variants[hash_cell(cell, salt) % variants.size()]

static func hash_cell(cell: Vector2i, salt: int = 0) -> int:
	return absi((cell.x * 73856093) ^ (cell.y * 19349663) ^ (salt * 83492791))

# Блок, верхняя грань которого центрирована в top_center.
# scale_mult < 1 — мелкие блоки (цитадель собрана из блоков в полклетки)
static func draw_block(canvas: CanvasItem, tex: Texture2D, top_center: Vector2, modulate: Color = Color.WHITE, scale_mult: float = 1.0) -> void:
	if tex == null:
		return
	canvas.draw_texture_rect(tex, block_rect(top_center, scale_mult), false, modulate)

# Прямоугольник, который занимает на экране блок draw_block (для проверки перекрытия)
static func block_rect(top_center: Vector2, scale_mult: float = 1.0) -> Rect2:
	var s = SCALE * scale_mult
	return Rect2(top_center - TOP_CENTER_PX * s, SPRITE_PX * s)

# Плитка темы расы: int — блок тайлсета, String — картинка ромба клетки целиком
static func draw_theme_tile(canvas: CanvasItem, entry, top_center: Vector2, modulate: Color = Color.WHITE) -> void:
	if entry is String:
		draw_tile_texture(canvas, FactionTheme.load_texture(entry), top_center, modulate)
	else:
		draw_block(canvas, tile(int(entry)), top_center, modulate)

# Картинка клетки целиком: ширина = ширина клетки, ромб верхней грани (2:1) —
# в верхней части картинки, его центр — в top_center
static func draw_tile_texture(canvas: CanvasItem, tex: Texture2D, top_center: Vector2, modulate: Color = Color.WHITE) -> void:
	if tex == null:
		return
	var k: float = float(IsoGrid.TILE_WIDTH) / tex.get_width()   # не целочисленно: PNG любой ширины
	var size = tex.get_size() * k
	canvas.draw_texture_rect(tex, Rect2(top_center - Vector2(size.x / 2.0, IsoGrid.TILE_HEIGHT / 2.0), size), false, modulate)

# Вариант для клетки (int или String) — как pick, но без приведения к int
static func pick_any(variants: Array, cell: Vector2i, salt: int = 0) -> Variant:
	return variants[hash_cell(cell, salt) % variants.size()]

# Декор стоит «ногами» (низом спрайта) в точке foot
static func draw_decoration(canvas: CanvasItem, tex: Texture2D, foot: Vector2) -> void:
	if tex == null:
		return
	var size = tex.get_size() * SCALE
	canvas.draw_texture_rect(tex, Rect2(foot - Vector2(size.x / 2.0, size.y * 0.75), size), false)
