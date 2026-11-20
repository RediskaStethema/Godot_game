extends SceneTree

# Построение перед боем (решение пользователя 23.10.2026, ориентир — 9 Kings):
# 1) «В БОЙ» — армия идёт строиться, бой ещё не идёт; встали — бой стартует сам;
# 2) все отряды игрока — за передним краем королевства (за стеной владений);
# 3) ближний бой впереди стрелков и лекарей (ближе к врагу по оси наступления);
# 4) клетка отряда не меняется (бонус ряда и соседство зданий — по ней);
# 5) враги: ближний бой — в передних клетках зоны, стрелки — в задних;
# 6) на паузе построение стоит.
#   godot --headless --path . -s tests/test_deploy.gd
func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _unit(id: String, count: int) -> UnitData:
	var d = UnitFactory.create(id)
	var hp: Array[float] = []
	for i in range(count):
		hp.append(1.0)
	d.saved_hp = hp
	d.squad_size = count
	return d

func _scene(wave: int):
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(5)
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == wave:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = wave
	var army: Array[UnitData] = []
	var placements = {}
	for p in [["devastator", Vector2i(2, 2), 6], ["tactical_marine", Vector2i(2, 1), 9],
			["assault_marine", Vector2i(0, 0), 6], ["terminator", Vector2i(0, 2), 6],
			["apothecary", Vector2i(2, 0), 2], ["dreadnought", Vector2i(1, 1), 2]]:
		var d = _unit(p[0], p[2])
		army.append(d)
		placements[d] = p[1]
	bm.player_units = army
	bm.player_placements = placements
	if current_scene:
		current_scene.queue_free()
		await process_frame
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	return scene

# Положение по оси наступления в клетках (col решётки; больше — ближе к врагу)
var _origin := Vector2.ZERO
func _u(p: Vector2) -> float:
	var l := p - _origin
	return (l.x / (IsoGrid.TILE_WIDTH / 2.0) + l.y / (IsoGrid.TILE_HEIGHT / 2.0)) / 2.0

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var reg = root.get_node("SquadRegistry")

	# 1, 6. С ходом: бой не идёт, на паузе стоит, потом стартует сам
	var scene = await _scene(6)
	var tiles := {}
	for sq in reg.get_alive_squads_of_team(0):
		tiles[sq] = sq.tile
	scene._on_start_pressed()
	await process_frame
	var deploying: bool = scene.is_deploying and not bm.is_battle_running()
	var sq0 = reg.get_alive_squads_of_team(0)[0]
	paused = true
	var p0: Vector2 = sq0.global_position
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300:
		await process_frame
	var still: bool = sq0.global_position == p0
	paused = false
	t0 = Time.get_ticks_msec()
	while not bm.is_battle_running() and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	_check("«В БОЙ» — армия строится, бой не идёт; на паузе стоит; встала — бой сам",
		deploying and still and bm.is_battle_running() and not scene.is_deploying)

	# 2–4. Где встали (тот же бой, первые кадры схватки)
	_origin = scene.iso_grid.player_origin
	var edge: float = scene.iso_grid.grid_width - 0.5
	var outside := true
	var front_u := INF
	var back_u := -INF
	var same_tiles := true
	for sq in reg.get_alive_squads_of_team(0):
		var u := _u(sq.global_position)
		outside = outside and u > edge
		var is_back: bool = sq.data.attack_range > scene.DEPLOY_BACK_RANGE or sq.data.heal_per_second > 0.0
		if is_back:
			back_u = maxf(back_u, u)
		else:
			front_u = minf(front_u, u)
		same_tiles = same_tiles and tiles.get(sq) == sq.tile
	_check("Все отряды — за передним краем королевства", outside)
	_check("Ближний бой впереди стрелков и лекарей (%.2f > %.2f)" % [front_u, back_u], front_u > back_u)
	_check("Клетка отряда не меняется (бонусы ряда и зданий)", same_tiles)

	# 5. Враги: ближний бой — в передних клетках зоны (col меньше), стрелки — в задних
	var enemy_ok := true
	var max_front_col := -1
	var min_back_col := 99
	var has_back := false
	for w in [3, 8, 12]:
		scene = await _scene(w)
		for sq in reg.get_alive_squads_of_team(1):
			if sq.data.attack_range > scene.DEPLOY_BACK_RANGE or sq.data.heal_per_second > 0.0:
				min_back_col = mini(min_back_col, sq.tile.x * 3 + sq.tile.y)
				has_back = true
			else:
				max_front_col = maxi(max_front_col, sq.tile.x * 3 + sq.tile.y)
		enemy_ok = enemy_ok and (not has_back or max_front_col < min_back_col)
		max_front_col = -1
		min_back_col = 99
		has_back = false
	_check("Враги: ближний бой в передних клетках зоны, стрелки — за ним", enemy_ok)

	# Без хода (тесты, balance_sim): сразу на местах и в бою
	scene = await _scene(6)
	scene._on_start_pressed(false)
	_check("Без хода — бой сразу", bm.is_battle_running() and not scene.is_deploying)
	bm.stop_battle()

	# 7. Большая армия (17.11.2026): линии не глубже DEPLOY_MAX_DEPTH, передняя — не в зоне врага
	bm.reset_run()
	var rm = root.get_node("RunManager")
	rm.new_run(5)
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == 10:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 10
	var big: Array[UnitData] = []
	var big_pl = {}
	var ids := ["tactical_marine", "assault_marine", "devastator", "terminator", "scout_marine", "apothecary"]
	var tiles16: Array[Vector2i] = []   # королевство 4×4 — 16 отрядов, предел игры (IsoGrid.MAX_KINGDOM_TILES)
	for x in 4:
		for y in 4:
			tiles16.append(Vector2i(x, y))
	bm.kingdom_tiles = tiles16
	for i in 16:
		var d = _unit(ids[i % ids.size()], 6)
		big.append(d)
		big_pl[d] = Vector2i(i % 4, i / 4)
	bm.player_units = big
	bm.player_placements = big_pl
	current_scene.queue_free()
	await process_frame
	scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var squads: Array = reg.get_alive_squads_of_team(0)
	var slots: Dictionary = scene._deploy_slots(squads)
	_origin = scene.iso_grid.player_origin
	var max_u := -INF
	var lines := {}
	for sq in slots:
		var su := _u(slots[sq])
		max_u = maxf(max_u, su)
		lines[snappedf(su, 0.05)] = true
	var enemy_start: float = scene.iso_grid.grid_width + scene.iso_grid.gap_tiles
	_check("Большая армия (%d отрядов): передняя линия u %.2f не заходит в зону врага (с %.1f), линий %d ≤ 3" % [squads.size(), max_u, enemy_start, lines.size()],
		squads.size() >= 14 and max_u < enemy_start - 1.0 and lines.size() <= 3 and slots.size() == squads.size())
	quit()
