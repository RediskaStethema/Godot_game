extends Control

# Живая сцена главного меню на весь экран (решение пользователя 16.11.2026: «переделай меню так, как на эталоне»,
# эталон — exec-cd0d7c5f-8bdb-404a-b35c-e09977c372ad.png, ассеты — NewAssets/07_ui/assets/ui/menu/anim → tools/menu_v2_assets.py):
# слои на холсте CANVAS 1774×887 (координаты эталона), холст масштабируется «обложкой» по окну и прижат к правому краю —
# при окне уже 2:1 слева обрезается пустое небо под колонкой меню. Снизу вверх: звёздное небо, грозовые облака,
# дальний мост-крепость, флагман, три корабля с огнями, башня с парапетом и знамёнами (знамёна нарисованы на ней), пепел. Положение и масштаб слоёв подобраны по эталону (assets/source_sheets/menu_v2: locate.py, mock.py,
# layout.json). Прежняя сцена (планета, башня на портретном холсте 712×1172, десантник, окна и знамя кадрами) — в бэкапе
# assets/source_sheets/_backup_before_redesign_2026-11-15/ui/menu_anim/ (MenuSceneArt.gd.bak).
# Живое: облака и корабли плывут и покачиваются медленно и плавно (решение пользователя 16.11.2026: «более плавным» — период
# 45–90 с, огни дышат непрерывно, а не сменой кадров; общей палитры с дизерингом на меню больше нет — она «ползла» по
# движущимся слоям), пепел над башней. Рыцаря на парапете нет (решение пользователя 16.11.2026). Пока курсор на кнопке
# меню (MainMenu → set_menu_hover) каждое второе окно кораблей — флагмана и малых — разгорается ярче (слои
# `*_glow_half`, tools/menu_ships_glow.py), курсор ушёл — плавно гаснет.

const DIR = "res://assets/ui/menu/anim/"
const CANVAS = Vector2(1774, 887)

# Слои без движения кадров: файл, положение и масштаб на холсте эталона
const SKY = {"file": "menu_night_sky_stars", "pos": Vector2(0, 0), "scale": 1.0}
const CLOUDS = {"file": "menu_storm_clouds", "pos": Vector2(0, 0), "scale": 1.0}
const BRIDGE = {"file": "distant_fortress_bridge", "pos": Vector2(857, 460), "scale": 0.37}
const CAPITAL = {"file": "menu_capital_ship", "pos": Vector2(480, 70), "scale": 0.5}
const CASTLE = {"file": "menu_castle_battlement", "pos": Vector2(556, -22), "scale": 0.9}
const CLOUD_DRIFT = Vector2(18, 90)     # облака: размах px холста, период с
const CAPITAL_DRIFT = Vector2(11, 62)   # флагман: дрейф по x (px, период с)
const CAPITAL_BOB = Vector2(4.0, 9.0)   # покачивание по y (px, период с)
const BRIDGE_DRIFT = Vector2(7, 75)
const BRIDGE_FADE_LEFT: float = 0.8    # доля ширины моста слева, где он растворяется в облаках (левая треть исчезает совсем)
# Корабли пакета (ship_N.png и огни ship_N_glow_00..03): положение, масштаб, дрейф по x, покачивание по y
const SHIPS = [
	{"id": 1, "pos": Vector2(1150, 80), "scale": 0.65, "drift": Vector2(13, 48), "bob": Vector2(3, 8.0)},
	{"id": 2, "pos": Vector2(1390, 215), "scale": 0.42, "drift": Vector2(10, 39), "bob": Vector2(2.5, 7.0)},
	{"id": 3, "pos": Vector2(1125, 415), "scale": 1.15, "drift": Vector2(8, 33), "bob": Vector2(2, 6.0)},
]
const SHIP_GLOW_BASE: float = 0.55         # постоянные огни малых кораблей (слой `ship_N_glow`), дышат ±SHIP_GLOW_BREATH
const SHIP_GLOW_BREATH: float = 0.2
const SHIP_GLOW_PERIOD: float = 5.3
const HOVER_GLOW: float = 1.0               # яркость слоёв `*_glow_half` при курсоре на кнопке (ADD поверх огней)
const HOVER_HOLD: float = 0.35              # сек: свет держится после ухода курсора с кнопки (между кнопками — зазоры)
const HOVER_RATE: float = 4.0               # доля в секунду: разгорается и гаснет за ~0.25 с, с плавным ходом
# Корабли за облаками (решение пользователя 16.11.2026, `Screenshot 2026-11-16 192706.png`: «корабли должны быть как бы за
# облаками»): облака рисуются под кораблями, поэтому шипастое днище флагмана и малый корабль под ним торчали поверх них.
# Вторым слоем облаков это не лечится — облака поверх облаков темнели и меняли цвет (замечание пользователя). Вместо слоя —
# вуаль в шейдере самих кораблей, моста и флагмана: цвет пикселя смешивается с цветом облака в той же точке холста
# (та же формула, что у обычного наложения), сила растёт сверху вниз (доли высоты холста VEIL_FROM → VEIL_TO) — верхние
# корабли и палуба флагмана на виду, днище и нижние корабли тонут в облаках, а сами облака не затрагиваются
const VEIL_FROM: float = 0.25
const VEIL_TO: float = 0.45
const VEIL_STRENGTH: float = 0.95
const VEIL_SHADER = """shader_type canvas_item;
uniform float sat = 1.0;
uniform float val = 1.0;
uniform vec3 tint = vec3(1.0);
uniform sampler2D cloud_tex : filter_linear;
uniform vec2 origin = vec2(0.0);
uniform float k = 1.0;
uniform float cloud_x = 0.0;
uniform vec2 canvas = vec2(1774.0, 887.0);
uniform float from_y = 0.25;
uniform float to_y = 0.45;
uniform float strength = 0.95;
uniform float fade_left = 0.0;
varying vec2 cpos;
void vertex() {
	cpos = origin + VERTEX * k;
}
void fragment() {
	vec4 c = COLOR;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(vec3(l), c.rgb, sat) * val * tint;
	vec2 cuv = vec2((cpos.x - cloud_x) / canvas.x, cpos.y / canvas.y);
	vec4 cl = texture(cloud_tex, cuv);
	float m = cl.a * smoothstep(from_y, to_y, cuv.y) * strength;
	c.rgb = mix(c.rgb, cl.rgb, m);
	if (fade_left > 0.0) {
		float f = smoothstep(0.15 * fade_left, fade_left, UV.x);
		c.a *= f * f;
	}
	COLOR = c;
}"""
const SHIP_GRADE = {"sat": 0.75, "val": 0.9, "tint": Color(1.0, 0.93, 0.92)}

const ASH_AMOUNT: int = 60
const ASH_FROM_X: float = 0.62                 # пепел рождается правее этой доли холста — над башней
const ASH_CANVAS_SCALE: float = 1.6

var _stage: Control = null           # холст CANVAS, масштабируется под окно
var _clouds: TextureRect = null
var _veiled: Array = []              # {node, mat}: слои под вуалью облаков (положение — в шейдер каждый кадр)
var _castle_glow: TextureRect = null   # все окна башни — при курсоре на кнопке меню
var _hover_hold: float = 0.0
var _bridge: TextureRect = null
var _capital: TextureRect = null
var _ships: Array = []               # {node, glow, glow_frames, data, phase}
var _capital_glow: TextureRect = null   # каждое второе окно флагмана — при курсоре на кнопке меню
var _hover: float = 0.0              # 0..1 — насколько разгорелись окна кораблей
var _hover_target: float = 0.0
var _atmosphere: CPUParticles2D = null
var _time: float = 0.0
var _sky: TextureRect = null
var _castle: TextureRect = null
var _par := Vector2.ZERO   # параллакс от мыши (решение пользователя 18.11.2026): -1..1, плавно
const PAR_SKY := Vector2(4, 2)
const PAR_CLOUDS := Vector2(9, 4)
const PAR_BRIDGE := Vector2(13, 6)
const PAR_CAPITAL := Vector2(18, 8)
const PAR_SHIPS := Vector2(22, 9)
const PAR_CASTLE := Vector2(28, 12)
const PAR_RATE: float = 2.5

static func available() -> bool:
	return ResourceLoader.exists(DIR + CASTLE["file"] + ".png") and ResourceLoader.exists(DIR + CAPITAL["file"] + ".png")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_stage = Control.new()
	_stage.size = CANVAS
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_sky = _add_layer(SKY)
	_add_twinkle()
	_clouds = _add_layer(CLOUDS)
	_bridge = _add_layer(BRIDGE)
	_veil(_bridge, {})
	if _bridge and _bridge.material:
		# левый конец моста тонет в облаках, а не висит острием в воздухе (решение пользователя 24.11.2026)
		_bridge.material.set_shader_parameter("fade_left", BRIDGE_FADE_LEFT)
	_capital = _add_layer(CAPITAL)
	if _capital:
		_veil(_capital, {})
		_capital_glow = _add_glow(_capital, "menu_capital_ship_glow_half")
	for ship in SHIPS:
		_add_ship(ship)
	var castle := _add_layer(CASTLE)
	_castle = castle
	if castle:
		_castle_glow = _add_glow(castle, "menu_castle_battlement_glow")
	_atmosphere = _add_ash()
	_atmosphere.visible = GameSettings.atmosphere
	GameSettings.changed.connect(_on_settings_changed)
	resized.connect(_layout)
	_layout()

func _on_settings_changed() -> void:
	_atmosphere.visible = GameSettings.atmosphere

# Пепел в воздухе над башней — как поле Космодесанта (Atmosphere "ash"), в масштабе холста
func _add_ash() -> CPUParticles2D:
	var k: Dictionary = Atmosphere.KINDS["ash"]
	var p = CPUParticles2D.new()
	p.name = "Ash"
	var from_x := CANVAS.x * ASH_FROM_X
	p.position = Vector2((from_x + CANVAS.x) / 2.0, CANVAS.y / 2.0)
	p.amount = ASH_AMOUNT
	p.lifetime = k["lifetime"]
	p.preprocess = k["lifetime"]   # меню открывается уже с пеплом
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2((CANVAS.x - from_x) / 2.0, CANVAS.y / 2.0)
	p.direction = k["direction"]
	p.spread = 25.0
	p.initial_velocity_min = k["velocity"].x * ASH_CANVAS_SCALE
	p.initial_velocity_max = k["velocity"].y * ASH_CANVAS_SCALE
	p.gravity = k["gravity"] * ASH_CANVAS_SCALE
	p.scale_amount_min = k["scale"].x * ASH_CANVAS_SCALE
	p.scale_amount_max = k["scale"].y * ASH_CANVAS_SCALE
	var c: Color = k["color"]
	var ramp = Gradient.new()
	ramp.set_color(0, Color(c, 0.0))
	ramp.set_color(1, Color(c, 0.0))
	ramp.add_point(0.2, c)
	ramp.add_point(0.75, c)
	p.color_ramp = ramp
	p.material = Vfx.mix_material()   # пепел — прозрачность ступенями, как частицы поля
	_stage.add_child(p)
	return p

# Запас холста за краем окна (решение пользователя 18.11.2026: у замка внизу была видна обрезанность — слои сдвигает параллакс
# и дрейф, а нижний край башни не доходил до низа холста): холст крупнее обложки на OVERSCAN, края уходят за окно
const OVERSCAN: float = 0.06
func _layout() -> void:
	var s = maxf(size.x / CANVAS.x, size.y / CANVAS.y)
	var s2: float = s * (1.0 + OVERSCAN)
	_stage.scale = Vector2(s2, s2)
	_stage.position = Vector2(size.x - CANVAS.x * s2 + CANVAS.x * (s2 - s) * 0.5, (size.y - CANVAS.y * s2) * 0.5)

func _process(delta: float) -> void:
	_time += delta
	var m := Vector2.ZERO
	if size.x > 1.0 and size.y > 1.0:
		m = (get_local_mouse_position() / size * 2.0 - Vector2.ONE).clamp(Vector2(-1, -1), Vector2(1, 1))
	_par = _par.lerp(m, clampf(delta * PAR_RATE, 0.0, 1.0))
	_update_veils()
	_hover = move_toward(_hover, _hover_target, delta * HOVER_RATE)
	var k := _hover * _hover * (3.0 - 2.0 * _hover)   # плавный ход разгорания
	for ship in _ships:
		var d = ship["data"]
		var t = _time + ship["phase"]
		ship["node"].position = d["pos"] - _par * PAR_SHIPS + Vector2(
			sin(TAU * t / d["drift"].y) * d["drift"].x,
			sin(TAU * t / d["bob"].y) * d["bob"].x)
		if ship["glow"]:
			var b: float = SHIP_GLOW_BASE * (1.0 + SHIP_GLOW_BREATH * sin(TAU * t / SHIP_GLOW_PERIOD) * sin(TAU * t / (SHIP_GLOW_PERIOD * 2.7)))
			ship["glow"].self_modulate = Color(b, b, b)
		_set_glow(ship["half"], k)
	_set_glow(_capital_glow, k)
	_set_glow(_castle_glow, k)
	_hover_hold -= delta
	if _hover_hold <= 0.0:
		_hover_target = 0.0   # курсор ушёл с колонки кнопок дольше HOVER_HOLD — гаснет (между кнопками — не мигает)
	if _clouds:
		_clouds.position = CLOUDS["pos"] - _par * PAR_CLOUDS + Vector2(sin(TAU * _time / CLOUD_DRIFT.y) * CLOUD_DRIFT.x, 0.0)
	if _bridge:
		_bridge.position = BRIDGE["pos"] - _par * PAR_BRIDGE + Vector2(sin(TAU * _time / BRIDGE_DRIFT.y) * BRIDGE_DRIFT.x, 0.0)
	if _capital:
		_capital.position = CAPITAL["pos"] - _par * PAR_CAPITAL + Vector2(
			sin(TAU * _time / CAPITAL_DRIFT.y) * CAPITAL_DRIFT.x,
			sin(TAU * _time / CAPITAL_BOB.y) * CAPITAL_BOB.x) + _ship_fly(CAPITAL["pos"].x + 600.0, 0.8)
	if _sky:
		_sky.position = SKY["pos"] - _par * PAR_SKY
	if _castle:
		_castle.position = CASTLE["pos"] - _par * PAR_CASTLE

# Вуаль облаков: положение слоя и сдвиг облаков — в шейдер (узлы плывут, облака тоже)
func _update_veils() -> void:
	var cx := _clouds.position.x if _clouds else 0.0
	for v in _veiled:
		var n: TextureRect = v["node"]
		var m: ShaderMaterial = v["mat"]
		m.set_shader_parameter("origin", n.position)
		m.set_shader_parameter("k", n.scale.x)
		m.set_shader_parameter("cloud_x", cx)

func _set_glow(r: TextureRect, k: float) -> void:
	if r == null:
		return
	r.visible = k > 0.002
	r.self_modulate = Color(k * HOVER_GLOW, k * HOVER_GLOW, k * HOVER_GLOW)

# Курсор на кнопке меню — каждое второе окно кораблей горит ярче (MainMenu._process)
func set_menu_hover(on: bool) -> void:
	if on:
		_hover_target = 1.0
		_hover_hold = HOVER_HOLD   # зазоры между кнопками колонки свет не гасят (мигало при проводе курсора по меню)

func _rect(tex: Texture2D) -> TextureRect:
	var r = TextureRect.new()
	r.texture = tex
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex:
		r.size = tex.get_size()
	return r

# Слой пакета на холсте: файл, положение и масштаб из словаря (TextureRect.scale — от левого верхнего угла)
func _add_layer(layer: Dictionary) -> TextureRect:
	var path: String = DIR + layer["file"] + ".png"
	if not ResourceLoader.exists(path):
		return null
	var r := _rect(load(path))
	r.position = layer["pos"]
	r.scale = Vector2(layer["scale"], layer["scale"])
	_stage.add_child(r)
	return r

# Слой под вуалью облаков + (для кораблей) цветокор g {sat, val, tint}
func _veil(r: TextureRect, g: Dictionary) -> void:
	if r == null or _clouds == null:
		return
	var sh := Shader.new()
	sh.code = VEIL_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var t: Color = g.get("tint", Color.WHITE)
	m.set_shader_parameter("sat", g.get("sat", 1.0))
	m.set_shader_parameter("val", g.get("val", 1.0))
	m.set_shader_parameter("tint", Vector3(t.r, t.g, t.b))
	m.set_shader_parameter("cloud_tex", _clouds.texture)
	m.set_shader_parameter("canvas", CANVAS)
	m.set_shader_parameter("from_y", VEIL_FROM)
	m.set_shader_parameter("to_y", VEIL_TO)
	m.set_shader_parameter("strength", VEIL_STRENGTH)
	r.material = m
	_veiled.append({"node": r, "mat": m})

func _frames(prefix: String, count: int) -> Array:
	var out: Array = []
	for i in count:
		var path = DIR + "%s_%02d.png" % [prefix, i]
		if ResourceLoader.exists(path):
			out.append(load(path))
	return out

# Слой света поверх спрайта (на его холсте, ADD — гладкое сложение: прозрачность без ступеней дизеринга)
func _add_glow(parent: TextureRect, file: String) -> TextureRect:
	var path: String = DIR + file + ".png"
	if not ResourceLoader.exists(path):
		return null
	var r := _rect(load(path))
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	r.material = mat
	r.visible = false
	parent.add_child(r)
	return r

func _add_ship(data: Dictionary) -> void:
	var path = DIR + "ship_%d.png" % data["id"]
	if not ResourceLoader.exists(path):
		return
	var node = _rect(load(path))
	node.position = data["pos"]
	node.scale = Vector2(data["scale"], data["scale"])
	_stage.add_child(node)
	_veil(node, SHIP_GRADE)
	# Огни — свет поверх корабля на его холсте: постоянные (дышат) и «половина окон» для курсора на кнопке меню
	var glow := _add_glow(node, "ship_%d_glow" % data["id"])
	if glow:
		glow.visible = true
	var half := _add_glow(node, "ship_%d_glow_half" % data["id"])
	_ships.append({"node": node, "glow": glow, "half": half, "data": data, "phase": float(data["id"]) * 3.7})

# Взлёт в забег (MenuLaunch; решение пользователя 08.11.2026: «пролетаем мимо десантника и замка, а не улетаем
# вверх»): камера летит вперёд мимо крепости — сцена растёт вокруг парапета (до LAUNCH_ZOOM) и с разгоном уходит
# вправо за край экрана (точка взлёта смещается на LAUNCH_SHIFT доли экрана), за LAUNCH_SHARE длительности взлёта
const LAUNCH_AT = Vector2(1380, 720)   # точка холста, вокруг которой растёт сцена при взлёте (была — рыцарь)
const LAUNCH_ZOOM: float = 3.8
const LAUNCH_SHIFT = Vector2(1.9, 0.25)
const LAUNCH_SHARE: float = 0.62
var _launch_from_pos: Vector2
var _launch_from_scale: Vector2
var _cloud_halves: Array = []   # [левая, правая] — облака при взлёте раздвигаются (решение пользователя 18.11.2026)
func launch(duration: float) -> void:
	_launch_from_pos = _stage.position
	_launch_from_scale = _stage.scale
	_split_clouds()
	_add_launch_stars()
	var tw := create_tween()
	tw.tween_method(_fly_by, 0.0, 1.0, duration * LAUNCH_SHARE)

# Облака при взлёте разлетаются целыми облаками (решение пользователя 19.11.2026: «улетает полноценное облако, а не
# отрезанный кусок»): лист облаков заранее нарезан на облака (tools/menu_clouds_split.py → clouds_parts/), у соседей по
# сплошной массе швы мягкие и заходят друг на друга; левые уходят влево, правые вправо — тем дальше и быстрее, чем
# дальше от середины, чтобы расходились не рядами, а вразнобой
const CLOUD_PARTS_DIR = "res://assets/ui/menu/anim/clouds_parts/"
const CLOUD_FLY: float = 0.75       # доля ширины холста — улёт облака у середины листа
const CLOUD_FLY_EDGE: float = 0.9   # плюс за каждую долю расстояния от середины

func _split_clouds() -> void:
	if _clouds == null:
		return
	var f := FileAccess.open(CLOUD_PARTS_DIR + "clouds_parts.json", FileAccess.READ)
	if f == null:
		return
	var parts = JSON.parse_string(f.get_as_text())
	if not (parts is Array):
		return
	_cloud_halves.clear()
	for d in parts:
		var path: String = CLOUD_PARTS_DIR + String(d["file"])
		if not ResourceLoader.exists(path):
			continue
		var r := _rect(load(path))
		var home: Vector2 = _clouds.position + Vector2(d["x"], d["y"]) * _clouds.scale.x
		r.position = home
		r.scale = _clouds.scale
		var rel: float = (float(d["cx"]) - CANVAS.x / 2.0) / (CANVAS.x / 2.0)   # -1..1 от середины листа
		var dir := -1.0 if rel < 0.0 else 1.0
		r.set_meta("home", home)
		r.set_meta("fly", dir * (CLOUD_FLY + CLOUD_FLY_EDGE * absf(rel)) * CANVAS.x * _clouds.scale.x)
		r.set_meta("lag", 0.12 * (1.0 - absf(rel)))   # у середины листа облака трогаются чуть позже
		_stage.add_child(r)
		_stage.move_child(r, _clouds.get_index())
		_cloud_halves.append(r)
	_clouds.visible = false

# Мигание звёзд меню (решение пользователя 24.11.2026): яркие пиксели самого ночного неба — звёзды; каждая то притухает
# (поверх неё тёмная заплатка цвета неба, обычное наложение), то горит как нарисована; фаза и темп у каждой свои.
# Узел — ребёнок неба: едет с ним (параллакс), лежит под облаками
class TwinkleStars extends Node2D:
	const LUM_MIN: float = 0.09      # яркость пикселя, с которой он считается звездой (звёзды неба тусклые: максимум 0.35)
	const MAX_STARS: int = 140
	const DIM_DEPTH: float = 0.85    # насколько глубоко звезда притухает (доля заплатки)
	const SKY_DARK := Color(0.02, 0.02, 0.04)
	var _stars: Array = []           # [точка, размер, фаза, темп, цвет вспышки]
	var _t: float = 0.0

	func setup(img: Image) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 2411
		var found: Array = []
		var cols := {}
		for y in range(0, img.get_height(), 2):   # шаг 2 px — вдвое быстрее, звёзды крупнее двух пикселей
			for x in range(0, img.get_width(), 2):
				var c := img.get_pixel(x, y)
				if c.a > 0.5 and c.get_luminance() > LUM_MIN:
					found.append(Vector2i(x, y))
					cols[Vector2i(x, y)] = c
		for i in range(found.size() - 1, 0, -1):   # перемешать своим rng: раскладка звёзд от seed, общий randi не трогаем
			var j := rng.randi_range(0, i)
			var tmp = found[i]
			found[i] = found[j]
			found[j] = tmp
		var taken: Array = []
		for p: Vector2i in found:
			if _stars.size() >= MAX_STARS:
				break
			var near := false
			for q: Vector2i in taken:   # одна звезда — не весь её пятно из соседних пикселей
				if absi(q.x - p.x) < 5 and absi(q.y - p.y) < 5:
					near = true
					break
			if near:
				continue
			taken.append(p)
			_stars.append([Vector2(p), 5.0, rng.randf() * TAU, rng.randf_range(0.8, 2.2), Color(cols[p]).lightened(0.7)])

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		for s in _stars:
			var k: float = 0.5 + 0.5 * sin(_t * s[3] + s[2])
			k *= k   # дольше горит, быстрее притухает — мигание, а не плавное дыхание
			var a: float = DIM_DEPTH * (1.0 - k)
			var sz: float = s[1]
			draw_rect(Rect2(s[0] - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), Color(SKY_DARK, a))
			var glint: Color = s[4]
			draw_rect(Rect2(s[0] - Vector2(1, 1), Vector2(3, 3)), Color(glint, 0.9 * k))   # вспышка в пике — звезда ярче, чем нарисована

func _add_twinkle() -> void:
	if _sky == null or _sky.texture == null:
		return
	var img := _sky.texture.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var tw := TwinkleStars.new()
	tw.name = "TwinkleStars"
	_sky.add_child(tw)
	tw.setup(img)

# Звёзды пролёта (решение пользователя 19.11.2026: «не видно звёзд при полёте»): ночное небо растянуто камерой ×3.8 и звёзд
# почти не остаётся — поверх него, под облаками, густое поле звёзд на холсте и за его левым краем (сцена уходит вправо)
class LaunchStars extends Node2D:
	const COUNT: int = 2200
	const AREA := Rect2(-2400.0, -500.0, 4200.0, 1900.0)
	var _stars: Array = []   # [точка, размер, фаза, цвет]
	var amount: float = 0.0
	var _t: float = 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1940
		var colors := [Palette.STAR_WHITE, Palette.STAR_WHITE, Palette.STAR_BLUE, Palette.STAR_AMBER]
		for i in COUNT:
			_stars.append([Vector2(rng.randf_range(AREA.position.x, AREA.end.x), rng.randf_range(AREA.position.y, AREA.end.y)),
				rng.randf_range(1.6, 3.6) if rng.randf() < 0.9 else rng.randf_range(4.0, 6.0), rng.randf() * TAU,
				colors[rng.randi() % colors.size()]])

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		for s in _stars:
			var a: float = amount * (0.55 + 0.45 * sin(_t * 1.7 + s[2]))
			var sz: float = s[1]
			draw_rect(Rect2(s[0] - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), Color(s[3], a))

var _launch_stars: LaunchStars = null
func _add_launch_stars() -> void:
	if _launch_stars != null or _sky == null:
		return
	_launch_stars = LaunchStars.new()
	_launch_stars.name = "LaunchStars"
	var star_mat := CanvasItemMaterial.new()
	star_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_launch_stars.material = star_mat
	_stage.add_child(_launch_stars)
	_stage.move_child(_launch_stars, _sky.get_index() + 1)

# Корабли при взлёте улетают, как облака (решение пользователя 19.11.2026): уходят вбок от середины холста и чуть вверх;
# k — доля пролёта, _ship_fly(x, сила) — сдвиг на холсте для корабля с левым краем в x
var _fly_k: float = 0.0
const SHIP_FLY: float = 1.1         # доля ширины холста — улёт корабля
func _ship_fly(x: float, power: float) -> Vector2:
	if _fly_k <= 0.0:
		return Vector2.ZERO
	var dir := -1.0 if x < CANVAS.x * 0.5 else 1.0
	return Vector2(dir * SHIP_FLY * CANVAS.x * power * _fly_k, -90.0 * power * _fly_k)

func _part_clouds(t: float) -> void:
	_fly_k = smoothstep(0.1, 0.9, t)
	_fly_k *= _fly_k
	if _launch_stars:
		_launch_stars.amount = smoothstep(0.0, 0.35, t) * 1.5
	for r: TextureRect in _cloud_halves:
		var k := smoothstep(0.05 + (r.get_meta("lag") as float), 0.85, t)
		r.position = (r.get_meta("home") as Vector2) + Vector2(r.get_meta("fly") as float * k, 0.0)
		r.modulate.a = 1.0 - 0.6 * smoothstep(0.5, 1.0, t)

func _fly_by(t: float) -> void:
	_part_clouds(t)
	var e := t * t                                       # разгон: сначала медленно, к концу — мимо со свистом
	var anchor := LAUNCH_AT                              # точка холста — парапет, мимо которого летим
	var from_screen := _launch_from_pos + anchor * _launch_from_scale.x
	var s := _launch_from_scale * (1.0 + (LAUNCH_ZOOM - 1.0) * e)
	var to_screen := from_screen + size * LAUNCH_SHIFT * e
	_stage.scale = s
	_stage.position = to_screen - anchor * s.x
	_stage.modulate.a = 1.0 - smoothstep(0.7, 1.0, t)   # к прыжку — чистый космос
