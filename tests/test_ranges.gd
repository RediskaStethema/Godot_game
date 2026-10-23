extends SceneTree

# Дальности (решения пользователя): Bolter Turret бьёт на всё поле (у карты нет attack_range),
# Scout — снайперы: самая большая дальность среди бойцов, но мало HP.
# Сохранение выключено — забег игрока не трогает.
#   godot --headless --path . -s tests/test_ranges.gd

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")

	# 1. Scout: дальность больше, чем у любого другого бойца (свои и враги), HP — меньше, чем у Tactical
	var scout = UnitFactory.create("scout_marine")
	var others = ["tactical_marine", "assault_marine", "devastator", "terminator", "apothecary", "librarian",
		"chaplain", "land_speeder", "dreadnought", "chapter_master", "chaos_marine", "chaos_cultist",
		"chaos_havoc", "chaos_raptor", "plague_marine", "chaos_champion", "chaos_hellbrute", "chaos_lord"]
	var longest_other = 0.0
	for id in others:
		longest_other = maxf(longest_other, UnitFactory.create(id).attack_range)
	_check("Scout: дальность %.0f > %.0f у остальных, HP %.0f < Tactical %.0f" % [scout.attack_range, longest_other,
		scout.hp, UnitFactory.create("tactical_marine").hp],
		scout.attack_range > longest_other and scout.hp < UnitFactory.create("tactical_marine").hp)

	# 2. Chaplain стреляет вблизи из болт-пистолета (лист спрайтов): дальше ближнего боя, ближе Tactical
	var chaplain = UnitFactory.create("chaplain")
	_check("Chaplain: стрелок, дальность %.0f, снаряд %s" % [chaplain.attack_range, chaplain.projectile],
		"ranged" in chaplain.tags and not "melee" in chaplain.tags and chaplain.projectile == "bolt"
		and chaplain.attack_range > 60.0 and chaplain.attack_range < UnitFactory.create("tactical_marine").attack_range)

	# 3. Турель в бою бьёт врага на другом краю поля (дальше прежних 300 px)
	bm.reset_run()
	rm.new_run(3)
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	var tac = UnitFactory.create("tactical_marine")
	tac.squad_size = 9
	var hp: Array[float] = []
	for i in 9:
		hp.append(1.0)
	tac.saved_hp = hp
	bm.player_units = [tac] as Array[UnitData]
	bm.player_placements = {tac: Vector2i(1, 1)}
	var turret_card = CardFactory.bolter_turret()
	bm.player_buildings = {turret_card: Vector2i(0, 0)}
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var turret = bm.buildings[0]
	scene._on_start_pressed(false)
	await process_frame
	var nearest = INF
	for e in root.get_node("SoldierRegistry").get_alive_soldiers_of_team(1):
		nearest = minf(nearest, turret.global_position.distance_to(e.global_position))
	turret.tick(0.1)
	var shot = bm.projectiles.filter(func(p): return is_instance_valid(p) and p.get("_target") != null)
	var target = shot[0].get("_target") if not shot.is_empty() else null
	var target_hp = target.current_hp if target else 0.0
	# Снаряд долетает до другого края поля и ранит цель (полёт — тиками боя)
	for i in 30:
		if shot.is_empty() or not is_instance_valid(shot[0]) or shot[0].finished:
			break
		shot[0].tick(0.1)
	_check("турель: нет дальности у карты, выстрел по врагу в %.0f px попал" % nearest,
		not turret_card.building_stats.has("attack_range") and nearest > 300.0 and target != null
		and is_instance_valid(target) and target.current_hp < target_hp)

	bm.stop_battle()
	scene.queue_free()
	bm.reset_run()
	quit()
