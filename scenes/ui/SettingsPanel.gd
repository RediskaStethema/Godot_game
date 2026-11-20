class_name SettingsPanel
extends ModalOverlay

# Настройки игрока (GameSettings): скорость боя, полноэкранный режим, громкость (общая, сражение, интерфейс, музыка).
# Изменения применяются и сохраняются сразу; «Готово» — закрыть.

# Ползунки громкости: поле GameSettings → подпись (решение пользователя 09.11.2026: бой, интерфейс и музыка — раздельно)
const VOLUME_ROWS = [["master_volume", "Громкость"], ["battle_volume", "Звук сражения"],
	["ui_volume", "Звук интерфейса"], ["music_volume", "Музыка"]]

var _speed_buttons: Array[Button] = []   # по GameSettings.BATTLE_SPEEDS — как радиокнопки

func setup() -> void:
	close_on_cancel = true
	build_frame(420.0)
	add_title("НАСТРОЙКИ")

	var speed_row = _add_row("Скорость боя")
	for speed in GameSettings.BATTLE_SPEEDS:
		var b = UITheme.make_button("×%d" % speed, "", _on_speed.bind(speed))
		b.toggle_mode = true
		b.button_pressed = is_equal_approx(GameSettings.battle_speed, speed)
		b.custom_minimum_size = Vector2(64, 40)
		speed_row.add_child(b)
		_speed_buttons.append(b)

	var full = CheckButton.new()
	full.button_pressed = GameSettings.fullscreen
	full.toggled.connect(GameSettings.set_fullscreen)
	_add_row("Полный экран").add_child(full)

	# Язык названий карт, отрядов и зданий (Names.of): две кнопки-переключателя
	var lang_row = _add_row("Названия")
	var lang_buttons: Dictionary = {}
	for code in Names.LANGUAGES:
		var lb = UITheme.make_button(Names.LANGUAGES[code], "", func(): _on_names_language(code, lang_buttons))
		lb.name = "Names_" + code
		lb.toggle_mode = true
		lb.button_pressed = GameSettings.names_language == code
		lb.custom_minimum_size = Vector2(110, 40)
		lang_row.add_child(lb)
		lang_buttons[code] = lb

	var atmo = CheckButton.new()
	atmo.button_pressed = GameSettings.atmosphere
	atmo.toggled.connect(GameSettings.set_atmosphere)
	_add_row("Атмосфера боя").add_child(atmo)

	for v in VOLUME_ROWS:
		var volume = HSlider.new()
		volume.name = v[0]
		volume.min_value = 0.0
		volume.max_value = 1.0
		volume.step = 0.05
		volume.value = GameSettings.get(v[0])
		volume.custom_minimum_size = Vector2(160, 0)
		volume.value_changed.connect(func(x: float): GameSettings.set_volume(v[0], x))
		_add_row(v[1]).add_child(volume)

	add_button("Готово", close, "PrimaryButton")

# Строка «подпись … элементы»; возвращает контейнер для элементов
func _add_row(label: String) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var l = UITheme.make_label(label, "ValueLabel")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var controls = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	row.add_child(controls)
	return controls

func _on_speed(speed: float) -> void:
	GameSettings.set_battle_speed(speed)
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(is_equal_approx(GameSettings.battle_speed, GameSettings.BATTLE_SPEEDS[i]))

func _on_names_language(code: String, buttons: Dictionary) -> void:
	for c in buttons:
		buttons[c].button_pressed = (c == code)
	GameSettings.set_names_language(code)
