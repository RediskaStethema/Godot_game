extends SceneTree

# Язык названий (решение пользователя 17.11.2026): у каждого названия, которое видит игрок, есть русский вариант в Names.RU,
# выбор языка в GameSettings сохраняется, карты и отряды показывают название выбранного языка.
# Запуск: godot --headless --path . -s tests/test_names.gd

var _fails := 0

func _check(name: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok:
		_fails += 1

func _initialize() -> void:
	_main()

func _main() -> void:
	await process_frame
	var gs = root.get_node("GameSettings")
	gs.config_path = "user://tmp_names_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.config_path))
	root.get_node("SaveManager").enabled = false

	# Покрытие: все карты обеих рас (пул + особые + тестовые) и их бойцы
	var missing: Array[String] = []
	var seen: Dictionary = {}
	var cards: Array = []
	for faction in ["space_marines", "chaos"]:
		cards.append_array(CardFactory.build_pool(faction))
		cards.append_array(CardFactory.test_cards(faction))
	for c in cards:
		if seen.has(c.title):
			continue
		seen[c.title] = true
		if not Names.RU.has(c.title):
			missing.append("карта «%s»" % c.title)
		if c.card_type == "squad" and c.unit_factory_id != "":
			var u := UnitFactory.create(c.unit_factory_id)
			if not seen.has("u:" + u.unit_name):
				seen["u:" + u.unit_name] = true
				if not Names.RU.has(u.unit_name):
					missing.append("боец «%s»" % u.unit_name)
	for c in Chapters.CHAPTERS:
		if not Names.RU.has(c["name"]):
			missing.append("братство / бог «%s»" % c["name"])
	var synergies: Dictionary = root.get_node("SynergyManager").SYNERGY_DEFINITIONS   # -s компилируется до автолоадов
	for tag in synergies:
		for level in synergies[tag]:
			if not Names.RU.has(level["name"]):
				missing.append("синергия «%s»" % level["name"])
	for id in EnemyWaves.BOSS_TITLES:
		var b := UnitFactory.create(id)
		if b and not Names.RU.has(b.unit_name):
			missing.append("босс «%s»" % b.unit_name)
	_check("у каждого названия есть русский вариант (%d карт проверено; нет: %s)" % [seen.size(), ", ".join(missing) if not missing.is_empty() else "—"],
		missing.is_empty())

	# Переключение
	var card = CardFactory.create("tactical_squad")
	var unit = UnitFactory.create("tactical_marine")
	gs.set_names_language("en")
	_check("английский: карта «%s», боец «%s»" % [card.display_title(), unit.display_name()],
		card.display_title() == card.title and unit.display_name() == unit.unit_name and card.title == "Crispin Line")
	gs.set_names_language("ru")
	_check("русский: карта «%s», боец «%s»; ключи title / unit_name не меняются" % [card.display_title(), unit.display_name()],
		card.display_title() == "Латники Криспина" and unit.display_name() == "Латники Криспина" and card.title == "Crispin Line"
		and unit.unit_name == "Crispin Plate")
	_check("название, которого нет в таблице, не ломается", Names.of("Нечто") == "Нечто")
	gs.set_names_language("xx")
	_check("неизвестный язык — русский", gs.names_language == "ru")

	# Сохранение и чтение
	gs.set_names_language("en")
	gs.names_language = "ru"
	gs._load()
	_check("язык сохраняется в настройках и читается обратно", gs.names_language == "en")
	gs.set_names_language("ru")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.config_path))

	# Окно настроек: переключатель есть
	var panel = load("res://scenes/ui/SettingsPanel.gd").new()
	root.add_child(panel)
	panel.setup()
	await process_frame
	var ru_btn = panel.find_child("Names_ru", true, false)
	var en_btn = panel.find_child("Names_en", true, false)
	_check("окно «Настройки»: кнопки «Русские» / «English», русский нажат", ru_btn != null and en_btn != null and ru_btn.button_pressed and not en_btn.button_pressed)
	en_btn.pressed.emit()
	_check("кнопка English переключает язык названий", gs.names_language == "en" and en_btn.button_pressed and not ru_btn.button_pressed)
	gs.set_names_language("ru")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.config_path))
	panel.queue_free()

	print("test_names: %s" % ("OK" if _fails == 0 else "%d провалов" % _fails))
	quit(1 if _fails > 0 else 0)
