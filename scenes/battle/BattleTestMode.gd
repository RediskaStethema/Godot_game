class_name BattleTestMode
extends Node

# Тестовый режим боя (RunManager.test_mode, решение пользователя 06.11.2026): панель карт, магазин из панели, волна и
# тип боя, итог без дохода и возврат расстановки. Узел-помощник BattleScene (вынесен 26.11.2026): поле, рука и камера —
# у сцены (`scene`), сама панель — `scene.test_panel`.

var scene: BattleScene

const TEST_RESULT_TIME: float = 3.0   # сек после итога — назад к расстановке

func build_panel() -> void:
	scene.test_panel = TestPanel.new()
	scene.get_node("UI").add_child(scene.test_panel)
	scene.test_panel.setup(RunManager.player_faction)
	scene.test_panel.card_picked.connect(_on_card_picked)
	scene.test_panel.wave_changed.connect(func(wave):
		RunManager.test_wave = wave
		_reload_placement())
	scene.test_panel.type_changed.connect(func(kind):
		RunManager.test_battle_type = kind
		_reload_placement())
	scene.test_panel.boss_changed.connect(func(id):
		RunManager.test_boss = id
		_reload_placement())
	scene.test_panel.level_changed.connect(func(level): scene._show_message("Из панели: отряды ур.%d, здания ур.%d" % [level, mini(1 + level, CardData.MAX_BUILDING_LEVEL)]))
	scene.test_panel.clear_pressed.connect(_on_clear)
	scene.test_panel.shop_pressed.connect(open_shop)

# Карта из панели — в руку бесплатно (лимит руки тот же)
func _on_card_picked(card_id: String) -> void:
	if not scene.is_placement_phase:
		return
	if scene.bench.bench_cards.size() >= BattleManager.MAX_HAND_SIZE:
		scene._show_message("Рука полна (%d) — сыграйте карту" % BattleManager.MAX_HAND_SIZE)
		return
	var card := CardFactory.create(card_id)
	if card == null:
		return
	scene.bench.bench_cards.append(card)
	scene.bench._populate()
	scene._show_message("В руке: %s" % card.display_title())

# Магазин из тестового режима (решение пользователя 21.11.2026: «добавь в тестовый режим возможность зайти в магазин»):
# то же окно поверх поля, что в забеге (ShopScene embedded), но без шага цепочки: набор каждый раз новый, монет
# TEST_SHOP_REQUISITION (долить до этой суммы), покупки — в руку расстановки, «В БОЙ» — просто закрыть и вернуться к полю
const TEST_SHOP_REQUISITION: int = 200
var _test_shop_node := {}   # шаг цепочки до входа: ShopScene.ensure_started его трогает — вернуть как было

func open_shop() -> void:
	if not RunManager.test_mode or not scene.is_placement_phase or scene.shop_phase or scene.shop != null:
		return
	BattleManager.sync_army_from_squads(SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER))
	if EconomyManager.requisition < TEST_SHOP_REQUISITION:
		EconomyManager.add_requisition(TEST_SHOP_REQUISITION - EconomyManager.requisition)
	_test_shop_node = {"id": RunManager.current_node_id, "done": RunManager.current_completed}
	ShopManager.shop_node_id = -1   # новый набор, а не прежний этого шага
	scene.shop_phase = true
	scene.get_node("UI").visible = false
	scene.bench.visible = false
	scene._fit_camera(false)
	var layer := CanvasLayer.new()
	layer.name = "ShopLayer"
	layer.layer = scene.SHOP_LAYER
	scene.add_child(layer)
	scene.shop = scene.SHOP_SCENE.instantiate()
	scene.shop.set("embedded", true)
	layer.add_child(scene.shop)
	scene.shop.connect("finished", _close_shop)

func _close_shop() -> void:
	if scene.shop == null:
		return
	var layer: Node = scene.shop.get_parent()
	scene.shop = null
	layer.queue_free()
	RunManager.current_node_id = int(_test_shop_node.get("id", RunManager.current_node_id))
	RunManager.current_completed = bool(_test_shop_node.get("done", RunManager.current_completed))
	ShopManager.shop_node_id = -1
	scene.shop_phase = false
	scene.get_node("UI").visible = true
	scene.bench.setup(BattleManager.pending_cards)   # рука магазина — новый массив (покупки / продажи)
	scene.bench.visible = true
	AudioManager.play_music("battle")
	scene._fit_camera(true)

# Волна или тип боя сменились — поле как есть, враги — новые (сцена заново)
func _reload_placement() -> void:
	BattleManager.sync_army_from_squads(SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER))
	RunManager.reload_test_battle()

func _on_clear() -> void:
	BattleManager.player_units.clear()
	BattleManager.player_placements.clear()
	BattleManager.player_buildings.clear()
	BattleManager.armed_events.clear()
	BattleManager.armed_tiles.clear()
	RunManager.reload_test_battle()

# Итог боя в тесте: баннер и итоги, без дохода, шага забега, меты и сохранения; затем расстановка как до боя
func end_battle(winner_team: int) -> void:
	var alive_at_end := SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER).filter(func(s): return not s.charmed).size()
	var won := winner_team == GameConstants.TEAM_PLAYER
	scene.hud.show_result(scene._result_title(winner_team), scene._battle_summary(alive_at_end), won)
	scene.hud.set_message("Тест: через %d с — снова расстановка" % int(TEST_RESULT_TIME))
	scene._play_finale_slowmo()
	SquadRegistry.clear()
	SoldierRegistry.clear()
	scene.get_tree().create_timer(TEST_RESULT_TIME, false).timeout.connect(_restore_field)

func _restore_field() -> void:
	if not RunManager.test_mode or not scene.is_inside_tree():   # за 3 с ушли в меню — тест окончен, поле не возвращать
		return
	if not RunManager.test_snapshot.is_empty():
		BattleManager.player_units.clear()
		BattleManager.player_placements.clear()
		BattleManager.player_buildings.clear()
		BattleManager.load_state(RunManager.test_snapshot)
	BattleManager.battle_in_progress = false
	BattleManager.citadel_hp = BattleManager.CITADEL_MAX_HP
	RunManager.reload_test_battle()
