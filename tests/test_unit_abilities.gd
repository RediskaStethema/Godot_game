extends SceneTree

# Способности отрядов Космодесанта (решение пользователя 17.10.2026), данными в UnitData:
# 1) Assault — прыжок на вражеского стрелка ближе jump_range: полёт, удар по площади и оглушение
#    при приземлении, раз за бой; на бойцов ближнего боя не прыгает;
# 2) Devastator — окапывание: стоит на месте — урон до +30% за 2 с, сдвинулся — с нуля;
# 3) Terminator — Deep Strike: через 1 с марша отряд строем у ближайшего врага;
# 4) Land Speeder — стрельба на ходу: в ATTACK кружит вокруг цели, не выходя из дальности;
# 5) справка отряда и описания карт называют способность.
# Бойцы тикаются вручную (FIXED_TICK) на расстановке — бой не идёт.
#   godot --headless --path . -s tests/test_unit_abilities.gd
const TICK: float = 0.1

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _ticks(s, seconds: float) -> void:
	for i in range(roundi(seconds / TICK)):
		s.tick(TICK)

func _of(team: int, id: String) -> Array:
	return root.get_node("SoldierRegistry").get_alive_soldiers_of_team(team) \
		.filter(func(s): return s.data.factory_id == id)

# Отряд из count бойцов, сдвинутый так, что его центр — в точке at
func _squad(scene, id: String, team: int, tile: Vector2i, count: int, at: Vector2) -> Array:
	var old = _of(team, id)
	scene._spawn_squad(UnitFactory.create(id), team, tile, count)
	var list = _of(team, id).filter(func(s): return not s in old)
	var sq = list[0].parent_squad
	sq.global_position = at
	return list

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(3)
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	bm.player_units = [] as Array[UnitData]
	bm.player_placements = {}
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	# 1. Assault: вражеский стрелок в 250 px — прыжок к нему, удар и оглушение при приземлении
	var assault = _squad(scene, "assault_marine", 0, Vector2i(0, 0), 2, Vector2(0, 2000))
	var shooters = _squad(scene, "chaos_marine", 1, Vector2i(0, 0), 3, Vector2(250, 2000))
	var a = assault[0]
	for s in shooters:
		s.max_hp = 1000.0
		s.current_hp = 1000.0
	a.transition_to(a.State.MOVE)
	a.tick(TICK)
	var started = a.is_leaping() and a.jump_used
	var prey = a._leap_target   # ближайший из стрелков
	var hp0: float = prey.current_hp
	var flew := 0
	while a.is_leaping() and flew < 30:
		a.tick(TICK)
		flew += 1
	var landed_near = a.global_position.distance_to(prey.global_position) <= a.current_attack_range * 1.5
	var hit = prey.current_hp < hp0 and prey.current_state == prey.State.STUNNED
	_check("Assault прыгает на стрелка: полёт %.1f с, приземлился рядом, цель ранена и оглушена" % (flew * TICK),
		started and flew >= 3 and landed_near and hit and a.target == prey)
	# Второй раз не прыгает: стрелка отодвинули
	prey.global_position = a.global_position + Vector2(250, 0)
	a.transition_to(a.State.CHASE)
	a.tick(TICK)
	_check("прыжок — раз за бой", not a.is_leaping())

	# На бойцов ближнего боя не прыгает
	var a2 = assault[1]
	for s in shooters:
		s.global_position = Vector2(5000, 5000)
	var raptors = _squad(scene, "chaos_raptor", 1, Vector2i(1, 0), 2, a2.global_position + Vector2(250, 0))
	a2.transition_to(a2.State.MOVE)
	a2.tick(TICK)
	_check("на бойцов ближнего боя (рапторы) не прыгает", not a2.is_leaping() and not a2.jump_used)
	for s in raptors + shooters + assault:
		s.global_position = Vector2(-9000, -9000)

	# 2. Devastator: стоит и стреляет 2 с — окопался (+30%), отброс — с нуля
	var devs = _squad(scene, "devastator", 0, Vector2i(1, 1), 2, Vector2(0, 4000))
	var dummies = _squad(scene, "chaos_marine", 1, Vector2i(1, 1), 1, Vector2(250, 4000))
	dummies[0].max_hp = 100000.0
	dummies[0].current_hp = 100000.0
	var d = devs[0]
	d.target = dummies[0]
	d.transition_to(d.State.ATTACK)
	var b0: float = d.get_entrench_bonus()
	_ticks(d, 1.0)
	var b1: float = d.get_entrench_bonus()
	_ticks(d, 1.0)
	var dug = d.is_entrenched() and absf(d.get_entrench_bonus() - 0.3) < 0.001
	d.apply_knockback(Vector2(-1, 0), 200.0)
	d.tick(TICK)
	_check("Devastator окапывается: 0 → %.2f за 1 с → +30%% за 2 с, отброс — с нуля (%.2f)" % [b1, d.get_entrench_bonus()],
		b0 == 0.0 and b1 > 0.1 and b1 < 0.3 and dug and d.get_entrench_bonus() == 0.0)
	var walker = devs[1]
	walker.transition_to(walker.State.MOVE)
	dummies[0].global_position = walker.global_position + Vector2(2000, 0)   # вне поля зрения — идёт
	_ticks(walker, 2.0)
	_check("на марше не окапывается", walker.get_entrench_bonus() == 0.0)
	for s in devs + dummies:
		s.global_position = Vector2(-9000, -9000)

	# 3. Terminator: через 1 с марша — строем у ближайшего врага
	var terms = _squad(scene, "terminator", 0, Vector2i(2, 2), 6, Vector2(0, 6000))
	var foes = _squad(scene, "chaos_marine", 1, Vector2i(2, 2), 3, Vector2(900, 6000))
	for s in foes:
		s.max_hp = 100000.0
		s.current_hp = 100000.0
	var sq = terms[0].parent_squad
	sq.start_march()
	sq.tick(TICK)
	var before = terms[0].global_position.distance_to(foes[0].global_position) > 700.0
	_ticks(sq, 1.0)
	var close := true
	for t in terms:
		var nearest = INF
		for f in foes:
			nearest = minf(nearest, t.global_position.distance_to(f.global_position))
		close = close and nearest <= t.data.attack_range + sq.DEEP_STRIKE_GAP + 60.0
	_check("Terminator: Deep Strike через 1 с — все 6 у врага", before and sq.deep_struck and close)
	for s in terms + foes:
		s.global_position = Vector2(-9000, -9000)

	# 4. Land Speeder: в ATTACK кружит вокруг цели и стреляет, не выходя из дальности
	var speeders = _squad(scene, "land_speeder", 0, Vector2i(0, 1), 2, Vector2(0, 8000))
	var targets = _squad(scene, "chaos_marine", 1, Vector2i(0, 1), 1, Vector2(160, 8000))
	targets[0].max_hp = 100000.0
	targets[0].current_hp = 100000.0
	var ls = speeders[0]
	var tgt = targets[0]
	ls.global_position = Vector2(0, 8000)
	tgt.global_position = Vector2(160, 8000)
	ls.target = tgt
	ls.transition_to(ls.State.ATTACK)
	var p0: Vector2 = ls.global_position
	var in_range := true
	var shots := 0
	for i in range(20):
		var t_before: float = ls.attack_timer
		ls.tick(TICK)
		if ls.attack_timer > t_before:
			shots += 1
		in_range = in_range and ls.global_position.distance_to(tgt.global_position) <= ls.current_attack_range
	_check("Land Speeder стреляет на ходу: сдвинулся на %d px, выстрелов %d, цель в дальности" \
		% [roundi(ls.global_position.distance_to(p0)), shots],
		ls.global_position.distance_to(p0) > 40.0 and shots >= 1 and in_range and ls.current_state == ls.State.ATTACK)
	var tact = UnitFactory.create("tactical_marine")
	var tac = _squad(scene, "tactical_marine", 0, Vector2i(2, 0), 1, Vector2(0, 9000))
	tac[0].target = tgt
	tgt.global_position = Vector2(150, 9000)
	tac[0].transition_to(tac[0].State.ATTACK)
	_ticks(tac[0], 1.0)
	_check("Tactical в ATTACK стоит на месте", tac[0].global_position.distance_to(Vector2(0, 9000) + tac[0].formation_offset) < 1.0)

	# 5. Справка отряда и карты называют способность
	var Inspector = load("res://scenes/battle/ui/SquadInspector.gd")
	var texts_ok := true
	for id in ["assault_marine", "devastator", "terminator", "land_speeder"]:
		texts_ok = texts_ok and Inspector.ability_text(UnitFactory.create(id)) != ""
	var cards_ok = "прыга" in CardFactory.create("assault_squad").description \
		and "окапыва" in CardFactory.create("devastator_squad").description \
		and "Deep Strike" in CardFactory.create("terminator_squad").description \
		and "на ходу" in CardFactory.create("land_speeder").description
	_check("справка и карты называют способность; у Tactical — нет",
		texts_ok and cards_ok and Inspector.ability_text(tact) == "")

	scene.queue_free()
	await process_frame
	quit()
