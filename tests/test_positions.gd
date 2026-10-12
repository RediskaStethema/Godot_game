extends SceneTree

# Бонусы рядов королевства (TDD [frontline] / [backline]): передний ряд — +10% HP,
# задний ряд — +15% урона стрелкам. Сохранение выключено — забег игрока не трогает.
#   godot --headless --path . -s tests/test_positions.gd
const EPS: float = 0.001

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _near(a: float, b: float) -> bool:
	return absf(a - b) < EPS * maxf(absf(b), 1.0)

func _squad_at(squads: Array, tile: Vector2i):
	for s in squads:
		if s.tile == tile:
			return s
	return null

func _main() -> void:
	await process_frame
	var syn = root.get_node("SynergyManager")
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")

	# 1. Ряды: 3×3 — col 2 впереди, col 0 сзади, col 1 без бонуса; один ряд — без бонусов
	var k3: Array[Vector2i] = []
	for row in range(3):
		for col in range(3):
			k3.append(Vector2i(col, row))
	var one_col: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1)]
	_check("ряды 3×3: впереди / средний / сзади, королевство в один ряд — без бонусов",
		syn.get_tile_position(Vector2i(2, 1), k3) == syn.FRONT and syn.get_tile_position(Vector2i(1, 1), k3) == ""
		and syn.get_tile_position(Vector2i(0, 2), k3) == syn.BACK and syn.get_tile_position(Vector2i(0, 0), one_col) == "")

	# 2. Купленная клетка в 4-м ряду делает передним его
	var k4 = k3.duplicate()
	k4.append(Vector2i(3, 1))
	_check("клетка в новом ряду: передний ряд — col 3, col 2 — средний",
		syn.get_tile_position(Vector2i(3, 1), k4) == syn.FRONT and syn.get_tile_position(Vector2i(2, 1), k4) == "")

	# 3. Бой: одинаковые отряды в разных рядах
	bm.reset_run()
	rm.new_run(42)
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	var plan = [["tactical_marine", Vector2i(2, 0)], ["tactical_marine", Vector2i(1, 1)], ["tactical_marine", Vector2i(0, 0)],
		["assault_marine", Vector2i(2, 2)], ["assault_marine", Vector2i(0, 2)]]
	var army: Array[UnitData] = []
	var placements = {}
	for p in plan:
		var d = UnitFactory.create(p[0])
		d.saved_hp = [1.0, 1.0] as Array[float]
		army.append(d)
		placements[d] = p[1]
	bm.player_units = army
	bm.player_placements = placements
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var squads = root.get_node("SquadRegistry").get_alive_squads_of_team(0).duplicate()
	var counts = syn.count_position_bonuses(squads)
	_check("расстановка: впереди 2 отряда, сзади 1 стрелок (рукопашник сзади не считается)",
		counts[syn.FRONT] == 2 and counts[syn.BACK] == 1)
	var front_info: String = load("res://scenes/battle/ui/SquadInspector.gd").describe(_squad_at(squads, Vector2i(2, 0)))
	var mid_info: String = load("res://scenes/battle/ui/SquadInspector.gd").describe(_squad_at(squads, Vector2i(1, 1)))
	_check("справка отряда называет его ряд", "Передний ряд" in front_info and not "ряд:" in mid_info)

	scene._on_start_pressed()
	var tac_front = _squad_at(squads, Vector2i(2, 0)).soldiers[0]
	var tac_mid = _squad_at(squads, Vector2i(1, 1)).soldiers[0]
	var tac_back = _squad_at(squads, Vector2i(0, 0)).soldiers[0]
	var as_front = _squad_at(squads, Vector2i(2, 2)).soldiers[0]
	var as_back = _squad_at(squads, Vector2i(0, 2)).soldiers[0]
	_check("передний ряд: +10%% HP (%.1f против %.1f), HP полное" % [tac_front.max_hp, tac_mid.max_hp],
		_near(tac_front.max_hp, tac_mid.max_hp * 1.10) and _near(tac_front.current_hp, tac_front.max_hp)
		and _near(as_front.max_hp, as_back.max_hp * 1.10))
	_check("задний ряд: +15%% урона стрелкам (%.2f против %.2f), рукопашнику — нет" % [tac_back.current_damage, tac_mid.current_damage],
		_near(tac_back.current_damage, tac_mid.current_damage * 1.15) and _near(as_back.current_damage, as_front.current_damage)
		and _near(tac_back.max_hp, tac_mid.max_hp))
	_check("данные отрядов не тронуты (бонус — только runtime-поля)",
		army.all(func(d): return _near(d.hp_multiplier, 1.0) and _near(d.damage_multiplier, 1.0)))
	bm.stop_battle()
	scene.queue_free()
	await process_frame
	quit()
