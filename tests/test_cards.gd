extends SceneTree

# Карты до 20 MVP: улучшения Iron Halo / Combat Stimms / Chapter Banner,
# события Emergency Reinforcements / Orbital Strike, пул магазина.
#   godot --headless --path . -s tests/test_cards.gd

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _frames(n: int) -> void:
	for i in range(n): await process_frame

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _squad_at(tile: Vector2i) -> Node:
	for s in root.get_node("SquadRegistry").get_alive_squads_of_team(0):
		if s.tile == tile:
			return s
	return null

func _battle(units: Array[UnitData]) -> Node:
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(11)
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	bm.player_units = units
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(3)
	return current_scene

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")

	# 1. Пул: 22 карты игрока (17 прежних + 5 MVP), ~60/30/10, новые карты есть
	var pool = CardFactory.build_pool()
	var ids = {}
	var by_rarity = {"common": 0, "rare": 0, "epic": 0}
	for c in pool:
		ids[c.id] = true
		by_rarity[c.rarity] += 1
	var share = func(r): return float(by_rarity[r]) / pool.size()
	_check("пул: %d разных карт (17 прежних + 5 MVP + 2 здания TDD), доли ~60/30/10 (%d / %d / %d копий)" % [ids.size(), by_rarity["common"], by_rarity["rare"], by_rarity["epic"]], ids.size() == 24 \
		and absf(share.call("common") - 0.6) < 0.05 and absf(share.call("rare") - 0.3) < 0.05 \
		and absf(share.call("epic") - 0.1) < 0.03)
	_check("новые карты в пуле", ["iron_halo", "combat_stimms", "chapter_banner",
		"emergency_reinforcements", "orbital_strike"].all(func(id): return ids.has(id)))

	# 2. Улучшения данными: щит, скорость, знамя; сохранение и сброс при возрождении
	var d = UnitFactory.create("tactical_marine")
	d.squad_size = 3
	d.apply_upgrade(CardFactory.iron_halo())
	d.apply_upgrade(CardFactory.combat_stimms())
	d.apply_upgrade(CardFactory.chapter_banner())
	var restored = UnitData.from_save_state(d.save_state())
	_check("улучшения: щит 0.3, скорость ×1.2, знамя 0.15 — и в сохранении", is_equal_approx(d.shield_ratio, 0.3) \
		and is_equal_approx(d.get_move_speed(), d.move_speed * 1.2) and is_equal_approx(d.banner_aura_bonus, 0.15) \
		and is_equal_approx(restored.shield_ratio, 0.3) and is_equal_approx(restored.move_speed_multiplier, 1.2) \
		and is_equal_approx(restored.banner_aura_bonus, 0.15))
	var old_save = d.save_state()
	old_save.erase("shield")
	old_save.erase("move_mult")
	old_save.erase("banner")
	var old = UnitData.from_save_state(old_save)
	_check("старое сохранение без новых полей грузится", old.shield_ratio == 0.0 and old.move_speed_multiplier == 1.0)
	d.respawn_after_wipe()
	_check("возрождение сбрасывает улучшения", d.shield_ratio == 0.0 and d.move_speed_multiplier == 1.0 \
		and d.banner_aura_bonus == 0.0)

	# 3. В бою: щит снимается раньше HP, знамя даёт ауру соседям
	var a = UnitFactory.create("tactical_marine")
	a.squad_size = 3
	a.saved_hp = [1.0, 1.0, 1.0] as Array[float]
	a.apply_upgrade(CardFactory.iron_halo())
	a.apply_upgrade(CardFactory.chapter_banner())
	var b = UnitFactory.create("assault_marine")
	b.squad_size = 2
	b.saved_hp = [1.0, 1.0] as Array[float]
	var units: Array[UnitData] = [a, b]
	var battle = await _battle(units)
	var halo_squad = null
	for s in root.get_node("SquadRegistry").get_alive_squads_of_team(0):
		if s.data == a:
			halo_squad = s
	var soldier = halo_squad.soldiers[0]
	var hp0 = soldier.current_hp
	var shield0 = soldier.shield
	soldier.take_damage(shield0 * 0.5)
	var hp_after_small = soldier.current_hp
	soldier.take_damage(shield0)
	_check("щит: %.0f, урон сначала по щиту, излишек — по HP" % shield0, shield0 > 0.0 \
		and is_equal_approx(hp_after_small, hp0) and is_equal_approx(soldier.current_hp, hp0 - shield0 * 0.5))
	var other = null
	for s in root.get_node("SoldierRegistry").get_alive_soldiers_of_team(0):
		if s.data == b:
			other = s
	other.global_position = soldier.global_position + Vector2(40, 0)
	var near_bonus = other.get_aura_damage_bonus()
	other.global_position = soldier.global_position + Vector2(UnitData.BANNER_RADIUS + 200, 0)
	var far_bonus = other.get_aura_damage_bonus()
	_check("знамя: сосед +15%%, далеко — нет (%.2f / %.2f)" % [near_bonus, far_bonus], \
		is_equal_approx(near_bonus, 0.15) and far_bonus < 0.15)

	# 4. Emergency Reinforcements: случайный Common отряд на пустую клетку, на занятую — нет
	var free_tile = Vector2i(2, 2)
	var occupied_tile = halo_squad.tile
	var ok_free = battle._play_event_card(CardFactory.emergency_reinforcements(), free_tile)
	var spawned = _squad_at(free_tile)
	var ok_busy = battle._play_event_card(CardFactory.emergency_reinforcements(), occupied_tile)
	_check("подкрепление: Common отряд полным составом; на занятую клетку — нет", ok_free and spawned != null \
		and UnitFactory.create(spawned.data.factory_id).rarity == "common" \
		and spawned.soldiers.size() == spawned.data.squad_size and not ok_busy)

	# 5. Orbital Strike: заряжен → сохраняется → в начале боя бьёт по скоплению
	_check("удар: карта заряжает событие", battle._play_event_card(CardFactory.orbital_strike(), free_tile) \
		and Array(bm.armed_events) == ["orbital_strike"])
	var saved = bm.save_state()
	bm.armed_events.clear()
	bm.load_state(saved)
	_check("удар: заряд переживает сохранение", Array(bm.armed_events) == ["orbital_strike"])
	var enemies = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(1)
	var hp_sum_before = 0.0
	for e in enemies:
		hp_sum_before += e.current_hp
	var enemy_count = enemies.size()
	battle._on_start_pressed()
	var hp_sum_after = 0.0
	for e in root.get_node("SoldierRegistry").get_alive_soldiers_of_team(1):
		hp_sum_after += e.current_hp
	_check("удар: в начале боя урон врагам (%.0f → %.0f HP), заряд снят" % [hp_sum_before, hp_sum_after], \
		hp_sum_after < hp_sum_before - 150.0 and bm.armed_events.is_empty() and enemy_count > 0)

	bm.stop_battle()
	quit()
