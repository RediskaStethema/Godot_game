extends SceneTree

# Ордены (Chapters): одна и та же армия в начале боя с каждым орденом против
# боя без ордена — бонусы в runtime-полях бойцов и статах зданий.
# Сохранение выключено — забег игрока не трогает.
#   godot --headless --path . -s tests/test_chapters.gd
const EPS: float = 0.001

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _near(a: float, b: float) -> bool:
	return absf(a - b) < EPS * maxf(absf(b), 1.0)

# Бой волны 1 с орденом: статы первого бойца каждого вида и здания после «В БОЙ»
func _snapshot(chapter: String) -> Dictionary:
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(11)
	rm.player_chapter = chapter
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	var army: Array[UnitData] = []
	var placements = {}
	for p in [["tactical_marine", Vector2i(1, 0)], ["assault_marine", Vector2i(1, 2)]]:
		var d = UnitFactory.create(p[0])
		d.saved_hp = [1.0, 1.0] as Array[float]
		army.append(d)
		placements[d] = p[1]
	bm.player_units = army
	bm.player_placements = placements
	bm.player_buildings[CardFactory.fortress_wall()] = Vector2i(0, 0)
	bm.player_buildings[CardFactory.bolter_turret()] = Vector2i(0, 2)
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	scene._on_start_pressed(false)
	var out = {"shield": bm.citadel_shield, "chapter_line": "Орден" in "\n".join(load("res://scenes/battle/ui/BattleHud.gd").synergy_lines())}
	for s in root.get_node("SoldierRegistry").get_alive_soldiers_of_team(0):
		if not out.has(s.data.factory_id):
			out[s.data.factory_id] = {"range": s.current_attack_range, "damage": s.current_damage,
				"move": s.current_move_speed, "attack_speed": s.current_attack_speed,
				"status": s._on_hit_status()[0], "node": s}
	for b in bm.buildings:
		if b.building_type == "tower":
			out["turret_damage"] = b.stats["damage"]
	out["card_damage"] = bm.player_buildings.keys().filter(func(c): return c.building_type == "tower")[0].get_building_stats()["damage"]
	return out

func _finish() -> void:
	root.get_node("BattleManager").stop_battle()
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	await process_frame

func _main() -> void:
	await process_frame
	var base = await _snapshot("")
	await _finish()
	var tb = base["tactical_marine"]
	var ab = base["assault_marine"]
	_check("без ордена: в панели строки ордена нет, огня при попадании нет", not base["chapter_line"] and tb["status"] == "")

	var u = await _snapshot("ultramarines")
	await _finish()
	_check("Ultramarines: +10%% дальности (%.0f → %.0f), урон тот же" % [tb["range"], u["tactical_marine"]["range"]],
		_near(u["tactical_marine"]["range"], tb["range"] * 1.10) and _near(u["assault_marine"]["range"], ab["range"] * 1.10)
		and _near(u["tactical_marine"]["damage"], tb["damage"]) and u["chapter_line"])

	var ba = await _snapshot("blood_angels")
	await _finish()
	# Минус ордена (решение пользователя 18.10.2026): Красная жажда — стрелкам −15% урона
	_check("Blood Angels: +15% урона ближнему бою, стрелкам −15% (минус ордена)",
		_near(ba["assault_marine"]["damage"], ab["damage"] * 1.15) and _near(ba["tactical_marine"]["damage"], tb["damage"] * 0.85))

	var sw = await _snapshot("space_wolves")
	await _finish()
	_check("Space Wolves: +15% бега и атаки",
		_near(sw["tactical_marine"]["move"], tb["move"] * 1.15) and _near(sw["assault_marine"]["attack_speed"], ab["attack_speed"] * 1.15))

	var imf = await _snapshot("imperial_fists")
	await _finish()
	_check("Imperial Fists: щит стены ×1.5 (%.0f → %.0f), урон турели ×1.2, карта не тронута" % [base["shield"], imf["shield"]],
		_near(imf["shield"], base["shield"] * 1.5) and _near(imf["turret_damage"], base["turret_damage"] * 1.2)
		and _near(imf["card_damage"], base["card_damage"]))

	var sal = await _snapshot("salamanders")
	var t = sal["tactical_marine"]
	_check("Salamanders: попадания поджигают (у бойцов — burning), статы те же", t["status"] == StatusEffects.BURNING
		and sal["assault_marine"]["status"] == StatusEffects.BURNING and _near(t["damage"], tb["damage"]))
	var a = sal["assault_marine"]["node"]
	var enemy = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(1)[0]
	enemy.global_position = a.global_position + Vector2(30, 0)
	a.target = enemy
	a._do_attack()
	# У Assault удар — на кадре замаха (hit_frame листа): тики до него
	var frames: SpriteFrames = a.sprite.sprite_frames
	var hit_time: float = maxf(frames.get_meta("hit_frame", 0), 0) / frames.get_animation_speed("attack")
	for i in ceili(hit_time / GameConstants.FIXED_TICK) + 1:
		a._tick_melee_hit(GameConstants.FIXED_TICK)
	_check("Salamanders: удар бойца ближнего боя поджёг цель", enemy.get_status_stacks(StatusEffects.BURNING) == 1)
	await _finish()
	quit()
