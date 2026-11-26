extends Node2D

# Сцена боя: собирает поле и компоненты, расстановка игрока, розыгрыш карт,
# старт и итог боя. Логика тика — BattleManager, механики — в автолоадах
# (армия между боями — BattleManager, синергии/командир — SynergyManager,
# доход — EconomyManager). UI — компоненты в scenes/battle/ui/.

@onready var grid_renderer: Node2D = $GridRenderer
@onready var units_container: Node2D = $Units
@onready var start_button: Button = $UI/StartButton
@onready var result_label: Label = $UI/ResultLabel

const BENCH_SCENE = preload("res://scenes/battle/Bench.tscn")
const SQUAD_SCENE = preload("res://scenes/battle/Squad.tscn")
# Магазин — окно поверх поля (решение пользователя 12.11.2026, образец download.png: «фон прозрачный, видно поле боя»):
# шаг SHOP забега открывает эту сцену (RunManager.enter_node), поле — следующего боя, враги скрыты как на расстановке;
# поверх — ShopScene (embedded) на слое SHOP_LAYER; шапка боя и рука спрятаны, поле клики не ловит. «В БОЙ» магазина →
# _on_shop_finished: шаг боя становится текущим без смены сцены (RunManager.enter_battle_in_place), магазин тает,
# открывается расстановка
const SHOP_SCENE = preload("res://scenes/shop/ShopScene.tscn")
const PICK_SCENE = preload("res://scenes/pick/CardPickScene.tscn")
const SHOP_SCENE_SCRIPT = preload("res://scenes/shop/ShopScene.gd")
const AUTO_START_DELAY: float = 1.0   # пауза между последней сыгранной картой и автостартом боя (сек, время дерева)
const SHOP_LAYER: int = 5           # над UI боя, под паузой (PauseMenu.LAYER 10) и посадкой (BattleLanding)
const SHOP_FADE_TIME: float = 0.25
# Область экрана под поле: под HUD; при расстановке — до скамейки
const PLAY_AREA_MARGIN: float = 8.0
const UPGRADE_FX_RISE := Vector2(0, -48)   # знак карты-улучшения — над головами отряда

var iso_grid: IsoGrid = IsoGrid.new()
var renderer: IsoGridRenderer = null
var camera: BattleCamera = null
var bench: Node = null
var hud: BattleHud = null
var inspector: SquadInspector = null
var expansion_banner: ExpansionBanner = null   # объявление этапа расширения (после боя, до магазина)
var pause_menu: PauseMenu = null
var fader: OcclusionFader = null   # прозрачность построек — только на расстановке
var reticle: ArtilleryReticle = null   # прицел орудия игрока — в бою за курсором
var hovered_building: Building = null   # здание под курсором (_update_building_hover)
var test_panel: TestPanel = null   # тестовый режим (RunManager.test_mode): все карты расы, волна, уровень
var shop: Control = null            # окно магазина поверх поля (ShopScene), пока идёт шаг SHOP
var shop_phase: bool = false        # открыт магазин: расстановки ещё нет
const BUILDING_HIGHLIGHT = Color(1.45, 1.2, 0.7)   # здание карты под курсором на скамейке — золотом
# Скорость боя: Engine.time_scale = базовый × GameSettings.battle_speed, только
# пока идёт бой; базовый — тот, что был до боя (тесты гоняют с ускорением)
var _base_time_scale: float = 1.0
var _speed_applied: bool = false
const FINALE_SLOWMO: float = 0.35       # скорость мира в финале боя
const FINALE_SLOWMO_TIME: float = 0.6   # сколько реальных секунд
# Стоп-кадр на крупном ударе (решение пользователя 08.11.2026, только вид): мир на HITSTOP_TIME реального
# времени замедляется до HITSTOP_SCALE — удар Дредноута, приземление прыжка, залп орудия, гибель техники.
# Не чаще HITSTOP_GAP_MS, не в финале; headless — выключен (тесты гоняют бой по кадрам), тест включает сам
const HITSTOP_SCALE: float = 0.05
const HITSTOP_TIME: float = 0.05
const HITSTOP_GAP_MS: int = 400
var hitstop_enabled: bool = DisplayServer.get_name() != "headless"
var _hitstop_base: float = -1.0   # скорость до стоп-кадра (-1 — его нет)
var _hitstop_at: int = -100000
var _finale_base_scale: float = -1.0    # скорость до замедления (-1 — замедления нет)
# Финальный босс (решение пользователя 09.11.2026, BossFx): выход — наезд камеры, титр, появление, удар о землю;
# смерть — замедление мира, наезд, вспышка, титр; итог боя ждёт конца этого мига. Только вид
const BOSS_INTRO_TIME: float = 2.2      # сек игрового времени: столько длится выход (бой не начнётся раньше)
const BOSS_INTRO_ZOOM: float = 1.8      # наезд — от вписанного зума
const BOSS_INTRO_IMPACT: float = 0.75   # удар о землю — на этой доле ряда appear
const BOSS_FALL_SLOWMO: float = 0.25    # скорость мира, пока примарх падает
const BOSS_FALL_TIME: float = 1.4       # реальных секунд
const BOSS_FALL_ZOOM: float = 1.6
const BOSS_FALL_LIGHT: float = 0.5      # яркость вспышки смерти (была 1.0 — засвечивала поле)
var _intro_time: float = 0.0            # выход босса этого «В БОЙ» (0 — нет)
var _boss_fall_base: float = -1.0       # скорость до замедления смерти босса (-1 — нет)
var _deferred_winner: int = -2          # итог боя пришёл во время смерти босса (-2 — нет)

var battle_type: String = RunMapNode.BATTLE   # тип боя шага забега: battle / miniboss / boss
var battle_wave: int = 1
var is_placement_phase: bool = true
var _auto_start_pending: bool = false   # бой уже вот-вот начнётся сам (в руке MIN_HAND_CARDS карты)
var player_soldiers_at_start: int = 0   # для бонуса «победа без потерь»
var _unlocked_difficulty: int = 0       # победа над боссом открыла этот уровень сложности (0 — нет)
var enemy_elites_at_start: int = 0      # элитные враги (тег elite) — бонус TDD за каждого
# Отряды игрока на старте боя — павшие целиком при победе возрождаются
var player_squads_at_start: Array[Dictionary] = []
var _battle_resolved: bool = false
# Построение перед боем (решение пользователя 23.10.2026, ориентир — 9 Kings, Screenshot 2026-10-23 181716.png):
# после «В БОЙ» армия выходит из королевства за переднюю стену и встаёт строем — ближний бой впереди, стрелки
# и лекари сзади (_deploy_slots); бой стартует сам, когда встали. Клетка отряда (squad.tile) по-прежнему решает
# бонус ряда и соседство со зданиями — строй только меняет, где отряд начинает бой. Враги в своей зоне — так же
# (_place_enemy_squads: ближний бой в передние клетки)
# Ход — бегом своей скоростью (решение пользователя 23.10.2026: было всем за 1.8 с с разгоном — до 300 px/с, отряды
# «вылетали», ноги не успевали): скорость бега отряда × DEPLOY_PACE, медленные — быстрее, чтобы успеть за
# DEPLOY_MAX_TIME; равномерно (без разгона — темп ног совпадает с ходом). С ×2 / ×3 скорости боя — быстрее
const DEPLOY_PACE: float = 1.5
const DEPLOY_MAX_TIME: float = 3.5      # сек — самый долгий ход
const DEPLOY_HOLD: float = 0.5          # сек — армия стоит строем перед стартом
const DEPLOY_BACK_LINE: float = 1.1     # клеток от переднего края рамки до задней линии (за стеной владений)
const DEPLOY_LINE_STEP: float = 1.2     # клеток между линиями
const DEPLOY_SLOTS: int = 4             # отрядов в линии
const DEPLOY_SLOT_STEP: float = 1.3     # клеток между отрядами в линии
# Большая армия (17.11.2026, решение пользователя: «при большом количестве юнитов армии смешиваются с армией противников»):
# линии шли вперёд без предела (7 линий = 8 клеток при 5 клетках ничьей земли) и заходили в зону врага. Теперь глубина
# построения не больше DEPLOY_MAX_DEPTH клеток (3 линии): отрядов в линии больше (до DEPLOY_SLOTS_MAX), шаг в линии уже
const DEPLOY_MAX_DEPTH: float = 2.4
const DEPLOY_SLOTS_MAX: int = 9
const DEPLOY_MAX_WIDTH: float = 8.5     # клеток — ширина линии не больше (поле не бесконечно)
const DEPLOY_MIN_LINE_STEP: float = 0.8
const DEPLOY_MIN_SLOT_STEP: float = 0.95
const DEPLOY_BACK_RANGE: float = 80.0   # дальность атаки больше — отряд встаёт назад (лекари — тоже)
var is_deploying: bool = false

# Тип карты → розыгрыш на клетку (card, tile) → разыграна ли. Новый тип карты:
# функция здесь + строка в словаре + подсказка в CardData.PLAY_HINTS
var _card_handlers: Dictionary = {}

# -------------------------------------------------------
# ИНИЦИАЛИЗАЦИЯ
# -------------------------------------------------------
func _ready() -> void:
	# Прошлый бой мог не дойти до итога (загрузка сохранения посреди боя) —
	# в реестрах остались бы удалённые отряды и бойцы
	SquadRegistry.clear()
	SoldierRegistry.clear()
	battle_type = RunManager.get_battle_type()   # в магазине — тип следующего боя (RunManager.get_upcoming_battle)
	shop_phase = not RunManager.test_mode and (RunManager.is_shop_node_active() or RunManager.is_pick_node_active())
	if RunManager.player_faction != "chaos":
		DropPod.warm()   # кадры капсулы — в фоне, к первой выложенной карте отряда
	if not shop_phase:   # музыку магазина ставит ShopScene
		AudioManager.play_music("battle")   # музыка босса — с началом схватки (_on_start_pressed)
	UITheme.apply_cursors()
	battle_wave = RunManager.get_battle_wave()
	# Обучение — до поля: учебный бой подменяет врага при расстановке (_place_enemy_squads)
	if Tutorial.is_active():
		tutorial = Tutorial.new()
		tutorial.setup(self, battle_wave)
	_card_handlers = {
		"squad": _play_squad_card,
		"upgrade": _play_upgrade_card,
		"building": _play_building_card,
		"event": _play_event_card,
	}
	_build_ui()
	_build_field()
	_populate_field()
	Vfx.warm_cache()          # листы эффектов и снарядов и файлы звуков — на загрузке, не посреди схватки
	Projectile.warm_cache()
	AudioManager.warm_cache()
	SaveManager.save_run()
	# Первое поле нового забега — посадка сквозь облака (MenuLaunch → магазин → сюда); флаг снимается всегда
	if RunManager.landing_pending:
		RunManager.landing_pending = false
		if not RunManager.test_mode and not BattleManager.battle_in_progress and DisplayServer.get_name() != "headless":
			BattleLanding.play(self, camera,
				Palette.LANDING_CLOUD_CHAOS if RunManager.player_faction == "chaos" else Palette.LANDING_CLOUD)
			_citadel_appear(CITADEL_APPEAR_DELAY)   # цитадель появляется, когда облака расходятся
	if shop_phase:
		_open_shop()
		var tut_event := "pick"
		if RunManager.is_start_pick_active():
			tut_event = "pick_start"
		elif RunManager.is_shop_node_active():
			tut_event = "shop_open"   # первый магазин обучения: монеты и покупка орудия
		_tutorial_notify(tut_event)
	# Загрузили сохранение посреди боя: армия уже стоит как была — сразу в бой
	elif BattleManager.battle_in_progress:
		_show_message("Бой продолжается")
		_on_start_pressed.call_deferred()
	else:
		_tutorial_notify("placement")

# Появление цитадели (решение пользователя 25.11.2026: эффект только на первом поле забега, после посадки сквозь облака):
# цитадель скрыта, через delay вокруг площадки идёт эффект (BuildingFx.citadel_spawn), на кадре 4 цитадель проявляется и
# встаёт на место (поднимается на CITADEL_RISE_PX). Только вид, бой и расстановка не ждут
const CITADEL_APPEAR_DELAY: float = 1.1    # с после посадки — облака уже расходятся
const CITADEL_REVEAL_AT: float = 0.35      # с после начала эффекта (кадр 4 из 16 при 12 к/с)
const CITADEL_REVEAL_TIME: float = 0.8
const CITADEL_RISE_PX: float = 12.0
func _citadel_appear(delay: float) -> void:
	var cit: Node2D = BattleManager.citadel
	if cit == null or not is_instance_valid(cit):
		return
	var home := cit.position
	cit.modulate.a = 0.0
	cit.position = home + Vector2(0.0, CITADEL_RISE_PX)
	var reveal := func():
		if not is_instance_valid(cit):
			return
		var tw := create_tween().set_parallel(true)
		tw.tween_property(cit, "modulate:a", 1.0, CITADEL_REVEAL_TIME)
		tw.tween_property(cit, "position", home, CITADEL_REVEAL_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var start := func():
		if not is_instance_valid(cit):
			return
		BuildingFx.citadel_spawn(cit.global_position)
		get_tree().create_timer(CITADEL_REVEAL_AT, false).timeout.connect(reveal)
	if delay <= 0.0:
		start.call()
	else:
		get_tree().create_timer(delay, false).timeout.connect(start)

# Обучение «Козёл учит» (Tutorial): подсказка продавца по событию, если оно идёт
var tutorial: Tutorial = null

func _tutorial_notify(event: String, ctx: Variant = null) -> void:
	if tutorial != null and is_instance_valid(tutorial):
		tutorial.wave = battle_wave
		tutorial.notify(event, ctx)

func _tutorial_live() -> bool:
	return tutorial != null and is_instance_valid(tutorial)

# Шаг обучения завершён: бой снова можно запускать, в руке две карты — начнётся сам
func tutorial_release() -> void:
	if is_placement_phase and not shop_phase:
		_auto_start_if_hand_low()

func _build_ui() -> void:
	var bg_layer = CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	bg_layer.add_child(UITheme.make_background())
	# Цветокоррекция мира — слой 1 перед UI в дереве: UI того же слоя рисуется позже и не тонируется
	var grade := WorldGrade.new()
	add_child(grade)
	move_child(grade, $UI.get_index())

	bench = BENCH_SCENE.instantiate()
	add_child(bench)
	bench.setup(BattleManager.pending_cards)
	bench.card_dropped_on_tile.connect(_on_card_dropped)
	bench.card_hovered.connect(_on_bench_card_hovered)

	hud = BattleHud.new()
	$UI.add_child(hud)
	var wave_parts: Array[String] = []   # номер волны — на ленте шапки, здесь только тип боя и сложность
	if battle_type != RunMapNode.BATTLE:
		wave_parts.append(UITheme.NODE_NAMES.get(battle_type, battle_type))
	wave_parts.append(Difficulty.level_name(RunManager.difficulty))
	if RunManager.test_mode:
		wave_parts.append("ТЕСТ")
	var wave_text := " · ".join(wave_parts)
	hud.setup(wave_text, result_label, start_button)
	hud.set_message("Расставьте отряды" + (" · в руке останется %d карты" % BattleManager.MIN_HAND_CARDS if _hand_floor_applies() else ""))
	start_button.pressed.connect(_on_start_pressed)

	inspector = SquadInspector.new()
	inspector.click_blocker = _artillery_takes_click
	inspector.building_finder = func(world: Vector2) -> Building:
		return _get_player_building_at(iso_grid.screen_to_tile(world))
	# Справка — между плашкой сообщения и рукой на расстановке, не поверх них
	inspector.top_limit = hud.message_bottom
	inspector.bottom_limit = func() -> float:
		return get_viewport().get_visible_rect().size.y - (UITheme.BENCH_PEEK if is_placement_phase else 0.0)
	$UI.add_child(inspector)
	inspector.squad_info_opened.connect(func(_squad): _tutorial_notify("squad_info"))
	if RunManager.test_mode:
		_build_test_panel()
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	hud.pause_toggled.connect(pause_menu.toggle_quick_pause)   # кнопка паузы в шапке — то же, что пробел
	pause_menu.quick_pause_changed.connect(hud.set_paused)
	# Камера мышью — отдельным узлом, работает и на паузе (пробел — осмотреть поле)
	var camera_input := CameraInput.new()
	camera_input.handler = _handle_camera_input
	add_child(camera_input)
	GameSettings.changed.connect(_apply_battle_speed)
	BattleManager.battle_ended.connect(_on_battle_ended)
	if shop_phase:   # под магазином — только поле: шапка боя, справка и рука появятся с расстановкой
		$UI.visible = false
		bench.visible = false

func _build_field() -> void:
	# Бойцы рисуются по глубине: кто ниже на экране — тот ближе
	units_container.y_sort_enabled = true
	# Шрамы поля — подпалины и кровь до конца боя, на земле под тенями (только вид)
	var scars := ScarLayer.new()
	add_child(scars)
	move_child(scars, units_container.get_index())
	scars.setup()
	# Тени и кольца бойцов — одним слоем под отрядами (SoldierShadows)
	var shadows := SoldierShadows.new()
	add_child(shadows)
	move_child(shadows, units_container.get_index())
	shadows.setup(units_container)
	# Пыль из-под ног — на земле под отрядами, над тенями (только вид)
	var dust := DustLayer.new()
	add_child(dust)
	move_child(dust, units_container.get_index())
	dust.setup(FactionTheme.current())
	# След снарядов — один слой над бойцами (только вид)
	units_container.get_parent().add_child(ProjectileTrail.new())
	iso_grid.set_unlocked_tiles(BattleManager.kingdom_tiles)
	iso_grid.setup()
	renderer = IsoGridRenderer.new()
	renderer.setup(iso_grid)
	grid_renderer.add_child(renderer)
	SideCritters.spawn(units_container, renderer, iso_grid)   # существа по краям поля (только вид)
	if FactionTheme.current().has("field_wall"):   # стена края поля кодом (только вид)
		FieldWall.build(units_container, iso_grid, FactionTheme.current()["field_wall"])
	AuraRing.layer = renderer   # кольца аур — на земле, под бойцами
	# Здания и цитадель полупрозрачны, пока за ними стоят бойцы (только расстановка)
	fader = OcclusionFader.new()
	add_child(fader)
	camera = BattleCamera.new()
	add_child(camera)
	camera.make_current()
	reticle = ArtilleryReticle.new()
	reticle.camera = camera
	add_child(reticle)
	# Пепел / угли в воздухе над всем полем (только вид)
	var atmosphere := Atmosphere.new()
	add_child(atmosphere)
	atmosphere.setup(iso_grid.get_world_bounds().grow(300.0), FactionTheme.current().get("atmosphere", ""), WorldGrade.mood())
	_fit_camera(false)
	get_viewport().size_changed.connect(_fit_camera.bind(false))

func _populate_field() -> void:
	Soldier.preload_frames(BattleManager.player_units.map(func(d): return d.sprite_path))
	_spawn_citadel()
	_place_enemy_squads()
	_place_player_buildings()
	_build_kingdom_wall(false)
	_place_player_squads()
	for tile in BattleManager.armed_tiles:   # «Продолжить»: заряженный удар — метка снова на своей клетке
		_strike_marks.append(TileGlow.target(renderer, "strike", iso_grid.tile_to_screen(tile)))
	_update_synergy_preview()
	_update_expansion()
	# Этап расширения объявлен экраном ещё до магазина (решение пользователя) — здесь подсказка в шапке;
	# финальный бой — сначала кто ждёт за туманом (примарх и его приём)
	var boss := _final_boss_note()
	if BattleManager.can_expand_kingdom() and not iso_grid.get_expansion_tiles().is_empty():
		hud.set_message(boss + "Этап расширения: клетки рядом с королевством — от %s, клик по клетке с ценой"
			% GameConstants.coins(BattleManager.get_tile_cost()))
	elif BattleManager.next_battle_note != "":
		hud.set_message(boss + BattleManager.next_battle_note)
	elif boss != "":
		hud.set_message(boss.trim_suffix(". "))

# «Финальная битва: <босс> (приём). » — для шапки расстановки; не финальный бой — ""
func _final_boss_note() -> String:
	for squad in SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_ENEMY):
		var d: UnitData = squad.data
		if EnemyWaves.BOSS_TITLES.has(d.factory_id):
			return "Финальная битва: %s — «%s». " % [EnemyWaves.BOSS_TITLES[d.factory_id], d.special_name]
	return ""

func _get_play_area() -> Rect2:
	var screen = get_viewport_rect().size
	var top = UITheme.HUD_HEIGHT
	var bottom = screen.y
	var left := 0.0
	if is_placement_phase and not shop_phase:   # под магазином руки расстановки нет — поле на весь экран
		bottom -= UITheme.BENCH_PEEK
		if test_panel:   # поле — правее панели тестового режима
			left = TestPanel.WIDTH + TestPanel.MARGIN
	return Rect2(left + PLAY_AREA_MARGIN, top + PLAY_AREA_MARGIN,
		screen.x - left - PLAY_AREA_MARGIN * 2.0, bottom - top - PLAY_AREA_MARGIN * 2.0)

func _fit_camera(animate: bool) -> void:
	camera.fit(iso_grid.get_world_bounds(), _get_play_area(), is_placement_phase, animate)

func _screen_to_world(p: Vector2) -> Vector2:
	return camera.screen_to_world(p)

func _world_to_screen(p: Vector2) -> Vector2:
	return camera.world_to_screen(p)

# -------------------------------------------------------
# ПОЛЕ: цитадель, здания, отряды
# -------------------------------------------------------
# Цитадель — в общем контейнере юнитов, чтобы сортироваться по глубине с бойцами
func _spawn_citadel() -> void:
	var citadel = Citadel.new()
	citadel.position = iso_grid.tile_to_screen(iso_grid.citadel_tile)
	units_container.add_child(citadel)
	BattleManager.citadel = citadel

# Здания стоят на своих клетках между раундами (стена владений — не на клетке: _build_kingdom_wall)
func _place_player_buildings() -> void:
	BattleManager.buildings.clear()
	for card in BattleManager.player_buildings:
		if card.building_type == "wall":
			BattleManager.player_buildings[card] = BattleManager.WALL_TILE
			continue
		var tile: Vector2i = BattleManager.player_buildings[card]
		if iso_grid.is_valid_tile(tile) and not _is_tile_occupied(tile):
			_spawn_building(card, tile)

# Стена вокруг владений (KingdomWall) — по карте стены забега; каждый бой — целая. rising — вырастает из земли
func _build_kingdom_wall(rising: bool) -> void:
	if BattleManager.has_kingdom_wall():
		BattleManager.kingdom_wall.queue_free()
	BattleManager.kingdom_wall = null
	var card := BattleManager.get_wall_card()
	if card:
		BattleManager.kingdom_wall = KingdomWall.build(units_container, iso_grid, card, rising)

func _spawn_building(card: CardData, tile: Vector2i) -> Building:
	var building = Building.new()
	building.setup(card, tile)
	building.position = iso_grid.tile_to_screen(tile)
	units_container.add_child(building)
	BattleManager.buildings.append(building)
	renderer.set_occupied(tile, true)
	return building

# Один UnitData = один отряд; без сохранённой клетки — первая свободная
func _place_player_squads() -> void:
	var free_tiles = iso_grid.get_all_tiles()
	var tile_index = 0
	for unit_data in BattleManager.player_units:
		var count = unit_data.saved_hp.size()
		if count == 0:
			continue
		var tile: Vector2i = BattleManager.player_placements.get(unit_data, IsoGrid.NO_TILE)
		if not iso_grid.is_valid_tile(tile) or _is_tile_occupied(tile):
			while tile_index < free_tiles.size() and _is_tile_occupied(free_tiles[tile_index]):
				tile_index += 1
			if tile_index >= free_tiles.size():
				break
			tile = free_tiles[tile_index]
		var squad := _spawn_squad(unit_data, GameConstants.TEAM_PLAYER, tile, count, unit_data.saved_hp, unit_data.saved_kinds)
		if unit_data.respawned:   # пал целиком, бой выигран — возродился: свет появления на бойцах
			unit_data.respawned = false
			_glow_soldiers.call_deferred(squad, "arrive")
		if unit_data.level_lost:   # и уровнем ниже — шеврон трескается
			unit_data.level_lost = false
			BuildingFx.level_down.call_deferred(squad)
		if unit_data.fresh_converted > 0:   # павшие встали бойцами бога (Святилище культа) — знак бога под ними
			_show_god_sigils.call_deferred(squad, unit_data.fresh_converted)
			unit_data.fresh_converted = 0

# Знак бога под последними count бойцами бога в отряде (новые — дописаны в конец состава)
func _show_god_sigils(squad: Squad, count: int) -> void:
	if not is_instance_valid(squad):
		return
	var order := 0
	for i in range(squad.soldiers.size() - 1, -1, -1):
		var s = squad.soldiers[i]
		if order >= count:
			break
		if is_instance_valid(s) and s.convert_kind != "":
			BuildingFx.god_sigil(s, ChaosGods.default_god(s.convert_kind.split(":")[0]), order)
			order += 1

# Благословение и смена бога отряда (EFFECTS_NEEDED 4.11, кодом 09.11.2026; было — свет появления): знак бога
# загорается под каждым бойцом по очереди
func _bless_sigils(squad: Squad) -> void:
	var god: String = squad.data.get_god()
	var order := 0
	for s in squad.soldiers:
		if is_instance_valid(s):
			BuildingFx.god_sigil(s, god, order)
			order += 1

# Выход отряда врага на «В БОЙ» (решение пользователя 09.11.2026, было — враги просто возникали): Хаос — из
# разлома варпа (BuildingFx.rift), Космодесант (забег за Хаос) — высадка телепортом (лист Deep Strike); отряд
# проявляется по очереди (ENEMY_ARRIVAL_STAGGER). Только вид — враги уже на местах
const ENEMY_ARRIVAL_STAGGER: float = 0.07
const ENEMY_ARRIVAL_FADE: float = 0.45
func _enemy_arrival(squad: Squad, order: int) -> void:
	var wait := order * ENEMY_ARRIVAL_STAGGER
	if FactionTheme.enemy_of(RunManager.player_faction) == "chaos":
		BuildingFx.rift(squad.global_position, Soldier.TARGET_SPRITE_HEIGHT * squad.data.sprite_scale, wait)
	else:
		# Не на каждого бойца: сотни листов в один кадр (волна 15) — вид тот же, лист один на 3 бойцов
		for i in range(0, squad.soldiers.size(), 3):
			var s = squad.soldiers[i]
			if is_instance_valid(s):
				Vfx.spawn(units_container, "teleport", s.global_position, s.data.sprite_scale * Soldier.EFFECT_SCALE)
	squad.modulate.a = 0.0
	var tw := squad.create_tween()
	tw.tween_interval(wait + 0.12)
	tw.tween_property(squad, "modulate:a", 1.0, ENEMY_ARRIVAL_FADE)

# Знаки бонусов над своими отрядами перед боем (решение пользователя 09.11.2026): синергия, ряд, орден / бог,
# командир — видно, что расстановка дала пользу. Те же условия, что у SynergyManager.apply_*
func _show_bonus_marks() -> void:
	var chapter: Dictionary = Chapters.get_chapter(RunManager.player_chapter)
	var order := 0
	for squad in SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER):
		var tags: Array = squad.data.tags
		var kinds: Array = []
		for syn in SynergyManager.active_synergies:
			var b: Dictionary = syn["bonus"]
			if syn["tag"] in tags and not b.has("epic_discount") and not b.has("income"):
				kinds.append("synergy")
				break
		var pos: String = SynergyManager.get_squad_position_bonus(squad)
		if pos != "":
			kinds.append("front" if pos == SynergyManager.FRONT else "back")
		if chapter.has("bonus") and (chapter.get("tag", "") == "" or chapter.get("tag", "") in tags):
			kinds.append("chapter")
		if squad.data.commander_damage_bonus > 0.0:
			kinds.append("commander")
		if not kinds.is_empty():
			BuildingFx.bonus_marks(squad, kinds, order * 0.05)
			order += 1

# Элитный враг пал (решение пользователя 09.11.2026; с 12.11.2026 — монетами): над ним подскакивают
# крутящиеся монеты (EconomyManager.BONUS_ELITE_KILL штук) и летят к счётчику в шапке — видно, за что бонус
# к доходу (начисляется в итоге боя)
const ELITE_KILL_SHAKE: float = 2.5
func elite_killed(world_point: Vector2) -> void:
	if hud == null or not is_inside_tree():
		return
	# вес гибели элиты: толчок, миг стоп-кадра и вспышка на земле (только вид)
	if camera:
		camera.shake(ELITE_KILL_SHAKE)
	hitstop()
	IsoGridRenderer.flash_light(world_point, Color(Palette.GOLD, 0.6), 90.0, 0.3)
	CoinFlight.burst($UI, [camera.world_to_screen(world_point)], hud.requisition_label(), EconomyManager.BONUS_ELITE_KILL)

# Доход по итогу боя (решение пользователя 12.11.2026: «с поля боя прилетают сами монетки, крутящиеся»):
# монеты подскакивают из бойцов, доживших до конца, и генераторов (нет — из центра экрана) и летят к счётчику;
# счётчик стоит на прежнем числе и прибавляет с каждой монетой (BattleHud.hold_requisition / coin_landed)
const INCOME_COINS_MIN: int = 3
const INCOME_COINS_MAX: int = 14
const INCOME_PER_COIN: int = 2
func _income_coin_sources() -> Array:
	var points: Array = []
	var alive: Array = SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER)
	var step := maxi(1, alive.size() / INCOME_COINS_MAX)
	for i in range(0, alive.size(), step):
		points.append(camera.world_to_screen(alive[i].global_position))
	for b in BattleManager.buildings:
		if is_instance_valid(b) and b.stats.get("income", 0.0) > 0.0:
			points.append(camera.world_to_screen(b.global_position))
	if points.is_empty():
		points.append(get_viewport().get_visible_rect().size / 2.0)
	return points

func _fly_income_coins(sources: Array, from_value: int) -> void:
	var gained := EconomyManager.requisition - from_value
	if gained <= 0 or not is_inside_tree():
		hud.release_requisition()
		return
	var n := clampi(ceili(float(gained) / INCOME_PER_COIN), INCOME_COINS_MIN, INCOME_COINS_MAX)
	sources.shuffle()
	CoinFlight.burst($UI, sources, hud.requisition_label(), n, func(i: int):
		if not is_instance_valid(hud):
			return
		if i == n - 1:
			hud.release_requisition()
		else:
			hud.coin_landed(from_value + roundi(float(gained) * (i + 1) / n)))

# «В БОЙ» — полоса света вдоль передней кромки королевства (EFFECTS_NEEDED 8.4, кодом; только вид)
func _show_front_line() -> void:
	if BattleManager.kingdom_tiles.is_empty():
		return
	var u := -999
	var v0 := 999
	var v1 := -999
	for t in BattleManager.kingdom_tiles:
		u = maxi(u, t.x)
		v0 = mini(v0, t.y)
		v1 = maxi(v1, t.y)
	BuildingFx.battle_start(renderer, iso_grid.lattice_to_screen(u + 0.5, v0 - 0.5),
		iso_grid.lattice_to_screen(u + 0.5, v1 + 0.5), RunManager.player_faction == "chaos")

# Состав врагов — данными в EnemyWaves; заполняют зону с переднего края в тыл
func _place_enemy_squads() -> void:
	var tiles = iso_grid.get_enemy_tiles_front_first()
	var specs = EnemyWaves.build(battle_wave, battle_type, tiles.size(), RunManager.rng.seed, RunManager.difficulty,
		FactionTheme.enemy_of(RunManager.player_faction))
	# Тестовый режим: босс из панели — любой из 9 примархов, и чужой расы (посмотреть всех)
	if RunManager.test_mode and RunManager.test_boss != "" and battle_type == RunMapNode.BOSS and not specs.is_empty():
		specs[0]["unit"] = RunManager.test_boss
	if _tutorial_live():
		tutorial.wave = battle_wave
		if tutorial.is_training_battle():   # учебный бой: один слабый отряд — игрок побеждает
			specs = tutorial.training_specs(specs)
		elif tutorial.is_trial_battle() or tutorial.is_boss_battle():   # волна 5 — простые враги для орудия, волна 6 — слабый примарх
			specs = tutorial.scripted_specs(tiles.size())
	enemy_elites_at_start = 0
	# Строй врага, как у игрока (построение перед боем): ближний бой — в передние клетки зоны, стрелки — в задние;
	# внутри групп — порядок волны (EnemyWaves: босс и танки впереди)
	var front: Array = []
	var back: Array = []
	for i in range(mini(specs.size(), tiles.size())):
		var spec: Dictionary = specs[i]
		var enemy_data = UnitFactory.create(spec["unit"])
		enemy_data.attack_range = minf(enemy_data.attack_range, EnemyWaves.MAX_ENEMY_RANGE)
		enemy_data.hp_multiplier = spec["mult"] * BattleManager.next_battle_enemy_hp   # событие забега
		enemy_data.damage_multiplier = spec["mult"]
		var is_back: bool = enemy_data.attack_range > DEPLOY_BACK_RANGE or enemy_data.heal_per_second > 0.0
		(back if is_back else front).append([enemy_data, spec["count"]])
	var placed: Array = front + back
	Soldier.preload_frames(placed.map(func(p): return p[0].sprite_path))
	for i in placed.size():
		var enemy_data: UnitData = placed[i][0]
		_spawn_squad(enemy_data, GameConstants.TEAM_ENEMY, tiles[i], placed[i][1])
		if "elite" in enemy_data.tags:
			enemy_elites_at_start += placed[i][1]

func _spawn_squad(unit_data: UnitData, team: int, tile: Vector2i, count: int, hp_list: Array[float] = [],
		kinds: Array[String] = []) -> Squad:
	var is_enemy = team == GameConstants.TEAM_ENEMY
	var squad = SQUAD_SCENE.instantiate()
	units_container.add_child(squad)
	squad.setup(unit_data, team, tile, count, hp_list, kinds)
	squad.global_position = iso_grid.tile_to_screen(tile, is_enemy)
	SquadRegistry.register(squad)
	# Враг скрыт до начала боя — игрок расставляется вслепую
	if is_enemy and is_placement_phase:
		squad.visible = false
	renderer.set_occupied(tile, true, is_enemy)
	if not is_enemy and is_placement_phase:
		_update_synergy_preview()
	return squad

func _is_tile_occupied(tile: Vector2i) -> bool:
	return renderer.occupied_tiles_player.has(tile)

func _get_player_squad_at(tile: Vector2i) -> Squad:
	for squad in SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER):
		if squad.tile == tile:
			return squad
	return null

# -------------------------------------------------------
# ВВОД: подсветка клеток, покупка клеток королевства (каждая 3-я волна)
# -------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# В конце кадра: к тому времени окно знает, над интерфейсом ли курсор (gui_get_hovered_control)
		_update_building_hover.call_deferred(event.position)
	if not is_placement_phase or shop_phase:
		return
	if event is InputEventMouseMotion:
		renderer.update_hover(iso_grid.screen_to_tile(_screen_to_world(event.position)))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_buy_tile(iso_grid.screen_to_tile(_screen_to_world(event.position)))

# Здание под курсором (и на расстановке, и в бою) — только по его клетке (решение пользователя: моделька
# над чужой клеткой не в счёт): подсказка — что за здание, уровень, что делает; оно не гаснет
# (OcclusionFader.pinned); на расстановке — его зона действия (Building.get_effect_tiles).
# Тащим карту здания — зона действия от клетки под курсором, как если бы здание встало туда.
# Курсор над интерфейсом (скамейка, шапка) — ничего
func _update_building_hover(screen_pos: Vector2) -> void:
	if not is_inside_tree():   # отложенный вызов пришёл, когда сцена боя уже ушла (смена сцены)
		return
	var world = _screen_to_world(screen_pos)
	var tile = iso_grid.screen_to_tile(world)
	var dragging: CardData = bench.dragging_card
	var found: Building = null
	if dragging == null and get_viewport().gui_get_hovered_control() == null:
		for b in BattleManager.buildings:
			if is_instance_valid(b) and b.tile == tile:
				found = b
				break
	hovered_building = found
	# Открыта справка здания — оно не гаснет и его зона видна, пока курсор не на другом здании;
	# подсказка при наведении на него же не нужна — то же в справке
	var info: Building = inspector.info_building if is_instance_valid(inspector.info_building) else null
	var shown: Building = found if found else info
	fader.pinned = shown
	inspector.show_building_hover(found.describe() if found and found != info else "", screen_pos)
	var effect: Array[Vector2i] = []
	if dragging and dragging.card_type == "building" and iso_grid.is_valid_tile(tile):
		effect = Building.get_effect_tiles(dragging.building_type, tile)
	elif shown:
		effect = Building.get_effect_tiles(shown.building_type, shown.tile)
	renderer.set_effect_tiles(effect)
	_update_drag_target(dragging, tile)

# Ромб на клетке под перетаскиваемой картой (только вид): playable — ляжет на пустую клетку, compatible —
# на свой отряд / здание того же типа (уровень, лечение, карта-улучшение), invalid — сюда нельзя
var _drag_target: TileGlow = null
var _drag_target_key := ""
func _update_drag_target(card: CardData, tile: Vector2i) -> void:
	var kind := ""
	if card and is_placement_phase and iso_grid.is_valid_tile(tile):
		kind = _drop_verdict(card, tile)
	var key := "%s %s" % [kind, tile]
	if key == _drag_target_key:
		return
	_drag_target_key = key
	if is_instance_valid(_drag_target):
		_drag_target.dismiss()   # старый ромб тает, новый проявляется — перетекают с клетки на клетку
	_drag_target = null
	if kind != "":
		_drag_target = TileGlow.target(renderer, kind, iso_grid.tile_to_screen(tile))

func _drop_verdict(card: CardData, tile: Vector2i) -> String:
	var squad := _get_player_squad_at(tile)
	if card.card_type == "building" and card.building_type == "wall":   # стена — на любую клетку королевства
		var wall := BattleManager.get_wall_card()
		return "playable" if wall == null else ("compatible" if wall.can_level_up_building() else "invalid")
	match card.card_type:
		"squad", "building":
			# свой отряд / здание того же типа: ляжет, только если есть что улучшить или вылечить
			if get_same_card_tiles(card).has(tile):
				var takes: bool
				if card.card_type == "squad":
					takes = squad.data.can_merge_upgrade() or squad.is_wounded()
				else:
					var own := _get_player_building_at(tile)
					takes = own != null and own.card.can_level_up_building()
				return "compatible" if takes else "invalid"
		"upgrade":
			return "compatible" if squad and squad.data.can_apply_upgrade(card) else "invalid"
		"event":
			if card.event_type == "orbital_strike":
				return "playable"
	return "invalid" if _is_tile_occupied(tile) else "playable"

# -------------------------------------------------------
# МАГАЗИН ПОВЕРХ ПОЛЯ
# -------------------------------------------------------
func _open_shop() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ShopLayer"
	layer.layer = SHOP_LAYER
	add_child(layer)
	# Шаг PICK — окно выбора карты (CardPickScene), иначе магазин; оба — embedded и сигнал finished
	shop = (PICK_SCENE if RunManager.is_pick_node_active() else SHOP_SCENE).instantiate()
	if RunManager.is_start_pick_active() and Tutorial.scripted_active() and GameSettings.tutorial_stage <= Tutorial.Stage.INTRO:
		shop.set("hold_deal", true)   # обучение: сперва поле и цитадель, карты — на реплике про шесть карт
	shop.set("embedded", true)   # до _ready: своей паузы и фона не будет, «В БОЙ» / «ДАЛЕЕ» — сигнал finished
	layer.add_child(shop)
	shop.connect("finished", _on_shop_finished)

# «В БОЙ» магазина: шаг магазина завершён (ShopScene), рука — в BattleManager.pending_cards; шаг боя — текущий,
# магазин тает, поле — расстановка. Следующий шаг не бой (не бывает в цепочке) — как раньше, со сменой сцены
func _on_shop_finished() -> void:
	if not RunManager.enter_battle_in_place():
		RunManager.advance()
		return
	shop_phase = false
	var old := shop
	shop = null
	old.propagate_call("set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])
	# Магазин разъезжается (ShopScene.play_exit: вывеска вверх, карты влево, рука вниз, продавец вправо), в конце
	# остаток тает
	var slide: float = old.play_exit() if old.has_method("play_exit") else 0.0
	if slide > 0.0:   # надписи шапки боя — после того, как погасли надписи шапки магазина (планка у них одна)
		hud.modulate.a = 0.0
		var hw := hud.create_tween()
		hw.tween_interval(SHOP_SCENE_SCRIPT.HUD_TEXT_FADE)
		hw.tween_property(hud, "modulate:a", 1.0, SHOP_FADE_TIME)
	var tw := old.create_tween()
	tw.tween_interval(maxf(slide - SHOP_FADE_TIME * 0.5, 0.0))
	tw.tween_property(old, "modulate:a", 0.0, SHOP_FADE_TIME)
	tw.tween_callback(old.get_parent().queue_free)
	battle_type = RunManager.get_battle_type()
	battle_wave = RunManager.get_battle_wave()
	AudioManager.play_music("battle")
	bench.setup(BattleManager.pending_cards)
	# Рука боя (скамейка) появляется, когда рука магазина уже уехала вниз (решение пользователя 16.11.2026: пока магазин
	# закрывался, в руке игрока была видна вторая пачка карт — скамейка раньше времени поверх уезжающей руки магазина)
	if slide > 0.0:
		bench.visible = false
		var bw := create_tween()
		bw.tween_interval(slide)
		bw.tween_callback(_show_bench_after_shop)
	else:
		bench.visible = true
	$UI.visible = true
	_update_expansion()
	_fit_camera(true)
	SaveManager.save_run()
	_tutorial_notify("placement")

func _show_bench_after_shop() -> void:
	if not is_instance_valid(bench) or BattleManager.is_battle_running():
		return
	bench.visible = true   # Bench — CanvasLayer: прозрачности у него нет, карты появляются сразу

# Этап расширения объявляется экраном в конце боя перед волной расширения — до магазина
# (решение пользователя: успеть отложить Req на клетки). Дальше — по кнопке «В магазин»
func _announce_expansion() -> void:
	AudioManager.play("expansion")
	_tutorial_notify("expansion")
	expansion_banner = ExpansionBanner.new()
	$UI.add_child(expansion_banner)
	# Кнопка всегда «ДАЛЕЕ» (решение пользователя 19.11.2026): магазина после каждой волны нет — дальше выбор карты / событие
	expansion_banner.setup(BattleManager.get_tile_cost(), "ДАЛЕЕ")
	expansion_banner.closed.connect(RunManager.advance)

# Следующая волна — с расширением, и есть что купить (рамка королевства не заполнена)
func _expansion_ahead() -> bool:
	return BattleManager.is_expansion_wave(EconomyManager.round_number) and not iso_grid.get_expansion_tiles().is_empty()

func _update_expansion() -> void:
	var tiles: Array[Vector2i] = []
	if is_placement_phase and not shop_phase and BattleManager.can_expand_kingdom():
		tiles = iso_grid.get_expansion_tiles()
	renderer.set_expansion(tiles, BattleManager.get_tile_cost())

func _try_buy_tile(tile: Vector2i) -> void:
	if not BattleManager.can_expand_kingdom() or not iso_grid.get_expansion_tiles().has(tile):
		return
	var cost = BattleManager.get_tile_cost()
	if not BattleManager.try_buy_tile(tile):
		AudioManager.play("no_money")
		_show_message("Не хватает монет: клетка стоит %s" % GameConstants.coins(cost))
		return
	iso_grid.set_unlocked_tiles(BattleManager.kingdom_tiles)
	_update_expansion()
	AudioManager.play("tile_bought")
	TileGlow.burst(renderer, iso_grid.tile_to_screen(tile))
	_show_message("Королевство расширено (−%s), клеток: %d" % [GameConstants.coins(cost), BattleManager.kingdom_tiles.size()])
	_update_synergy_preview()   # новый ряд меняет, кто впереди и сзади
	_save_placement()

# -------------------------------------------------------
# КАРТЫ СО СКАМЕЙКИ
# -------------------------------------------------------
func _on_card_dropped(card: CardData, screen_pos: Vector2) -> void:
	_update_drag_target(null, Vector2i.ZERO)   # карту отпустили — ромб под ней гаснет
	if not is_placement_phase:
		return
	var tile = iso_grid.screen_to_tile(_screen_to_world(screen_pos))
	if not iso_grid.is_valid_tile(tile):
		_show_message("Мимо сетки")
		return
	var handler: Callable = _card_handlers.get(card.card_type, Callable())
	if not handler.is_valid():
		_show_message("%s: эту карту нельзя сыграть на поле" % card.display_title())
		return
	if _tutorial_live() and not tutorial.allow_drop(card, tile):   # обучение: пока есть цель — только она и её клетка
		return
	if _hand_floor_applies() and BattleManager.pending_cards.size() <= BattleManager.MIN_HAND_CARDS:
		_show_message("В руке должны остаться %d карты — «В БОЙ»" % BattleManager.MIN_HAND_CARDS)
		return
	if handler.call(card, tile):
		AudioManager.play("place")
		_consume_bench_card(card)
		_tutorial_notify("card_played", card)
		_auto_start_if_hand_low()

# Правило минимальной руки (решение пользователя 17.11.2026) действует везде, кроме тестового режима и расстановки
# перед финальным боссом (волна 15 — BOSS): там можно сыграть всё
func _hand_floor_applies() -> bool:
	if _tutorial_live() and tutorial.exempts_hand_floor():   # обучение ведёт карту (орудие) на клетку — рука может опустеть
		return false
	return not RunManager.test_mode and battle_type != RunMapNode.BOSS

# Сыграна карта, в руке осталось MIN_HAND_CARDS — бой начинается сам (после короткой паузы: карта «приземляется»)
func _auto_start_if_hand_low() -> void:
	if not _hand_floor_applies() or _auto_start_pending or BattleManager.pending_cards.size() > BattleManager.MIN_HAND_CARDS:
		return
	if _tutorial_live() and (tutorial.holds_start() or tutorial.no_auto_start()):   # обучение: бой — только кнопкой «В БОЙ»
		return
	_auto_start_pending = true
	_show_message("В руке %d карты — бой начинается" % BattleManager.MIN_HAND_CARDS)
	get_tree().create_timer(AUTO_START_DELAY, false).timeout.connect(_auto_start_fire, CONNECT_ONE_SHOT)

func _auto_start_fire() -> void:
	_auto_start_pending = false
	if is_inside_tree() and is_placement_phase and not shop_phase and not BattleManager.is_battle_running():
		_on_start_pressed()

# Отряд на пустую клетку; на свой отряд того же типа — улучшение с лечением (_merge_squad)
func _play_squad_card(card: CardData, tile: Vector2i) -> bool:
	var own = _get_player_squad_at(tile)
	if own and own.data.factory_id == card.unit_factory_id:
		return _merge_squad(card, own)
	if _is_tile_occupied(tile):
		_show_message("Тайл занят")
		return false
	var unit_data = UnitFactory.create(card.unit_factory_id)
	unit_data.squad_size = card.unit_count
	unit_data.squad_growth = UnitFactory.squad_growth_for(card)
	var squad := _spawn_squad(unit_data, GameConstants.TEAM_PLAYER, tile, card.unit_count)
	if RunManager.test_mode:   # тест: отряд сразу нужного уровня (как слиянием — с пополнением бойцов)
		for i in RunManager.test_level:
			squad.merge_upgrade()
	_materialize(squad)
	return true

# Улучшение бросают НА свой отряд
func _play_upgrade_card(card: CardData, tile: Vector2i) -> bool:
	var squad = _get_player_squad_at(tile)
	if squad == null:
		_show_message("%s: перетащите на свой отряд" % card.display_title())
		return false
	if card.upgrade_type in ["blessing", "change_god"]:
		return _play_god_card(card, squad)
	if not squad.apply_upgrade(card):
		_show_message("%s: не подходит этому отряду (только «%s», знамя не складывается)" % [card.display_title(), card.affects_tag])
		return false
	# Знак карты над отрядом (у Хаоса — свои id карт: daemonic_armour, icon_of_chaos…)
	Vfx.spawn(units_container, "upgrade_" + card.id, squad.global_position + UPGRADE_FX_RISE)
	_show_message("%s → %s (%s)" % [card.display_title(), squad.data.display_name(), card.description])
	return true

# Карты богов Хаоса (ChaosGods, решение пользователя 25.10.2026): благословение — только на отряд своего бога, до 3 раз;
# «Chaos Gods' Blessing» — на любой отряд Хаоса (и Common без бога): окно выбора бога, карта уходит из руки по выбору
# (Отмена — остаётся)
func _play_god_card(card: CardData, squad: Squad) -> bool:
	var god: String = squad.data.get_god()
	if not "chaos" in squad.data.tags:
		_show_message("%s: только на отряд Кровоподписантов" % card.display_title())
		return false
	if card.upgrade_type == "change_god":
		var dialog := GodPickDialog.new()
		$UI.add_child(dialog)
		dialog.setup(squad.data.display_name(), god)
		dialog.chosen.connect(_on_god_chosen.bind(card, squad))
		return false   # карта уйдёт из руки, когда бог выбран (_on_god_chosen)
	if god == "":
		_show_message("%s: у отряда нет бога — сначала «Recasting»" % card.display_title())
		return false
	if card.blessing_god != god:
		_show_message("%s: только на отряд бога %s (у этого — %s)" % [card.display_title(), ChaosGods.god_name(card.blessing_god),
			ChaosGods.god_name(god)])
		return false
	if squad.data.blessings >= ChaosGods.MAX_BLESSINGS:
		_show_message("%s: у отряда уже %d/%d благословений" % [card.display_title(), squad.data.blessings, ChaosGods.MAX_BLESSINGS])
		return false
	if not squad.apply_upgrade(card):   # Вестник — только стрелкам
		_show_message("%s: действует только на стрелков" % card.display_title())
		return false
	_bless_sigils(squad)
	_show_message("%s → %s: %s" % [card.display_title(), squad.data.display_name(),
		ChaosGods.describe(squad.data.get_god(), squad.data.blessings, squad.data.tags)])
	return true

func _on_god_chosen(new_god: String, card: CardData, squad: Squad) -> void:
	if not is_instance_valid(squad) or not is_placement_phase or not bench.bench_cards.has(card):
		return
	squad.data.change_god(new_god)
	for s in squad.soldiers:
		s.refresh_stats_from_data()
	_bless_sigils(squad)
	AudioManager.play("place")
	_show_message("%s теперь служит богу %s" % [squad.data.display_name(), ChaosGods.god_name(new_god)])
	_consume_bench_card(card)

# Здание на пустую клетку; такая же карта на своё здание — уровень +1. Стена владений — на любую клетку
func _play_building_card(card: CardData, tile: Vector2i) -> bool:
	if card.building_type == "wall":
		return _play_wall_card(card)
	var own = _get_player_building_at(tile)
	if own and own.card.id == card.id:
		if not own.card.level_up_building():
			_show_message("%s: максимальный уровень" % own.card.display_title())
			return false
		var from_scale: Vector2 = own.sprite.scale if own.sprite else Vector2.ONE
		own.refresh_stats()
		own.play_level_up(from_scale)
		TileGlow.burst(renderer, own.global_position, "level", own.card.faction)
		AudioManager.play("building_level_up")
		_show_message("%s улучшено до уровня %d/%d" % [own.card.display_title(), own.card.building_level, CardData.MAX_BUILDING_LEVEL])
		_tutorial_notify("building_level")
		return true
	if _is_tile_occupied(tile):
		_show_message("Тайл занят")
		return false
	if RunManager.test_mode:   # тест: здание сразу нужного уровня
		while card.building_level < 1 + RunManager.test_level and card.level_up_building():
			pass
	_materialize(_spawn_building(card, tile))
	BattleManager.player_buildings[card] = tile
	_show_message("Построено: %s" % card.display_title())
	return true

# Стена владений (решение пользователя 22.10.2026): клетку не занимает. Нет стены — вырастает по контуру,
# есть — уровень +1 (звенья крепче, щит больше)
func _play_wall_card(card: CardData) -> bool:
	var own := BattleManager.get_wall_card()
	if own:
		if not own.level_up_building():
			_show_message("%s: максимальный уровень" % own.display_title())
			return false
		BattleManager.kingdom_wall.refresh_stats()
		BattleManager.kingdom_wall.flash_shield()
		_show_message("%s улучшена до уровня %d/%d" % [own.display_title(), own.building_level, CardData.MAX_BUILDING_LEVEL])
		_tutorial_notify("building_level")
		return true
	BattleManager.player_buildings[card] = BattleManager.WALL_TILE
	_build_kingdom_wall(true)
	AudioManager.play("tile_bought")
	_show_message("Возведена стена вокруг владений: %s" % card.display_title())
	return true

# Карты-события: подкрепление — сразу отряд; орбитальный удар — заряжается до боя
func _play_event_card(card: CardData, tile: Vector2i) -> bool:
	match card.event_type:
		"reinforcements":
			if _is_tile_occupied(tile):
				_show_message("%s: нужна пустая клетка" % card.display_title())
				return false
			# Своя случайность (забег, шаг, клетка): общий RunManager.rng не сдвигается — наборы магазина те же
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([RunManager.rng.seed, RunManager.current_node_id, tile])
			var squad_card = CardFactory.random_squad_card(card.event_stats.get("rarity", "common"), rng)
			var unit_data = UnitFactory.create(squad_card.unit_factory_id)
			unit_data.squad_size = squad_card.unit_count
			unit_data.squad_growth = UnitFactory.squad_growth_for(squad_card)
			_materialize(_spawn_squad(unit_data, GameConstants.TEAM_PLAYER, tile, squad_card.unit_count))
			_show_message("Подкрепление: %s" % squad_card.title)
			return true
		"orbital_strike":
			BattleManager.armed_events.append(card.id)
			BattleManager.armed_tiles.append(tile)
			_strike_marks.append(TileGlow.target(renderer, "strike", iso_grid.tile_to_screen(tile)))
			_show_message("Орбитальный удар наведён: ударит в начале боя")
			return true
	return false

# Карта легла на клетку — моделька проявляется (решение пользователя 21.10.2026: на поле кладут карту, а не
# модельку): вырастает из клетки — на каждом бойце свет телепорта (LevelUpGlow "arrive", у Хаоса — бордо), под
# зданием волна света по клетке (TileGlow "build"); решение пользователя 22.10.2026: столбы и «вата» пакета
# выбивались из стиля. Только вид, расстановка
const SPAWN_TIME: float = 0.3
const SPAWN_FROM_SCALE: float = 0.35
var _spawn_tweens: Array[Tween] = []   # «В БОЙ» раньше конца — доводим сразу (масштаб отряда сдвигает бойцов)
var _strike_marks: Array = []          # метки Orbital Strike на клетках (TileGlow) — до «В БОЙ»
var _drop_pods: Array = []             # капсулы в полёте / раскрытии — «В БОЙ» доводит сразу (DropPod.finish)
func _materialize(node: Node2D) -> void:
	# Отряд Космодесанта на пустую клетку — прилетает в десантной капсуле (решение пользователя 12.11.2026,
	# ART_TZ_DROP_POD_2026-11-12.txt): пока капсула падает и раскрывается, отряда не видно; виден — с кадра,
	# когда падают двери (DropPod.REVEAL_FRAME), дальше — как обычно (вырастает из клетки). Хаос — разлом варпа
	if node is Squad and node.team == GameConstants.TEAM_PLAYER:
		var chaos: bool = RunManager.player_faction == "chaos"
		if not chaos and DropPod.available():
			node.modulate.a = 0.0
			_drop_pods = _drop_pods.filter(func(p): return is_instance_valid(p))
			_drop_pods.append(DropPod.drop(units_container, node.position, node.data.tags.has("vehicle"),
				_pod_exit.bind(node)))
			return
		if chaos:
			BuildingFx.rift(node.global_position, Soldier.TARGET_SPRITE_HEIGHT * node.data.sprite_scale * 1.6)
	_grow_in(node, true)

# Моделька вырастает из клетки и проявляется; glow — свет на бойцах / волна по клетке здания
func _grow_in(node: Node2D, glow: bool) -> void:
	if not is_instance_valid(node):
		return
	node.scale = Vector2(SPAWN_FROM_SCALE, SPAWN_FROM_SCALE)
	node.modulate.a = 0.0
	var tw := node.create_tween().set_parallel(true)
	_spawn_tweens = _spawn_tweens.filter(func(t: Tween): return t.is_valid())
	_spawn_tweens.append(tw)
	tw.tween_property(node, "scale", Vector2.ONE, SPAWN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, SPAWN_TIME * 0.6)
	if not glow:
		return
	if node is Building:
		TileGlow.burst(renderer, node.global_position, "build", node.card.faction)
	elif node is Squad:
		_glow_soldiers(node, "arrive")

# Выход из капсулы (решение пользователя 12.11.2026, стилизация «удар и выход»): двери упали — бойцы выбегают
# от дверей (чуть впереди центра клетки) на свои места в строю, по очереди, бегом; отряд виден сразу.
# «В БОЙ» раньше конца — твины доводятся (_spawn_tweens), бойцы на местах и в стойке
const POD_EXIT_TIME: float = 0.45
const POD_EXIT_STAGGER: float = 0.05
const POD_EXIT_FROM := Vector2(0.0, 6.0)   # точка дверей относительно клетки, px мира
const POD_EXIT_FADE: float = 0.12
func _pod_exit(squad: Squad) -> void:
	if not is_instance_valid(squad):
		return
	squad.scale = Vector2.ONE
	squad.modulate.a = 1.0
	var alive: Array = squad.soldiers.filter(func(s): return s.current_state != Soldier.State.DEAD)
	_spawn_tweens = _spawn_tweens.filter(func(t: Tween): return t.is_valid())
	for i in alive.size():
		var s: Soldier = alive[i]
		var target: Vector2 = s.position
		s.position = POD_EXIT_FROM
		s.modulate.a = 0.0
		var dist := target.distance_to(POD_EXIT_FROM)
		var tw := s.create_tween()
		_spawn_tweens.append(tw)
		tw.tween_interval(i * POD_EXIT_STAGGER)
		tw.tween_callback(func(): s.deploy_walk(dist / POD_EXIT_TIME, target - POD_EXIT_FROM))
		tw.tween_property(s, "modulate:a", 1.0, POD_EXIT_FADE)
		tw.parallel().tween_property(s, "position", target, POD_EXIT_TIME).set_trans(Tween.TRANS_SINE) 			.set_ease(Tween.EASE_OUT)
		tw.tween_callback(s.deploy_stand)

# Свет на каждом живом бойце отряда волной по строю (LevelUpGlow: появление, лечение)
func _glow_soldiers(squad: Squad, kind: String) -> void:
	var alive: Array = squad.soldiers.filter(func(s): return s.current_state != Soldier.State.DEAD)
	for i in alive.size():
		LevelUpGlow.play(alive[i], 0, float(i) / maxf(alive.size() - 1, 1.0), kind)

func _get_player_building_at(tile: Vector2i) -> Building:
	for b in BattleManager.buildings:
		if is_instance_valid(b) and b.tile == tile:
			return b
	return null

# Карта отряда на свой отряд того же типа (решение пользователя 21.10.2026, меню «улучшить / вылечить» убрано):
# уровень +1 (бойцы роста — с полным HP), затем лечение — живым доля max HP, павшие возвращаются с той же долей.
# На максимальном уровне — только лечение; отряд здоров и на максимуме — карта не тратится
func _merge_squad(card: CardData, squad: Squad) -> bool:
	var leveled := squad.merge_upgrade()
	if not leveled and not squad.is_wounded():
		_show_message("%s: максимальный уровень, отряд здоров" % squad.data.display_name())
		return false
	var revived := squad.heal_by_ratio(UnitFactory.get_merge_bonuses(squad.data.faction)["heal"])
	# Уровень — свет на каждом бойце (Squad.merge_upgrade → LevelUpGlow), только лечение — зелёный свет на бойцах
	if not leveled:
		_glow_soldiers(squad, "heal")
	var extra := ", вернулось бойцов: %d" % revived if revived > 0 else ""
	if leveled:
		_show_message("%s улучшен до уровня %d/%d и вылечен%s" % [squad.data.display_name(),
			squad.data.squad_level, UnitFactory.MAX_SQUAD_LEVEL, extra])
	else:
		_show_message("%s вылечен%s (уровень максимальный)" % [squad.data.display_name(), extra])
	_update_synergy_preview()
	_tutorial_notify("merge")
	return true

func _consume_bench_card(card: CardData) -> void:
	bench.bench_cards.erase(card)
	bench._populate()
	_save_placement()

# Армия с поля → забег и сохранение: «Продолжить» вернёт поле как было
func _save_placement() -> void:
	BattleManager.sync_army_from_squads(SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER))
	SaveManager.save_run()

# -------------------------------------------------------
# БОЙ
# -------------------------------------------------------
# Орудия игрока (Thunderfire Cannon): клик по полю в бою — залп готового орудия.
# _unhandled_input: клики по UI (шапка, кнопки) сюда не доходят
func _unhandled_input(event: InputEvent) -> void:
	if not BattleManager.is_battle_running() or not (event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	fire_artillery(_screen_to_world(event.position))

# Камера мышью (решение пользователя): колесо — зум к курсору, правая / средняя кнопка — тянуть.
# true — событие съедено. Зовёт CameraInput (PROCESS_MODE_ALWAYS — и на паузе)
class CameraInput extends Node:
	var handler: Callable
	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _unhandled_input(event: InputEvent) -> void:
		if handler.call(event):
			get_viewport().set_input_as_handled()

var _camera_dragging: bool = false
func _handle_camera_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			camera.zoom_at(event.position, 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
			return true
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_camera_dragging = event.pressed
			return true
	elif event is InputEventMouseMotion and _camera_dragging:
		# Кнопку отпустили над панелью (UI съел отпускание) — перетаскивание кончилось
		if not (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)):
			_camera_dragging = false
			return false
		camera.pan(event.relative)
		return true
	return false

# Клик в бою уйдёт на залп — справка по отряду его не трогает
func _artillery_takes_click() -> bool:
	if not BattleManager.is_battle_running():
		return false
	for b in BattleManager.buildings:
		if is_instance_valid(b) and b.is_artillery_ready():
			return true
	return false

# Залп первого готового орудия в точку (мир); false — готовых нет
func fire_artillery(point: Vector2) -> bool:
	for b in BattleManager.buildings:
		if is_instance_valid(b) and b.is_artillery_ready():
			return b.fire_at(point)
	return false

# Карта отряда / здания на скамейке под курсором — клетки такого же отряда / здания на поле
# подсвечены (только на расстановке): видно, куда бросить карту для улучшения или лечения
var _same_card_glows: Array = []
func _on_bench_card_hovered(card: CardData) -> void:
	var tiles: Array[Vector2i] = []
	if is_placement_phase:
		tiles = get_same_card_tiles(card)
	# Клетки светятся как под перетаскиваемой картой (TileGlow «compatible»; плоской заливки нет — 19.11.2026)
	for g in _same_card_glows:
		if is_instance_valid(g):
			g.dismiss()
	_same_card_glows.clear()
	for t in tiles:
		var glow := TileGlow.target(renderer, "compatible", iso_grid.tile_to_screen(t))
		if glow != null:
			_same_card_glows.append(glow)
	if card == null:   # карту бросили / курсор ушёл — зоны действия перетаскиваемой карты больше нет
		renderer.set_effect_tiles([] as Array[Vector2i])
	# Здание закрывает свою клетку — подсвечивается и само (modulate: прозрачность OcclusionFader — self_modulate)
	for b in BattleManager.buildings:
		if is_instance_valid(b):
			b.modulate = BUILDING_HIGHLIGHT if tiles.has(b.tile) else Color.WHITE
	# Карта стены — подсвечена стена владений (клетки у неё нет)
	if BattleManager.has_kingdom_wall():
		BattleManager.kingdom_wall.set_highlighted(is_placement_phase and card != null 			and card.card_type == "building" and card.building_type == "wall")

func get_same_card_tiles(card: CardData) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if card == null:
		return tiles
	match card.card_type:
		"squad":
			for squad in SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER):
				if squad.data.factory_id == card.unit_factory_id:
					tiles.append(squad.tile)
		"building":
			for b in BattleManager.player_buildings:
				if b.id == card.id and BattleManager.player_buildings[b] != BattleManager.WALL_TILE:
					tiles.append(BattleManager.player_buildings[b])
	return tiles

# deploy = false — армия сразу на местах построения, бой без хода (тесты)
func _on_start_pressed(deploy: bool = true) -> void:
	if deploy and _tutorial_live() and tutorial.holds_start():
		_show_message("Наставник просит сначала закончить урок")
		return
	for pod in _drop_pods:   # капсула ещё падает / раскрывается — отряд сразу на месте
		if is_instance_valid(pod):
			pod.finish()
	_drop_pods.clear()
	for tw in _spawn_tweens:   # моделька ещё растёт из клетки / бойцы выходят из капсулы — сразу на месте
		if tw.is_valid():
			tw.custom_step(SPAWN_TIME + POD_EXIT_TIME + POD_EXIT_STAGGER * 16.0)
	_spawn_tweens.clear()
	for mark in _strike_marks:   # удар — в начале боя, метка больше не нужна
		if is_instance_valid(mark):
			mark.queue_free()
	_strike_marks.clear()
	_update_drag_target(null, Vector2i.ZERO)
	is_placement_phase = false
	AudioManager.play("battle_start")
	if battle_type == RunMapNode.BOSS:
		AudioManager.play_music("boss")
	_on_bench_card_hovered(null)
	renderer.set_grid_overlay(false)   # в бою — только поле, здания, цитадель и бойцы
	fader.enabled = false
	start_button.disabled = true
	# Армия перед боем — в забег и в сохранение. До синергий: они меняют max_hp
	# бойцов только на этот бой и исказили бы доли HP
	BattleManager.battle_in_progress = true
	_save_placement()
	if RunManager.test_mode:   # после боя — та же расстановка
		RunManager.test_snapshot = BattleManager.save_state()
		test_panel.visible = false
	# Бой: прячем скамейку, камера отъезжает на всё поле
	bench.visible = false
	_fit_camera(true)
	_update_expansion()
	_intro_time = 0.0
	var arrival := 0
	for squad in SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_ENEMY):
		squad.visible = true
		var boss := false
		for s in squad.soldiers:
			s.reveal_boss()   # тень и кольцо примарха — только теперь (на расстановке выдали бы его)
			if s.data.special_kind != "":
				boss = true
			if deploy and s.data.special_kind != "":   # примарх выходит на поле, пока армия строится (только вид)
				_boss_intro(s)
		if not boss:   # у примарха свой выход
			_enemy_arrival(squad, arrival)
			arrival += 1
	_base_time_scale = Engine.time_scale
	_speed_applied = true
	_apply_battle_speed()
	Building.show_start_waves()   # волна от зданий к соседям — пока отряды на своих клетках
	_show_front_line()
	var slots := _deploy_slots(SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER))
	if not deploy:
		for squad in slots:
			squad.global_position = slots[squad]
		_begin_battle()
		return
	_deploy_army(slots)

# Места построения: линии поперёк оси наступления за передней стеной — впереди ближний бой, за ним стрелки
# и лекари; в линии — по ряду клетки (отряды не перебегают друг другу дорогу)
func _deploy_slots(squads: Array) -> Dictionary:
	var front: Array = []
	var back: Array = []
	for squad in squads:
		var d: UnitData = squad.data
		(back if d.attack_range > DEPLOY_BACK_RANGE or d.heal_per_second > 0.0 else front).append(squad)
	var by_row := func(a, b): return a.tile.y < b.tile.y or (a.tile.y == b.tile.y and a.tile.x > b.tile.x)
	front.sort_custom(by_row)
	back.sort_custom(by_row)
	# Отрядов в линии — столько, чтобы все линии уложились в DEPLOY_MAX_DEPTH (иначе передняя уходит в зону врага)
	var max_lines: int = int(DEPLOY_MAX_DEPTH / DEPLOY_LINE_STEP) + 1
	var per_line: int = DEPLOY_SLOTS
	while ceili(front.size() / float(per_line)) + ceili(back.size() / float(per_line)) > max_lines and per_line < DEPLOY_SLOTS_MAX:
		per_line += 1
	var lines: Array = []   # от передней к задней
	for group in [front, back]:
		for i in range(0, group.size(), per_line):
			lines.append(group.slice(i, i + per_line))
	var line_step: float = minf(DEPLOY_LINE_STEP, DEPLOY_MAX_DEPTH / maxf(lines.size() - 1, 1.0))
	line_step = maxf(line_step, DEPLOY_MIN_LINE_STEP)
	var slot_step: float = clampf(DEPLOY_MAX_WIDTH / maxf(per_line - 1, 1.0), DEPLOY_MIN_SLOT_STEP, DEPLOY_SLOT_STEP)
	var back_u: float = iso_grid.grid_width - 0.5 + DEPLOY_BACK_LINE
	var center_v: float = (IsoGrid.KINGDOM_FRAME_MIN.y + iso_grid.grid_height - 1) / 2.0
	var slots := {}
	for k in lines.size():
		var u: float = back_u + (lines.size() - 1 - k) * line_step
		var line: Array = lines[k]
		for j in line.size():
			var v: float = center_v + (j - (line.size() - 1) / 2.0) * slot_step
			slots[line[j]] = iso_grid.lattice_to_screen(u, v)
	return slots

# Ход на построение — только вид (бой не идёт: тиков нет); на паузе стоит, скорость боя ускоряет
func _deploy_army(slots: Dictionary) -> void:
	is_deploying = true
	hud.set_message("Построение...")
	var tw := create_tween().set_parallel(true)
	for squad in slots:
		var to: Vector2 = slots[squad]
		var way: Vector2 = to - squad.global_position
		var speed: float = maxf(squad.data.get_move_speed() * DEPLOY_PACE, way.length() / DEPLOY_MAX_TIME)
		var time: float = way.length() / maxf(speed, 1.0)
		tw.tween_property(squad, "global_position", to, time)
		for s in squad.soldiers:
			s.deploy_walk(speed, way)
		# Дошёл — стойка лицом к врагу, пока остальные подходят
		tw.tween_callback(_deploy_arrived.bind(squad)).set_delay(time)
	# Пауза «стоят строем» — после последнего: параллельный шаг длится до него, дальше — по очереди
	# (без set_parallel(false) пауза шла бы вместе с ходом и бой стартовал бы на бегу)
	tw.set_parallel(false)
	var walk := 0.0
	for squad in slots:
		walk = maxf(walk, (slots[squad] - squad.global_position).length()
			/ maxf(maxf(squad.data.get_move_speed() * DEPLOY_PACE, (slots[squad] - squad.global_position).length() / DEPLOY_MAX_TIME), 1.0))
	tw.tween_interval(maxf(DEPLOY_HOLD, _intro_time - walk))   # выход босса доигрывается до схватки
	tw.tween_callback(_begin_battle)

func _deploy_arrived(squad: Squad) -> void:
	if is_instance_valid(squad):
		for s in squad.soldiers:
			s.deploy_stand()

# Армия стоит строем — схватка: марш, синергии, бонусы, щиты, старт тиков
func _begin_battle() -> void:
	is_deploying = false
	hud.set_message("Бой идёт...")
	_tutorial_notify("battle_start")
	for squad in SquadRegistry.get_all_alive_squads():
		squad.start_march()

	# Синергии и командир — по бойцам на поле, один раз перед боем
	var my_soldiers = SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER)
	SynergyManager.calculate_synergies(my_soldiers)
	SynergyManager.apply_synergies_to_soldiers(my_soldiers)
	SynergyManager.apply_position_bonuses(SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER))
	SynergyManager.apply_chapter_bonus(my_soldiers)
	SynergyManager.apply_meta_bonus(my_soldiers)
	SynergyManager.apply_commander_bonus(my_soldiers)
	Building.apply_battle_start()   # здания на соседние отряды: щит, клич, вампиризм, +урон
	_show_bonus_marks()

	player_soldiers_at_start = my_soldiers.size()
	player_squads_at_start.clear()
	for squad in SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER):
		player_squads_at_start.append({"data": squad.data, "tile": squad.tile})
	BattleManager.prepare_citadel_shield()
	_show_shields(my_soldiers)
	BattleManager.start_battle()
	for hit in BattleManager.fire_armed_events():
		_spawn_strike_flash(hit["pos"], hit["radius"])

# Щиты в начале боя (только вид): Iron Halo на бойцах, щит стен на цитадели
func _show_shields(soldiers: Array) -> void:
	var bannered := {}   # аура знамени — одно кольцо на отряд (знамя у всего отряда), за центром отряда
	for s in soldiers:
		if s.shield > 0.0:
			Vfx.attach(s, "shield", s.data.sprite_scale * Soldier.EFFECT_SCALE)
		if s.data.banner_aura_bonus > 0.0 and not bannered.has(s.data):
			bannered[s.data] = true
			AuraRing.follow_squad(s.parent_squad, UnitData.BANNER_RADIUS,
				"banner_chaos" if s.data.faction == "chaos" else "banner")
	# Щит стен — вспышка по стене владений (решение пользователя 22.10.2026: купол убран); без стены (пассивка
	# «Освящённые стены») — щит на цитадели
	if BattleManager.citadel_shield > 0.0 and BattleManager.has_kingdom_wall():
		BattleManager.kingdom_wall.flash_shield()
	elif BattleManager.citadel_shield > 0.0 and is_instance_valid(BattleManager.citadel):
		Vfx.attach(BattleManager.citadel, "citadel_shield")

# Орбитальный удар: луч с неба и кольцо по земле (у Хаоса — разлом варпа); кольцо листа — радиус ~130
const STRIKE_VFX_RADIUS: float = 130.0
const STRIKE_IMPACT_DELAY: float = 0.22   # кадр 4 листа (18 к/с) — луч дошёл до земли
const STRIKE_SHAKE: float = 6.0
func _spawn_strike_flash(pos: Vector2, radius: float) -> void:
	Vfx.spawn(units_container, Vfx.race_kind("orbital_strike"), pos, radius / STRIKE_VFX_RADIUS)
	get_tree().create_timer(STRIKE_IMPACT_DELAY, false).timeout.connect(_strike_impact.bind(pos, radius))

# Удар дошёл до земли — в мир поля, как разрывы снарядов: свет по земле и бойцам, тряска, подпалина, пыль
func _strike_impact(pos: Vector2, radius: float) -> void:
	if not is_inside_tree():
		return
	var chaos: bool = RunManager.player_faction == "chaos"
	IsoGridRenderer.flash_light(pos, Palette.CHAOS_LANTERN if chaos else Palette.FIRE, radius * 1.3, 0.5)
	camera.shake(STRIKE_SHAKE)
	ScarLayer.scorch(pos, radius * 0.45)
	DustLayer.puff(pos, radius * 0.18, 12, radius * 0.5)

# -------------------------------------------------------
# КОНЕЦ БОЯ
# -------------------------------------------------------
func _on_battle_ended(winner_team: int) -> void:
	# Итог боя обрабатывается ровно один раз: доход, round_number, шаг забега
	if _battle_resolved:
		return
	if _boss_fall_base > 0.0:
		if not BattleManager.surrendered:   # примарх ещё падает — итог после (_end_boss_fall)
			_deferred_winner = winner_team
			return
		# сдача в миг смерти примарха — итог сразу: за ней следует уход в меню, а _exit_tree стёр бы
		# отложенный итог — забег не закончился бы и «Продолжить» вернуло бы в бой (ревью 09.11.2026)
		_end_boss_fall()
	_battle_resolved = true
	BattleManager.battle_in_progress = false
	_restore_time_scale()
	if winner_team == GameConstants.TEAM_PLAYER:
		WorldGrade.relieve()   # победа — поле светлеет и теплеет
	if RunManager.test_mode:
		_end_test_battle(winner_team)
		return
	if BattleManager.citadel_hp <= 0:
		_end_run(false, "Цитадель пала!")
		return
	# Сдача — конец забега (решение пользователя): сохранение удаляется,
	# игрок сам уходит из боя (в меню или из игры)
	if BattleManager.surrendered:
		_end_run(false, "Вы сдались")
		return
	var won = winner_team == GameConstants.TEAM_PLAYER
	if won:
		MetaProgress.on_battle_won(battle_type)   # счётчик мини-боссов забега — для Славы
	if battle_type == RunMapNode.BOSS and won:
		RunManager.complete_current_node()
		_unlocked_difficulty = SaveManager.on_run_won(RunManager.difficulty)
		_end_run(true, "Босс повержен!")
		return
	# Последствие события действовало на этот бой
	BattleManager.next_battle_enemy_hp = 1.0
	BattleManager.next_battle_note = ""
	# Живые до итога: store_survivors возрождает павшие отряды, Казармы пополняют — потери считать раньше
	var alive_at_end := SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER).filter(func(s): return not s.charmed).size()
	var coin_sources := _income_coin_sources()   # до итога: реестры чистятся ниже
	var req_before := EconomyManager.requisition
	hud.hold_requisition()
	var result_text := _resolve_battle(winner_team)
	var building_income := EconomyManager.collect_building_income(BattleManager.player_buildings)
	if building_income > 0:
		result_text += " · генераторы +%s" % GameConstants.coins(building_income)
	var repaired := BattleManager.repair_from_forges()
	if repaired > 0.0:
		result_text += " · кузня +%d HP цитадели" % roundi(repaired)
	_show_building_income(repaired)
	_fly_income_coins(coin_sources, req_before)
	hud.set_message(result_text)
	AudioManager.play("victory" if won else "defeat")
	if won:
		_tutorial_notify("battle_won")
	var summary := _battle_summary(alive_at_end)
	hud.show_result(_result_title(winner_team), result_text + "\n" + summary, won)
	_play_finale_slowmo()
	# BattleManager.pending_cards НЕ очищаем: невыложенные карты остаются в руке
	SquadRegistry.clear()
	SoldierRegistry.clear()
	RunManager.complete_current_node(won)
	# Босс не побеждён без гибели цитадели (бывает только без цитадели) — забег проигран
	if battle_type == RunMapNode.BOSS:
		_end_run(false, "")
		return
	# Итог боя сохранён: при загрузке — сразу магазин следующей волны
	SaveManager.save_run()
	# Таймер не тикает на паузе (иначе ушли бы в магазин с открытым меню паузы).
	# Подключение к методу сцены, а не await: если игрок за эти 2 с ушёл из боя
	# (пауза → меню / сдаться), сцена удалена и связь снимается сама
	get_tree().create_timer(2.0, false).timeout.connect(_go_to_next_step)

# Итоги боя для баннера: лучший отряд по урону и потери (решение пользователя)
func _battle_summary(alive_at_end: int) -> String:
	var parts: Array[String] = []
	var top := BattleManager.top_damage_dealer()
	if not top.is_empty():
		parts.append("Лучший отряд: %s — %d урона" % [top[0].display_name(), roundi(top[1])])
	var lost := maxi(player_soldiers_at_start - alive_at_end, 0)
	parts.append("Потери: %d из %d бойцов" % [lost, player_soldiers_at_start] if lost > 0 else "Без потерь")
	return " · ".join(parts)

func _result_title(winner_team: int) -> String:
	if winner_team == GameConstants.TEAM_PLAYER:
		return "ЦИТАДЕЛЬ ВЫСТОЯЛА" if BattleManager.siege_started else "ПОБЕДА"
	return "ПОРАЖЕНИЕ" if winner_team == GameConstants.TEAM_ENEMY else "НИЧЬЯ"

# Финал боя (решение пользователя): мир на миг замедляется — последние падения, позы победы.
# Бой уже закончен — на исход не влияет; таймер по реальному времени, на паузе стоит
func _play_finale_slowmo() -> void:
	_end_hitstop()
	_finale_base_scale = Engine.time_scale
	Engine.time_scale = _finale_base_scale * FINALE_SLOWMO
	get_tree().create_timer(FINALE_SLOWMO_TIME, false, false, true).timeout.connect(_end_finale_slowmo)

# Выход финального босса (по «В БОЙ», бой ещё не идёт): наезд камеры, титр, ряд appear, удар о землю; через
# BOSS_INTRO_TIME камера — обратно на поле. Время игровое (как построение — скорость боя ускоряет и его)
func _boss_intro(boss: Soldier) -> void:
	_intro_time = BOSS_INTRO_TIME
	var d: UnitData = boss.data
	camera.focus(boss.global_position + Vector2(0.0, -Soldier.TARGET_SPRITE_HEIGHT * d.sprite_scale * 0.5),
		BOSS_INTRO_ZOOM, 0.5)
	var title_col := EnemyWaves.boss_color(d.factory_id)   # цвет бога / легиона (решение пользователя 09.11.2026)
	BossFx.title(self, d.display_name().to_upper(), EnemyWaves.BOSS_TITLES.get(d.factory_id, "").get_slice(",", 1).strip_edges(),
		title_col if title_col.a > 0.0 else d.special_color, title_col.a > 0.0)
	var impact := 0.3
	if boss.play_appear():
		var frames := boss.sprite.sprite_frames
		impact = frames.get_frame_count("appear") / frames.get_animation_speed("appear") * BOSS_INTRO_IMPACT
	var tw := create_tween()
	tw.tween_interval(impact)
	tw.tween_callback(_boss_landed.bind(boss))
	tw.tween_interval(maxf(BOSS_INTRO_TIME - impact, 0.0))
	tw.tween_callback(func(): if is_instance_valid(camera): _fit_camera(true))

func _boss_landed(boss: Soldier) -> void:
	if not is_instance_valid(boss):
		return
	var d: UnitData = boss.data
	BossFx.shockwave(boss.global_position, d.special_radius * 1.3, d.special_color)
	WorldGrade.pulse(0.9)
	BossFx.cracks(boss.global_position, d.special_radius, Soldier.BOSS_CRACK_LIFE, d.special_color)
	IsoGridRenderer.flash_light(boss.global_position, Color(d.special_color, 0.9), d.special_radius * 2.0, 0.5)
	camera.shake(Soldier.SPECIAL_SHAKE)

# Ярость босса (Soldier._enrage) — строка в шапке
func boss_enraged(boss: Soldier) -> void:
	_show_message("%s в ярости: приём чаще!" % boss.data.display_name())

# Смерть финального босса (Soldier._die): мир замедляется на BOSS_FALL_TIME реального времени, камера — к нему,
# вспышка, ударная волна, титр; итог боя, пришедший в это время, ждёт (_deferred_winner). Без стоп-кадров
# (headless, hitstop_enabled) — только вспышка и титр, без замедления и ожидания
func boss_fall(boss: Soldier) -> void:
	var d: UnitData = boss.data
	var at := boss.global_position
	BossFx.shockwave(at, d.special_radius * 2.0, d.special_color)
	WorldGrade.pulse(1.0)
	BossFx.cracks(at, d.special_radius * 1.2, Soldier.BOSS_CRACK_LIFE * 1.5, d.special_color)
	# Решение пользователя 09.11.2026 («умирают инородно от текстур»): вспышка была на полную яркость 0.9 с — в
	# замедлении ×0.25 почти 4 с засвечивала поле и тело добела; взрыв и удар пака Pixel, растянутые до размера
	# примарха, ложились на тело квадратной серо-белой кляксой. Теперь: свет глуше и короче, вместо них — пыль
	# поля (DustLayer) кольцом от тела; павший сам не загорается (Soldier.add_flash_light)
	IsoGridRenderer.flash_light(at, Color(d.special_color, BOSS_FALL_LIGHT), d.special_radius * 2.0, 0.45)
	DustLayer.puff(at, d.special_radius * 0.3, 10, d.special_radius * 0.35)
	ScarLayer.scorch(at, d.special_radius * 0.55)
	DustLayer.puff(at, d.special_radius * 0.18, 8, d.special_radius * 0.7)
	camera.shake(Soldier.SPECIAL_SHAKE * 1.5)
	BossFx.title(self, "ДЕМОН ИЗГНАН" if d.faction == "chaos" else "ОТЕЦ ПОВЕРЖЕН", d.display_name(), d.special_color)
	if not hitstop_enabled or _boss_fall_base > 0.0:
		return
	_end_hitstop()
	_boss_fall_base = Engine.time_scale
	Engine.time_scale = _boss_fall_base * BOSS_FALL_SLOWMO
	camera.focus(at + Vector2(0.0, -Soldier.TARGET_SPRITE_HEIGHT * d.sprite_scale * 0.4), BOSS_FALL_ZOOM, 0.35, true)
	get_tree().create_timer(BOSS_FALL_TIME, false, false, true).timeout.connect(_end_boss_fall)

func is_boss_falling() -> bool:
	return _boss_fall_base > 0.0

func _end_boss_fall() -> void:
	if _boss_fall_base <= 0.0:
		return
	if is_equal_approx(Engine.time_scale, _boss_fall_base * BOSS_FALL_SLOWMO):
		Engine.time_scale = _boss_fall_base
	_boss_fall_base = -1.0
	if not is_inside_tree():
		return
	_fit_camera(true)
	if _deferred_winner != -2:
		var w := _deferred_winner
		_deferred_winner = -2
		_on_battle_ended(w)

# Стоп-кадр (зовут бойцы и снаряды через дерево: current_scene.has_method("hitstop"))
func hitstop(sec: float = HITSTOP_TIME) -> void:
	if not hitstop_enabled or _hitstop_base > 0.0 or _finale_base_scale > 0.0 or _boss_fall_base > 0.0 \
			or not BattleManager.is_battle_running():
		return
	if Time.get_ticks_msec() - _hitstop_at < HITSTOP_GAP_MS:
		return
	_hitstop_at = Time.get_ticks_msec()
	_hitstop_base = Engine.time_scale
	Engine.time_scale = _hitstop_base * HITSTOP_SCALE
	get_tree().create_timer(sec, false, false, true).timeout.connect(_end_hitstop)

# Конец стоп-кадра; скорость за это время сменили (кнопка ×2, итог боя) — не трогаем
func _end_hitstop() -> void:
	if _hitstop_base > 0.0:
		if is_equal_approx(Engine.time_scale, _hitstop_base * HITSTOP_SCALE):
			Engine.time_scale = _hitstop_base
		_hitstop_base = -1.0

func _end_finale_slowmo() -> void:
	if _finale_base_scale > 0.0:
		Engine.time_scale = _finale_base_scale
		_finale_base_scale = -1.0

func _go_to_next_step() -> void:
	if _expansion_ahead():   # round_number уже следующей волны (give_round_income)
		_announce_expansion()
	else:
		RunManager.advance()

# Доход и армия по итогу боя; возвращает текст для шапки
func _resolve_battle(winner_team: int) -> String:
	if winner_team != GameConstants.TEAM_PLAYER:
		var income = EconomyManager.give_round_income(false)
		BattleManager.lose_army()
		return "%s +%s" % ["Поражение!" if winner_team == GameConstants.TEAM_ENEMY else "Ничья!", GameConstants.coins(income)]
	var alive = SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER).filter(func(s): return not s.charmed).size()
	var flawless = player_soldiers_at_start > 0 and alive == player_soldiers_at_start
	var bonuses = EconomyManager.calculate_victory_bonuses(SynergyManager.income_bonus, flawless, enemy_elites_at_start)
	var income = EconomyManager.give_round_income(true, bonuses)
	var text = "%s +%s" % ["Цитадель выстояла!" if BattleManager.siege_started else "Победа!", GameConstants.coins(income)]
	var revived = BattleManager.store_survivors(
		SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER), player_squads_at_start)
	if not revived.is_empty():
		text += " · возрождено отрядов: %d" % revived.size()
	var refilled = BattleManager.refill_from_barracks()
	if refilled > 0:
		text += " · Казармы вернули бойцов: %d" % refilled
	_show_barracks_refill(refilled)
	var thralls = BattleManager.apply_thralls()
	if thralls > 0:
		text += " · порабощено: %d" % thralls
	print("BattleScene: армия %d отрядов, возрождено %s" % [BattleManager.player_units.size(), revived])
	return text

# Только вид: Казармы лечат / пополняют соседние отряды (у Святилища — только пополнение) — вспышка на клетках
# (решение пользователя 22.10.2026: лист пакета refill — яркий и обрезанный) — свет на каждом живом бойце соседних
# отрядов волной (LevelUpGlow "heal"), как уровень отряда
func _show_barracks_refill(refilled: int) -> void:
	var squads: Array = units_container.get_children().filter(func(n): return n is Squad and n.team == GameConstants.TEAM_PLAYER)
	for b in BattleManager.buildings:
		if not is_instance_valid(b) or b.building_type != "barracks":
			continue
		if refilled <= 0 and b.card.faction == "chaos":
			continue
		for squad in squads:
			if not BattleManager.NEIGHBOUR_TILES.has(squad.tile - b.tile):
				continue
			_glow_soldiers(squad, "heal")

# Только вид: генераторы дали доход (разряд над зданием), Кузня чинит цитадель
func _show_building_income(repaired: float) -> void:
	for b in BattleManager.buildings:
		if is_instance_valid(b) and b.stats.get("income", 0.0) > 0.0:
			TileGlow.burst(renderer, b.global_position, "income", b.card.faction)
	if repaired > 0.0 and is_instance_valid(BattleManager.citadel):
		Vfx.spawn(units_container, "forge_repair", BattleManager.citadel.global_position)

# Забег окончен (победа над боссом / цитадель пала): экран итога, сохранение удаляется
func _end_run(victory: bool, message: String) -> void:
	if message != "":
		hud.set_message(message)
	SquadRegistry.clear()
	SoldierRegistry.clear()
	_show_run_end(victory)

func _show_run_end(victory: bool) -> void:
	AudioManager.play("run_won" if victory else "run_lost")
	AudioManager.play_music("")
	SaveManager.delete_save()
	inspector.shutdown()
	var subtitle = "Главный босс повержен — забег выигран!" if victory \
		else "Забег окончен на волне %d из %d." % [battle_wave, RunManager.get_total_waves()]
	var meta: Dictionary = MetaProgress.on_run_end(victory)
	if MetaProgress.active():
		subtitle += "\nСлава +%d (всего %d) — тратится в «Арсенале» главного меню" % [meta["glory"], meta["total"]]
	var stats = "%s · Побед в волнах: %d · Цитадель %d/%d · %s" % [
		Difficulty.describe(RunManager.difficulty), EconomyManager.wins + (1 if victory else 0),
		ceili(BattleManager.citadel_hp), int(BattleManager.CITADEL_MAX_HP), GameConstants.coins(EconomyManager.requisition)]
	if _unlocked_difficulty > 0:
		subtitle += "\nОткрыта новая сложность: %s" % Difficulty.describe(_unlocked_difficulty)
	pause_menu.enabled = false
	var screen = RunEndScreen.new()
	$UI.add_child(screen)
	screen.setup(victory, subtitle, stats)
	screen.new_run_pressed.connect(_on_new_run_pressed)
	screen.main_menu_pressed.connect(RunManager.goto_main_menu)
	print("BattleScene: забег окончен — %s" % ("победа" if victory else "поражение"))

func _on_new_run_pressed() -> void:
	BattleManager.reset_run()
	SaveManager.delete_save()
	RunManager.landing_pending = true   # первое поле нового забега — посадка (BattleLanding)
	RunManager.advance()

# -------------------------------------------------------
# СКОРОСТЬ БОЯ
# -------------------------------------------------------
func _apply_battle_speed() -> void:
	if _speed_applied:
		Engine.time_scale = _base_time_scale * GameSettings.battle_speed
		BattleManager.battle_speed_now = GameSettings.battle_speed

func _restore_time_scale() -> void:
	if _speed_applied:
		Engine.time_scale = _base_time_scale
		_speed_applied = false
	BattleManager.battle_speed_now = 1.0

# Ушли со сцены посреди боя (в меню) — скорость не должна остаться ускоренной
func _exit_tree() -> void:
	BattleManager.kingdom_wall = null
	if AuraRing.layer == renderer:   # новая сцена боя могла уже поставить свой слой
		AuraRing.layer = null
	_end_hitstop()
	_deferred_winner = -2   # сцена уходит — отложенный итог не обрабатываем
	_end_boss_fall()
	_restore_time_scale()
	_end_finale_slowmo()

# -------------------------------------------------------
# UI
# -------------------------------------------------------
# Во время расстановки — только предпросмотр синергий (справка цитадели), бойцам ничего не применяем
func _update_synergy_preview() -> void:
	SynergyManager.calculate_synergies(SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER))

# Короткое уведомление (сыграна карта, нельзя и т. п.) — надпись сверху, гаснет сама (решение пользователя 11.11.2026,
# `Screenshot 2026-11-11 140856.png`: плашка была огромной и висела до следующего сообщения). Состояние этапа
# («Расставьте отряды», «Бой идёт…», подсказка расширения) — постоянной плашкой hud.set_message
func _show_message(text: String) -> void:
	print("BattleScene: ", text)
	hud.notify(text)

# -------------------------------------------------------
# ТЕСТОВЫЙ РЕЖИМ (RunManager.test_mode, решение пользователя 06.11.2026)
# -------------------------------------------------------
const TEST_RESULT_TIME: float = 3.0   # сек после итога — назад к расстановке

func _build_test_panel() -> void:
	test_panel = TestPanel.new()
	$UI.add_child(test_panel)
	test_panel.setup(RunManager.player_faction)
	test_panel.card_picked.connect(_on_test_card_picked)
	test_panel.wave_changed.connect(func(wave):
		RunManager.test_wave = wave
		_reload_test_placement())
	test_panel.type_changed.connect(func(kind):
		RunManager.test_battle_type = kind
		_reload_test_placement())
	test_panel.boss_changed.connect(func(id):
		RunManager.test_boss = id
		_reload_test_placement())
	test_panel.level_changed.connect(func(level): _show_message("Из панели: отряды ур.%d, здания ур.%d" % [level, mini(1 + level, CardData.MAX_BUILDING_LEVEL)]))
	test_panel.clear_pressed.connect(_on_test_clear)
	test_panel.shop_pressed.connect(_open_test_shop)

# Карта из панели — в руку бесплатно (лимит руки тот же)
func _on_test_card_picked(card_id: String) -> void:
	if not is_placement_phase:
		return
	if bench.bench_cards.size() >= BattleManager.MAX_HAND_SIZE:
		_show_message("Рука полна (%d) — сыграйте карту" % BattleManager.MAX_HAND_SIZE)
		return
	var card := CardFactory.create(card_id)
	if card == null:
		return
	bench.bench_cards.append(card)
	bench._populate()
	_show_message("В руке: %s" % card.display_title())

# Магазин из тестового режима (решение пользователя 21.11.2026: «добавь в тестовый режим возможность зайти в магазин»):
# то же окно поверх поля, что в забеге (ShopScene embedded), но без шага цепочки: набор каждый раз новый, монет
# TEST_SHOP_REQUISITION (долить до этой суммы), покупки — в руку расстановки, «В БОЙ» — просто закрыть и вернуться к полю
const TEST_SHOP_REQUISITION: int = 200
var _test_shop_node := {}   # шаг цепочки до входа: ShopScene.ensure_started его трогает — вернуть как было

func _open_test_shop() -> void:
	if not RunManager.test_mode or not is_placement_phase or shop_phase or shop != null:
		return
	BattleManager.sync_army_from_squads(SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER))
	if EconomyManager.requisition < TEST_SHOP_REQUISITION:
		EconomyManager.add_requisition(TEST_SHOP_REQUISITION - EconomyManager.requisition)
	_test_shop_node = {"id": RunManager.current_node_id, "done": RunManager.current_completed}
	ShopManager.shop_node_id = -1   # новый набор, а не прежний этого шага
	shop_phase = true
	$UI.visible = false
	bench.visible = false
	_fit_camera(false)
	var layer := CanvasLayer.new()
	layer.name = "ShopLayer"
	layer.layer = SHOP_LAYER
	add_child(layer)
	shop = SHOP_SCENE.instantiate()
	shop.set("embedded", true)
	layer.add_child(shop)
	shop.connect("finished", _close_test_shop)

func _close_test_shop() -> void:
	if shop == null:
		return
	var layer: Node = shop.get_parent()
	shop = null
	layer.queue_free()
	RunManager.current_node_id = int(_test_shop_node.get("id", RunManager.current_node_id))
	RunManager.current_completed = bool(_test_shop_node.get("done", RunManager.current_completed))
	ShopManager.shop_node_id = -1
	shop_phase = false
	$UI.visible = true
	bench.setup(BattleManager.pending_cards)   # рука магазина — новый массив (покупки / продажи)
	bench.visible = true
	AudioManager.play_music("battle")
	_fit_camera(true)

# Волна или тип боя сменились — поле как есть, враги — новые (сцена заново)
func _reload_test_placement() -> void:
	BattleManager.sync_army_from_squads(SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER))
	RunManager.reload_test_battle()

func _on_test_clear() -> void:
	BattleManager.player_units.clear()
	BattleManager.player_placements.clear()
	BattleManager.player_buildings.clear()
	BattleManager.armed_events.clear()
	BattleManager.armed_tiles.clear()
	RunManager.reload_test_battle()

# Итог боя в тесте: баннер и итоги, без дохода, шага забега, меты и сохранения; затем расстановка как до боя
func _end_test_battle(winner_team: int) -> void:
	var alive_at_end := SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER).filter(func(s): return not s.charmed).size()
	var won := winner_team == GameConstants.TEAM_PLAYER
	hud.show_result(_result_title(winner_team), _battle_summary(alive_at_end), won)
	hud.set_message("Тест: через %d с — снова расстановка" % int(TEST_RESULT_TIME))
	_play_finale_slowmo()
	SquadRegistry.clear()
	SoldierRegistry.clear()
	get_tree().create_timer(TEST_RESULT_TIME, false).timeout.connect(_restore_test_field)

func _restore_test_field() -> void:
	if not RunManager.test_mode or not is_inside_tree():   # за 3 с ушли в меню — тест окончен, поле не возвращать
		return
	if not RunManager.test_snapshot.is_empty():
		BattleManager.player_units.clear()
		BattleManager.player_placements.clear()
		BattleManager.player_buildings.clear()
		BattleManager.load_state(RunManager.test_snapshot)
	BattleManager.battle_in_progress = false
	BattleManager.citadel_hp = BattleManager.CITADEL_MAX_HP
	RunManager.reload_test_battle()
