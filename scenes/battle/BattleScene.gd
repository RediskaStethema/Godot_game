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
# Область экрана под поле: под HUD; при расстановке — до скамейки
const PLAY_AREA_MARGIN: float = 8.0

var iso_grid: IsoGrid = IsoGrid.new()
var renderer: IsoGridRenderer = null
var camera: BattleCamera = null
var bench: Node = null
var hud: BattleHud = null
var inspector: SquadInspector = null
var merge_menu: MergeMenu = null   # выбор «улучшить / вылечить» отряд его картой
var pause_menu: PauseMenu = null
var fader: OcclusionFader = null   # прозрачность построек — только на расстановке
var reticle: ArtilleryReticle = null   # прицел орудия игрока — в бою за курсором
const BUILDING_HIGHLIGHT = Color(1.45, 1.2, 0.7)   # здание карты под курсором на скамейке — золотом
# Скорость боя: Engine.time_scale = базовый × GameSettings.battle_speed, только
# пока идёт бой; базовый — тот, что был до боя (тесты гоняют с ускорением)
var _base_time_scale: float = 1.0
var _speed_applied: bool = false

var battle_type: String = RunMapNode.BATTLE   # тип боя шага забега: battle / miniboss / boss
var battle_wave: int = 1
var is_placement_phase: bool = true
var player_soldiers_at_start: int = 0   # для бонуса «победа без потерь»
var enemy_elites_at_start: int = 0      # элитные враги (тег elite) — бонус TDD за каждого
# Отряды игрока на старте боя — павшие целиком при победе возрождаются
var player_squads_at_start: Array[Dictionary] = []
var _battle_resolved: bool = false

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
	battle_type = RunManager.get_battle_type()
	battle_wave = RunManager.get_battle_wave()
	_card_handlers = {
		"squad": _play_squad_card,
		"upgrade": _play_upgrade_card,
		"building": _play_building_card,
	}
	_build_ui()
	_build_field()
	_populate_field()
	SaveManager.save_run()
	# Загрузили сохранение посреди боя: армия уже стоит как была — сразу в бой
	if BattleManager.battle_in_progress:
		_show_message("Бой продолжается")
		_on_start_pressed.call_deferred()

func _build_ui() -> void:
	var bg_layer = CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	bg_layer.add_child(UITheme.make_background())

	bench = BENCH_SCENE.instantiate()
	add_child(bench)
	bench.setup(BattleManager.pending_cards)
	bench.card_dropped_on_tile.connect(_on_card_dropped)
	bench.card_hovered.connect(_on_bench_card_hovered)

	hud = BattleHud.new()
	$UI.add_child(hud)
	var wave_text = "Волна %d/%d" % [battle_wave, RunManager.get_total_waves()]
	if battle_type != RunMapNode.BATTLE:
		wave_text += " · " + UITheme.NODE_NAMES.get(battle_type, battle_type)
	hud.setup(wave_text, result_label, start_button, bench.BENCH_RIGHT_RESERVE)
	hud.set_message("Расставьте отряды")
	start_button.pressed.connect(_on_start_pressed)

	inspector = SquadInspector.new()
	inspector.click_blocker = _artillery_takes_click
	$UI.add_child(inspector)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	GameSettings.changed.connect(_apply_battle_speed)
	BattleManager.battle_ended.connect(_on_battle_ended)

func _build_field() -> void:
	# Бойцы рисуются по глубине: кто ниже на экране — тот ближе
	units_container.y_sort_enabled = true
	iso_grid.set_unlocked_tiles(BattleManager.kingdom_tiles)
	iso_grid.setup()
	renderer = IsoGridRenderer.new()
	renderer.setup(iso_grid)
	grid_renderer.add_child(renderer)
	# Здания и цитадель полупрозрачны, пока за ними стоят бойцы (только расстановка)
	fader = OcclusionFader.new()
	add_child(fader)
	camera = BattleCamera.new()
	add_child(camera)
	camera.make_current()
	reticle = ArtilleryReticle.new()
	reticle.camera = camera
	add_child(reticle)
	_fit_camera(false)
	get_viewport().size_changed.connect(_fit_camera.bind(false))

func _populate_field() -> void:
	_spawn_citadel()
	_place_enemy_squads()
	_place_player_buildings()
	_place_player_squads()
	_update_synergy_preview()
	_update_expansion()
	if BattleManager.can_expand_kingdom() and not iso_grid.get_expansion_tiles().is_empty():
		_show_message("Расширение: кликните по зелёной клетке")
	elif BattleManager.next_battle_note != "":
		_show_message(BattleManager.next_battle_note)

func _get_play_area() -> Rect2:
	var screen = get_viewport_rect().size
	var top = UITheme.HUD_HEIGHT
	var bottom = screen.y
	if is_placement_phase:
		bottom -= UITheme.BENCH_HEIGHT
	return Rect2(PLAY_AREA_MARGIN, top + PLAY_AREA_MARGIN,
		screen.x - PLAY_AREA_MARGIN * 2.0, bottom - top - PLAY_AREA_MARGIN * 2.0)

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

# Здания стоят на своих клетках между раундами
func _place_player_buildings() -> void:
	BattleManager.buildings.clear()
	for card in BattleManager.player_buildings:
		var tile: Vector2i = BattleManager.player_buildings[card]
		if iso_grid.is_valid_tile(tile) and not _is_tile_occupied(tile):
			_spawn_building(card, tile)

func _spawn_building(card: CardData, tile: Vector2i) -> void:
	var building = Building.new()
	building.setup(card, tile)
	building.position = iso_grid.tile_to_screen(tile)
	units_container.add_child(building)
	BattleManager.buildings.append(building)
	renderer.set_occupied(tile, true)

# Один UnitData = один отряд; без сохранённой клетки — первая свободная
func _place_player_squads() -> void:
	var free_tiles = iso_grid.get_all_tiles()
	var tile_index = 0
	for unit_data in BattleManager.player_units:
		var count = unit_data.saved_hp.size()
		if count == 0:
			continue
		var tile: Vector2i = BattleManager.player_placements.get(unit_data, Vector2i(-1, -1))
		if not iso_grid.is_valid_tile(tile) or _is_tile_occupied(tile):
			while tile_index < free_tiles.size() and _is_tile_occupied(free_tiles[tile_index]):
				tile_index += 1
			if tile_index >= free_tiles.size():
				break
			tile = free_tiles[tile_index]
		_spawn_squad(unit_data, GameConstants.TEAM_PLAYER, tile, count, unit_data.saved_hp)

# Состав врагов — данными в EnemyWaves; заполняют зону с переднего края в тыл
func _place_enemy_squads() -> void:
	var tiles = iso_grid.get_enemy_tiles_front_first()
	var specs = EnemyWaves.build(battle_wave, battle_type, tiles.size(), RunManager.rng.seed)
	enemy_elites_at_start = 0
	for i in range(mini(specs.size(), tiles.size())):
		var spec: Dictionary = specs[i]
		var enemy_data = UnitFactory.create(spec["unit"])
		enemy_data.hp_multiplier = spec["mult"] * BattleManager.next_battle_enemy_hp   # событие забега
		enemy_data.damage_multiplier = spec["mult"]
		_spawn_squad(enemy_data, GameConstants.TEAM_ENEMY, tiles[i], spec["count"])
		if "elite" in enemy_data.tags:
			enemy_elites_at_start += spec["count"]

func _spawn_squad(unit_data: UnitData, team: int, tile: Vector2i, count: int, hp_list: Array[float] = []) -> void:
	var is_enemy = team == GameConstants.TEAM_ENEMY
	var squad = SQUAD_SCENE.instantiate()
	units_container.add_child(squad)
	squad.setup(unit_data, team, tile, count, hp_list)
	squad.global_position = iso_grid.tile_to_screen(tile, is_enemy)
	SquadRegistry.register(squad)
	# Враг скрыт до начала боя — игрок расставляется вслепую
	if is_enemy and is_placement_phase:
		squad.visible = false
	renderer.set_occupied(tile, true, is_enemy)
	if not is_enemy and is_placement_phase:
		_update_synergy_preview()

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
	if not is_placement_phase or merge_menu:
		return
	if event is InputEventMouseMotion:
		renderer.update_hover(iso_grid.screen_to_tile(_screen_to_world(event.position)))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_buy_tile(iso_grid.screen_to_tile(_screen_to_world(event.position)))

func _update_expansion() -> void:
	var tiles: Array[Vector2i] = []
	if is_placement_phase and BattleManager.can_expand_kingdom():
		tiles = iso_grid.get_expansion_tiles()
	renderer.set_expansion(tiles, BattleManager.get_tile_cost())

func _try_buy_tile(tile: Vector2i) -> void:
	if not BattleManager.can_expand_kingdom() or not iso_grid.get_expansion_tiles().has(tile):
		return
	var cost = BattleManager.get_tile_cost()
	if not BattleManager.try_buy_tile(tile):
		_show_message("Не хватает Requisition: клетка стоит %d" % cost)
		return
	iso_grid.set_unlocked_tiles(BattleManager.kingdom_tiles)
	_update_expansion()
	_show_message("Королевство расширено (−%d Req), клеток: %d" % [cost, BattleManager.kingdom_tiles.size()])
	_update_synergy_preview()   # новый ряд меняет, кто впереди и сзади
	_save_placement()

# -------------------------------------------------------
# КАРТЫ СО СКАМЕЙКИ
# -------------------------------------------------------
func _on_card_dropped(card: CardData, screen_pos: Vector2) -> void:
	if not is_placement_phase:
		return
	_close_merge_menu()
	var tile = iso_grid.screen_to_tile(_screen_to_world(screen_pos))
	if not iso_grid.is_valid_tile(tile):
		_show_message("Мимо сетки")
		return
	var handler: Callable = _card_handlers.get(card.card_type, Callable())
	if not handler.is_valid():
		_show_message("%s: эту карту нельзя сыграть на поле" % card.title)
		return
	if handler.call(card, tile):
		_consume_bench_card(card)

# Отряд на пустую клетку; на свой отряд того же типа — меню «улучшить / вылечить»
func _play_squad_card(card: CardData, tile: Vector2i) -> bool:
	var own = _get_player_squad_at(tile)
	if own and own.data.factory_id == card.unit_factory_id:
		_open_merge_menu(card, own)
		return false   # карту тратит выбор в меню
	if _is_tile_occupied(tile):
		_show_message("Тайл занят")
		return false
	var unit_data = UnitFactory.create(card.unit_factory_id)
	unit_data.squad_size = card.unit_count
	unit_data.squad_growth = UnitFactory.squad_growth_for(card)
	_spawn_squad(unit_data, GameConstants.TEAM_PLAYER, tile, card.unit_count)
	return true

# Улучшение бросают НА свой отряд
func _play_upgrade_card(card: CardData, tile: Vector2i) -> bool:
	var squad = _get_player_squad_at(tile)
	if squad == null:
		_show_message("%s: перетащите на свой отряд" % card.title)
		return false
	if not squad.apply_upgrade(card):
		_show_message("%s действует только на отряды «%s»" % [card.title, card.affects_tag])
		return false
	_show_message("%s → %s (%s)" % [card.title, squad.data.unit_name, card.description])
	return true

# Здание на пустую клетку; такая же карта на своё здание — уровень +1
func _play_building_card(card: CardData, tile: Vector2i) -> bool:
	var own = _get_player_building_at(tile)
	if own and own.card.id == card.id:
		if not own.card.level_up_building():
			_show_message("%s: максимальный уровень" % own.card.title)
			return false
		own.refresh_stats()
		_show_message("%s улучшено до уровня %d/%d" % [own.card.title, own.card.building_level, CardData.MAX_BUILDING_LEVEL])
		return true
	if _is_tile_occupied(tile):
		_show_message("Тайл занят")
		return false
	_spawn_building(card, tile)
	BattleManager.player_buildings[card] = tile
	_show_message("Построено: %s" % card.title)
	return true

func _get_player_building_at(tile: Vector2i) -> Building:
	for b in BattleManager.buildings:
		if is_instance_valid(b) and b.tile == tile:
			return b
	return null

func _open_merge_menu(card: CardData, squad: Squad) -> void:
	if not MergeMenu.has_options(squad):
		_show_message("%s: максимальный уровень, отряд здоров" % squad.data.unit_name)
		return
	inspector.close_info()
	inspector.enabled = false
	merge_menu = MergeMenu.new()
	$UI.add_child(merge_menu)
	merge_menu.setup(card, squad)
	merge_menu.place_near(_world_to_screen(squad.global_position))
	merge_menu.chosen.connect(_on_merge_chosen)
	merge_menu.closed.connect(_on_merge_menu_closed)

func _on_merge_chosen(card: CardData, squad: Squad, upgrade: bool) -> void:
	if not is_instance_valid(squad) or not bench.bench_cards.has(card):
		return
	if upgrade:
		if not squad.merge_upgrade():
			return
		_show_message("%s улучшен до уровня %d/%d" % [squad.data.unit_name,
			squad.data.squad_level, UnitFactory.MAX_SQUAD_LEVEL])
	else:
		var revived = squad.heal_by_ratio(UnitFactory.get_merge_bonuses(squad.data.faction)["heal"])
		var extra = ", вернулось бойцов: %d" % revived if revived > 0 else ""
		_show_message("%s вылечен%s" % [squad.data.unit_name, extra])
		_update_synergy_preview()
	_consume_bench_card(card)

func _on_merge_menu_closed() -> void:
	merge_menu = null
	inspector.enabled = true

func _close_merge_menu() -> void:
	if merge_menu:
		merge_menu.close()

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
func _on_bench_card_hovered(card: CardData) -> void:
	var tiles: Array[Vector2i] = []
	if is_placement_phase:
		tiles = get_same_card_tiles(card)
	renderer.set_highlighted(tiles)
	# Здание закрывает свою клетку — подсвечивается и само (modulate: прозрачность OcclusionFader — self_modulate)
	for b in BattleManager.buildings:
		if is_instance_valid(b):
			b.modulate = BUILDING_HIGHLIGHT if tiles.has(b.tile) else Color.WHITE

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
				if b.id == card.id:
					tiles.append(BattleManager.player_buildings[b])
	return tiles

func _on_start_pressed() -> void:
	is_placement_phase = false
	_on_bench_card_hovered(null)
	renderer.set_grid_overlay(false)   # в бою — только поле, здания, цитадель и бойцы
	fader.enabled = false
	start_button.disabled = true
	_close_merge_menu()
	# Армия перед боем — в забег и в сохранение. До синергий: они меняют max_hp
	# бойцов только на этот бой и исказили бы доли HP
	BattleManager.battle_in_progress = true
	_save_placement()
	# Бой: прячем скамейку и синергии, камера отъезжает на всё поле
	bench.visible = false
	hud.set_battle_mode()
	_fit_camera(true)
	hud.set_message("Бой идёт...")
	_update_expansion()
	for squad in SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_ENEMY):
		squad.visible = true
	for squad in SquadRegistry.get_all_alive_squads():
		squad.start_march()

	# Синергии и командир — по бойцам на поле, один раз перед боем
	var my_soldiers = SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER)
	SynergyManager.calculate_synergies(my_soldiers)
	SynergyManager.apply_synergies_to_soldiers(my_soldiers)
	SynergyManager.apply_position_bonuses(SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER))
	SynergyManager.apply_chapter_bonus(my_soldiers)
	SynergyManager.apply_commander_bonus(my_soldiers)
	hud.show_synergies()

	player_soldiers_at_start = my_soldiers.size()
	player_squads_at_start.clear()
	for squad in SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER):
		player_squads_at_start.append({"data": squad.data, "tile": squad.tile})
	BattleManager.prepare_citadel_shield()
	BattleManager.start_battle()
	_base_time_scale = Engine.time_scale
	_speed_applied = true
	_apply_battle_speed()

# -------------------------------------------------------
# КОНЕЦ БОЯ
# -------------------------------------------------------
func _on_battle_ended(winner_team: int) -> void:
	# Итог боя обрабатывается ровно один раз: доход, round_number, шаг забега
	if _battle_resolved:
		return
	_battle_resolved = true
	BattleManager.battle_in_progress = false
	_restore_time_scale()
	if BattleManager.citadel_hp <= 0:
		_end_run(false, "Цитадель пала!")
		return
	# Сдача — конец забега (решение пользователя): сохранение удаляется,
	# игрок сам уходит из боя (в меню или из игры)
	if BattleManager.surrendered:
		_end_run(false, "Вы сдались")
		return
	var won = winner_team == GameConstants.TEAM_PLAYER
	if battle_type == RunMapNode.BOSS and won:
		RunManager.complete_current_node()
		_end_run(true, "Босс повержен!")
		return
	# Последствие события действовало на этот бой
	BattleManager.next_battle_enemy_hp = 1.0
	BattleManager.next_battle_note = ""
	hud.set_message(_resolve_battle(winner_team))
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

func _go_to_next_step() -> void:
	RunManager.advance()

# Доход и армия по итогу боя; возвращает текст для шапки
func _resolve_battle(winner_team: int) -> String:
	if winner_team != GameConstants.TEAM_PLAYER:
		var income = EconomyManager.give_round_income(false)
		BattleManager.lose_army()
		return "%s +%d Req" % ["Поражение!" if winner_team == GameConstants.TEAM_ENEMY else "Ничья!", income]
	var alive = SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER).size()
	var flawless = player_soldiers_at_start > 0 and alive == player_soldiers_at_start
	var bonuses = EconomyManager.calculate_victory_bonuses(SynergyManager.income_bonus, flawless, enemy_elites_at_start)
	var income = EconomyManager.give_round_income(true, bonuses)
	var text = "%s +%d Req" % ["Цитадель выстояла!" if BattleManager.siege_started else "Победа!", income]
	var revived = BattleManager.store_survivors(
		SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER), player_squads_at_start)
	if not revived.is_empty():
		text += " · возрождено отрядов: %d" % revived.size()
	print("BattleScene: армия %d отрядов, возрождено %s" % [BattleManager.player_units.size(), revived])
	return text

# Забег окончен (победа над боссом / цитадель пала): экран итога, сохранение удаляется
func _end_run(victory: bool, message: String) -> void:
	if message != "":
		hud.set_message(message)
	SquadRegistry.clear()
	SoldierRegistry.clear()
	_show_run_end(victory)

func _show_run_end(victory: bool) -> void:
	SaveManager.delete_save()
	inspector.shutdown()
	var subtitle = "Главный босс Хаоса повержен — забег выигран!" if victory \
		else "Забег окончен на волне %d из %d." % [battle_wave, RunManager.get_total_waves()]
	var stats = "Побед в волнах: %d · Цитадель %d/%d · %d Req" % [
		EconomyManager.wins + (1 if victory else 0), ceili(BattleManager.citadel_hp),
		int(BattleManager.CITADEL_MAX_HP), EconomyManager.requisition]
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
	RunManager.advance()

# -------------------------------------------------------
# СКОРОСТЬ БОЯ
# -------------------------------------------------------
func _apply_battle_speed() -> void:
	if _speed_applied:
		Engine.time_scale = _base_time_scale * GameSettings.battle_speed

func _restore_time_scale() -> void:
	if _speed_applied:
		Engine.time_scale = _base_time_scale
		_speed_applied = false

# Ушли со сцены посреди боя (в меню) — скорость не должна остаться ускоренной
func _exit_tree() -> void:
	_restore_time_scale()

# -------------------------------------------------------
# UI
# -------------------------------------------------------
# Во время расстановки — только предпросмотр синергий, бойцам ничего не применяем
func _update_synergy_preview() -> void:
	if hud == null:
		return
	SynergyManager.calculate_synergies(SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER))
	hud.show_synergies()

# Подсказка игроку в шапке + в консоль
func _show_message(text: String) -> void:
	print("BattleScene: ", text)
	hud.set_message(text)
