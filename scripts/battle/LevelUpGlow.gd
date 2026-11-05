class_name LevelUpGlow
extends Node2D

# Уровень отряда на каждом бойце (решение пользователя 22.10.2026: столб пакета на клетку — обрезанный и
# неестественный): у ног расходится кольцо, сквозь бойца поднимается свет с искрами, над головой всплывают
# шевроны — их столько, каков новый уровень. Бойцы загораются волной (WAVE по номеру в отряде).
# Рисуется кодом в пикселях мира — обрезаться негде. Двигается с бойцом (ребёнок). Только вид.
#   play(боец, уровень, сдвиг, вид) — кольцо за спрайтом, свет и шевроны перед ним; вид "heal" — Казармы
#   вылечили / пополнили отряд (решение пользователя 22.10.2026: лист пакета refill — яркий, крупный, обрезанный):
#   зелёный свет и крестик вместо шевронов (Святилище Хаоса — бордо без крестика); вид "arrive" — отряд встал с
#   карты (вместо столба телепорта / разлома варпа пакета): холодный свет телепорта без знака, у Хаоса — бордо

const DURATION: float = 1.0
const WAVE: float = 0.35          # сдвиг последнего бойца отряда, сек
const RING_TIME: float = 0.55
const PILLAR_TIME: float = 0.65
const CHEVRON_FROM: float = 0.2   # шевроны появляются (доля DURATION не нужна — секунды)
const CHEVRON_STEP: float = 0.08  # следующий шеврон — позже
const CHEVRON_RISE: float = 7.0   # px за время жизни
const MOTES: int = 4
# Цвета: кромка, ядро (Космодесант — золото, Хаос — бордо в огонь, как в ТЗ 2.1)
const COLORS = {
	"space_marines": [Palette.GOLD, Palette.GOLD_PALE],
	"chaos": [Palette.RED_BRIGHT, Palette.FIRE],
}
const HEAL_COLORS = [Palette.HEAL_DEEP, Palette.HEAL]
const ARRIVE_COLORS = [Palette.SHIELD_BLUE, Palette.GOLD_PALE]   # телепорт Космодесанта — холодный свет

static var _add: CanvasItemMaterial

var level := 2
var kind := "level"   # "level" — шевроны по уровню, "heal" — крестик лечения
var ground := false
var _delay := 0.0
var _t := 0.0
var _h := 31.0          # рост бойца, px
var _edge := Palette.GOLD
var _core := Palette.GOLD_PALE
var _seed := 0

static func play(soldier: Node2D, new_level: int, stagger: float, glow_kind: String = "level") -> void:
	for is_ground in [true, false]:
		var g := LevelUpGlow.new()
		g.level = new_level
		g.kind = glow_kind
		g.ground = is_ground
		g._delay = stagger * WAVE
		g._h = Soldier.TARGET_SPRITE_HEIGHT * soldier.data.sprite_scale
		var c: Array = COLORS.get(soldier.data.faction, COLORS["space_marines"])
		if glow_kind == "heal" and soldier.data.faction != "chaos":
			c = HEAL_COLORS
		elif glow_kind == "arrive" and soldier.data.faction != "chaos":
			c = ARRIVE_COLORS
		g._edge = c[0]
		g._core = c[1]
		g._seed = soldier.get_instance_id()
		if _add == null:
			_add = CanvasItemMaterial.new()
			_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		g.material = _add
		soldier.add_child(g)
		if is_ground:
			soldier.move_child(g, 0)   # дети рисуются по порядку: первым — за спрайтом

func _process(delta: float) -> void:
	_t += delta
	if _t - _delay >= DURATION:
		queue_free()
		return
	queue_redraw()

func _rand(i: int) -> float:
	return fmod(sin(float(_seed % 9973 + i * 17) * 12.9898) * 43758.5453, 1.0) * 0.5 + 0.5

func _draw() -> void:
	var t := _t - _delay
	if t <= 0.0:
		return
	var w := _h * 0.6
	if ground:
		_draw_ring(t, w)
	else:
		_draw_pillar(t, w)
		_draw_motes(t, w)
		if kind == "heal":
			if _edge == Palette.HEAL_DEEP:
				_draw_cross(t)
		elif kind == "level":
			_draw_chevrons(t)

# Кольцо у ног: из точки расходится изометрический эллипс и гаснет (в плотном строю — не шире бойца)
func _draw_ring(t: float, w: float) -> void:
	if t >= RING_TIME:
		return
	var k := t / RING_TIME
	var r := lerpf(0.2, 0.7, 1.0 - pow(1.0 - k, 3.0)) * w
	var pts := PackedVector2Array()
	for i in 21:
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a) * r, sin(a) * r * 0.5).round())
	draw_polyline(pts, Color(_edge, 0.7 * (1.0 - k)), 1.0)

# Свет на бойце: мягкий ореол вокруг фигуры и свет, поднимающийся от ног и тающий кверху
func _draw_pillar(t: float, w: float) -> void:
	if t >= PILLAR_TIME:
		return
	var k := t / PILLAR_TIME
	var fade := sin(k * PI)
	for i in 4:   # ореол — концентрические пятна, к краю прозрачнее
		var r := w * (0.35 + 0.15 * i)
		draw_circle(Vector2(0, roundf(-_h * 0.5)), r, Color(_edge, fade * 0.07))
	var half := roundf(w * lerpf(0.4, 0.2, k))
	var top := _h * lerpf(0.5, 1.4, minf(k * 1.6, 1.0))
	var steps := 7
	for i in steps:   # ступенями снизу вверх, к верху гаснет
		var y1 := -top * i / steps
		var a := fade * pow(1.0 - float(i) / steps, 1.5) * 0.22
		draw_rect(Rect2(-half, roundf(y1 - top / steps), half * 2.0, ceilf(top / steps)), Color(_core, a))

# Искры поднимаются от ног выше головы, покачиваясь
func _draw_motes(t: float, w: float) -> void:
	for i in MOTES:
		var start := _rand(i) * 0.3
		var life := (t - start) / 0.7
		if life <= 0.0 or life >= 1.0:
			continue
		var x := (_rand(i + 50) - 0.5) * w + sin(life * TAU + i) * 2.0
		var y := -_rand(i + 90) * _h * 0.4 - life * _h * 1.1
		draw_rect(Rect2(Vector2(x, y).round(), Vector2(1.5, 1.5)), Color(_core, 1.0 - life))

# Крестик лечения над головой: всплывает и гаснет
func _draw_cross(t: float) -> void:
	var life := (t - CHEVRON_FROM) / (DURATION - CHEVRON_FROM)
	if life <= 0.0 or life >= 1.0:
		return
	var a := minf(life * 6.0, 1.0) * (1.0 - smoothstep(0.6, 1.0, life))
	var c := Vector2(0.0, roundf(-_h - 6.0 - life * CHEVRON_RISE))
	draw_rect(Rect2(c + Vector2(-1, -3), Vector2(2, 6)), Color(_core, a))
	draw_rect(Rect2(c + Vector2(-3, -1), Vector2(6, 2)), Color(_core, a))

# Шевроны «^» над головой: столько, каков уровень; всплывают и гаснут
func _draw_chevrons(t: float) -> void:
	for i in level:
		var s := t - CHEVRON_FROM - i * CHEVRON_STEP
		var life := s / (DURATION - CHEVRON_FROM - (level - 1) * CHEVRON_STEP)
		if life <= 0.0 or life >= 1.0:
			continue
		var a := minf(life * 6.0, 1.0) * (1.0 - smoothstep(0.6, 1.0, life))
		var y := roundf(-_h - 5.0 - i * 4.0 - life * CHEVRON_RISE)
		var pts := PackedVector2Array([Vector2(-4, y + 3), Vector2(0, y), Vector2(4, y + 3)])
		draw_polyline(pts, Color(_edge, a), 2.0)
		draw_polyline(pts, Color(_core, a * 0.8), 1.0)
