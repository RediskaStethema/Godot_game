class_name DropPod
extends Node2D

# Десантная капсула (решение пользователя 12.11.2026, ТЗ ART_TZ_DROP_POD_2026-11-12.txt): отряд Космодесанта,
# выложенный картой на пустую клетку расстановки, прилетает в капсуле: она падает с неба (лист fall, тень на земле
# растёт), бьёт о землю (лист land: удар, двери падают — тряска камеры, вспышка, пыль), с кадра REVEAL_FRAME
# отряд проявляется (on_reveal), капсула тает в дыме (лист fade) и уходит. Хаос — без капсулы (разлом варпа),
# здания — без неё. Листы — assets/effects/drop_pod (tools/drop_pod_frames.py: общий холст, точка клетки
# metadata/anchor). Только вид, только расстановка; «В БОЙ» раньше конца — finish(): отряд сразу виден.

const FRAMES_PATH := "res://assets/effects/drop_pod/frames.tres"
const WORLD_SCALE: float = 0.27        # кадры ×4 к миру ×1.08 (решение пользователя 23.11.2026: «капсулы слишком маленькие, +20%» — было 0.225; 12.11.2026 было 0.3 → 0.225)
const VEHICLE_SCALE: float = 1.15      # техника — капсула крупнее
const FALL_HEIGHT: float = 420.0       # с какой высоты падает, px мира
const FALL_TIME: float = 0.35
const FALL_Z: int = 60                 # в падении — над всем полем; на земле — в y-sort с бойцами
const REVEAL_FRAME: int = 8            # кадр land, с которого виден отряд (двери падают)
const SHAKE: float = 4.0
const FLASH_RADIUS: float = 90.0
const SHADOW_SIZE := Vector2(46.0, 16.0)   # тень на земле в конце падения, px мира (полуоси)
const SHADOW_ALPHA: float = 0.45
const SHADOW_STEPS: int = 4             # стопка эллипсов — мягкий край, как тень зданий
const DUST_RING: int = 10
# В стиль поля (решение пользователя 12.11.2026: «капсула смотрится инородно»): материал как у зданий — шейдер
# бойцов со светом местности темы "building_env" (оттенок, насыщенность, приглушение светов, затемнение к
# основанию, контур Palette.BUILDING_OUTLINE) + двери в цвет ордена (Chapters "armor", как броня бойцов)
# Удар (решение пользователя 12.11.2026, стилизация «удар и выход»): корпус сплющивается и пружинит обратно,
# из-под днища — пиксельные камни по дуге (земля 2:1), падают и гаснут
const SQUASH := Vector2(1.1, 0.86)
const SQUASH_TIME: float = 0.07
const UNSQUASH_TIME: float = 0.22
const DEBRIS: int = 14
const DEBRIS_SPEED := Vector2(40.0, 95.0)    # px мира/с по земле
const DEBRIS_UP := Vector2(60.0, 130.0)      # вверх
const DEBRIS_GRAVITY: float = 420.0
const DEBRIS_REST: float = 0.35              # лежит на земле и гаснет, с
const DEBRIS_PX := [1.5, 2.5]                # размер камня, px мира
const DEBRIS_COLORS := [Color(0.16, 0.15, 0.15), Color(0.27, 0.25, 0.23), Color(0.4, 0.36, 0.31)]
const AO_HEIGHT: float = 0.18          # затемнение к основанию — доля высоты кадра над точкой клетки
const AO_BELOW: float = 0.04
# Стилизация v3 (решение пользователя 23.11.2026: «капсулы выглядят инородно»): палитра расы и светотень ступенями сильнее,
# чем у зданий (тянут чистую рендер-краску Layer к грунту), воронка-подпалина под капсулой — «приземлена», а не наклеена
const POD_GAIN: float = 0.82          # общая яркость капсулы (самое светлое в кадре было — решение пользователя 23.11.2026)
const POD_PAL_MIX: float = 0.4
const POD_BAND_MIX: float = 0.3
const POD_SCORCH_R: float = 34.0       # подпалина под капсулой, px мира при WORLD_SCALE

static var _frames: SpriteFrames = null

var sprite: AnimatedSprite2D
var _on_reveal: Callable
var _revealed := false
var _fall_left := FALL_TIME
var _scale_k := 1.0
var _debris: Array = []   # {p: Vector2 по земле, v: Vector2, h: высота, vh, size, color, rest}
var _rng := RandomNumberGenerator.new()

static func available() -> bool:
	return ResourceLoader.exists(FRAMES_PATH)

# Кадры (32 × 640×768) — заранее в фоне (BattleScene._ready): первая загрузка в момент клика стояла ~0.5 с
static func warm() -> void:
	if _frames == null and available() and ResourceLoader.load_threaded_get_status(FRAMES_PATH) 			== ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(FRAMES_PATH)

static func _get_frames() -> SpriteFrames:
	if _frames == null:
		if ResourceLoader.load_threaded_get_status(FRAMES_PATH) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_frames = ResourceLoader.load_threaded_get(FRAMES_PATH)   # ждёт, если ещё грузится
		else:
			_frames = load(FRAMES_PATH)
	return _frames

# Капсула на точку клетки at (мировые координаты родителя-контейнера бойцов); on_reveal — показать отряд
static func drop(parent: Node, at: Vector2, vehicle: bool, on_reveal: Callable) -> DropPod:
	_get_frames()
	var pod := DropPod.new()
	pod._on_reveal = on_reveal
	pod._scale_k = WORLD_SCALE * (VEHICLE_SCALE if vehicle else 1.0)
	pod.position = at
	parent.add_child(pod)
	AudioManager.play("pod_fall")
	return pod

func _ready() -> void:
	z_index = FALL_Z
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = _frames
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.scale = Vector2(_scale_k, _scale_k)
	sprite.offset = -Vector2(_frames.get_meta("anchor", Vector2(320, 600)))
	sprite.position = Vector2(0.0, -FALL_HEIGHT)
	_apply_environment()
	add_child(sprite)
	sprite.play("fall")
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)

func _process(delta: float) -> void:
	if not _debris.is_empty():
		_tick_debris(delta)
	if _fall_left <= 0.0:
		return
	_fall_left -= delta
	var t := clampf(1.0 - _fall_left / FALL_TIME, 0.0, 1.0)
	sprite.position.y = -FALL_HEIGHT * (1.0 - t * t)   # с ускорением
	queue_redraw()
	if _fall_left <= 0.0:
		_touch_down()

# Материал как у зданий: свет местности темы (building_env) и цвет ордена на дверях
func _apply_environment() -> void:
	var env: Dictionary = FactionTheme.current().get("building_env", {})
	var m := ShaderMaterial.new()
	m.shader = Soldier.unit_shader()
	m.set_shader_parameter("outline_px", float(maxi(1, roundi(env.get("outline_px", Building.OUTLINE_WORLD_PX)
		/ maxf(_scale_k, 0.01)))))
	m.set_shader_parameter("outline_color", Color(Palette.BUILDING_OUTLINE, env.get("outline_alpha", 1.0)))
	m.set_shader_parameter("env_sat", env.get("sat", 1.0))
	m.set_shader_parameter("env_knee", env.get("knee", 0.0))
	var anchor_v: float = Vector2(_frames.get_meta("anchor", Vector2(320, 600))).y \
		/ _frames.get_frame_texture("land", 0).get_height()
	m.set_shader_parameter("ao_strength", env.get("ao", 0.0))
	m.set_shader_parameter("ao_from", anchor_v - AO_HEIGHT)
	m.set_shader_parameter("ao_to", anchor_v + AO_BELOW)
	var armor: Dictionary = Chapters.get_chapter(RunManager.player_chapter).get("armor", {})
	if not armor.is_empty():
		m.set_shader_parameter("armor", 1.0)
		m.set_shader_parameter("target_hue", armor.get("hue", 0.6))
		m.set_shader_parameter("sat_mult", armor.get("sat", 1.0))
		m.set_shader_parameter("val_mult", armor.get("val", 1.0))
		# Корпус и отделка — цвета братства, как у бойцов (решение пользователя 23.11.2026: «капсула выбивается из
		# стилистики и должна краситься в цвета ордена»): нейтральная сталь → body, золото и лампы → trim
		if armor.has("body"):
			var body: Dictionary = armor["body"]
			m.set_shader_parameter("body_mix", 1.0)
			m.set_shader_parameter("body_hsv", Vector3(body.get("hue", 0.0), body.get("sat", 0.0), body.get("val", 1.0)))
			m.set_shader_parameter("body_cap", float(body.get("cap", 1.0)))
		if armor.has("trim"):
			var trim: Dictionary = armor["trim"]
			m.set_shader_parameter("trim_mix", 1.0)
			m.set_shader_parameter("trim_hsv", Vector3(trim.get("hue", 0.12), trim.get("sat", 1.0), trim.get("val", 1.0)))
	Soldier.apply_style(m, "building")   # светотень ступенями и палитра расы, как у зданий
	m.set_shader_parameter("pal_mix", maxf(POD_PAL_MIX, float(m.get_shader_parameter("pal_mix"))))
	m.set_shader_parameter("band_mix", maxf(POD_BAND_MIX, float(m.get_shader_parameter("band_mix"))))
	sprite.material = m
	var tint: Color = env.get("tint", Color.WHITE)
	sprite.self_modulate = Color(tint.r * POD_GAIN, tint.g * POD_GAIN, tint.b * POD_GAIN, tint.a)   # приглушена: была ярче поля

# Тень на земле: растёт и темнеет, пока капсула падает; на земле — полная, в дыме (fade) гаснет
func _draw() -> void:
	var t := 1.0
	var a := 1.0
	if _fall_left > 0.0:
		t = clampf(1.0 - _fall_left / FALL_TIME, 0.0, 1.0)
		a = t
	elif sprite and sprite.animation == "fade":
		a = 1.0 - float(sprite.frame + 1) / maxf(sprite.sprite_frames.get_frame_count("fade"), 1.0)
	if a <= 0.0:
		_draw_debris()
		return
	var k := (0.35 + 0.65 * t) * _scale_k / WORLD_SCALE
	for i in SHADOW_STEPS:
		var f := 1.0 - float(i) / SHADOW_STEPS * 0.45
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(SHADOW_SIZE.x * k * f, SHADOW_SIZE.y * k * f))
		draw_circle(Vector2.ZERO, 1.0, Color(0, 0, 0, SHADOW_ALPHA * a / SHADOW_STEPS * 1.6))
	draw_set_transform(Vector2.ZERO)
	_draw_debris()   # поверх тени

func _touch_down() -> void:
	sprite.position = Vector2.ZERO
	z_index = 0   # дальше — в y-sort с бойцами отряда
	sprite.play("land")
	var base := Vector2(_scale_k, _scale_k)
	var sq := create_tween()
	sq.tween_property(sprite, "scale", base * SQUASH, SQUASH_TIME).set_ease(Tween.EASE_OUT)
	sq.tween_property(sprite, "scale", base, UNSQUASH_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_rng.randomize()
	var k := _scale_k / WORLD_SCALE
	for i in DEBRIS:
		var ang := TAU * (i + _rng.randf()) / DEBRIS
		var sp := _rng.randf_range(DEBRIS_SPEED.x, DEBRIS_SPEED.y) * k
		_debris.append({"p": Vector2(cos(ang), sin(ang) * 0.5) * 10.0 * k, "v": Vector2(cos(ang), sin(ang) * 0.5) * sp,
			"h": 2.0, "vh": _rng.randf_range(DEBRIS_UP.x, DEBRIS_UP.y), "size": _rng.randf_range(DEBRIS_PX[0], DEBRIS_PX[1]),
			"color": DEBRIS_COLORS[_rng.randi() % DEBRIS_COLORS.size()], "rest": DEBRIS_REST})
	queue_redraw()
	AudioManager.play("pod_impact")
	var scene := get_tree().current_scene if is_inside_tree() else null
	var cam = scene.get("camera") if scene else null
	if cam and cam.has_method("shake"):
		cam.shake(SHAKE)
	IsoGridRenderer.flash_light(global_position, Palette.FIRE, FLASH_RADIUS * _scale_k / WORLD_SCALE, 0.35)
	DustLayer.puff(global_position, 14.0 * _scale_k / WORLD_SCALE, DUST_RING, 26.0 * _scale_k / WORLD_SCALE)
	ScarLayer.scorch(global_position, POD_SCORCH_R * _scale_k / WORLD_SCALE)

# Камни: летят по дуге над землёй, упали — лежат и гаснут
func _tick_debris(delta: float) -> void:
	for d in _debris:
		if d["h"] > 0.0:
			d["p"] += d["v"] * delta
			d["vh"] -= DEBRIS_GRAVITY * delta
			d["h"] = maxf(d["h"] + d["vh"] * delta, 0.0)
		else:
			d["rest"] -= delta
	_debris = _debris.filter(func(d): return d["rest"] > 0.0)
	queue_redraw()

# Камни — квадратами в пиксель (как кластеры листа), тень камня в воздухе — точкой на земле
func _draw_debris() -> void:
	for d in _debris:
		var a: float = clampf(d["rest"] / DEBRIS_REST, 0.0, 1.0)
		var sz: float = d["size"]
		var p: Vector2 = (d["p"] as Vector2).round()
		if d["h"] > 0.0:
			draw_rect(Rect2(p - Vector2(sz, sz * 0.5) * 0.5, Vector2(sz, sz * 0.5)), Color(0, 0, 0, 0.35))
		var c: Color = d["color"]
		draw_rect(Rect2(p - Vector2(sz * 0.5, sz + d["h"]), Vector2(sz, sz)).abs(), Color(c, a))

func _on_frame_changed() -> void:
	if sprite.animation == "land" and sprite.frame >= REVEAL_FRAME:
		_reveal()
	if sprite.animation == "fade":
		queue_redraw()   # тень гаснет вместе с капсулой

func _on_animation_finished() -> void:
	match sprite.animation:
		"land":
			_reveal()
			AudioManager.play("pod_open")
			sprite.play("fade")
		"fade":
			queue_free()

func _reveal() -> void:
	if _revealed:
		return
	_revealed = true
	if _on_reveal.is_valid():
		_on_reveal.call()

# «В БОЙ» раньше конца: отряд виден сразу, капсулы нет
func finish() -> void:
	_fall_left = 0.0
	_reveal()
	queue_free()
