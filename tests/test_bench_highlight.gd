extends SceneTree

# Расстановка: курсор на карте отряда / здания на скамейке — клетки такого же отряда / здания на поле подсвечены
# (BattleScene._on_bench_card_hovered → свечение TileGlow «compatible»; плоскую заливку клеток убрали 19.11.2026). Пока карту тащат —
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

# Клетки, что сейчас светятся «такой же отряд / здание» (свечение живо и не гаснет)
func _lit(scene) -> Array:
	var tiles: Array = []
	for g in scene._same_card_glows:
		if is_instance_valid(g) and g.get("_dismiss_left") < 0.0:
			for t in scene.iso_grid.get_all_tiles():
				if g.global_position.distance_to(scene.iso_grid.tile_to_screen(t)) < 1.0:
					tiles.append(t)
	return tiles

# Негаснущего свечения «compatible» на поле не осталось
func _off(scene) -> bool:
	return scene.renderer.get_children().all(func(g):
		return g.get("verdict") != "compatible" or g.get("_dismiss_left") >= 0.0 or g.is_queued_for_deletion())

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
	bm.pending_cards = [CardFactory.tactical_squad(), CardFactory.scout_squad(), CardFactory.bolter_turret(),
		CardFactory.fortress_wall()] as Array[CardData]
	bm.player_buildings = {CardFactory.bolter_turret(): Vector2i(0, 0), CardFactory.thunderfire_cannon(): Vector2i(0, 1)}
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var renderer = scene.renderer
	var tac_card = _bench_card(scene, "tactical_squad")

	# 1. Курсор на карте Tactical — подсвечены обе клетки Tactical, Assault — нет
	tac_card.mouse_entered.emit()
	var lit: Array = _lit(scene)
	_check("Tactical: подсвечены %s" % [lit], lit.size() == 2 and lit.has(Vector2i(2, 0))
		and lit.has(Vector2i(1, 2)) and not lit.has(Vector2i(2, 1)))

	# 2. Курсор ушёл с карты — подсветка погасла
	tac_card.mouse_exited.emit()
	_check("курсор ушёл: подсветки нет", _off(scene))

	# 3. Отряда / здания этой карты на поле нет — подсветки нет
	_bench_card(scene, "scout_squad").mouse_entered.emit()
	var scout_lit := _off(scene)
	_bench_card(scene, "fortress_wall").mouse_entered.emit()
	_check("Scout и стена (нет на поле): подсветки нет", scout_lit and _off(scene))

	# 4. Карта здания — подсвечена клетка такого же здания, другое здание — нет
	_bench_card(scene, "bolter_turret").mouse_entered.emit()
	var lit_buildings = bm.buildings.filter(func(x): return x.modulate != Color.WHITE).map(func(x): return x.tile)
	var lit_turret := _lit(scene)
	_check("турель: подсвечена клетка %s и само здание %s" % [lit_turret, lit_buildings],
		lit_turret == [Vector2i(0, 0)]
		and bm.buildings.size() == 2 and lit_buildings == [Vector2i(0, 0)])
	_bench_card(scene, "bolter_turret").mouse_exited.emit()
	_check("курсор ушёл: здания без подсветки", bm.buildings.all(func(x): return x.modulate == Color.WHITE))

	# 5. Карту тащат: курсор ушёл на поле — подсветка держится; бросили мимо — погасла
	tac_card.mouse_entered.emit()
	tac_card.drag_started.emit(tac_card.card_data, Vector2.ZERO)
	tac_card.mouse_exited.emit()
	var held := _lit(scene).size() == 2
	scene.bench._on_drop(Vector2(-1000, -1000))
	_check("тащим: подсветка держится, бросили — погасла", held and _off(scene))

	# 6. В бою подсветки нет: ни карты под курсором, ни клеток королевства; зона врага не подсвечивается вовсе
	var overlay_before = renderer.grid_overlay
	scene._on_start_pressed(false)
	await process_frame
	scene._on_bench_card_hovered(tac_card.card_data)
	_check("в бою: подсветки нет (на расстановке клетки королевства подсвечены, в бою — нет; зона врага — никогда)",
		_off(scene) and overlay_before and not renderer.grid_overlay
		and not renderer.has_method("_draw_enemy_zone"))

	bm.stop_battle()
	scene.queue_free()
	bm.reset_run()
	quit()
