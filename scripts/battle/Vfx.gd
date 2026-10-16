class_name Vfx
extends AnimatedSprite2D

# Визуальные эффекты боя из листов assets/Spritesheets (кадры сеткой: слева направо, сверху вниз).
# Только вид: на бой не влияют, живут своей анимацией (на паузе стоят, скорость ×2 ускоряет).
# Разовый эффект (loop = false) удаляет себя сам; постоянный (статус, оглушение) снимает владелец.
#   spawn(parent, вид, точка)  — разовый эффект в мировой точке (попадание, взрыв)
#   attach(боец, вид)          — на бойце: ставится к ногам, двигается вместе с ним

const SHEETS_DIR = "res://assets/Spritesheets/"
# sheet — файл листа, size — кадр, frames — кадров (пустые хвосты листа не берём), fps, loop,
# scale — масштаб на бойце роста 62 px, pivot — точка кадра, которая встаёт в позицию эффекта
# (у эффектов на бойце — ноги), behind — рисовать за спрайтом бойца
const EFFECTS = {
	# попадание снаряда в цитадель — искры по направлению полёта
	"hit_spark":  {"sheet": "Sparks-Sheet.png", "size": Vector2i(96, 96), "frames": 7, "fps": 20.0,
		"loop": false, "scale": 0.4, "pivot": Vector2(20, 62)},
	# удар в ближнем бою и попадание снаряда в бойца (Projectile)
	"blood":      {"sheet": "Blood Splat.png", "size": Vector2i(96, 96), "frames": 7, "fps": 16.0,
		"loop": false, "scale": 1.2, "pivot": Vector2(50, 46)},
	# лужа крови под павшим
	"splatter":   {"sheet": "Splatter-Sheet.png", "size": Vector2i(150, 150), "frames": 30, "fps": 30.0,
		"loop": false, "scale": 0.45, "pivot": Vector2(85, 140), "behind": true},
	# отбрасывание (удар Dreadnought)
	"impact":     {"sheet": "Spark1-Sheet.png", "size": Vector2i(150, 150), "frames": 30, "fps": 33.0,
		"loop": false, "scale": 0.4, "pivot": Vector2(72, 140)},
	# взрыв (цитадель, Thunderfire Cannon) — масштаб по радиусу взрыва
	"explosion":  {"sheet": "Smoke-Sheet.png", "size": Vector2i(80, 80), "frames": 19, "fps": 18.0,
		"loop": false, "scale": 1.0, "pivot": Vector2(38, 78)},
	# взрыв залпа Thunderfire: огненный шар (+ "explosion" и "impact" — дым и обломки)
	"fireball":   {"sheet": "Fire+Sparks-Sheet.png", "size": Vector2i(96, 96), "frames": 19, "fps": 22.0,
		"loop": false, "scale": 0.9, "pivot": Vector2(52, 92)},
	# взрыв клетки (лист assets/Chaos_assets1.png, кадры 6–12: трещины → взрыв → выжженная земля) —
	# попадание орбитального удара и Thunderfire; плита земли: на слое пола, бойцы поверх (ground),
	# последний кадр гаснет за fade с. Верхняя грань плиты в кадре — 232 px, центр (127, 150):
	# масштаб 60 / 232 — ширина грани = поперечник взрыва радиуса Projectile.EXPLOSION_VFX_RADIUS
	"tile_blast": {"sheet": "Chaos Tile Blast-Sheet.png", "size": Vector2i(256, 235), "frames": 7,
		"fps": 12.0, "loop": false, "scale": 0.26, "pivot": Vector2(127, 150), "ground": true, "fade": 0.5},
	# вспышка выстрела орудия — поджиг ракеты (первые кадры листа ракеты)
	"muzzle_flash": {"sheet": "Rocket Fire 2-Sheet.png", "size": Vector2i(150, 150), "frames": 5,
		"fps": 20.0, "loop": false, "scale": 1.0, "pivot": Vector2(68, 78)},
	# дым из ствола орудия
	"muzzle_smoke": {"sheet": "Smoke2-Sheet.png", "size": Vector2i(150, 150), "frames": 40, "fps": 40.0,
		"loop": false, "scale": 0.5, "pivot": Vector2(80, 148)},
	# лечение (Apothecary, лечение картой)
	"heal":       {"sheet": "Regen.png", "size": Vector2i(96, 96), "frames": 8, "fps": 10.0,
		"loop": false, "scale": 0.6, "pivot": Vector2(46, 96)},
	# оглушение (попадание Librarian)
	"stun":       {"sheet": "Eletric A-Sheet.png", "size": Vector2i(96, 96), "frames": 9, "fps": 12.0,
		"loop": true, "scale": 0.65, "pivot": Vector2(51, 91)},
	# каст (Librarian)
	"cast":       {"sheet": "Eletric Aura.png", "size": Vector2i(96, 96), "frames": 7, "fps": 12.0,
		"loop": true, "scale": 0.7, "pivot": Vector2(50, 89)},
	# поджог при попадании (Havoc, Salamanders) — язык пламени по направлению удара
	"flame_burst": {"sheet": "Flamethrower-Sheet.png", "size": Vector2i(96, 48), "frames": 10, "fps": 24.0,
		"loop": false, "scale": 0.9, "pivot": Vector2(30, 24)},
	# бурление ядовитой реки (IsoGridRenderer, только вид) — голубой лист, перекрашен в зелёный
	"river_splash": {"sheet": "Water Vortex Splash-Sheet.png", "size": Vector2i(150, 150), "frames": 30,
		"fps": 20.0, "loop": false, "scale": 0.5, "pivot": Vector2(75, 75), "flat": true,
		"modulate": Color(0.55, 1.0, 0.35, 0.85)},
	# статусы — StatusEffects.VFX
	"burning":    {"sheet": "Fire+Sparks-Sheet.png", "size": Vector2i(96, 96), "frames": 19, "fps": 14.0,
		"loop": true, "scale": 0.3, "pivot": Vector2(52, 96)},   # пламя ниже бойца — не закрывает его
	"poisoned":   {"sheet": "Poison Cloud-Sheet.png", "size": Vector2i(144, 144), "frames": 19, "fps": 14.0,
		"loop": true, "scale": 0.38, "pivot": Vector2(80, 144)},
	"empowered":  {"sheet": "Holy Light Aura.png", "size": Vector2i(96, 96), "frames": 7, "fps": 8.0,
		"loop": true, "scale": 0.8, "pivot": Vector2(48, 62), "behind": true},
	"slowed":     {"sheet": "Gravity-Sheet.png", "size": Vector2i(96, 80), "frames": 20, "fps": 14.0,
		"loop": true, "scale": 0.45, "pivot": Vector2(48, 42), "behind": true, "flat": true},
}
const Z_INDEX_WORLD: int = 10   # разовые эффекты в мире — поверх бойцов и построек, как снаряды
const FLAT_Y: float = 0.5       # эффект «на земле» сплющен под изометрию

static var _frames_cache: Dictionary = {}   # вид → SpriteFrames
# Слой земли (пол поля, BattleScene._build_field): эффекты с "ground" — под бойцами, поверх плит
static var ground_layer: Node2D = null

# Разовый эффект в мировой точке. size — множитель масштаба, angle — поворот (радианы)
static func spawn(parent: Node, kind: String, at: Vector2, size: float = 1.0, angle: float = 0.0) -> Vfx:
	if parent == null or not EFFECTS.has(kind):
		return null
	var v := _make(kind, size)
	v.z_index = Z_INDEX_WORLD
	if EFFECTS[kind].get("ground", false) and is_instance_valid(ground_layer):
		parent = ground_layer
		v.z_index = 0
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
	if not e["loop"] and e.has("fade"):
		v.animation_finished.connect(func():
			var tw := v.create_tween()
			tw.tween_property(v, "modulate:a", 0.0, e["fade"])
			tw.tween_callback(v.queue_free))
	elif not e["loop"]:
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
	var sheet: Texture2D = load(SHEETS_DIR + e["sheet"])
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
