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
	Tutorial.show_event_intro(self)   # обучение: наставники объясняют, что такое событие
	SaveManager.save_run()   # вылет на событии — «Продолжить» вернёт сюда же
	if RunManager.current_completed or _event.is_empty():
		_finish("")

func _build() -> void:
	add_child(UITheme.make_background())

	var hud := ShopFrame.hud_bar(self)   # шапка как в магазине и бою — без рамки (17.11.2026)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	hud.add_child(row)
	row.add_child(UITheme.make_label("Событие · перед волной %d/%d" % [EconomyManager.round_number, RunManager.get_total_waves()],
		"HeaderLabel"))
	row.add_child(UITheme.make_spacer())
	_req_label = UITheme.make_label("", "ValueLabel")
	row.add_child(UITheme.icon_row("hud", "requisition", _req_label))   # монета и число
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
		ButtonVolume.attach(b, 5.0)
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
	ButtonVolume.attach(_next_button, 6.0)

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
	_req_label.text = str(EconomyManager.requisition)
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
	_play_outcome.call_deferred(not result.begins_with("Не повезло"), result)

# Исход выбора на иллюстрации (решение пользователя 09.11.2026, было — только текст): удача / без риска — золотая
# вспышка и награда всплывает над картинкой; неудача — красная вспышка, трещины и картинка вздрагивает. Только вид
const OUTCOME_TIME: float = 0.9
const CRACKS := 5
func _play_outcome(lucky: bool, result: String) -> void:
	if not is_instance_valid(_art) or not _art.is_inside_tree():
		return
	var col: Color = UITheme.GOLD_BRIGHT if lucky else Palette.HIT_RED
	var flash := ColorRect.new()
	flash.color = Color(col, 0.35)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.add_child(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tw := flash.create_tween()
	tw.tween_property(flash, "color:a", 0.0, OUTCOME_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(flash.queue_free)
	if lucky:
		# награда — первая строка эффекта (без «Удача!») всплывает от середины картинки
		var lines: Array = Array(result.split("
")).filter(func(l): return l != "" and l != "Удача!")
		if lines.is_empty():
			return
		var reward := UITheme.make_label(lines[0], "HeaderLabel")
		reward.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		reward.add_theme_color_override("font_outline_color", Palette.OUTLINE)
		reward.add_theme_constant_override("outline_size", 6)
		reward.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_art.add_child(reward)
		reward.position = _art.size / 2.0 - reward.get_combined_minimum_size() / 2.0
		var up := reward.create_tween()
		up.tween_property(reward, "position:y", reward.position.y - 40.0, OUTCOME_TIME * 1.4).set_trans(Tween.TRANS_QUAD) 			.set_ease(Tween.EASE_OUT)
		up.parallel().tween_property(reward, "modulate:a", 0.0, OUTCOME_TIME * 1.4).set_delay(OUTCOME_TIME * 0.6)
		up.tween_callback(reward.queue_free)
	else:
		# трещины по картинке и встряска
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(result)
		var cracks := Control.new()
		cracks.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_art.add_child(cracks)
		cracks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var lines: Array = []
		var origin := Vector2(rng.randf_range(0.35, 0.65), rng.randf_range(0.35, 0.65)) * _art.size
		for i in CRACKS:
			var p := origin
			var ang := TAU * i / CRACKS + rng.randf_range(-0.4, 0.4)
			var line := PackedVector2Array([p])
			for k in 5:
				ang += rng.randf_range(-0.5, 0.5)
				p += Vector2.from_angle(ang) * rng.randf_range(18.0, 40.0)
				line.append(p)
			lines.append(line)
		cracks.draw.connect(func():
			for l in lines:
				cracks.draw_polyline(l, Color(0, 0, 0, 0.8), 3.0, true)
				cracks.draw_polyline(l, Color(Palette.HIT_RED, 0.9), 1.2, true))
		cracks.modulate.a = 1.0
		var fade := cracks.create_tween()
		fade.tween_interval(OUTCOME_TIME)
		fade.tween_property(cracks, "modulate:a", 0.0, OUTCOME_TIME)
		fade.tween_callback(cracks.queue_free)
		var x0 := _art.position.x
		var shake := _art.create_tween()
		for k in 6:
			shake.tween_property(_art, "position:x", x0 + (6.0 if k % 2 == 0 else -6.0) * (1.0 - k / 6.0), 0.04)
		shake.tween_property(_art, "position:x", x0, 0.04)

func _on_next_pressed() -> void:
	RunManager.advance()
