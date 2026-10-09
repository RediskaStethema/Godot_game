extends Node2D

@onready var grid_renderer: Node2D = $GridRenderer
@onready var units_container: Node2D = $Units
@onready var start_button: Button = $UI/StartButton
@onready var result_label: Label = $UI/ResultLabel

const BENCH_SCENE = preload("res://scenes/battle/Bench.tscn")
const SQUAD_SCENE = preload("res://scenes/battle/Squad.tscn")

var bench: Node = null
var iso_grid: IsoGrid = IsoGrid.new()
var is_placement_phase: bool = true
var player_soldiers_at_start: int = 0   # для бонуса «победа без потерь»
var enemy_elites_at_start: int = 0      # элитные враги (тег elite) — бонус TDD +3 за каждого
var battle_type: String = RunMapNode.BATTLE   # тип боя шага забега: battle / miniboss / boss
var battle_wave: int = 1
var _battle_resolved: bool = false
var synergy_label: Label = null
var hud: PanelContainer = null
var requisition_label: Label = null
var citadel_label: Label = null
var merge_menu: PanelContainer = null   # выбор «улучшить / вылечить» отряд его картой

# -------------------------------------------------------
# ИНИЦИАЛИЗАЦИЯ
# -------------------------------------------------------
func _ready() -> void:
	# Тип боя и волна — из текущего шага забега
	battle_type = RunManager.get_battle_type()
	battle_wave = RunManager.get_battle_wave()
	start_button.pressed.connect(_on_start_pressed)
	BattleManager.battle_ended.connect(_on_battle_ended)

	# Скамейку создаём до сетки — её панель ограничивает игровую область снизу
	bench = BENCH_SCENE.instantiate()
	add_child(bench)
	bench.setup(BattleManager.pending_cards)
	bench.card_dropped_on_tile.connect(_on_card_dropped)
	_build_ui()

	iso_grid.set_unlocked_tiles(BattleManager.kingdom_tiles)
	iso_grid.setup(get_viewport_rect().size, _get_play_area())

	var renderer = IsoGridRenderer.new()
	renderer.setup(iso_grid)
	grid_renderer.add_child(renderer)

	# Очищаем занятые тайлы — новый раунд с чистого поля
	renderer.occupied_tiles_player.clear()
	renderer.occupied_tiles_enemy.clear()
	renderer.queue_redraw()

	_spawn_citadel()
	_place_enemy_squads()
	_place_player_buildings()
	_place_player_squads()
	_update_synergy_preview()
	_update_expansion()
	if BattleManager.can_expand_kingdom() and not iso_grid.get_expansion_tiles().is_empty():
		_show_message("Расширение: кликните по зелёной клетке")

# Цитадель — в общем контейнере юнитов, чтобы сортироваться по глубине с бойцами
func _spawn_citadel() -> void:
	var citadel = Citadel.new()
	citadel.position = iso_grid.tile_to_screen(iso_grid.citadel_tile)
	units_container.add_child(citadel)
	BattleManager.citadel = citadel

# -------------------------------------------------------
# ЗДАНИЯ — стоят на своих клетках между раундами
# -------------------------------------------------------
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
	var renderer = grid_renderer.get_child(0) as IsoGridRenderer
	if renderer:
		renderer.set_occupied(tile, true)

# Область экрана под сетки: между HUD сверху и скамейкой снизу
const PLAY_AREA_MARGIN: float = 40.0

func _get_play_area() -> Rect2:
	var screen = get_viewport_rect().size
	var top = hud.get_global_rect().end.y if hud else start_button.get_global_rect().end.y
	var bottom = screen.y
	var bench_panel = bench.get_node_or_null("BenchPanel") as Control
	if bench_panel:
		bottom = bench_panel.get_global_rect().position.y
	return Rect2(PLAY_AREA_MARGIN, top, screen.x - PLAY_AREA_MARGIN * 2.0, bottom - top)

# -------------------------------------------------------
# РАССТАНОВКА ИГРОКА
# -------------------------------------------------------
func _place_player_squads() -> void:
	var all_tiles = iso_grid.get_all_tiles()
	var tile_index = 0

	# Один UnitData = один выживший отряд
	for unit_data in BattleManager.player_units:
		var count = unit_data.saved_hp.size()
		if count == 0:
			continue
		var tile: Vector2i
		if BattleManager.player_placements.has(unit_data) 				and iso_grid.is_valid_tile(BattleManager.player_placements[unit_data]) 				and not _is_tile_occupied(BattleManager.player_placements[unit_data]):
			tile = BattleManager.player_placements[unit_data]
		else:
			while tile_index < all_tiles.size() and _is_tile_occupied(all_tiles[tile_index]):
				tile_index += 1
			if tile_index >= all_tiles.size():
				break
			tile = all_tiles[tile_index]
			tile_index += 1
		_spawn_squad(unit_data, GameConstants.TEAM_PLAYER, tile, count, unit_data.saved_hp)

# -------------------------------------------------------
# РАССТАНОВКА ВРАГОВ
# -------------------------------------------------------
# Состав — данными в EnemyWaves по волне и типу боя (бой / мини-босс / босс)
func _place_enemy_squads() -> void:
	var all_tiles = iso_grid.get_enemy_tiles_front_first()
	var squads = EnemyWaves.build(battle_wave, battle_type, all_tiles.size())
	enemy_elites_at_start = 0

	# Враги занимают зону с переднего края (ближе к королевству) в тыл
	for i in range(squads.size()):
		if i >= all_tiles.size():
			break
		var spec: Dictionary = squads[i]
		var enemy_data = UnitFactory.create(spec["unit"])
		enemy_data.hp_multiplier = spec["mult"]
		enemy_data.damage_multiplier = spec["mult"]
		_spawn_squad(enemy_data, GameConstants.TEAM_ENEMY, all_tiles[i], spec["count"])
		if "elite" in enemy_data.tags:
			enemy_elites_at_start += spec["count"]

# -------------------------------------------------------
# СПАВН ОТРЯДА
# -------------------------------------------------------
func _spawn_squad(unit_data: UnitData, team: int, tile: Vector2i, count: int, hp_list: Array[float] = []) -> void:
	var squad = SQUAD_SCENE.instantiate()
	units_container.add_child(squad)
	squad.setup(unit_data, team, tile, count, hp_list)
	squad.global_position = iso_grid.tile_to_screen(tile, team == GameConstants.TEAM_ENEMY)
	SquadRegistry.register(squad)
	# Враг скрыт до начала боя — игрок расставляется вслепую
	if team == GameConstants.TEAM_ENEMY and is_placement_phase:
		squad.visible = false

	var renderer = grid_renderer.get_child(0) as IsoGridRenderer
	if renderer:
		renderer.set_occupied(tile, true, team == GameConstants.TEAM_ENEMY)

	if team == GameConstants.TEAM_PLAYER and is_placement_phase and synergy_label:
		_update_synergy_preview()

func _create_unit_from_card(card: CardData) -> UnitData:
	return UnitFactory.create(card.unit_factory_id)

func _is_tile_occupied(tile: Vector2i) -> bool:
	var renderer = grid_renderer.get_child(0) as IsoGridRenderer
	if renderer:
		return renderer.occupied_tiles_player.has(tile)
	return false

# -------------------------------------------------------
# ВВОД — подсветка тайлов
# -------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not is_placement_phase or merge_menu:
		return
	if event is InputEventMouseMotion:
		var tile = iso_grid.screen_to_tile(event.position, false)
		var renderer = grid_renderer.get_child(0) as IsoGridRenderer
		if renderer:
			renderer.update_hover(tile)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_buy_tile(iso_grid.screen_to_tile(event.position, false))

# -------------------------------------------------------
# РАСШИРЕНИЕ КОРОЛЕВСТВА (каждая 3-я волна)
# -------------------------------------------------------
func _update_expansion() -> void:
	var renderer = grid_renderer.get_child(0) as IsoGridRenderer
	if not renderer:
		return
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

# -------------------------------------------------------
# БОЙ
# -------------------------------------------------------
func _on_start_pressed() -> void:
	is_placement_phase = false
	start_button.disabled = true
	_close_merge_menu()
	result_label.text = "Бой идёт..."
	_update_expansion()
	for squad in SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_ENEMY):
		squad.visible = true

	for squad in SquadRegistry.get_all_alive_squads():
		squad.start_march()

	# Синергии считаются по бойцам на поле и применяются один раз перед боем
	var my_soldiers = SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER)
	SynergyManager.calculate_synergies(my_soldiers)
	SynergyManager.apply_synergies_to_soldiers(my_soldiers)
	_apply_commander_bonus(my_soldiers)
	_show_synergies()

	player_soldiers_at_start = my_soldiers.size()
	# Стены дают цитадели щит на этот бой
	var shield: float = 0.0
	for b in BattleManager.buildings:
		shield += b.get_citadel_shield()
	BattleManager.citadel_shield = shield
	BattleManager.emit_signal("citadel_hp_changed", BattleManager.citadel_hp)
	BattleManager.start_battle()

# Командир (Chapter Master): +урон всем союзникам, один раз перед боем.
# Несколько командиров не суммируются — берётся самый сильный бонус.
func _apply_commander_bonus(soldiers: Array) -> void:
	var bonus: float = 0.0
	for s in soldiers:
		bonus = max(bonus, s.data.commander_damage_bonus)
	if bonus <= 0.0:
		return
	for s in soldiers:
		s.current_damage *= 1.0 + bonus
	print("BattleScene: командир — +%d%% урона армии" % int(round(bonus * 100.0)))

# -------------------------------------------------------
# КОНЕЦ БОЯ
# -------------------------------------------------------
func _on_battle_ended(winner_team: int) -> void:
	# Итог боя обрабатывается ровно один раз: доход, round_number, узел карты
	if _battle_resolved:
		return
	_battle_resolved = true
	if BattleManager.citadel_hp <= 0:
		_game_over()
		return
	# Босс повержен — забег выигран (доход уже не нужен: забег окончен)
	if battle_type == RunMapNode.BOSS and winner_team == GameConstants.TEAM_PLAYER:
		RunManager.complete_current_node()
		SquadRegistry.clear()
		SoldierRegistry.clear()
		_show_run_end(true)
		return
	if winner_team == GameConstants.TEAM_PLAYER:
		var bonuses = _calculate_victory_bonuses()
		var income = EconomyManager.give_round_income(true, bonuses)
		if BattleManager.siege_started:
			result_label.text = "Цитадель выстояла! +%d Req" % income
		else:
			result_label.text = "Победа! +%d Req" % income
		_save_survivors()
	elif winner_team == GameConstants.TEAM_ENEMY:
		var income = EconomyManager.give_round_income(false)
		result_label.text = "Поражение! +%d Req" % income
		BattleManager.player_units.clear()
		BattleManager.player_placements.clear()
	else:
		var income = EconomyManager.give_round_income(false)
		result_label.text = "Ничья! +%d Req" % income
		BattleManager.player_units.clear()
		BattleManager.player_placements.clear()

	# BattleManager.pending_cards НЕ очищаем: невыложенные карты остаются
	# в руке игрока и переносятся дальше по карте (лимит руки — MAX_HAND_SIZE)
	SquadRegistry.clear()
	SoldierRegistry.clear()
	RunManager.complete_current_node(winner_team == GameConstants.TEAM_PLAYER)
	# Босс не побеждён без гибели цитадели (бывает только без цитадели) — забег проигран
	if battle_type == RunMapNode.BOSS:
		_show_run_end(false)
		return
	# Следующая волна начинается с магазина
	await get_tree().create_timer(2.0).timeout
	RunManager.advance()

# Цитадель пала — забег окончен: экран поражения, по кнопке — новый забег
func _game_over() -> void:
	result_label.text = "Цитадель пала!"
	SquadRegistry.clear()
	SoldierRegistry.clear()
	_show_run_end(false)

# Экран конца забега (TDD: Victory / Game Over). Кнопка — новый забег с первого магазина.
func _show_run_end(victory: bool) -> void:
	var total = RunManager.get_total_waves()
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	$UI.add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel = PanelContainer.new()
	panel.theme = UITheme.get_theme()
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var title = UITheme.make_label("ПОБЕДА" if victory else "ЦИТАДЕЛЬ ПАЛА", "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not victory:
		title.add_theme_color_override("font_color", UITheme.RED_BRIGHT)
	col.add_child(title)
	var text = "Главный босс Хаоса повержен — забег выигран!" if victory 		else "Забег окончен на волне %d из %d." % [battle_wave, total]
	var sub = UITheme.make_label(text, "HeaderLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var stats = UITheme.make_label("Побед в волнах: %d · Цитадель %d/%d · %d Req" % [
		EconomyManager.wins + (1 if victory else 0), ceili(BattleManager.citadel_hp),
		int(BattleManager.CITADEL_MAX_HP), EconomyManager.requisition], "SmallLabel")
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(stats)
	var again = Button.new()
	again.theme_type_variation = "PrimaryButton"
	again.text = "НОВЫЙ ЗАБЕГ"
	again.pressed.connect(_on_new_run_pressed)
	col.add_child(again)
	print("BattleScene: забег окончен — %s" % ("победа" if victory else "поражение"))

func _on_new_run_pressed() -> void:
	BattleManager.reset_run()
	RunManager.advance()

# Бонусы TDD к доходу за победу. Кап +8 применяет EconomyManager.
# «Без потерь», синергия фракции и +3 за каждого элитного врага (на победе убиты все).
func _calculate_victory_bonuses() -> int:
	var bonuses = SynergyManager.income_bonus
	var alive = SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER).size()
	if player_soldiers_at_start > 0 and alive == player_soldiers_at_start:
		bonuses += EconomyManager.BONUS_FLAWLESS
	bonuses += enemy_elites_at_start * EconomyManager.BONUS_ELITE_KILL
	return bonuses

# -------------------------------------------------------
# UI СИНЕРГИЙ
# -------------------------------------------------------
# Вёрстка UI боя кодом: фон, HUD сверху, панель синергий справа снизу.
# Скамейка (Bench) сама занимает низ слева.
func _build_ui() -> void:
	var bg_layer = CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	bg_layer.add_child(UITheme.make_background())

	# Бойцы рисуются по глубине: кто ниже на экране — тот ближе
	units_container.y_sort_enabled = true

	# --- HUD ---
	hud = PanelContainer.new()
	hud.theme = UITheme.get_theme()
	hud.theme_type_variation = "HudPanel"
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.offset_bottom = UITheme.HUD_HEIGHT
	$UI.add_child(hud)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	hud.add_child(row)
	var wave_text = "Волна %d/%d" % [battle_wave, RunManager.get_total_waves()]
	if battle_type != RunMapNode.BATTLE:
		wave_text += " · " + UITheme.NODE_NAMES.get(battle_type, battle_type)
	var wave = UITheme.make_label(wave_text, "HeaderLabel")
	row.add_child(wave)
	requisition_label = UITheme.make_label("", "ValueLabel")
	row.add_child(requisition_label)
	_update_requisition(EconomyManager.requisition)
	EconomyManager.requisition_changed.connect(_update_requisition)
	citadel_label = UITheme.make_label("", "ValueLabel")
	row.add_child(citadel_label)
	_update_citadel_label(BattleManager.citadel_hp)
	BattleManager.citadel_hp_changed.connect(_update_citadel_label)

	result_label.reparent(row)
	result_label.theme_type_variation = "HeaderLabel"
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Длинные подсказки обрезаются, а не выталкивают кнопку «В БОЙ» за экран
	result_label.clip_text = true
	result_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.text = "Расставьте отряды"

	start_button.reparent(row)
	start_button.theme_type_variation = "PrimaryButton"
	start_button.text = "В БОЙ"
	start_button.custom_minimum_size = Vector2(180, 0)

	# --- Панель синергий ---
	var syn_panel = PanelContainer.new()
	syn_panel.theme = UITheme.get_theme()
	syn_panel.theme_type_variation = "HudPanel"
	syn_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	syn_panel.offset_left = -bench.BENCH_RIGHT_RESERVE
	syn_panel.offset_top = -UITheme.BENCH_HEIGHT
	syn_panel.offset_right = 0
	syn_panel.offset_bottom = 0
	$UI.add_child(syn_panel)
	var col = VBoxContainer.new()
	syn_panel.add_child(col)
	col.add_child(UITheme.make_label("СИНЕРГИИ", "HeaderLabel"))
	synergy_label = UITheme.make_label("", "SmallLabel")
	synergy_label.name = "SynergyLabel"
	synergy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	synergy_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(synergy_label)

func _update_requisition(amount: int) -> void:
	requisition_label.text = "%d Req" % amount

func _update_citadel_label(hp: float) -> void:
	citadel_label.text = "Цитадель %d/%d" % [ceili(hp), int(BattleManager.CITADEL_MAX_HP)]
	if BattleManager.citadel_shield > 0.0:
		citadel_label.text += " +%d щит" % ceili(BattleManager.citadel_shield)
	citadel_label.add_theme_color_override("font_color",
		UITheme.RED_BRIGHT if hp <= BattleManager.CITADEL_MAX_HP / 4 else UITheme.GOLD_BRIGHT)

# Во время расстановки — только предпросмотр, бойцам ничего не применяем
func _update_synergy_preview() -> void:
	SynergyManager.calculate_synergies(SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER))
	_show_synergies()

func _show_synergies() -> void:
	var lines: Array[String] = []
	for s in SynergyManager.active_synergies:
		lines.append("• %s — %s" % [s["name"], s["desc"]])
	if lines.is_empty():
		lines.append("Нет активных синергий (3+ Marine → +15% HP)")
	var marines = SynergyManager.tag_counts.get(SynergyManager.INCOME_TAG, 0)
	lines.append("Marine: %d · доход синергии +%d Req" % [marines, SynergyManager.income_bonus])
	synergy_label.text = "\n".join(lines)

# -------------------------------------------------------
# СОХРАНЕНИЕ ВЫЖИВШИХ
# -------------------------------------------------------
func _save_survivors() -> void:
	BattleManager.player_units.clear()
	BattleManager.player_placements.clear()

	# Сохраняем по отряду: один UnitData + доля HP каждого живого бойца
	var soldier_count = 0
	for squad in SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER):
		var hp_list: Array[float] = []
		for soldier in squad.soldiers:
			if soldier.current_state != Soldier.State.DEAD:
				hp_list.append(soldier.current_hp / soldier.max_hp)
		if hp_list.is_empty():
			continue
		squad.data.saved_hp = hp_list
		BattleManager.player_units.append(squad.data)
		BattleManager.player_placements[squad.data] = squad.tile
		soldier_count += hp_list.size()

	print("BattleScene: выжило %d отрядов, %d бойцов" % [BattleManager.player_units.size(), soldier_count])

# -------------------------------------------------------
# DROP КАРТЫ НА ТАЙЛ
# -------------------------------------------------------
func _on_card_dropped(card: CardData, screen_pos: Vector2) -> void:
	if not is_placement_phase:
		return
	_close_merge_menu()
	var tile = iso_grid.screen_to_tile(screen_pos, false)

	if not iso_grid.is_valid_tile(tile):
		_show_message("Мимо сетки")
		return

	match card.card_type:
		"squad":
			# Карта на свой отряд того же типа — улучшить или вылечить
			var own = _get_player_squad_at(tile)
			if own and own.data.factory_id == card.unit_factory_id:
				_open_merge_menu(card, own)
				return
			if _is_tile_occupied(tile):
				_show_message("Тайл занят")
				return
			var unit_data = _create_unit_from_card(card)
			unit_data.squad_size = card.unit_count
			_spawn_squad(unit_data, GameConstants.TEAM_PLAYER, tile, card.unit_count)
			_consume_bench_card(card)
		"upgrade":
			# Улучшение бросают НА свой отряд
			var squad = _get_player_squad_at(tile)
			if squad == null:
				_show_message("%s: перетащите на свой отряд" % card.title)
				return
			if not squad.apply_upgrade(card):
				_show_message("%s действует только на отряды «%s»" % [card.title, card.affects_tag])
				return
			_show_message("%s → %s (%s)" % [card.title, squad.data.unit_name, card.description])
			_consume_bench_card(card)
		"building":
			if _is_tile_occupied(tile):
				_show_message("Тайл занят")
				return
			_spawn_building(card, tile)
			BattleManager.player_buildings[card] = tile
			_consume_bench_card(card)
			_show_message("Построено: %s" % card.title)

# -------------------------------------------------------
# КАРТА ОТРЯДА НА ТАКОЙ ЖЕ ОТРЯД: УЛУЧШЕНИЕ / ЛЕЧЕНИЕ
# -------------------------------------------------------
func _open_merge_menu(card: CardData, squad: Squad) -> void:
	var can_upgrade = squad.data.can_merge_upgrade()
	var wounded = squad.is_wounded()
	if not can_upgrade and not wounded:
		_show_message("%s: максимальный уровень, отряд здоров" % squad.data.unit_name)
		return
	var b = UnitFactory.get_merge_bonuses(squad.data.faction)

	merge_menu = PanelContainer.new()
	merge_menu.theme = UITheme.get_theme()
	merge_menu.theme_type_variation = "HudPanel"
	$UI.add_child(merge_menu)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	merge_menu.add_child(col)
	col.add_child(UITheme.make_label("%s — уровень %d/%d" % [squad.data.unit_name,
		squad.data.squad_level, UnitFactory.MAX_SQUAD_LEVEL], "HeaderLabel"))

	var up = Button.new()
	up.text = "Улучшить: +%d%% урона, +%d%% HP, +%d%% скорострельности" % [
		roundi(b["damage"] * 100), roundi(b["hp"] * 100), roundi(b["attack_speed"] * 100)]
	if not can_upgrade:
		up.text = "Улучшить: достигнут максимум"
	up.disabled = not can_upgrade
	up.pressed.connect(_on_merge_chosen.bind(card, squad, true))
	col.add_child(up)

	var heal = Button.new()
	heal.text = "Вылечить: +%d%% HP каждому бойцу" % roundi(b["heal"] * 100)
	if squad.get_missing_count() > 0:
		heal.text += ", вернуть павших: %d" % squad.get_missing_count()
	if not wounded:
		heal.text = "Вылечить: отряд здоров"
	heal.disabled = not wounded
	heal.pressed.connect(_on_merge_chosen.bind(card, squad, false))
	col.add_child(heal)

	var cancel = Button.new()
	cancel.text = "Отмена"
	cancel.pressed.connect(_close_merge_menu)
	col.add_child(cancel)

	# Рядом с отрядом, но в пределах экрана
	merge_menu.reset_size()
	var pos = squad.global_position + Vector2(-merge_menu.size.x / 2.0, 20)
	var screen = get_viewport_rect().size
	merge_menu.position = pos.clamp(Vector2.ZERO, screen - merge_menu.size)

func _on_merge_chosen(card: CardData, squad: Squad, upgrade: bool) -> void:
	_close_merge_menu()
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

func _close_merge_menu() -> void:
	if merge_menu:
		merge_menu.queue_free()
		merge_menu = null

func _consume_bench_card(card: CardData) -> void:
	bench.bench_cards.erase(card)
	bench._populate()

func _get_player_squad_at(tile: Vector2i) -> Squad:
	for squad in SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER):
		if squad.tile == tile:
			return squad
	return null

# Подсказка игроку в шапке (во время расстановки) + в консоль
func _show_message(text: String) -> void:
	print("BattleScene: ", text)
	result_label.text = text
