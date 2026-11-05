class_name BuildingLevelUp
extends Node2D

# Улучшение здания (решение пользователя 26.10.2026: «при lvlup должен быть эффект — свечение или что ещё»).
# Здание (Building.play_level_up) вспыхивает белым — под вспышкой меняются кадры уровня — и с пружинкой
# вырастает до нового роста; этот узел — свет вокруг: от основания по земле расходятся два кольца, сквозь
# здание поднимается столб света с искрами, над крышей всплывают шевроны — их столько, каков новый уровень.
# Цвета — как у уровня отряда (LevelUpGlow.COLORS: Космодесант — золото, Хаос — бордо в огонь). Рисуется
# кодом в пикселях мира, ребёнок здания. Только вид
#   play(здание, уровень, рост px, раса) — кольца за спрайтом, свет и шевроны перед ним

const DURATION: float = 1.4
const RING_TIME: float = 0.7
const RING_DELAY: float = 0.15       # второе кольцо — позже
const PILLAR_TIME: float = 0.9
const CHEVRON_FROM: float = 0.3
const CHEVRON_STEP: float = 0.1
const CHEVRON_RISE: float = 14.0     # px за время жизни
const CHEVRON_SIZE: float = 8.0
const MOTES: int = 16
const PILLAR_BANDS: int = 4       # столб света поперёк: столько вложенных полос — мягкий край
const WIDTH: float = 0.8             # ширина света — доля клетки (как спрайт здания, Building.SPRITE_WIDTH)

static var _add: CanvasItemMaterial

var level := 2
var ground := false
var _t := 0.0
var _h := 100.0         # рост здания над основанием, px мира
var _w := 100.0
var _edge := Palette.GOLD
var _core := Palette.GOLD_PALE
var _seed := 0

static func play(building: Node2D, new_level: int, height: float, faction: String) -> void:
	var c: Array = LevelUpGlow.COLORS.get(faction, LevelUpGlow.COLORS["space_marines"])
	if _add == null:
		_add = CanvasItemMaterial.new()
		_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for is_ground in [true, false]:
		var g := BuildingLevelUp.new()
		g.level = new_level
		g.ground = is_ground
		g._h = height
		g._w = IsoGrid.TILE_WIDTH * WIDTH
		g._edge = c[0]
		g._core = c[1]
		g._seed = building.get_instance_id()
		g.material = _add
		building.add_child(g)
		if is_ground:
			building.move_child(g, 0)   # дети рисуются по порядку: первым — за спрайтом

func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		queue_free()
		return
	queue_redraw()

func _rand(i: int) -> float:
	return fmod(sin(float(_seed % 9973 + i * 17) * 12.9898) * 43758.5453, 1.0) * 0.5 + 0.5

func _draw() -> void:
	if ground:
		_draw_ground(_t)
		_draw_ground(_t - RING_DELAY)
	else:
		_draw_pillar(_t)
		_draw_motes(_t)
		_draw_chevrons(_t)

# По земле от основания: пятно света и расходящееся изометрическое кольцо (эллипс 2:1)
func _draw_ground(t: float) -> void:
	if t <= 0.0 or t >= RING_TIME:
		return
	var k := t / RING_TIME
	var r := lerpf(0.25, 0.8, 1.0 - pow(1.0 - k, 3.0)) * _w
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, r * 0.8, Color(_core, 0.1 * (1.0 - k)))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(_edge, 0.75 * (1.0 - k)), 3.0)
	draw_set_transform(Vector2.ZERO)

# Сквозь здание: ореол и свет, поднимающийся от основания выше крыши и тающий кверху
func _draw_pillar(t: float) -> void:
	if t >= PILLAR_TIME:
		return
	var k := t / PILLAR_TIME
	var fade := sin(k * PI)
	for i in 4:   # ореол — концентрические пятна, к краю прозрачнее
		draw_circle(Vector2(0, roundf(-_h * 0.45)), _w * (0.3 + 0.12 * i), Color(_edge, fade * 0.06))
	var half := roundf(_w * lerpf(0.42, 0.18, k))
	var top := _h * lerpf(0.4, 1.35, minf(k * 1.5, 1.0))
	var steps := 10
	for i in steps:   # ступенями снизу вверх, к верху гаснет; поперёк — вложенные полосы, к краям гаснет
		var y1 := -top * i / steps
		var a := fade * pow(1.0 - float(i) / steps, 1.4) * 0.24 / PILLAR_BANDS
		for b in PILLAR_BANDS:
			var hw := roundf(half * (1.0 - float(b) / PILLAR_BANDS))
			draw_rect(Rect2(-hw, roundf(y1 - top / steps), hw * 2.0, ceilf(top / steps)), Color(_core, a))

# Искры поднимаются от основания выше крыши, покачиваясь
func _draw_motes(t: float) -> void:
	for i in MOTES:
		var start := _rand(i) * 0.5
		var life := (t - start) / 0.8
		if life <= 0.0 or life >= 1.0:
			continue
		var x := (_rand(i + 50) - 0.5) * _w + sin(life * TAU + i) * 4.0
		var y := -_rand(i + 90) * _h * 0.5 - life * _h * 0.9
		var s := 2.0 + floorf(_rand(i + 130) * 2.0)
		draw_rect(Rect2(Vector2(x, y).round(), Vector2(s, s)), Color(_core, 1.0 - life))

# Шевроны «^» над крышей: столько, каков уровень; всплывают и гаснут
func _draw_chevrons(t: float) -> void:
	for i in level:
		var s := t - CHEVRON_FROM - i * CHEVRON_STEP
		var life := s / (DURATION - CHEVRON_FROM - (level - 1) * CHEVRON_STEP)
		if life <= 0.0 or life >= 1.0:
			continue
		var a := minf(life * 6.0, 1.0) * (1.0 - smoothstep(0.6, 1.0, life))
		var y := roundf(-_h - 10.0 - i * CHEVRON_SIZE * 0.8 - life * CHEVRON_RISE)
		var pts := PackedVector2Array([Vector2(-CHEVRON_SIZE, y + CHEVRON_SIZE * 0.7), Vector2(0, y),
			Vector2(CHEVRON_SIZE, y + CHEVRON_SIZE * 0.7)])
		draw_polyline(pts, Color(_edge, a), 4.0)
		draw_polyline(pts, Color(_core, a * 0.8), 2.0)
