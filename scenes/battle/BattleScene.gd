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
var synergy_label: Label = null
var hud: PanelContainer = null
var requisition_label: Label = null

# -------------------------------------------------------
# ИНИЦИАЛИЗАЦИЯ
# -------------------------------------------------------
func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	BattleManager.battle_ended.connect(_on_battle_ended)

	# Скамейку создаём до сетки — её панель ограничивает игровую область снизу
	bench = BENCH_SCENE.instantiate()
	add_child(bench)
	bench.setup(BattleManager.pending_cards)
	bench.card_dropped_on_tile.connect(_on_card_dropped)
	_build_ui()

	iso_grid.expand_grid(1)
	iso_grid.setup(get_viewport_rect().size, _get_play_area())

	var renderer = IsoGridRenderer.new()
	renderer.setup(iso_grid)
	grid_renderer.add_child(renderer)

	# Очищаем занятые тайлы — новый раунд с чистого поля
	renderer.occupied_tiles_player.clear()
	renderer.occupied_tiles_enemy.clear()
	renderer.queue_redraw()

	_place_enemy_squads()
	_place_player_squads()
	_update_synergy_preview()

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
func _place_enemy_squads() -> void:
	var round = EconomyManager.round_number
	var squad_count = min(round + 1, iso_grid.grid_width * iso_grid.grid_height)
	var stat_mult = 1.0 + (round - 1) * 0.15
	var soldiers_per_squad = min(round + 1, 6)

	# Враги занимают зону с переднего края (ближе к королевству) в тыл
	var all_tiles = iso_grid.get_enemy_tiles_front_first()
	for i in range(squad_count):
		if i >= all_tiles.size():
			break
		var enemy_data = UnitFactory.chaos_marine()
		enemy_data.hp_multiplier = stat_mult
		enemy_data.damage_multiplier = stat_mult
		_spawn_squad(enemy_data, GameConstants.TEAM_ENEMY, all_tiles[i], soldiers_per_squad)

# -------------------------------------------------------
# СПАВН ОТРЯДА
# -------------------------------------------------------
func _spawn_squad(unit_data: UnitData, team: int, tile: Vector2i, count: int, hp_list: Array[float] = []) -> void:
	var squad = SQUAD_SCENE.instantiate()
	units_container.add_child(squad)
	squad.setup(unit_data, team, tile, count, hp_list)
	squad.global_position = iso_grid.tile_to_screen(tile, team == GameConstants.TEAM_ENEMY)
	SquadRegistry.register(squad)

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
	if not is_placement_phase:
		return
	if event is InputEventMouseMotion:
		var tile = iso_grid.screen_to_tile(event.position, false)
		var renderer = grid_renderer.get_child(0) as IsoGridRenderer
		if renderer:
			renderer.update_hover(tile)

# -------------------------------------------------------
# БОЙ
# -------------------------------------------------------
func _on_start_pressed() -> void:
	is_placement_phase = false
	start_button.disabled = true
	result_label.text = "Бой идёт..."

	for squad in SquadRegistry.get_all_alive_squads():
		squad.start_march()

	# Синергии считаются по бойцам на поле и применяются один раз перед боем
	var my_soldiers = SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER)
	SynergyManager.calculate_synergies(my_soldiers)
	SynergyManager.apply_synergies_to_soldiers(my_soldiers)
	_show_synergies()

	player_soldiers_at_start = my_soldiers.size()
	BattleManager.start_battle()

# -------------------------------------------------------
# КОНЕЦ БОЯ
# -------------------------------------------------------
func _on_battle_ended(winner_team: int) -> void:
	if winner_team == GameConstants.TEAM_PLAYER:
		var bonuses = _calculate_victory_bonuses()
		var income = EconomyManager.give_round_income(true, bonuses)
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
	# в руке игрока и возвращаются в магазин (лимит руки — MAX_HAND_SIZE)
	SquadRegistry.clear()
	SoldierRegistry.clear()
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/shop/ShopScene.tscn")

# Бонусы TDD к доходу за победу. Кап +8 применяет EconomyManager.
# Есть: «без потерь» и синергия фракции; элитных врагов пока нет.
func _calculate_victory_bonuses() -> int:
	var bonuses = SynergyManager.income_bonus
	var alive = SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER).size()
	if player_soldiers_at_start > 0 and alive == player_soldiers_at_start:
		bonuses += EconomyManager.BONUS_FLAWLESS
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
	var wave = UITheme.make_label("Волна %d" % EconomyManager.round_number, "HeaderLabel")
	row.add_child(wave)
	requisition_label = UITheme.make_label("", "ValueLabel")
	row.add_child(requisition_label)
	_update_requisition(EconomyManager.requisition)
	EconomyManager.requisition_changed.connect(_update_requisition)

	result_label.reparent(row)
	result_label.theme_type_variation = "HeaderLabel"
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var tile = iso_grid.screen_to_tile(screen_pos, false)

	if not iso_grid.is_valid_tile(tile):
		_show_message("Мимо сетки")
		return

	match card.card_type:
		"squad":
			if _is_tile_occupied(tile):
				_show_message("Тайл занят")
				return
			var unit_data = _create_unit_from_card(card)
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
			_show_message("Здания пока не реализованы")

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
