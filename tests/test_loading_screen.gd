extends SceneTree

# Экран загрузки (25.11.2026): needed() — только сцена боя, не в headless и пока кэши не тёплые; run() прогревает кэши,
# грузит сцену боя, меняет её и убирает экран. Запуск: godot --headless --path . -s tests/test_loading_screen.gd
const SCREEN := "res://scenes/ui/LoadingScreen.gd"
var _fails := 0

func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_fails += 1

func _initialize() -> void:
	root.get_node("GameSettings").battle_speed = 1.0
	root.get_node("SaveManager").enabled = false
	_main()

func _main() -> void:
	var S: Script = load(SCREEN)
	var rm = root.get_node("RunManager")
	_check("в headless экран не нужен (тесты меняют сцену синхронно)", not S.needed(rm.BATTLE_SCENE))
	_check("шагов прогрева не меньше четырёх, у каждого есть метод", S.STEPS.size() >= 4
		and S.STEPS.all(func(s): return S.new().has_method(s[1])))
	_check("подсказок несколько", S.TIPS.size() >= 4)
	root.get_node("BattleManager").reset_run()
	rm.new_run(7)
	for n in rm.map.nodes:
		if n.is_battle():
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	S.run(self, rm.BATTLE_SCENE)
	_check("пока идёт загрузка — экран занят", S.busy())
	await process_frame
	await process_frame
	var screen: Node = null
	for c in root.get_children():
		if c.get_script() == S:
			screen = c
	var corner_ok := false
	if screen != null:
		var sp: Control = screen.get("_spinner")
		corner_ok = sp != null and screen.get("_spin_textures").size() == S.SPIN_FRAMES and sp.anchor_right == 1.0 and sp.anchor_bottom == 1.0
		await create_timer(0.5).timeout
		corner_ok = corner_ok and sp.texture != screen.get("_spin_textures")[0]
	_check("круговая загрузка: 16 кадров, правый нижний угол, кадры сменяются", corner_ok)
	var guard := 0
	while (current_scene == null or current_scene.get_script() == null or not str(current_scene.scene_file_path).ends_with("BattleScene.tscn")) and guard < 3000:
		await process_frame
		guard += 1
	_check("сцена боя открыта", current_scene != null and str(current_scene.scene_file_path).ends_with("BattleScene.tscn"))
	_check("кэши помечены тёплыми", S.warmed)
	guard = 0
	while S.busy() and guard < 600:
		await create_timer(0.05).timeout
		guard += 1
	_check("экран убран, занятость снята", not S.busy())
	var left := 0
	for c in root.get_children():
		if c.get_script() == S:
			left += 1
	_check("узла экрана в дереве нет", left == 0)
	print("loading: %d fail" % _fails)
	quit()
