class_name ExpansionBanner
extends Control

# Объявление этапа расширения королевства (решение пользователя): на расстановке волны, когда
# можно покупать клетки (BattleManager.can_expand_kingdom), ниже королевства — «Пришло время
# расширяться» и цена клетки. Появляется плавно, держится SHOW_TIME с и гаснет; клик по
# баннеру — закрыть сразу. Клики мимо баннера проходят на поле (покупка клетки не ждёт).

signal closed

const FADE_TIME: float = 0.35
const SHOW_TIME: float = 3.5
const PANEL_WIDTH: float = 520.0
const BAND_TOP: float = 0.5      # полоса экрана (доли высоты), по центру которой стоит баннер
const BAND_BOTTOM: float = 0.72

var _panel: PanelContainer
var _tween: Tween

func setup(tile_cost: int) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.get_theme()

	# Ниже королевства, над скамейкой: зелёные клетки для покупки остаются видны
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.anchor_top = BAND_TOP
	center.anchor_bottom = BAND_BOTTOM
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = UITheme.make_panel("HudPanel")
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.gui_input.connect(_on_panel_input)
	center.add_child(_panel)

	var col = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)
	for line in [["ПРИШЛО ВРЕМЯ РАСШИРЯТЬСЯ", "TitleLabel"],
			["Клетки рядом с королевством — от %d Req. Кликните по зелёной клетке." % tile_cost, "ValueLabel"],
			["Новый ряд впереди меняет передний ряд и его бонус", "DimLabel"]]:
		var l = UITheme.make_label(line[0], line[1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)

	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_TIME)
	_tween.tween_interval(SHOW_TIME)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	_tween.tween_callback(close)

func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		close()

func close() -> void:
	if is_queued_for_deletion():
		return
	if _tween:
		_tween.kill()
	closed.emit()
	queue_free()
