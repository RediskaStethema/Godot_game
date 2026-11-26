extends SceneTree

# Мета-прогрессия (MetaProgress — древо Арсенала, решение пользователя 10.11.2026):
# 1) пустой профиль: открыт только Ultramarines, закрытые карты (Orbital Strike, Plasma Generatorium,
#    Chapter Banner, Apothecarion) в магазин и подкрепление не выпадают;
# 2) древо: у каждого узла есть родитель в той же ветке (или корень), карты и ордены узлов существуют;
#    без родителя и без Славы узел не купить, купленный — второй раз нет; орден / карта открываются узлом;
# 3) Слава за забег (и проигранный): победы, мини-боссы, главный босс × сложность;
# 4) перенос старого профиля (уровни пассивок, стартовые карты, достижения) в узлы;
# 5) пассивки в деле: «Резервы» (+Req на старте), «Освящённые стены» (щит цитадели),
#    «Связи в Муниторуме» (первое обновление бесплатно), «Ветеранская выучка» (+HP бойцам);
#    стартовая карта — в руке в начале забега;
# 6) сохранение выключено (тесты, balance_sim) — всё открыто, пассивок нет.
# Свои файлы профиля и сохранения — прогресс игрока не трогается.
#   godot --headless --path . -s tests/test_meta.gd

const PROFILE := "user://test_meta_profile.cfg"
const SAVE := "user://test_meta_save.json"

func _initialize() -> void:
	var sm = root.get_node("SaveManager")
	sm.enabled = true
	sm.save_path = SAVE
	sm.profile_path = PROFILE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	sm.load_profile()
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

# Карты, которые открывает древо
func _locked_cards(meta) -> Array:
	return meta.TREE.filter(func(n): return n["kind"] == "card").map(func(n): return n["target"])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _main() -> void:
	await process_frame
	var meta = root.get_node("MetaProgress")
	var bm = root.get_node("BattleManager")
	var em = root.get_node("EconomyManager")
	var rm = root.get_node("RunManager")
	var shop = root.get_node("ShopManager")
	var sm = root.get_node("SaveManager")
	meta.load_profile()

	# 1. Пустой профиль
	var chapters_open: Array = []
	for c in Chapters.for_faction("space_marines"):   # боги Хаоса открыты всегда — у них нет условий
		if meta.is_chapter_unlocked(c["id"]):
			chapters_open.append(c["id"])
	bm.reset_run()
	var seen: Dictionary = {}
	for i in 60:
		shop.refresh_shop()
		for c in shop.current_offers:
			seen[c.id] = true
		shop._roll_catch_up()
		for c in shop.catch_up_offers:
			seen[c.id] = true
	var locked_seen: Array = _locked_cards(meta).filter(func(id): return seen.has(id))
	_check("пустой профиль: ордены %s, закрытые карты в магазине и подкреплении не выпадают (выпало %s)" % [
		chapters_open, locked_seen], chapters_open == ["ultramarines"] and locked_seen.is_empty() and seen.size() > 10)

	# События забега («Взять снаряжение», «Выслать отряд») тоже не дают закрытых карт
	var events = load("res://scripts/data/RunEvents.gd")
	var ev_rng := RandomNumberGenerator.new()
	ev_rng.seed = 11
	var from_events: Dictionary = {}
	for i in 80:
		bm.pending_cards.clear()
		events._give_card(ev_rng, ["", "common", "rare"][i % 3], "")
		for c in bm.pending_cards:
			from_events[c.id] = true
	var locked_from_events: Array = _locked_cards(meta).filter(func(id): return from_events.has(id))
	_check("события не выдают закрытых карт (выдали %s)" % [locked_from_events], locked_from_events.is_empty()
		and from_events.size() > 5)
	bm.pending_cards.clear()

	# 2. Древо: связность и данные
	var bad: Array = []
	for n in meta.TREE:
		var parent: Dictionary = meta.get_node_data(n["requires"]) if n["requires"] != "" else {}
		if n["requires"] != "" and (parent.is_empty() or parent["branch"] != n["branch"] or parent["row"] >= n["row"]):
			bad.append(n["id"])
		if n["kind"] in ["start_card", "card"] and CardFactory.create(n["target"]) == null:
			bad.append(n["id"])
		if n["kind"] == "chapter" and Chapters.get_chapter(n["target"]).is_empty():
			bad.append(n["id"])
		if n["kind"] == "passive" and meta.get_passive(n["target"]).is_empty():
			bad.append(n["id"])
	var roots: Array = meta.BRANCHES.map(func(b): return meta.branch_nodes(b["id"]).filter(func(n): return n["requires"] == "").size())
	_check("древо: родители в своей ветке выше, карты / ордены / пассивки есть (ошибки: %s), по корню на ветку %s" % [bad, roots],
		bad.is_empty() and roots.all(func(r): return r == 1))

	# 2б. Покупка узлов
	meta.glory = 40
	var no_parent: bool = not meta.buy_node("chapter_space_wolves")        # родитель Blood Angels не куплен
	var root_ok: bool = meta.buy_node("chapter_blood_angels")               # 40 − 15 = 25
	var twice: bool = not meta.buy_node("chapter_blood_angels")
	var child_ok: bool = meta.buy_node("chapter_space_wolves")              # 25 − 25 = 0
	var poor: bool = not meta.buy_node("card_orbital_strike")                # 20 > 0
	meta.load_profile()   # из файла
	_check("покупка: без родителя нет, корень и потомок да (Слава %d), дважды и без Славы нет; орден открыт, из файла" % meta.get_glory(),
		no_parent and root_ok and twice and child_ok and poor and meta.get_glory() == 0
		and meta.is_chapter_unlocked("blood_angels") and meta.is_chapter_unlocked("space_wolves")
		and not meta.is_chapter_unlocked("imperial_fists") and not meta.is_card_unlocked("orbital_strike"))

	# 3. Слава за забег
	rm.difficulty = 2
	em.wins = 4
	meta.run_minibosses = 1
	var lost: Dictionary = meta.on_run_end(false)   # 4 + 3 = 7 × 1.0
	rm.difficulty = 7
	em.wins = 14
	meta.run_minibosses = 2
	var won: Dictionary = meta.on_run_end(true)     # (15 + 6 + 10) × 2.25 = 70
	meta.on_battle_won("miniboss")
	_check("Слава: проигрыш на сложности 2 +%d (ожидалось 7), победа на 7 +%d (ожидалось 70), всего %d; мини-босс в счётчике забега" % [
		lost["glory"], won["glory"], meta.get_glory()], lost["glory"] == 7 and won["glory"] == 70
		and meta.get_glory() == 77 and meta.run_minibosses == 3)

	# 4. Перенос старого профиля
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "glory", 12)
	legacy.set_value("meta", "passives", {"reserves": 2, "walls": 1})
	legacy.set_value("meta", "start_cards", ["scout_squad"])
	legacy.set_value("meta", "stats", {"best_wave": 8, "total_wins": 3, "minibosses_total": 0, "runs_won": 0})
	legacy.save(PROFILE)
	meta.load_profile()
	var migrated: Array = meta.owned_nodes.duplicate()
	migrated.sort()
	meta.save_profile()
	var after := ConfigFile.new()
	after.load(PROFILE)
	_check("перенос: %s, Слава %d, старые ключи убраны" % [migrated, meta.get_glory()],
		migrated == ["chapter_blood_angels", "chapter_space_wolves", "reserves_1", "reserves_2", "start_scout_squad", "walls_1"]
		and meta.get_glory() == 12 and meta.passive_level("reserves") == 2
		and not after.has_section_key("meta", "passives") and after.has_section_key("meta", "nodes"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	meta.load_profile()

	# 5. Пассивки и стартовая карта в деле
	meta.glory = 300
	for id in ["reserves_1", "reserves_2", "reserves_3", "walls_1", "walls_2", "start_scout_squad", "veterans_1", "munitorum_1"]:
		meta.buy_node(id)
	meta.select_start_card("scout_squad")
	bm.reset_run()
	var req_ok: bool = em.requisition == em.STARTING_REQUISITION + 9
	var card_in_hand: bool = bm.pending_cards.any(func(c): return c.id == "scout_squad")
	shop.open_shop()
	var free_reroll: bool = shop.get_reroll_cost() == 0 and shop.try_reroll() and shop.get_reroll_cost() > 0
	bm.prepare_citadel_shield()
	var shield_ok: bool = is_equal_approx(bm.citadel_shield, 200.0)
	var d = UnitFactory.create("tactical_marine")
	d.squad_size = 3
	d.saved_hp = [1.0, 1.0, 1.0] as Array[float]
	bm.player_units = [d] as Array[UnitData]
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(3)
	var soldier = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(0)[0]
	var hp_before: float = soldier.max_hp
	root.get_node("SynergyManager").apply_meta_bonus([soldier])
	_check("пассивки: Req %d (+9), щит цитадели %.0f (+200), первое обновление бесплатно, +5%% HP бойцам (%.1f → %.1f); стартовая карта в руке" % [
		em.requisition, bm.citadel_shield, hp_before, soldier.max_hp], req_ok and shield_ok and free_reroll and card_in_hand
		and is_equal_approx(soldier.max_hp, hp_before * 1.05))
	bm.stop_battle()

	# 6. Сохранение выключено — всё открыто, пассивок нет (тесты, balance_sim)
	sm.enabled = false
	var all_open: bool = Chapters.CHAPTERS.all(func(c): return meta.is_chapter_unlocked(c["id"])) \
		and _locked_cards(meta).all(func(id): return meta.is_card_unlocked(id))
	_check("сохранение выключено: всё открыто, пассивки 0, стартовой карты нет", all_open
		and meta.passive_value("reserves") == 0.0 and meta.available_start_cards().is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit()
