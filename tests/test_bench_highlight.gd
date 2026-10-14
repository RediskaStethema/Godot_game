extends SceneTree

# Расстановка: курсор на карте отряда на скамейке — клетки такого же отряда на поле подсвечены
# (BattleScene._on_bench_card_hovered → IsoGridRenderer.highlighted_tiles). Пока карту тащат —
# подсветка держится, бросили / ушли курсором — гаснет; в бою — нет.
# Сохранение выключено — забег игрока не трогает.
#   godot --headless --path . -s tests/test_bench_highlight.gd

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _squad(card: CardData) -> UnitData:
	var d = UnitFactory.create(card.unit_factory_id)
	d.squad_size = card.unit_count
	var hp: Array[float] = []
	for i in card.unit_count:
		hp.append(1.0)
	d.saved_hp = hp
	return d

func _bench_card(scene, id: String):
	for c in scene.bench.cards_container.get_children():
		if c.get("card_data") and c.card_data.id == id:
			return c
	return null

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(7)
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == 2:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 2
	var tac_a = _squad(CardFactory.tactical_squad())
	var tac_b = _squad(CardFactory.tactical_squad())
	var assault = _squad(CardFactory.assault_squad())
	bm.player_units = [tac_a, tac_b, assault] as Array[UnitData]
	bm.player_placements = {tac_a: Vector2i(2, 0), tac_b: Vector2i(1, 2), assault: Vector2i(2, 1)}
	bm.pending_cards = [CardFactory.tactical_squad(), CardFactory.scout_squad(), CardFactory.bolter_turret()] as Array[CardData]
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var renderer = scene.renderer
	var tac_card = _bench_card(scene, "tactical_squad")

	# 1. Курсор на карте Tactical — подсвечены обе клетки Tactical, Assault — нет
	tac_card.mouse_entered.emit()
	var lit: Array = renderer.highlighted_tiles
	_check("Tactical: подсвечены %s" % [lit], lit.size() == 2 and lit.has(Vector2i(2, 0))
		and lit.has(Vector2i(1, 2)) and not lit.has(Vector2i(2, 1)))

	# 2. Курсор ушёл с карты — подсветка погасла
	tac_card.mouse_exited.emit()
	_check("курсор ушёл: подсветки нет", renderer.highlighted_tiles.is_empty())

	# 3. Отряда этой карты на поле нет, здание — подсветки нет
	_bench_card(scene, "scout_squad").mouse_entered.emit()
	var scout_lit = renderer.highlighted_tiles.is_empty()
	_bench_card(scene, "bolter_turret").mouse_entered.emit()
	_check("Scout (нет на поле) и здание: подсветки нет", scout_lit and renderer.highlighted_tiles.is_empty())

	# 4. Карту тащат: курсор ушёл на поле — подсветка держится; бросили мимо — погасла
	tac_card.mouse_entered.emit()
	tac_card.drag_started.emit(tac_card.card_data, Vector2.ZERO)
	tac_card.mouse_exited.emit()
	var held = renderer.highlighted_tiles.size() == 2
	scene.bench._on_drop(Vector2(-1000, -1000))
	_check("тащим: подсветка держится, бросили — погасла", held and renderer.highlighted_tiles.is_empty())

	# 5. В бою подсветки нет
	scene._on_start_pressed()
	await process_frame
	scene._on_bench_card_hovered(tac_card.card_data)
	_check("в бою: подсветки нет", renderer.highlighted_tiles.is_empty())

	bm.stop_battle()
	scene.queue_free()
	bm.reset_run()
	quit()
