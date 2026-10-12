extends SceneTree

# Архетипы врагов: состав обычной волны из EnemyWaves.ARCHETYPES по бюджету,
# случайный от seed забега и волны (переигровка боя — тот же состав).
# Сохранение выключено — забег игрока не трогает.
#   godot --headless --path . -s tests/test_enemy_waves.gd
const SEEDS: int = 200
const BATTLE: String = "battle"

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _units(specs: Array) -> Array:
	return specs.map(func(s): return s["unit"])

func _main() -> void:
	await process_frame

	# 1. Один seed и волна — один состав; разные seed — разные составы
	var same = true
	for w in range(1, 16):
		same = same and str(EnemyWaves.build(w, BATTLE, 9, 777)) == str(EnemyWaves.build(w, BATTLE, 9, 777))
	var variants = {}
	for s in range(1, 21):
		variants[str(_units(EnemyWaves.build(8, BATTLE, 9, s)))] = true
	_check("состав детерминирован от seed и волны, разные seed дают разные волны (%d вариантов)" % variants.size(),
		same and variants.size() >= 5)

	# 2. Архетипы открываются с волны from_wave, к 8-й встречаются все
	var early_ok = true
	var seen = {}
	for s in range(1, SEEDS + 1):
		for w in range(1, 9):
			for u in _units(EnemyWaves.build(w, BATTLE, 9, s)):
				early_ok = early_ok and w >= EnemyWaves.ARCHETYPES[u]["from_wave"]
				seen[u] = true
	_check("архетипы не раньше своей волны, к 8-й все 5 (%s)" % ",".join(seen.keys()),
		early_ok and seen.size() == EnemyWaves.ARCHETYPES.size())

	# 3. Доля архетипа ≤ max_share, строй: от переднего края к тылу по order
	var share_ok = true
	var order_ok = true
	for s in range(1, SEEDS + 1):
		for w in range(1, 16):
			var units = _units(EnemyWaves.build(w, BATTLE, 9, s))
			var counts = {}
			for u in units:
				counts[u] = counts.get(u, 0) + 1
			for u in counts:
				share_ok = share_ok and counts[u] <= maxi(ceili(units.size() * EnemyWaves.ARCHETYPES[u]["max_share"]), 1)
			for i in range(1, units.size()):
				order_ok = order_ok and EnemyWaves.ARCHETYPES[units[i - 1]]["order"] <= EnemyWaves.ARCHETYPES[units[i]]["order"]
	_check("доля архетипа не больше max_share", share_ok)
	_check("строй: чумные и культисты впереди, хавоки в тылу", order_ok)

	# 4. Сила волны ≈ бюджету (в бойцах Chaos Marine): от 70% до 125% —
	# округление числа бойцов: у рапторов и хавоков боец стоит 2–2.5 Chaos Marine
	var power_ok = true
	var worst = 1.0
	for s in range(1, SEEDS + 1):
		for w in range(1, 16):
			var specs = EnemyWaves.build(w, BATTLE, 9, s)
			var power = 0.0
			for sp in specs:
				power += sp["count"] * EnemyWaves.ARCHETYPES[sp["unit"]]["power"]
			var ratio = power / float(specs.size() * EnemyWaves.get_soldiers_per_squad(w))
			worst = ratio if absf(ratio - 1.0) > absf(worst - 1.0) else worst
			power_ok = power_ok and ratio >= 0.70 and ratio <= 1.25
	_check("сила волны в пределах 70–125%% бюджета (худшая %.2f)" % worst, power_ok)

	# 5. Босс и мини-босс по-прежнему на переднем крае, отрядов не больше клеток
	var boss = EnemyWaves.build(15, "boss", 9, 5)
	var mini_boss = EnemyWaves.build(10, "miniboss", 9, 5)
	var small = EnemyWaves.build(14, BATTLE, 4, 5)
	_check("босс и мини-босс впереди, состав не больше клеток зоны", boss[0]["unit"] == "chaos_lord"
		and mini_boss[0]["unit"] == "chaos_hellbrute" and mini_boss[1]["unit"] == "chaos_champion" and small.size() == 4)

	# 6. Юниты архетипов: id, роль, снаряд
	var ok_units = true
	for id in EnemyWaves.ARCHETYPES:
		var d = UnitFactory.create(id)
		ok_units = ok_units and d.factory_id == id and d.faction == "chaos"
	var raptor = UnitFactory.create("chaos_raptor")
	var plague = UnitFactory.create("plague_marine")
	var havoc = UnitFactory.create("chaos_havoc")
	_check("юниты: рапторы ищут стрелков, рапторы и чумные без снаряда, хавоки — charged", ok_units
		and raptor.priority == GameConstants.PRIORITY_RANGED_FIRST and raptor.projectile == ""
		and plague.projectile == "" and havoc.projectile == "charged")

	# 7. Бой: рапторы целятся в стрелков игрока за спинами бойцов ближнего боя
	var seed_with_raptor = 0
	for s in range(1, SEEDS + 1):
		if "chaos_raptor" in _units(EnemyWaves.build(6, BATTLE, 9, s)):
			seed_with_raptor = s
			break
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(seed_with_raptor)
	for n in rm.map.nodes:
		if n.type == BATTLE and n.wave == 6:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 6
	var army: Array[UnitData] = []
	for id in ["assault_marine", "tactical_marine"]:
		var d = UnitFactory.create(id)
		d.saved_hp = [1.0, 1.0] as Array[float]
		army.append(d)
	bm.player_units = army
	bm.player_placements = {army[0]: Vector2i(2, 1), army[1]: Vector2i(0, 1)}
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var raptors = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(1) \
		.filter(func(s): return s.data.factory_id == "chaos_raptor")
	Engine.time_scale = 4.0
	scene._on_start_pressed()
	# Цель появляется, когда враг в поле зрения: запоминаем первую цель каждого раптора
	var first_target = {}
	var frames = 0
	while first_target.size() < raptors.size() and bm.is_battle_running() and frames < 2000:
		await process_frame
		frames += 1
		for r in raptors:
			if is_instance_valid(r) and r.target != null and not first_target.has(r):
				first_target[r] = "ranged" in r.target.data.tags
	Engine.time_scale = 1.0
	_check("бой: первая цель у %d/%d рапторов — стрелок" % [first_target.values().count(true), raptors.size()],
		not raptors.is_empty() and first_target.size() == raptors.size() and first_target.values().all(func(v): return v))
	_check("seed забега задан (состав переигрываемого боя тот же)", rm.rng.seed == seed_with_raptor and seed_with_raptor != 0)
	bm.stop_battle()
	scene.queue_free()
	await process_frame
	quit()
