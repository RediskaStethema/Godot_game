extends SceneTree

# Казармы (Barracks): после каждого выигранного боя отрядам на соседних клетках (по сторонам, не по диагонали)
# лечат живых (20 / 30 / 45%) и возвращают павших 2 / 3 / 4 по уровням, с полным HP, не больше состава.
# Святилище культа (Хаос, решение пользователя 21.10.2026): не лечит; отряд бога рядом — павшие других
# соседей встают бойцами бога (сила по редкости отряда), отряд хранит тип бойца между боями.
# Сохранение выключено — забег игрока не трогает.
#   godot --headless --path . -s tests/test_barracks.gd
const EPS: float = 0.001

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

# Отряд Tactical (9 бойцов по составу) с alive живыми бойцами по hp доли
func _squad(alive: int, hp: float = 0.5) -> UnitData:
	var card = CardFactory.tactical_squad()
	var d = UnitFactory.create(card.unit_factory_id)
	d.squad_size = card.unit_count
	d.squad_growth = UnitFactory.squad_growth_for(card)
	var list: Array[float] = []
	for i in alive:
		list.append(hp)
	d.saved_hp = list
	return d

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")

	# 1. Карта: Common 7 (решение пользователя), 3 копии в пуле; пополнение 2 → 3 → 4 по уровням
	var card = CardFactory.barracks()
	var refills = []
	for i in 3:
		refills.append(floori(card.get_building_stats()["refill"]))
		card.level_up_building()
	var in_pool = CardFactory.build_pool().filter(func(c): return c.id == "barracks").size()
	_check("карта: Common %d Req, в пуле %d, пополнение по уровням %s" % [card.cost, in_pool, refills],
		card.rarity == "common" and card.cost == 7 and in_pool == 3 and refills == [2, 3, 4])

	# 2. Ход Казарм: соседи по сторонам пополнены (не лечены), диагональ и дальние — нет, полный — как был
	bm.reset_run()
	var side = _squad(4)        # (2,1) — справа от казарм
	var below = _squad(8)       # (1,2) — снизу: недостаёт 1 — вернётся 1, не 2
	var diagonal = _squad(4)    # (2,2) — по диагонали
	var full = _squad(9)        # (0,1) — слева, полный состав
	bm.player_units = [side, below, diagonal, full] as Array[UnitData]
	bm.player_placements = {side: Vector2i(2, 1), below: Vector2i(1, 2), diagonal: Vector2i(2, 2), full: Vector2i(0, 1)}
	bm.player_buildings = {CardFactory.barracks(): Vector2i(1, 1)}
	var total = bm.refill_from_barracks()
	_check("ход: +%d — сосед 4 → %d, сосед 8 → %d, диагональ %d, полный %d" % [total, side.saved_hp.size(),
		below.saved_hp.size(), diagonal.saved_hp.size(), full.saved_hp.size()],
		total == 3 and side.saved_hp.size() == 6 and below.saved_hp.size() == 9
		and diagonal.saved_hp.size() == 4 and full.saved_hp.size() == 9)
	_check("лечит: живые 0.5 → %.2f (+20%%), новые — с полным" % side.saved_hp[0],
		absf(side.saved_hp[0] - 0.7) < EPS and absf(side.saved_hp[3] - 0.7) < EPS
		and absf(side.saved_hp[4] - 1.0) < EPS and absf(side.saved_hp[5] - 1.0) < EPS
		and absf(diagonal.saved_hp[0] - 0.5) < EPS)

	# 3. Двое казарм рядом с одним отрядом — каждые дают своё; ур.3 — 4 бойца
	bm.reset_run()
	var between = _squad(1)
	bm.player_units = [between] as Array[UnitData]
	bm.player_placements = {between: Vector2i(1, 1)}
	var lvl3 = CardFactory.barracks()
	lvl3.level_up_building()
	lvl3.level_up_building()
	bm.player_buildings = {lvl3: Vector2i(0, 1), CardFactory.barracks(): Vector2i(1, 0)}
	_check("двое казарм (ур.3 и ур.1) — +4 и +2: %d бойцов" % (1 + bm.refill_from_barracks()), between.saved_hp.size() == 7)

	# 4. Бой выигран — в итоге боя «Казармы вернули бойцов: N», павшие вернулись
	bm.reset_run()
	var rm = root.get_node("RunManager")
	rm.new_run(3)
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	var army = _squad(9, 1.0)
	bm.player_units = [army] as Array[UnitData]
	bm.player_placements = {army: Vector2i(2, 1)}
	bm.player_buildings = {CardFactory.barracks(): Vector2i(1, 1)}
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	scene._on_start_pressed()
	await process_frame
	var mine = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(0).duplicate()
	for i in 3:
		mine[i].take_damage(99999.0)
	await process_frame
	var text: String = scene._resolve_battle(GameConstants.TEAM_PLAYER)
	_check("победа: «%s», отряд 6 → %d" % [text, army.saved_hp.size()],
		"Казармы вернули бойцов: 2" in text and army.saved_hp.size() == 8)

	bm.stop_battle()
	scene.queue_free()
	await process_frame

	# 5. Святилище культа: без отряда бога — свои бойцы и без лечения; с отрядом бога — павшие других соседей
	#    встают бойцами бога (сила ×0.7 для Common), сам отряд бога пополняется своими
	bm.reset_run()
	var shrine = CardFactory.create("cult_shrine")
	var marines = _chaos_squad("chaos_marines", 3)
	bm.player_units = [marines] as Array[UnitData]
	bm.player_placements = {marines: Vector2i(2, 1)}
	bm.player_buildings = {shrine: Vector2i(1, 1)}
	bm.refill_from_barracks()
	_check("Святилище без бога: свои бойцы %d, без лечения (%.2f), типов нет" % [marines.saved_hp.size(), marines.saved_hp[0]],
		marines.saved_hp.size() == 5 and absf(marines.saved_hp[0] - 0.5) < EPS and marines.saved_kinds.is_empty())
	bm.reset_run()
	marines = _chaos_squad("chaos_marines", 3)
	var god = _chaos_squad("khorne_berzerkers", 1)
	bm.player_units = [marines, god] as Array[UnitData]
	bm.player_placements = {marines: Vector2i(2, 1), god: Vector2i(1, 2)}
	bm.player_buildings = {shrine: Vector2i(1, 1)}
	bm.refill_from_barracks()
	var kind := UnitFactory.convert_kind("khorne_berzerkers", marines.rarity)
	_check("Святилище с богом: отряд 3 → %d, новые — %s; отряд бога пополнен своими (%s)" % [marines.saved_hp.size(),
		marines.saved_kinds.slice(3), god.saved_kinds],
		Array(marines.saved_kinds) == ["", "", "", kind, kind] and god.saved_kinds.is_empty()
		and god.saved_hp.size() == 3)
	var fighter := UnitFactory.convert_fighter(kind)
	var base := UnitFactory.create("khorne_berzerkers")
	var epic := UnitFactory.convert_fighter(UnitFactory.convert_kind("khorne_berzerkers", "epic"))
	_check("сила бойца бога по редкости: Common ×%.2f HP, Epic ×%.2f" % [fighter.get_max_hp() / base.get_max_hp(),
		epic.get_max_hp() / base.get_max_hp()],
		absf(fighter.get_max_hp() / base.get_max_hp() - 0.7) < EPS and absf(epic.get_max_hp() / base.get_max_hp() - 1.3) < EPS)

	# 6. Смешанный отряд: тип бойцов — в сохранении; на поле боец бога со своим листом; итог боя сохраняет типы
	var restored: UnitData = UnitData.from_save_state(marines.save_state())
	_check("сохранение: типы бойцов %s" % [restored.saved_kinds], Array(restored.saved_kinds) == Array(marines.saved_kinds))
	bm.reset_run()
	rm.new_run(3)
	rm.player_faction = "chaos"
	bm.player_units = [marines] as Array[UnitData]
	bm.player_placements = {marines: Vector2i(2, 1)}
	scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var on_field = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(0)
	var gods: Array = on_field.filter(func(s): return s.data.factory_id == "khorne_berzerkers")
	var squads = root.get_node("SquadRegistry").get_alive_squads_of_team(0)
	bm.sync_army_from_squads(squads)
	_check("на поле: бойцов %d, из них бога %d (лист %s); после сохранения расстановки типы те же" % [on_field.size(),
		gods.size(), gods[0].data.sprite_path.get_file() if not gods.is_empty() else "—"],
		on_field.size() == 5 and gods.size() == 2 and Array(marines.saved_kinds.slice(3)) == [kind, kind])
	bm.stop_battle()
	scene.queue_free()
	rm.player_faction = "space_marines"
	bm.reset_run()
	quit()

func _chaos_squad(card_id: String, alive: int, hp: float = 0.5) -> UnitData:
	var card = CardFactory.create(card_id)
	var d = UnitFactory.create(card.unit_factory_id)
	d.squad_size = card.unit_count
	d.squad_growth = UnitFactory.squad_growth_for(card)
	var list: Array[float] = []
	for i in alive:
		list.append(hp)
	d.saved_hp = list
	return d
