extends SceneTree

# Обучение (23.11.2026, сценарий двух наставников): три первые карты — пехота, Казармы, лекарь; шаги INTRO → PICK →
# PLACE_UNIT → TRAIN_BATTLE → PLACE_BARRACKS → CLICK_SQUAD → DONE; ограничения броска карты и старта боя, слабый враг
# в учебном бою, подсказки волн 2–4 один раз, выключатель и «пропустить»; в headless само не идёт.
#   godot --headless --path . -s tests/test_tutorial.gd

const FAKE_SCENE := "extends Node\nvar iso_grid\nvar renderer\nvar bench\nvar shop\nvar msgs: Array = []\nfunc _show_message(t): msgs.append(t)\nfunc tutorial_release(): msgs.append('release')\n"
const FAKE_GRID := "extends RefCounted\nfunc is_valid_tile(t): return t.x >= 0 and t.x < 3 and t.y >= 0 and t.y < 3\nfunc get_all_tiles(): return []\n"
const FAKE_SHOP := "extends Node
var purchased_cards: Array = []
var shop_slots := Node.new()
"
const FAKE_RENDERER := "extends Node\nvar occupied_tiles_player: Dictionary = {}\nvar tutorial_tile\nfunc set_effect_tiles(_t): pass\n"

func _initialize() -> void:
	_main()

# Наставники ушли с экрана (в тесте их уход — твин, а не мгновенно)
func _hide_holders(t) -> void:
	for h in t._holders.values():
		h.visible = false

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _as_set(arr: Array) -> Dictionary:
	var d := {}
	for x in arr:
		d[x] = true
	return d

func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s

func _main() -> void:
	await process_frame
	var gs = root.get_node("GameSettings")
	var rm = root.get_node("RunManager")
	var bm = root.get_node("BattleManager")
	root.get_node("SaveManager").enabled = false   # забег игрока не трогаем, Арсенал открыт целиком
	gs.config_path = "user://_tmp_tutorial_settings.cfg"
	gs.battle_speed = 1.0
	gs.tutorial_enabled = true
	gs.tutorial_seen.clear()
	gs.tutorial_stage = 0
	rm.player_faction = "space_marines"
	var T = load("res://scripts/tutorial/Tutorial.gd")

	# 1. Первые три карты — пехота, Казармы, лекарь (у Хаоса — их пары)
	var ids: Array = []
	for c in T.start_cards():
		ids.append(c.id)
	_check("стартовые карты: пехота, Казармы, лекарь", ids == ["tactical_squad", "barracks", "apothecary"])
	rm.player_faction = "chaos"
	_check("у Хаоса три карты своей расы", T.start_cards().size() == 3)
	rm.player_faction = "space_marines"

	# 2. В headless сценарий сам не идёт
	_check("headless: сценарий и подсказки не активны", not T.scripted_active() and not T.is_active() and not T.scripted_pick_active())

	# 3. Подсказки волн: шаги по волнам, один раз
	_check("волна 3: подсказка расстановки", T.find_step("placement", 3) != null and T.find_step("placement", 5) == null)
	gs.mark_tutorial_seen("w3_place")
	_check("показанная подсказка не повторяется", T.find_step("placement", 3) == null)
	gs.set_tutorial_enabled(false)
	_check("выключатель: реплики магазина нет", T.take_line("shop", 5) == "")
	gs.set_tutorial_enabled(true)
	_check("включили снова: с начала (стадия 0, подсказки заново)", gs.tutorial_stage == 0 and gs.tutorial_seen.is_empty())

	# 4. Сценарий на подставной сцене
	var scene := Node.new()
	scene.set_script(_script(FAKE_SCENE))
	scene.iso_grid = _script(FAKE_GRID).new()
	var rend := Node2D.new()
	rend.set_script(_script(FAKE_RENDERER))
	scene.renderer = rend
	root.add_child(scene)
	var t = T.new()
	t.setup(scene, 1)
	await process_frame
	_check("два наставника: Космодесант и Хаос", t.vendors.has("marine") and t.vendors.has("chaos")
		and t.vendors["marine"].faction == "space_marines" and t.vendors["chaos"].faction == "chaos")

	# 4а. Приветствие: диалог по кликам, спорят оба, в конце — стадия «выбор карт»
	t.notify("pick_start")
	_check("приветствие: диалог идёт, бой держится", t._dialogue_active and t.holds_start())
	var speakers := {}
	var guard := 0
	while t._dialogue_active and guard < 20:
		speakers[t._lines[maxi(t._line_i - 1, 0)][0]] = true
		t._next_line()
		guard += 1
	_check("в приветствии говорят оба наставника", speakers.has("chaos") and speakers.has("marine"))
	_hide_holders(t)
	_check("после приветствия — стадия выбора, бой не держится", gs.tutorial_stage == T.Stage.PICK and not t.holds_start())

	# 4б. Расстановка волны 1: карта и клетка подсвечены, ставить можно только их
	var hand: Array[CardData] = []
	hand.assign(T.start_cards())
	bm.pending_cards = hand
	t.wave = 1
	t.notify("placement")
	while t._dialogue_active:
		t._next_line()
	var unit: CardData = hand[0]
	_check("стадия PLACE_UNIT, цель — пехота", gs.tutorial_stage == T.Stage.PLACE_UNIT and t.target_id == unit.id)
	_check("клетка в королевстве", scene.iso_grid.is_valid_tile(t.target_tile))
	_check("бой держится, пока карта не сыграна", t.holds_start())
	_check("чужую карту бросить нельзя", not t.allow_drop(hand[1], t.target_tile))
	_check("не на ту клетку нельзя", not t.allow_drop(unit, Vector2i(0, 0) if t.target_tile != Vector2i(0, 0) else Vector2i(2, 2)))
	_check("светящуюся карту на подсвеченную клетку можно", t.allow_drop(unit, t.target_tile))

	# 4в. Карта сыграна → объяснение боя → учебный бой
	t.notify("card_played", unit)
	_check("после карты: диалог о бое, цель снята", t._dialogue_active and t.target_id == "")
	while t._dialogue_active:
		t._next_line()
	_hide_holders(t)
	_check("стадия TRAIN_BATTLE, бой можно начинать", gs.tutorial_stage == T.Stage.TRAIN_BATTLE and not t.holds_start()
		and scene.msgs.has("release"))
	_check("учебный бой: враг слабый и один", t.is_training_battle())
	var specs: Array = t.training_specs([{"unit": "chaos_cultist", "count": 9, "mult": 1.2}, {"unit": "chaos_havoc", "count": 4, "mult": 1.2}])
	_check("один слабый отряд врага", specs.size() == 1 and specs[0]["count"] <= T.TRAINING_COUNT_MAX and specs[0]["mult"] < 1.0)

	# 4г. Победа → урок про Казармы
	t.notify("battle_won")
	_check("после победы — стадия Казарм", gs.tutorial_stage == T.Stage.PLACE_BARRACKS and not t.is_training_battle() or gs.tutorial_stage == T.Stage.PLACE_BARRACKS)
	t.wave = 2
	scene.msgs.clear()

	# 5. Клик по отряду закрывает «паузу»
	gs.tutorial_stage = T.Stage.CLICK_SQUAD
	_check("CLICK_SQUAD: бой держится", t.holds_start())
	t.notify("squad_info")
	_check("клик по отряду: диалог, потом DONE и бой свободен", t._dialogue_active)
	while t._dialogue_active:
		t._next_line()
	_hide_holders(t)
	_check("сценарий волн 1–2 завершён: дальше WAVES, бой свободен", gs.tutorial_stage == T.Stage.WAVES and not t.holds_start())

	# 5а. Приветствие говорит про цитадель
	_check("в приветствии наставник объясняет, что цитадель надо защищать",
		T.INTRO_LINES.any(func(l): return "цитадел" in str(l[1]).to_lower() and "сердце" in str(l[1])))

	# 5б. Выбор после боя: открыть 2, взять 1 + зачем нужны монеты
	t.wave = 2
	t.notify("pick")
	_check("волна 2, выбор карты: диалог про «откроешь две, заберёшь одну» и про монеты", t._dialogue_active
		and T.PICK_LINES.any(func(l): return "Вскрываешь ты 2" in str(l[1])) and T.PICK_LINES.any(func(l): return "монет" in str(l[1])))
	while t._dialogue_active:
		t._next_line()

	# 5б2. Урок о прокачке: волна 4, расстановка — диалог про отряды и здания, один раз; уровень здания — облако
	_check("урок о прокачке говорит про отряды и здания", T.UPGRADE_LINES.any(func(l): return "отряд" in str(l[1]))
		and T.UPGRADE_LINES.any(func(l): return "здани" in str(l[1])) and T.UPGRADE_LINES.any(func(l): return l[0] == "chaos"))
	_check("реплики с «цитаделью» и «монетами» показывают её (наезд / пульс)", T.LINE_FOCUS.any(func(f): return f[1] == "citadel")
		and T.LINE_FOCUS.any(func(f): return f[1] == "coins") and T.LINE_FOCUS.any(func(f): return f[1] == "reroll")
		and T.INTRO_LINES.any(func(l): return T.LINE_FOCUS.any(func(f): return str(l[1]).begins_with(f[0]) and f[1] == "citadel")))
	_check("выбор перед волной 2 — обязательная карта пехоты (на ней урок о прокачке)", T.UNIT_PICK_WAVE == 2)
	_check("урок о прокачке — сценарий, не подсказка", T.find_step("placement", 4) == null)
	t.wave = 4
	t.notify("placement")   # отрядов на поле нет — урок не нужен и не ломает ход
	_check("волна 4 без отряда на поле: урок снят, диалога нет", not t._dialogue_active and gs.tutorial_seen.has("upgrade_done"))
	t.notify("building_level")
	_check("здание улучшено: подсказка один раз", gs.tutorial_seen.has("building_level"))
	while t._dialogue_active:
		t._next_line()

	# 5в. Событие: наставники объясняют (сцена события — отдельная, диалог в ней)
	_check("реплики события есть у обоих наставников", T.EVENT_LINES.any(func(l): return l[0] == "marine")
		and T.EVENT_LINES.any(func(l): return l[0] == "chaos") and T.EVENT_LINES.any(func(l): return "событие" in str(l[1]).to_lower()))

	# 5г. Первый магазин: монеты, орудие, «В БОЙ» держится, пока оно не куплено
	var cannon: CardData = T.cannon_card()
	_check("орудие — Thunderfire Cannon (у Хаоса Hellfire Mortar)", cannon != null and cannon.id == "thunderfire_cannon")
	t.wave = 4
	t.notify("shop_open")
	_check("магазин: диалог, стадия SHOP_BUY, в репликах название орудия",
		t._dialogue_active and gs.tutorial_stage == T.Stage.SHOP_BUY and t._lines.any(func(l): return cannon.display_title() in str(l[1])))
	while t._dialogue_active:
		t._next_line()
	var fake_shop := Node.new()
	fake_shop.set_script(_script(FAKE_SHOP))
	scene.shop = fake_shop
	t._poll_shop()
	_check("орудие не куплено: стадия SHOP_BUY", gs.tutorial_stage == T.Stage.SHOP_BUY)
	var bought: Array[CardData] = [cannon]
	fake_shop.purchased_cards = bought
	t._poll_shop()
	_check("орудие куплено: стадия PLACE_CANNON, бой держится", gs.tutorial_stage == T.Stage.PLACE_CANNON and t.holds_start()
		and t.exempts_hand_floor())

	# 5д. Волна 5: как работает орудие, подсвеченные карта и клетка, потом босс
	var hand5: Array[CardData] = [cannon, T.start_cards()[0]]
	bm.pending_cards = hand5
	t.wave = 5
	t.notify("placement")
	_check("расстановка волны 5: диалог про орудие", t._dialogue_active and t._lines.any(func(l): return "клик по полю" in str(l[1]).to_lower()))
	while t._dialogue_active:
		t._next_line()
	_check("цель — орудие на свободной клетке, бросить можно только его", t.target_id == cannon.id and scene.iso_grid.is_valid_tile(t.target_tile)
		and t.allow_drop(cannon, t.target_tile) and not t.allow_drop(hand5[1], t.target_tile))
	t.notify("card_played", cannon)
	_check("орудие поставлено: подсказка, бой ждёт ухода наставника", gs.tutorial_seen.has("cannon_placed") and t.holds_start() and t._holders["marine"].visible)
	t._show_holder("marine", false)
	t._show_holder("chaos", false)
	for h in t._holders.values():
		h.visible = false
	_check("наставники ушли — бой свободен, но сам не начнётся", not t.holds_start() and t.no_auto_start())
	_check("волна 5 — простые враги, волна 6 — ослабленный примарх", t.is_trial_battle() and not t.is_boss_battle())
	t.notify("battle_start")
	_check("в бою — подсказка «клик по полю — залп»", t._holders["marine"].visible)
	t.notify("battle_won")
	_check("волна 5 выиграна: стадия BOSS, обучение не кончилось", gs.tutorial_stage == T.Stage.BOSS)
	for h in t._holders.values():
		h.visible = false
	t.wave = 6
	_check("волна 6 — босс ослаблен", t.is_boss_battle() and t.BOSS_MULT < 0.5)
	t.notify("placement")
	_check("расстановка волны 6: объявление босса и предупреждение", t._dialogue_active and t._lines.any(func(l): return "босс" in str(l[1]).to_lower())
		and t._lines.any(func(l): return "цитадел" in str(l[1]).to_lower()))
	while t._dialogue_active:
		t._next_line()
	t.notify("battle_won")
	_check("босс побеждён: обучение окончено", gs.tutorial_stage == T.Stage.DONE and not T.scripted_active())
	gs.tutorial_stage = T.Stage.WAVES

	# 5е. Старт: шесть рубашек, стандартные три всегда
	var sm = root.get_node("ShopManager")
	rm.player_faction = "space_marines"
	sm._deal_tutorial_start()
	var dealt_ids: Array = sm.pick_offers.map(func(c): return c.id)
	_check("стартовый выбор обучения: рубашек %d, пехота / Казармы / лекарь среди них" % dealt_ids.size(), dealt_ids.size() == T.START_DEALT
		and "tactical_squad" in dealt_ids and "barracks" in dealt_ids and "apothecary" in dealt_ids and dealt_ids.size() == {}.merged(_as_set(dealt_ids)).size())
	var got: Array = []
	var picks := [4, 0, 2]   # любые три рубашки
	sm.pick_start_taken.clear()
	for idx in picks:
		sm.pick_start_taken.append(idx)
		sm._tutorial_swap_start(idx)
		got.append(sm.pick_offers[idx].id)
	_check("какие бы рубашки ни открыли, выпадают пехота, Казармы, лекарь по порядку", got == ["tactical_squad", "barracks", "apothecary"])
	sm.pick_offers.clear()
	sm.pick_start_taken.clear()

	# 5ж. Карта-событие после 2-го боя, редкая после 3-го, орудие в руку не попадает до покупки
	T.force_for_tests = true
	gs.tutorial_stage = T.Stage.WAVES
	gs.tutorial_seen.clear()
	rm.new_run()
	gs.tutorial_enabled = true
	gs.tutorial_stage = T.Stage.WAVES
	var pick_nodes: Array = []
	for n in rm.map.nodes:
		if n.type == "pick":
			pick_nodes.append(n)
	var cannon_ids: Array = T.hidden_card_ids()
	_check("до покупки орудие скрыто из выдачи (оба названия)", "thunderfire_cannon" in cannon_ids and "hellfire_mortar" in cannon_ids)
	var cannon_leaks := 0
	var event_ok := true
	var rare_ok := true
	for n in pick_nodes:
		rm.current_node_id = n.id
		rm.current_completed = false
		sm.pick_node_id = -1
		sm.open_pick()
		if not sm.pick_offers.all(func(c): return not (c.id in cannon_ids)):
			cannon_leaks += 1
		var w: int = rm.get_battle_wave()
		if w == T.EVENT_PICK_WAVE:
			event_ok = sm.pick_offers.any(func(c): return c.id == T.EVENT_CARD)
			var idx := 0 if sm.pick_offers[0].id != T.EVENT_CARD else 1
			sm.pick_reveal(idx)   # открываем «не ту» — первой открывается карта-событие
			event_ok = event_ok and sm.pick_offers[idx].id == T.EVENT_CARD and sm.pick_take(idx).id == T.EVENT_CARD
		elif w == T.RARE_PICK_WAVE:
			rare_ok = sm.pick_offers.any(func(c): return c.id == T.RARE_CARD)
			var idx2 := 0 if sm.pick_offers[0].id != T.RARE_CARD else 1
			sm.pick_reveal(idx2)
			sm.pick_reveal(1 if idx2 != 1 else 2)
			var rares := 0
			for i in sm.pick_open:   # урок о редкости: обе открытые рубашки — редкие карты
				if sm.pick_offers[i].rarity == "rare":
					rares += 1
			rare_ok = rare_ok and sm.pick_offers[idx2].id == T.RARE_CARD and rares == 2 and sm.pick_take(idx2).id == T.RARE_CARD
	_check("выборы волн 2–4: орудия среди рубашек нет", cannon_leaks == 0)
	_check("перед волной 3 в выборе всегда карта-событие, первой открывается она и её можно взять", event_ok)
	_check("перед волной 4 — две редкие карты: обе открытые редкие, взять можно редкую", rare_ok)
	_check("взятые обязательные карты запомнены", gs.tutorial_seen.has("pick_event_done") and gs.tutorial_seen.has("pick_rare_done"))
	gs.tutorial_stage = T.Stage.PLACE_CANNON
	_check("после покупки орудия оно снова может выпасть", T.hidden_card_ids().is_empty())
	# карта-событие в руке (волна 3): диалог, цель, после броска — объяснение и метка
	var evc: CardData = CardFactory.equivalent(T.EVENT_CARD, "space_marines")
	var hand3: Array[CardData] = [evc, T.start_cards()[0]]
	bm.pending_cards = hand3
	var squad_fake := Node2D.new()
	t.wave = 3
	gs.tutorial_stage = T.Stage.WAVES
	var before_target: String = t.target_id
	var handled: bool = t._on_placement(T.Stage.WAVES)
	_check("карта-событие в руке: наставник открывает урок, только если рядом есть свободная клетка (без отряда урок откладывается)",
		(handled and t._dialogue_active) or (not handled and before_target == t.target_id))
	while t._dialogue_active:
		t._next_line()
	if handled:
		_check("событие: подсвечена карта и клетка, бой держится", t.target_id == evc.id and t.holds_start())
		t.notify("card_played", evc)
		_check("событие сыграно: объяснение, метка, цель снята", gs.tutorial_seen.has("event_card_played") and t.target_id == "")
	squad_fake.free()
	# 5з. Ревью 26.11.2026: враги волны 5 расставляются ещё под магазином, выбор перед волной 2 — на стадии Казарм,
	# две редкие, даже если обязательная выпала сама; в учебном стартовом наборе нет орудия
	t.wave = T.TRIAL_WAVE
	gs.tutorial_stage = T.Stage.WAVES
	var trial_in_shop: bool = t.is_trial_battle()
	gs.tutorial_stage = T.Stage.SHOP_BUY
	_check("учебные враги волны 5 — уже под магазином (стадии WAVES и SHOP_BUY)", trial_in_shop and t.is_trial_battle())
	gs.tutorial_seen.clear()
	gs.tutorial_stage = T.Stage.PLACE_BARRACKS
	for n in pick_nodes:
		rm.current_node_id = n.id
		rm.current_completed = false
		if rm.get_battle_wave() == T.UNIT_PICK_WAVE:
			break
	var wave2_target: CardData = T.pick_target_card()
	_check("выбор перед волной 2 на стадии Казарм: обязательная карта пехоты", wave2_target != null and wave2_target.id == T.UNIT_CARD)
	gs.tutorial_stage = T.Stage.WAVES
	for n in pick_nodes:
		rm.current_node_id = n.id
		rm.current_completed = false
		if rm.get_battle_wave() == T.RARE_PICK_WAVE:
			break
	var two_rares := true
	for attempt in 20:
		var offers: Array[CardData] = [T.pick_target_card(), T.start_cards()[0], T.start_cards()[1], T.start_cards()[2]]
		sm.pick_offers = offers
		sm._tutorial_place_target()
		two_rares = two_rares and sm.pick_offers.filter(func(c): return c.rarity == "rare").size() >= 2 \
			and sm.pick_offers.any(func(c): return c.id == T.RARE_CARD)
	_check("урок о редкости: обязательная уже в наборе — всё равно две редкие", two_rares)
	gs.tutorial_stage = T.Stage.PICK
	var cannon_dealt := false
	for attempt in 30:
		sm._deal_tutorial_start()
		cannon_dealt = cannon_dealt or sm.pick_offers.any(func(c): return c.id in cannon_ids)
	_check("учебный стартовый набор: орудия среди шести рубашек нет", not cannon_dealt)
	sm.pick_offers.clear()
	# 5и. Забег, начатый без обучения (старое сохранение): стадия INTRO посреди забега — обучение молчит; на стартовом
	# выборе нового забега — идёт
	gs.tutorial_stage = T.Stage.INTRO
	rm.current_node_id = pick_nodes[0].id
	rm.current_completed = false
	var old_run_quiet: bool = T.dormant() and not T.scripted_active() and T.hidden_card_ids().is_empty()
	for n in rm.map.nodes:
		if n.type == "start_pick":
			rm.current_node_id = n.id
	_check("старое сохранение (стадия 0 посреди забега): сценарий молчит, орудие выпадает; новый забег — сценарий идёт",
		old_run_quiet and not T.dormant() and T.scripted_active() and not T.hidden_card_ids().is_empty())
	# уже созданный наставник (обучение выключили и включили посреди боя) — тоже молчит
	gs.tutorial_stage = T.Stage.INTRO
	rm.current_node_id = pick_nodes[0].id
	rm.current_completed = false
	t._dialogue_active = false
	t.wave = 1
	t.notify("merge")
	_check("наставник на поле в таком забеге: бой не держит, автостарт есть, учебного боя и реплик нет",
		not t.holds_start() and not t.no_auto_start() and not t.exempts_hand_floor() and not t.is_training_battle()
		and not t._dialogue_active)
	T.force_for_tests = false
	gs.tutorial_stage = T.Stage.WAVES

	# 6. Пропустить
	gs.tutorial_stage = T.Stage.PLACE_UNIT
	t._on_skip()
	_check("«Пропустить» выключает обучение и снимает бой", not gs.tutorial_enabled and not t.holds_start())
	var seen_before: int = gs.tutorial_seen.size()
	t.notify("merge")
	_check("после пропуска подсказок нет", gs.tutorial_seen.size() == seen_before)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.config_path))
	quit()
