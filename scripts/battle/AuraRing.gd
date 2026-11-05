class_name AuraRing
extends Node2D

# Аура на земле в бою — тонкое кольцо по радиусу действия, кодом (решение пользователя 23.10.2026: кольца листов
# пакета banner_aura / aura_plague / aura_pleasure — тусклые, мутные от растяжки, срезаны краем кадра, символы
# прыгали по кругу). Линия в пиксель с мягким ореолом, по кругу медленно бегут огоньки. Радиус — ровно
# радиус механики (расстояние в px мира — круг, как круг зоны здания на расстановке). Только вид.
#   follow_squad(отряд, радиус, вид) — аура знамени: идёт за центром живых бойцов, отряд пал — гаснет
#   at(точка, радиус, вид) — аура здания на его месте
# Слой — земля поля (layer: IsoGridRenderer, ставит BattleScene._build_field): под бойцами и постройками.
# Конец боя — гаснет сама; снять раньше — dismiss().

const FADE_IN: float = 0.5
const FADE_OUT: float = 0.4
# Мигание (решение пользователя 23.10.2026: «знамя мигает»): «дыхание» яркостью убрано, огоньки — без округления
# до пикселя (прыгали), кольцо знамени идёт за центром отряда плавно (FOLLOW_RATE) и после хода бойцов
# (process_priority: в кадр тика бойцы стоят в логической позиции на шаг впереди — кольцо скакало)
const FOLLOW_RATE: float = 8.0     # 1/с — догоняет центр отряда (боец пал — центр сдвигается скачком)
const RUN_PERIOD: float = 9.0      # огонёк обходит кольцо, сек
const SEGMENTS: int = 72
const LINE_ALPHA: float = 0.75
const GLOW = [[5.0, 0.10], [10.0, 0.04]]   # ореол линии: ширина, прозрачность
const FILL_ALPHA: float = 0.035            # заливка зоны — едва заметно
# Виды: кромка, ядро (огоньки), огоньков
const LOOKS = {
	"banner":       {"edge": Palette.GOLD, "core": Palette.GOLD_PALE, "motes": 4},
	"banner_chaos": {"edge": Palette.RED_BRIGHT, "core": Palette.FIRE, "motes": 4},
	"plague":       {"edge": Palette.POISON_DEEP, "core": Palette.POISON, "motes": 5},
	"pleasure":     {"edge": Palette.SLAANESH, "core": Palette.SLAANESH_PALE, "motes": 5},
}

static var layer: Node2D = null
static var _add: CanvasItemMaterial

var radius := 160.0
var look := "banner"
var squad: Node2D = null       # за кем идёт (аура знамени); null — стоит на месте
var _t := 0.0
var _dismiss_left := -1.0
var _seen_battle := false

static func follow_squad(target: Node2D, r: float, kind: String) -> AuraRing:
	var a := _make(r, kind, target)
	if a and is_instance_valid(target):
		a.global_position = a._squad_center()
	return a

static func at(point: Vector2, r: float, kind: String) -> AuraRing:
	var a := _make(r, kind, null)
	if a:
		a.global_position = point
	return a

static func _make(r: float, kind: String, target: Node2D) -> AuraRing:
	var parent: Node2D = layer if is_instance_valid(layer) else target
	if parent == null or r <= 0.0:
		return null
	var a := AuraRing.new()
	a.radius = r
	a.look = kind if LOOKS.has(kind) else "banner"
	a.squad = target
	if _add == null:
		_add = CanvasItemMaterial.new()
		_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	a.material = _add
	a.process_priority = 1
	parent.add_child(a)
	return a

func dismiss() -> void:
	if _dismiss_left < 0.0:
		_dismiss_left = FADE_OUT

func _process(delta: float) -> void:
	_t += delta
	if BattleManager.is_battle_running():
		_seen_battle = true
	elif _seen_battle:
		dismiss()   # итог боя — аура гаснет
	if squad != null:
		if not is_instance_valid(squad) or not squad.is_alive():
			squad = null
			dismiss()
		else:
			global_position = global_position.lerp(_squad_center(), 1.0 - exp(-FOLLOW_RATE * delta))
	if _dismiss_left >= 0.0:
		_dismiss_left -= delta
		if _dismiss_left <= 0.0:
			queue_free()
			return
	queue_redraw()

# Центр живых бойцов отряда (отряд стоит на клетке, бойцы уходят с неё)
func _squad_center() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for s in squad.soldiers:
		if is_instance_valid(s) and s.current_state != s.State.DEAD:
			sum += s.global_position
			n += 1
	return sum / n if n > 0 else squad.global_position

func _alpha() -> float:
	var a := minf(_t / FADE_IN, 1.0)
	if _dismiss_left >= 0.0:
		a *= _dismiss_left / FADE_OUT
	return a

func _draw() -> void:
	var l: Dictionary = LOOKS[look]
	var a := _alpha()
	if a <= 0.0:
		return
	var edge: Color = l["edge"]
	var core: Color = l["core"]
	draw_circle(Vector2.ZERO, radius, Color(edge, FILL_ALPHA * a))
	for g in GLOW:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, SEGMENTS, Color(edge, g[1] * a), g[0])
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, SEGMENTS, Color(edge, LINE_ALPHA * a), 1.0, true)
	# Огоньки бегут по кругу с коротким хвостом
	var n: int = l["motes"]
	for i in n:
		var base := TAU * (float(i) / n + _t / RUN_PERIOD)
		for k in 4:
			var ang := base - k * 0.035
			var p := Vector2(cos(ang), sin(ang)) * radius
			var s := 3.0 if k == 0 else 2.0
			draw_circle(p, s * 0.5, Color(core if k == 0 else edge, a * (1.0 - k * 0.25)), true, -1.0, true)
