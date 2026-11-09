extends Control

# Живая сцена главного меню справа (UI_NEEDED.txt раздел 6, пакет художника 06.11.2026):
# слои одного холста CANVAS (assets/ui/menu/anim/) складываются пиксель в пиксель —
# космос, звёзды, планета, облака, корабли, башня, окна, знамя, десантник.
# Циклы кадров — по FPS своего слоя, корабли и облака код медленно ведёт сам.
# Ширина узла — по высоте (пропорция холста), прижат к правому краю родителя.
# Пакета нет — неподвижная menu_scene.png, как раньше (MainMenu._add_scene_art).

const DIR = "res://assets/ui/menu/anim/"
const CANVAS = Vector2(712, 1172)

# Циклы кадров: имя слоя → [кадров, к/с]
const LOOPS = {
	"stars": [4, 1.5],
	"windows": [4, 3.0],
	"banner": [12, 8.0],
	"marine": [8, 6.0],
}
# Корабли: место на холсте (по превью художника), дрейф по x (px, период с), покачивание (px, период с)
const SHIPS = [
	{"id": 1, "pos": Vector2(11, 66), "drift": Vector2(10, 34), "bob": Vector2(3, 6.0)},
	{"id": 2, "pos": Vector2(61, 281), "drift": Vector2(8, 27), "bob": Vector2(2.5, 5.0)},
	{"id": 3, "pos": Vector2(272, 422), "drift": Vector2(6, 21), "bob": Vector2(2, 4.2)},
]
const SHIP_GLOW_FPS: float = 4.0
const CLOUD_DRIFT = Vector2(5, 48)   # облака по планете: размах px, период с
# Облака — только на диске планеты (решение пользователя 08.11.2026, Screenshot 2026-11-08 113942: у кромки слой
# облаков, который дрейфует, съезжал с неподвижного диска — край двоился): прозрачность облаков × силуэт планеты,
# сжатый внутрь на CLOUD_EDGE_INSET px холста (минимум из 8 выборок вокруг), — у края облака тают, за край не выходят
const CLOUD_EDGE_INSET: float = 9.0
const CLOUD_MASK_SHADER = """shader_type canvas_item;
uniform float sat = 1.0;
uniform float val = 1.0;
uniform vec3 tint = vec3(1.0);
uniform sampler2D planet_tex : filter_linear;
uniform float shift_uv = 0.0;        // сдвиг облаков относительно планеты, доля ширины слоя
uniform float inset = 9.0;           // px — насколько сжать силуэт планеты
void fragment() {
	vec4 c = COLOR;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(vec3(l), c.rgb, sat) * val * tint;
	vec2 p = UV + vec2(shift_uv, 0.0);
	vec2 d = TEXTURE_PIXEL_SIZE * inset;
	vec2 e = d * 0.7071;
	float m = texture(planet_tex, p).a;
	m = min(m, min(texture(planet_tex, p + vec2(d.x, 0.0)).a, texture(planet_tex, p - vec2(d.x, 0.0)).a));
	m = min(m, min(texture(planet_tex, p + vec2(0.0, d.y)).a, texture(planet_tex, p - vec2(0.0, d.y)).a));
	m = min(m, min(texture(planet_tex, p + e).a, texture(planet_tex, p - e).a));
	m = min(m, min(texture(planet_tex, p + vec2(e.x, -e.y)).a, texture(planet_tex, p + vec2(-e.x, e.y)).a));
	c.a *= smoothstep(0.2, 0.95, m);
	COLOR = c;
}"""
const PLANET_EXT: float = 320.0      # px холста — запас слева у *_wide (tools/menu_planet_extend.py EXT)
# Свет сцены (решение пользователя 06.11.2026: «добавь освещение и стилизацию»): отсвет планеты
const PLANET_LIGHT = Palette.SHIELD_BLUE
const PLANET_LIGHT_ALPHA: float = 0.08   # 08.11.2026: планета глуше — и отсвет слабее (было 0.16)
# Планета и облака темнее и глуше (решение пользователя 08.11.2026, образец exampel.png: тёмно-синий диск с
# бледными облаками, не яркая голубая): насыщенность, яркость, холодный оттенок — шейдером на слоях
const PLANET_GRADE = {"sat": 0.55, "val": 0.47, "tint": Color(0.82, 0.9, 1.0)}
const CLOUDS_GRADE = {"sat": 0.45, "val": 0.66, "tint": Color(0.86, 0.93, 1.0)}
# Остальная сцена тоже тусклее (решение пользователя 08.11.2026: «флаг слишком яркий, всё слишком яркое» —
# замер по образцу: знамя 0.46 → 0.34 яркости, башня — нейтральный камень, огни кораблей едва тлеют)
const TOWER_GRADE = {"sat": 0.45, "val": 0.84, "tint": Color(1.0, 0.98, 0.96)}
# Знамя (решение пользователя 08.11.2026: «очень выбивается из общего стиля, слишком яркое»): глуше и темнее, светлое
# (белая аквила, золото кромки) приглушено сильнее — knee, к кости, а не к белому; тон холоднее, как у башни
const BANNER_GRADE = {"sat": 0.62, "val": 0.62, "tint": Color(0.95, 0.92, 0.92), "knee": 0.45}
# Колышется только от клика по нему (решение пользователя 08.11.2026): в покое кадр 0, клик по полотну —
# BANNER_WAVES проходов цикла и снова кадр 0
const BANNER_WAVES: int = 2
const BANNER_FPS: float = 9.0
const SHIP_GRADE = {"sat": 0.5, "val": 0.85, "tint": Color(0.95, 0.97, 1.0)}
const SHIP_GLOW_DIM: float = 0.35    # огни кораблей (ADD) — доля яркости
const WINDOWS_DIM: float = 0.62      # свет в окнах башни
# космос сцены почти чёрный (0, 3, 7) — поднят до фона меню (Palette.MENU_SPACE), шва нет
const SPACE_GRADE = {"sat": 1.0, "val": 1.0, "tint": Color.WHITE, "lift": Color(0.043, 0.06, 0.088)}
const GRADE_SHADER = """shader_type canvas_item;
uniform float sat = 1.0;
uniform float val = 1.0;
uniform vec3 tint = vec3(1.0);
uniform vec3 lift = vec3(0.0);       // прибавка к тёмному (космос сцены — до цвета фона меню)
uniform float knee = 0.0;            // светлое приглушается сильнее тёмного (белое → кость)
void fragment() {
	vec4 c = COLOR;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb *= 1.0 - knee * smoothstep(0.35, 0.95, l);
	c.rgb = max(mix(vec3(l), c.rgb, sat) * val * tint, lift);
	COLOR = c;
}"""
const PLANET_LIGHT_FROM = Vector2(0.0, 0.92)   # доли холста: центр — планета внизу слева
const PLANET_LIGHT_TO = Vector2(0.62, 0.45)    # радиус — до середины башни
const ASH_AMOUNT: int = 60
const ASH_FROM_X: float = 0.4                  # пепел рождается правее этой доли холста — над башней
const LIGHT_EDGE_MARGIN: float = 40.0          # px холста — свет планеты гаснет до нуля раньше кромки своего прямоугольника
const ASH_CANVAS_SCALE: float = 2.0            # холст ×2 к экрану — пепел крупнее и быстрее в px холста
# Десантник и его тень меньше на 20% (решение пользователя 07.11.2026: «слишком большой») — вокруг точки
# под ногами (низ силуэта marine_00, середина сапог), стоит на тех же плитах
const MARINE_SCALE: float = 0.5   # 08.11.2026, образец exampel.png: мельче рядом с башней (было 0.8)
const MARINE_FEET = Vector2(291, 804)
# Десантник органичнее (решение пользователя 08.11.2026, образец exampel.png: «у него есть тень»): стоит вплотную
# к парапету (сдвиг ног MARINE_OFFSET px холста), под ногами тёмное пятно, от него на плиты падает тень —
# силуэт текущего кадра, сплющенный и скошенный вправо (свет планеты слева), повторяет поворот головы
const MARINE_OFFSET = Vector2(-8, -20)
# Поворот головы — по курсору (решение пользователя 08.11.2026: «слишком часто поворачивается»): в покое стоит
# спиной (кадр 0), курсор на кнопке меню — оборачивается до кадра MARINE_PEAK и держит, ушёл — доигрывает
# поворот обратно (кадры после пика) и снова кадр 0. MainMenu зовёт set_marine_look
const MARINE_PEAK: int = 3
const MARINE_TURN_FPS: float = 8.0
const CAST_SHADOW_ALPHA: float = 0.7
const CAST_SHADOW_FLATTEN: float = -0.38   # длина тени — доля роста (минус — ложится от ног вперёд, на плиты)
const CAST_SHADOW_SKEW: float = -0.9       # рад: и вправо (свет слева); подобрано по образцу из 4 вариантов
const CONTACT_SHADOW_ALPHA: float = 0.6
const CONTACT_SHADOW_SIZE = Vector2(150, 44)   # px холста до масштаба десантника

var _stage: Control = null           # холст CANVAS, масштабируется под высоту
var _loops: Dictionary = {}          # имя → {rect, frames}
var _ships: Array = []               # {node, glow, glow_frames, data, phase}
var _clouds: TextureRect = null
var _planet: TextureRect = null
var _atmosphere: CPUParticles2D = null
var _time: float = 0.0

static func available() -> bool:
	return ResourceLoader.exists(DIR + "layer_tower.png")

# Слои планеты шире холста (решение пользователя 06.11.2026: «планета как бы обрезана» — у художника диск срезан
# левым краем холста): *_wide.png на PLANET_EXT px шире слева, космос с прозрачным краем — layer_space_edge.png.
# Есть — сцена не обрезается своей рамкой и без полосы растворения (MainMenu), нет — как раньше
static func has_wide_planet() -> bool:
	return ResourceLoader.exists(DIR + "layer_planet_wide.png") and ResourceLoader.exists(DIR + "layer_space_edge.png")

func _planet_x() -> float:
	return -PLANET_EXT if has_wide_planet() else 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Планета целиком (tools/menu_planet_extend.py) выходит за левый край сцены — без обрезки по её рамке
	clip_contents = not has_wide_planet()
	_stage = Control.new()
	_stage.size = CANVAS
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	# Снизу вверх, как в README пакета
	_grade(_add_layer("layer_space_edge" if has_wide_planet() else "layer_space"), SPACE_GRADE)   # левый край прозрачный — фон меню
	_add_loop("stars")
	_planet = _add_layer("layer_planet_wide" if has_wide_planet() else "layer_planet", _planet_x())
	_grade(_planet, PLANET_GRADE)
	_clouds = _add_layer("layer_clouds_wide" if has_wide_planet() else "layer_clouds", _planet_x())
	_grade(_clouds, CLOUDS_GRADE)
	if _clouds and _planet and _clouds.texture.get_size() == _planet.texture.get_size():
		var sh := Shader.new()
		sh.code = CLOUD_MASK_SHADER
		var m: ShaderMaterial = _clouds.material
		var keep := {"sat": m.get_shader_parameter("sat"), "val": m.get_shader_parameter("val"),
			"tint": m.get_shader_parameter("tint")}
		m.shader = sh
		for k in keep:
			m.set_shader_parameter(k, keep[k])
		m.set_shader_parameter("planet_tex", _planet.texture)
		m.set_shader_parameter("inset", CLOUD_EDGE_INSET)
	for ship in SHIPS:
		_add_ship(ship)
	_grade(_add_layer("layer_tower"), TOWER_GRADE)
	_add_planet_light()
	_add_loop("windows")
	if _loops.has("windows"):
		_loops["windows"]["rect"].modulate = Color(WINDOWS_DIM, WINDOWS_DIM, WINDOWS_DIM)
	_add_loop("banner")
	if _loops.has("banner"):
		_grade(_loops["banner"]["rect"], BANNER_GRADE)
	_add_loop("marine")
	if _loops.has("marine"):
		_add_marine_shadows()   # пятно у ног и падающая тень — под десантником
		_scale_marine(_loops["marine"]["rect"])
	_atmosphere = _add_ash()
	_atmosphere.visible = GameSettings.atmosphere
	GameSettings.changed.connect(_on_settings_changed)
	resized.connect(_layout)
	_layout()

func _on_settings_changed() -> void:
	_atmosphere.visible = GameSettings.atmosphere

# Отсвет планеты: холодный свет снизу слева гаснет к башне (ADD) — ложится на башню и площадку
func _add_planet_light() -> void:
	var g = Gradient.new()
	g.set_color(0, Color(PLANET_LIGHT, PLANET_LIGHT_ALPHA))
	g.set_color(1, Color(PLANET_LIGHT, 0.0))
	var tex = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	# Планета целиком выходит за левый край холста — свет тоже: прямоугольник шире слева на весь радиус пятна
	# (+ LIGHT_EDGE_MARGIN; 06.11.2026, Screenshot 2026-11-06 175554.png: запаса PLANET_EXT не хватало — у левой
	# кромки прямоугольника свет ещё не погас, на большом окне была видна вертикальная граница) и во столько же раз
	# выше (радиус в UV — один на обе оси: так пятно на экране то же), центр — та же точка холста
	var radius_x := (PLANET_LIGHT_TO - PLANET_LIGHT_FROM).length() * CANVAS.x
	var ext := maxf(-_planet_x(), radius_x - PLANET_LIGHT_FROM.x * CANVAS.x + LIGHT_EDGE_MARGIN) if has_wide_planet() else 0.0
	var k := (CANVAS.x + ext) / CANVAS.x
	var rect_size := CANVAS * k
	var center := PLANET_LIGHT_FROM * CANVAS + Vector2(ext, 0.0)
	tex.fill_from = center / rect_size
	tex.fill_to = tex.fill_from + (PLANET_LIGHT_TO - PLANET_LIGHT_FROM) / k
	var r = TextureRect.new()
	r.name = "PlanetLight"
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.position = Vector2(-ext, 0.0)
	r.size = rect_size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	r.material = mat
	_stage.add_child(r)

# Пепел в воздухе над площадкой — как поле Космодесанта (Atmosphere "ash"), в масштабе холста
func _add_ash() -> CPUParticles2D:
	var k: Dictionary = Atmosphere.KINDS["ash"]
	var p = CPUParticles2D.new()
	p.name = "Ash"
	# Рождается только над башней (ASH_FROM_X — доля холста): летит вправо-вниз и не доходит до левого края
	# сцены — иначе по краю было бы видно, где пепел кончается
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
	_stage.add_child(p)
	return p

func _layout() -> void:
	# Своя ширина — по высоте (как прежняя картинка EXPAND_FIT_WIDTH_PROPORTIONAL)
	var w = size.y * CANVAS.x / CANVAS.y
	if absf(offset_left + w) > 0.5:
		offset_left = -w
		return   # придёт новый resized
	var s = maxf(size.x / CANVAS.x, size.y / CANVAS.y)
	_stage.scale = Vector2(s, s)
	_stage.position = Vector2(size.x - CANVAS.x * s, (size.y - CANVAS.y * s) * 0.5)

func _process(delta: float) -> void:
	_time += delta
	for key in _loops:
		if key == "marine":
			_tick_marine(delta)
			continue
		if key == "banner":
			_tick_banner(delta)
			continue
		var loop = _loops[key]
		var frames: Array = loop["frames"]
		loop["rect"].texture = frames[int(_time * LOOPS[key][1]) % frames.size()]
	if _cast_shadow:
		_cast_shadow.texture = _loops["marine"]["rect"].texture   # тень повторяет кадр
	for ship in _ships:
		var d = ship["data"]
		var t = _time + ship["phase"]
		ship["node"].position = d["pos"] + Vector2(
			sin(TAU * t / d["drift"].y) * d["drift"].x,
			sin(TAU * t / d["bob"].y) * d["bob"].x)
		var glow: Array = ship["glow_frames"]
		if not glow.is_empty():
			ship["glow"].texture = glow[int(t * SHIP_GLOW_FPS) % glow.size()]
	if _clouds:
		var dx := sin(TAU * _time / CLOUD_DRIFT.y) * CLOUD_DRIFT.x
		_clouds.position.x = _planet_x() + dx
		if _clouds.material is ShaderMaterial:   # маска по планете — с учётом сдвига облаков
			(_clouds.material as ShaderMaterial).set_shader_parameter("shift_uv", dx / _clouds.texture.get_width())

func _rect(tex: Texture2D) -> TextureRect:
	var r = TextureRect.new()
	r.texture = tex
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex:
		r.size = tex.get_size()
	return r

func _add_layer(layer: String, x: float = 0.0) -> TextureRect:
	if not ResourceLoader.exists(DIR + layer + ".png"):
		return null
	var r = _rect(load(DIR + layer + ".png"))
	r.position.x = x
	_stage.add_child(r)
	return r

func _grade(r: TextureRect, g: Dictionary) -> void:
	if r == null:
		return
	var sh := Shader.new()
	sh.code = GRADE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var t: Color = g["tint"]
	m.set_shader_parameter("sat", g["sat"])
	m.set_shader_parameter("val", g["val"])
	m.set_shader_parameter("tint", Vector3(t.r, t.g, t.b))
	var lift: Color = g.get("lift", Color.BLACK)
	m.set_shader_parameter("lift", Vector3(lift.r, lift.g, lift.b))
	m.set_shader_parameter("knee", g.get("knee", 0.0))
	r.material = m

var _cast_shadow: Sprite2D = null
var _banner_t: float = -1.0   # сек с клика по знамени (< 0 — висит, кадр 0)
var _banner_mask: Image = null  # кадр 0 знамени — попадание клика по непрозрачному
var _marine_look: bool = false
var _marine_pos: float = 0.0   # кадр поворота (дробный): 0 — спиной, MARINE_PEAK — смотрит через плечо

# Клик по полотну знамени — колыхнётся (мышь сцена не ловит — смотрим ввод сами, кнопкам меню он не мешает)
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not _loops.has("banner") or not is_visible_in_tree():
		return
	if _banner_mask == null:
		_banner_mask = (_loops["banner"]["frames"][0] as Texture2D).get_image()
		if _banner_mask.is_compressed():
			_banner_mask.decompress()
	var p: Vector2 = _stage.get_local_mouse_position()   # в px холста (учтены масштаб сцены и окна)
	var x := int(p.x)
	var y := int(p.y)
	if x >= 0 and y >= 0 and x < _banner_mask.get_width() and y < _banner_mask.get_height() 			and _banner_mask.get_pixel(x, y).a > 0.5:
		wave_banner()

func wave_banner() -> void:
	if _banner_t < 0.0:
		_banner_t = 0.0

func _tick_banner(delta: float) -> void:
	var frames: Array = _loops["banner"]["frames"]
	var f := 0
	if _banner_t >= 0.0:
		_banner_t += delta
		f = int(_banner_t * BANNER_FPS)
		if f >= frames.size() * BANNER_WAVES:
			_banner_t = -1.0
			f = 0
	_loops["banner"]["rect"].texture = frames[f % frames.size()]

# Взлёт в забег (MenuLaunch; решение пользователя 08.11.2026: «пролетаем мимо десантника и замка, а не улетаем
# вверх»): камера летит вперёд мимо крепости — сцена растёт вокруг десантника (до LAUNCH_ZOOM) и с разгоном уходит
# вправо за край экрана (десантник смещается на LAUNCH_SHIFT доли экрана), за LAUNCH_SHARE длительности взлёта
const LAUNCH_ZOOM: float = 3.8
const LAUNCH_SHIFT = Vector2(1.9, 0.25)
const LAUNCH_SHARE: float = 0.62
var _launch_from_pos: Vector2
var _launch_from_scale: Vector2
func launch(duration: float) -> void:
	_launch_from_pos = _stage.position
	_launch_from_scale = _stage.scale
	var tw := create_tween()
	tw.tween_method(_fly_by, 0.0, 1.0, duration * LAUNCH_SHARE)

func _fly_by(t: float) -> void:
	var e := t * t                                       # разгон: сначала медленно, к концу — мимо со свистом
	var anchor := MARINE_FEET + MARINE_OFFSET            # точка холста — десантник
	var from_screen := _launch_from_pos + anchor * _launch_from_scale.x
	var s := _launch_from_scale * (1.0 + (LAUNCH_ZOOM - 1.0) * e)
	var to_screen := from_screen + size * LAUNCH_SHIFT * e
	_stage.scale = s
	_stage.position = to_screen - anchor * s.x
	_stage.modulate.a = 1.0 - smoothstep(0.7, 1.0, t)   # к прыжку — чистый космос

func set_marine_look(on: bool) -> void:
	_marine_look = on

func _tick_marine(delta: float) -> void:
	var frames: Array = _loops["marine"]["frames"]
	var n := frames.size()
	var step := delta * MARINE_TURN_FPS
	if _marine_look:
		if _marine_pos <= MARINE_PEAK:
			_marine_pos = minf(_marine_pos + step, MARINE_PEAK)
		else:   # отворачивался — обратно к пику теми же кадрами
			_marine_pos = maxf(_marine_pos - step, MARINE_PEAK)
	elif _marine_pos > 0.0:
		_marine_pos += step
		if _marine_pos >= n:
			_marine_pos = 0.0
	_loops["marine"]["rect"].texture = frames[int(_marine_pos) % n]

# Тени десантника кодом (прежний слой marine_shadow.png не сдвигается вместе с ним): тёмное пятно у ног и
# падающая тень — силуэт кадра чёрным, сплющен и скошен (Sprite2D — у Control нет скоса); кадр — в _process
func _add_marine_shadows() -> void:
	var feet := MARINE_FEET + MARINE_OFFSET
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, CONTACT_SHADOW_ALPHA))
	g.set_color(1, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var contact := TextureRect.new()
	contact.texture = tex
	contact.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sz := CONTACT_SHADOW_SIZE * MARINE_SCALE
	contact.size = sz
	contact.position = feet - sz * 0.5 + Vector2(sz.x * 0.12, 0.0)   # чуть вправо — к тени
	_stage.add_child(contact)
	_cast_shadow = Sprite2D.new()
	_cast_shadow.centered = false
	_cast_shadow.offset = -MARINE_FEET
	_cast_shadow.position = feet
	_cast_shadow.scale = Vector2(MARINE_SCALE, MARINE_SCALE * CAST_SHADOW_FLATTEN)   # сплющенный силуэт от ног
	_cast_shadow.skew = CAST_SHADOW_SKEW
	_cast_shadow.modulate = Color(0, 0, 0, CAST_SHADOW_ALPHA)
	_cast_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cast_shadow.texture = _loops["marine"]["frames"][0]
	_stage.add_child(_cast_shadow)

func _scale_marine(r: TextureRect) -> void:
	if r == null:
		return
	r.pivot_offset = MARINE_FEET
	r.scale = Vector2(MARINE_SCALE, MARINE_SCALE)
	r.position += MARINE_OFFSET

func _frames(prefix: String, count: int) -> Array:
	var out: Array = []
	for i in count:
		var path = DIR + "%s_%02d.png" % [prefix, i]
		if ResourceLoader.exists(path):
			out.append(load(path))
	return out

func _add_loop(key: String) -> void:
	var frames = _frames(key, LOOPS[key][0])
	if frames.is_empty():
		return
	var r = _rect(frames[0])
	_stage.add_child(r)
	_loops[key] = {"rect": r, "frames": frames}

func _add_ship(data: Dictionary) -> void:
	var path = DIR + "ship_%d.png" % data["id"]
	if not ResourceLoader.exists(path):
		return
	var node = _rect(load(path))
	node.position = data["pos"]
	_stage.add_child(node)
	_grade(node, SHIP_GRADE)
	# Огни — свет поверх корабля на его холсте
	var glow_frames = _frames("ship_%d_glow" % data["id"], 4)
	var glow = _rect(glow_frames[0] if not glow_frames.is_empty() else null)
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	glow.self_modulate = Color(SHIP_GLOW_DIM, SHIP_GLOW_DIM, SHIP_GLOW_DIM)
	node.add_child(glow)
	_ships.append({"node": node, "glow": glow, "glow_frames": glow_frames,
		"data": data, "phase": float(data["id"]) * 3.7})
