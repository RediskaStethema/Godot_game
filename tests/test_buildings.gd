extends SceneTree

# Здания: улучшение такой же картой (до CardData.MAX_BUILDING_LEVEL), статы по
# уровню, прозрачность построек только на расстановке.
#   godot --headless --path . -s tests/test_buildings.gd

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _frames(n: int) -> void:
	for i in range(n): await process_frame

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(3)
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	bm.player_buildings[CardFactory.bolter_turret()] = Vector2i(0, 0)
	bm.player_buildings[CardFactory.fortress_wall()] = Vector2i(1, 1)
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(3)
	var battle = current_scene

	var tower = battle._get_player_building_at(Vector2i(0, 0))
	var wall = battle._get_player_building_at(Vector2i(1, 1))
	_check("здания на поле, 1-й уровень", tower != null and wall != null \
		and tower.card.building_level == 1 and wall.card.building_level == 1)

	# Турель: такая же карта на неё — уровень +1, статы растут
	var dmg1: float = tower.stats["damage"]
	var spd1: float = tower.stats["attack_speed"]
	var ok2 = battle._play_building_card(CardFactory.bolter_turret(), Vector2i(0, 0))
	_check("турель → ур.2: +25% урона, +20% скорострельности", ok2 and tower.card.building_level == 2 \
		and is_equal_approx(tower.stats["damage"], dmg1 * 1.25) and is_equal_approx(tower.stats["attack_speed"], spd1 * 1.2))
	var ok3 = battle._play_building_card(CardFactory.bolter_turret(), Vector2i(0, 0))
	var ok4 = battle._play_building_card(CardFactory.bolter_turret(), Vector2i(0, 0))
	_check("турель → ур.3 (множители копятся), 4-я карта не тратится", ok3 and not ok4 \
		and tower.card.building_level == 3 and is_equal_approx(tower.stats["damage"], dmg1 * 1.25 * 1.25))
	_check("база карты не меняется", is_equal_approx(tower.card.building_stats["damage"], dmg1))

	# Стена: щит и радиус замедления; чужая карта здания на неё — «занято»
	var shield1: float = wall.get_citadel_shield()
	var radius1: float = wall.stats["slow_radius"]
	_check("турель на стену — не улучшение", not battle._play_building_card(CardFactory.bolter_turret(), Vector2i(1, 1)) \
		and wall.card.building_level == 1)
	battle._play_building_card(CardFactory.fortress_wall(), Vector2i(1, 1))
	_check("стена → ур.2: щит +50%, радиус +20%", wall.card.building_level == 2 \
		and is_equal_approx(wall.get_citadel_shield(), shield1 * 1.5) and is_equal_approx(wall.stats["slow_radius"], radius1 * 1.2))
	_check("уровень на карте в забеге (сохранится)", bm.player_buildings.keys().any(
		func(c): return c.id == "fortress_wall" and c.building_level == 2))

	# Прозрачность: на расстановке включена, после «В БОЙ» — выключена, постройки непрозрачны
	_check("расстановка: прозрачность включена", battle.fader.enabled)
	tower.self_modulate.a = 0.35
	battle._on_start_pressed()
	await _frames(30)
	_check("бой: прозрачность выключена, постройки непрозрачны", not battle.fader.enabled \
		and is_equal_approx(tower.self_modulate.a, 1.0))
	var shield_expected = shield1 * 1.5
	_check("щит цитадели в бою — по уровню стены", bm.citadel_shield <= shield_expected + 0.01 \
		and bm.citadel_shield > 0.0)

	bm.stop_battle()

	# Plasma Generatorium: доход после боя по уровню (2 → 3 → 5)
	bm.reset_run()
	var eco = root.get_node("EconomyManager")
	var gen = CardFactory.plasma_generatorium()
	bm.player_buildings[gen] = Vector2i(0, 0)
	var req0 = eco.requisition
	var inc1 = eco.collect_building_income(bm.player_buildings)
	gen.level_up_building()
	var inc2 = eco.collect_building_income(bm.player_buildings)
	gen.level_up_building()
	var inc3 = eco.collect_building_income(bm.player_buildings)
	_check("генератор: +2 / +3 / +5 Req по уровням", inc1 == 2 and inc2 == 3 and inc3 == 5 \
		and eco.requisition == req0 + 10)

	# Apothecarion: павший боец отряда на соседней клетке (крест) встаёт с 30% HP, второй раз — нет;
	# отряд по диагонали — не встаёт
	bm.reset_run()
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	eco.round_number = 1
	var apo = CardFactory.apothecarion()
	apo.building_stats["revive_chance"] = 1.0   # для теста — всегда
	bm.player_buildings[apo] = Vector2i(1, 0)
	var u = UnitFactory.create("tactical_marine")
	u.squad_size = 3
	u.saved_hp = [1.0, 1.0, 1.0] as Array[float]
	var diag = UnitFactory.create("tactical_marine")
	diag.squad_size = 3
	diag.saved_hp = [1.0, 1.0, 1.0] as Array[float]
	bm.player_units = [u, diag] as Array[UnitData]
	bm.player_placements[u] = Vector2i(0, 0)
	bm.player_placements[diag] = Vector2i(0, 1)   # по диагонали от (1, 0)
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(3)
	var alive = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(0)
	var s = alive.filter(func(x): return x.get("parent_squad").tile == Vector2i(0, 0))[0]
	var sd = alive.filter(func(x): return x.get("parent_squad").tile == Vector2i(0, 1))[0]
	sd.take_damage(sd.max_hp * 5.0)
	var diag_dead = sd.current_hp <= 0.0
	s.take_damage(s.max_hp * 5.0)
	var revived = s.current_hp > 0.0 and is_equal_approx(s.current_hp, s.max_hp * 0.3)
	s.take_damage(s.max_hp * 5.0)
	_check("апотекарион: сосед по стороне встал с 30% HP, второй раз — пал; по диагонали — не встал", revived \
		and not root.get_node("SoldierRegistry").get_alive_soldiers_of_team(0).has(s) and diag_dead)
	var lvl = CardFactory.apothecarion()
	lvl.level_up_building()
	lvl.level_up_building()
	_check("апотекарион ур.3: шанс 15% → ≈26.6%", \
		absf(lvl.get_building_stats()["revive_chance"] - 0.15 * 1.33 * 1.33) < 0.001)

	bm.stop_battle()
	quit()
