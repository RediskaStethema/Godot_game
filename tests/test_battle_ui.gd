extends SceneTree

# Вид боя и интерфейс (решения пользователя 16.10.2026):
# 1) полоска HP отряда (SquadBar): доля HP от полного состава, число бойцов, скрыта у скрытых врагов;
#    туман темы приглушён;
# 2) всплывающие цифры: крупный удар в схватке — да, мелкий / яд / расстановка — нет; свой отряд пал — надпись;
# 3) итог боя: урон отрядов в итогах (лучший отряд), баннер «ПОБЕДА», миг замедления и возврат скорости;
# 4) камера: зум к курсору в пределах, тянуть — в пределах поля; скорость ×3; пауза пробелом в схватке;
# 5) магазин: лента 15 волн (мини-боссы, босс, ближайшая волна), сноска синергии на карте.
# Классы сцен по имени не упоминаются (скрипт компилируется до автолоадов).
#   godot --headless --path . -s tests/test_battle_ui.gd

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _of_class(node: Node, cls: String) -> Array:
	var out: Array = []
	for c in node.find_children("*", "", true, false):
		var s = c.get_script()
		if s and s.get_global_name() == cls:
			out.append(c)
	return out

func _squad_with(d: UnitData, n: int) -> UnitData:
	d.squad_size = n
	var hp: Array[float] = []
	for i in n:
		hp.append(1.0)
	d.saved_hp = hp
	return d

func _battle_scene(units: Array[UnitData]) -> Node:
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(3)
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	bm.player_units = units
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(3)
	return current_scene

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var reg = root.get_node("SoldierRegistry")
	var squads_reg = root.get_node("SquadRegistry")

	# 1. Полоска отряда
	var units: Array[UnitData] = [_squad_with(UnitFactory.create("tactical_marine"), 6),
		_squad_with(UnitFactory.create("dreadnought"), 2)]
	var scene = await _battle_scene(units)
	var mine = squads_reg.get_alive_squads_of_team(0)
	var enemy = squads_reg.get_alive_squads_of_team(1)
	var bars_ok = true
	for sq in mine + enemy:
		bars_ok = bars_ok and _of_class(sq, "SquadBar").size() == 1
	var tac = mine.filter(func(s): return s.data.factory_id == "tactical_marine")[0]
	var bar = _of_class(tac, "SquadBar")[0]
	await _frames(2)
	var full_ratio: float = bar._ratio
	var enemy_bar = _of_class(enemy[0], "SquadBar")[0]
	tac.soldiers[0].take_damage(99999.0)
	tac.soldiers[0].take_damage(tac.soldiers[0].max_hp * 0.5)
	await _frames(2)
	_check("полоска отряда: у каждого отряда; полный %.2f → после потерь %.2f, бойцов %d; скрытый враг — без полоски" % [
		full_ratio, bar._ratio, bar._count], bars_ok and is_equal_approx(full_ratio, 1.0) and bar._count == 5 \
		and bar._ratio < 5.0 / 6.0 and not enemy_bar.is_visible_in_tree())
	var fog: Dictionary = load("res://scripts/data/FactionTheme.gd").SM_FOG_CRATERS[0]
	_check("туман темы приглушён (tint темнее белого)", fog.has("tint") and fog["tint"].v < 0.9)

	# 2. Всплывающие цифры: на расстановке нет; в схватке — крупный удар да, мелкий и яд нет
	var dread = mine.filter(func(s): return s.data.factory_id == "dreadnought")[0].soldiers[0]
	dread.max_hp = 1e6
	dread.current_hp = 1e6
	var parent = dread._world_parent()
	dread.take_damage(50.0)
	var in_placement := _of_class(parent, "FloatingText").size()
	scene._on_start_pressed()
	bm.set_process(false)   # тикаем сами — бой не кончится сам собой
	var before := _of_class(parent, "FloatingText").size()
	dread.take_damage(5.0)
	dread.take_damage(50.0, false)   # яд / огонь
	var small := _of_class(parent, "FloatingText").size() - before
	dread.take_damage(50.0)
	var big := _of_class(parent, "FloatingText").size() - before
	var texts = _of_class(parent, "FloatingText")
	var near_target: bool = not texts.is_empty() and texts[-1].global_position.distance_to(dread.global_position) < 80.0
	_check("цифры: расстановка %d, мелкий удар и яд %d, крупный %d — над бойцом" % [in_placement, small, big],
		in_placement == 0 and small == 0 and big == 1 and near_target)
	var before_wipe := _of_class(parent, "FloatingText").size()
	for s in tac.soldiers.duplicate():
		s.take_damage(99999.0)
	var wipe_texts = _of_class(parent, "FloatingText").filter(func(t): return "пал" in t.text)
	_check("свой отряд пал — надпись «… пал»", _of_class(parent, "FloatingText").size() > before_wipe and wipe_texts.size() == 1)

	# 3. Итог боя: урон в итогах, баннер, замедление
	bm.credit_damage(mine[1], 120.0)
	bm.credit_damage(enemy[0], 999.0)   # урон врага в итоги игрока не идёт
	var top = bm.top_damage_dealer()
	_check("урон отрядов игрока за бой: лучший %s — %d" % [top[0].unit_name if not top.is_empty() else "-", top[1] if not top.is_empty() else 0],
		not top.is_empty() and top[0] == mine[1].data and is_equal_approx(top[1], 120.0))
	for e in reg.get_alive_soldiers_of_team(1).duplicate():
		e.take_damage(1e9)
	bm._battle_tick()   # бой кончается: победа
	var banner = scene.hud.result_banner
	var slowed: bool = Engine.time_scale < 0.99
	_check("итог боя: баннер «%s» с лучшим отрядом, мир на миг замедлен (%.2f)" % [
		banner.get_child(0).text if banner else "", Engine.time_scale],
		banner != null and banner.get_child(0).text == "ПОБЕДА" and "Лучший отряд" in banner.get_child(1).text and slowed)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 900:
		await process_frame
	_check("замедление финала прошло — скорость обычная (%.2f)" % Engine.time_scale, is_equal_approx(Engine.time_scale, 1.0))
	bm.set_process(true)

	# 4. Камера, скорость, пауза пробелом
	scene = await _battle_scene([_squad_with(UnitFactory.create("tactical_marine"), 3)] as Array[UnitData])
	var cam = scene.camera
	var p := Vector2(500, 300)
	var world_before: Vector2 = cam.screen_to_world(p)
	var z0: float = cam.zoom.x
	cam.zoom_at(p, 1.0)
	cam.zoom_at(p, 1.0)   # два щелчка за кадр — точка всё равно на месте
	await process_frame
	var keeps_point: bool = cam.screen_to_world(p).distance_to(world_before) < 1.0 and cam.zoom.x > z0
	for i in 40:
		cam.zoom_at(p, 1.0)
	var z_max: float = cam.zoom.x
	for i in 80:
		cam.zoom_at(p, -1.0)
	var z_min: float = cam.zoom.x
	var pos0: Vector2 = cam.position
	cam.pan(Vector2(100, 0))
	var panned: bool = cam.position.x < pos0.x
	cam.pan(Vector2(1e6, 1e6))
	var clamped: bool = cam._bounds.grow(cam.PAN_MARGIN).has_point(cam.position) or \
		cam._bounds.grow(cam.PAN_MARGIN + 1.0).has_point(cam.position)
	_check("камера: зум к курсору (точка на месте), пределы ×%.1f…×%.1f от вписанного, тянуть — в пределах поля" % [
		z_min / cam._fit_zoom, z_max / cam._fit_zoom],
		keeps_point and is_equal_approx(z_max, cam._fit_zoom * cam.ZOOM_RANGE.y) \
		and is_equal_approx(z_min, cam._fit_zoom * cam.ZOOM_RANGE.x) and panned and clamped)
	_check("скорость боя: ×1, ×2, ×3", root.get_node("GameSettings").BATTLE_SPEEDS == ([1.0, 2.0, 3.0] as Array[float]))
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	var pm = scene.pause_menu
	pm._input(space)
	var no_pause_in_placement: bool = not paused
	scene._on_start_pressed()
	pm._input(space)
	var quick_on: bool = paused and pm.is_quick_paused() and not pm.is_open()
	pm.open()   # Esc поверх паузы пробелом — меню, подпись снята
	var menu_ok: bool = paused and pm.is_open() and not pm.is_quick_paused()
	pm.resume()
	pm._input(space)
	pm._input(space)
	_check("пробел: на расстановке нет; в схватке — пауза без меню, Esc — меню; второй пробел снимает",
		no_pause_in_placement and quick_on and menu_ok and not paused and not pm.is_quick_paused())
	# Через настоящую очередь ввода: кнопка скорости в фокусе (после клика) — пробел всё равно пауза
	var gs = root.get_node("GameSettings")
	var speed0: float = gs.battle_speed
	scene.hud._speed_button.grab_focus()
	var press := InputEventKey.new()
	press.keycode = KEY_SPACE
	press.physical_keycode = KEY_SPACE
	press.pressed = true
	root.push_input(press)
	var paused_by_queue: bool = paused and pm.is_quick_paused() and is_equal_approx(gs.battle_speed, speed0)
	# Камера на паузе: колесо всё равно зумит
	var zp: float = cam.zoom.x
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP   # камера сейчас на нижнем пределе зума
	wheel.pressed = true
	wheel.position = Vector2(500, 300)
	root.push_input(wheel)
	var zoom_on_pause: bool = cam.zoom.x > zp
	pm._input(space)
	_check("пробел при кнопке «×N» в фокусе — пауза, скорость та же; на паузе колесо зумит",
		paused_by_queue and zoom_on_pause and not paused)
	# Перетаскивание: отпускание съел UI — первое движение без зажатой кнопки его снимает
	scene._camera_dragging = true
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(50, 0)
	var pos_d: Vector2 = cam.position
	var ate: bool = scene._handle_camera_input(motion)
	_check("камера не залипает: кнопка отпущена над панелью — движение мыши не тянет",
		not ate and not scene._camera_dragging and cam.position == pos_d)
	bm.stop_battle()

	# 5. Магазин: лента забега и сноска синергии
	bm.reset_run()
	root.get_node("RunManager").new_run(3)
	root.get_node("EconomyManager").round_number = 5
	bm.player_units = [_squad_with(UnitFactory.create("tactical_marine"), 3)] as Array[UnitData]   # Marine 1
	change_scene_to_file("res://scenes/shop/ShopScene.tscn")
	await _frames(3)
	var tl = current_scene.timeline
	var tip: String = tl._get_tooltip(Vector2(tl._wave_x(15), 5))
	_check("лента забега: ближайшая волна %d, 5 — мини-босс, 15 — главный босс (%s)" % [tl.current_wave, tip],
		tl.current_wave == 5 and tl.wave_kind(5) == "miniboss" and tl.wave_kind(15) == "boss" \
		and tl.wave_kind(7) == "battle" and "главный босс" in tip)
	var sm = root.get_node("ShopManager")
	var note_tac: String = sm.get_synergy_note(CardFactory.tactical_squad())   # +3 Marine → 4
	var note_two: String = sm.get_synergy_note(CardFactory.apothecary_card())  # +1 Marine → 2
	var note_building: String = sm.get_synergy_note(CardFactory.bolter_turret())
	_check("сноска синергии: «%s» / «%s» / здание — нет" % [note_tac, note_two],
		"Marine 1 → 4" in note_tac and "откроет «Astartes Brotherhood»" in note_tac \
		and "Marine 1 → 2" in note_two and "ещё 1" in note_two and note_building == "")
	# Сноски на карте магазина — над кнопкой «Купить», ниже портрета
	var slot = null
	for n in current_scene.find_children("*", "", true, false):
		if n.has_method("show_owned_note") and n.card_data and n.card_data.card_type == "squad":
			slot = n
			break
	if slot == null:   # в наборе нет отряда — подставим карту отряда в первый слот
		for n in current_scene.find_children("*", "", true, false):
			if n.has_method("show_owned_note"):
				slot = n
				break
		slot.card_data = CardFactory.tactical_squad()
	slot.show_owned_note()
	await _frames(2)
	slot.show_owned_note()   # раскладка устоялась
	var notes_rect: Rect2 = slot._notes.get_global_rect()
	var portrait_bottom: float = slot.card_title.global_position.y
	_check("сноски карты — над кнопкой «Купить» (низ %.0f ≤ %.0f), не на портрете (верх %.0f ≥ %.0f)" % [
		notes_rect.end.y, slot.buy_button.global_position.y, notes_rect.position.y, portrait_bottom],
		slot.synergy_note.visible and notes_rect.end.y <= slot.buy_button.global_position.y + 0.5 and notes_rect.position.y >= portrait_bottom - 0.5)
	quit()
