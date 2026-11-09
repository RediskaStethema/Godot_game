class_name ScarLayer
extends Node2D

# Шрамы поля (решение пользователя 09.11.2026: «поле показывает, где шла сеча»): подпалины от разрывов и пятна
# крови павших лежат на земле до конца боя. Один слой под тенями и отрядами (BattleScene._build_field), только вид.
#   scorch(точка, r) — подпалина: неровное тёмное пятно 2:1 с бурым краем, пара угольков тлеет и гаснет
#   blood(точка, r, цвет) — пятно крови павшего (цвет — Vfx.BLOOD_COLORS по UnitData.get_blood())
# Отрисовка одной командой (как звенья KingdomWall): все пятна — треугольники с цветом вершин в общих массивах,
# canvas_item_add_triangle_array; 09.11.2026 рисование пятен по одному (draw_colored_polygon) давало +500 вызовов
# отрисовки и 96 → 47 FPS в худшем бою (test_performance). Перерисовка — только когда добавилось пятно;
# угольки — в своём маленьком узле каждый кадр, пока тлеют. Не больше MAX_SCARS (лишние уходят пачкой TRIM),
# не больше MAX_PER_FRAME за кадр; своя случайность (не randf — он общий с боем); выключается GameSettings.atmosphere

const MAX_SCARS: int = 160
const TRIM: int = 16                 # сверх MAX_SCARS — старые уходят пачкой (пересборка массивов — раз на пачку)
const MAX_PER_FRAME: int = 6
const FLATTEN: float = 0.5           # лежит на земле — эллипс 2:1
const SCORCH_ALPHA: float = 0.55
const BLOOD_ALPHA: float = 0.5
const BLOOD_DARKEN: float = 0.35     # пятно темнее брызг: засохшая кровь на камне
const EMBER_TIME: float = 2.5        # с — угольки подпалины гаснут
const MAX_EMBERS: int = 60
const POINTS: int = 12               # вершин у неровного края
const INNER: float = 0.62            # ядро пятна — доля края
const DROP_POINTS: int = 6

static var layer: ScarLayer = null

var _scars: Array = []               # {p, poly, col, edge, alpha, drops} — p, вершины — в координатах слоя
var _pts := PackedVector2Array()     # все треугольники пятен
var _cols := PackedColorArray()
var _idx := PackedInt32Array()
var _embers: Array = []              # [точка, возраст, фаза]
var _ember_node: Node2D
var _this_frame: int = 0
var _rng := RandomNumberGenerator.new()

func setup() -> void:
	_rng.seed = 11
	layer = self
	_ember_node = Node2D.new()
	_ember_node.name = "Embers"
	_ember_node.draw.connect(_draw_embers)
	add_child(_ember_node)

func _exit_tree() -> void:
	if layer == self:
		layer = null

static func scorch(at: Vector2, r: float) -> void:
	if layer != null and GameSettings.atmosphere:
		layer._add(at, r, true, Palette.SCORCH)

static func blood(at: Vector2, r: float, col: Color) -> void:
	if layer != null and GameSettings.atmosphere:
		layer._add(at, r, false, col)

func count() -> int:
	return _scars.size()

func _add(at: Vector2, r: float, is_scorch: bool, col: Color) -> void:
	if _this_frame >= MAX_PER_FRAME or r <= 0.5:
		return
	_this_frame += 1
	var p := to_local(at)
	var scar := {"p": p, "poly": _blob(r), "drops": [],
		"col": col if is_scorch else col.darkened(BLOOD_DARKEN),
		"edge": Palette.SCORCH_EDGE if is_scorch else col.darkened(BLOOD_DARKEN + 0.25),
		"alpha": SCORCH_ALPHA if is_scorch else BLOOD_ALPHA}
	if is_scorch:
		for i in _rng.randi_range(2, 4):
			if _embers.size() < MAX_EMBERS:
				_embers.append([p + Vector2(_rng.randf_range(-r, r), _rng.randf_range(-r, r) * FLATTEN) * 0.6, 0.0,
					_rng.randf() * TAU])
	else:
		for i in _rng.randi_range(1, 3):   # брызги рядом с лужей
			var ang := _rng.randf() * TAU
			scar["drops"].append([Vector2(cos(ang), sin(ang) * FLATTEN) * r * _rng.randf_range(1.1, 1.6),
				r * _rng.randf_range(0.12, 0.25)])
	_scars.append(scar)
	if _scars.size() > MAX_SCARS + TRIM:
		_scars = _scars.slice(_scars.size() - MAX_SCARS)
		_rebuild()
	else:
		_append_mesh(scar)
	queue_redraw()

# Неровный край: окружность с шумом радиуса, сплющенная 2:1
func _blob(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rot := _rng.randf() * TAU
	for i in POINTS:
		var a := rot + TAU * i / POINTS
		pts.append(Vector2(cos(a), sin(a) * FLATTEN) * r * _rng.randf_range(0.7, 1.15))
	return pts

func _rebuild() -> void:
	_pts.clear()
	_cols.clear()
	_idx.clear()
	for s in _scars:
		_append_mesh(s)

# Пятно — веер треугольников: край полупрозрачный (edge), ядро плотнее (col); брызги — маленькие веера
func _append_mesh(s: Dictionary) -> void:
	var p: Vector2 = s["p"]
	var a: float = s["alpha"]
	_fan(p, s["poly"], 1.0, Color(s["edge"], a * 0.7))
	_fan(p, s["poly"], INNER, Color(s["col"], a))
	for d in s["drops"]:
		var ring := PackedVector2Array()
		for i in DROP_POINTS:
			var ang := TAU * i / DROP_POINTS
			ring.append(Vector2(cos(ang), sin(ang) * FLATTEN) * d[1])
		_fan(p + d[0], ring, 1.0, Color(s["col"], a))

func _fan(center: Vector2, ring: PackedVector2Array, k: float, col: Color) -> void:
	var base := _pts.size()
	_pts.append(center)
	_cols.append(col)
	for v in ring:
		_pts.append(center + v * k)
		_cols.append(col)
	var n := ring.size()
	for i in n:
		_idx.append(base)
		_idx.append(base + 1 + i)
		_idx.append(base + 1 + (i + 1) % n)

func _process(delta: float) -> void:
	_this_frame = 0
	if _embers.is_empty():
		return
	for e in _embers:
		e[1] += delta
	_embers = _embers.filter(func(e): return e[1] < EMBER_TIME)
	_ember_node.queue_redraw()

func _draw() -> void:
	if not _idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _pts, _cols)

func _draw_embers() -> void:
	for e in _embers:
		var glow: float = 1.0 - e[1] / EMBER_TIME
		var flick: float = 0.6 + 0.4 * sin(e[1] * 9.0 + e[2])
		_ember_node.draw_rect(Rect2(e[0] - Vector2(0.8, 0.8), Vector2(1.6, 1.6)),
			Color(Palette.SCORCH_EMBER, glow * glow * flick))
