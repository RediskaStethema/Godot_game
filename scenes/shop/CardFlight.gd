class_name CardFlight
extends Control

# Купленная карта летит из слота магазина в руку (EFFECTS_NEEDED 9.1, 06.11.2026 — кодом, без листа художника):
# лицо карты по дуге вверх и вниз к своему месту в руке, сжимается до карты руки, за ней — янтарный след
# (ADD, тает по длине); карта руки проявляется, когда долетела (вспышка светом). Только вид, мышь не ловит.
#   CardFlight.fly(родитель, карта, прямоугольник лица в слоте, узел карты в руке)

const DURATION: float = 0.45       # сек полёта
const ARC: float = 0.35            # подъём дуги — доля пути (не меньше ARC_MIN px)
const ARC_MIN: float = 60.0
const TRAIL_LIFE: float = 0.22     # сек: сколько живёт точка следа
const TRAIL_WIDTH: float = 26.0    # px у головы следа (ореол; ядро — уже)
const LAND_FLASH: float = 1.8      # яркость карты руки в миг прилёта
const LAND_TIME: float = 0.25      # сек: вспышка гаснет
const TRAIL_COLOR := Palette.AMBER_LIGHT
const TRAIL_CORE := Palette.GOLD_BRIGHT

var _face: Control
var _trail: Control
var _target: Control
var _from: Rect2
var _to: Rect2
var _t: float = 0.0
var _landed: bool = false
var _points: Array = []   # [позиция, возраст]

static func fly(parent: Node, card: CardData, from_rect: Rect2, target: Control) -> CardFlight:
	var f := CardFlight.new()
	f._from = from_rect
	f._target = target
	parent.add_child(f)
	f._build(card)
	return f

func _build(card: CardData) -> void:
	top_level = true
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_trail = Control.new()
	_trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail.material = add
	_trail.draw.connect(_draw_trail)
	add_child(_trail)
	_face = UITheme.make_card_face(card, _from.size.x) if UITheme.has_card_art(card) else _plain_face(card)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)
	_face.size = _face.custom_minimum_size
	_face.pivot_offset = _face.size / 2.0
	if is_instance_valid(_target):
		_target.modulate.a = 0.0   # карта руки — когда долетит
	_place(0.0)

# Нет арта — простая плашка цвета редкости с названием
func _plain_face(card: CardData) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.card_style(card.rarity))
	p.custom_minimum_size = _from.size
	var l := UITheme.make_label(card.title, "HeaderLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	p.add_child(l)
	return p

func _process(delta: float) -> void:
	for p in _points:
		p[1] += delta
	_points = _points.filter(func(p): return p[1] < TRAIL_LIFE)
	if not _landed:
		if is_instance_valid(_target):
			_to = _target.get_global_rect()   # ряд руки раскладывается после покупки — цель берётся каждый кадр
		_t = minf(_t + delta / DURATION, 1.0)
		_place(_t)
		if _t >= 1.0:
			_land()
	_trail.queue_redraw()
	if _landed and _points.is_empty():
		queue_free()

func _place(t: float) -> void:
	var to := _to if _to.size != Vector2.ZERO else _from
	var e := t * t * (3.0 - 2.0 * t)   # плавно в начале и в конце
	var a := _from.get_center()
	var b := to.get_center()
	var lift := maxf(a.distance_to(b) * ARC, ARC_MIN)
	var c := (a + b) / 2.0 - Vector2(0.0, lift)
	var pos := a.lerp(c, e).lerp(c.lerp(b, e), e)   # квадратичная кривая Безье
	var k := lerpf(1.0, minf(to.size.x / maxf(_face.size.x, 1.0), to.size.y / maxf(_face.size.y, 1.0)), e)
	_face.scale = Vector2(k, k)
	_face.position = pos - _face.size / 2.0
	_face.rotation = sin(e * PI) * -0.18   # наклон по ходу дуги
	if t > 0.0:
		_points.append([pos, 0.0])

func _land() -> void:
	_landed = true
	_face.queue_free()
	if is_instance_valid(_target):
		_target.modulate = Color(LAND_FLASH, LAND_FLASH, LAND_FLASH, 1.0)
		_target.create_tween().tween_property(_target, "modulate", Color.WHITE, LAND_TIME)

func _draw_trail() -> void:
	for i in range(1, _points.size()):
		var a: Array = _points[i - 1]
		var b: Array = _points[i]
		var life: float = 1.0 - b[1] / TRAIL_LIFE
		var w: float = TRAIL_WIDTH * life * (float(i) / _points.size())
		_trail.draw_line(a[0], b[0], Color(TRAIL_COLOR, 0.18 * life), w)          # ореол
		_trail.draw_line(a[0], b[0], Color(TRAIL_COLOR, 0.45 * life), w * 0.5)
		_trail.draw_line(a[0], b[0], Color(TRAIL_CORE, 0.9 * life), w * 0.2)      # ядро
		_trail.draw_circle(b[0], w * 0.25, Color(TRAIL_CORE, 0.35 * life))        # стыки без зазоров

# Сцена ушла посреди полёта (В БОЙ) — карта руки не должна остаться невидимой
func _exit_tree() -> void:
	if not _landed and is_instance_valid(_target):
		_target.modulate = Color.WHITE
