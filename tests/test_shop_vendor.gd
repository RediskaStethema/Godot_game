extends SceneTree

# Продавец магазина (решение пользователя 11.11.2026): справа от карт, «Обновить» — вывеска на цепях над ним,
# реплики в облаке на действия, у Хаоса — свои реплики; seed забега не трогает; лист без ряби, тень, «Армия»
# сворачивает магазин над полем (12.11.2026).
#   godot --headless --path . -s tests/test_shop_vendor.gd

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _open_shop(race: String) -> Node:
	var rm = root.get_node("RunManager")
	root.get_node("BattleManager").reset_run()
	rm.player_faction = race
	var scene = load("res://scenes/shop/ShopScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(3)
	return scene

func _main() -> void:
	await process_frame
	var eco = root.get_node("EconomyManager")
	var rm = root.get_node("RunManager")
	var scene = await _open_shop("space_marines")
	var vendor = scene.vendor
	var lines: Dictionary = vendor.LINES

	# 1. Место: продавец справа от карт, кнопка обновления — на вывеске над ним, приветствие при входе
	var slots_end := 0.0
	for slot in scene.shop_slots.get_children():
		slots_end = maxf(slots_end, slot.get_global_rect().end.x)
	var vrect: Rect2 = vendor.get_global_rect()
	var sign_rect: Rect2 = vendor.sign_node.get_global_rect()
	var on_sign: bool = scene.reroll_button.get_parent() == vendor.sign_node and scene.reroll_button.size.x > 100.0
	_check("продавец справа (карты до %d, продавец с %d), «Обновить» на вывеске над ним (%s), приветствие «%s»"
		% [slots_end, vrect.position.x, on_sign, vendor.bubble_text()],
		slots_end <= vrect.position.x + 1.0 and on_sign and sign_rect.position.y < vendor.figure.get_global_rect().position.y
		and vendor.last_event == "greet" and lines["space_marines"]["greet"].has(vendor.bubble_text()))

	# 2. Реакции: обновление (вывеска качается), нет Req, покупка, продажа; seed забега не сдвигается
	eco.requisition = 100
	scene._on_reroll_pressed()
	var reroll_ok: bool = vendor.last_event == "reroll" and vendor.sign_node._swing > 0.0
	scene._on_purchase_requested(0)
	var buy_ok: bool = vendor.last_event == "buy" and lines["space_marines"]["buy"].has(vendor.bubble_text())
	eco.requisition = 0
	scene._on_reroll_pressed()
	var broke_ok: bool = vendor.last_event == "no_money"
	scene._sell_card(scene.purchased_cards[-1])
	var sell_ok: bool = vendor.last_event == "sell"
	var rng_state: int = rm.rng.state   # обновление и покупка берут rng забега сами; реплики — нет
	for e in vendor.EVENTS:
		vendor.react(e)
	_check("реакции: обновление %s, покупка %s, нет Req %s, продажа %s; seed забега не тронут %s"
		% [reroll_ok, buy_ok, broke_ok, sell_ok, rm.rng.state == rng_state],
		reroll_ok and buy_ok and broke_ok and sell_ok and rm.rng.state == rng_state)

	# 3. Облако в пределах экрана и гаснет само; заглушка без листа — рисуется кодом
	var view: Rect2 = scene.get_viewport_rect()
	var inside: bool = view.encloses(vendor.bubble.get_global_rect())
	await create_timer(vendor.BUBBLE_TIME + 4.0).timeout
	_check("облако реплики в экране (%s), гаснет само (%s); арт %s" % [inside, vendor.bubble_text(),
		"лист" if vendor.figure.has_art() else "заглушка"], inside and vendor.bubble_text() == "")
	scene.queue_free()
	await _frames(2)

	# 4. Хаос — тёмный механикус: свои реплики
	scene = await _open_shop("chaos")
	vendor = scene.vendor
	_check("Хаос: продавец «%s», приветствие из реплик тёмного механикус «%s»" % [vendor.faction, vendor.bubble_text()],
		vendor.faction == "chaos" and lines["chaos"]["greet"].has(vendor.bubble_text()))
	scene.queue_free()
	await _frames(2)

	# 5. Лист без «кипения» и тени (12.11.2026): тело кадров стойки — из кадра 0 (меняется только своё — рука,
	# механодендриты), у фигуры тень силуэтом; «Армия» над полем сворачивает магазин и разворачивает обратно
	var fr: SpriteFrames = load("res://assets/ui/shop/vendor/space_marines/frames.tres")
	var a: Image = fr.get_frame_texture("idle", 0).get_image()
	var b: Image = fr.get_frame_texture("buy", 3).get_image()   # стойка — один кадр; тело жеста — из него же
	var same := 0
	var total := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			if a.get_pixel(x, y).a > 0.5:
				total += 1
				if a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
					same += 1
	rm.new_run(7)
	for n in rm.map.nodes:   # магазин — после события (волна 1 теперь — стартовый выбор, 17.11.2026)
		if n.type == "shop":
			rm.current_node_id = n.id
			break
	rm.current_completed = false
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(6)
	var shop = current_scene.get("shop")
	var shadows: int = shop.vendor.figure.get("_shadows").size() if shop else 0
	var no_frame: bool = shop != null and shop.get_node_or_null("VendorFrame") == null
	shop.army_button.button_pressed = true
	shop.army_button.pressed.emit()
	await create_timer(shop.SLIDE_TIME + shop.SLIDE_STAGGER * 3.0 + 0.15).timeout
	var down: bool = shop.collapsed and not shop.get_node("ShopFrame").visible and shop.return_button.visible 		and shop.mouse_filter == 2 and shop.get_node("HudBar").visible
	shop.return_button.pressed.emit()
	await create_timer(shop.SLIDE_TIME + shop.SLIDE_STAGGER * 3.0 + 0.15).timeout
	var up: bool = not shop.collapsed and shop.get_node("ShopFrame").visible and not shop.return_button.visible 		and shop.mouse_filter == 0 and not shop.army_button.button_pressed
	_check("стойка — 1 кадр (%d), тело жеста = стойка на %d%%; тени %d, рамки нет %s; «Армия» сворачивает %s и разворачивает %s"
		% [fr.get_frame_count("idle"), 100 * same / maxi(total, 1), shadows, no_frame, down, up],
		fr.get_frame_count("idle") == 1 and same * 100 >= total * 60 and shadows > 0 and no_frame and down and up)
	# 5. «В БОЙ»: пока рука магазина уезжает вниз, рука боя (скамейка) скрыта — второй пачки карт нет (решение пользователя 16.11.2026);
	# когда магазин убран — скамейка видна
	var battle = current_scene
	var shop2 = battle.get("shop")
	shop2._empty_army_warned = true   # без армии первое нажатие только предупреждает
	shop2._on_battle_pressed()
	await _frames(2)
	var hidden_while_closing: bool = battle.bench != null and not battle.bench.visible
	await create_timer(shop2.SLIDE_TIME + shop2.SLIDE_STAGGER * 6.0 + 0.6).timeout
	var shown_after: bool = battle.bench.visible and battle.get("shop") == null
	_check("«В БОЙ»: скамейка скрыта, пока уезжает рука магазина (%s), после — видна (%s)" % [hidden_while_closing, shown_after],
		hidden_while_closing and shown_after)
	root.get_node("BattleManager").reset_run()
	quit()
