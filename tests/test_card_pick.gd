extends SceneTree

# Выбор карты после волны (RunMapNode.PICK, решение пользователя 16.11.2026): 4 карты рубашкой вверх → открыть 2 →
# взять 1 из открытых; набор сохраняется; рука полна — карта продаётся. Запуск: godot --headless --path . -s tests/test_card_pick.gd

var _fails := 0

func _check(name: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok:
		_fails += 1

func _init() -> void:
	await process_frame
	var rm = root.get_node("RunManager")
	var sm = root.get_node("ShopManager")
	var bm = root.get_node("BattleManager")
	var eco = root.get_node("EconomyManager")
	root.get_node("SaveManager").enabled = false
	bm.reset_run()
	rm.new_run(7)

	# Цепочка: после волн без события — выбор карты, после 4 / 8 / 12 / 14 — событие и магазин
	var kinds := []
	for n in rm.map.nodes:
		kinds.append(n.type)
	_check("магазин только после событий, перед волной 1 — стартовый выбор", kinds.count("shop") == RunMapData.EVENT_AFTER_WAVES.size()
		and kinds.count("start_pick") == 1 and rm.map.nodes[0].type == "start_pick")
	_check("выбор карты — перед остальными волнами", kinds.count("pick") == 15 - 1 - RunMapData.EVENT_AFTER_WAVES.size())
	_check("событие → магазин, бой → выбор", rm.map.nodes[8].type == "event" and rm.map.nodes[9].type == "shop" and rm.map.nodes[2].type == "pick")

	rm.current_node_id = 1
	rm.current_completed = true
	rm.advance()
	for i in 20:
		await process_frame
	var sc = current_scene.get("shop")   # выбор карты — окно поверх поля следующего боя (BattleScene.shop)
	_check("после боя — окно выбора над полем, 4 разные карты", sc != null and sc.scene_file_path.ends_with("CardPickScene.tscn")
		and sm.pick_offers.size() == 4
		and sm.pick_offers.map(func(c): return c.id).size() == 4)
	var ids: Array = sm.pick_offers.map(func(c): return c.id)
	var distinct := {}
	for id in ids:
		distinct[id] = true
	_check("карты без повторов", distinct.size() == 4)

	_check("до открытия 2 карт взять нельзя", sm.pick_take(0) == null)
	_check("открыть первую и вторую", sm.pick_reveal(0) and sm.pick_reveal(1))
	_check("третью открыть нельзя, повторно — тоже", not sm.pick_reveal(2) and not sm.pick_reveal(0))
	_check("неоткрытую взять нельзя", sm.pick_take(2) == null)

	# Сохранение набора и открытых (copy: load_state не должен портить словарь сохранения)
	var st: Dictionary = sm.save_state()
	sm.load_state(st)
	_check("набор и открытые сохраняются", CardFactory.ids_of(sm.pick_offers) == ids and sm.pick_open == [0, 1] and sm.pick_node_id == 2)
	sm.open_pick()
	_check("повторный вход в тот же шаг — тот же набор", CardFactory.ids_of(sm.pick_offers) == ids)

	var got = sm.pick_take(1)
	_check("взята открытая карта, набор закрыт", got != null and got.id == ids[1] and sm.pick_done() and sm.pick_take(0) == null)

	# Новый шаг — новый набор
	rm.current_node_id = 3
	rm.current_completed = false
	sm.open_pick()
	_check("новый шаг — новый набор, ничего не открыто", sm.pick_node_id == 3 and sm.pick_open.is_empty() and not sm.pick_done())

	# Через сцену: взять в руку / рука полна → продажа
	rm.current_node_id = 1
	rm.current_completed = true
	sm.reset()
	rm.advance()
	for i in 20:
		await process_frame
	sc = current_scene.get("shop")
	sc._dealing = false
	sc._on_back_clicked(0)
	sc._on_back_clicked(1)
	bm.pending_cards.clear()
	sc._on_take_pressed(0)
	_check("карта — в руку, шаг завершён", bm.pending_cards.size() == 1 and rm.current_completed)

	rm.current_node_id = 3
	rm.current_completed = true
	rm.advance()
	for i in 20:
		await process_frame
	sc = current_scene.get("shop")
	sc._dealing = false
	sc._on_back_clicked(0)
	sc._on_back_clicked(1)
	while bm.pending_cards.size() < bm.MAX_HAND_SIZE:
		bm.pending_cards.append(sm.pick_offers[3])
	var req: int = eco.requisition
	sc._on_take_pressed(0)
	_check("рука полна — карта продана, рука не выросла", bm.pending_cards.size() == bm.MAX_HAND_SIZE
		and eco.requisition == req + eco.get_sell_price(sm.pick_offers[0]))

	# --- Стартовый выбор забега (17.11.2026): 6 карт рубашкой вверх, берёт 3 вслепую; минимум 2 карты в руке ---
	bm.reset_run()
	rm.new_run(11)
	sm.reset()
	eco.round_number = 1
	bm.pending_cards.clear()
	rm.advance()
	for i in 20:
		await process_frame
	var scene = current_scene
	var spick = scene.get("shop")
	_check("перед волной 1 — окно стартового выбора над полем", rm.is_start_pick_active() and spick != null
		and spick.scene_file_path.ends_with("CardPickScene.tscn") and sm.pick_is_start())
	var sids: Array = sm.pick_offers.map(func(c): return c.id)
	var sdist := {}
	for id in sids:
		sdist[id] = true
	_check("6 разных карт", sm.pick_offers.size() == 6 and sdist.size() == 6)
	spick._dealing = false
	_check("взять вслепую: первая в руку, остальные закрыты", sm.pick_start_take(2) != null and not sm.pick_done()
		and sm.pick_open == [2] and sm.pick_start_take(2) == null)
	sm.pick_start_taken.clear()
	sm.pick_open.clear()
	var hand_before: int = bm.pending_cards.size()
	spick._on_start_taken(0)
	spick._on_start_taken(0)   # повторный клик по взятой — ничего
	_check("клик по рубашке — карта в руке, шаг не завершён", bm.pending_cards.size() == hand_before + 1 and not rm.current_completed)
	spick._on_start_taken(3)
	spick._on_start_taken(5)
	_check("взято 3 карты вслепую — шаг завершён, рука +3", sm.pick_done() and rm.current_completed
		and bm.pending_cards.size() == hand_before + 3 and sm.pick_start_taken == [0, 3, 5])
	_check("четвёртую взять нельзя", sm.pick_start_take(1) == null)
	var saved: Dictionary = sm.save_state()
	sm.load_state(saved)
	_check("взятые вслепую сохраняются", sm.pick_start_taken == [0, 3, 5])

	spick._on_next_pressed()   # «ДАЛЕЕ» → поле переходит к расстановке волны 1
	for i in 10:
		await process_frame
	_check("расстановка волны 1 с тремя картами", scene.is_placement_phase and not scene.shop_phase)
	_check("правило минимальной руки действует (не босс)", scene._hand_floor_applies())
	scene.battle_type = "boss"
	_check("перед финальным боссом правила нет", not scene._hand_floor_applies())
	scene.battle_type = "battle"
	var tile := Vector2i(1, 1)
	var sp: Vector2 = scene.camera.world_to_screen(scene.iso_grid.tile_to_screen(tile))
	bm.pending_cards.clear()
	var c1 = CardFactory.create("tactical_squad")
	var c2 = CardFactory.create("tactical_squad")
	bm.pending_cards.append(c1)
	bm.pending_cards.append(c2)
	scene.bench.setup(bm.pending_cards)
	scene._on_card_dropped(c1, sp)
	_check("в руке 2 карты — сыграть нельзя", bm.pending_cards.size() == 2 and not scene._auto_start_pending)
	var c3 = CardFactory.create("tactical_squad")
	bm.pending_cards.append(c3)
	scene.bench.setup(bm.pending_cards)
	scene._on_card_dropped(c3, sp)
	_check("сыграли из трёх — осталось 2, бой стартует сам", bm.pending_cards.size() == 2 and scene._auto_start_pending)
	await create_timer(1.3, true, false, true).timeout
	_check("через паузу бой начался", not scene.is_placement_phase)

	print("test_card_pick: %s" % ("OK" if _fails == 0 else "%d провалов" % _fails))
	quit(1 if _fails > 0 else 0)
