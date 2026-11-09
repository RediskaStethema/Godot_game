extends Control

# Событие — шаг цепочки забега (RunMapNode.EVENT): текст, варианты с ценой и риском (RunEvents),
# выбор → итог → «Далее» в магазин следующей волны. Какое событие и исход риска — от seed забега
# (RunManager.get_current_event / get_event_rng): выход и «Продолжить» не дают переиграть.
# Выбор применяется, шаг завершается и сохраняется сразу. UI собирается кодом, стили — UITheme.

const PANEL_WIDTH: float = 640.0
const OPTION_HEIGHT: float = 52.0
const ART_MAX_HEIGHT: float = 300.0    # иллюстрация события (assets/ui/events/<id>.png, 16:9)
const ART_MIN_HEIGHT: float = 110.0
const ART_SCREEN_MARGIN: float = 24.0  # окно не впритык к шапке и низу

var _art: Control = null
var _panel: Control = null

var _event: Dictionary = {}
var _option_buttons: Array[Button] = []
var _result_label: Label
var _next_button: Button
var _req_label: Label
var _citadel_label: Label

func _ready() -> void:
	AudioManager.play_music("shop")   # событие — передышка между боями, как магазин
	theme = UITheme.get_theme()
	UITheme.apply_cursors()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_event = RunManager.get_current_event()
	_build()
	add_child(PauseMenu.new())
	# Методы, не лямбды: связь с автолоадами снимается сама, когда сцена удалена
	EconomyManager.requisition_changed.connect(_on_resources_changed)
	BattleManager.citadel_hp_changed.connect(_on_resources_changed)
	_refresh_hud()
	SaveManager.save_run()   # вылет на событии — «Продолжить» вернёт сюда же
	if RunManager.current_completed or _event.is_empty():
		_finish("")

func _build() -> void:
	add_child(UITheme.make_background())

	var hud = UITheme.make_panel("HudBar")   # полоса шапки — hud_bar повтором
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.offset_bottom = UITheme.HUD_HEIGHT
	add_child(hud)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	hud.add_child(row)
	row.add_child(UITheme.make_label("Событие · перед волной %d/%d" % [EconomyManager.round_number, RunManager.get_total_waves()],
		"HeaderLabel"))
	row.add_child(UITheme.make_spacer())
	_req_label = UITheme.make_label("", "ValueLabel")
	row.add_child(_req_label)
	_citadel_label = UITheme.make_label("", "ValueLabel")
	row.add_child(_citadel_label)
	for l in [_req_label, _citadel_label]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = UITheme.HUD_HEIGHT
	add_child(center)
	var panel = UITheme.make_panel("WindowPanel")   # рамка окон с аквилой — как остальные окна игры
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	center.add_child(panel)
	ModalOverlay.add_frame_eagle(panel)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var title = UITheme.make_label(_event.get("title", "Событие"), "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var divider := ModalOverlay.make_divider()
	if divider:
		col.add_child(divider)
	_art = UITheme.make_illustration("events", _event.get("id", ""), ART_MAX_HEIGHT)
	if _art:
		col.add_child(_art)
		_panel = panel
		panel.resized.connect(_fit_art)
		get_viewport().size_changed.connect(_fit_art)
		_fit_art.call_deferred()
	var text = UITheme.make_label(_event.get("text", ""))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(text)

	for option in _event.get("options", []):
		var reason = RunEvents.blocker(option)
		var label = RunEvents.describe(option) + ("  — " + reason if reason != "" else "")
		var b = UITheme.make_button(label, "", _choose.bind(option))
		b.custom_minimum_size = Vector2(0, OPTION_HEIGHT)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = reason != ""
		col.add_child(b)
		_option_buttons.append(b)
	for b in _option_buttons:
		if not b.disabled:
			ModalOverlay.focus_later(b)
			break

	_result_label = UITheme.make_label("", "HeaderLabel")
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	_result_label.visible = false
	col.add_child(_result_label)
	_next_button = UITheme.make_button("ДАЛЕЕ", "PrimaryButton", _on_next_pressed)
	_next_button.custom_minimum_size = Vector2(0, 46)
	_next_button.visible = false
	col.add_child(_next_button)

# Иллюстрация — сколько осталось по высоте под шапкой (окно с итогом выше — картинка ниже),
# не выше ART_MAX_HEIGHT (≈ 16:9 по ширине окна) и не ниже ART_MIN_HEIGHT
func _fit_art() -> void:
	if not is_instance_valid(_art) or not is_inside_tree():
		return
	var other = _panel.get_combined_minimum_size().y - _art.custom_minimum_size.y
	var free = get_viewport_rect().size.y - UITheme.HUD_HEIGHT - ART_SCREEN_MARGIN - other
	var h = clampf(free, ART_MIN_HEIGHT, ART_MAX_HEIGHT)
	if absf(h - _art.custom_minimum_size.y) > 0.5:
		_art.custom_minimum_size.y = h

func _on_resources_changed(_value) -> void:
	_refresh_hud()

func _refresh_hud() -> void:
	_req_label.text = "%d Req" % EconomyManager.requisition
	_citadel_label.text = "Цитадель %d/%d" % [roundi(BattleManager.citadel_hp), roundi(BattleManager.CITADEL_MAX_HP)]

# Выбор: эффект, шаг завершён, сохранение — до показа итога
func _choose(option: Dictionary) -> void:
	if RunManager.current_completed:
		return
	var result = RunEvents.apply(option, RunManager.get_event_rng())
	RunManager.complete_current_node()
	SaveManager.save_run()
	_finish(result)

func _finish(result: String) -> void:
	for b in _option_buttons:
		b.disabled = true
	_result_label.text = result
	_result_label.visible = result != ""
	_next_button.visible = true
	ModalOverlay.focus_later(_next_button)
	_fit_art.call_deferred()   # итог и «Далее» заняли место — картинка ниже

func _on_next_pressed() -> void:
	RunManager.advance()
