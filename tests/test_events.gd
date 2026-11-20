extends SceneTree

# События — шаг цепочки забега (RunEvents, EventScene): место в цепочке, выбор от seed
# без повторов, эффекты и цены, недоступные варианты, последствие на следующий бой,
# сохранение, сцена (выбор → итог → магазин).
# Свой файл сохранения — забег игрока не трогает.
#   godot --headless --path . -s tests/test_events.gd
const TEST_SAVE_PATH: String = "user://test_events_save.json"

# RunEvents обращается к автолоадам — по имени класса в -s скрипте не компилируется, грузим после старта
var RE

func _initialize() -> void:
	root.get_node("SaveManager").save_path = TEST_SAVE_PATH
	root.get_node("SaveManager").profile_path = "user://test_events_profile.cfg"   # открытые сложности игрока не трогаем
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _frames(n: int) -> void:
	for i in range(n): await process_frame

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _event_node_ids(rm) -> Array:
	var ids = []
	for n in rm.map.nodes:
		if n.type == "event":
			ids.append(n.id)
	return ids

func _option(event_id: String, index: int) -> Dictionary:
	for e in RE.EVENTS:
		if e["id"] == event_id:
			return e["options"][index]
	return {}

func _tactical() -> UnitData:
	var card = CardFactory.tactical_squad()
	var d = UnitFactory.create(card.unit_factory_id)
	d.squad_size = card.unit_count
	d.squad_growth = UnitFactory.squad_growth_for(card)
	var hp: Array[float] = []
	for i in d.squad_size: hp.append(0.5)
	d.saved_hp = hp
	return d

func _main() -> void:
	await process_frame
	RE = load("res://scripts/data/RunEvents.gd")
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	var em = root.get_node("EconomyManager")
	var sv = root.get_node("SaveManager")

	# 1. Цепочка: событие после волн 4, 8, 12, 14 — между боем и магазином
	bm.reset_run()
	rm.new_run(777)
	var ids = _event_node_ids(rm)
	var after = ids.map(func(i): return rm.map.nodes[i - 1].wave)
	var between = ids.all(func(i): return rm.map.nodes[i - 1].is_battle() and rm.map.nodes[i + 1].type == "shop")
	_check("цепочка: события после волн %s, между боем и магазином" % [after], after == [4, 8, 12, 14] and between)

	# 2. Выбор от seed: 4 разных события, тот же seed — те же
	var picked = []
	for k in range(ids.size()):
		picked.append(RE.for_run(777, k)["id"])
	var again = []
	for k in range(ids.size()):
		again.append(RE.for_run(777, k)["id"])
	var distinct = {}
	for p in picked: distinct[p] = true
	_check("события забега без повторов и от seed: %s" % [picked], distinct.size() == ids.size() and picked == again)

	# 3. Эффекты: Req, ремонт, урон (не убивает), карта в руку / полная рука
	em.requisition = 20
	bm.citadel_hp = 500.0
	var rng = RandomNumberGenerator.new()
	RE.apply(_option("munitorum_cache", 0), rng)
	RE.apply(_option("tech_priests", 0), rng)
	var req_ok = em.requisition == 30 and is_equal_approx(bm.citadel_hp, 750.0)
	RE._apply_effect({"damage": 5000}, rng)
	var alive_ok = is_equal_approx(bm.citadel_hp, 1.0)
	bm.pending_cards.clear()
	RE.apply(_option("reinforcements", 0), rng)
	var card_ok = bm.pending_cards.size() == 1 and bm.pending_cards[0].card_type == "squad" \
		and bm.pending_cards[0].rarity == "common"
	while bm.pending_cards.size() < bm.MAX_HAND_SIZE:
		bm.pending_cards.append(CardFactory.tactical_squad())
	var req_before = em.requisition
	RE.apply(_option("munitorum_cache", 1), rng)
	var full_ok = bm.pending_cards.size() == bm.MAX_HAND_SIZE and em.requisition > req_before
	_check("эффекты: +Req, ремонт, урон оставляет 1 HP, карта в руку, полная рука → Req",
		req_ok and alive_ok and card_ok and full_ok)

	# 4. Армия и здания: отряд +1 уровень (+бойцы), лечение армии, здание +1 уровень
	bm.reset_run()
	var d = _tactical()
	bm.player_units = [d] as Array[UnitData]
	RE.apply(_option("chapter_relic", 0), rng)
	var level_ok = d.squad_level == 1 and d.squad_size == 11 and d.saved_hp.size() == 11 \
		and d.saved_hp[d.saved_hp.size() - 1] == 1.0 and d.saved_hp[0] == 0.5
	em.requisition = 10
	RE.apply(_option("field_hospital", 0), rng)
	var heal_ok = em.requisition == 4 and d.saved_hp.size() == d.squad_size and d.saved_hp.all(func(v): return v == 1.0)
	var wall = CardFactory.fortress_wall()
	bm.player_buildings[wall] = Vector2i(0, 1)
	em.requisition = 10
	RE.apply(_option("tech_priests", 1), rng)
	_check("отряд +1 уровень (11 бойцов, новые здоровы), лечение армии за 6 Req, здание ур.2",
		level_ok and heal_ok and wall.building_level == 2 and em.requisition == 2)

	# 5. Недоступные варианты: нет Req, слабая цитадель, нет отряда / здания
	bm.reset_run()
	em.requisition = 3
	bm.citadel_hp = 80.0
	var blocked = RE.blocker(_option("cultists", 0)) != "" \
		and RE.blocker(_option("warp_storm", 0)) != "" \
		and RE.blocker(_option("chapter_relic", 0)) != "" \
		and RE.blocker(_option("field_hospital", 0)) != ""
	var open_ok = RE.blocker(_option("cultists", 1)) == "" and RE.blocker(_option("warp_storm", 1)) == ""
	_check("недоступно: нет Req / слабая цитадель / нет отряда; бесплатные варианты открыты", blocked and open_ok)

	# 6. Риск: исход от seed забега и шага — тот же при повторе
	rm.new_run(4242)
	rm.current_node_id = _event_node_ids(rm)[0]
	var r1 = rm.get_event_rng().randf()
	var r2 = rm.get_event_rng().randf()
	_check("бросок риска повторяется (перезапуск не перебросит)", r1 == r2)

	# 7. Последствие на следующий бой: сохранение, враги с HP ×0.8, сброс после боя
	bm.reset_run()
	rm.new_run(31)
	bm.citadel_hp = 900.0
	RE.apply(_option("warp_storm", 0), rng)
	var cost_ok = is_equal_approx(bm.citadel_hp, 800.0) and is_equal_approx(bm.next_battle_enemy_hp, 0.8)
	sv.enabled = true
	sv.save_run()
	bm.reset_run()
	sv.load_run()
	var saved_ok = is_equal_approx(bm.next_battle_enemy_hp, 0.8) and bm.next_battle_note != ""
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	em.round_number = 1
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(3)
	var enemies = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(1)
	var weaker = enemies.all(func(s): return is_equal_approx(s.data.hp_multiplier, EnemyWaves.get_stat_mult(1) * 0.8))
	scene._on_start_pressed(false)
	var t = 0
	while bm.is_battle_running() and t < 5000:
		await process_frame
		t += 1
	_check("варп-шторм: −100 HP, сохранён, враги боя ×0.8 HP, после боя сброшен",
		cost_ok and saved_ok and weaker and is_equal_approx(bm.next_battle_enemy_hp, 1.0))
	scene.queue_free()
	await _frames(2)

	# 8. Сцена: шаг события → выбор → итог сохранён → «Далее» в магазин
	bm.reset_run()
	rm.new_run(99)
	var ev_id = _event_node_ids(rm)[0]
	rm.current_node_id = ev_id - 1
	rm.current_completed = true
	em.round_number = 5
	rm.advance()
	await _frames(3)
	var ev_scene = current_scene
	var on_event = ev_scene.name == "EventScene" and rm.current_node_id == ev_id and not rm.current_completed
	var button = ev_scene._option_buttons.filter(func(b): return not b.disabled)[0]
	button.pressed.emit()
	await _frames(2)
	# исход на иллюстрации (09.11.2026): вспышка поверх картинки (золотая — удача, красная — неудача)
	var art = ev_scene.get("_art")
	var outcome_shown: bool = art == null or art.get_children().any(func(c): return c is ColorRect)
	var chosen = rm.current_completed and ev_scene._next_button.visible \
		and ev_scene._option_buttons.all(func(b): return b.disabled)
	bm.reset_run()
	sv.load_run()
	var persisted = rm.current_node_id == ev_id and rm.current_completed
	ev_scene._on_next_pressed()
	await _frames(3)
	_check("сцена: событие открыто, выбор применён и сохранён, исход вспышкой на картинке, «Далее» → магазин",
		on_event and chosen and outcome_shown and persisted and current_scene.get("shop") != null and rm.current_node_id == ev_id + 1)

	sv.delete_save()
	quit()
