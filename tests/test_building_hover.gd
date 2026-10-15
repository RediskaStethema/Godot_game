extends SceneTree

# Подсказка по зданию под курсором — только по его клетке: что за здание, уровень, что делает;
# оно не гаснет (OcclusionFader.pinned); моделька над чужой клеткой — ни подсказки, ни зоны;
# зона действия Казарм (соседи по сторонам) — на расстановке подсвечена, в бою — нет (поле без подсветки); курсор ушёл — подсказка и зона пропали.
# Сохранение выключено — забег игрока не трогает.
#   godot --headless --path . -s tests/test_building_hover.gd

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _frames(n: int) -> void:
	for i in range(n): await process_frame

# Движение мыши как от игрока: окно обновляет, что под курсором, и BattleScene._input ведёт подсказку
func _move_mouse(pos: Vector2) -> void:
	var e = InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	root.push_input(e, true)   # координаты вьюпорта (окно headless — другого размера)
	await _frames(2)

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(5)
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	var barracks = CardFactory.barracks()
	var turret = CardFactory.bolter_turret()
	bm.player_buildings[barracks] = Vector2i(1, 1)
	bm.player_buildings[turret] = Vector2i(0, 0)
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(3)
	var scene = current_scene
	var b_node = null
	for b in bm.buildings:
		if b.building_type == "barracks":
			b_node = b
	var at = scene.camera.world_to_screen(b_node.global_position)

	# 1. Наведение на Казармы: подсказка с названием и уровнем, здание не гаснет, соседи подсвечены
	await _move_mouse(at)
	var text: String = b_node.describe()
	var neighbours = b_node.get_effect_tiles("barracks", Vector2i(1, 1))
	_check("Казармы под курсором: подсказка «%s», здание закреплено" % text.get_slice("\n", 0),
		scene.hovered_building == b_node and scene.inspector.is_building_hover_visible()
		and text.contains("Barracks") and text.contains("ур. 1/") and scene.fader.pinned == b_node)
	_check("зона Казарм — %d соседа по сторонам" % neighbours.size(),
		neighbours.size() == 4 and scene.renderer.effect_tiles == neighbours)

	# 1б. Курсор на модельке Казарм над клеткой без здания — здание не выбрано: ни подсказки, ни зоны
	var grid = scene.iso_grid
	var rect: Rect2 = b_node.get_occlusion_rect()
	var on_model = Vector2.INF
	var building_tiles = bm.player_buildings.values()   # клетка с другим зданием выберет его — не та проверка
	for y in range(int(rect.position.y) + 2, int(rect.end.y), 4):
		for x in range(int(rect.position.x) + 2, int(rect.end.x), 4):
			var p = Vector2(x, y)
			if not building_tiles.has(grid.screen_to_tile(p)):
				on_model = p
				break
		if on_model != Vector2.INF:
			break
	await _move_mouse(scene.camera.world_to_screen(on_model))
	_check("моделька Казарм над пустой клеткой: ни подсказки, ни зоны, здание не закреплено",
		on_model != Vector2.INF and scene.hovered_building == null and not scene.inspector.is_building_hover_visible()
		and scene.renderer.effect_tiles.is_empty() and scene.fader.pinned == null)

	# 2. Текст описания — без буквальных переносов внутри строк, по строке на пункт
	var turret_text: String = bm.buildings.filter(func(b): return b.building_type == "tower")[0].describe()
	_check("описание турели: 3 строки (название, действие, уровень)", turret_text.split("\n").size() == 3)

	# 3. Курсор ушёл в пустоту — подсказки и зоны нет
	await _move_mouse(Vector2(-500, -500))
	_check("курсор ушёл — подсказки и зоны нет",
		scene.hovered_building == null and not scene.inspector.is_building_hover_visible()
		and scene.renderer.effect_tiles.is_empty() and scene.fader.pinned == null)

	# 4. В бою: подсказка есть, зона действия не рисуется (подсветка поля выключена)
	scene._on_start_pressed()
	await _frames(1)
	await _move_mouse(scene.camera.world_to_screen(b_node.global_position))
	_check("в бою — подсказка есть, подсветки поля нет",
		scene.inspector.is_building_hover_visible() and not scene.renderer.grid_overlay)
	bm.stop_battle()
	quit()
