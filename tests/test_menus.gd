extends SceneTree

# Пауза, настройки, скорость боя, выход в меню, сдача посреди боя, подтверждение нового забега.
# Свои файлы сохранения и настроек — настройки и забег игрока не трогает.
#   godot --headless --path . -s tests/test_menus.gd
const TEST_SAVE_PATH: String = "user://test_menus_save.json"
const TEST_CONFIG_PATH: String = "user://test_menus_settings.cfg"
const TEST_PROFILE_PATH: String = "user://test_menus_profile.cfg"   # не существует — открыты стартовые 3

func _initialize() -> void:
	root.get_node("SaveManager").save_path = TEST_SAVE_PATH
	root.get_node("SaveManager").profile_path = TEST_PROFILE_PATH   # открытые сложности игрока не трогаем
	root.get_node("SaveManager").load_profile()
	root.get_node("GameSettings").config_path = TEST_CONFIG_PATH
	_main()

func _frames(n: int) -> void:
	for i in range(n): await process_frame

# Классы сцен (ConfirmDialog, PauseMenu…) по имени не упоминаем: скрипт -s
# компилируется до автолоадов, и их зависимости не скомпилировались бы
func _is(node: Node, class_name_str: String) -> bool:
	var script = node.get_script()
	return script != null and script.get_global_name() == class_name_str

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _battle_scene() -> Node:
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(3)
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == 3:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 3
	var units: Array[UnitData] = []
	for i in range(3):
		var d = UnitFactory.create("tactical_marine")
		d.squad_size = 3
		d.saved_hp = [1.0, 1.0, 1.0] as Array[float]
		units.append(d)
	bm.player_units = units
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(3)
	return current_scene

func _main() -> void:
	await process_frame
	var gs = root.get_node("GameSettings")
	var sv = root.get_node("SaveManager")
	var bm = root.get_node("BattleManager")
	sv.delete_save()

	# 1. Настройки сохраняются в файл и читаются обратно
	gs.set_battle_speed(2.0)
	gs.set_master_volume(0.4)
	gs.battle_speed = 1.0
	gs.master_volume = 1.0
	gs._load()
	_check("настройки: запись и чтение", is_equal_approx(gs.battle_speed, 2.0) and is_equal_approx(gs.master_volume, 0.4))
	gs.cycle_battle_speed()
	_check("скорость по кругу ×2 → ×1", is_equal_approx(gs.battle_speed, 1.0))

	# 2. Скорость ×2 действует только во время боя
	gs.set_battle_speed(2.0)
	var battle = await _battle_scene()
	_check("расстановка — скорость обычная", is_equal_approx(Engine.time_scale, 1.0))
	battle._on_start_pressed()
	_check("бой — скорость ×2", is_equal_approx(Engine.time_scale, 2.0))
	gs.cycle_battle_speed()
	_check("переключение в бою → ×1 сразу", is_equal_approx(Engine.time_scale, 1.0))
	gs.set_battle_speed(2.0)

	# 3. Пауза останавливает бой
	await _frames(10)
	var soldier = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(0)[0]
	battle.pause_menu.open()
	var pos_before = soldier.global_position
	var round_before = root.get_node("EconomyManager").round_number
	await _frames(30)
	_check("пауза: дерево на паузе, бойцы стоят", paused and soldier.global_position == pos_before \
		and root.get_node("EconomyManager").round_number == round_before)
	battle.pause_menu.resume()
	await _frames(10)
	_check("продолжить: бойцы снова идут", not paused and soldier.global_position != pos_before)

	# 4. Из боя в главное меню: бой остановлен, скорость сброшена, сохранение есть
	battle.pause_menu.open()
	battle.pause_menu._to_main_menu()
	await _frames(4)
	_check("в главное меню посреди боя", current_scene.name == "MainMenu" and not paused \
		and bm.phase == bm.BattlePhase.IDLE and is_equal_approx(Engine.time_scale, 1.0) and sv.has_save() \
		and current_scene.continue_button.visible)

	# 5. «Новый забег» при сохранении — сначала подтверждение
	var menu = current_scene
	menu._on_new_run_pressed()
	var dialog = null
	for c in menu.get_children():
		if _is(c, "ConfirmDialog"):
			dialog = c
	_check("новый забег при сохранении → подтверждение, сохранение цело", dialog != null and sv.has_save() \
		and current_scene == menu)
	dialog._on_yes()
	await _frames(2)
	var race = null
	for c in menu.get_children():
		if _is(c, "RaceSelectDialog"):
			race = c
	var marines = race.find_child("Race_space_marines", true, false) if race else null
	var chaos = race.find_child("Race_chaos", true, false) if race else null
	var tyranids = race.find_child("Race_tyranids", true, false) if race else null
	_check("подтвердили → выбор расы: десант доступен и в фокусе, Хаос и Тираниды закрыты", race != null \
		and marines != null and not marines.disabled and chaos.disabled and tyranids.disabled \
		and root.get_viewport().gui_get_focus_owner() == marines and current_scene == menu)
	menu._open_race_select()
	await _frames(1)
	var extra = null
	for c in menu.get_children():
		if _is(c, "RaceSelectDialog") and c != race:
			extra = c
	var esc = InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	extra._unhandled_input(esc)
	await _frames(2)
	_check("Esc закрывает окно выбора расы без старта", not is_instance_valid(extra) and current_scene == menu)
	race.choose("chaos")   # закрытая раса — ничего
	await _frames(2)
	_check("закрытую расу не выбрать", current_scene == menu and is_instance_valid(race))
	race.choose("space_marines")
	await _frames(2)
	var chapter = null
	for c in menu.get_children():
		if _is(c, "ChapterSelectDialog"):
			chapter = c
	var chapter_cards = 0
	for c in Chapters.CHAPTERS:
		if chapter and chapter.find_child("Chapter_" + c["id"], true, false):
			chapter_cards += 1
	_check("выбрали десант → окно ордена (5 орденов), забег ещё не начат", chapter != null \
		and chapter_cards == 5 and current_scene == menu)
	chapter.choose("salamanders")
	await _frames(2)
	var difficulty = null
	for c in menu.get_children():
		if _is(c, "DifficultySelectDialog"):
			difficulty = c
	var open_levels = []
	for level in range(1, 8):
		var card = difficulty.find_child("Difficulty_%d" % level, true, false) if difficulty else null
		if card and not card.disabled:
			open_levels.append(level)
	_check("выбрали орден → окно сложности: открыты %s из 7, фокус на 3-й, забег не начат" % [open_levels],
		difficulty != null and open_levels == [1, 2, 3] and current_scene == menu
		and root.get_viewport().gui_get_focus_owner() == difficulty.find_child("Difficulty_3", true, false))
	difficulty.choose(4)   # закрытая — ничего
	await _frames(2)
	_check("закрытую сложность не выбрать", current_scene == menu and is_instance_valid(difficulty))
	difficulty.choose(3)
	await _frames(4)
	_check("выбрали сложность → магазин волны 1, раса, орден и сложность в забеге, в магазине есть пауза",
		current_scene.name == "ShopScene" \
		and root.get_node("EconomyManager").round_number == 1 \
		and root.get_node("RunManager").player_faction == "space_marines" \
		and root.get_node("RunManager").player_chapter == "salamanders" \
		and root.get_node("RunManager").difficulty == 3 \
		and current_scene.get_children().any(func(c): return _is(c, "PauseMenu")))

	# 6. Экран конца забега: пауза выключена, кнопка «В главное меню»
	gs.set_battle_speed(1.0)
	battle = await _battle_scene()
	battle._show_run_end(false)
	await _frames(2)
	_check("конец забега: пауза выключена", not battle.pause_menu.enabled)
	var screen = null
	for c in battle.get_node("UI").get_children():
		if _is(c, "RunEndScreen"):
			screen = c
	screen.emit_signal("main_menu_pressed")
	await _frames(4)
	_check("конец забега → главное меню", current_scene.name == "MainMenu")

	# 7. Выход посреди схватки — выбор «выйти / сдаться»; на расстановке — без вопросов
	battle = await _battle_scene()
	battle.pause_menu.open()
	battle.pause_menu._leave(battle.pause_menu._to_main_menu)
	await _frames(2)
	_check("расстановка: выход без вопроса", current_scene.name == "MainMenu")
	battle = await _battle_scene()
	battle._on_start_pressed()
	await _frames(10)
	battle.pause_menu.open()
	battle.pause_menu._leave(battle.pause_menu._to_main_menu)
	await _frames(2)
	var leave_dialog = battle.pause_menu._dialog
	_check("бой: выход → окно «выйти / сдаться», бой на паузе", leave_dialog != null \
		and current_scene == battle and paused and bm.is_battle_running())
	var eco = root.get_node("EconomyManager")
	var req_before = eco.requisition
	var round_at_surrender = eco.round_number
	battle.pause_menu._surrender_and(battle.pause_menu._to_main_menu)
	await _frames(4)
	_check("сдался → забег окончен: главное меню, сохранения нет, «Продолжить» скрыта", \
		current_scene.name == "MainMenu" and not paused and not bm.battle_in_progress \
		and not sv.has_save() and not current_scene.continue_button.visible)
	_check("сдался → доход не начислен, волна та же", eco.requisition == req_before \
		and eco.round_number == round_at_surrender)

	# 8. «Сдаться» в паузе: подтверждение; в магазине — забег окончен, главное меню
	bm.reset_run()
	root.get_node("RunManager").advance()
	await _frames(4)
	sv.save_run()
	var shop_pause = null
	for c in current_scene.get_children():
		if _is(c, "PauseMenu"):
			shop_pause = c
	shop_pause.open()
	shop_pause._confirm_surrender()
	var confirm = shop_pause._dialog
	_check("магазин: «Сдаться» → подтверждение, забег цел", confirm != null and _is(confirm, "ConfirmDialog") \
		and current_scene.name == "ShopScene" and sv.has_save())
	confirm._on_yes()
	await _frames(4)
	_check("магазин: сдался → главное меню, сохранения нет", current_scene.name == "MainMenu" and not paused \
		and not sv.has_save() and not current_scene.continue_button.visible)

	# 9. «Сдаться» в паузе посреди схватки — экран итога боя, сцена не меняется
	battle = await _battle_scene()
	battle._on_start_pressed()
	await _frames(10)
	battle.pause_menu.open()
	battle.pause_menu._confirm_surrender()
	battle.pause_menu._dialog._on_yes()
	await _frames(4)
	var end_screen = battle.get_node("UI").get_children().any(func(c): return _is(c, "RunEndScreen"))
	_check("бой: сдался из паузы → экран конца забега, пауза снята, сохранения нет", current_scene == battle \
		and end_screen and not paused and not bm.is_battle_running() and not sv.has_save() \
		and not battle.pause_menu.enabled)

	sv.delete_save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG_PATH))
	quit()
