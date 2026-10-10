extends Node

# -------------------------------------------------------
# ЗАБЕГ — состояние
# -------------------------------------------------------
# Отдельный autoload, а не поля BattleManager: BattleManager отвечает за бой
# и его тик, а цепочка шагов забега и текущий шаг — навигация между сценами.
# Сбрасывается из BattleManager.reset_run() (new_run()), генерирует RunMapData.
#
# Цикл линейный, игрок путь не выбирает: ShopScene → BattleScene → ShopScene → …
# Шаг завершён → advance() сам открывает следующий. round_number растёт только в
# EconomyManager.give_round_income (один бой = одна волна).

const SHOP_SCENE: String = "res://scenes/shop/ShopScene.tscn"
const BATTLE_SCENE: String = "res://scenes/battle/BattleScene.tscn"
const MENU_SCENE: String = "res://scenes/menu/MainMenu.tscn"

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

func new_run(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	map = RunMapData.generate(rng)
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
			get_tree().change_scene_to_file(SHOP_SCENE)
		RunMapNode.BATTLE, RunMapNode.MINIBOSS, RunMapNode.BOSS:
			if node.wave != EconomyManager.round_number:
				push_warning("RunManager: волна шага %d ≠ round_number %d" % [node.wave, EconomyManager.round_number])
			get_tree().change_scene_to_file(BATTLE_SCENE)
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
	BattleManager.stop_battle()
	get_tree().change_scene_to_file(MENU_SCENE)

# Сдача вне схватки (магазин, расстановка, итог боя) — конец забега без экрана
# итога: сохранение удаляется, в главное меню. В схватке — BattleManager.surrender()
func abandon_run() -> void:
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
	}

func load_state(d: Dictionary) -> void:
	rng.seed = str(d["rng_seed"]).to_int()
	rng.state = str(d["rng_state"]).to_int()
	current_node_id = int(d["current_node_id"])
	current_completed = bool(d["current_completed"])

# -------------------------------------------------------
# ДЛЯ БОЯ
# -------------------------------------------------------
# Тип текущего боя; если BattleScene запущена напрямую — обычный бой
func get_battle_type() -> String:
	var node = get_current_node()
	if node and node.is_battle() and not current_completed:
		return node.type
	return RunMapNode.BATTLE

func get_battle_wave() -> int:
	var node = get_current_node()
	if node and node.is_battle() and not current_completed:
		return node.wave
	return EconomyManager.round_number

func get_total_waves() -> int:
	return map.total_waves if map else 0

func is_shop_node_active() -> bool:
	var node = get_current_node()
	return node != null and node.type == RunMapNode.SHOP and not current_completed
