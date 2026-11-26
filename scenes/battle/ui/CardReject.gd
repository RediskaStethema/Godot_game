class_name CardReject
extends Control

# Карта не сыграна (EFFECTS_NEEDED 1.6, кодом — решение пользователя 07.11.2026: лист пакета рисовал всю карту):
# отпустили над полем мимо сетки / на занятую клетку — карта вернулась в руку, по её рамке — красная вспышка и
# крестик-руна в центре, быстро гаснет; середина прозрачная — карта видна. Только вид, мышь не ловит.
#   CardReject.flash(карта руки)

const TIME: float = 0.4
const EDGE: float = 3.0          # px — кромка вспышки
const RUNE: float = 0.16         # полуразмер крестика — доля ширины карты

static var _add: CanvasItemMaterial
var _t := 0.0

# Без типа: узел карты мог освободиться до колбэка твина (как Bench._restore_hand_card)
static func flash(card) -> void:
	if not is_instance_valid(card):
		return
	AudioManager.play("card_reject")   # «заклинание не вышло»: звук вместе с красной вспышкой
	var f := CardReject.new()
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _add == null:
		_add = CanvasItemMaterial.new()
		_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	f.material = _add
	card.add_child(f)
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	_t += delta
	if _t >= TIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var k := _t / TIME
	var a := (1.0 - k) * (1.0 - k)
	var r := Rect2(Vector2.ZERO, size)
	for g in [[EDGE * 3.0, 0.18], [EDGE, 0.75]]:
		draw_rect(r.grow(-g[0] * 0.5), Color(Palette.RED, g[1] * a), false, g[0])
	draw_rect(r.grow(-EDGE * 0.5), Color(Palette.HIT_RED, a), false, 1.0)
	var c := size / 2.0
	var s := size.x * RUNE * (1.0 + 0.2 * k)
	for d in [Vector2(s, s), Vector2(s, -s)]:
		draw_line(c - d, c + d, Color(Palette.RED, 0.5 * a), 5.0, true)
		draw_line(c - d, c + d, Color(Palette.HIT_RED, a), 2.0, true)
