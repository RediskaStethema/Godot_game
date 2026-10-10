class_name SettingsPanel
extends ModalOverlay

# Настройки игрока (GameSettings): скорость боя, полноэкранный режим, громкость.
# Изменения применяются и сохраняются сразу; «Готово» — закрыть.

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

	var volume = HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = GameSettings.master_volume
	volume.custom_minimum_size = Vector2(160, 0)
	volume.value_changed.connect(GameSettings.set_master_volume)
	_add_row("Громкость").add_child(volume)

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
