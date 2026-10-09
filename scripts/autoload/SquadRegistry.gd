extends Node

# Реестр отрядов текущего боя. Списки живых кэшируются и пересобираются
# только при регистрации / гибели отряда / очистке (BattleManager проверяет
# конец боя каждый тик). Возвращаемые массивы — общий кэш: НЕ изменять.

var active_squads: Array[Squad] = []
var _alive_by_team: Dictionary = {}     # team → Array[Squad]
var _alive_all: Array[Squad] = []
var _dirty: bool = true

func register(squad: Squad) -> void:
	if not active_squads.has(squad):
		active_squads.append(squad)
		squad.squad_wiped.connect(_on_squad_wiped)
		_dirty = true

func _on_squad_wiped(squad: Squad) -> void:
	active_squads.erase(squad)
	_dirty = true

func get_alive_squads_of_team(team_id: int) -> Array[Squad]:
	_rebuild_if_dirty()
	if not _alive_by_team.has(team_id):
		var empty: Array[Squad] = []
		_alive_by_team[team_id] = empty
	return _alive_by_team[team_id]

func get_all_alive_squads() -> Array[Squad]:
	_rebuild_if_dirty()
	return _alive_all

# Отряд, боец которого виден в точке мира (ближайший к точке). Скрытые отряды
# (враги до боя) не в счёт. half_width — полуширина бойца для попадания, px.
func find_squad_at(world_pos: Vector2, half_width: float) -> Squad:
	var best: Squad = null
	var best_dist = INF
	for squad in get_all_alive_squads():
		if not squad.visible:
			continue
		for soldier in squad.soldiers:
			var k = soldier.data.sprite_scale
			var local = world_pos - soldier.global_position
			if absf(local.x) > half_width * k or local.y > 6.0 \
					or local.y < -Soldier.TARGET_SPRITE_HEIGHT * k:
				continue
			var d = local.length_squared()
			if d < best_dist:
				best_dist = d
				best = squad
	return best

func clear() -> void:
	active_squads.clear()
	_alive_by_team.clear()
	_alive_all.clear()
	_dirty = false

func _rebuild_if_dirty() -> void:
	if not _dirty:
		return
	_dirty = false
	_alive_by_team.clear()
	_alive_all = []
	for s in active_squads:
		if not is_instance_valid(s) or not s.is_alive():
			continue
		_alive_all.append(s)
		if not _alive_by_team.has(s.team):
			var list: Array[Squad] = []
			_alive_by_team[s.team] = list
		_alive_by_team[s.team].append(s)
