extends SceneTree

# Мета-прогрессия (MetaProgress, решение пользователя 16.10.2026 — смешанная схема):
# 1) пустой профиль: открыт только Ultramarines, закрытые карты (Orbital Strike, Plasma Generatorium,
#    Chapter Banner, Apothecarion) в магазин и подкрепление не выпадают;
# 2) достижения по прогрессу: победы → лучшая волна / мини-боссы / побед всего → ордены и карты,
#    названия открытого — для итога боя; прогресс в файле профиля;
# 3) Слава за забег (и проигранный): победы, мини-боссы, главный босс × сложность;
# 4) Арсенал: покупка пассивок и стартовых карт за Славу, предел уровней, не хватает — нет;
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
	for c in Chapters.CHAPTERS:
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
	var locked_seen: Array = meta.CARD_UNLOCKS.keys().filter(func(id): return seen.has(id))
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
	var locked_from_events: Array = meta.CARD_UNLOCKS.keys().filter(func(id): return from_events.has(id))
	_check("события не выдают закрытых карт (выдали %s)" % [locked_from_events], locked_from_events.is_empty()
		and from_events.size() > 5)
	bm.pending_cards.clear()

	# Карты меты существуют (опечатка в id — пустая карта в Арсенале)
	var ids: Array = meta.START_CARDS.map(func(x): return x["card"]) + meta.CARD_UNLOCKS.keys()
	var missing: Array = ids.filter(func(id): return CardFactory.create(id) == null)
	_check("все карты меты есть в CardFactory (нет: %s)" % [missing], missing.is_empty())

	# 2. Достижения
	var opened: Array = []
	for w in range(1, 6):
		opened += meta.on_battle_won(w, "miniboss" if w == 5 else "battle")
	var ba_open: bool = meta.is_chapter_unlocked("blood_angels")
	meta.load_profile()   # из файла
	_check("достижения: волна 5 — Blood Angels открыт (%s), прогресс в файле (лучшая волна %d, побед %d, мини-боссов %d)" % [
		", ".join(opened), meta.stats["best_wave"], meta.stats["total_wins"], meta.stats["minibosses_total"]],
		ba_open and meta.is_chapter_unlocked("blood_angels") and "орден Blood Angels" in opened
		and meta.stats["best_wave"] == 5 and meta.stats["total_wins"] == 5 and meta.stats["minibosses_total"] == 1
		and not meta.is_chapter_unlocked("space_wolves"))

	# 3. Слава за забег
	rm.difficulty = 2
	em.wins = 4
	meta.run_minibosses = 1
	var lost: Dictionary = meta.on_run_end(false)   # 4 + 3 = 7 × 1.0
	rm.difficulty = 7
	em.wins = 14
	meta.run_minibosses = 2
	var won: Dictionary = meta.on_run_end(true)     # (15 + 6 + 10) × 2.25 = 70
	_check("Слава: проигрыш на сложности 2 +%d (ожидалось 7), победа на 7 +%d (ожидалось 70), всего %d; Salamanders открыт" % [
		lost["glory"], won["glory"], meta.get_glory()], lost["glory"] == 7 and won["glory"] == 70
		and meta.get_glory() == 77 and meta.is_chapter_unlocked("salamanders"))

	# 4. Арсенал
	var bought_ok: bool = meta.buy_passive("reserves") and meta.buy_passive("reserves") and meta.buy_passive("reserves")
	var capped: bool = not meta.buy_passive("reserves")   # максимум 3
	var glory_after: int = meta.get_glory()               # 77 − 10 − 20 − 35 = 12
	var card_ok: bool = meta.buy_start_card("scout_squad") and not meta.buy_start_card("scout_squad")
	var poor: bool = not meta.buy_start_card("terminator_squad")   # 30 > 7
	_check("Арсенал: «Резервы» до ур.3 (Слава %d → после карты %d), выше максимума и без Славы — нет" % [
		glory_after, meta.get_glory()], bought_ok and capped and glory_after == 12 and card_ok and poor and meta.get_glory() == 7)

	# 5. Пассивки и стартовая карта в деле
	meta.glory = 200
	for id in ["walls", "walls", "veterans", "munitorum"]:
		meta.buy_passive(id)
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
		and meta.CARD_UNLOCKS.keys().all(func(id): return meta.is_card_unlocked(id))
	_check("сохранение выключено: всё открыто, пассивки 0, стартовой карты нет", all_open
		and meta.passive_value("reserves") == 0.0 and meta.available_start_cards().is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit()
