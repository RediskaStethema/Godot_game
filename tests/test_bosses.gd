extends SceneTree

# Финальные боссы — примархи (решение пользователя 09.11.2026): у каждого из 9 свой приём (UnitData.special_*).
# Каждый босс ставится против отряда тактиков (стрелки — в стороне, для прыжка), бойцы тикаются вручную (FIXED_TICK)
# на расстановке — бой не идёт. Проверки:
# 1) приём срабатывает (ряд special листа), пока он идёт — оглушение и отброс не действуют, FSM стоит;
# 2) на кадре срабатывания — урон задетым, статус / оглушение / щит по виду; прыжок и рывок — босс сдвинулся;
# 3) после приёма — снова бой, следующий — через special_cooldown;
# 4) появление (ряд appear) — у кого он есть, по окончании стойка; справка отряда называет приём.
#   godot --headless --path . -s tests/test_bosses.gd
const TICK: float = 0.1

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _alive(team: int) -> Array:
	return root.get_node("SoldierRegistry").get_alive_soldiers_of_team(team)

func _spawn(scene, id: String, team: int, tile: Vector2i, count: int, at: Vector2) -> Array:
	var old = _alive(team).duplicate()
	scene._spawn_squad(UnitFactory.create(id), team, tile, count)
	var list = _alive(team).filter(func(s): return not s in old)
	list[0].parent_squad.global_position = at
	for s in list:
		s.max_hp = 5000.0   # цели не гибнут — урон видно по HP
		s.current_hp = 5000.0
	return list

func _clear() -> void:
	for s in _alive(0) + _alive(1):
		s.parent_squad.queue_free()
	root.get_node("SoldierRegistry").clear()
	root.get_node("SquadRegistry").clear()

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(3)
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	bm.player_units = [] as Array[UnitData]
	bm.player_placements = {}
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	_clear()
	await process_frame

	var ids: Array = EnemyWaves.BOSS["units"] + EnemyWaves.SM_BOSS["units"]
	var all_fired := true
	var all_effect := true
	var all_locked := true
	var all_resume := true
	var report: Array[String] = []
	for id in ids:
		var base := Vector2(0, 3000 + ids.find(id) * 600)
		var boss = _spawn(scene, id, 1, Vector2i(0, 0), 1, base)[0]
		var d: UnitData = boss.data
		# цель: ближний бой — вплотную; прыжок / рывок / снаряд — на дальности приёма, стрелки — для прыжка
		var near: bool = d.special_kind in ["cone", "nova", "shield"]
		var dist: float = d.special_radius * 0.5 if near else minf(d.special_range * 0.8, 200.0)
		var foes = _spawn(scene, "tactical_marine", 0, Vector2i(0, 1), 6, base + Vector2(-dist, 0))
		boss.target = foes[0]
		boss.transition_to(boss.State.ATTACK if near else boss.State.CHASE)
		var hp0 := {}
		for f in foes:
			hp0[f] = f.current_hp
		var start: Vector2 = boss.global_position
		var waited := 0
		while not boss.is_using_special() and waited < 60:
			boss.tick(TICK)
			waited += 1
		var fired: bool = boss.is_using_special() and boss.sprite.animation == &"special"
		# пока идёт приём — контроль не действует
		boss.apply_stun(2.0)
		boss.apply_knockback(Vector2.RIGHT, 300.0)
		var locked: bool = boss.current_state != boss.State.STUNNED and boss.current_state != boss.State.KNOCKBACK
		var shield0: float = boss.shield
		var spent := 0
		while boss.is_using_special() and spent < 40:
			boss.tick(TICK)
			spent += 1
		# снаряд Магнуса долетает — тикаем снаряды
		for i in 30:
			for p in bm.projectiles.duplicate():
				p.tick(TICK)
			bm.projectiles = bm.projectiles.filter(func(p): return is_instance_valid(p) and not p.finished)
		var hurt := 0
		var marked := 0
		var stunned := 0
		for f in foes:
			if f.current_hp < hp0[f]:
				hurt += 1
			if d.special_status != "" and f.get_status_stacks(d.special_status) > 0:
				marked += 1
			if f.current_state == f.State.STUNNED:
				stunned += 1
		var effect: bool = hurt > 0 and (d.special_status == "" or marked > 0) \
			and (d.special_stun <= 0.0 or stunned > 0) and (d.special_shield <= 0.0 or boss.shield > shield0) \
			and (not d.special_kind in ["leap", "dash"] or boss.global_position.distance_to(start) > 40.0)
		var resumed: bool = not boss.is_using_special() and boss._special_cd > d.special_cooldown - 2.0 \
			and boss.current_state in [boss.State.ATTACK, boss.State.CHASE, boss.State.MOVE]
		report.append("%s %s: %.1f с до приёма, задето %d, статус %d, оглушено %d" % [id, d.special_kind,
			waited * TICK, hurt, marked, stunned])
		all_fired = all_fired and fired
		all_effect = all_effect and effect
		all_locked = all_locked and locked
		all_resume = all_resume and resumed
		_clear()
		await process_frame
	for line in report:
		print("  ", line)
	_check("приём срабатывает у всех 9 (ряд special)", all_fired)
	_check("пока идёт приём — оглушение и отброс не действуют", all_locked)
	_check("на кадре срабатывания — урон, статус / оглушение / щит, прыжок и рывок сдвигают босса", all_effect)
	_check("после приёма — снова бой, перезарядка special_cooldown", all_resume)

	# Конус (решение пользователя 09.11.2026: метка и удар расходились): ось — на начале замаха; цель ушла вбок
	# за время замаха — удар туда, куда показала метка: стоящий в метке задет, ушедший — нет; метка — по той же оси
	var mort = _spawn(scene, "daemon_mortarion", 1, Vector2i(0, 0), 1, Vector2(0, 8000))[0]
	var r: float = mort.data.special_radius
	var runner = _spawn(scene, "tactical_marine", 0, Vector2i(0, 1), 1, Vector2(-r * 0.5, 8000))[0]
	var stayer = _spawn(scene, "tactical_marine", 0, Vector2i(1, 1), 1, Vector2(-r * 0.7, 8000))[0]
	mort.target = runner
	mort.transition_to(mort.State.ATTACK)
	var w := 0
	while not mort.is_using_special() and w < 60:
		mort.tick(TICK)
		w += 1
	var tg = mort.get("_telegraph")
	var tg_dir: Vector2 = (tg.to_point - tg.from_point).normalized() if is_instance_valid(tg) else Vector2.ZERO
	var aim0: Vector2 = mort.get("_special_aim")
	var hp_run: float = runner.current_hp     # с начала замаха: до него босс бил бегущего обычными ударами
	var hp_stay: float = stayer.current_hp
	runner.parent_squad.global_position = mort.global_position + Vector2(0, r * 0.6)   # ушёл вбок, вне конуса
	var sp := 0
	while mort.is_using_special() and sp < 40:
		mort.tick(TICK)
		sp += 1
	_check("конус: метка и удар по одной оси (метка %.2f°), цель ушла вбок — не задета, стоявший в метке — задет" \
		% rad_to_deg(tg_dir.angle_to(aim0)),
		w < 60 and tg_dir.dot(aim0) > 0.999 and runner.current_hp == hp_run and stayer.current_hp < hp_stay)
	_clear()
	await process_frame

	# Появление и справка
	var dorn = _spawn(scene, "primarch_dorn", 1, Vector2i(0, 0), 1, Vector2(0, 9000))[0]
	var vulkan = _spawn(scene, "primarch_vulkan", 1, Vector2i(1, 0), 1, Vector2(0, 9600))[0]
	var appeared: bool = dorn.play_appear() and dorn.sprite.animation == &"appear" and not vulkan.play_appear()
	dorn.sprite.animation_finished.emit()
	var text: String = load("res://scenes/battle/ui/SquadInspector.gd").ability_text(dorn.data)
	_check("появление: у Дорна ряд appear, потом стойка; у Вулкана ряда нет; справка «%s»" % text,
		appeared and dorn.sprite.animation == &"idle" and "Несокрушимая стена" in text)
	# Рост на экране — по фигуре стойки, а не по холсту: ~2.5 роста бойца
	var fig: float = dorn.sprite.sprite_frames.get_meta("figure_height")
	var on_screen: float = fig * dorn.sprite.scale.y
	_check("рост примарха на экране %.0f px (≈ 2.5 × %.0f)" % [on_screen, dorn.TARGET_SPRITE_HEIGHT],
		absf(on_screen - dorn.TARGET_SPRITE_HEIGHT * UnitFactory.PRIMARCH_SCALE) < 2.0)
	_clear()
	await process_frame

	# Подача кодом (BossFx, 09.11.2026): тень и кольцо после показа, метка зоны на время замаха, после удара —
	# ударная волна и трещины, которые гаснут; шаг трясёт камеру не чаще BOSS_STEP_GAP_MS
	var layer: Node = load("res://scripts/battle/AuraRing.gd").layer
	# На слое не только BossFx: у других эффектов "kind" — строка, сравнивать с числом нельзя
	var fx_kind := func(n) -> int:
		var k = n.get("kind")
		return k if typeof(k) == TYPE_INT else -1
	var fx_of := func(k: int) -> int:
		return layer.get_children().filter(func(n): return fx_kind.call(n) == k and not n.is_queued_for_deletion()).size()
	var angron = _spawn(scene, "daemon_angron", 1, Vector2i(0, 0), 1, Vector2(0, 12000))[0]
	var prey = _spawn(scene, "tactical_marine", 0, Vector2i(0, 1), 3, Vector2(-160, 12000))
	var no_ground_hidden: bool = not is_instance_valid(angron._ground)
	angron.reveal_boss()
	var ground_ok: bool = is_instance_valid(angron._ground) and angron._ground.get_parent() == layer
	angron.target = prey[0]
	angron.transition_to(angron.State.CHASE)
	var n := 0
	while not angron.is_using_special() and n < 60:
		angron.tick(TICK)
		n += 1
	var marked: bool = is_instance_valid(angron._telegraph) and angron._telegraph.get_parent() == layer
	var waves0: int = fx_of.call(2)
	var cracks0: int = fx_of.call(3)
	while angron.is_using_special() and n < 120:
		angron.tick(TICK)
		n += 1
	var after_hit: bool = angron._telegraph == null and fx_of.call(2) > waves0 and fx_of.call(3) > cracks0
	for node in layer.get_children():   # время вперёд: волна и трещины догорают
		if fx_kind.call(node) in [2, 3]:
			node._process(5.0)
	var faded: bool = fx_of.call(2) == 0 and fx_of.call(3) == 0
	_check("BossFx: тень и кольцо только после показа, метка зоны в замахе, после удара волна и трещины, гаснут",
		no_ground_hidden and ground_ok and marked and after_hit and faded)
	var c1: int = fx_of.call(3)
	angron._step_shake_at = -100000
	load("res://scripts/battle/BossSpecial.gd").step(angron)
	load("res://scripts/battle/BossSpecial.gd").step(angron)   # сразу второй шаг — без тряски и трещин
	_check("шаг босса: трещина и тряска не чаще %d мс" % angron.BOSS_STEP_GAP_MS, fx_of.call(3) == c1 + 1)

	# Ярость: впервые ≤ 50% HP — один раз, приём скоро, перезарядка × ENRAGE_COOLDOWN_MULT, кольцо пульсирует,
	# тело тлеет (бит усиления в маске шейдера)
	angron.max_hp = 1000.0
	angron.current_hp = 1000.0
	angron._special_cd = 6.0
	angron.take_damage(400.0)
	var calm: bool = not angron.enraged
	angron.take_damage(150.0)
	var raged: bool = angron.enraged and angron._special_cd <= angron.ENRAGE_FIRST + 0.001 and angron._ground.enraged \
		and angron._status_mask != 0
	angron.take_damage(10.0)   # повторно не срабатывает: перезарядку не сбрасывает
	angron._special_cd = 3.0
	angron.take_damage(10.0)
	var once: bool = is_equal_approx(angron._special_cd, 3.0)
	angron.target = prey[0]
	angron.transition_to(angron.State.CHASE)
	angron._special_cd = 0.0
	n = 0
	while not angron.is_using_special() and n < 20:
		angron.tick(TICK)
		n += 1
	var cd_ok: bool = absf(angron._special_cd - angron.data.special_cooldown * angron.ENRAGE_COOLDOWN_MULT) < 0.01
	_check("ярость на 50%%: один раз, приём скоро, перезарядка ×%.2f, кольцо и тело" % angron.ENRAGE_COOLDOWN_MULT,
		calm and raged and once and cd_ok)

	# Смерть: замедление мира, итог боя ждёт конца мига, затем обрабатывается
	scene.hitstop_enabled = true
	var speed0: float = Engine.time_scale
	angron._special_left = 0.0
	angron.take_damage(100000.0)
	var slowed: bool = scene.is_boss_falling() and Engine.time_scale < speed0 * 0.5
	scene._on_battle_ended(0)
	var waited_end: bool = not scene.get("_battle_resolved") and scene.get("_deferred_winner") == 0
	scene._end_boss_fall()
	scene._end_finale_slowmo()   # итог боя сам включил финальное замедление — снимаем, чтобы сравнить скорость
	print("  смерть: замедлен %s, итог ждал %s, обработан %s, скорость ×%.2f" % [slowed, waited_end,
		scene.get("_battle_resolved"), Engine.time_scale / speed0 if speed0 > 0 else 0.0])
	_check("смерть босса: мир замедлен, итог боя после мига, скорость вернулась",
		slowed and waited_end and scene.get("_battle_resolved") and is_equal_approx(Engine.time_scale, speed0))

	# Вид смерти (решение пользователя 09.11.2026, «умирают инородно от текстур»): вспышка удара снята сразу,
	# павший не загорается от света, лужа — в мире, не ребёнком за спрайтом; тело после ряда лежит, а не пропадает
	var mort2 = _spawn(scene, "daemon_mortarion", 1, Vector2i(0, 0), 1, Vector2(0, 12000))[0]
	mort2.take_damage(100000.0, true, true)
	var no_flash: bool = mort2.get("_flash_left") <= 0.0 and mort2.sprite.material == mort2.get("_base_material")
	mort2.add_flash_light(Color(1, 1, 1), 1.0)
	var unlit: bool = mort2.get("_flash_light_left") <= 0.0
	var pool_child := false
	for c in mort2.get_children():
		pool_child = pool_child or (c != mort2.sprite and c is AnimatedSprite2D)
	mort2.sprite.animation_finished.emit()
	await process_frame
	var corpse: bool = is_instance_valid(mort2) and mort2.is_inside_tree()
	for i in 30:   # дольше прежних 0.3 с до пропажи
		await process_frame
	corpse = corpse and is_instance_valid(mort2)
	_check("вид смерти: вспышка снята, свет не белит павшего, лужа не за спрайтом, тело лежит после ряда",
		no_flash and unlit and not pool_child and corpse)

	# Сдача в миг смерти примарха (ревью 09.11.2026): итог не откладывается — иначе уход в меню стирал его,
	# забег не заканчивался и «Продолжить» возвращало в бой
	scene.set("_battle_resolved", false)
	scene.set("_boss_fall_base", Engine.time_scale)
	Engine.time_scale = Engine.time_scale * scene.BOSS_FALL_SLOWMO
	bm.surrendered = true
	scene._on_battle_ended(1)
	_check("сдача во время смерти босса: итог сразу, замедление снято",
		scene.get("_battle_resolved") and scene.get("_boss_fall_base") <= 0.0 and scene.get("_deferred_winner") == -2)
	bm.surrendered = false
	quit()
