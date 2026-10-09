extends Node

# -------------------------------------------------------
# КОНСТАНТЫ И СОСТОЯНИЕ
# -------------------------------------------------------

# Фиксированный тик берём из GameConstants —
# одно значение используется везде, меняем в одном месте
# Добавь переменную

var player_placements: Dictionary = {}
# Рука — карты, ещё не выложенные на поле (pending_cards). Переносятся между раундами.
const MAX_HAND_SIZE: int = 10
const FIXED_TICK: float = GameConstants.FIXED_TICK
var pending_cards: Array[CardData] = []

# Королевство: открытые клетки для расстановки. Живут весь забег.
# Каждую EXPANSION_EVERY-ю волну (3, 6, 9, 12, 15) во время расстановки можно
# докупать соседние клетки; цена растёт с каждой купленной.
const START_KINGDOM_SIZE = Vector2i(3, 3)
const EXPANSION_EVERY: int = 3
const TILE_BASE_COST: int = 6
const TILE_COST_STEP: int = 2
var kingdom_tiles: Array[Vector2i] = []
var tiles_bought: int = 0

# Цитадель: HP живёт весь забег. Если армия игрока погибла, начинается штурм —
# бой цитадели с уцелевшими врагами: враги бьют её своими атаками, она стреляет
# в ответ (статы — в Citadel.gd). Все враги убиты — волна отбита; HP = 0 — забег окончен.
const CITADEL_MAX_HP: float = 1000.0
var citadel_hp: float = CITADEL_MAX_HP
var citadel: Node2D = null          # цитадель текущего боя (ставит BattleScene)
var siege_started: bool = false     # армия игрока пала, враги штурмуют цитадель
# Щит цитадели на текущий бой (Fortress Wall): урон штурма сначала снимает его
var citadel_shield: float = 0.0

# Здания: стоят между раундами на своих клетках (CardData → Vector2i)
var player_buildings: Dictionary = {}
var buildings: Array = []           # узлы Building текущего боя (ставит BattleScene)

signal citadel_hp_changed(hp: float)
signal citadel_destroyed
# нам нужно различать "ещё не начался" и "уже закончился"
enum BattlePhase { IDLE, RUNNING, FINISHED }
var player_units: Array[UnitData] = []
var phase: BattlePhase = BattlePhase.IDLE
var winner_team: int = -1       # 0 = игрок, 1 = враг, -1 = ничья
var _accumulator: float = 0.0   # накопитель времени между тиками

# Сигналы для UI и GameManager —
# они подпишутся и будут знать о событиях боя
signal battle_started
signal battle_ended(winner_team: int)

# -------------------------------------------------------
# ЗАПУСК И ОСТАНОВКА
# -------------------------------------------------------

func start_battle() -> void:
	if phase == BattlePhase.RUNNING:
		return  # защита от двойного запуска

	phase = BattlePhase.RUNNING
	winner_team = -1
	_accumulator = 0.0
	siege_started = false
	emit_signal("battle_started")
	print("BattleManager: бой начался")

func stop_battle() -> void:
	phase = BattlePhase.IDLE
	SquadRegistry.clear()
	SoldierRegistry.clear()

# -------------------------------------------------------
# ГЛАВНЫЙ ЦИКЛ
# -------------------------------------------------------

# _process вызывается каждый кадр — но мы используем
# его только как источник времени. Реальная логика боя
# происходит в _battle_tick() по фиксированному расписанию.
func _process(delta: float) -> void:
	if phase != BattlePhase.RUNNING:
		return

	# Накапливаем время. Когда накопилось достаточно —
	# делаем тик и вычитаем. Остаток переносится на следующий кадр.
	# Это называется "accumulator pattern" — стандартный подход
	# для фиксированного шага симуляции.
	_accumulator += delta
	# Бой мог закончиться на одном из тиков кадра — дальше не тикаем,
	# иначе при длинном кадре battle_ended придёт несколько раз (двойной доход)
	while _accumulator >= FIXED_TICK and phase == BattlePhase.RUNNING:
		_battle_tick()
		_accumulator -= FIXED_TICK

# -------------------------------------------------------
# ТИК БОЯ
# -------------------------------------------------------

func _battle_tick() -> void:
	# Тикаем все живые отряды
	var squads = SquadRegistry.get_all_alive_squads()
	for squad in squads:
		squad.tick(FIXED_TICK)
	for b in buildings:
		if is_instance_valid(b):
			b.tick(FIXED_TICK)
	if siege_started and has_citadel():
		citadel.tick(FIXED_TICK)
	_check_battle_end()

func _check_battle_end() -> void:
	var team0_alive = SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER).size() > 0
	var team1_alive = SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_ENEMY).size() > 0

	# Цитадель тоже сторона игрока: пока она стоит, игрок не проиграл
	var citadel_alive = has_citadel() and citadel_hp > 0.0
	var player_alive = team0_alive or citadel_alive
	if team1_alive and player_alive:
		# Армия пала, цитадель стоит — штурм: бой цитадели с врагами
		if not team0_alive and not siege_started:
			siege_started = true
			print("BattleManager: армия пала — штурм цитадели")
		return

	phase = BattlePhase.FINISHED

	if player_alive and not team1_alive:
		winner_team = GameConstants.TEAM_PLAYER   # в т.ч. цитадель отбила штурм
	elif team1_alive:
		winner_team = GameConstants.TEAM_ENEMY
	else:
		winner_team = -1

	print("BattleManager: бой закончен, победитель — команда ", winner_team)
	emit_signal("battle_ended", winner_team)
# -------------------------------------------------------
# ПРОВЕРКА ПОБЕДЫ
# -------------------------------------------------------


func set_player_units(units: Array[UnitData]) -> void:
	player_units = units

# -------------------------------------------------------
# КОРОЛЕВСТВО
# -------------------------------------------------------
func _ready() -> void:
	reset_kingdom()

func reset_kingdom() -> void:
	kingdom_tiles.clear()
	tiles_bought = 0
	for row in range(START_KINGDOM_SIZE.y):
		for col in range(START_KINGDOM_SIZE.x):
			kingdom_tiles.append(Vector2i(col, row))

# -------------------------------------------------------
# ЦИТАДЕЛЬ
# -------------------------------------------------------
func has_citadel() -> bool:
	return is_instance_valid(citadel)

func damage_citadel(amount: float) -> void:
	if citadel_hp <= 0.0:
		return
	var absorbed = minf(citadel_shield, amount)
	citadel_shield -= absorbed
	citadel_hp = maxf(citadel_hp - (amount - absorbed), 0.0)
	emit_signal("citadel_hp_changed", citadel_hp)
	if citadel_hp <= 0.0:
		print("BattleManager: цитадель пала")
		emit_signal("citadel_destroyed")

# Ремонт цитадели (события карты забега). Возвращает, сколько HP восстановлено.
func heal_citadel(amount: float) -> float:
	var before = citadel_hp
	citadel_hp = minf(citadel_hp + maxf(amount, 0.0), CITADEL_MAX_HP)
	emit_signal("citadel_hp_changed", citadel_hp)
	return citadel_hp - before

# Новый забег: цитадель, королевство, армия, рука, экономика, синергии, цепочка забега
func reset_run() -> void:
	citadel_hp = CITADEL_MAX_HP
	emit_signal("citadel_hp_changed", citadel_hp)
	citadel_shield = 0.0
	reset_kingdom()
	player_buildings.clear()
	player_units.clear()
	player_placements.clear()
	pending_cards.clear()
	EconomyManager.reset()
	SynergyManager.reset()
	RunManager.new_run()

# Волна, в которой можно расширять королевство
func can_expand_kingdom() -> bool:
	return EconomyManager.round_number % EXPANSION_EVERY == 0

func get_tile_cost() -> int:
	return TILE_BASE_COST + tiles_bought * TILE_COST_STEP

# Списывает Requisition и открывает клетку. Соседство и рамку проверяет вызывающий.
func try_buy_tile(tile: Vector2i) -> bool:
	if not can_expand_kingdom() or kingdom_tiles.has(tile):
		return false
	if not EconomyManager.try_spend(get_tile_cost()):
		return false
	kingdom_tiles.append(tile)
	tiles_bought += 1
	print("BattleManager: куплена клетка %s, всего %d" % [tile, kingdom_tiles.size()])
	return true
