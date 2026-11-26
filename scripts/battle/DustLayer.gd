class_name DustLayer
extends Node2D

# Пыль из-под ног (решение пользователя 08.11.2026, только вид): низкие клубы на земле — шаг бега (тяжёлые — каждый
# шаг, пехота — каждый INFANTRY_EVERY-й), построение, приземление прыжка, высадка Deep Strike. Один слой под
# отрядами (как SoldierShadows): мягкое пятно одной текстурой — пакет отрисовки не рвётся. Цвет — ключ темы
# "dust" (Color, альфа — плотность). Лимит живых MAX_ALIVE и за кадр MAX_PER_FRAME; своя случайность (не randf —
# он общий со случайностью боя); выключается GameSettings.atmosphere

const MAX_ALIVE: int = 140
const MAX_PER_FRAME: int = 12
const LIFE: float = 0.75          # сек жизни клуба
const GROW: float = 1.8           # во сколько раз клуб расползается к концу
const RISE: float = 4.0           # px: клуб чуть поднимается
const INFANTRY_EVERY: int = 2     # пехота пылит каждым 2-м шагом (17.11.2026: было 3-м — шаг виден на земле)
const FLATTEN: float = 0.5        # пятно на земле — эллипс 2:1, как клетка изометрии

static var layer: DustLayer = null
static var _tex: GradientTexture2D

var color: Color = Palette.DUST
var _puffs: Array = []            # [точка, радиус, возраст, снос]
var _this_frame: int = 0
var _rng := RandomNumberGenerator.new()

func setup(theme: Dictionary) -> void:
	color = theme.get("dust", Color(Palette.DUST, 0.3))
	_rng.seed = 7
	layer = self
	material = Vfx.mix_material()   # пыль пиксельная: прозрачность ступенями с дизерингом (shaders/fx_pixel)

func _exit_tree() -> void:
	if layer == self:
		layer = null

# Клубы у точки: count штук радиусом ~r px мира, разлёт spread px
static func puff(at: Vector2, r: float, count: int = 1, spread: float = 3.0) -> void:
	if layer == null or not GameSettings.atmosphere:
		return
	layer._add(at, r, count, spread)

func _add(at: Vector2, r: float, count: int, spread: float) -> void:
	for i in count:
		if _puffs.size() >= MAX_ALIVE or _this_frame >= MAX_PER_FRAME:
			return
		_this_frame += 1
		var off := Vector2(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread) * FLATTEN)
		var drift := Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-2.0, 1.0))
		_puffs.append([to_local(at) + off, r * _rng.randf_range(0.8, 1.2), 0.0, drift])

func _process(delta: float) -> void:
	_this_frame = 0
	if _puffs.is_empty():
		return
	for p in _puffs:
		p[2] += delta
	_puffs = _puffs.filter(func(p): return p[2] < LIFE)
	queue_redraw()

func _draw() -> void:
	if _tex == null:
		var g := Gradient.new()
		g.set_color(0, Color.WHITE)
		g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		g.add_point(0.45, Color(1.0, 1.0, 1.0, 0.5))
		_tex = GradientTexture2D.new()
		_tex.gradient = g
		_tex.fill = GradientTexture2D.FILL_RADIAL
		_tex.fill_from = Vector2(0.5, 0.5)
		_tex.fill_to = Vector2(0.5, 0.0)
		_tex.width = 64
		_tex.height = 64
	for p in _puffs:
		var t: float = p[2] / LIFE
		var r: float = p[1] * lerpf(1.0, GROW, 1.0 - (1.0 - t) * (1.0 - t))
		var at: Vector2 = p[0] + p[3] * t - Vector2(0.0, RISE * t)
		var col := color
		col.a *= (1.0 - t) * minf(t * 6.0, 1.0)   # быстро проявляется, долго тает
		draw_texture_rect(_tex, Rect2(at - Vector2(r, r * FLATTEN), Vector2(r * 2.0, r * 2.0 * FLATTEN)), false, col)
