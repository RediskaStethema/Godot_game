extends SceneTree

# Сохранение забега (SaveManager): магазин после перезапуска, развитая армия,
# «Продолжить» после пройденного шага и посреди боя, удаление в конце забега.
# Пишет в свой файл — сохранение игрока не трогает.
#   godot --headless --path . -s tests/test_save.gd
const TEST_SAVE_PATH: String = "user://test_run_save.json"

func _initialize() -> void:
	root.get_node("SaveManager").save_path = TEST_SAVE_PATH
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

	# 1. Новый забег из меню, покупки и обновление в магазине
	change_scene_to_file("res://scenes/menu/MainMenu.tscn")
	await _frames(3)
	_check("меню без сохранения — «Продолжить» скрыта", not current_scene.continue_button.visible)
	current_scene._on_new_run_pressed()
	await _frames(3)
	var shop = current_scene
	_check("новый забег → магазин шага 0, сохранение записано", shop.name == "ShopScene" and rm.current_node_id == 0 and sv.has_save())
	shop._on_purchase_requested(0)   # бесплатная карта 1-й волны
	em.requisition = 40
	shop._on_purchase_requested(0)
	shop._on_reroll_pressed()
	var before = "req=%d hand=%s offers=%s rerolls=%d free=%d wave=%d" % [em.requisition, _ids(bm.pending_cards), _ids(sm.current_offers), sm.rerolls_done, sm.free_cards_left, em.round_number]

	# 2. «Перезапуск игры» → «Продолжить»: магазин один в один
	bm.reset_run()
	change_scene_to_file("res://scenes/menu/MainMenu.tscn")
	await _frames(3)
	_check("меню с сохранением — «Продолжить» видна", current_scene.continue_button.visible)
	current_scene._on_continue_pressed()
	await _frames(3)
	var after = "req=%d hand=%s offers=%s rerolls=%d free=%d wave=%d" % [em.requisition, _ids(bm.pending_cards), _ids(sm.current_offers), sm.rerolls_done, sm.free_cards_left, em.round_number]
	print("  до:    ", before)
	print("  после: ", after)
	_check("магазин восстановлен", before == after and current_scene.name == "ShopScene" and current_scene.purchased_cards.size() == 2)

	# 3. Развитая армия: уровни, улучшения, клетки, здания, королевство, цитадель
	bm.reset_run()
	rm.current_node_id = 7
	rm.current_completed = true   # бой волны 4 пройден
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
	bm.player_units = [t, s] as Array[UnitData]
	bm.player_placements[t] = Vector2i(1, 1)
	bm.player_placements[s] = Vector2i(3, 0)
	bm.player_buildings[CardFactory.fortress_wall()] = Vector2i(0, 2)
	bm.pending_cards = [CardFactory.battle_fury(), CardFactory.tactical_squad()] as Array[CardData]
	sv.save_run()
	bm.reset_run()
	_check("загрузка", sv.load_run())
	var lt = bm.player_units[0]
	var ls = bm.player_units[1]
	_check("экономика и забег", em.requisition == 77 and em.round_number == 5 and em.wins == 4 \
		and is_equal_approx(bm.citadel_hp, 640.5) and bm.kingdom_tiles.size() == 10 and bm.tiles_bought == 1 \
		and rm.current_node_id == 7 and rm.current_completed)
	_check("отряд: уровень, множители, улучшения, HP, клетка", lt.factory_id == "terminator" and lt.squad_level == 1 \
		and is_equal_approx(lt.hp_multiplier, 1.5) and is_equal_approx(lt.damage_multiplier, 1.2) \
		and is_equal_approx(lt.attack_speed_multiplier, 1.15) and lt.applied_upgrades == ["Blessed Armour"] \
		and lt.saved_hp == [1.0, 0.35] and lt.squad_size == 2 and bm.player_placements.get(lt) == Vector2i(1, 1))
	_check("раненый отряд на купленной клетке", ls.saved_hp == [0.5] and bm.player_placements.get(ls) == Vector2i(3, 0))
	var bkeys = bm.player_buildings.keys()
	_check("здания и рука", bkeys.size() == 1 and bkeys[0].id == "fortress_wall" \
		and bm.player_buildings[bkeys[0]] == Vector2i(0, 2) and _ids(bm.pending_cards) == "battle_fury,tactical_squad")

	# 4. «Продолжить» после пройденного боя → магазин следующей волны
	rm.resume()
	await _frames(3)
	_check("пройденный шаг → магазин шага 8", current_scene.name == "ShopScene" and rm.current_node_id == 8)

	# 5. В бой, «вылет» посреди боя → «Продолжить» → тот же бой с расстановки
	current_scene._on_battle_pressed()
	await _frames(3)
	var battle_node = rm.current_node_id
	current_scene._on_start_pressed()
	await _frames(5)
	bm.stop_battle()
	bm.reset_run()
	sv.load_run()
	rm.resume()
	await _frames(3)
	_check("вылет посреди боя → тот же бой", current_scene.name == "BattleScene" and rm.current_node_id == battle_node \
		and bm.player_units.size() == 2)

	# 6. Конец забега — сохранение удалено
	current_scene._show_run_end(false)
	_check("конец забега удаляет сохранение", not sv.has_save())
	sv.delete_save()
	quit()
