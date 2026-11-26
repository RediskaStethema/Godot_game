extends SceneTree

# Тестовый режим (решение пользователя 06.11.2026): кнопка в меню только в сборке для разработки, сразу
# расстановка с панелью всех карт расы (+ особые всех орденов), королевство 4×4, уровень из панели,
# волна и тип боя на выбор, цитадель не падает, после боя — та же расстановка, без сохранения.
#   godot --headless --path . -s tests/test_mode.gd
const SAVE_PATH = "user://_test_mode_save.json"

var bm
var rm

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	bm = root.get_node("BattleManager")
	rm = root.get_node("RunManager")
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _scene():
	await _frames(3)
	return current_scene

func _player_squads() -> Array:
	return root.get_node("SquadRegistry").get_alive_squads_of_team(0)

func _main() -> void:
	await process_frame
	# 1. Меню: кнопка есть в сборке для разработки
	var menu = load("res://scenes/menu/MainMenu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var button = menu.find_child("TestModeButton", true, false)
	_check("меню: кнопка «ТЕСТОВЫЙ РЕЖИМ» в сборке для разработки (debug %s)" % OS.is_debug_build(),
		(button != null) == OS.is_debug_build())
	var tut_button = menu.find_child("TutorialTestButton", true, false)
	_check("меню: кнопка «ОБУЧЕНИЕ (ТЕСТ)» — в сборке для разработки, как тестовый режим",
		(tut_button != null) == OS.is_debug_build())
	menu.queue_free()

	# 2. Вход: сразу расстановка, панель, королевство 4×4, рука пуста; карты — все расы и особые всех орденов
	rm.start_test_mode("space_marines", "ultramarines")
	var scene = await _scene()
	var panel = scene.get("test_panel")
	var ids: Array = CardFactory.ids_of(CardFactory.test_cards("space_marines"))
	var specials := ["honour_guard", "sanguinary_guard", "centurion_devastators", "thunderwolf_cavalry", "firedrakes",
		"codex_bastion", "blood_chalice", "fists_bastion", "wolf_totem", "vulkan_forge"]
	var all_special := specials.all(func(id): return id in ids)
	var unique := ids.size() == {}.merged(_as_set(ids)).size()
	_check("вход: расстановка с панелью, королевство %d клеток, рука пуста; карт %d без повторов, особые всех орденов, Хаоса нет" % [
		bm.kingdom_tiles.size(), ids.size()], scene.get("is_placement_phase") and panel != null
		and bm.kingdom_tiles.size() == 16 and bm.pending_cards.is_empty() and all_special and unique
		and not ("chaos_marines" in ids) and "bolter_turret" in ids and "iron_halo" in ids)

	var chaos_ids: Array = CardFactory.ids_of(CardFactory.test_cards("chaos"))
	_check("набор Хаоса: свои отряды и здания, особые всех богов, благословения; карт Космодесанта нет (%d карт)" % chaos_ids.size(),
		["chaos_marines", "hellbrute", "heretic_autocannon", "khorne_berzerkers", "rubric_marines", "warp_spire",
		"plague_cauldron", "blessing_khorne", "chaos_gods_blessing"].all(func(id): return id in chaos_ids)
		and not ("tactical_squad" in chaos_ids) and not ("honour_guard" in chaos_ids))

	# 3. Карта из панели — в руку; уровень 3 — отряд и здание сразу 3-го уровня
	panel.card_picked.emit("tactical_squad")
	panel.card_picked.emit("bolter_turret")
	var in_hand: int = scene.bench.bench_cards.size()
	panel._set_level(3)   # 3 улучшения: отряд ур.3, здание ур.3 (предел)
	var squad_card: CardData = scene.bench.bench_cards[0]
	var turret_card: CardData = scene.bench.bench_cards[1]
	var ok_s: bool = scene.card_play.play_squad(squad_card, Vector2i(3, 1))
	var ok_b: bool = scene.card_play.play_building(turret_card, Vector2i(0, 0))
	await _frames(2)
	var squad = scene._get_player_squad_at(Vector2i(3, 1))
	var turret = scene._get_player_building_at(Vector2i(0, 0))
	_check("панель → рука (%d), уровень 3: отряд ур.%d (%d бойцов), турель ур.%d" % [in_hand,
		squad.data.squad_level if squad else 0, squad.soldiers.size() if squad else 0, turret.card.building_level if turret else 0],
		in_hand == 2 and ok_s and ok_b and squad != null and squad.data.squad_level == 3 and turret != null
		and turret.card.building_level == 3 and turret.sprite != null and turret.sprite.animation == &"idle_3")
	scene.card_play.consume_bench_card(squad_card)
	scene.card_play.consume_bench_card(turret_card)

	# 4. Волна и тип боя: сцена заново, армия на месте, враги новой волны
	panel.wave_changed.emit(10)
	scene = await _scene()
	panel = scene.get("test_panel")
	panel.type_changed.emit("boss")
	scene = await _scene()
	var squad2 = scene._get_player_squad_at(Vector2i(3, 1))
	_check("волна 10, бой с боссом: сцена заново, отряд ур.3 на месте, турель стоит",
		scene.get("battle_wave") == 10 and scene.get("battle_type") == "boss" and squad2 != null
		and squad2.data.squad_level == 3 and scene._get_player_building_at(Vector2i(0, 0)) != null)

	# 4б. Босс из панели (решение пользователя 09.11.2026 — сетка вместо перебора): видна в бою «босс», «от seed» + все
	# 9 примархов (свои враги — первыми), выбранный подсвечен; клик по чужому (Жиллиман против Космодесанта) — он и выходит
	panel = scene.get("test_panel")
	var order: Array = panel.boss_order(rm.player_faction)
	var grid_btns: Dictionary = panel.get("_boss_buttons")
	var shown: bool = panel.get("_boss_box").visible and grid_btns.size() == 10 and grid_btns[""].button_pressed
	grid_btns["primarch_guilliman"].pressed.emit()
	scene = await _scene()
	var bosses: Array = root.get_node("SquadRegistry").get_alive_squads_of_team(1) 		.filter(func(sq): return sq.data.factory_id == "primarch_guilliman")
	var new_btns: Dictionary = scene.get("test_panel").get("_boss_buttons")
	var picked: bool = new_btns["primarch_guilliman"].button_pressed and not new_btns[""].button_pressed
	_check("босс из панели: сетка %d, выбран Жиллиман — подсвечен и на поле, отряд на месте" % order.size(),
		shown and order.size() == 10 and order[0] == "" and order[1] == EnemyWaves.BOSS["units"][0]
		and bosses.size() == 1 and picked and scene._get_player_squad_at(Vector2i(3, 1)) != null)

	# 5. Без сохранения: даже с включённым SaveManager файл не пишется
	var sm = root.get_node("SaveManager")
	var old_path: String = sm.save_path
	sm.save_path = SAVE_PATH
	sm.enabled = true
	var saved: bool = sm.save_run()
	sm.enabled = false
	sm.save_path = old_path
	_check("сохранение в тесте не пишется", not saved and not FileAccess.file_exists(SAVE_PATH))

	# 6. Бой: цитадель не падает; итог — та же расстановка, цитадель целая
	scene.card_play.play_building(CardFactory.create("fists_bastion"), Vector2i(1, 0))
	var audio = root.get_node("AudioManager")
	var placement_music: String = audio.current_music()
	scene._on_start_pressed(false)
	await _frames(2)
	var battle_music: String = audio.current_music()
	await create_timer(audio.MUSIC_PUNCH["boss"] + 0.15).timeout   # прежний трек погас — босс сразу в полную громкость
	var player: AudioStreamPlayer = audio.get("_music")
	var loop = player.stream as AudioStreamWAV
	_check("музыка босса: на расстановке «%s», с началом боя «%s» — петля %.1f с, сразу в полную громкость (%.0f дБ)" % [
		placement_music, battle_music, loop.get_length() if loop else 0.0, player.volume_db],
		placement_music == "battle" and battle_music == "boss" and loop != null and loop.loop_mode == AudioStreamWAV.LOOP_FORWARD
		and is_equal_approx(loop.get_length(), 30.0) and loop.loop_end == int(30.0 * loop.mix_rate)
		and player.playing and is_zero_approx(player.volume_db))
	# Бастион бьёт только вперёд: враги левее (у цитадели, в тылу) — не цель, разворота нет
	var bastion = scene._get_player_building_at(Vector2i(1, 0))
	var enemies: Array = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(1).duplicate()
	var saved_pos := enemies.map(func(e): return e.global_position)
	for e in enemies:
		e.global_position = bastion.global_position + Vector2(-200, 40)
	var behind = bastion._find_target(INF)
	enemies[0].global_position = bastion.global_position + Vector2(300, -60)
	var ahead = bastion._find_target(INF)
	for i in enemies.size():
		enemies[i].global_position = saved_pos[i]
	_check("бастион: враги позади (у цитадели) — не цель, впереди — цель", behind == null and ahead == enemies[0])
	bm.damage_citadel(100000.0)
	var hp_in_battle: float = bm.citadel_hp
	# штурм проигран — бой кончается поражением сразу (09.11.2026: было 1 HP и осада минутами — бой «вставал»)
	var siege_lost: bool = not bm.is_battle_running() and bm.winner_team == GameConstants.TEAM_ENEMY
	bm.surrender()   # бой уже кончен — ничего не делает
	await create_timer(scene.test_tools.TEST_RESULT_TIME + 0.6).timeout
	scene = await _scene()
	var squad3 = scene._get_player_squad_at(Vector2i(3, 1))
	_check("цитадель не падает (%.0f HP), штурм проигран — бой сразу кончен, после боя — расстановка как до боя, цитадель целая, панель на месте" % hp_in_battle,
		hp_in_battle >= 1.0 and siege_lost and scene.get("is_placement_phase") and scene.get("test_panel") != null
		and squad3 != null and squad3.data.squad_level == 3 and bm.citadel_hp == bm.CITADEL_MAX_HP
		and not bm.battle_in_progress and rm.test_mode)

	# 6b. Магазин из панели (21.11.2026): окно поверх поля, монет хватает, набор новый, покупка — в руку, «В БОЙ» — назад к полю
	var node_before: int = rm.current_node_id
	var hand_before: int = bm.pending_cards.size()
	scene.get("test_panel").shop_pressed.emit()
	await _frames(4)
	var shop = scene.get("shop")
	var offers_ok: bool = shop != null and root.get_node("ShopManager").current_offers.size() > 0
	var req: int = root.get_node("EconomyManager").requisition
	var bought = null
	if offers_ok:   # покупка — как кликом по слоту (карта уходит в руку магазина)
		shop.call("_on_purchase_requested", 0)
		bought = true if shop.get("purchased_cards").size() == hand_before + 1 else null
	if shop != null:
		shop.call("_on_battle_pressed")   # без армии — предупреждение, со второго нажатия уход
		if scene.get("shop") != null:
			shop.call("_on_battle_pressed")
	await _frames(4)
	_check("магазин из панели: окно открыто, монет ≥ %d (%d), покупка ушла в руку (%d → %d), закрыт — поле и панель на месте, шаг цепочки не сдвинут" % [
		scene.test_tools.TEST_SHOP_REQUISITION, req, hand_before, bm.pending_cards.size()],
		offers_ok and req >= scene.test_tools.TEST_SHOP_REQUISITION and bought != null and bm.pending_cards.size() == hand_before + 1
		and scene.get("shop") == null and not scene.get("shop_phase") and scene.get("test_panel").is_visible_in_tree()
		and scene.bench.bench_cards.size() == bm.pending_cards.size() and rm.current_node_id == node_before)

	# 7. Очистить поле
	scene.get("test_panel").clear_pressed.emit()
	scene = await _scene()
	_check("«Очистить поле»: ни отрядов, ни зданий", _player_squads().is_empty() and bm.player_buildings.is_empty())

	# 8. В главное меню — тест закончен, армия тестовая сброшена
	rm.goto_main_menu()
	await _frames(3)
	_check("в меню: тестовый режим выключен, армия сброшена", not rm.test_mode and bm.player_units.is_empty()
		and bm.kingdom_tiles.size() == 9)
	quit()

static func _as_set(a: Array) -> Dictionary:
	var d := {}
	for x in a:
		d[x] = true
	return d
