extends SceneTree

# Визуал кодом (решение пользователя 08.11.2026, только вид): статусы на теле (шейдер бойца), отдача от удара,
# стоп-кадр и возврат скорости, пыль под лимитом, вспышка света на бойце гаснет, луч лечения появляется и гаснет,
# след у снаряда, блик карты руки, шторка смены сцены, отматывающийся счётчик Req.
# Классы сцен и бойцов по имени не упоминаются (скрипт компилируется до автолоадов).
#   godot --headless --path . -s tests/test_visual_fx.gd

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _wait(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout

func _of_class(node: Node, cls: String) -> Array:
	var out: Array = []
	for c in node.find_children("*", "", true, false):
		var s = c.get_script()
		if s and s.get_global_name() == cls:
			out.append(c)
	return out

# Параметр шейдера бойца (не задан в материале — значение по умолчанию 0)
func _param(s, key: String) -> float:
	var v = s.sprite.material.get_shader_parameter(key)
	return 0.0 if v == null else float(v)

func _squad_with(d: UnitData, n: int) -> UnitData:
	d.squad_size = n
	var hp: Array[float] = []
	for i in n:
		hp.append(1.0)
	d.saved_hp = hp
	return d

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	var squads_reg = root.get_node("SquadRegistry")
	root.get_node("GameSettings").atmosphere = true
	bm.reset_run()
	rm.new_run(3)
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	bm.player_units = [_squad_with(UnitFactory.create("tactical_marine"), 6),
		_squad_with(UnitFactory.create("apothecary"), 2)] as Array[UnitData]
	bm.pending_cards.clear()
	bm.pending_cards.append(CardFactory.create("tactical_squad"))
	rm._go("res://scenes/battle/BattleScene.tscn")
	# шторка смены сцены: сразу — чёрная
	var fade_a: float = rm._fade_rect.modulate.a if rm._fade_rect else -1.0
	await _frames(4)
	var scene = current_scene
	_check("смена сцены — шторка поверх (%.2f)" % fade_a, fade_a == 1.0 and rm._fade.is_inside_tree())
	await _wait(rm.FADE_TIME + 0.1)
	_check("шторка сошла (%.2f)" % rm._fade_rect.modulate.a, rm._fade_rect.modulate.a <= 0.01)

	var mine: Array = squads_reg.get_alive_squads_of_team(0)
	var tac = mine.filter(func(s): return s.data.factory_id == "tactical_marine")[0]
	var apo = mine.filter(func(s): return s.data.factory_id == "apothecary")[0]
	var s0 = tac.soldiers[0]

	# 1. статусы на теле
	s0.apply_status(StatusEffects.POISONED, 2.0, 3.0)
	var poison_on := _param(s0, "st_poison")
	s0.apply_status(StatusEffects.EMPOWERED, 0.2, 3.0)
	var emp_on := _param(s0, "st_emp")
	# листы статусов на теле (09.11.2026, вместо значков над головой): стилизованный лист, точка — у ног
	var vfx_cls = load("res://scripts/battle/Vfx.gd")
	var sheets_ok := true
	for kind in ["burning", "poisoned", "slowed", "empowered"]:
		var e: Dictionary = vfx_cls.EFFECTS[kind]
		sheets_ok = sheets_ok and e["sheet"].begins_with(vfx_cls.STATUS_DIR) and e["pivot"].y > e["size"].y * 0.7 \
			and vfx_cls.graded_path(e["sheet"]).begins_with(vfx_cls.GRADED_DIR)
	var on_body: Array = _of_class(s0, "Vfx").filter(func(v): return v.sprite_frames == vfx_cls._get_frames("poisoned"))
	_check("статусы — листы на теле (стилизованы, у ног), яд на бойце: %d" % on_body.size(), sheets_ok and on_body.size() == 1)
	s0.status_effects.clear()
	s0._sync_status_vfx()
	var off := _param(s0, "st_poison")
	_check("статусы на теле: яд %.0f, усиление %.0f, сняты — %.0f" % [poison_on, emp_on, off],
		poison_on == 1.0 and emp_on == 1.0 and off == 0.0)

	# 2. отдача от удара
	s0.take_damage(1.0)
	s0._tick_recoil(0.02)   # кадр headless длиннее отдачи — шаг вручную
	var squashed: bool = s0.sprite.scale.y < s0._sprite_k and s0.sprite.position.x != 0.0
	await _wait(0.2)
	_check("отдача: сжался и отскочил, вернулся (%.3f / %.3f, x %.2f)" % [s0.sprite.scale.y, s0._sprite_k, s0.sprite.position.x],
		squashed and is_equal_approx(s0.sprite.scale.y, s0._sprite_k) and is_zero_approx(s0.sprite.position.x))

	# 3. вспышка света
	var before: Color = s0.sprite.self_modulate
	load("res://scripts/battle/IsoGridRenderer.gd").flash_light(s0.global_position, Color(Palette.FIRE, 1.0), 60.0, 0.15)
	var lit: Color = s0.sprite.self_modulate
	await _wait(0.4)
	var after: Color = s0.sprite.self_modulate
	_check("вспышка света: боец ярче (%.2f → %.2f) и гаснет (%.2f)" % [before.r, lit.r, after.r],
		lit.r > before.r + 0.1 and absf(after.r - before.r) < 0.02)

	# 4. пыль под лимитом
	var dust_cls = load("res://scripts/battle/DustLayer.gd")
	for i in 400:
		dust_cls.puff(s0.global_position, 4.0)
		if i % 10 == 9:
			await process_frame
	var dust = dust_cls.layer
	_check("пыль: слой есть, клубов %d ≤ %d" % [dust._puffs.size() if dust else -1, dust_cls.MAX_ALIVE],
		dust != null and dust._puffs.size() > 0 and dust._puffs.size() <= dust_cls.MAX_ALIVE)

	# 5. луч лечения
	var healer = apo.soldiers[0]
	s0.current_hp = s0.max_hp * 0.4
	healer.current_state = healer.State.MOVE
	healer.sprite.play("idle")   # стоит — играет ряд heal и поворачивается к раненому
	healer._tick_support(0.1)
	var beam = healer.heal_beam
	await _frames(3)
	var shown: bool = beam != null and beam.patient == s0 and beam._alpha > 0.0
	# Луч — из нартециума (metadata/heal_origin), со стороны раненого, не из груди (решение пользователя 11.11.2026)
	var origin: Vector2 = healer.heal_point()
	var chest: Vector2 = healer.global_position + Vector2(0.0, -31.0 * 0.45 * healer.data.sprite_scale)
	var to_patient: float = signf(s0.global_position.x - healer.global_position.x)
	var from_tool: bool = healer.sprite.animation == "heal" and origin.distance_to(chest) > 2.0 \
		and signf(origin.x - healer.global_position.x) == to_patient
	healer.stand_down()
	await _wait(0.35)
	_check("луч лечения к раненому появился и погас; из нартециума со стороны раненого (%s)" % from_tool,
		shown and beam._alpha <= 0.0 and from_tool)

	# 6. блик карты руки
	_check("карта руки — наклон и блик", _of_class(scene.bench, "CardGlare").size() == 1)
	# подсветка редкости в руке — только под курсором (курсор не на карте — не горит)
	var bench_card = CardFactory.create("librarian")
	bm.pending_cards.append(bench_card)
	scene.bench.setup(bm.pending_cards)
	await _frames(3)
	var glows: Array = scene.bench.find_children("RarityGlow", "", true, false)
	var idle_level: float = 1.0
	if not glows.is_empty():
		idle_level = float(glows[0].material.get_shader_parameter("level"))
	_check("рука: подсветка редкости без наведения не горит (%d шт., сила %.2f)" % [glows.size(), idle_level],
		not glows.is_empty() and idle_level == 0.0)

	# 7. бой: след снаряда, стоп-кадр
	scene._on_start_pressed(false)
	# выход врагов (09.11.2026): отряд проявляется (прозрачный в начале), у Хаоса — разлом варпа; знаки бонусов
	var foes_in: Array = squads_reg.get_alive_squads_of_team(1)
	var faded: bool = foes_in.all(func(sq): return sq.modulate.a < 1.0)
	var rifts: int = _of_class(scene, "BuildingFx").filter(func(n): return n.kind == "rift").size()
	var marks: int = _of_class(scene, "BuildingFx").filter(func(n): return n.kind == "bonus").size()
	_check("выход врагов: %d отрядов проявляются, разломов %d; знаков бонусов над своими %d" % [foes_in.size(), rifts, marks],
		faded and rifts == foes_in.size() and marks >= 1)
	await _frames(2)
	var shot = load("res://scripts/battle/Projectile.gd").launch(scene.units_container, "bolt", s0.global_position, null, s0.global_position + Vector2(200, 0))
	shot.visible = true
	await _frames(2)
	var trail_layer = load("res://scripts/battle/ProjectileTrail.gd").layer
	_check("у болта — трассер", trail_layer != null and trail_layer.has_trail(shot))
	scene.hitstop_enabled = true
	var base := Engine.time_scale
	scene.hitstop()
	var slowed := Engine.time_scale
	await _wait(0.15)
	_check("стоп-кадр: ×%.2f → скорость вернулась (%.2f)" % [slowed / base, Engine.time_scale],
		slowed < base * 0.1 and is_equal_approx(Engine.time_scale, base))

	# 7б. эффекты кодом 09.11.2026 (решение пользователя: что лучше кодом — кодом)
	var fx_of := func(kind: String) -> int:
		return _of_class(scene, "BuildingFx").filter(func(n): return n.kind == kind and not n.is_queued_for_deletion()).size()
	# телепорт Deep Strike — лист художника: у каждого бойца уход (задом наперёд) и высадка (вперёд), стилизован
	var term = scene._spawn_squad(_squad_with(UnitFactory.create("terminator"), 6), 0, Vector2i(0, 2), 6)
	term.global_position = Vector2(-1500, 0)
	var vfx_tele = load("res://scripts/battle/Vfx.gd")
	var tele_frames = vfx_tele._get_frames("teleport")
	var tele0: Array = _of_class(scene, "Vfx").filter(func(v): return v.sprite_frames == tele_frames)
	term._tick_deep_strike(10.0)
	var tele: Array = _of_class(scene, "Vfx").filter(func(v): return v.sprite_frames == tele_frames and not v in tele0)
	var tele_back: int = tele.filter(func(v): return v._reverse).size()
	var graded_tele: bool = vfx_tele.graded_path(vfx_tele.EFFECTS["teleport"]["sheet"]).begins_with(vfx_tele.GRADED_DIR)
	_check("телепорт Deep Strike: лист у %d бойцов, уход задом наперёд %d, высадка %d, стилизован" % [term.soldiers.size(),
		tele_back, tele.size() - tele_back], term.deep_struck and tele_back == term.soldiers.size()
		and tele.size() == term.soldiers.size() * 2 and graded_tele)
	# благословение: знак бога под каждым бойцом отряда
	var zerk = scene._spawn_squad(_squad_with(UnitFactory.create("khorne_berzerkers"), 4), 0, Vector2i(1, 2), 4)
	var sig0: int = fx_of.call("sigil")
	scene._bless_sigils(zerk)
	_check("благословение: знак бога под %d бойцами" % (fx_of.call("sigil") - sig0),
		fx_of.call("sigil") - sig0 == zerk.soldiers.size())
	# падение отряда (обе стороны) и шрамы поля: кровь павших, подпалина разрыва
	var scars = load("res://scripts/battle/ScarLayer.gd").layer
	var scars0: int = scars.count() if scars else -1
	var foes: Array = squads_reg.get_alive_squads_of_team(1)
	var fall0: int = fx_of.call("fall")
	var foe_sq = foes[0]
	for e in foe_sq.soldiers.duplicate():
		e.take_damage(1.0e6)
	await _frames(2)
	_check("отряд врага пал: кольцо по земле (%d), пятна крови (%d → %d)" % [fx_of.call("fall") - fall0, scars0,
		scars.count() if scars else -1], fx_of.call("fall") > fall0 and scars != null and scars.count() > scars0)
	# порабощение: розовая цепь
	foes = squads_reg.get_alive_squads_of_team(1)
	if not foes.is_empty():
		var ch0: int = fx_of.call("charm")
		foes[0].soldiers[0].charm(tac)
		_check("порабощение: цепь к бойцу", fx_of.call("charm") == ch0 + 1)
	else:
		_check("порабощение: цепь к бойцу (нет врага для проверки)", false)
	# шрамы не копятся сверх MAX_SCARS; без «Атмосферы» — не добавляются
	for i in 40:
		for j in 6:
			scars.scorch(Vector2(i * 8.0, j * 8.0), 6.0)
		await process_frame
	var capped: int = scars.count()
	root.get_node("GameSettings").atmosphere = false
	scars.scorch(Vector2.ZERO, 6.0)
	var off_same: bool = scars.count() == capped
	root.get_node("GameSettings").atmosphere = true
	# старые уходят пачкой TRIM (пересборка массивов — раз на пачку): живых от MAX_SCARS до MAX_SCARS + TRIM
	_check("шрамы: не больше %d + %d (%d), без «Атмосферы» — не добавляются" % [scars.MAX_SCARS, scars.TRIM, capped],
		capped >= scars.MAX_SCARS and capped <= scars.MAX_SCARS + scars.TRIM and off_same)
	# тени от костров: боец у огня — тень есть, отошёл — её нет
	var fires: Array = load("res://scripts/battle/IsoGridRenderer.gd").fire_sources()
	var shadows = _of_class(scene, "SoldierShadows")[0]
	if fires.is_empty():
		_check("тени от костров: на поле нет огня", false)
	else:
		for sq in squads_reg.get_alive_squads_of_team(0) + squads_reg.get_alive_squads_of_team(1):
			for x in sq.soldiers:
				x.teleport_to(Vector2(-5000, -5000))
		s0.teleport_to(fires[0][0] + Vector2(25.0, 6.0))
		await _frames(2)
		var near: int = shadows.fire_shadow_count()
		s0.teleport_to(fires[0][0] + Vector2(900.0, 0.0))
		await _frames(2)
		var far: int = shadows.fire_shadow_count()
		_check("тени от костров: у огня %d, далеко %d" % [near, far], near >= 1 and far == 0)
	# свет по рамке окна подкрепления
	var picker = load("res://scenes/shop/CatchUpPicker.gd").new()
	root.add_child(picker)
	picker.setup()
	var glow_ok: bool = picker.find_child("RarityGlow", true, false) != null
	picker.queue_free()
	_check("подкрепление: свет по рамке окна", glow_ok)

	# щит бойца кончился — лопается; элитный враг пал — монеты летят к счётчику (09.11.2026, монеты — 12.11.2026)
	var shielded = squads_reg.get_alive_squads_of_team(0)[0].soldiers[0]
	shielded.shield = 5.0
	var sb0: int = _of_class(scene, "BuildingFx").filter(func(n): return n.kind == "shield").size()
	shielded.take_damage(10.0)
	var sb1: int = _of_class(scene, "BuildingFx").filter(func(n): return n.kind == "shield").size()
	var coins0: int = _of_class(scene, "CoinFlight").size()
	scene.elite_killed(Vector2.ZERO)
	var coins1: int = _of_class(scene, "CoinFlight").size()
	var bonus: int = root.get_node("EconomyManager").BONUS_ELITE_KILL
	_check("щит лопнул (%d), элита — монет к счётчику %d (бонус %d)" % [sb1 - sb0, coins1 - coins0, bonus],
		sb1 == sb0 + 1 and coins1 - coins0 == bonus)

	# 8. счётчик монет отматывается (число без «Req» — решение пользователя 12.11.2026)
	var hud = scene.hud
	var label: Label = hud._requisition
	var econ = root.get_node("EconomyManager")
	econ.add_requisition(20)
	await _frames(2)
	var mid := label.text
	await _wait(0.6)   # UITheme.ROLL_TIME 0.45 (UITheme по имени — до автолоадов не компилируется)
	_check("счётчик монет бежит («%s») и встаёт на %d («%s»)" % [mid, econ.requisition, label.text],
		mid != str(econ.requisition) and label.text == str(econ.requisition))
	bm.stop_battle()

	# 9. меню: окна кораблей горят ярче только пока курсор на кнопке (решение пользователя 16.11.2026)
	change_scene_to_file("res://scenes/menu/MainMenu.tscn")
	await _frames(5)
	var arts: Array = current_scene.find_children("*", "", true, false).filter(func(n): return n.has_method("set_menu_hover"))
	if arts.is_empty():
		_check("меню: живая сцена с кораблями", false)
	else:
		var art = arts[0]
		await _wait(0.6)
		var idle_glow: float = art._hover
		var idle_visible: bool = art._capital_glow != null and art._capital_glow.visible
		art.set_menu_hover(true)
		current_scene.set_process(false)   # иначе меню само снимет наведение — курсора над кнопкой нет
		# MainMenu зовёт set_menu_hover каждый кадр; свет держится HOVER_HOLD после ухода курсора (зазоры между кнопками)
		for i in 48:
			art.set_menu_hover(true)
			await process_frame
		await _wait(0.1)
		var look_glow: float = art._hover
		var look_visible: bool = art._capital_glow != null and art._capital_glow.visible 			and art._capital_glow.self_modulate.r > 0.9
		var ship_half: bool = not art._ships.is_empty() and art._ships[0]["half"] != null and art._ships[0]["half"].visible
		art.set_menu_hover(false)
		await _wait(0.8)
		_check("меню: окна кораблей в покое не горят ярче (%.1f), с курсором — ярче (%.1f, флагман %s, малый %s), ушёл — снова гаснут (%.1f)" % [
			idle_glow, look_glow, look_visible, ship_half, art._hover],
			idle_glow == 0.0 and not idle_visible and look_glow == 1.0 and look_visible and ship_half and art._hover == 0.0)
		# ни одна кнопка не подсвечена без курсора
		_check("меню: кнопка в фокусе без курсора — %s" % [root.get_viewport().gui_get_focus_owner()],
			root.get_viewport().gui_get_focus_owner() == null)
		# взлёт в забег (MenuLaunch; headless — сразу) → магазин поверх поля (BattleScene); флаг посадки снимает
		# первое поле — уже под магазином
		current_scene._start_new_run("space_marines", "ultramarines", 2)
		await _frames(4)
		var in_shop: bool = current_scene.scene_file_path.ends_with("BattleScene.tscn") and current_scene.get("shop") != null
		_check("взлёт → магазин поверх поля, флаг посадки снят первым полем (%s, %s)" % [in_shop, rm.landing_pending],
			in_shop and not rm.landing_pending)
	quit()
