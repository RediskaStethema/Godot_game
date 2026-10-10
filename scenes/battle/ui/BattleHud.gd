class_name BattleHud
extends Control

# Интерфейс боя поверх поля (в CanvasLayer): шапка (волна, Req, цитадель,
# сообщение, кнопка «В БОЙ») и панель синергий справа снизу рядом со скамейкой.
# Кнопка и строка сообщения — ноды из BattleScene.tscn, переставляются сюда.

var _message: Label
var _requisition: Label
var _citadel: Label
var _synergy_panel: PanelContainer
var _synergy_label: Label
var _speed_button: Button   # скорость боя ×1/×2 (GameSettings.battle_speed)

func setup(wave_text: String, message_label: Label, start_button: Button, synergy_width: float) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_header(wave_text, message_label, start_button)
	_build_synergy_panel(synergy_width)
	EconomyManager.requisition_changed.connect(_on_requisition_changed)
	BattleManager.citadel_hp_changed.connect(_on_citadel_changed)
	_on_requisition_changed(EconomyManager.requisition)
	_on_citadel_changed(BattleManager.citadel_hp)

func _build_header(wave_text: String, message_label: Label, start_button: Button) -> void:
	var hud = UITheme.make_panel()
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.offset_bottom = UITheme.HUD_HEIGHT
	add_child(hud)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	hud.add_child(row)
	row.add_child(UITheme.make_label(wave_text, "HeaderLabel"))
	_requisition = UITheme.make_label("", "ValueLabel")
	row.add_child(_requisition)
	_citadel = UITheme.make_label("", "ValueLabel")
	row.add_child(_citadel)

	_message = message_label
	_message.reparent(row)
	_message.theme_type_variation = "HeaderLabel"
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Длинные подсказки обрезаются, а не выталкивают кнопку «В БОЙ» за экран
	_message.clip_text = true
	_message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_speed_button = UITheme.make_button("", "", GameSettings.cycle_battle_speed)
	_speed_button.custom_minimum_size = Vector2(64, 0)
	_speed_button.tooltip_text = "Скорость боя"
	row.add_child(_speed_button)
	GameSettings.changed.connect(_update_speed_button)
	_update_speed_button()

	start_button.reparent(row)
	start_button.theme_type_variation = "PrimaryButton"
	start_button.text = "В БОЙ"
	start_button.custom_minimum_size = Vector2(180, 0)

func _build_synergy_panel(width: float) -> void:
	_synergy_panel = UITheme.make_panel()
	_synergy_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_synergy_panel.offset_left = -width
	_synergy_panel.offset_top = -UITheme.BENCH_HEIGHT
	_synergy_panel.offset_right = 0
	_synergy_panel.offset_bottom = 0
	add_child(_synergy_panel)
	var col = VBoxContainer.new()
	_synergy_panel.add_child(col)
	col.add_child(UITheme.make_label("СИНЕРГИИ", "HeaderLabel"))
	_synergy_label = UITheme.make_label("", "SmallLabel")
	_synergy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_synergy_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_synergy_label)

# -------------------------------------------------------
# API
# -------------------------------------------------------
func set_message(text: String) -> void:
	_message.text = text

# Бой: панель синергий прячется, чтобы было видно всё поле
func set_battle_mode() -> void:
	_synergy_panel.visible = false

# Список активных синергий SynergyManager (после calculate_synergies)
func show_synergies() -> void:
	var lines: Array[String] = []
	for s in SynergyManager.active_synergies:
		lines.append("• %s — %s" % [s["name"], s["desc"]])
	if lines.is_empty():
		lines.append("Нет активных синергий (3+ Marine → +15% HP)")
	var marines = SynergyManager.tag_counts.get(SynergyManager.INCOME_TAG, 0)
	lines.append("Marine: %d · доход синергии +%d Req" % [marines, SynergyManager.income_bonus])
	_synergy_label.text = "\n".join(lines)

func _update_speed_button() -> void:
	_speed_button.text = "×%d" % GameSettings.battle_speed

func _on_requisition_changed(amount: int) -> void:
	_requisition.text = "%d Req" % amount

func _on_citadel_changed(hp: float) -> void:
	_citadel.text = "Цитадель %d/%d" % [ceili(hp), int(BattleManager.CITADEL_MAX_HP)]
	if BattleManager.citadel_shield > 0.0:
		_citadel.text += " +%d щит" % ceili(BattleManager.citadel_shield)
	_citadel.add_theme_color_override("font_color",
		UITheme.RED_BRIGHT if hp <= BattleManager.CITADEL_MAX_HP / 4 else UITheme.GOLD_BRIGHT)
