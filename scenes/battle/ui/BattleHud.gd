class_name BattleHud
extends Control

# Интерфейс боя поверх поля (в CanvasLayer): шапка (волна, Req, цитадель,
# сообщение, кнопка «В БОЙ»). Панели синергий нет (решение пользователя 23.10.2026): синергии армии — в справке
# цитадели (SquadInspector, клик по цитадели на расстановке), строки — synergy_lines().
# Кнопка и строка сообщения — ноды из BattleScene.tscn, переставляются сюда.

var _message: Label
var _message_plate: PanelContainer   # сообщение — плашкой по центру под шапкой (в строке шапки обрезалось)
const MESSAGE_MAX_WIDTH: float = 640.0
var _requisition: Label
var _citadel: Label
var _shield_icon: Control           # щит цитадели в шапке — только пока щит есть
var _artillery_icon: TextureRect    # орудие: готово / перезарядка
var _speed_button: Button   # скорость боя ×1/×2 (GameSettings.battle_speed)
var _pause_button: Button   # пауза в бою (решение пользователя 25.11.2026): то же, что пробел — PauseMenu.toggle_quick_pause
var _paused: bool = false
signal pause_toggled
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
	theme = UITheme.get_theme()   # баннер итога — вне панели шапки: без темы вариации TitleLabel / ValueLabel не находятся
	_build_header(wave_text, message_label, start_button)
	EconomyManager.requisition_changed.connect(_on_requisition_changed)
	BattleManager.citadel_hp_changed.connect(_on_citadel_changed)
	_on_requisition_changed(EconomyManager.requisition)
	_on_citadel_changed(BattleManager.citadel_hp)

const TIMELINE_WIDTH: float = 330.0

func _build_header(wave_text: String, message_label: Label, start_button: Button) -> void:
	var hud := ShopFrame.hud_bar(self, false)   # без рамки и фона (решение пользователя 17.11.2026): орден, сложность, монеты, лента волн
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	hud.add_child(row)
	var badge := UITheme.make_chapter_badge()   # бог / орден забега — первым слева
	if badge:
		row.add_child(badge)
	# Счётчика «Волна N/15» нет — номер волны на ленте; значок и название сложности (+ тип боя, ТЕСТ)
	row.add_child(UITheme.icon_row("difficulty", str(RunManager.difficulty), UITheme.make_label(wave_text, "HeaderLabel")))
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
	citadel_row.visible = false   # HP цитадели в шапке убрано (решение пользователя 17.11.2026): над цитаделью на поле уже есть полоска
	row.add_child(citadel_row)

	# Сообщение — плашкой по центру под шапкой (решение пользователя 24.10.2026: после пиксельных шрифтов
	# в строке шапки обрезалось — «Расставьте отр…»); длинное переносится, не шире MESSAGE_MAX_WIDTH
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var timeline := RunTimeline.new()   # лента 15 волн, как в магазине (17.11.2026), уже — между счётчиками и кнопками
	timeline.custom_minimum_size.x = TIMELINE_WIDTH
	row.add_child(timeline)
	_message_plate = UITheme.make_panel("HudPanel", true)
	_message_plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_message_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_plate.offset_top = UITheme.HUD_HEIGHT + 6.0
	_message_plate.hide()   # пустая — до первого set_message
	add_child(_message_plate)
	_message = message_label
	_message.reparent(_message_plate)
	_message.theme_type_variation = "HeaderLabel"
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_artillery = UITheme.make_label("", "ValueLabel")
	_artillery.visible = false
	var artillery_row := UITheme.icon_row("hud", "cannon_ready", _artillery)
	_artillery_icon = artillery_row.get_node_or_null("Icon")
	if _artillery_icon:
		_artillery_icon.visible = false
	row.add_child(artillery_row)
	_pause_button = UITheme.make_button("", "", func(): pause_toggled.emit())
	_pause_button.custom_minimum_size = Vector2(36, 0)
	_pause_button.tooltip_text = "Пауза (пробел)"
	_pause_button.process_mode = Node.PROCESS_MODE_ALWAYS   # на паузе дерево стоит — кнопка должна нажиматься, чтобы снять её
	_flatten_button(_pause_button)
	_pause_button.draw.connect(_draw_pause_glyph)
	_pause_button.mouse_entered.connect(_pause_button.queue_redraw)
	_pause_button.mouse_exited.connect(_pause_button.queue_redraw)
	row.add_child(_pause_button)
	_speed_button = UITheme.make_button("", "", GameSettings.cycle_battle_speed)
	_speed_button.custom_minimum_size = Vector2(60, 0)
	_speed_button.tooltip_text = "Скорость боя"
	_flatten_button(_speed_button)   # без рамки (решение пользователя 25.11.2026): значок и число на шапке
	row.add_child(_speed_button)
	GameSettings.changed.connect(_update_speed_button)
	_update_speed_button()

	start_button.reparent(row)
	start_button.theme_type_variation = "PrimaryButton"
	start_button.text = "В БОЙ"
	start_button.custom_minimum_size = Vector2(180, 0)
	ButtonVolume.attach(start_button, 5.0)   # объём и отклик, как «В БОЙ» в магазине

# -------------------------------------------------------
# API
# -------------------------------------------------------
func set_message(text: String) -> void:
	_message.text = text
	_message_plate.visible = text != ""
	# По ширине текста, длинный — переносом в MESSAGE_MAX_WIDTH; плашка — по центру
	_message.autowrap_mode = TextServer.AUTOWRAP_OFF
	_message.custom_minimum_size = Vector2.ZERO
	if _message.get_minimum_size().x > MESSAGE_MAX_WIDTH:
		_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_message.custom_minimum_size = Vector2(MESSAGE_MAX_WIDTH, 0)
	_fit_message_plate()
	# Перенос считается по ширине метки после раскладки: сразу плашка бралась по высоте переноса «по букве»
	# и раздувалась (Screenshot 2026-11-11 140856) — подгоняем ещё раз в конце кадра
	_fit_message_plate.call_deferred()
	_place_notice()

func _fit_message_plate() -> void:
	if not is_instance_valid(_message_plate):
		return
	if _message.autowrap_mode != TextServer.AUTOWRAP_OFF:
		_message.size = Vector2(MESSAGE_MAX_WIDTH, 0)
	_message_plate.reset_size()
	_message_plate.offset_left = -_message_plate.size.x / 2.0
	_message_plate.offset_right = _message_plate.size.x / 2.0
	_place_notice()

# Короткое уведомление (решение пользователя 11.11.2026: «слишком большое окно и слишком долго висит — просто надпись
# сверху»): текст с обводкой без плашки под плашкой этапа, держится NOTICE_TIME реального времени и тает за NOTICE_FADE;
# новое — заменяет прежнее
const NOTICE_TIME: float = 2.2
const NOTICE_FADE: float = 0.4
var _notice: Label
var _notice_tween: Tween

func notify(text: String) -> void:
	if _notice == null:
		_notice = UITheme.make_label("", "HeaderLabel")
		_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_notice.add_theme_color_override("font_outline_color", Palette.OUTLINE)
		_notice.add_theme_constant_override("outline_size", 6)
		_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
		add_child(_notice)
	_notice.text = text
	_notice.visible = text != ""
	_notice.modulate.a = 1.0
	_place_notice()
	if _notice_tween:
		_notice_tween.kill()
	if text == "":
		return
	_notice_tween = create_tween().set_ignore_time_scale(true)   # скорость боя ×3 и стоп-кадр не сокращают
	_notice_tween.tween_interval(NOTICE_TIME)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, NOTICE_FADE)
	_notice_tween.tween_callback(_notice.hide)

func notice_text() -> String:
	return _notice.text if _notice and _notice.visible else ""

func _place_notice() -> void:
	if _notice == null:
		return
	_notice.offset_left = -MESSAGE_MAX_WIDTH / 2.0
	_notice.offset_right = MESSAGE_MAX_WIDTH / 2.0
	_notice.offset_top = (message_bottom() if _message_plate.visible else UITheme.HUD_HEIGHT) + 4.0
	_notice.offset_bottom = _notice.offset_top

# Низ плашки сообщения на экране (нет сообщения — низ шапки): справки на поле — ниже неё
func message_bottom() -> float:
	if not _message_plate.visible:
		return UITheme.HUD_HEIGHT
	return _message_plate.get_global_rect().end.y

# Итог боя крупно по центру: заголовок (янтарь — победа, красный — нет) и строка дохода
func show_result(title: String, subtitle: String, victory: bool) -> void:
	_message_plate.hide()   # «Бой идёт…» под баннером итога — устарело
	if _notice:
		_notice.hide()
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
	head.add_theme_font_size_override("font_size", UITheme.ui_px(RESULT_FONT_SIZE))
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
		head.add_theme_font_size_override("font_size", UITheme.ui_px(RESULT_PLATE_FONT_SIZE))   # в тёмное поле подложки
		back.add_child(head)
		head.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		banner.add_child(head)
	# Подпись — на тёмной плашке (решение пользователя 24.10.2026: висела над боем и сливалась с цифрами урона):
	# первая строка (доход) — янтарём крупнее, итоги — по пункту в строку
	var lines := subtitle.split("
")
	var plate_box := UITheme.make_panel("HudPanel", true)
	plate_box.name = "SubtitlePlate"
	plate_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	banner.add_child(plate_box)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	plate_box.add_child(col)
	var sub = UITheme.make_label(lines[0].replace(" · ", "  ·  "), "ValueLabel")
	sub.name = "Subtitle"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var rest: Array[String] = []
	for l in lines.slice(1):
		for part in l.split(" · "):
			rest.append(part)
	if not rest.is_empty():
		var details = UITheme.make_label("
".join(rest), "SmallLabel")
		details.name = "Details"
		details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(details)
	_result_sparks(victory)
	banner.modulate.a = 0.0
	result_banner = banner
	var tween := banner.create_tween().set_ignore_time_scale(true)
	tween.tween_property(banner, "modulate:a", 1.0, RESULT_FADE_IN)
	tween.tween_interval(RESULT_HOLD)
	tween.tween_property(banner, "modulate:a", 0.0, RESULT_FADE_OUT)
	tween.tween_callback(banner.queue_free)

# Искры итога боя (решение пользователя 18.11.2026): победа — золотой фонтан искр вверх от баннера, поражение — медленный
# красный пепел вниз; один залп, ADD, по реальному времени, гаснет сам
func _result_sparks(victory: bool) -> void:
	if not GameSettings.atmosphere:
		return
	var p := CPUParticles2D.new()
	p.name = "ResultSparks"
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 70 if victory else 40
	p.lifetime = 2.2
	p.local_coords = false
	p.direction = Vector2(0, -1) if victory else Vector2(0, 1)
	p.spread = 70.0 if victory else 120.0
	p.initial_velocity_min = 80.0 if victory else 15.0
	p.initial_velocity_max = 220.0 if victory else 50.0
	p.gravity = Vector2(0, 160) if victory else Vector2(0, 20)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = Palette.GOLD_BRIGHT if victory else Color(0.8, 0.18, 0.12)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = grad
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.position = size * Vector2(0.5, 0.45)
	get_tree().create_timer(3.0, true, false, true).timeout.connect(p.queue_free)

# Строки синергий армии (после calculate_synergies): справка цитадели (SquadInspector)
static func synergy_lines() -> Array[String]:
	var lines: Array[String] = []
	for s in SynergyManager.active_synergies:
		lines.append("• %s — %s" % [Names.of(s["name"]), s["desc"]])
	var tag := SynergyManager.faction_tag()
	if lines.is_empty():
		var first: Dictionary = SynergyManager.SYNERGY_DEFINITIONS[tag][0]
		lines.append("Нет активных синергий (%d+ %s → %s)" % [first["threshold"], SynergyManager.tag_label(tag), first["desc"]])
	var chapter = Chapters.get_chapter(RunManager.player_chapter)
	if not chapter.is_empty():
		lines.append("• %s %s — %s" % ["Метка" if chapter["faction"] == "chaos" else "Братство", Names.of(chapter["name"]), chapter["desc"]])
		if chapter.has("malus_desc"):
			lines.append("  минус: %s" % chapter["malus_desc"])
	var rows = SynergyManager.count_position_bonuses(
		SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER))
	for pos in [SynergyManager.FRONT, SynergyManager.BACK]:
		var p: Dictionary = SynergyManager.POSITION_BONUSES[pos]
		lines.append("• %s (%d отр.) — %s" % [p["name"], rows[pos], p["desc"]])
	lines.append("%s: %d · доход синергии +%s" % [SynergyManager.tag_label(tag), SynergyManager.tag_counts.get(tag, 0),
		GameConstants.coins(SynergyManager.income_bonus)])
	return lines

# Кнопка без рамки: пустые стили всех состояний, отклик — цветом текста и значка (шапка остаётся одной плашкой)
static func _flatten_button(b: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, empty)
	b.add_theme_color_override("font_hover_color", Palette.GOLD_BRIGHT)
	b.add_theme_color_override("font_pressed_color", Palette.AMBER_LIGHT)
	b.add_theme_color_override("icon_hover_color", Palette.AMBER_LIGHT)
	b.add_theme_color_override("icon_pressed_color", Palette.GOLD_BRIGHT)
	b.focus_mode = Control.FOCUS_NONE   # пробел — пауза (PauseMenu._input), не нажатие кнопки в фокусе

# Значок паузы кодом: две полосы (идёт бой) или треугольник «играть» (стоит на паузе)
func _draw_pause_glyph() -> void:
	var b := _pause_button
	var color := Palette.TEXT_DIM if b.disabled else (Palette.GOLD_BRIGHT if (b.is_hovered() or _paused) else Palette.TEXT)
	var c := b.size / 2.0
	var half := 7.0
	if _paused:
		b.draw_colored_polygon(PackedVector2Array([Vector2(c.x - 5.0, c.y - half), Vector2(c.x - 5.0, c.y + half),
			Vector2(c.x + 7.0, c.y)]), color)
	else:
		b.draw_rect(Rect2(c.x - 6.0, c.y - half, 4.0, half * 2.0), color)
		b.draw_rect(Rect2(c.x + 2.0, c.y - half, 4.0, half * 2.0), color)

# Пауза включена / снята (PauseMenu.quick_pause_changed): значок меняется, подсказка — что нажатие сделает
func set_paused(on: bool) -> void:
	_paused = on
	_pause_button.tooltip_text = "Продолжить (пробел)" if on else "Пауза (пробел)"
	_pause_button.queue_redraw()

# Орудия игрока: опрос раз в кадр — только надпись, на бой не влияет
func _process(_delta: float) -> void:
	var can_pause := BattleManager.is_battle_running()   # на расстановке и в итоге паузы нет
	if _pause_button.disabled == can_pause:
		_pause_button.disabled = not can_pause
		_pause_button.queue_redraw()
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
	UITheme.set_button_icon(_speed_button, "hud", "speed_%d" % roundi(GameSettings.battle_speed))   # шевроны 1–3

func _on_requisition_changed(amount: int) -> void:
	if _coin_hold:   # доход боя — счётчик прибавляет по долетевшим монетам (coin_landed)
		return
	UITheme.roll_number(_requisition, amount, func(v: int): return str(v))   # монета и число, отматывается

# Доход по итогу боя летит монетами с поля (BattleScene._fly_income_coins): пока летят — счётчик стоит на
# прежнем числе и прибавляет с каждой монетой; release — встаёт на настоящее
var _coin_hold := false
func hold_requisition() -> void:
	_coin_hold = true

func coin_landed(value: int) -> void:
	UITheme.roll_number(_requisition, value, func(v: int): return str(v))

func release_requisition() -> void:
	_coin_hold = false
	_on_requisition_changed(EconomyManager.requisition)

func requisition_label() -> Label:
	return _requisition

func _citadel_text(hp: int) -> String:
	var t := "%d/%d" % [hp, int(BattleManager.CITADEL_MAX_HP)]
	if BattleManager.citadel_shield > 0.0:
		t += "  +%d" % ceili(BattleManager.citadel_shield)
	return t

func _on_citadel_changed(hp: float) -> void:
	# «Цитадель» и «щит» — значками шапки (пакет интерфейса), в тексте только числа
	UITheme.roll_number(_citadel, ceili(hp), _citadel_text, false)   # отматывается, без вспышки (штурм — часто)
	if _shield_icon:
		_shield_icon.visible = BattleManager.citadel_shield > 0.0
	_citadel.add_theme_color_override("font_color",
		UITheme.RED_BRIGHT if hp <= BattleManager.CITADEL_MAX_HP / 4 else UITheme.GOLD_BRIGHT)
