extends Node

var active_squads: Array[Squad] = []

func register(squad: Squad) -> void:
	if not active_squads.has(squad):
		active_squads.append(squad)
		squad.squad_wiped.connect(_on_squad_wiped)

func _on_squad_wiped(squad: Squad) -> void:
	active_squads.erase(squad)

func get_alive_squads_of_team(team_id: int) -> Array[Squad]:
	var result: Array[Squad] = []
	for s in active_squads:
		if s.team == team_id and s.is_alive():
			result.append(s)
	return result

func get_all_alive_squads() -> Array[Squad]:
	var result: Array[Squad] = []
	for s in active_squads:
		if s.is_alive():
			result.append(s)
	return result

func clear() -> void:
	active_squads.clear()
