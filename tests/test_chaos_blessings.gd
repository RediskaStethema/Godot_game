extends SceneTree

# Боги отрядов Хаоса и благословения (решение пользователя 25.10.2026, ChaosGods, CARD_ABILITIES.txt): бог отряда по
# лору (у Common нет), карты в пуле Хаоса и их арт, кому можно сыграть (свой бог, до 3, Вестник — стрелкам), статы
# благословений, смена бога (благословения пропадают), сохранение, яд и порабощение в бою (боец уходит в отряд
# Король Второго Акта, бьётся за нас, вражеский отряд из одних порабощённых пал), порабощённые после боя (павшие / лечение),
# Котёл — яд в атаках соседей. Классы сцен и бойцов по имени не упоминаются (скрипт компилируется до автолоадов).
#   godot --headless --path . -s tests/test_chaos_blessings.gd
const EPS: float = 0.01

var bm: Node
var rm: Node

func _initialize() -> void:
	root.get_node("GameSettings").names_language = "en"   # тесты сверяют английские названия (по умолчанию игроку показываются русские)
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	bm = root.get_node("BattleManager")
	rm = root.get_node("RunManager")
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _squad(card_id: String) -> UnitData:
	var card = CardFactory.create(card_id)
	var d = UnitFactory.create(card.unit_factory_id)
	d.squad_size = card.unit_count
	d.squad_growth = UnitFactory.squad_growth_for(card)
	var hp: Array[float] = []
	for i in d.squad_size:
		hp.append(1.0)
	d.saved_hp = hp
	return d

func _battle(units: Dictionary, buildings: Dictionary = {}, chapter: String = "") -> Node:
	if current_scene:
		current_scene.queue_free()
		await process_frame
	bm.stop_battle()
	rm.player_faction = "chaos"
	bm.reset_run()
	rm.player_chapter = chapter
	rm.new_run(3)
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	var list: Array[UnitData] = []
	for d in units:
		list.append(d)
	bm.player_units = list
	bm.player_placements = units
	bm.player_buildings = buildings
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	scene._on_start_pressed(false)
	await process_frame
	return scene

func _squad_node(d: UnitData) -> Node:
	for sq in root.get_node("SquadRegistry").get_alive_squads_of_team(0):
		if sq.data == d:
			return sq
	return null

func _main() -> void:
	await process_frame

	# 1. Бог отряда по лору, у Common бога нет
	var gods := {}
	for id in ["plague_marines", "havocs", "chaos_champions", "hellbrute", "chaos_lord", "cultists", "chaos_marines",
			"raptors", "khorne_berzerkers", "plaguebearers", "rubric_marines", "noise_marines"]:
		gods[id] = _squad(id).get_god()
	_check("бог отряда по лору: %s" % str(gods), gods["plague_marines"] == "nurgle" and gods["havocs"] == "tzeentch"
		and gods["chaos_champions"] == "khorne" and gods["hellbrute"] == "khorne" and gods["chaos_lord"] == "slaanesh"
		and gods["cultists"] == "" and gods["chaos_marines"] == "" and gods["raptors"] == ""
		and gods["khorne_berzerkers"] == "khorne" and gods["plaguebearers"] == "nurgle"
		and gods["rubric_marines"] == "tzeentch" and gods["noise_marines"] == "slaanesh")

	# 2. Карты: в пуле Хаоса (Rare, 4 благословения по 1, смена бога — 2), не у Космодесанта, есть арт
	var ids := ["blessing_khorne", "blessing_nurgle", "blessing_tzeentch", "blessing_slaanesh", "chaos_gods_blessing"]
	var chaos_pool: Array = CardFactory.ids_of(CardFactory.build_pool("chaos"))
	var sm_pool: Array = CardFactory.ids_of(CardFactory.build_pool("space_marines"))
	var cards_ok := true
	for id in ids:
		var c = CardFactory.create(id)
		cards_ok = cards_ok and c != null and c.rarity == "rare" and c.faction == "chaos" and not id in sm_pool \
			and ResourceLoader.exists("res://assets/ui/card_art/%s.png" % id)
	_check("карты благословений: в пуле Хаоса (по 1, смена бога — 2, %d и %d Req), не у Космодесанта, с артом" % [
		CardFactory.create("blessing_khorne").cost, CardFactory.create("chaos_gods_blessing").cost],
		cards_ok and chaos_pool.count("blessing_nurgle") == 1 and chaos_pool.count("chaos_gods_blessing") == 2
		and CardFactory.create("chaos_gods_blessing").cost == 5 and CardFactory.create("blessing_slaanesh").cost == 7)

	# 3. Кому можно: свой бог, не больше 3, Вестник — только стрелкам, смена бога — не Common
	var champ := _squad("chaos_champions")   # Кипящий, ближний бой
	var plague := _squad("plague_marines")   # Дедушка Тысячи
	var cult := _squad("cultists")
	var bk = CardFactory.create("blessing_khorne")
	var allowed := champ.can_apply_upgrade(bk) and not plague.can_apply_upgrade(bk) and not cult.can_apply_upgrade(bk)
	for i in 3:
		champ.apply_upgrade(bk)
	var tz_champ := _squad("chaos_champions")
	tz_champ.change_god("tzeentch")
	var cg = CardFactory.create("chaos_gods_blessing")
	# Common без бога (решение пользователя 25.10.2026): благословение бога — нельзя; «Chaos Gods' Blessing» — можно,
	# отряд получает бога, дальше — благословения только этого бога
	var cult_b := _squad("cultists")
	var no_bless := not cult_b.can_apply_upgrade(CardFactory.create("blessing_slaanesh")) 		and not cult_b.can_apply_upgrade(CardFactory.create("blessing_khorne")) and cult_b.can_apply_upgrade(cg)
	cult_b.change_god("slaanesh")
	_check("Common: благословение нельзя, смена бога — можно (%s), дальше — благословения только его бога" % 		cult_b.get_god(), no_bless and cult_b.get_god() == "slaanesh"
		and not cult_b.can_apply_upgrade(CardFactory.create("blessing_khorne"))
		and cult_b.can_apply_upgrade(CardFactory.create("blessing_slaanesh"))
		and UnitData.from_save_state(cult_b.save_state()).get_god() == "slaanesh"
		and not _squad("chaos_marines").can_apply_upgrade(CardFactory.create("blessing_tzeentch")))
	_check("кому можно: свой бог, после 3 — нет, Вестник — не ближникам, смена бога — любому отряду Хаоса",
		allowed and champ.blessings == 3 and not champ.can_apply_upgrade(bk)
		and not tz_champ.can_apply_upgrade(CardFactory.create("blessing_tzeentch"))
		and _squad("havocs").can_apply_upgrade(CardFactory.create("blessing_tzeentch"))
		and champ.can_apply_upgrade(cg) and cult.can_apply_upgrade(cg))

	# 4. Статы благословений (3 Кипящего, 1 Дедушки Тысячи, 2 Вестника, 1 Король Второго Акта)
	var base_champ := _squad("chaos_champions")
	var nurg := _squad("plague_marines")
	var base_nurg := _squad("plague_marines")
	nurg.apply_upgrade(CardFactory.create("blessing_nurgle"))
	var hav := _squad("havocs")
	var base_hav := _squad("havocs")
	for i in 2:
		hav.apply_upgrade(CardFactory.create("blessing_tzeentch"))
	var lord := _squad("chaos_lord")
	var base_lord := _squad("chaos_lord")
	var berz_like := _squad("havocs")   # Havocs отступают; переведены к Кипящему и благословлены — нет
	berz_like.change_god("khorne")
	berz_like.apply_upgrade(CardFactory.create("blessing_khorne"))
	lord.apply_upgrade(CardFactory.create("blessing_slaanesh"))
	_check("статы: Кипящий ×1.45 урона, не отступает; Дедушка Тысячи +20%% HP, урон ×0.9, яд %.0f; Вестник +30%% дальности, +%.1f урона, ×0.81 скорострельности; Король Второго Акта ×0.95, шанс %.0f%%" % [
		ChaosGods.poison_power("nurgle", 1), hav.get_damage() - base_hav.get_damage(),
		ChaosGods.charm_chance("slaanesh", 1) * 100.0],
		absf(champ.get_damage() - base_champ.get_damage() * 1.45) < EPS and champ.get_retreat_threshold() == 0.0
		and berz_like.get_retreat_threshold() == 0.0 and _squad("havocs").get_retreat_threshold() > 0.0
		and absf(nurg.get_max_hp() - base_nurg.get_max_hp() * 1.2) < EPS and absf(nurg.get_damage() - base_nurg.get_damage() * 0.9) < EPS
		and absf(hav.get_attack_range() - base_hav.get_attack_range() * 1.3) < EPS
		and absf(hav.get_damage() - (base_hav.get_damage() + 10.0 * hav.unit_weight)) < EPS
		and absf(hav.get_attack_speed() - base_hav.get_attack_speed() * 0.81) < EPS
		and absf(lord.get_max_hp() - base_lord.get_max_hp() * 0.95) < EPS
		and absf(lord.get_move_speed() - base_lord.get_move_speed() * 0.95) < EPS
		and is_equal_approx(ChaosGods.charm_chance("slaanesh", 3), 0.10))

	# 5. Смена бога: благословения пропадают; сохранение — бог и благословения
	champ.change_god("nurgle")
	var lost := champ.blessings == 0 and champ.get_god() == "nurgle" and absf(champ.get_damage() - base_champ.get_damage()) < EPS
	champ.apply_upgrade(CardFactory.create("blessing_nurgle"))
	var restored := UnitData.from_save_state(champ.save_state())
	var old_save := UnitData.from_save_state(_squad("hellbrute").save_state())
	_check("смена бога: благословения пропали; сохранение: %s, %d благословение; без поля — бог по лору" % [
		restored.get_god(), restored.blessings],
		lost and restored.get_god() == "nurgle" and restored.blessings == 1 and old_save.get_god() == "khorne")
	champ.respawn_after_wipe()
	_check("отряд пал целиком — благословения сброшены, бог остался", champ.blessings == 0 and champ.get_god() == "nurgle")

	# 6. Бой: яд Дедушки Тысячи в атаках, порабощение Король Второго Акта (шанс 1 — гарантия), боец уходит в наш отряд
	var lord_b := _squad("chaos_lord")
	lord_b.apply_upgrade(CardFactory.create("blessing_slaanesh"))
	var nurg_b := _squad("plague_marines")
	nurg_b.apply_upgrade(CardFactory.create("blessing_nurgle"))
	await _battle({lord_b: Vector2i(1, 1), nurg_b: Vector2i(2, 1)})
	var lord_sq = _squad_node(lord_b)
	var nurg_sq = _squad_node(nurg_b)
	var p0 = nurg_sq.soldiers[0]
	_check("в бою: яд в атаках Дедушки Тысячи %.0f ур/с, шанс порабощения Король Второго Акта %.0f%%" % [p0.bonus_poison_power,
		lord_sq.soldiers[0].charm_chance * 100.0],
		is_equal_approx(p0.bonus_poison_power, 2.0) and is_equal_approx(lord_sq.soldiers[0].charm_chance, 0.03))
	var reg = root.get_node("SoldierRegistry")
	var enemies: Array = reg.get_alive_soldiers_of_team(1).duplicate()
	var victim = null
	for e in enemies:
		if not ("elite" in e.data.tags or "commander" in e.data.tags):
			victim = e
			break
	var enemy_sq = victim.parent_squad
	var enemy_before: int = enemy_sq.soldiers.size()
	var dealer = lord_sq.soldiers[0]
	dealer.apply_blessing_hit(victim, 2.0, 1.0, lord_sq)
	var moved = victim.charmed and victim.team == 0 and victim.parent_squad == lord_sq and victim in lord_sq.soldiers \
		and not victim in enemy_sq.soldiers and enemy_sq.soldiers.size() == enemy_before - 1 \
		and victim in reg.get_alive_soldiers_of_team(0) and not victim in reg.get_alive_soldiers_of_team(1)
	_check("порабощение: боец перешёл на нашу сторону в отряд Chaos Lord, отравлен (%d), в реестре — наш" % \
		victim.get_status_stacks("poisoned"), moved and victim.get_status_stacks("poisoned") == 1 and bm.thralls.get(lord_b, 0) == 1)
	# Остальных бойцов того же вражеского отряда — тоже: отряд из одних порабощённых пал
	for s in enemy_sq.soldiers.duplicate():
		if s.can_be_charmed(lord_sq):
			dealer.apply_blessing_hit(s, 0.0, 1.0, lord_sq)
	_check("вражеский отряд, все бойцы которого порабощены, пал (бой может кончиться)", not enemy_sq.is_alive()
		and not enemy_sq in root.get_node("SquadRegistry").get_alive_squads_of_team(1))
	var elite = null
	for e in reg.get_alive_soldiers_of_team(1):
		if "elite" in e.data.tags:
			elite = e
	_check("элиту не порабощает", elite == null or not elite.can_be_charmed(lord_sq))

	# 7. После боя: порабощённые не сохраняются бойцами; за каждого — павший вернулся, полный состав — лечение 25%
	var thralls_n: int = bm.thralls[lord_b]
	lord_sq.soldiers[0].take_damage(lord_sq.soldiers[0].max_hp * 2.0)   # один свой боец пал
	var survivors = bm.store_survivors(root.get_node("SquadRegistry").get_alive_squads_of_team(0), [])
	var size_after_store: int = lord_b.saved_hp.size()
	var applied: int = bm.apply_thralls()
	_check("после боя: порабощённых %d — в армию не попали (%d бойцов), павший вернулся → %d/%d" % [
		thralls_n, size_after_store, lord_b.saved_hp.size(), lord_b.squad_size],
		survivors.is_empty() and size_after_store == lord_b.squad_size - 1 and applied == thralls_n
		and lord_b.saved_hp.size() == lord_b.squad_size)
	var full := _squad("chaos_lord")
	full.saved_hp = [0.5, 0.5] as Array[float]
	bm.player_units.append(full)
	bm.thralls = {full: 2}
	bm.apply_thralls()
	_check("полный состав: порабощённые лечат отряд на 25%% один раз (%.2f)" % full.saved_hp[0],
		is_equal_approx(full.saved_hp[0], 0.75) and is_equal_approx(full.saved_hp[1], 0.75))

	# 8. Котёл Дедушки Тысячи: атаки отряда на соседней клетке отравляют — только в забеге за Дедушки Тысячи (решение пользователя
	# 25.10.2026: особый эффект здания бога — только у своего бога)
	var neigh := _squad("chaos_marines")
	var scene = await _battle({neigh: Vector2i(1, 1)}, {CardFactory.special_card("plague_cauldron"): Vector2i(1, 2)}, "nurgle")
	var n0 = _squad_node(neigh).soldiers[0]
	var badge = scene.hud.find_child("ChapterBadge", true, false)
	_check("котёл за Дедушки Тысячи: атаки соседнего отряда отравляют (%.1f ур/с); значок бога в шапке" % n0.bonus_poison_power,
		is_equal_approx(n0.bonus_poison_power, 2.0) and badge != null and "Grandfather of the Thousand" in badge.tooltip_text)
	var neigh2 := _squad("chaos_marines")
	await _battle({neigh2: Vector2i(1, 1)}, {CardFactory.special_card("plague_cauldron"): Vector2i(1, 2)}, "khorne")
	var cauldron = null
	for b in bm.buildings:
		if b.building_type == "plague_cauldron":
			cauldron = b
	_check("котёл за Кипящего: соседям яда нет (%.1f), аура котла — есть; в подсказке «не ваш бог»" % 		_squad_node(neigh2).soldiers[0].bonus_poison_power,
		_squad_node(neigh2).soldiers[0].bonus_poison_power == 0.0 and cauldron.stats.get("poison_radius", 0.0) > 0.0
		and "Не ваш Внешний" in cauldron.effect_text())

	bm.stop_battle()
	if current_scene:
		current_scene.queue_free()
	await process_frame
	quit()
