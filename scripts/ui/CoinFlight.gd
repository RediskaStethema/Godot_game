class_name CoinFlight
extends Control

# Монеты летят к счётчику (решение пользователя 12.11.2026: «убери Req, оставь монеты и их число; с поля боя
# прилетают сами монетки, анимированные, крутящиеся»). Монета — значок счётчика assets/ui/hud/requisition.png,
# вращение кодом: ширина × |cos|, обратная сторона темнее, на ребре — латунная полоска. Вылет: монеты подскакивают
# из точек поля веером, по очереди летят к счётчику, на каждой — on_coin(номер) (счётчик прибавляет), счётчик
# вздрагивает. По реальному времени (стоп-кадр, замедление финала и ×3 не мешают). Только вид

const SIZE: float = 30.0
const MIN_WIDTH: float = 0.1          # ребро монеты — не тоньше доли ширины
const SPIN_SPEED := Vector2(7.0, 11.0)   # рад/с, у каждой своя
const STAGGER: float = 0.07           # между монетами
const POP_TIME: float = 0.32          # подскок из точки
const POP_RISE := Vector2(30.0, 62.0)
const POP_SPREAD: float = 34.0
const FLY_TIME: float = 0.55
const END_SCALE: float = 0.7
const BACK_TINT := Color(0.62, 0.5, 0.38)
const GLOW := Color(1.0, 0.78, 0.35, 0.3)   # центр ореола; к краю — плавно в ноль (_glow_texture)
const GLOW_SCALE: float = 1.7               # поперечник ореола — доля SIZE
const EDGE := Color(0.66, 0.5, 0.26)
const PULSE_SCALE: float = 1.18

static var _texture: Texture2D = null
static var _glow: Texture2D = null

# Ореол без края (решение пользователя 12.11.2026: «видны границы отсвета» — был сплошной круг): радиальная
# картинка, прозрачность (1 − r)², один раз на все монеты
static func _glow_texture() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) / 2.0
	for y in n:
		for x in n:
			var d := clampf(Vector2(x - c, y - c).length() / c, 0.0, 1.0)
			var a := (1.0 - d) * (1.0 - d)
			img.set_pixel(x, y, Color(GLOW.r, GLOW.g, GLOW.b, GLOW.a * a))
	return ImageTexture.create_from_image(img)

var _phase := 0.0
var _speed := 9.0

# Монеты из точек экрана from_points (по кругу) к target; count штук; on_coin(i) — монета i долетела.
# Возвращает время до последней монеты
static func burst(layer: Node, from_points: Array, target: Control, count: int,
		on_coin: Callable = Callable()) -> float:
	if count <= 0 or from_points.is_empty() or layer == null:
		return 0.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var coin := CoinFlight.new()
		coin._phase = rng.randf() * TAU
		coin._speed = rng.randf_range(SPIN_SPEED.x, SPIN_SPEED.y)
		layer.add_child(coin)
		var start: Vector2 = from_points[i % from_points.size()]
		coin.position = start
		coin.scale = Vector2.ZERO
		var pop := start + Vector2(rng.randf_range(-POP_SPREAD, POP_SPREAD), -rng.randf_range(POP_RISE.x, POP_RISE.y))
		var tw := coin.create_tween().set_ignore_time_scale(true)
		tw.tween_interval(i * STAGGER)
		tw.tween_property(coin, "position", pop, POP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(coin, "scale", Vector2.ONE, POP_TIME * 0.6).set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)
		var end := target.get_global_rect().get_center() if is_instance_valid(target) else pop
		tw.tween_property(coin, "position", end, FLY_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(coin, "scale", Vector2(END_SCALE, END_SCALE), FLY_TIME)
		var index := i
		tw.tween_callback(func():
			coin.queue_free()
			pulse(target)
			if on_coin.is_valid():
				on_coin.call(index))
	return (count - 1) * STAGGER + POP_TIME + FLY_TIME

# Счётчик вздрагивает — монета «зачислена»
static func pulse(target: Control) -> void:
	if not is_instance_valid(target):
		return
	target.pivot_offset = target.size / 2.0
	var t := target.create_tween().set_ignore_time_scale(true)
	t.tween_property(target, "scale", Vector2(PULSE_SCALE, PULSE_SCALE), 0.06)
	t.tween_property(target, "scale", Vector2.ONE, 0.14)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _texture == null:
		_texture = _padded_coin()
	if _glow == null:
		_glow = _glow_texture()

# Значок монеты с прозрачными полями TEX_PAD (решение пользователя 12.11.2026: «видно, как обрезан ассет»): в
# requisition.png монета касается края картинки (справа непрозрачность 104 из 255), при сжатии вращением и
# мип-уровнях край текстуры давал ровный срез. Поля — по краям пусто, срез уходит
const TEX_PAD: int = 6
static func _padded_coin() -> Texture2D:
	var src: Texture2D = UITheme.ui_icon("hud", "requisition")
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		return src
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var out := Image.create(img.get_width() + TEX_PAD * 2, img.get_height() + TEX_PAD * 2, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(TEX_PAD, TEX_PAD))
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)

func _process(delta: float) -> void:
	_phase += delta * _speed
	queue_redraw()

func _draw() -> void:
	var c := cos(_phase)
	var w := maxf(absf(c), MIN_WIDTH) * SIZE
	var pad_k := 1.0 + 2.0 * TEX_PAD / 96.0   # поля текстуры — рамка рисунка больше на их долю, монета того же размера
	var rect := Rect2(Vector2(-w / 2.0, -SIZE / 2.0) * pad_k, Vector2(w, SIZE) * pad_k)
	var g := SIZE * GLOW_SCALE   # тёплый ореол — бронза читается на тёмном поле
	draw_texture_rect(_glow, Rect2(Vector2(-g, -g) / 2.0, Vector2(g, g)), false)
	if _texture:
		draw_texture_rect(_texture, rect, false, Color.WHITE if c >= 0.0 else BACK_TINT)
	else:
		draw_rect(rect, EDGE)
	if absf(c) < 0.35:   # ребро: толщина монеты, свет посередине
		var ew := 4.0
		draw_rect(Rect2(Vector2(-ew / 2.0, -SIZE * 0.44), Vector2(ew, SIZE * 0.88)), EDGE.darkened(0.35))
		draw_rect(Rect2(Vector2(-0.5, -SIZE * 0.4), Vector2(1.0, SIZE * 0.8)), EDGE.lightened(0.3))
