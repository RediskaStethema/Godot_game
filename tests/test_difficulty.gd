extends SceneTree

# Уровни сложности (Difficulty): 7 уровней, открыты 3, уровень 2 — прежний баланс; выше —
# больше бойцов в отрядах волн и чаще / раньше сильные архетипы. Победа над боссом на самом
# высоком открытом уровне открывает следующий (профиль SaveManager, свой файл теста).
#   godot --headless --path . -s tests/test_difficulty.gd
const TEST_PROFILE_PATH: String = "user://test_difficulty_profile.cfg"
const BATTLE: String = "battle"
const SEEDS = [1, 7, 42, 99, 777, 1234, 5000, 31337]

func _initialize() -> void:
	root.get_node("SaveManager").enabled = true   # профиль пишется — свой файл, забег не сохраняем
	root.get_node("SaveManager").save_path = "user://test_difficulty_save.json"
	root.get_node("SaveManager").profile_path = TEST_PROFILE_PATH
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _remove_profile() -> void:
	if FileAccess.file_exists(TEST_PROFILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE_PATH))

# Бойцов в обычных волнах 1..15 и доля сильных отрядов на волнах 8..15 по SEEDS
func _stats(level: int) -> Vector2:
	var soldiers = 0
	var squads = 0
	var strong = 0
	for s in SEEDS:
		for w in range(1, 16):
			for sp in EnemyWaves.build(w, BATTLE, 9, s, level):
				soldiers += sp["count"]
				if w >= 8:
					squads += 1
					if sp["unit"] in Difficulty.STRONG:
						strong += 1
	return Vector2(soldiers, float(strong) / squads)

func _main() -> void:
	await process_frame
	var sv = root.get_node("SaveManager")

	# 1. Таблица: 7 уровней, уровень 2 — без поправок, числа растут с уровнем
	var grows = true
	for i in range(1, Difficulty.COUNT):
		var a = Difficulty.get_level(i)
		var b = Difficulty.get_level(i + 1)
		grows = grows and b["enemies"] > a["enemies"] and b["strong_weight"] > a["strong_weight"] \
			and b["strong_earlier"] >= a["strong_earlier"] and b["strong_share"] >= a["strong_share"]
	var d2 = Difficulty.get_level(Difficulty.DEFAULT)
	_check("7 уровней, открыто 3, уровень 2 — прежний баланс, сложность растёт",
		Difficulty.COUNT == 7 and Difficulty.START_UNLOCKED == 3 and Difficulty.DEFAULT == 2 and grows
		and d2["enemies"] == 1.0 and d2["strong_weight"] == 1.0 and d2["strong_earlier"] == 0)

	# 2. Уровень 2 даёт тот же состав, что и без уровня (прежний баланс); составы детерминированы
	var same = true
	for s in SEEDS:
		for w in range(1, 16):
			same = same and str(EnemyWaves.build(w, BATTLE, 9, s)) == str(EnemyWaves.build(w, BATTLE, 9, s, 2)) \
				and str(EnemyWaves.build(w, BATTLE, 9, s, 6)) == str(EnemyWaves.build(w, BATTLE, 9, s, 6))
	_check("уровень 2 = прежние волны, любой уровень повторяется от seed", same)

	# 3. Больше врагов и больше сильных отрядов с уровнем
	var st = []
	for level in [1, 2, 4, 7]:
		st.append(_stats(level))
	_check("бойцов в волнах 1–15: %s; доля сильных отрядов (волны 8–15): %s" % [
		st.map(func(v): return int(v.x)), st.map(func(v): return "%.2f" % v.y)],
		st[0].x < st[1].x and st[1].x < st[2].x and st[2].x < st[3].x
		and st[0].y <= st[1].y and st[1].y < st[2].y and st[2].y < st[3].y)

	# 4. Сильные — раньше: на уровне 6 Havoc (с 3-й) и Raptor (с 4-й) бывают уже на 1–2-й волне
	var early = false
	for s in range(1, 200):
		for w in [1, 2]:
			for sp in EnemyWaves.build(w, BATTLE, 9, s, 6):
				early = early or sp["unit"] in ["chaos_havoc", "chaos_raptor"]
	var early_default = false
	for s in range(1, 200):
		for sp in EnemyWaves.build(2, BATTLE, 9, s, 2):
			early_default = early_default or sp["unit"] in ["chaos_havoc", "chaos_raptor"]
	_check("уровень 6: Havoc / Raptor на 1–2-й волне, на уровне 2 — нет", early and not early_default)

	# 5. Профиль: свежий — открыто 3; победа ниже предела ничего не открывает; на пределе — следующий
	_remove_profile()
	sv.load_profile()
	var fresh = sv.unlocked_difficulty
	var low = sv.on_run_won(2)
	var opened = sv.on_run_won(3)
	sv.unlocked_difficulty = 0
	sv.load_profile()   # открытое — в файле профиля
	var reloaded = sv.unlocked_difficulty
	sv.unlocked_difficulty = Difficulty.COUNT
	var at_max = sv.on_run_won(Difficulty.COUNT)
	_check("профиль: свежий %d, победа на 2 → %d, на 3 → открыт %d, после перезагрузки %d, на 7 — ничего" % [
		fresh, low, opened, reloaded], fresh == 3 and low == 0 and opened == 4 and reloaded == 4 and at_max == 0
		and sv.is_difficulty_unlocked(4) and not sv.is_difficulty_unlocked(8))

	# 6. Бой с боссом выигран на самом высоком открытом уровне → открыт следующий, сказано в итоге
	_remove_profile()
	sv.load_profile()
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(5)
	rm.difficulty = 3
	for n in rm.map.nodes:
		if n.type == "boss":
			rm.current_node_id = n.id
			rm.current_completed = false
	root.get_node("EconomyManager").round_number = 15
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	scene._on_battle_ended(GameConstants.TEAM_PLAYER)
	await process_frame
	var screen = null
	for c in scene.get_node("UI").get_children():
		if c.get_script() and c.get_script().get_global_name() == "RunEndScreen":
			screen = c
	var texts = []
	if screen:
		for l in screen.find_children("*", "Label", true, false):
			texts.append(l.text)
	var text = "\n".join(texts)
	_check("босс повержен на 3 → открыт 4, на экране итога: «Открыта новая сложность», «Сложность 3»",
		sv.unlocked_difficulty == 4 and "Открыта новая сложность: Сложность 4" in text and "Сложность 3 · Седоусый" in text)

	scene.queue_free()
	bm.reset_run()
	_remove_profile()
	sv.delete_save()
	quit()
