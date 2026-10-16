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

static var _cache: Dictionary = {}

static func tile(n: int) -> Texture2D:
	return _load(DIR + "Tiles/Slice %d.png" % n)

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

# Плитка темы расы: int — блок тайлсета, String — картинка ромба клетки целиком,
# {"texture": путь, "top": px} — то же, но над ромбом торчит что-то высотой top px картинки.
# flip — отразить по горизонтали (русло / стена вдоль другой оси клеток);
# {"frames": [плитки], "fps"} — анимированная плита: на время time (с) кадр по кругу, следующий
# кадр проступает поверх по мере приближения (туман густеет плавно, а не мигает);
# "prop": объект — поверх плиты стоит объект (руины, draw_prop) основанием в центре клетки
static func draw_theme_tile(canvas: CanvasItem, entry, top_center: Vector2, modulate: Color = Color.WHITE,
		flip: bool = false, time: float = 0.0) -> void:
	if entry is Dictionary and entry.has("frames"):
		var frames: Array = entry["frames"]
		var phase: float = time * entry.get("fps", 1.0)
		var i := int(floor(phase))
		draw_theme_tile(canvas, frames[posmod(i, frames.size())], top_center, modulate, flip)
		var blend := phase - i
		if blend > 0.0:
			var next_modulate := modulate
			next_modulate.a *= blend
			draw_theme_tile(canvas, frames[posmod(i + 1, frames.size())], top_center, next_modulate, flip)
		return
	if entry is String:
		draw_tile_texture(canvas, FactionTheme.load_texture(entry), top_center, modulate, 0.0, flip)
	elif entry is Dictionary:
		draw_tile_texture(canvas, FactionTheme.load_texture(entry["texture"]), top_center, modulate,
			entry.get("top", 0.0), flip)
		if entry.has("prop"):
			draw_prop(canvas, entry["prop"], top_center, modulate, flip)
	else:
		draw_block(canvas, tile(int(entry)), top_center, modulate)

# Картинка клетки целиком: ширина = ширина клетки, ромб верхней грани (2:1) —
# в верхней части картинки (верхний угол — на top_px от верха), его центр — в top_center
static func draw_tile_texture(canvas: CanvasItem, tex: Texture2D, top_center: Vector2, modulate: Color = Color.WHITE,
		top_px: float = 0.0, flip: bool = false) -> void:
	if tex == null:
		return
	var k: float = float(IsoGrid.TILE_WIDTH) / tex.get_width()   # не целочисленно: PNG любой ширины
	var size = tex.get_size() * k
	# Ромб симметричен относительно вертикали через top_center — отражение вокруг неё
	canvas.draw_set_transform(top_center, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	canvas.draw_texture_rect(tex, Rect2(-Vector2(size.x / 2.0, IsoGrid.TILE_HEIGHT / 2.0 + top_px * k), size),
		false, modulate)
	canvas.draw_set_transform(Vector2.ZERO)

# Вариант для клетки (int или String) — как pick, но без приведения к int
static func pick_any(variants: Array, cell: Vector2i, salt: int = 0) -> Variant:
	return variants[hash_cell(cell, salt) % variants.size()]

# Объект темы {"texture": путь, "base": точка земли в картинке (px), "scale", "tint"} — основанием в точке foot
# (руины на клетке, декор, tools/props_from_sheet.py); flip — отразить по горизонтали
static func draw_prop(canvas: CanvasItem, prop: Dictionary, foot: Vector2, modulate: Color = Color.WHITE,
		flip: bool = false) -> void:
	var tex := FactionTheme.load_texture(prop["texture"])
	if tex == null:
		return
	var k: float = prop.get("scale", 1.0)
	var base: Vector2 = prop.get("base", Vector2(tex.get_width() / 2.0, tex.get_height()))
	canvas.draw_set_transform(foot, 0.0, Vector2(-k if flip else k, k))
	canvas.draw_texture_rect(tex, Rect2(-base, tex.get_size()), false, modulate * prop.get("tint", Color.WHITE))
	canvas.draw_set_transform(Vector2.ZERO)
