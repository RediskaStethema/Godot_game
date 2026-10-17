class_name Vfx
extends AnimatedSprite2D

# Визуальные эффекты боя из листов assets/Spritesheets (кадры сеткой: слева направо, сверху вниз).
# Только вид: на бой не влияют, живут своей анимацией (на паузе стоят, скорость ×2 ускоряет).
# Разовый эффект (loop = false) удаляет себя сам; постоянный (статус, оглушение) снимает владелец.
#   spawn(parent, вид, точка)  — разовый эффект в мировой точке (попадание, взрыв)
#   attach(боец, вид)          — на бойце: ставится к ногам, двигается вместе с ним

const SHEETS_DIR = "res://assets/Spritesheets/"
const PIXEL_DIR = "res://assets/effects/Pixel/PNG_native/"   # пак Pixel: sheet — полный путь
# sheet — файл листа, size — кадр, frames — кадров (пустые хвосты листа не берём), fps, loop,
# scale — масштаб на бойце роста 62 px, pivot — точка кадра, которая встаёт в позицию эффекта
# (у эффектов на бойце — ноги), behind — рисовать за спрайтом бойца
const EFFECTS = {
	# удар в ближнем бою и попадание снаряда в бойца (Projectile)
	"blood":      {"sheet": "Blood Splat.png", "size": Vector2i(96, 96), "frames": 7, "fps": 16.0,
		"loop": false, "scale": 1.2, "pivot": Vector2(50, 46)},
	# лужа крови под павшим
	"splatter":   {"sheet": "Splatter-Sheet.png", "size": Vector2i(150, 150), "frames": 30, "fps": 30.0,
		"loop": false, "scale": 0.45, "pivot": Vector2(85, 140), "behind": true},
	# обломки взрыва залпа Thunderfire
	"impact":     {"sheet": "Spark1-Sheet.png", "size": Vector2i(150, 150), "frames": 30, "fps": 33.0,
		"loop": false, "scale": 0.4, "pivot": Vector2(72, 140)},
	# дым взрыва Thunderfire Cannon — масштаб по радиусу взрыва
	"explosion":  {"sheet": "Smoke-Sheet.png", "size": Vector2i(80, 80), "frames": 19, "fps": 18.0,
		"loop": false, "scale": 1.0, "pivot": Vector2(38, 78)},
	# взрыв залпа Thunderfire: огненный шар (+ "explosion" и "impact" — дым и обломки)
	"fireball":   {"sheet": "Fire+Sparks-Sheet.png", "size": Vector2i(96, 96), "frames": 19, "fps": 22.0,
		"loop": false, "scale": 0.9, "pivot": Vector2(52, 92)},
	# вспышка выстрела орудия — поджиг ракеты (первые кадры листа ракеты)
	"muzzle_flash": {"sheet": "Rocket Fire 2-Sheet.png", "size": Vector2i(150, 150), "frames": 5,
		"fps": 20.0, "loop": false, "scale": 1.0, "pivot": Vector2(68, 78)},
	# дым из ствола орудия
	"muzzle_smoke": {"sheet": "Smoke2-Sheet.png", "size": Vector2i(150, 150), "frames": 40, "fps": 40.0,
		"loop": false, "scale": 0.5, "pivot": Vector2(80, 148)},
	# поджог при попадании (Havoc, Salamanders) — язык пламени по направлению удара
	"flame_burst": {"sheet": "Flamethrower-Sheet.png", "size": Vector2i(96, 48), "frames": 10, "fps": 24.0,
		"loop": false, "scale": 0.9, "pivot": Vector2(30, 24)},
	# бурление ядовитой реки (IsoGridRenderer, только вид) — голубой лист, перекрашен в зелёный
	"river_splash": {"sheet": "Water Vortex Splash-Sheet.png", "size": Vector2i(150, 150), "frames": 30,
		"fps": 20.0, "loop": false, "scale": 0.5, "pivot": Vector2(75, 75), "flat": true,
		"modulate": Color(0.55, 1.0, 0.35, 0.85)},
	# --- Пак Pixel (assets/effects/Pixel, листы PNG_native: кадры 32×32 в ряд; решение пользователя 17.10.2026) ---
	# масштаб — на бойце роста 62 px (как у остальных); pivot за пределами кадра — эффект над головой
	# попадание снаряда в цитадель
	"hit_spark":  {"sheet": PIXEL_DIR + "combat/hit_side.png", "size": Vector2i(32, 32), "frames": 8, "fps": 12.0,
		"loop": false, "scale": 1.2, "pivot": Vector2(16, 16)},
	# росчерк удара в ближнем бою (поверх крови), по направлению удара
	"slash":      {"sheet": PIXEL_DIR + "combat/slash.png", "size": Vector2i(32, 32), "frames": 8, "fps": 16.0,
		"loop": false, "scale": 1.2, "pivot": Vector2(16, 16)},
	# отбрасывание (удар Dreadnought / Hellbrute) — удар о землю у ног
	"ground_slam": {"sheet": PIXEL_DIR + "combat/ground_slam_side.png", "size": Vector2i(32, 32), "frames": 12,
		"fps": 16.0, "loop": false, "scale": 1.6, "pivot": Vector2(16, 27)},
	# взрыв снаряда цитадели — масштаб по радиусу взрыва (как "explosion")
	"citadel_blast": {"sheet": PIXEL_DIR + "combat/explosion_side.png", "size": Vector2i(32, 32), "frames": 12,
		"fps": 16.0, "loop": false, "scale": 0.9, "pivot": Vector2(16, 27)},
	# попадание Librarian (оглушает) — молния в цель
	"lightning":  {"sheet": PIXEL_DIR + "magic/lightning_side.png", "size": Vector2i(32, 32), "frames": 12,
		"fps": 16.0, "loop": false, "scale": 1.4, "pivot": Vector2(16, 17)},
	# каст Librarian — вспышка вокруг бойца
	"cast":       {"sheet": PIXEL_DIR + "magic/magic_burst.png", "size": Vector2i(32, 32), "frames": 8, "fps": 12.0,
		"loop": true, "scale": 1.6, "pivot": Vector2(16, 35)},
	# лечение (Apothecary, лечение картой)
	"heal":       {"sheet": PIXEL_DIR + "magic/heal_side.png", "size": Vector2i(32, 32), "frames": 12, "fps": 12.0,
		"loop": false, "scale": 1.4, "pivot": Vector2(16, 37)},
	# щит Iron Halo на бойце в начале боя; щит цитадели от стен — большой
	"shield":     {"sheet": PIXEL_DIR + "magic/shield.png", "size": Vector2i(32, 32), "frames": 12, "fps": 12.0,
		"loop": false, "scale": 1.5, "pivot": Vector2(16, 37)},
	"citadel_shield": {"sheet": PIXEL_DIR + "magic/shield.png", "size": Vector2i(32, 32), "frames": 12, "fps": 12.0,
		"loop": false, "scale": 5.0, "pivot": Vector2(16, 28)},
	# сигналы игроку: улучшение отряда, боец встал (Apothecarion)
	"level_up":   {"sheet": PIXEL_DIR + "pickup_ui/level_up.png", "size": Vector2i(32, 32), "frames": 12, "fps": 12.0,
		"loop": false, "scale": 1.2, "pivot": Vector2(16, 74)},
	"poof":       {"sheet": PIXEL_DIR + "movement/poof_side.png", "size": Vector2i(32, 32), "frames": 8, "fps": 12.0,
		"loop": false, "scale": 1.5, "pivot": Vector2(16, 37)},
	# статусы над головой — StatusEffects.VFX; оглушение (STUNNED) — звёздочки
	"burning":    {"sheet": PIXEL_DIR + "status/burn.png", "size": Vector2i(32, 32), "frames": 8, "fps": 12.0,
		"loop": true, "scale": 1.4, "pivot": Vector2(16, 72)},
	"poisoned":   {"sheet": PIXEL_DIR + "status/poison.png", "size": Vector2i(32, 32), "frames": 12, "fps": 12.0,
		"loop": true, "scale": 1.4, "pivot": Vector2(16, 72)},
	"empowered":  {"sheet": PIXEL_DIR + "status/buff.png", "size": Vector2i(32, 32), "frames": 12, "fps": 12.0,
		"loop": true, "scale": 1.4, "pivot": Vector2(16, 72)},
	"slowed":     {"sheet": PIXEL_DIR + "status/debuff.png", "size": Vector2i(32, 32), "frames": 12, "fps": 12.0,
		"loop": true, "scale": 1.4, "pivot": Vector2(16, 72)},
	"stun":       {"sheet": PIXEL_DIR + "status/stun.png", "size": Vector2i(32, 32), "frames": 12, "fps": 12.0,
		"loop": true, "scale": 1.4, "pivot": Vector2(16, 72)},
}
const Z_INDEX_WORLD: int = 10   # разовые эффекты в мире — поверх бойцов и построек, как снаряды
const FLAT_Y: float = 0.5       # эффект «на земле» сплющен под изометрию

static var _frames_cache: Dictionary = {}   # вид → SpriteFrames

# Разовый эффект в мировой точке. size — множитель масштаба, angle — поворот (радианы)
static func spawn(parent: Node, kind: String, at: Vector2, size: float = 1.0, angle: float = 0.0) -> Vfx:
	if parent == null or not EFFECTS.has(kind):
		return null
	var v := _make(kind, size)
	v.z_index = Z_INDEX_WORLD
	v.rotation = angle
	parent.add_child(v)
	v.global_position = at
	return v

# Эффект на бойце (или другом узле): к его ногам, двигается вместе с ним
static func attach(owner: Node2D, kind: String, size: float = 1.0) -> Vfx:
	if owner == null or not EFFECTS.has(kind):
		return null
	var v := _make(kind, size)
	owner.add_child(v)
	if EFFECTS[kind].get("behind", false):
		owner.move_child(v, 0)   # дети рисуются по порядку: первым — за спрайтом
	return v

static func _make(kind: String, size: float) -> Vfx:
	var e: Dictionary = EFFECTS[kind]
	var v := Vfx.new()
	v.sprite_frames = _get_frames(kind)
	v.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # пиксель-арт
	v.offset = Vector2(e["size"]) / 2.0 - e["pivot"]
	var s: float = e["scale"] * size
	v.scale = Vector2(s, s * (FLAT_Y if e.get("flat", false) else 1.0))
	v.modulate = e.get("modulate", Color.WHITE)
	if not e["loop"]:
		v.animation_finished.connect(v.queue_free)
	v.play("play")
	return v

# Все листы — заранее (BattleScene._ready): иначе первый эффект каждого вида читает лист посреди боя
static func warm_cache() -> void:
	for kind in EFFECTS:
		_get_frames(kind)

static func _get_frames(kind: String) -> SpriteFrames:
	if _frames_cache.has(kind):
		return _frames_cache[kind]
	var e: Dictionary = EFFECTS[kind]
	var path: String = e["sheet"]
	var sheet: Texture2D = load(path if path.begins_with("res://") else SHEETS_DIR + path)
	var size: Vector2i = e["size"]
	var cols: int = sheet.get_width() / size.x
	var frames := SpriteFrames.new()
	frames.rename_animation("default", "play")
	frames.set_animation_speed("play", e["fps"])
	frames.set_animation_loop("play", e["loop"])
	var first: int = e.get("from", 0)
	for i in range(first, first + e["frames"]):
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2((i % cols) * size.x, (i / cols) * size.y, size.x, size.y)
		frames.add_frame("play", atlas)
	_frames_cache[kind] = frames
	return frames
