extends SceneTree

# Хаос как раса игрока (решение пользователя 16.10.2026): пул карт Хаоса, герои-пары,
# волны Космодесанта, боги-покровители, синергия и доход по тегу chaos, бой за Хаос.
# Сохранение выключено — забег игрока не трогает.
#   godot --headless --path . -s tests/test_chaos_race.gd
const EPS: float = 0.001
const BATTLE = "battle"

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _near(a: float, b: float) -> bool:
	return absf(a - b) < EPS * maxf(absf(b), 1.0)

# Бой волны wave за Хаос с богом god: армия — Chaos Marines и Raptors, снимок после «В БОЙ»
func _battle(god: String, wave: int = 1, type: String = BATTLE) -> Dictionary:
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	rm.player_faction = "chaos"
	bm.reset_run()
	rm.new_run(21)
	rm.player_chapter = god
	for n in rm.map.nodes:
		if n.type == type and n.wave == wave:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = wave
	var army: Array[UnitData] = []
	var placements = {}
	for p in [["chaos_marine", Vector2i(1, 0), 9], ["chaos_raptor", Vector2i(1, 2), 6]]:
		var d = UnitFactory.create(p[0])
		var hp: Array[float] = []
		for i in p[2]:
			hp.append(1.0)
		d.saved_hp = hp
		army.append(d)
		placements[d] = p[1]
	bm.player_units = army
	bm.player_placements = placements
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	scene._on_start_pressed(false)
	var reg = root.get_node("SoldierRegistry")
	var enemies: Array = []
	for e in reg.get_alive_soldiers_of_team(1):
		enemies.append({"faction": e.data.faction, "range": e.current_attack_range, "id": e.data.factory_id})
	var out = {"enemies": enemies, "panel": "\n".join(load("res://scenes/battle/ui/BattleHud.gd").synergy_lines()),
		"income": root.get_node("SynergyManager").income_bonus}
	for s in reg.get_alive_soldiers_of_team(0):
		if not out.has(s.data.factory_id):
			out[s.data.factory_id] = {"damage": s.current_damage, "hp": s.max_hp, "move": s.current_move_speed}
	return out

func _finish() -> void:
	root.get_node("BattleManager").stop_battle()
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	await process_frame

func _main() -> void:
	await process_frame
	var rm = root.get_node("RunManager")

	# 1. Пул карт Хаоса: 53 копии (с благословениями богов 25.10.2026), доли 27 / 22 / 4, своих отрядов 8, id не пересекаются с Космодесантом
	var pool: Array = CardFactory.build_pool("chaos")
	var sm_ids: Array = CardFactory.ids_of(CardFactory.build_pool("space_marines"))
	var by_rarity = {"common": 0, "rare": 0, "epic": 0}
	var squads = {}
	var ids_ok = true
	var factions_ok = true
	var upgrades_ok = true
	for c in pool:
		by_rarity[c.rarity] += 1
		ids_ok = ids_ok and not c.id in sm_ids
		factions_ok = factions_ok and c.faction == "chaos"
		if c.card_type == "squad":
			squads[c.id] = true
			factions_ok = factions_ok and UnitFactory.create(c.unit_factory_id).faction == "chaos"
		if c.card_type == "upgrade":
			upgrades_ok = upgrades_ok and c.affects_tag == "chaos"
	_check("пул Хаоса: %d карт (%s), отрядов %d, id свои, улучшения — на отряды Хаоса" % [pool.size(), by_rarity, squads.size()],
		pool.size() == 53 and by_rarity == {"common": 27, "rare": 22, "epic": 4} and squads.size() == 8
		and ids_ok and factions_ok and upgrades_ok)
	rm.player_faction = "space_marines"
	var found = CardFactory.create("warp_strike")
	_check("карта Хаоса находится по id при любой расе (сохранение), пул по умолчанию — раса забега",
		found != null and found.title == "Warp Strike" and found.event_type == "orbital_strike"
		and CardFactory.build_pool().size() == sm_ids.size())
	_check("стартовая карта: карта той же роли расы забега, мета открывает обе",
		CardFactory.equivalent("scout_squad", "chaos").id == "cultists"
		and CardFactory.equivalent("bolter_turret", "chaos").id == "heretic_autocannon"
		and CardFactory.equivalent("scout_squad", "space_marines").id == "scout_squad"
		and CardFactory.base_id("warp_strike") == "orbital_strike")

	# 2. Герои Хаоса — пары: Hellbrute как Dreadnought, Champion растёт на бойца без деления статов
	var hb = UnitFactory.create("hellbrute")
	var dr = UnitFactory.create("dreadnought")
	var champ_card = CardFactory.chaos_champions()
	_check("Hellbrute игрока — пара со статами Dreadnought, Chaos Lord — командир; Champion: пара, +1 боец за уровень",
		_near(hb.hp, dr.hp) and _near(hb.damage, dr.damage) and hb.faction == "chaos"
		and UnitFactory.create("chaos_lord_player").commander_damage_bonus > 0.0
		and UnitFactory.squad_growth_for(champ_card) == UnitFactory.PAIR_GROWTH
		and _near(UnitFactory.create("chaos_champion").hp, UnitFactory.chaos_champion().hp))

	# 3. Волны Космодесанта: архетипы, детерминизм, мини-босс и босс по статам Хаоса
	var sm_ok = true
	var same = true
	for w in range(1, 15):
		for sp in EnemyWaves.build(w, BATTLE, 9, 77, 2, "space_marines"):
			sm_ok = sm_ok and EnemyWaves.SM_ARCHETYPES.has(sp["unit"]) and w >= EnemyWaves.SM_ARCHETYPES[sp["unit"]]["from_wave"]
		same = same and str(EnemyWaves.build(w, BATTLE, 9, 77, 2, "space_marines")) == str(EnemyWaves.build(w, BATTLE, 9, 77, 2, "space_marines"))
	var mini = EnemyWaves.build(10, "miniboss", 9, 77, 2, "space_marines")
	var boss = EnemyWaves.build(15, "boss", 9, 77, 2, "space_marines")
	var dread = UnitFactory.create("dreadnought_boss")
	var cm = UnitFactory.create("chapter_master_boss")
	_check("волны за Хаос — Космодесант: только его архетипы с их волны, тот же seed — тот же состав", sm_ok and same)
	_check("мини-босс — Dreadnought + 2 отряда ветеранов, босс — примарх-лоялист; статы как у Hellbrute / Chaos Lord",
		mini[0]["unit"] == "dreadnought_boss" and mini.filter(func(s): return s["unit"] == "veteran_terminator").size() == 2
		and boss[0]["unit"] in EnemyWaves.SM_BOSS["units"] and _near(dread.hp, UnitFactory.chaos_hellbrute().hp)
		and _near(cm.hp, UnitFactory.chaos_lord().hp) and "elite" in cm.tags)
	_check("волны Хаоса без расы врага — прежние", str(EnemyWaves.build(6, BATTLE, 9, 77, 2))
		== str(EnemyWaves.build(6, BATTLE, 9, 77, 2, "chaos")))

	# 4. Боги-покровители: 4 у Хаоса, ордены — у Космодесанта
	var gods = Chapters.for_faction("chaos").map(func(c): return c["id"])
	_check("боги Хаоса: %s; ордены — только Космодесанту" % [gods], gods == ["khorne", "nurgle", "tzeentch", "slaanesh"]
		and Chapters.for_faction("space_marines").size() == 5 and Chapters.has_chapters("chaos"))

	# 5. Бой за Хаос: враги — Космодесант с дальностью ≤ MAX_ENEMY_RANGE, синергия и доход — по тегу chaos
	var base = await _battle("")
	await _finish()
	var enemies_sm = base["enemies"].all(func(e): return e["faction"] == "space_marines")
	var range_ok = base["enemies"].all(func(e): return e["range"] <= EnemyWaves.MAX_ENEMY_RANGE + EPS)
	_check("бой за Хаос: враги — Космодесант (%d бойцов), дальность ≤ %d" % [base["enemies"].size(), EnemyWaves.MAX_ENEMY_RANGE],
		not base["enemies"].is_empty() and enemies_sm and range_ok)
	_check("синергия Хаоса: 5 юнитов chaos → «Path to Glory», доход +2, в панели — Chaos",
		"Path to Glory" in base["panel"] and base["income"] == 2 and "Chaos: 5" in base["panel"])
	var k = await _battle("khorne")
	await _finish()
	# Минус бога (решение пользователя 25.10.2026; было −20% урона): Кхорн презирает стрелков — их HP −10%
	_check("Кхорн: +20% урона Raptors (ближний бой), Chaos Marines −10% HP (минус бога), в панели «Метка Khorne»",
		_near(k["chaos_raptor"]["damage"], base["chaos_raptor"]["damage"] * 1.2)
		and _near(k["chaos_marine"]["damage"], base["chaos_marine"]["damage"])
		and _near(k["chaos_marine"]["hp"], base["chaos_marine"]["hp"] * 0.9) and "Метка Khorne" in k["panel"])
	var n = await _battle("nurgle")
	await _finish()
	_check("Нургл: +15% HP всем", _near(n["chaos_marine"]["hp"], base["chaos_marine"]["hp"] * 1.15)
		and _near(n["chaos_raptor"]["hp"], base["chaos_raptor"]["hp"] * 1.15))
	var m = await _battle("", 10, "miniboss")
	await _finish()
	_check("мини-босс за Хаос — Dreadnought впереди", m["enemies"].any(func(e): return e["id"] == "dreadnought_boss"))

	# 6. Сохранение забега за Хаос (свой файл): раса, бог, карты Хаоса в руке, отряд-пара Хаоса
	var bm = root.get_node("BattleManager")
	var sv = root.get_node("SaveManager")
	sv.save_path = "user://test_chaos_save.json"
	sv.profile_path = "user://test_chaos_profile.cfg"
	sv.enabled = true
	rm.player_faction = "chaos"
	bm.reset_run()
	rm.new_run(33)
	rm.player_chapter = "nurgle"
	bm.pending_cards = CardFactory.create_many(["heretic_autocannon", "warp_strike", "hellbrute"])
	var brute = UnitFactory.create("hellbrute")
	brute.squad_growth = UnitFactory.squad_growth_for(CardFactory.hellbrute_card())   # как отряд с карты
	brute.saved_hp = [1.0, 0.5] as Array[float]
	bm.player_units = [brute] as Array[UnitData]
	bm.player_placements = {brute: Vector2i(1, 1)}
	sv.save_run()
	rm.player_faction = "space_marines"
	rm.player_chapter = ""
	bm.reset_run()
	var loaded: bool = sv.load_run()
	var hand_titles = bm.pending_cards.map(func(c): return c.title)
	var unit: UnitData = bm.player_units[0] if not bm.player_units.is_empty() else null
	_check("сохранение за Хаос: раса и бог, рука %s, Hellbrute на клетке (2 бойца)" % [hand_titles],
		loaded and rm.player_faction == "chaos" and rm.player_chapter == "nurgle"
		and hand_titles == ["Heretic Autocannon", "Warp Strike", "Hellbrute"]
		and unit != null and unit.factory_id == "hellbrute" and unit.faction == "chaos"
		and unit.saved_hp.size() == 2 and bm.player_placements.get(unit) == Vector2i(1, 1))
	sv.delete_save()
	sv.enabled = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_chaos_profile.cfg"))

	rm.player_faction = "space_marines"
	rm.player_chapter = ""
	quit()
