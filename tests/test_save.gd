extends SceneTree

# Сохранение забега (SaveManager): магазин после перезапуска, развитая армия,
# «Продолжить» после пройденного шага, посреди расстановки и посреди боя,
# удаление в конце забега.
# Пишет в свой файл — сохранение игрока не трогает.
#   godot --headless --path . -s tests/test_save.gd
const TEST_SAVE_PATH: String = "user://test_run_save.json"

func _initialize() -> void:
	# Скорость боя игрока (GameSettings) не должна влиять на тест
	root.get_node("GameSettings").battle_speed = 1.0
	root.get_node("SaveManager").save_path = TEST_SAVE_PATH
	root.get_node("SaveManager").profile_path = "user://test_save_profile.cfg"   # открытые сложности игрока не трогаем
	_main()

func _frames(n: int) -> void:
	for i in range(n): await process_frame

func _ids(a: Array) -> String:
	var r := []
	for c in a: r.append(c.id)
	return ",".join(r)

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _main() -> void:
	var bm = root.get_node("BattleManager")
	var em = root.get_node("EconomyManager")
	var rm = root.get_node("RunManager")
	var sm = root.get_node("ShopManager")
	var sv = root.get_node("SaveManager")
	sv.delete_save()

	# 1. Новый забег из меню, стартовый выбор 3 из 6 вслепую (17.11.2026 — магазина волны 1 нет): две карты из трёх
	change_scene_to_file("res://scenes/menu/MainMenu.tscn")
	await _frames(3)
	_check("меню без сохранения — «Продолжить» скрыта", not current_scene.continue_button.visible)
	current_scene._on_new_run_pressed()
	await _frames(2)
	for c in current_scene.get_children():
		if c.has_method("choose"):   # окно выбора расы
			c.choose("space_marines")
	await _frames(2)
	for c in current_scene.get_children():
		if c.has_method("choose") and c.get("_chosen") == false:   # следом — окно выбора ордена
			c.choose("ultramarines")
	await _frames(2)
	for c in current_scene.get_children():
		if c.has_method("choose") and c.get("_chosen") == false:   # следом — окно выбора сложности
			c.choose(3)
	await _frames(3)
	var shop = current_scene.get("shop")   # магазин — окно поверх поля BattleScene
	_check("новый забег → стартовый выбор шага 0, сохранение записано", shop != null and rm.current_node_id == 0 and sv.has_save()
		and sm.pick_is_start() and sm.pick_offers.size() == 6)
	shop._dealing = false
	em.requisition = 40
	shop._on_start_taken(0)
	shop._on_start_taken(2)   # две из трёх — «вылет» посреди выбора (сохранение — после каждого взятия)
	var before = "req=%d hand=%s offers=%s taken=%s wave=%d" % [em.requisition, _ids(bm.pending_cards), _ids(sm.pick_offers), sm.pick_start_taken, em.round_number]

	# 2. «Перезапуск игры» → «Продолжить»: магазин один в один
	bm.reset_run()
	change_scene_to_file("res://scenes/menu/MainMenu.tscn")
	await _frames(3)
	_check("меню с сохранением — «Продолжить» видна", current_scene.continue_button.visible)
	current_scene._on_continue_pressed()
	await _frames(3)
	var after = "req=%d hand=%s offers=%s taken=%s wave=%d" % [em.requisition, _ids(bm.pending_cards), _ids(sm.pick_offers), sm.pick_start_taken, em.round_number]
	print("  до:    ", before)
	print("  после: ", after)
	_check("стартовый выбор восстановлен: набор, взятые вслепую и рука", before == after and current_scene.get("shop") != null
		and sm.pick_start_taken.size() == 2 and bm.pending_cards.size() >= 2)

	# 3. Развитая армия: уровни, улучшения, клетки, здания, королевство, цитадель
	bm.reset_run()
	rm.current_node_id = 8
	rm.current_completed = true   # событие после волны 4 пройдено (RunMapData.EVENT_AFTER_WAVES) — дальше магазин
	em.round_number = 5
	em.requisition = 77
	em.wins = 4
	bm.citadel_hp = 640.5
	bm.kingdom_tiles.append(Vector2i(3, 0))
	bm.tiles_bought = 1
	var t = UnitFactory.create("terminator")
	t.squad_size = 2
	t.apply_merge_upgrade()
	t.apply_upgrade(CardFactory.blessed_armour())
	t.saved_hp = [1.0, 0.35] as Array[float]
	var s = UnitFactory.create("scout_marine")
	s.squad_size = 3
	s.saved_hp = [0.5] as Array[float]
	s.apply_upgrade(CardFactory.iron_halo())
	s.apply_upgrade(CardFactory.combat_stimms())
	s.apply_upgrade(CardFactory.chapter_banner())
	bm.player_units = [t, s] as Array[UnitData]
	bm.player_placements[t] = Vector2i(1, 1)
	bm.player_placements[s] = Vector2i(3, 0)
	var wall = CardFactory.fortress_wall()
	wall.level_up_building()
	bm.player_buildings[wall] = Vector2i(0, 2)
	bm.pending_cards = [CardFactory.battle_fury(), CardFactory.tactical_squad()] as Array[CardData]
	rm.player_chapter = "imperial_fists"
	rm.difficulty = 5
	bm.armed_events.append("orbital_strike")
	bm.armed_tiles.append(Vector2i(2, 1))
	root.get_node("MetaProgress").run_minibosses = 2
	sv.save_run()
	bm.reset_run()
	rm.player_chapter = ""
	rm.difficulty = 2
	_check("загрузка", sv.load_run())
	_check("орден и сложность забега сохранены; мини-боссов в забеге (мета) — 2",
		rm.player_chapter == "imperial_fists" and rm.difficulty == 5
		and root.get_node("MetaProgress").run_minibosses == 2)
	var lt = bm.player_units[0]
	var ls = bm.player_units[1]
	_check("экономика и забег", em.requisition == 77 and em.round_number == 5 and em.wins == 4 \
		and is_equal_approx(bm.citadel_hp, 640.5) and bm.kingdom_tiles.size() == 10 and bm.tiles_bought == 1 \
		and rm.current_node_id == 8 and rm.current_completed)
	_check("отряд: уровень, множители, улучшения, HP, клетка", lt.factory_id == "terminator" and lt.squad_level == 1 \
		and is_equal_approx(lt.hp_multiplier, 1.5) and is_equal_approx(lt.damage_multiplier, 1.2) \
		and is_equal_approx(lt.attack_speed_multiplier, 1.15) and lt.applied_upgrades == ["Hallowed Plate"] \
		and lt.saved_hp == [1.0, 0.35] and lt.squad_size == 2 and bm.player_placements.get(lt) == Vector2i(1, 1))
	_check("раненый отряд на купленной клетке, щит / стимуляторы / знамя, заряд удара и его клетка", ls.saved_hp == [0.5] 		and bm.player_placements.get(ls) == Vector2i(3, 0) and is_equal_approx(ls.shield_ratio, 0.3) 		and is_equal_approx(ls.move_speed_multiplier, 1.2) and is_equal_approx(ls.banner_aura_bonus, 0.15) 		and Array(bm.armed_events) == ["orbital_strike"] and Array(bm.armed_tiles) == [Vector2i(2, 1)])
	var bkeys = bm.player_buildings.keys()
	_check("здания (уровень 2) и рука", bkeys.size() == 1 and bkeys[0].id == "fortress_wall" and bkeys[0].building_level == 2 \
		and bm.player_buildings[bkeys[0]] == bm.WALL_TILE and _ids(bm.pending_cards) == "battle_fury,tactical_squad")

	# 4. «Продолжить» после пройденного боя → магазин следующей волны (шаг 9 — после события)
	rm.resume()
	await _frames(3)
	_check("пройденный шаг → магазин шага 9", current_scene.get("shop") != null and rm.current_node_id == 9)

	# 5. Расстановка: выставить отряд с карты и наложить улучшение → «вылет» →
	#    «Продолжить» возвращает поле как было
	current_scene.shop._on_battle_pressed()   # «В БОЙ» магазина — расстановка в той же сцене
	await _frames(3)
	var battle = current_scene
	# Правило минимальной руки (17.11.2026): играть можно, пока в руке не меньше 2 карт — две лишние остаются в руке
	bm.pending_cards.append(CardFactory.iron_halo())
	bm.pending_cards.append(CardFactory.chapter_banner())
	var battle_node = rm.current_node_id
	var hand_tactical = bm.pending_cards.filter(func(c): return c.id == "tactical_squad")[0]
	var hand_fury = bm.pending_cards.filter(func(c): return c.id == "battle_fury")[0]
	battle._on_card_dropped(hand_tactical, battle._world_to_screen(battle.iso_grid.tile_to_screen(Vector2i(0, 0))))
	battle._on_card_dropped(hand_fury, battle._world_to_screen(battle.iso_grid.tile_to_screen(Vector2i(1, 1))))
	bm.reset_run()
	sv.load_run()
	rm.resume()
	await _frames(3)
	battle = current_scene
	var term = bm.player_units.filter(func(d): return d.factory_id == "terminator")[0]
	var tac = bm.player_units.filter(func(d): return d.factory_id == "tactical_marine")
	_check("расстановка сохранена: новый отряд на клетке, улучшение, в руке 2 карты", battle.name == "BattleScene" 		and battle.is_placement_phase and rm.current_node_id == battle_node and bm.player_units.size() == 3 		and tac.size() == 1 and bm.player_placements.get(tac[0]) == Vector2i(0, 0) and tac[0].saved_hp.size() == hand_tactical.unit_count 		and term.squad_level == 1 and term.applied_upgrades == ["Hallowed Plate", "Tiger's Action"] 		and bm.pending_cards.size() == 2 		and root.get_node("SquadRegistry").get_alive_squads_of_team(0).size() == 3)

	# 6. «В БОЙ» → «вылет» посреди боя → «Продолжить»: та же армия, бой сразу идёт.
	#    Заряженный в шаге 3 Orbital Strike снимаем: при хрупкой волне (seed забега случайный) он
	#    добивал всех врагов в первый же кадр — бой кончался раньше проверки
	bm.armed_events.clear()
	battle._on_start_pressed(false)
	await _frames(5)
	bm.stop_battle()
	bm.reset_run()
	sv.load_run()
	_check("флаг «бой идёт» в сохранении", bm.battle_in_progress)
	rm.resume()
	await _frames(4)
	battle = current_scene
	term = bm.player_units.filter(func(d): return d.factory_id == "terminator")[0]
	_check("вылет посреди боя → бой сразу, армия как была", battle.name == "BattleScene" 		and not battle.is_placement_phase and rm.current_node_id == battle_node and bm.player_units.size() == 3 		and term.applied_upgrades == ["Hallowed Plate", "Tiger's Action"] 		and root.get_node("SquadRegistry").get_alive_squads_of_team(0).size() == 3)

	# 7. Конец забега — сохранение удалено
	current_scene._show_run_end(false)
	_check("конец забега удаляет сохранение", not sv.has_save())
	sv.delete_save()
	quit()
