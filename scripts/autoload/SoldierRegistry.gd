extends Node

# Реестр бойцов текущего боя. Списки живых по командам кэшируются и
# пересобираются только при регистрации / гибели / очистке — бойцы
# запрашивают их много раз за тик (цель, аура, лечение, штурм).
# Возвращаемые массивы — общий кэш: НЕ изменять, при необходимости .duplicate().

var active_soldiers: Array[Soldier] = []
var _alive_by_team: Dictionary = {}     # team → Array[Soldier]
var _alive_all: Array[Soldier] = []
var _aura_by_team: Dictionary = {}     # team → Array[Soldier] с аурой урона (пересборка с кэшем живых)
var _dirty: bool = true
# Центр живых бойцов команды — считается один раз за тик (begin_tick сбрасывает)
var _center_by_team: Dictionary = {}
# Сетка живых бойцов по клеткам GRID_CELL — поиск ближайшего без перебора всех (цель, поле
# зрения, отход). Строится раз за тик, на первом запросе; за тик боец сдвигается не дальше
# GRID_SLACK (бег за FIXED_TICK, отброс Дредноута 30 px) — поиск это учитывает, и ответ —
# как у полного перебора по текущим позициям. Только внутри тика BattleManager (begin_tick …
# end_tick): вне его (тесты тикают бойцов вручную) — обычный перебор
const GRID_CELL: float = 96.0
const GRID_SLACK: float = 48.0
var _grid_by_team: Dictionary = {}     # team → {cells: {Vector2i: Array}, lo: Vector2i, hi: Vector2i}
var _in_tick: bool = false
var _best: Soldier = null
var _best_d: float = INF

func register(soldier: Soldier) -> void:
	if not active_soldiers.has(soldier):
		active_soldiers.append(soldier)
		soldier.died.connect(_on_soldier_died)
		_dirty = true
		_grid_by_team.clear()

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

# Живые бойцы команды с аурой урона (Chaplain) — аура считается на каждом ударе
func get_aura_sources(team_id: int) -> Array:
	_rebuild_if_dirty()
	return _aura_by_team.get(team_id, [])

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

# Ближайший живой боец команды к точке: не дальше max_dist, ranged_only — только стрелки
# (тег ranged). Нет такого — null. Кольца клеток от точки наружу, пока ближе не найти
func find_nearest(team_id: int, from: Vector2, max_dist: float = INF, ranged_only: bool = false) -> Soldier:
	if not _in_tick:
		return _find_nearest_linear(team_id, from, max_dist, ranged_only)
	var g := _get_grid(team_id)
	var cells: Dictionary = g["cells"]
	if cells.is_empty():
		return null
	var lo: Vector2i = g["lo"]
	var hi: Vector2i = g["hi"]
	var c0 := Vector2i(floori(from.x / GRID_CELL), floori(from.y / GRID_CELL))
	_best = null
	_best_d = max_dist * max_dist if max_dist < INF else INF
	# Вся команда дальше max_dist (с запасом на сдвиг за тик) — искать нечего (марш издалека)
	if _best_d < INF:
		var area := Rect2(Vector2(lo) * GRID_CELL, Vector2(hi - lo + Vector2i.ONE) * GRID_CELL).grow(GRID_SLACK)
		var gap := Vector2(maxf(maxf(area.position.x - from.x, from.x - area.end.x), 0.0),
			maxf(maxf(area.position.y - from.y, from.y - area.end.y), 0.0))
		if gap.length_squared() > _best_d:
			return null
	var max_r := maxi(maxi(c0.x - lo.x, hi.x - c0.x), maxi(c0.y - lo.y, hi.y - c0.y))
	for r in range(max_r + 1):
		# Клетки кольца r — не ближе (r − 1) клеток от точки, бойцы в них — ещё на сдвиг за тик
		var reach := (r - 1) * GRID_CELL - GRID_SLACK
		if reach > 0.0 and reach * reach > _best_d:
			break
		var x0 := maxi(c0.x - r, lo.x)
		var x1 := mini(c0.x + r, hi.x)
		if c0.y - r >= lo.y:
			for x in range(x0, x1 + 1):
				_scan_cell(cells, Vector2i(x, c0.y - r), from, ranged_only)
		if r > 0 and c0.y + r <= hi.y:
			for x in range(x0, x1 + 1):
				_scan_cell(cells, Vector2i(x, c0.y + r), from, ranged_only)
		if r > 0:
			for y in range(maxi(c0.y - r + 1, lo.y), mini(c0.y + r - 1, hi.y) + 1):
				if c0.x - r >= lo.x:
					_scan_cell(cells, Vector2i(c0.x - r, y), from, ranged_only)
				if c0.x + r <= hi.x:
					_scan_cell(cells, Vector2i(c0.x + r, y), from, ranged_only)
	var found := _best
	_best = null
	return found

func _find_nearest_linear(team_id: int, from: Vector2, max_dist: float, ranged_only: bool) -> Soldier:
	_best = null
	_best_d = max_dist * max_dist if max_dist < INF else INF
	_scan_list(get_alive_soldiers_of_team(team_id), from, ranged_only)
	var found := _best
	_best = null
	return found

func _scan_cell(cells: Dictionary, c: Vector2i, from: Vector2, ranged_only: bool) -> void:
	if cells.has(c):
		_scan_list(cells[c], from, ranged_only)

func _scan_list(list: Array, from: Vector2, ranged_only: bool) -> void:
	for s in list:
		if not is_instance_valid(s) or s.current_state == Soldier.State.DEAD:
			continue   # погиб в этом тике
		if ranged_only and not "ranged" in s.data.tags:
			continue
		var d := from.distance_squared_to(s.global_position)
		if d < _best_d or (_best == null and d <= _best_d):
			_best_d = d
			_best = s

func _get_grid(team_id: int) -> Dictionary:
	if _grid_by_team.has(team_id):
		return _grid_by_team[team_id]
	var cells := {}
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for s in get_alive_soldiers_of_team(team_id):
		var c := Vector2i(floori(s.global_position.x / GRID_CELL), floori(s.global_position.y / GRID_CELL))
		if not cells.has(c):
			cells[c] = []
		cells[c].append(s)
		lo = lo.min(c)
		hi = hi.max(c)
	var g := {"cells": cells, "lo": lo, "hi": hi}
	_grid_by_team[team_id] = g
	return g

# Зовёт BattleManager перед каждым тиком боя: позиции изменились. Бойцы, нарисованные
# между тиками (плавное движение), возвращаются в логические позиции
func begin_tick() -> void:
	_center_by_team.clear()
	_grid_by_team.clear()
	_in_tick = true
	for s in get_all_alive_soldiers():
		s.restore_tick_position()

func end_tick() -> void:
	_in_tick = false
	_grid_by_team.clear()

func clear() -> void:
	active_soldiers.clear()
	_alive_by_team.clear()
	_alive_all.clear()
	_aura_by_team.clear()
	_center_by_team.clear()
	_grid_by_team.clear()
	_in_tick = false
	_dirty = false

func _rebuild_if_dirty() -> void:
	if not _dirty:
		return
	_dirty = false
	_alive_by_team.clear()
	_aura_by_team.clear()
	_alive_all = []
	for s in active_soldiers:
		if not is_instance_valid(s) or s.current_state == Soldier.State.DEAD:
			continue
		_alive_all.append(s)
		if not _alive_by_team.has(s.team):
			var list: Array[Soldier] = []
			_alive_by_team[s.team] = list
		_alive_by_team[s.team].append(s)
		if s.data.aura_damage_bonus > 0.0:
			if not _aura_by_team.has(s.team):
				_aura_by_team[s.team] = []
			_aura_by_team[s.team].append(s)
