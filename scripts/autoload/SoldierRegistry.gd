extends Node

var active_soldiers: Array[Soldier] = []

func register(soldier: Soldier) -> void:
	if not active_soldiers.has(soldier):
		active_soldiers.append(soldier)
		soldier.died.connect(_on_soldier_died)

func _on_soldier_died(soldier: Soldier) -> void:
	active_soldiers.erase(soldier)

func get_alive_soldiers_of_team(team_id: int) -> Array[Soldier]:
	var result: Array[Soldier] = []
	for s in active_soldiers:
		if s.team == team_id and s.current_state != Soldier.State.DEAD:
			result.append(s)
	return result

func get_all_alive_soldiers() -> Array[Soldier]:
	var result: Array[Soldier] = []
	for s in active_soldiers:
		if s.current_state != Soldier.State.DEAD:
			result.append(s)
	return result

func clear() -> void:
	active_soldiers.clear()
