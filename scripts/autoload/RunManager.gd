extends Node

# -------------------------------------------------------
# ЗАБЕГ — состояние
# -------------------------------------------------------
# Отдельный autoload, а не поля BattleManager: BattleManager отвечает за бой
# и его тик, а цепочка шагов забега и текущий шаг — навигация между сценами.
# Сбрасывается из BattleManager.reset_run() (new_run()), генерирует RunMapData.
#
# Цикл линейный, игрок путь не выбирает: магазин → бой → (EventScene) → магазин → …
# Магазин — окно поверх поля в BattleScene (решение пользователя 12.11.2026, образец download.png: сквозь магазин
# видно поле): шаг SHOP открывает BattleScene, «В БОЙ» магазина — enter_battle_in_place() без смены сцены
# Шаг завершён → advance() сам открывает следующий. round_number растёт только в
# EconomyManager.give_round_income (один бой = одна волна).

const SHOP_SCENE: String = "res://scenes/shop/ShopScene.tscn"   # окно магазина (BattleScene кладёт поверх поля)
const BATTLE_SCENE: String = "res://scenes/battle/BattleScene.tscn"
const EVENT_SCENE: String = "res://scenes/event/EventScene.tscn"
const PICK_SCENE: String = "res://scenes/pick/CardPickScene.tscn"   # выбор карты после волны (16.11.2026)
const MENU_SCENE: String = "res://scenes/menu/MainMenu.tscn"
# Переход между сценами (решение пользователя 08.11.2026, только вид): сцена меняется сразу (тесты и сохранения
# ничего не ждут), поверх — чёрная шторка на слое FADE_LAYER, тает за FADE_TIME (по реальному времени, и на паузе)
const FADE_LAYER: int = 100
const FADE_TIME: float = 0.35
var _fade: CanvasLayer = null
var _fade_rect: ColorRect = null
var _fade_tween: Tween = null

signal run_started
signal node_entered(node: RunMapNode)
signal node_completed(node: RunMapNode)

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var map: RunMapData = null
var current_node_id: int = -1        # -1 — забег только начат, первый шаг не открыт
var current_completed: bool = true   # текущий шаг пройден — можно идти дальше
var run_won: bool = false            # босс повержен

func _ready() -> void:
	new_run()

# Раса игрока на забег: от неё оформление поля и цитадели (FactionTheme).
# Выбор расы — позже; новый забег её не сбрасывает (выбирается до new_run)
var player_faction: String = FactionTheme.DEFAULT_FACTION
# Орден Космодесанта / бог Хаоса (Chapters) — выбирается после расы; "" — без ордена
var player_chapter: String = ""
# Уровень сложности забега (Difficulty, 1..COUNT) — выбирается после ордена, новый забег его не сбрасывает
var difficulty: int = Difficulty.DEFAULT

# Тестовый режим (решение пользователя 06.11.2026, только в сборке для разработки — OS.is_debug_build):
# сразу расстановка, панель со всеми картами расы (TestPanel), волна и тип боя на выбор, цитадель не падает,
# королевство 4×4; после боя — та же расстановка (test_snapshot), без сохранения, Славы и открытий меты
var test_mode: bool = false
# Посадка на поле (BattleLanding, решение пользователя 08.11.2026): ставят MainMenu (после взлёта MenuLaunch) и
# «НОВЫЙ ЗАБЕГ» экрана итога, снимает первое поле забега (BattleScene._ready); не сохраняется, выход в меню снимает
var landing_pending: bool = false
var test_wave: int = 1
var test_battle_type: String = RunMapNode.BATTLE
var test_level: int = 0                 # улучшений у отрядов (ур.N) и зданий (ур. 1 + N) из панели
var test_boss: String = ""              # финальный босс боя «босс» (любой из 9 примархов); "" — от seed, как в забеге
var test_snapshot: Dictionary = {}      # BattleManager.save_state() перед «В БОЙ» — после боя поле как было

static func test_mode_available() -> bool:
	return OS.is_debug_build()

# Вход в тестовый режим: раса и орден выбраны в главном меню
func start_test_mode(faction: String, chapter: String) -> void:
	player_faction = faction
	BattleManager.reset_run()
	BattleManager.pending_cards.clear()   # без стартовой карты меты
	player_chapter = chapter
	test_mode = true
	test_wave = 1
	test_battle_type = RunMapNode.BATTLE
	test_level = 0
	test_boss = ""
	test_snapshot = {}
	BattleManager.kingdom_tiles.clear()
	for row in IsoGrid.MAX_KINGDOM_SIZE.y:   # 4×4 = MAX_KINGDOM_TILES: расширять некуда
		for col in IsoGrid.MAX_KINGDOM_SIZE.x:
			BattleManager.kingdom_tiles.append(Vector2i(col, row))
	_go(BATTLE_SCENE)

# Тестовый режим: новая расстановка (волна / тип боя сменились, бой кончился) — сцена боя заново
func reload_test_battle() -> void:
	get_tree().paused = false
	BattleManager.stop_battle()
	_go(BATTLE_SCENE)

func new_run(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	map = RunMapData.generate(rng)
	test_mode = false
	current_node_id = -1
	current_completed = true
	run_won = false
	print("RunManager: новый забег — %d узлов, %d волн" % [map.nodes.size(), map.total_waves])
	emit_signal("run_started")

# -------------------------------------------------------
# НАВИГАЦИЯ
# -------------------------------------------------------
func get_current_node() -> RunMapNode:
	return map.get_node_by_id(current_node_id) if map else null

# Входит в шаг и меняет сцену (магазин / бой)
func enter_node(id: int) -> bool:
	if not _set_current(id):
		return false
	var node = map.get_node_by_id(id)
	match node.type:
		RunMapNode.SHOP:
			_go(BATTLE_SCENE)   # магазин — окном поверх поля (BattleScene.shop_phase)
		RunMapNode.EVENT:
			_go(EVENT_SCENE)
		RunMapNode.PICK, RunMapNode.START_PICK:
			_go(BATTLE_SCENE)   # выбор карты — окном поверх поля следующего боя (BattleScene.shop_phase), как магазин
		RunMapNode.BATTLE, RunMapNode.MINIBOSS, RunMapNode.BOSS:
			if node.wave != EconomyManager.round_number:
				push_warning("RunManager: волна шага %d ≠ round_number %d" % [node.wave, EconomyManager.round_number])
			_go(BATTLE_SCENE)
	return true

# Делает шаг текущим без смены сцены
func _set_current(id: int) -> bool:
	if id < 0 or id != get_next_id():
		return false
	var node = map.get_node_by_id(id)
	if id != current_node_id:
		current_node_id = id
		current_completed = false
		print("RunManager: шаг %d (%s, волна %d)" % [id, node.type, node.wave])
		emit_signal("node_entered", node)
	return true

# Следующий шаг цепочки: старт → первый; незавершённый — он сам; иначе — next.
# Шагов нет (забег выигран) — -1.
func get_next_id() -> int:
	if map == null or run_won or map.nodes.is_empty():
		return -1
	if current_node_id < 0:
		return 0
	if not current_completed:
		return current_node_id
	var next = get_current_node().next
	return next[0] if not next.is_empty() else -1

# Магазин закрыт «В БОЙ» (BattleScene): следующий шаг — бой — становится текущим без смены сцены
# (поле уже стоит под магазином). false — следующий шаг не бой (тогда — advance со сменой сцены)
func enter_battle_in_place() -> bool:
	var id := get_next_id()
	var node: RunMapNode = map.get_node_by_id(id) if map and id >= 0 else null
	if node == null or not node.is_battle():
		return false
	return _set_current(id)

# Бой, к которому готовит открытый магазин (шаг после него); нет — null
func get_upcoming_battle() -> RunMapNode:
	if not is_shop_node_active() and not is_pick_node_active():
		return null
	var next = get_current_node().next
	var node: RunMapNode = map.get_node_by_id(next[0]) if not next.is_empty() else null
	return node if node and node.is_battle() else null

# Переход к следующему шагу забега со сменой сцены (вызывают сцены по итогам шага)
func advance() -> void:
	var id = get_next_id()
	if id < 0 or not enter_node(id):
		push_warning("RunManager: следующего шага нет")

# В главное меню посреди забега (пауза / экран конца забега). Прогресс уже
# в автосохранении; идущий бой останавливается, чтобы BattleManager не тикал
# отряды удалённой сцены
func goto_main_menu() -> void:
	get_tree().paused = false
	landing_pending = false
	if test_mode:   # тест не продолжается: армия и поле — тестовые
		test_mode = false
		test_snapshot = {}
		BattleManager.reset_run()
		player_chapter = ""
	BattleManager.stop_battle()
	_go(MENU_SCENE)

# Сдача вне схватки (магазин, расстановка, итог боя) — конец забега без экрана
# итога: сохранение удаляется, в главное меню. В схватке — BattleManager.surrender()
func abandon_run() -> void:
	if test_mode:   # «Сдаться» в тесте — просто выход: ни Славы, ни сохранения
		goto_main_menu()
		return
	MetaProgress.on_run_end(false)   # сдача — тоже конец забега: Слава за пройденное
	SaveManager.delete_save()
	goto_main_menu()

# Продолжить загруженный забег (SaveManager.load_run): незавершённый шаг —
# открыть его заново (бой — с расстановки), завершённый — перейти к следующему
func resume() -> void:
	if current_node_id >= 0 and not current_completed:
		enter_node(current_node_id)
	else:
		advance()

# Сцена открыта напрямую (главная сцена — магазин): забег ещё не начат —
# первый шаг становится текущим без смены сцены
func ensure_started() -> void:
	if current_node_id < 0 and not run_won:
		_set_current(get_next_id())

# Вызывают сцены шагов: магазин — при уходе, бой — по итогам
func complete_current_node(won: bool = true) -> void:
	var node = get_current_node()
	if node == null or current_completed:
		return
	current_completed = true
	if node.type == RunMapNode.BOSS and won:
		run_won = true
		print("RunManager: босс повержен — забег выигран")
	emit_signal("node_completed", node)

# -------------------------------------------------------
# СОХРАНЕНИЕ (SaveManager) — своё состояние забега
# -------------------------------------------------------
# seed/state — 64-битные: в JSON строками (число потеряло бы точность);
# state ставится после seed. Граф не хранится: RunMapData.generate() детерминирован
func save_state() -> Dictionary:
	return {
		"rng_seed": str(rng.seed),
		"rng_state": str(rng.state),
		"current_node_id": current_node_id,
		"current_completed": current_completed,
		"player_faction": player_faction,
		"player_chapter": player_chapter,
		"difficulty": difficulty,
	}

func load_state(d: Dictionary) -> void:
	rng.seed = str(d["rng_seed"]).to_int()
	rng.state = str(d["rng_state"]).to_int()
	current_node_id = int(d["current_node_id"])
	current_completed = bool(d["current_completed"])
	player_faction = str(d.get("player_faction", FactionTheme.DEFAULT_FACTION))
	player_chapter = str(d.get("player_chapter", ""))
	difficulty = clampi(int(d.get("difficulty", Difficulty.DEFAULT)), 1, Difficulty.COUNT)

# -------------------------------------------------------
# ДЛЯ БОЯ
# -------------------------------------------------------
# Тип текущего боя; если BattleScene запущена напрямую — обычный бой
func get_battle_type() -> String:
	if test_mode:
		return test_battle_type
	var node = get_current_node()
	if node and node.is_battle() and not current_completed:
		return node.type
	var upcoming := get_upcoming_battle()   # магазин поверх поля — поле следующего боя
	if upcoming:
		return upcoming.type
	return RunMapNode.BATTLE

func get_battle_wave() -> int:
	if test_mode:
		return test_wave
	var node = get_current_node()
	if node and node.is_battle() and not current_completed:
		return node.wave
	var upcoming := get_upcoming_battle()
	if upcoming:
		return upcoming.wave
	return EconomyManager.round_number

# -------------------------------------------------------
# СОБЫТИЯ
# -------------------------------------------------------
# Событие текущего шага (пусто — шаг не событие). Детерминировано от seed забега:
# «Продолжить» покажет то же событие
func get_current_event() -> Dictionary:
	var node = get_current_node()
	if node == null or node.type != RunMapNode.EVENT:
		return {}
	return RunEvents.for_run(rng.seed, map.get_event_index(current_node_id))

# Случайность исхода события (риск, случайная карта / отряд) — от seed забега и шага:
# перезапуск не перебрасывает результат
func get_event_rng() -> RandomNumberGenerator:
	var r = RandomNumberGenerator.new()
	r.seed = hash([rng.seed, current_node_id, "event"])
	return r

func get_total_waves() -> int:
	return map.total_waves if map else 0

func is_shop_node_active() -> bool:
	var node = get_current_node()
	return node != null and node.type == RunMapNode.SHOP and not current_completed

func is_pick_node_active() -> bool:
	var node = get_current_node()
	return node != null and node.is_pick() and not current_completed

# Стартовый выбор забега: 6 карт рубашкой вверх, берёт 3 вслепую (вместо магазина волны 1, 17.11.2026)
func is_start_pick_active() -> bool:
	var node = get_current_node()
	return node != null and node.type == RunMapNode.START_PICK and not current_completed

# Смена сцены со шторкой: всё, что меняет сцену забега, — через _go
func _go(path: String) -> void:
	get_tree().change_scene_to_file(path)
	if _fade == null:
		_fade = CanvasLayer.new()
		_fade.layer = FADE_LAYER
		_fade.process_mode = Node.PROCESS_MODE_ALWAYS
		_fade_rect = ColorRect.new()
		_fade_rect.color = Palette.BG_DEEP
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.add_child(_fade_rect)
		_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		get_tree().root.add_child.call_deferred(_fade)
	if _fade_tween:
		_fade_tween.kill()
	_fade_rect.modulate.a = 1.0
	_fade_tween = create_tween().set_ignore_time_scale(true)
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_fade_rect, "modulate:a", 0.0, FADE_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
