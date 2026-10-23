extends SceneTree

# Подкрепление (catch-up): цитадель ранена в бою и ниже 50% HP → в следующем
# магазине выбор одной Common карты из 3 бесплатно, одна смена набора.
# Свой файл сохранения — забег игрока не трогает.
#   godot --headless --path . -s tests/test_catch_up.gd
const TEST_SAVE_PATH: String = "user://test_catch_up_save.json"

func _initialize() -> void:
	root.get_node("SaveManager").save_path = TEST_SAVE_PATH
	root.get_node("SaveManager").profile_path = "user://test_catch_up_profile.cfg"   # открытые сложности игрока не трогаем
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _frames(n: int) -> void:
	for i in range(n): await process_frame

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _ids(a: Array) -> Array:
	return a.map(func(c): return c.id)

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	var sm = root.get_node("ShopManager")
	var sv = root.get_node("SaveManager")
	var eco = root.get_node("EconomyManager")

	# 1. Порог: урон в бою и HP ниже половины
	bm.reset_run()
	var cases = [[600.0, 400.0, true], [400.0, 400.0, false], [800.0, 600.0, false], [600.0, 0.0, false]]
	var ok_cases = true
	for c in cases:
		bm.catch_up_pending = false
		bm._citadel_hp_at_start = c[0]
		bm.citadel_hp = c[1]
		bm._check_catch_up()
		ok_cases = ok_cases and bm.catch_up_pending == c[2]
	_check("порог: ранена и < 50% — да; без урона, выше половины, 0 HP — нет", ok_cases)

	# 2. Бой: армии нет, штурм с 530 HP → цитадель ниже 500 → флаг. Штурм волны 1 снимает ≈ 50 HP
	# со случайным разбросом урона (Soldier._roll_damage): с 550 цитадель оставалась то ≈ 496, то ≈ 501 —
	# на пороге 500 тест падал через раз; с 530 запас ≈ 20 HP
	bm.reset_run()
	rm.new_run(7)
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	eco.round_number = 1
	bm.citadel_hp = 530.0
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(3)
	current_scene._on_start_pressed(false)
	var t = 0
	while bm.is_battle_running() and t < 4000:
		await process_frame
		t += 1
	_check("штурм отбит, цитадель ниже 500 → подкрепление ждёт магазина", bm.winner_team == 0 \
		and bm.citadel_hp < 500.0 and bm.catch_up_pending)

	# 3. Магазин следующей волны: окно выбора, 3 разные Common карты
	await create_timer(2.6).timeout
	await _frames(3)
	var shop = current_scene
	var offers: Array = sm.catch_up_offers
	var distinct = {}
	for c in offers:
		distinct[c.id] = true
	_check("магазин: окно открыто, 3 разные Common, флаг снят", shop.name == "ShopScene" \
		and shop.catch_up_picker != null and offers.size() == 3 and distinct.size() == 3 \
		and offers.all(func(c): return c.rarity == "common") and not bm.catch_up_pending \
		and shop.catch_up_button.visible)

	# 4. Сохранение: выбор и флаг подкрепления переживают «Продолжить»
	var ids_before = _ids(sm.catch_up_offers)
	bm.catch_up_pending = true
	sv.save_run()
	sm.reset()
	bm.catch_up_pending = false
	sv.load_run()
	_check("сохранение: выбор, смены и флаг восстановлены", _ids(sm.catch_up_offers) == ids_before \
		and sm.catch_up_rerolls_left == 1 and bm.catch_up_pending)
	bm.catch_up_pending = false

	# 5. Смена набора — один раз, новые карты в приоритете
	var before_reroll = _ids(sm.catch_up_offers)
	var first = sm.try_reroll_catch_up()
	var unseen_common = {}
	for c in CardFactory.build_pool():
		if c.rarity == "common" and not before_reroll.has(c.id):
			unseen_common[c.id] = true
	_check("смена: все ещё не показанные Common попали в набор", unseen_common.keys().all(
		func(id): return _ids(sm.catch_up_offers).has(id)))
	var second = sm.try_reroll_catch_up()
	_check("смена набора: первая есть, второй нет", first and not second and sm.catch_up_offers.size() == 3 \
		and sm.catch_up_rerolls_left == 0)

	# 6. Не копится: новый триггер при невзятом выборе набор не меняет
	var ids_kept = _ids(sm.catch_up_offers)
	bm.catch_up_pending = true
	sm.shop_node_id = -1
	sm.open_shop()
	_check("не копится: выбор тот же, смен не добавилось, окно само не всплывает", \
		_ids(sm.catch_up_offers) == ids_kept and sm.catch_up_rerolls_left == 0 and not bm.catch_up_pending \
		and not sm.catch_up_just_issued)

	# 7. Полная рука — взять нельзя, выбор остаётся
	shop._refresh_catch_up_picker()
	var hand: Array = shop.purchased_cards
	var saved_hand = hand.duplicate()
	hand.clear()
	for i in range(bm.MAX_HAND_SIZE):
		hand.append(CardFactory.tactical_squad())
	shop._on_catch_up_picked(0)
	_check("рука полна: карта не взята, выбор цел", hand.size() == bm.MAX_HAND_SIZE and sm.has_catch_up())

	# 8. Взять карту: бесплатно, в руку, выбор закрыт
	hand.clear()
	hand.append_array(saved_hand)
	var req_before = eco.requisition
	var pick_id = sm.catch_up_offers[1].id
	shop._on_catch_up_picked(1)
	await _frames(2)
	_check("взял: карта в руке, Req не списаны, окно и кнопка скрыты", hand.size() == saved_hand.size() + 1 \
		and hand[-1].id == pick_id and eco.requisition == req_before and not sm.has_catch_up() \
		and shop.catch_up_picker == null and not shop.catch_up_button.visible)

	# 9. Новый забег — выбора нет
	bm.catch_up_pending = true
	bm.reset_run()
	_check("новый забег: флаг и выбор сброшены", not bm.catch_up_pending and not sm.has_catch_up())

	sv.delete_save()
	quit()
