extends SceneTree

# Подсказка по зданию под курсором — только по его клетке: что за здание, уровень, что делает;
# оно не гаснет (OcclusionFader.pinned); моделька над чужой клеткой — ни подсказки, ни зоны;
# зона действия Казарм (соседи по сторонам) — на расстановке подсвечена, в бою — нет (поле без подсветки); курсор ушёл — подсказка и зона пропали;
# клик по зданию — справка-карточка; длинная справка не выходит за экран.
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

# Клик левой кнопкой по точке мира — прямо в справку (как _unhandled_input от окна)
func _click(inspector, world: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = root.get_viewport().get_canvas_transform() * world
	inspector._unhandled_input(e)

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

	# 1а. Зона на клетках — только у зданий для своих (правило пользователя 17.10.2026): Apothecarion — крест,
	#     как Казармы; турель (по врагам) — без зоны, стена и генератор — тоже
	var t_node = bm.buildings.filter(func(b): return b.building_type == "tower")[0]
	await _move_mouse(scene.camera.world_to_screen(t_node.global_position))
	var apo_zone = b_node.get_effect_tiles("apothecarion", Vector2i(1, 1))
	_check("турель под курсором — зоны нет; Apothecarion — крест (%d); стена и генератор — нет" % apo_zone.size(),
		scene.hovered_building == t_node and scene.renderer.effect_tiles.is_empty()
		and apo_zone.size() == 4 and apo_zone.has(Vector2i(1, 2)) and not apo_zone.has(Vector2i(2, 2))
		and b_node.get_effect_tiles("wall", Vector2i(1, 1)).is_empty()
		and b_node.get_effect_tiles("generator", Vector2i(1, 1)).is_empty())

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

	# 3а. Клик по зданию на расстановке — справка-карточка (решение пользователя 24.10.2026): название, ур.
	#     ромбиками, что делает; пока открыта и курсор ушёл — здание закреплено, зона видна; клик снова — закрыта
	var insp = scene.inspector
	_click(insp, b_node.global_position)
	var card_text: String = insp._card._body.text
	await _move_mouse(Vector2(-500, -500))
	var card_ok: bool = insp.is_info_visible() and insp.info_building == b_node \
		and insp._card._title.text == b_node.card.title and insp._card._level == 1 and "соседних клетках" in card_text
	var kept: bool = scene.fader.pinned == b_node and scene.renderer.effect_tiles == neighbours
	_click(insp, b_node.global_position)
	_check("клик по Казармам — справка %s, курсор ушёл — зона и здание держатся %s, клик снова — закрыта %s"
		% [card_ok, kept, not insp.is_info_visible()], card_ok and kept and not insp.is_info_visible())

	# 3б. Длинная справка не уходит за экран (решение пользователя 24.10.2026: справка цитадели с синергиями
	#     была выше экрана): карточка шире / текст мельче, низ — в пределах экрана, верх — не выше шапки
	_click(insp, bm.citadel.get_occlusion_rect().get_center())
	var long_text := "\n".join(range(40).map(func(i): return "• Синергия %d — +15%% урона всем Marine" % i))
	insp._card.setup(null, "Цитадель", "", long_text, 0, 0, Color.GOLD)
	var screen: Vector2 = root.get_viewport().get_visible_rect().size
	var hud: float = load("res://scripts/ui/UITheme.gd").HUD_HEIGHT   # UITheme тянет автолоады — не по имени
	insp._card.fit(screen.y - hud)
	insp._card.reset_size()
	var compact: bool = insp._card.size.y <= screen.y - hud + 1.0 and insp._card.size.x > 270.0   # пришлось расширить
	_click(insp, bm.citadel.get_occlusion_rect().get_center())   # закрыть
	_click(insp, bm.citadel.get_occlusion_rect().get_center())   # открыть: настоящая справка цитадели
	var r := Rect2(insp._card.position, insp._card.size)
	_check("длинная справка: %d строк влезают в %d px, шире (%s); цитадель — карточка %s в экране %s" % [40,
		int(screen.y - hud), compact, r, screen],
		compact and r.position.y >= hud - 0.5 and r.end.y <= screen.y + 0.5 and r.end.x <= screen.x + 0.5)
	_click(insp, bm.citadel.get_occlusion_rect().get_center())

	# 4. В бою: подсказка есть, зона действия не рисуется (подсветка поля выключена)
	scene._on_start_pressed(false)
	await _frames(1)
	await _move_mouse(scene.camera.world_to_screen(b_node.global_position))
	_check("в бою — подсказка есть, подсветки поля нет",
		scene.inspector.is_building_hover_visible() and not scene.renderer.grid_overlay)
	bm.stop_battle()
	quit()
