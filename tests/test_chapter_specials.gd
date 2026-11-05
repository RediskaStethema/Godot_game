extends SceneTree

# Особое у орденов и богов (решение пользователя 18.10.2026): у каждого — свой юнит (Epic) и здание (Rare)
# только в магазине своего ордена, бонус и минус. Проверки: данные и карты, пул по ордену, карта по id
# при любом ордене, минус в бою (скорость, получаемый урон), здания на соседние отряды в начале боя
# (щит, вампиризм, клич, +урон) — а по диагонали нет, алтарь черепов, котёл, шпиль, ремонт кузней.
# Классы сцен и бойцов по имени не упоминаются (скрипт компилируется до автолоадов).
#   godot --headless --path . -s tests/test_chapter_specials.gd
const EPS: float = 0.01

var bm: Node
var rm: Node

func _initialize() -> void:
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

# Бой волны 1 с армией и зданиями на заданных клетках; возвращает сцену после «В БОЙ»
func _battle(faction: String, chapter: String, units: Dictionary, buildings: Dictionary) -> Node:
	if current_scene:
		current_scene.queue_free()
		await process_frame
	bm.stop_battle()
	rm.player_faction = faction
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

func _soldiers_of(d: UnitData) -> Array:
	for sq in root.get_node("SquadRegistry").get_alive_squads_of_team(0):
		if sq.data == d:
			return sq.soldiers
	return []

func _main() -> void:
	await process_frame

	# 1. Данные: у каждого ордена и бога — минус, юнит и здание; юнит создаётся по своему id (не запасной Tactical)
	var bad: Array = []
	for c in Chapters.CHAPTERS:
		var unit_card = CardFactory.special_card(c.get("unit_card", ""))
		var building_card = CardFactory.special_card(c.get("building_card", ""))
		if not c.has("malus") or unit_card == null or building_card == null \
				or unit_card.rarity != "epic" or building_card.rarity != "rare" \
				or unit_card.faction != c["faction"] or building_card.faction != c["faction"] \
				or UnitFactory.create(unit_card.unit_factory_id).factory_id != unit_card.unit_factory_id:
			bad.append(c["id"])
	_check("9 орденов и богов: минус, Epic-юнит и Rare-здание своей расы %s" % str(bad),
		Chapters.CHAPTERS.size() == 9 and bad.is_empty())

	# 2. Пул: особые карты — только у своего ордена, по 2 копии; без ордена и с чужим — нет
	rm.player_faction = "space_marines"
	rm.player_chapter = "ultramarines"
	var um = CardFactory.build_pool("space_marines")
	rm.player_chapter = ""
	var none = CardFactory.build_pool("space_marines")
	rm.player_chapter = "khorne"
	var foreign = CardFactory.build_pool("space_marines")
	var chaos_khorne = CardFactory.build_pool("chaos")
	var count = func(pool, id): return pool.filter(func(c): return c.id == id).size()
	_check("пул: Ultramarines +2 стражи +2 бастиона (%d / %d), без ордена %d, с чужим богом %d; Хаос с Кхорном — берсерки %d" % [
		count.call(um, "honour_guard"), count.call(um, "codex_bastion"), none.size(), foreign.size(),
		count.call(chaos_khorne, "khorne_berzerkers")],
		count.call(um, "honour_guard") == 2 and count.call(um, "codex_bastion") == 2 and um.size() == none.size() + 4
		and foreign.size() == none.size() and count.call(chaos_khorne, "khorne_berzerkers") == 2
		and count.call(chaos_khorne, "skull_altar") == 2)
	rm.player_chapter = ""
	var by_id = CardFactory.create("rubric_marines")
	_check("карта по id (сохранения) — при любом ордене: %s" % (by_id.title if by_id else "нет"),
		by_id != null and by_id.unit_factory_id == "rubric_marines")

	# 3. Минус в бою: Ultramarines — бег ×0.9 (дальность ×1.1 — бонус); Slaanesh — получаемый урон ×1.1
	var tac = _squad("tactical_squad")
	await _battle("space_marines", "ultramarines", {tac: Vector2i(2, 1)}, {})
	var s0 = _soldiers_of(tac)[0]
	_check("Ultramarines: бег %.1f = %.1f × 0.9, дальность ×1.1" % [s0.current_move_speed, tac.get_move_speed()],
		absf(s0.current_move_speed - tac.get_move_speed() * 0.9) < EPS
		and absf(s0.current_attack_range - tac.attack_range * 1.1) < EPS)
	var cm = _squad("chaos_marines")
	await _battle("chaos", "slaanesh", {cm: Vector2i(2, 1)}, {})
	var c0 = _soldiers_of(cm)[0]
	var before: float = c0.current_hp
	c0.take_damage(10.0, false)
	_check("Slaanesh: удар 10 снимает %.1f HP (×1.1)" % (before - c0.current_hp), absf(before - c0.current_hp - 11.0) < EPS)

	# 4. Здания на соседей в начале боя: Кодекс-бастион — щит, Чаша — вампиризм; диагональ — ничего
	var near = _squad("tactical_squad")
	var diag = _squad("tactical_squad")
	await _battle("space_marines", "ultramarines", {near: Vector2i(2, 1), diag: Vector2i(2, 2)},
		{CardFactory.special_card("codex_bastion"): Vector2i(1, 1), CardFactory.special_card("blood_chalice"): Vector2i(1, 2)})
	var n0 = _soldiers_of(near)[0]
	var d0 = _soldiers_of(diag)[0]
	# Особый эффект здания — только у своего ордена (решение пользователя 25.10.2026): Чаша Blood Angels за Ultramarines — нет
	_check("Кодекс-бастион: сосед щит %.1f (25%% от %.1f), диагональ %.1f; Чаша чужого ордена: вампиризма нет (%.2f)" % [
		n0.shield, n0.max_hp, d0.shield, d0.lifesteal],
		absf(n0.shield - n0.max_hp * 0.25) < EPS and d0.shield < EPS and d0.lifesteal < EPS and n0.lifesteal < EPS)
	var ba_near = _squad("tactical_squad")
	var ba_far = _squad("tactical_squad")
	await _battle("space_marines", "blood_angels", {ba_near: Vector2i(2, 2), ba_far: Vector2i(2, 0)},
		{CardFactory.special_card("blood_chalice"): Vector2i(1, 2)})
	_check("Чаша за Blood Angels: сосед вампиризм %.2f, не сосед %.2f" % [_soldiers_of(ba_near)[0].lifesteal,
		_soldiers_of(ba_far)[0].lifesteal],
		absf(_soldiers_of(ba_near)[0].lifesteal - 0.2) < EPS and _soldiers_of(ba_far)[0].lifesteal < EPS)

	# 5. Клич Волчьего тотема и +урон Кузни
	var wolf_n = _squad("tactical_squad")
	var forge_n = _squad("tactical_squad")
	# оба отряда — в среднем ряду (x = 1): без бонусов переднего / заднего ряда
	await _battle("space_marines", "space_wolves", {wolf_n: Vector2i(1, 0), forge_n: Vector2i(1, 2)},
		{CardFactory.special_card("wolf_totem"): Vector2i(0, 0), CardFactory.special_card("vulkan_forge"): Vector2i(2, 2)})
	var w0 = _soldiers_of(wolf_n)[0]
	var f0 = _soldiers_of(forge_n)[0]
	# Сравнение с соседом тотема: та же синергия Marine (+10% урона за 6), но без Кузни
	_check("Тотем: сосед усилен (%d стак); Кузня Salamanders за Space Wolves — урон соседа прежний (%.2f = %.2f)" % [
		w0.get_status_stacks("empowered"), f0.current_damage, w0.current_damage],
		w0.get_status_stacks("empowered") == 1 and absf(f0.current_damage - w0.current_damage) < EPS)
	var sal_far = _squad("tactical_squad")
	var sal_near = _squad("tactical_squad")
	await _battle("space_marines", "salamanders", {sal_far: Vector2i(1, 0), sal_near: Vector2i(1, 2)},
		{CardFactory.special_card("vulkan_forge"): Vector2i(2, 2)})
	_check("Кузня за Salamanders: сосед урон %.2f = %.2f × 1.1" % [_soldiers_of(sal_near)[0].current_damage,
		_soldiers_of(sal_far)[0].current_damage],
		absf(_soldiers_of(sal_near)[0].current_damage - _soldiers_of(sal_far)[0].current_damage * 1.1) < EPS)

	# 6. Алтарь черепов: убитые враги — +урон армии; котёл — яд врагам в круге
	var berz = _squad("khorne_berzerkers")
	var scene = await _battle("chaos", "khorne", {berz: Vector2i(2, 1)},
		{CardFactory.special_card("skull_altar"): Vector2i(1, 1), CardFactory.special_card("plague_cauldron"): Vector2i(0, 1)})
	var b0 = _soldiers_of(berz)[0]
	var dmg0: float = b0.current_damage
	var enemies = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(1).duplicate()
	for i in 5:
		enemies[i].take_damage(1e6, false)
	var cauldron = null
	for b in bm.buildings:
		if b.building_type == "skull_altar":
			b.tick(0.1)
		elif b.building_type == "plague_cauldron":
			cauldron = b
	var victim = enemies[5]
	victim.global_position = cauldron.global_position + Vector2(20, 0)
	cauldron.tick(0.1)
	# Берсерки — отряд Кхорна: армии +1% за убитого, им ещё +5% (решение пользователя 25.10.2026): ×1.05 × 1.25
	_check("алтарь: 5 убитых — урон Берсерков %.2f → %.2f (×1.05 армии × 1.25 Кхорну); котёл: враг рядом отравлен (%d)" % [
		dmg0, b0.current_damage, victim.get_status_stacks("poisoned")],
		absf(b0.current_damage - dmg0 * 1.05 * 1.25) < EPS and victim.get_status_stacks("poisoned") == 1)
	var ring = cauldron.get("_aura_ring")
	_check("котёл: в бою — кольцо ауры яда на земле по радиусу %.0f" % cauldron.stats.get("poison_radius", 0.0),
		ring != null and ring.look == "plague" and is_equal_approx(ring.radius, cauldron.stats.get("poison_radius", 0.0))
		and ring.get_parent() == scene.renderer)

	# 7. Кузня после боя чинит цитадель (ур.1 — 50 HP), павшая цитадель — нет
	bm.stop_battle()
	bm.reset_run()
	bm.citadel_hp = 500.0
	bm.player_buildings = {CardFactory.special_card("vulkan_forge"): Vector2i(1, 1)}
	var healed: float = bm.repair_from_forges()
	bm.citadel_hp = 0.0
	_check("Кузня: +%.0f HP цитадели; пала — +%.0f" % [healed, bm.repair_from_forges()],
		absf(healed - 50.0) < EPS and bm.citadel_hp == 0.0)

	if current_scene:
		current_scene.queue_free()
	rm.player_chapter = ""
	rm.player_faction = "space_marines"
	quit()
