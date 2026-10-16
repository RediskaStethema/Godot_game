class_name ExpansionBanner
extends Control

# Объявление этапа расширения королевства (решение пользователя): экран в конце боя перед волной,
# на расстановке которой продаются клетки, — ещё до магазина, чтобы игрок успел отложить Req.
# Затемнение на весь экран, по центру «Пришло время расширяться», цена клетки и кнопка
# «В МАГАЗИН» (перед событием — «ДАЛЕЕ»); дальше — по кнопке (BattleScene._announce_expansion).

signal closed

const FADE_TIME: float = 0.35
const PANEL_WIDTH: float = 560.0
const DIM = Color(0, 0, 0, 0.55)

var button: Button
var _closing: bool = false

func setup(tile_cost: int, button_text: String = "В МАГАЗИН") -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # поле под затемнением не кликается
	theme = UITheme.get_theme()

	var dim = ColorRect.new()
	dim.color = DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel = UITheme.make_panel("HudPanel")
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	center.add_child(panel)
	var col = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	for line in [["ПРИШЛО ВРЕМЯ РАСШИРЯТЬСЯ", "TitleLabel"],
			["На расстановке следующей волны можно купить клетки рядом с королевством — от %d Req." % tile_cost, "ValueLabel"],
			["Отложите Req в магазине. Новый ряд впереди меняет передний ряд и его бонус", "DimLabel"]]:
		var l = UITheme.make_label(line[0], line[1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
	button = UITheme.make_button(button_text, "PrimaryButton", close)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(220, 0)
	col.add_child(button)

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_TIME)

func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
