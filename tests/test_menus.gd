extends SceneTree

# Пауза, настройки, скорость боя, выход в меню, подтверждение нового забега.
# Свои файлы сохранения и настроек — настройки и забег игрока не трогает.
#   godot --headless --path . -s tests/test_menus.gd
const TEST_SAVE_PATH: String = "user://test_menus_save.json"
const TEST_CONFIG_PATH: String = "user://test_menus_settings.cfg"

func _initialize() -> void:
	root.get_node("SaveManager").save_path = TEST_SAVE_PATH
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
	await _frames(4)
	_check("подтвердили → магазин волны 1, в магазине есть пауза", current_scene.name == "ShopScene" \
		and root.get_node("EconomyManager").round_number == 1 \
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

	sv.delete_save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG_PATH))
	quit()
