class_name ButtonVolume
extends Control

# Объёмная кнопка (решение пользователя 12.11.2026, «единая шапка и кнопки», «отклик интерфейса»): у кнопки
# литое основание — боковая грань тёмной латуни с заклёпками и мягкая тень (рисует этот узел за кнопкой,
# show_behind_parent), на крышке — блик сверху и тень снизу (Sheen поверх). Отклик: наведение — кнопка
# приподнимается на lift и светлее, нажатие — уходит в основание на SINK (грань короче), неактивная — без
# отклика. Работает и в контейнерах: смещение кнопки — поверх раскладки, после пересортировки контейнера
# возвращается само. Только вид.
#   ButtonVolume.attach(кнопка, глубина, подъём)

const SINK: float = 4.0
const EASE: float = 22.0          # скорость перехода к цели, 1/с
const HOVER_BRIGHT: float = 1.08

var button: Button
var depth: float = 8.0
var lift: float = 2.0
var _cur: float = 0.0             # смещение крышки: < 0 — приподнята, > 0 — нажата
var _applied: float = 0.0         # сколько уже прибавлено к position.y кнопки

static func attach(b: Button, depth_px: float = 8.0, lift_px: float = 2.0) -> ButtonVolume:
	for c in b.get_children():
		if c is ButtonVolume:
			return c
	var v := ButtonVolume.new()
	v.button = b
	v.depth = depth_px
	v.lift = lift_px
	v.show_behind_parent = true
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sheen := Sheen.new()
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(sheen)
	sheen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return v

# Кнопка уже в дереве (можно навесить до add_child кнопки в окно): контейнер расставил её заново — смещение снято
func _ready() -> void:
	var parent := button.get_parent()
	if parent is Container and not parent.sort_children.is_connected(_on_sorted):
		parent.sort_children.connect(_on_sorted)

func _on_sorted() -> void:
	_applied = 0.0

func _process(delta: float) -> void:
	if not is_instance_valid(button):
		return
	var target := 0.0
	if not button.disabled:
		if button.get_draw_mode() in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED]:
			target = SINK
		elif button.is_hovered():
			target = -lift
	_cur = move_toward(_cur, target, EASE * delta * maxf(SINK, lift) * 2.0)
	if absf(_cur - _applied) > 0.01:
		button.position.y += _cur - _applied
		_applied = _cur
	button.self_modulate = Color(HOVER_BRIGHT, HOVER_BRIGHT, HOVER_BRIGHT) if target < 0.0 else Color.WHITE
	queue_redraw()

# Основание: тень вправо-вниз и боковая грань от низа крышки до низа основания (нажатая — грань короче)
func _draw() -> void:
	if not is_instance_valid(button) or not button.visible:
		return
	var w := size.x
	var top := size.y - 2.0
	var bottom := size.y + depth - _cur
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0.35)
	sh.set_corner_radius_all(3)
	sh.corner_detail = 1
	sh.shadow_color = Color(0, 0, 0, 0.28)
	sh.shadow_size = 5
	draw_style_box(sh, Rect2(Vector2(5.0, 6.0 - _cur), Vector2(w - 4.0, bottom - 6.0 + _cur - 4.0)))
	if bottom - top <= 0.5:
		return
	var side := Rect2(Vector2(2.0, top), Vector2(w - 4.0, bottom - top))
	draw_rect(side, Palette.SHOP_FRAME_DARK)
	draw_rect(Rect2(side.position, Vector2(side.size.x, side.size.y * 0.5)), Color(Palette.SHOP_FRAME, 0.45))
	draw_rect(Rect2(side.position, Vector2(side.size.x, minf(2.0, side.size.y))), Palette.SHOP_FRAME_LIGHT)
	draw_rect(Rect2(Vector2(side.position.x, side.end.y - 2.0), Vector2(side.size.x, 2.0)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(side.position, Vector2(2.0, side.size.y)), Palette.SHOP_FRAME)
	draw_rect(Rect2(Vector2(side.end.x - 2.0, side.position.y), Vector2(2.0, side.size.y)), Color(0, 0, 0, 0.5))
	if side.size.y >= 5.0:   # заклёпки
		var y := side.position.y + side.size.y / 2.0
		var x := side.position.x + 12.0
		while x < side.end.x - 8.0:
			draw_rect(Rect2(Vector2(x - 1.0, y - 1.0), Vector2(2.0, 2.0)), Palette.SHOP_FRAME_LIGHT)
			x += 24.0

# Объём крышки: блик по верхней трети, тень по нижней четверти (поверх рисунка кнопки, мышь не ловит)
class Sheen extends Control:
	func _draw() -> void:
		var h := size.y
		var steps := 6
		for i in steps:
			var f := float(i) / steps
			draw_rect(Rect2(Vector2(4.0, 4.0 + h * 0.32 * f), Vector2(size.x - 8.0, h * 0.32 / steps)),
				Color(1.0, 0.9, 0.7, 0.14 * (1.0 - f)))
			draw_rect(Rect2(Vector2(4.0, h - 4.0 - h * 0.25 * (f + 1.0 / steps)), Vector2(size.x - 8.0, h * 0.25 / steps)),
				Color(0, 0, 0, 0.26 * (1.0 - f)))
