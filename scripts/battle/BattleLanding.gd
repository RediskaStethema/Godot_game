class_name BattleLanding
extends Control

# Посадка на поле боя (решение пользователя 08.11.2026: «улетает в космос и прилетает на поле боя») — первое поле
# нового забега (RunManager.landing_pending ставят MainMenu и «НОВЫЙ ЗАБЕГ» на экране итога; BattleScene._ready
# снимает его): камера с высоты опускается к полю (zoom от LAND_FROM_ZOOM вписанного до вписанного), экран
# сначала затянут облаками, они расходятся от центра и тают, будто камера проходит сквозь них, в конце — толчок
# посадки (BattleCamera.shake). Оверлей на CanvasLayer поверх интерфейса, мышь ловит до конца посадки.
# Облака — цвет темы (тумана) расы. Только вид; headless — не играет (флаг снимается)
# Гримдарк (решение пользователя 08.11.2026: «слишком красочная»): не светлые облака, а тяжёлый дым и пепел сгоревшего
# мира — тёмные клубы, снизу их подсвечивают отсветы пожаров (Palette.LANDING_FIRE, ADD-пятна), сквозь них летит пепел
# и тлеющие угли (вверх — камера опускается), всё гаснет к посадке

const DURATION: float = 2.6
const LAND_FROM_ZOOM: float = 0.28     # доля вписанного зума в начале
const CLOUDS: int = 30
const CLOUD_LAYER: int = 60
const SHAKE: float = 5.0
const FIRES: int = 7                   # отсветы пожаров под дымом
const ASH: int = 140                   # частицы пепла / углей

var camera: BattleCamera
var color: Color = Palette.DUST_PALE
var _target_zoom: Vector2
var _t: float = 0.0
var _clouds: Array = []                # [точка (доли), радиус (доля высоты), сила]
var _tex: GradientTexture2D
var _layer: CanvasLayer
var _fires: Array = []                 # [точка (доли), радиус (доля высоты), фаза]
var _ash: Array = []                   # [точка (доли), скорость, размер, уголь?]
var _add: CanvasItem = null            # слой отсветов (ADD)

static func play(scene: Node, cam: BattleCamera, cloud_color: Color) -> void:
	var layer := CanvasLayer.new()
	layer.layer = CLOUD_LAYER
	scene.add_child(layer)
	var l := BattleLanding.new()
	l.camera = cam
	l.color = cloud_color
	l._layer = layer
	layer.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for i in CLOUDS:
		_clouds.append([Vector2(rng.randf_range(-0.1, 1.1), rng.randf_range(-0.1, 1.1)),
			rng.randf_range(0.25, 0.55), rng.randf_range(0.7, 1.0)])
	for i in FIRES:
		_fires.append([Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.35, 1.0)), rng.randf_range(0.15, 0.3),
			rng.randf() * TAU])
	for i in ASH:
		_ash.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.25, 0.7), rng.randf_range(1.0, 2.5),
			rng.randf() < 0.18])
	var add := Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.material = mat
	add.draw.connect(_draw_fire.bind(add))
	add_child(add)
	_add = add
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 0.6))
	_tex = GradientTexture2D.new()
	_tex.gradient = g
	_tex.fill = GradientTexture2D.FILL_RADIAL
	_tex.fill_from = Vector2(0.5, 0.5)
	_tex.fill_to = Vector2(0.5, 0.0)
	_tex.width = 128
	_tex.height = 128
	_target_zoom = camera.zoom
	camera.zoom = _target_zoom * LAND_FROM_ZOOM
	var tw := camera.create_tween()
	tw.tween_property(camera, "zoom", _target_zoom, DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): camera.shake(SHAKE))
	AudioManager.play("landing")

func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION + 0.2:
		_layer.queue_free()
		return
	queue_redraw()
	_add.queue_redraw()

func _draw() -> void:
	var k := clampf(_t / DURATION, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 2.0)                  # быстро сквозь облака, плавно к земле
	var c := size * 0.5
	# сплошная дымка в начале — поле не видно, пока камера над облаками
	var haze := 1.0 - smoothstep(0.0, 0.45, k)
	if haze > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(color.darkened(0.35), haze))
	for cl in _clouds:
		var p: Vector2 = (cl[0] as Vector2) * size
		var at := c + (p - c) * (1.0 + e * 2.6)           # облака расходятся от центра — камера проходит сквозь
		var r: float = cl[1] * size.y * (1.0 + e * 2.2)
		var a: float = cl[2] * pow(1.0 - e, 1.3)
		if a <= 0.01:
			continue
		draw_texture_rect(_tex, Rect2(at - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, Color(color, a))
	# пепел и угли: летят вверх (камера опускается), гаснут к посадке
	var fade := 1.0 - smoothstep(0.55, 1.0, k)
	for p in _ash:
		var pos: Vector2 = p[0]
		var y := fposmod(pos.y - _t * p[1] * 1.6, 1.0)
		var x := pos.x + sin(_t * 1.3 + pos.y * 9.0) * 0.01
		var col: Color = Palette.LAUNCH_EMBER if p[3] else Palette.LAUNCH_ASH
		draw_rect(Rect2(Vector2(x, y) * size, Vector2(p[2], p[2] * (2.5 if not p[3] else 1.0))),
			Color(col, (0.75 if p[3] else 0.45) * fade))

# Отсветы пожаров снизу сквозь дым (ADD): тусклые пятна огня мерцают, гаснут вместе с дымом
func _draw_fire(canvas: Node2D) -> void:
	var k := clampf(_t / DURATION, 0.0, 1.0)
	var a := (1.0 - smoothstep(0.3, 0.85, k)) * 0.3   # тусклее: отсвет, а не яркое пятно
	if a <= 0.0:
		return
	for f in _fires:
		var flick := 0.75 + 0.25 * sin(_t * 6.0 + f[2]) * sin(_t * 2.3 + f[2] * 1.7)
		var r: float = f[1] * size.y * 0.75 * (1.0 + k * 1.5)
		var at: Vector2 = (f[0] as Vector2) * size
		canvas.draw_texture_rect(_tex, Rect2(at - Vector2(r, r * 0.6), Vector2(r * 2.0, r * 1.2)), false,
			Color(Palette.LANDING_FIRE, a * flick))
