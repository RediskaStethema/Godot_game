extends Node

# Реестр бойцов текущего боя. Списки живых по командам кэшируются и
# пересобираются только при регистрации / гибели / очистке — бойцы
# запрашивают их много раз за тик (цель, аура, лечение, штурм).
# Возвращаемые массивы — общий кэш: НЕ изменять, при необходимости .duplicate().

var active_soldiers: Array[Soldier] = []
var _alive_by_team: Dictionary = {}     # team → Array[Soldier]
var _alive_all: Array[Soldier] = []
var _dirty: bool = true
# Центр живых бойцов команды — считается один раз за тик (begin_tick сбрасывает)
var _center_by_team: Dictionary = {}

func register(soldier: Soldier) -> void:
	if not active_soldiers.has(soldier):
		active_soldiers.append(soldier)
		soldier.died.connect(_on_soldier_died)
		_dirty = true

func _on_soldier_died(soldier: Soldier) -> void:
	active_soldiers.erase(soldier)
	_dirty = true
	_center_by_team.clear()

func get_alive_soldiers_of_team(team_id: int) -> Array[Soldier]:
	_rebuild_if_dirty()
	if not _alive_by_team.has(team_id):
		var empty: Array[Soldier] = []
		_alive_by_team[team_id] = empty
	return _alive_by_team[team_id]

func get_all_alive_soldiers() -> Array[Soldier]:
	_rebuild_if_dirty()
	return _alive_all

# Средняя точка живых бойцов команды на начало тика (марш строем к врагу)
func get_team_center(team_id: int) -> Vector2:
	if _center_by_team.has(team_id):
		return _center_by_team[team_id]
	var soldiers = get_alive_soldiers_of_team(team_id)
	var center = Vector2.ZERO
	for s in soldiers:
		center += s.global_position
	if not soldiers.is_empty():
		center /= soldiers.size()
	_center_by_team[team_id] = center
	return center

# Зовёт BattleManager перед каждым тиком боя: позиции изменились
func begin_tick() -> void:
	_center_by_team.clear()

func clear() -> void:
	active_soldiers.clear()
	_alive_by_team.clear()
	_alive_all.clear()
	_center_by_team.clear()
	_dirty = false

func _rebuild_if_dirty() -> void:
	if not _dirty:
		return
	_dirty = false
	_alive_by_team.clear()
	_alive_all = []
	for s in active_soldiers:
		if not is_instance_valid(s) or s.current_state == Soldier.State.DEAD:
			continue
		_alive_all.append(s)
		if not _alive_by_team.has(s.team):
			var list: Array[Soldier] = []
			_alive_by_team[s.team] = list
		_alive_by_team[s.team].append(s)
