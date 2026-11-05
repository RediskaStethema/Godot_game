extends SceneTree

# Состав и размер отрядов (решения пользователя): отрядов из одного бойца нет — герои и техника
# парами (2 → 3 → 4 → 5 по уровням), сила пары как у прежнего одиночки; Космодесант в силовой
# броне и техника на 10% крупнее, люди (Scout, культисты) — прежнего роста.
#   godot --headless --path . -s tests/test_squad_sizes.gd

const EPS: float = 0.001
var UF = load("res://scripts/data/UnitFactory.gd")   # статы функций по имени — прежние «на бойца»

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _main() -> void:
	await process_frame

	# 1. Ни одной карты отряда с одним бойцом
	var singles = []
	for c in CardFactory.build_pool():
		if c.card_type == "squad" and c.unit_count < 2 and not singles.has(c.id):
			singles.append(c.id)
	_check("в пуле нет отрядов из одного бойца %s" % [singles], singles.is_empty())

	# 2. Пара героев: HP, урон и лечение бойца пополам, вес 1/2, уровни 2 → 3 → 4 → 5
	var ok_pairs = true
	var sizes = []
	for id in UnitFactory.PAIR_UNITS:
		var base: UnitData = UF.call(id)   # статы функции — прежний одиночка
		var d = UnitFactory.create(id)
		ok_pairs = ok_pairs and absf(d.hp * 2.0 - base.hp) < EPS and absf(d.damage * 2.0 - base.damage) < EPS \
			and absf(d.heal_per_second * 2.0 - base.heal_per_second) < EPS and absf(d.unit_weight - 0.5) < EPS 			and absf(d.on_hit_stun * 2.0 - base.on_hit_stun) < EPS and absf(d.on_hit_knockback * 2.0 - base.on_hit_knockback) < EPS
	var card = CardFactory.chaplain_card()
	var pair = UnitFactory.create(card.unit_factory_id)
	pair.squad_size = card.unit_count
	pair.squad_growth = UnitFactory.squad_growth_for(card)
	sizes.append(pair.squad_size)
	for i in UnitFactory.MAX_SQUAD_LEVEL:
		pair.apply_merge_upgrade()
		sizes.append(pair.squad_size)
	# Отряд пал целиком в выигранном бою — пара на уровень ниже: 5 бойцов ур.3 → 4 бойца ур.2
	pair.respawn_after_wipe()
	_check("пары: сила как у одиночки, уровни %s, возрождение ур.%d ×%d" % [sizes, pair.squad_level, pair.squad_size],
		ok_pairs and sizes == [2, 3, 4, 5] and pair.squad_level == 2 and pair.squad_size == 4)

	# 3. Броня Космодесанта и техника — ×1.1 к росту, люди — прежние
	var ok_scale = true
	for id in UnitFactory.ARMOURED_UNITS:
		ok_scale = ok_scale and absf(UnitFactory.create(id).sprite_scale - UF.call(id).sprite_scale * 1.1) < EPS
	for id in ["scout_marine", "chaos_cultist", "chaos_marine"]:
		ok_scale = ok_scale and absf(UnitFactory.create(id).sprite_scale - UF.call(id).sprite_scale) < EPS
	_check("рост: броня и техника ×1.1, Scout и Хаос — прежние", ok_scale and not "scout_marine" in UnitFactory.ARMOURED_UNITS)

	# 4. Старое сохранение: одиночка ур.1 → пара + боец уровня, доли HP те же; пехота — как раньше
	var old_hero = UnitData.from_save_state({"id": "librarian", "saved_hp": [0.5], "hp_mult": 1.0, "dmg_mult": 1.0,
		"as_mult": 1.0, "upgrades": [], "squad_size": 1, "level": 1, "growth": 0})
	var old_tac = UnitData.from_save_state({"id": "tactical_marine", "saved_hp": [1.0, 1.0, 1.0], "hp_mult": 1.0,
		"dmg_mult": 1.0, "as_mult": 1.0, "upgrades": [], "squad_size": 3, "level": 0})
	_check("старое сохранение: Librarian %d бойцов %s, Tactical %d" % [old_hero.squad_size, old_hero.saved_hp, old_tac.squad_size],
		old_hero.squad_size == 3 and old_hero.squad_growth == 1 and old_hero.saved_hp.size() == 2 and old_hero.saved_hp.all(func(v): return absf(v - 0.5) < EPS)
		and old_tac.squad_size == 9 and old_tac.squad_growth == 2)

	# 5. Карта отряда на свой отряд (решение пользователя 21.10.2026, без меню): уровень +1, бойцы роста,
	#    лечение 30% и возврат павших; на максимуме — только лечение; здоров и на максимуме — карта не тратится
	var bm = root.get_node("BattleManager")
	bm.reset_run()
	var tac_card = CardFactory.tactical_squad()
	var d5 = UnitFactory.create(tac_card.unit_factory_id)
	d5.squad_size = tac_card.unit_count
	d5.squad_growth = UnitFactory.squad_growth_for(tac_card)
	var hp: Array[float] = []
	for i in 6:
		hp.append(0.5)
	d5.saved_hp = hp
	bm.player_units = [d5] as Array[UnitData]
	bm.player_placements = {d5: Vector2i(1, 1)}
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var squad = root.get_node("SquadRegistry").get_alive_squads_of_team(0)[0]
	var played: bool = scene._play_squad_card(tac_card, Vector2i(1, 1))
	var ratio: float = squad.soldiers[0].current_hp / squad.soldiers[0].max_hp
	_check("улучшение: ур. %d, бойцов %d из %d, раненый 0.5 → %.2f (с учётом +20%% HP уровня)" % [d5.squad_level,
		squad.soldiers.size(), d5.squad_size, ratio],
		played and d5.squad_level == 1 and d5.squad_size == 11 and squad.soldiers.size() == 11 and ratio > 0.6)
	d5.squad_level = UnitFactory.MAX_SQUAD_LEVEL
	squad.soldiers[0].current_hp = squad.soldiers[0].max_hp * 0.2
	var healed: bool = scene._play_squad_card(tac_card, Vector2i(1, 1))
	var after: float = squad.soldiers[0].current_hp / squad.soldiers[0].max_hp
	for s in squad.soldiers:
		s.current_hp = s.max_hp
	var wasted: bool = scene._play_squad_card(tac_card, Vector2i(1, 1))
	_check("на максимуме — лечение 0.2 → %.2f; здоров — карта не тратится" % after,
		healed and absf(after - 0.5) < EPS and not wasted)
	scene.queue_free()
	bm.reset_run()
	quit()
