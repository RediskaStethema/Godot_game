extends SceneTree

# Thunderfire Cannon — орудие под управлением игрока: в бою клик по полю → залп
# по площади (только враги), перезарядка; уровни; бонус Imperial Fists.
# Сохранение выключено — забег игрока не трогает.
#   godot --headless --path . -s tests/test_artillery.gd
const EPS: float = 0.001

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _near(a: float, b: float) -> bool:
	return absf(a - b) < EPS * maxf(absf(b), 1.0)

func _click(scene, world: Vector2) -> void:
	var e = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = root.get_viewport().get_canvas_transform() * world
	scene._unhandled_input(e)

func _cannon():
	for b in root.get_node("BattleManager").buildings:
		if b.building_type == "artillery":
			return b
	return null

func _scene(chapter: String):
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(21)
	rm.player_chapter = chapter
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == 4:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 4
	var d = UnitFactory.create("terminator")
	d.saved_hp = [1.0, 1.0] as Array[float]
	bm.player_units = [d] as Array[UnitData]
	bm.player_placements = {d: Vector2i(2, 1)}
	bm.player_buildings[CardFactory.thunderfire_cannon()] = Vector2i(0, 1)
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	return scene

func _main() -> void:
	await process_frame
	# 1. Карта: Rare 8 Req, в пуле магазина; уровень: урон +25%, перезарядка −15%
	var card = CardFactory.thunderfire_cannon()
	var in_pool = CardFactory.build_pool().filter(func(c): return c.id == "thunderfire_cannon").size()
	var s1 = card.get_building_stats()
	card.level_up_building()
	var s2 = card.get_building_stats()
	_check("карта: Rare 8 Req, 1 копия в пуле; ур.2 — урон ×1.25, перезарядка ×0.85",
		card.rarity == "rare" and card.cost == 8 and in_pool == 1
		and _near(s2["damage"], s1["damage"] * 1.25) and _near(s2["cooldown"], s1["cooldown"] * 0.85))

	# 2. Расстановка: клик по полю не стреляет
	var scene = await _scene("")
	var cannon = _cannon()
	var enemies = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(1)
	var target_pos: Vector2 = enemies[0].global_position
	_click(scene, target_pos)
	await process_frame
	_check("расстановка: орудие на поле, клик не стреляет, надписи орудия нет", cannon != null and cannon.is_artillery_ready()
		and root.get_node("BattleManager").projectiles.is_empty() and not scene.hud._artillery.visible)

	# 3. Бой: клик — залп, сразу второй — нет (перезарядка), надпись в шапке
	scene._on_start_pressed()
	await process_frame
	# Свой боец рядом с точкой взрыва — дружественного огня нет
	var mine = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(0)[0]
	var hp_before = {}
	for e in root.get_node("SoldierRegistry").get_alive_soldiers_of_team(1):
		hp_before[e] = e.current_hp
		e.apply_stun(100.0)   # враги не бьют своего бойца в их строю — урон только от взрыва
	target_pos = enemies[0].global_position
	mine.global_position = target_pos + Vector2(10, 0)
	var mine_hp = mine.current_hp
	var blocks = scene.inspector.click_blocker.call()
	_click(scene, target_pos)
	var fired = not cannon.is_artillery_ready() and root.get_node("BattleManager").projectiles.size() >= 1
	var second = scene.fire_artillery(target_pos)
	await process_frame
	_check("бой: клик — залп (справка клик не берёт), сразу второй — нет; в шапке «%s»" % scene.hud._artillery.text,
		fired and not second and scene.hud._artillery.visible and "с" in scene.hud._artillery.text
		and blocks and not scene.inspector.click_blocker.call())

	# 4. Взрыв при попадании: враги в радиусе ранены, свой боец — нет
	var shot = root.get_node("BattleManager").projectiles.filter(func(p): return p.splash_radius > 0.0)
	var frames = 0
	while not shot.is_empty() and is_instance_valid(shot[0]) and not shot[0].finished and frames < 600:
		await process_frame
		frames += 1
	var hit = 0
	for e in hp_before:
		if is_instance_valid(e) and e.current_hp < hp_before[e] - 1.0:
			hit += 1
	_check("взрыв: ранено врагов — %d, свой боец рядом цел" % hit, hit >= 1 and mine.current_hp >= mine_hp - EPS)

	# 5. Перезарядка cooldown — за тик до неё не готово, по ней — готово
	var ticks = roundi(cannon.stats["cooldown"] / 0.1)
	cannon.cooldown_left = cannon.stats["cooldown"]
	for i in range(ticks - 1):
		cannon.tick(0.1)
	var early = cannon.is_artillery_ready()
	cannon.tick(0.1)
	_check("через %.0f с орудие снова готово, раньше — нет" % cannon.stats["cooldown"], not early and cannon.is_artillery_ready())
	var dmg = cannon.stats["damage"]
	root.get_node("BattleManager").stop_battle()
	scene.queue_free()
	await process_frame

	# 6. Imperial Fists: урон орудия ×1.2
	scene = await _scene("imperial_fists")
	_check("Imperial Fists: урон орудия ×1.2 (%.0f → %.0f)" % [dmg, _cannon().stats["damage"]],
		_near(_cannon().stats["damage"], dmg * 1.2))
	scene.queue_free()
	await process_frame
	quit()
