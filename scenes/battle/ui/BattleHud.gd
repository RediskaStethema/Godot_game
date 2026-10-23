class_name BattleHud
extends Control

# Интерфейс боя поверх поля (в CanvasLayer): шапка (волна, Req, цитадель,
# сообщение, кнопка «В БОЙ»). Панели синергий нет (решение пользователя 23.10.2026): синергии армии — в справке
# цитадели (SquadInspector, клик по цитадели на расстановке), строки — synergy_lines().
# Кнопка и строка сообщения — ноды из BattleScene.tscn, переставляются сюда.

var _message: Label
var _requisition: Label
var _citadel: Label
var _shield_icon: Control           # щит цитадели в шапке — только пока щит есть
var _artillery_icon: TextureRect    # орудие: готово / перезарядка
var _speed_button: Button   # скорость боя ×1/×2 (GameSettings.battle_speed)
var _artillery: Label       # орудия игрока в бою: готово / перезарядка (только если есть)
var _artillery_state: String = ""   # последняя надпись — метка меняется только при смене
# Баннер итога боя по центру экрана (решение пользователя): появляется, держится, гаснет —
# по реальному времени (замедление финала и ×2 на него не влияют)
const RESULT_FONT_SIZE: int = 56
const RESULT_FADE_IN: float = 0.25
const RESULT_HOLD: float = 1.5
const RESULT_FADE_OUT: float = 0.4
var result_banner: Control = null
const RESULT_PLATE_WIDTH: float = 820.0
const RESULT_PLATE_FONT_SIZE: int = 44

func setup(wave_text: String, message_label: Label, start_button: Button) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_header(wave_text, message_label, start_button)
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
	row.add_theme_constant_override("separation", 16)
	hud.add_child(row)
	row.add_child(UITheme.icon_row("hud", "wave", UITheme.make_label(wave_text, "HeaderLabel")))
	_requisition = UITheme.make_label("", "ValueLabel")
	row.add_child(UITheme.icon_row("hud", "requisition", _requisition))
	_citadel = UITheme.make_label("", "ValueLabel")
	var citadel_row := UITheme.icon_row("hud", "citadel_hp", _citadel)
	citadel_row.tooltip_text = "Цитадель (+ щит стен в этом бою)"
	citadel_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_shield_icon = UITheme.make_icon("hud", "shield", UITheme.HUD_ICON_SIZE)
	if _shield_icon:
		citadel_row.add_child(_shield_icon)
		_shield_icon.visible = false
	row.add_child(citadel_row)

	_message = message_label
	_message.reparent(row)
	_message.theme_type_variation = "HeaderLabel"
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Длинные подсказки обрезаются, а не выталкивают кнопку «В БОЙ» за экран
	_message.clip_text = true
	_message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_artillery = UITheme.make_label("", "ValueLabel")
	_artillery.visible = false
	var artillery_row := UITheme.icon_row("hud", "cannon_ready", _artillery)
	_artillery_icon = artillery_row.get_node_or_null("Icon")
	if _artillery_icon:
		_artillery_icon.visible = false
	row.add_child(artillery_row)
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

# -------------------------------------------------------
# API
# -------------------------------------------------------
func set_message(text: String) -> void:
	_message.text = text

# Итог боя крупно по центру: заголовок (янтарь — победа, красный — нет) и строка дохода
func show_result(title: String, subtitle: String, victory: bool) -> void:
	if is_instance_valid(result_banner):
		result_banner.queue_free()
	var banner := VBoxContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var head = UITheme.make_label(title, "TitleLabel")
	head.name = "Title"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", RESULT_FONT_SIZE)
	head.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT if victory else UITheme.RED_BRIGHT)
	head.add_theme_color_override("font_outline_color", UITheme.OUTLINE)
	head.add_theme_constant_override("outline_size", 12)
	# Подложка пакета интерфейса (имперская — победа, хаоситская — нет); заголовок — в её тёмном поле
	var plate := UITheme.ui_icon("banners", "victory" if victory else "defeat")
	if plate:
		var back = TextureRect.new()
		back.texture = plate
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		back.custom_minimum_size = Vector2(RESULT_PLATE_WIDTH, RESULT_PLATE_WIDTH * plate.get_height() / plate.get_width())
		back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(back)
		head.add_theme_font_size_override("font_size", RESULT_PLATE_FONT_SIZE)   # в тёмное поле подложки
		back.add_child(head)
		head.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		banner.add_child(head)
	var sub = UITheme.make_label(subtitle, "ValueLabel")
	sub.name = "Subtitle"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_outline_color", UITheme.OUTLINE)
	sub.add_theme_constant_override("outline_size", 8)
	banner.add_child(sub)
	banner.modulate.a = 0.0
	result_banner = banner
	var tween := banner.create_tween().set_ignore_time_scale(true)
	tween.tween_property(banner, "modulate:a", 1.0, RESULT_FADE_IN)
	tween.tween_interval(RESULT_HOLD)
	tween.tween_property(banner, "modulate:a", 0.0, RESULT_FADE_OUT)
	tween.tween_callback(banner.queue_free)

# Строки синергий армии (после calculate_synergies): справка цитадели (SquadInspector)
static func synergy_lines() -> Array[String]:
	var lines: Array[String] = []
	for s in SynergyManager.active_synergies:
		lines.append("• %s — %s" % [s["name"], s["desc"]])
	var tag := SynergyManager.faction_tag()
	if lines.is_empty():
		var first: Dictionary = SynergyManager.SYNERGY_DEFINITIONS[tag][0]
		lines.append("Нет активных синергий (%d+ %s → %s)" % [first["threshold"], tag.capitalize(), first["desc"]])
	var chapter = Chapters.get_chapter(RunManager.player_chapter)
	if not chapter.is_empty():
		lines.append("• %s %s — %s" % ["Метка" if chapter["faction"] == "chaos" else "Орден", chapter["name"], chapter["desc"]])
		if chapter.has("malus_desc"):
			lines.append("  минус: %s" % chapter["malus_desc"])
	var rows = SynergyManager.count_position_bonuses(
		SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER))
	for pos in [SynergyManager.FRONT, SynergyManager.BACK]:
		var p: Dictionary = SynergyManager.POSITION_BONUSES[pos]
		lines.append("• %s (%d отр.) — %s" % [p["name"], rows[pos], p["desc"]])
	lines.append("%s: %d · доход синергии +%d Req" % [tag.capitalize(), SynergyManager.tag_counts.get(tag, 0),
		SynergyManager.income_bonus])
	return lines

# Орудия игрока: опрос раз в кадр — только надпись, на бой не влияет
func _process(_delta: float) -> void:
	var ready_count = 0
	var wait = INF
	var any = false
	if BattleManager.is_battle_running():   # на расстановке клик не стреляет — надписи нет
		for b in BattleManager.buildings:
			if not is_instance_valid(b) or b.building_type != "artillery":
				continue
			any = true
			if b.is_artillery_ready():
				ready_count += 1
			else:
				wait = minf(wait, b.cooldown_left)
	var text = ""
	if any:
		if ready_count > 0:
			text = "Орудие: готово — клик по полю" if ready_count == 1 else "Орудия: %d готовы — клик по полю" % ready_count
		else:
			text = "Орудие: %.1f с" % wait
	if text == _artillery_state:
		return
	_artillery_state = text
	_artillery.visible = text != ""
	_artillery.text = text
	if _artillery_icon:
		_artillery_icon.visible = text != ""
		_artillery_icon.texture = UITheme.ui_icon("hud", "cannon_ready" if ready_count > 0 else "cannon_cooldown")
	_artillery.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT if ready_count > 0 else UITheme.TEXT_DIM)

func _update_speed_button() -> void:
	_speed_button.text = "×%d" % GameSettings.battle_speed

func _on_requisition_changed(amount: int) -> void:
	_requisition.text = "%d Req" % amount

func _on_citadel_changed(hp: float) -> void:
	# «Цитадель» и «щит» — значками шапки (пакет интерфейса), в тексте только числа
	_citadel.text = "%d/%d" % [ceili(hp), int(BattleManager.CITADEL_MAX_HP)]
	if BattleManager.citadel_shield > 0.0:
		_citadel.text += "  +%d" % ceili(BattleManager.citadel_shield)
	if _shield_icon:
		_shield_icon.visible = BattleManager.citadel_shield > 0.0
	_citadel.add_theme_color_override("font_color",
		UITheme.RED_BRIGHT if hp <= BattleManager.CITADEL_MAX_HP / 4 else UITheme.GOLD_BRIGHT)
