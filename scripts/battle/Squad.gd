class_name Squad
extends Node2D

# -------------------------------------------------------
# СОСТОЯНИЯ ОТРЯДА
# -------------------------------------------------------
enum State { IDLE, MARCHING, FIGHTING, DEAD }

# -------------------------------------------------------
# ДАННЫЕ
# -------------------------------------------------------
var data: UnitData           # тип юнита в отряде
var team: int
var tile: Vector2i           # позиция на сетке
var soldiers: Array[Soldier] = []
var current_state: State = State.IDLE

signal squad_wiped(squad: Squad)  # все бойцы мертвы

# -------------------------------------------------------
# СЦЕНА БОЙЦА
# -------------------------------------------------------
# Боец — это отдельная сцена с AnimatedSprite2D
const SOLDIER_SCENE = preload("res://scenes/battle/Soldier.tscn")

# ----------------------------------------s---------------
# ИНИЦИАЛИЗАЦИЯ
# -------------------------------------------------------
# hp_list — доли HP выживших бойцов (пустой = все с полным HP)
func setup(unit_data: UnitData, team_id: int, grid_tile: Vector2i, count: int, hp_list: Array[float] = []) -> void:
	data = unit_data
	team = team_id
	tile = grid_tile
	# Бойцы участвуют в общей сортировке по глубине (Units.y_sort_enabled)
	y_sort_enabled = true

	# Спавним бойцов в строю на клетке
	_spawn_soldiers(count, hp_list)

func _spawn_soldiers(count: int, hp_list: Array[float]) -> void:
	# Вычисляем смещения для строя на клетке
	# Бойцы расставляются в небольшой сетке внутри тайла
	var offsets = _get_formation_offsets(count)

	for i in range(count):
		var hp_ratio: float = hp_list[i] if i < hp_list.size() else 1.0
		_add_soldier(offsets[i], hp_ratio)

func _add_soldier(offset: Vector2, hp_ratio: float) -> void:
	var soldier = SOLDIER_SCENE.instantiate()
	add_child(soldier)
	soldier.setup(data, team, self, offset, hp_ratio)
	soldier.position = offset
	soldier.died.connect(_on_soldier_died)
	soldiers.append(soldier)
	SoldierRegistry.register(soldier)

# Перестроить строй под текущее число бойцов (после возвращения павших)
func _reform() -> void:
	var offsets = _get_formation_offsets(soldiers.size())
	for i in range(soldiers.size()):
		soldiers[i].formation_offset = offsets[i]
		soldiers[i].position = offsets[i]

# Строй как в 9 Kings: шеренги вдоль осей изометрии, фронт смотрит на врага.
# Шеренга (до FORMATION_MAX_RANK бойцов) — вдоль оси row, ряды уходят в тыл
# вдоль оси наступления. Первый ряд — ближе к противнику.
const FORMATION_MAX_RANK: int = 3
const RANK_SPACING: float = 26.0   # между бойцами в шеренге, px
const FILE_SPACING: float = 22.0   # между рядами, px

func _get_formation_offsets(count: int) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	var cols = min(count, FORMATION_MAX_RANK)
	var rows = int(ceil(float(count) / cols))
	var rank_dir = IsoGrid.rank_direction()
	# Игрок наступает вдоль +advance, враг — навстречу
	var forward = IsoGrid.advance_direction() * (1.0 if team == GameConstants.TEAM_PLAYER else -1.0)

	for i in range(count):
		var col = i % cols
		var row = i / cols
		# Неполный последний ряд центрируем
		var in_row = cols if row < rows - 1 else count - row * cols
		var along_rank = (col - (in_row - 1) / 2.0) * RANK_SPACING
		var depth = ((rows - 1) / 2.0 - row) * FILE_SPACING   # row 0 — впереди
		offsets.append(rank_dir * along_rank + forward * depth)

	return offsets

# -------------------------------------------------------
# ГЛАВНЫЙ ТИК
# -------------------------------------------------------
func tick(delta: float) -> void:
	match current_state:
		State.IDLE:     pass
		State.MARCHING: _tick_marching(delta)
		State.FIGHTING: _tick_fighting(delta)
		State.DEAD:     pass

func _tick_marching(delta: float) -> void:
	# Тикаем всех живых бойцов
	for soldier in soldiers:
		if soldier.current_state != Soldier.State.DEAD:
			soldier.tick(delta)

	# Если хоть один боец вступил в бой — переходим в FIGHTING
	for soldier in soldiers:
		if soldier.current_state == Soldier.State.ATTACK:
			current_state = State.FIGHTING
			return

func _tick_fighting(delta: float) -> void:
	for soldier in soldiers:
		if soldier.current_state != Soldier.State.DEAD:
			soldier.tick(delta)

# -------------------------------------------------------
# КОМАНДЫ ОТ BATTLEMANAGER
# -------------------------------------------------------

# Бой начался — бойцы выдвигаются вперёд
func start_march() -> void:
	current_state = State.MARCHING
	for soldier in soldiers:
		soldier.transition_to(Soldier.State.MOVE)

# Карта-улучшение брошена на этот отряд: множители в data (живут между
# раундами), живым бойцам пересчитываем статы сразу
func apply_upgrade(card: CardData) -> bool:
	if not data.can_apply_upgrade(card):
		return false
	data.apply_upgrade(card)
	for soldier in soldiers:
		soldier.refresh_stats_from_data()
	return true

# Карта того же отряда → улучшение (до UnitFactory.MAX_SQUAD_LEVEL раз)
func merge_upgrade() -> bool:
	if not data.can_merge_upgrade():
		return false
	data.apply_merge_upgrade()
	for soldier in soldiers:
		soldier.refresh_stats_from_data()
	return true

# Карта того же отряда → лечение: каждому живому бойцу доля его максимального HP,
# павшие (до полного состава data.squad_size) возвращаются с той же долей HP.
# Возвращает, сколько бойцов вернулось.
func heal_by_ratio(ratio: float) -> int:
	for soldier in soldiers:
		soldier.heal(soldier.max_hp * ratio)
	var missing = get_missing_count()
	for i in range(missing):
		_add_soldier(Vector2.ZERO, ratio)
	if missing > 0:
		_reform()
	return missing

func get_missing_count() -> int:
	return max(data.squad_size - soldiers.size(), 0)

func is_wounded() -> bool:
	if get_missing_count() > 0:
		return true
	for soldier in soldiers:
		if soldier.current_hp < soldier.max_hp:
			return true
	return false

# -------------------------------------------------------
# СМЕРТЬ БОЙЦОВ
# -------------------------------------------------------
func _on_soldier_died(soldier: Soldier) -> void:
	soldiers.erase(soldier)
	print("Squad: боец погиб, осталось %d" % soldiers.size())

	# Если все бойцы мертвы — отряд уничтожен
	if soldiers.is_empty():
		current_state = State.DEAD
		emit_signal("squad_wiped", self)

# -------------------------------------------------------
# УТИЛИТЫ
# -------------------------------------------------------
func is_alive() -> bool:
	return current_state != State.DEAD

func get_alive_soldier_count() -> int:
	return soldiers.size()
