extends Control

# Гримдарк (решение пользователя 08.11.2026: «слишком красочная»): лучи — пепел и сталь с редким тусклым янтарём,
# реже и тусклее; вместо бело-голубой вспышки — тёмный мутный разрыв варпа (бордо-фиолет), гаснущий в черноту.
# Взлёт из главного меню в забег (решение пользователя 08.11.2026: «игрок будто улетает в космос и прилетает на поле
# боя»): после выбора расы / ордена / сложности / стартовой карты — оверлей на весь экран: колонка меню гаснет,
# сцена с башней уходит вниз (камера поднимается от крепости — MenuSceneArt.launch), звёзды вытягиваются в лучи
# от точки прыжка и разгоняются, вспышка варп-прыжка, затемнение — и on_done (RunManager.advance: шторка
# RunManager._go продолжает чёрным в магазин). Посадка — на первом поле забега (BattleLanding).
# Только вид, мышь ловит (во время взлёта меню не нажать); headless — сразу on_done.

const DURATION: float = 2.7
const STREAKS: int = 170
const CENTER = Vector2(0.42, 0.42)     # точка прыжка — доля экрана: куда летим, мимо крепости (она уходит вправо)
const STREAK_SPEED: float = 2.4        # доля экрана за секунду на пике
const FLASH_AT: float = 0.74           # доля длительности — вспышка прыжка
const FLASH_TIME: float = 0.3          # сек
const BLACK_FROM: float = 0.82         # доля длительности — с неё экран темнеет

var on_done: Callable
var _t: float = 0.0
var _streaks: Array = []               # [направление, радиус (доля), скорость, цвет, толщина]
var _rng := RandomNumberGenerator.new()
var _done: bool = false
var _glow: GradientTexture2D           # мягкий свет вспышки (draw_circle — резкий край)

static func start(parent: Control, done: Callable) -> void:
	if DisplayServer.get_name() == "headless":
		done.call()
		return
	var l = load("res://scenes/menu/MenuLaunch.gd").new()
	l.on_done = done
	parent.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # меню во время взлёта не нажать
	material = Vfx.mix_material()   # лучи, разрыв варпа, затемнение — пиксельно, как эффекты боя (12.11.2026)
	_rng.seed = 77
	var colors := [Palette.LAUNCH_ASH, Palette.LAUNCH_ASH, Palette.LAUNCH_ASH, Palette.LAUNCH_EMBER]
	for i in STREAKS:
		var ang := _rng.randf() * TAU
		_streaks.append([Vector2(cos(ang), sin(ang)), _rng.randf_range(0.02, 0.7), _rng.randf_range(0.6, 1.4),
			colors[_rng.randi() % colors.size()], 1.0 if _rng.randf() < 0.8 else 2.0])
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 0.55))
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(0.5, 0.0)
	AudioManager.play("launch")

func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION and not _done:
		_done = true
		on_done.call()
	queue_redraw()

func _draw() -> void:
	var k := clampf(_t / DURATION, 0.0, 1.0)
	var c := size * CENTER
	var diag := size.length()
	var accel := k * k * k                       # разгон: сначала тихо, к прыжку — лучи через весь экран
	var appear := smoothstep(0.08, 0.35, k)
	for s in _streaks:
		var r: float = fmod(s[1] + accel * STREAK_SPEED * s[2], 1.2)
		var head: Vector2 = c + s[0] * r * diag
		var length: float = (0.004 + accel * 0.22 * s[2]) * diag
		var tail: Vector2 = head - s[0] * minf(length, r * diag)
		var a := appear * clampf(r * 4.0, 0.0, 1.0) * 0.6
		draw_line(tail, head, Color(s[3], a * 0.25), s[4] + 2.0)   # ореол
		draw_line(tail, head, Color(s[3], a), s[4])
	# вспышка прыжка — холодный свет из точки прыжка на весь экран
	var ft := (_t - FLASH_AT * DURATION) / FLASH_TIME
	if ft > 0.0 and ft < 1.0:
		var fa := sin(ft * PI)
		# разрыв варпа: мутное пятно бордо-фиолета раскрывается из точки прыжка, экран темнеет вокруг
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.BG_DEEP, fa * 0.45))
		var r := diag * 0.55 * (0.35 + ft)
		draw_texture_rect(_glow, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(Palette.WARP_RIFT, fa * 0.95))
		var rc := r * 0.4
		draw_texture_rect(_glow, Rect2(c - Vector2(rc, rc), Vector2(rc, rc) * 2.0), false, Color(Palette.WARP_RIFT_CORE, fa * 0.7))
	# затемнение к концу — дальше чёрная шторка RunManager._go
	var black := smoothstep(BLACK_FROM, 1.0, k)
	if black > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.BG_DEEP, black))
