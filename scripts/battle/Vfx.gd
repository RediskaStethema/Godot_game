class_name Vfx
extends AnimatedSprite2D

# Визуальные эффекты боя из листов assets/Spritesheets (кадры сеткой: слева направо, сверху вниз).
# Только вид: на бой не влияют, живут своей анимацией (на паузе стоят, скорость ×2 ускоряет).
# Разовый эффект (loop = false) удаляет себя сам; постоянный (статус, оглушение) снимает владелец.
#   spawn(parent, вид, точка)  — разовый эффект в мировой точке (попадание, взрыв)
#   attach(боец, вид)          — на бойце: ставится к ногам, двигается вместе с ним

const SHEETS_DIR = "res://assets/Spritesheets/"
const PIXEL_DIR = "res://assets/effects/Pixel/PNG_native/"   # пак Pixel: sheet — полный путь
const BLOOD_DIR = "res://assets/effects/NEw pack blood/"     # брызги попадания снаряда: 5 листов 6×6 по 100 px
# Листы в палитре игры (tools/vfx_grade.py): res://assets/<путь> → res://assets/graded/<путь>, если перекрашен
const GRADED_DIR = "res://assets/graded/"
# sheet — файл листа, size — кадр, frames — кадров (пустые хвосты листа не берём), fps, loop,
# scale — масштаб на бойце роста 62 px, pivot — точка кадра, которая встаёт в позицию эффекта
# add — ADD-смешение (огонь, искры, энергия светятся; тёмные края листа исчезают)
# (у эффектов на бойце — ноги), behind — рисовать за спрайтом бойца
const EFFECTS = {
	# удар в ближнем бою (Soldier._land_melee_hit) — цвет крови жертвы, spawn_blood
	"blood":      {"sheet": "Blood Splat.png", "size": Vector2i(96, 96), "frames": 7, "fps": 16.0,
		"loop": false, "scale": 1.2, "pivot": Vector2(50, 46)},
	# попадание снаряда в бойца (Projectile) — случайный из 5 вариантов пака NEw pack blood, цвет — spawn_blood
	# (решение пользователя 18.10.2026); frames — без пустых хвостов и одиночной точки в конце листов
	"blood_1":    {"sheet": BLOOD_DIR + "1_100x100px.png", "size": Vector2i(100, 100), "frames": 22, "fps": 30.0,
		"loop": false, "scale": 0.6, "pivot": Vector2(47, 45)},
	"blood_2":    {"sheet": BLOOD_DIR + "2_100x100px.png", "size": Vector2i(100, 100), "frames": 21, "fps": 30.0,
		"loop": false, "scale": 0.6, "pivot": Vector2(47, 45)},
	"blood_3":    {"sheet": BLOOD_DIR + "3_100x100px.png", "size": Vector2i(100, 100), "frames": 24, "fps": 30.0,
		"loop": false, "scale": 0.6, "pivot": Vector2(47, 45)},
	"blood_4":    {"sheet": BLOOD_DIR + "4_100x100px.png", "size": Vector2i(100, 100), "frames": 13, "fps": 30.0,
		"loop": false, "scale": 0.6, "pivot": Vector2(47, 45)},
	"blood_5":    {"sheet": BLOOD_DIR + "5_100x100px.png", "size": Vector2i(100, 100), "frames": 29, "fps": 30.0,
		"loop": false, "scale": 0.6, "pivot": Vector2(47, 45)},
	# лужа крови под павшим
	"splatter":   {"sheet": "Splatter-Sheet.png", "size": Vector2i(150, 150), "frames": 30, "fps": 30.0,
		"loop": false, "scale": 0.45, "pivot": Vector2(85, 140), "behind": true},
	# обломки взрыва залпа Thunderfire
	"impact":     {"sheet": "Spark1-Sheet.png", "size": Vector2i(150, 150), "frames": 30, "fps": 33.0,
		"add": true, "loop": false, "scale": 0.4, "pivot": Vector2(72, 140)},
	# дым взрыва Thunderfire Cannon — масштаб по радиусу взрыва
	"explosion":  {"sheet": "Smoke-Sheet.png", "size": Vector2i(80, 80), "frames": 19, "fps": 18.0,
		"loop": false, "scale": 1.0, "pivot": Vector2(38, 78)},
	# взрыв залпа Thunderfire: огненный шар (+ "explosion" и "impact" — дым и обломки)
	"fireball":   {"sheet": "Fire+Sparks-Sheet.png", "size": Vector2i(96, 96), "frames": 19, "fps": 22.0,
		"add": true, "loop": false, "scale": 0.9, "pivot": Vector2(52, 92)},
	# вспышка выстрела орудия — поджиг ракеты (первые кадры листа ракеты)
	"muzzle_flash": {"sheet": "Rocket Fire 2-Sheet.png", "size": Vector2i(150, 150), "frames": 5,
		"fps": 20.0, "add": true, "loop": false, "scale": 1.0, "pivot": Vector2(68, 78)},
	# дым из ствола орудия
	"muzzle_smoke": {"sheet": "Smoke2-Sheet.png", "size": Vector2i(150, 150), "frames": 40, "fps": 40.0,
		"loop": false, "scale": 0.5, "pivot": Vector2(80, 148)},
	# поджог при попадании (Havoc, Salamanders) — язык пламени по направлению удара
	"flame_burst": {"sheet": "Flamethrower-Sheet.png", "size": Vector2i(96, 48), "frames": 10, "fps": 24.0,
		"add": true, "loop": false, "scale": 0.9, "pivot": Vector2(30, 24)},
	# бурление ядовитой реки (IsoGridRenderer, только вид) — голубой лист, перекрашен в зелёный
	"river_splash": {"sheet": "Water Vortex Splash-Sheet.png", "size": Vector2i(150, 150), "frames": 30,
		"fps": 20.0, "loop": false, "scale": 0.5, "pivot": Vector2(75, 75), "flat": true,
		"modulate": Color(0.55, 1.0, 0.35, 0.85)},
	# --- Пак Pixel (assets/effects/Pixel, листы PNG_native: кадры 32×32 в ряд; решение пользователя 17.10.2026) ---
	# масштаб — на бойце роста 62 px (как у остальных); pivot за пределами кадра — эффект над головой
	# попадание снаряда в цитадель
	"hit_spark":  {"sheet": PIXEL_DIR + "combat/hit_side.png", "size": Vector2i(32, 32), "frames": 8, "fps": 12.0,
		"add": true, "loop": false, "scale": 1.2, "pivot": Vector2(16, 16)},
	# росчерк удара в ближнем бою (поверх крови), по направлению удара
	"slash":      {"sheet": PIXEL_DIR + "combat/slash.png", "size": Vector2i(32, 32), "frames": 8, "fps": 16.0,
		"loop": false, "scale": 1.2, "pivot": Vector2(16, 16)},
	# отбрасывание (удар Dreadnought / Hellbrute) — удар о землю у ног
	"ground_slam": {"sheet": PIXEL_DIR + "combat/ground_slam_side.png", "size": Vector2i(32, 32), "frames": 12,
		"fps": 16.0, "loop": false, "scale": 1.6, "pivot": Vector2(16, 27)},
	# попадание Librarian (оглушает) — молния в цель
	"lightning":  {"sheet": PIXEL_DIR + "magic/lightning_side.png", "size": Vector2i(32, 32), "frames": 12,
		"fps": 16.0, "add": true, "loop": false, "scale": 1.4, "pivot": Vector2(16, 17)},
	# каст Librarian — вспышка вокруг бойца
	"cast":       {"sheet": PIXEL_DIR + "magic/magic_burst.png", "size": Vector2i(32, 32), "frames": 8, "fps": 12.0,
		"add": true, "loop": true, "scale": 1.6, "pivot": Vector2(16, 35)},
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
		"add": true, "loop": false, "scale": 1.2, "pivot": Vector2(16, 74)},
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
# Частые эффекты попаданий (каждый удар и снаряд) — под лимитом, как FloatingText: в сшибке сотен бойцов
# узел на каждый удар съедал тик (test_performance). Лишние не создаются — бой от этого не меняется
const HIT_EFFECTS = ["blood", "blood_1", "blood_2", "blood_3", "blood_4", "blood_5", "slash", "hit_spark"]
const SHOT_BLOOD = ["blood_1", "blood_2", "blood_3", "blood_4", "blood_5"]
# Цвет крови по UnitData.get_blood() (решение пользователя 18.10.2026): Космодесант — тёмно-красная,
# люди (культисты) — красная, Космодесант Хаоса — фиолетовая, нурглиты — зелёная, техника — чёрное масло + искра
const BLOOD_COLORS = {
	"dark_red": Color(0.45, 0.02, 0.03),
	"red":      Color(0.8, 0.05, 0.05),
	"purple":   Color(0.5, 0.1, 0.62),
	"green":    Color(0.45, 0.66, 0.12),
	"oil":      Color(0.08, 0.07, 0.06),
}
# Листы крови красные: яркость красного канала → оттенок крови (тени брызг сохраняются)
const BLOOD_SHADER = """shader_type canvas_item;
uniform vec3 blood;
void fragment() {
	COLOR = vec4(blood * clamp(COLOR.r / 0.7, 0.0, 1.3), COLOR.a);
}"""
static var _blood_shader: Shader
static var _blood_materials: Dictionary = {}   # цвет крови → ShaderMaterial (общие на все брызги)
const MAX_HIT_ALIVE: int = 48
const MAX_HIT_PER_FRAME: int = 8
static var _hits_alive: int = 0
static var _hit_frame: int = -1
static var _hits_this_frame: int = 0
const Z_INDEX_WORLD: int = 10   # разовые эффекты в мире — поверх бойцов и построек, как снаряды
const FLAT_Y: float = 0.5       # эффект «на земле» сплющен под изометрию

static var _frames_cache: Dictionary = {}   # вид → SpriteFrames

# Разовый эффект в мировой точке. size — множитель масштаба, angle — поворот (радианы)
static func spawn(parent: Node, kind: String, at: Vector2, size: float = 1.0, angle: float = 0.0) -> Vfx:
	if parent == null or not EFFECTS.has(kind):
		return null
	var hit: bool = kind in HIT_EFFECTS
	if hit and not _has_hit_slot():
		return null
	var v := _make(kind, size)
	v.z_index = Z_INDEX_WORLD
	v.rotation = angle
	parent.add_child(v)
	v.global_position = at
	# Место — только за эффектом в дереве: освобождает его tree_exited, вне дерева он бы не пришёл
	if hit and v.is_inside_tree():
		_hits_alive += 1
		_hits_this_frame += 1
		v.tree_exited.connect(_free_hit_slot)
	return v

# Кровь попадания в бойца цвета victim.get_blood(): shot — снаряд (случайный вариант пака), иначе удар вплотную.
# Техника — масло и искра по металлу
static func spawn_blood(parent: Node, at: Vector2, victim: UnitData, shot: bool, size: float = 1.0) -> void:
	var blood := victim.get_blood()
	var kind: String = SHOT_BLOOD[randi() % SHOT_BLOOD.size()] if shot else "blood"   # только вид — не RNG забега
	var v := spawn(parent, kind, at, size)
	if v:
		v.material = blood_material(blood)
	if blood == "oil":
		spawn(parent, "hit_spark", at, size * 0.5)   # мельче брызг — масло под искрой видно

static var _add: CanvasItemMaterial
# Фильтрация листов эффектов и снарядов (пиксель-арт — NEAREST; сравнение стилей — tests/capture_style.gd)
static var filter: CanvasItem.TextureFilter = CanvasItem.TEXTURE_FILTER_NEAREST

static func _add_material() -> CanvasItemMaterial:
	if _add == null:
		_add = CanvasItemMaterial.new()
		_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add

# Перекрашенный лист (tools/vfx_grade.py), если он есть, иначе исходный
static func graded_path(path: String) -> String:
	if path.begins_with("res://assets/") and not path.begins_with(GRADED_DIR):
		var graded := GRADED_DIR + path.trim_prefix("res://assets/")
		if ResourceLoader.exists(graded):
			return graded
	return path

static func blood_material(blood: String) -> ShaderMaterial:
	if not _blood_materials.has(blood):
		if _blood_shader == null:
			_blood_shader = Shader.new()
			_blood_shader.code = BLOOD_SHADER
		var m := ShaderMaterial.new()
		m.shader = _blood_shader
		m.set_shader_parameter("blood", BLOOD_COLORS.get(blood, BLOOD_COLORS["red"]))
		_blood_materials[blood] = m
	return _blood_materials[blood]

# Есть место под эффект попадания: живых < MAX_HIT_ALIVE и за этот кадр < MAX_HIT_PER_FRAME
static func _has_hit_slot() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _hit_frame:
		_hit_frame = frame
		_hits_this_frame = 0
	return _hits_alive < MAX_HIT_ALIVE and _hits_this_frame < MAX_HIT_PER_FRAME

static func _free_hit_slot() -> void:
	_hits_alive = maxi(_hits_alive - 1, 0)

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
	v.texture_filter = filter
	v.offset = Vector2(e["size"]) / 2.0 - e["pivot"]
	var s: float = e["scale"] * size
	v.scale = Vector2(s, s * (FLAT_Y if e.get("flat", false) else 1.0))
	v.modulate = e.get("modulate", Color.WHITE)
	if e.get("add", false):
		v.material = _add_material()
	if not e["loop"]:
		v.animation_finished.connect(v.queue_free)
	FrameBlend.attach(v, e.get("add", false))   # кадры перетекают; ADD — родитель гаснет на ту же долю
	v.play("play")
	return v

# Все листы — заранее (BattleScene._ready): иначе первый эффект каждого вида читает лист посреди боя
static func warm_cache() -> void:
	for kind in EFFECTS:
		_get_frames(kind)
	for blood in BLOOD_COLORS:
		blood_material(blood)
	_hits_alive = 0   # вход в бой: счёт эффектов попаданий заново (тесты гоняют бои в одном процессе)

static func _get_frames(kind: String) -> SpriteFrames:
	if _frames_cache.has(kind):
		return _frames_cache[kind]
	var e: Dictionary = EFFECTS[kind]
	var path: String = e["sheet"]
	var sheet: Texture2D = load(graded_path(path if path.begins_with("res://") else SHEETS_DIR + path))
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
