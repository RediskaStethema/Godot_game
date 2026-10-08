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
	while _accumulator >= FIXED_TICK:
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
	_check_battle_end()

func _check_battle_end() -> void:
	var team0_alive = SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER).size() > 0
	var team1_alive = SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_ENEMY).size() > 0

	if team0_alive and team1_alive:
		return

	phase = BattlePhase.FINISHED

	if team0_alive and not team1_alive:
		winner_team = GameConstants.TEAM_PLAYER
	elif team1_alive and not team0_alive:
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
