class_name RunMapData
extends Resource

# Забег — линейная цепочка шагов, игрок путь не выбирает:
#   магазин → волна 1 → магазин → волна 2 → … → магазин → волна TOTAL_WAVES;
#   после волн EVENT_AFTER_WAVES — событие перед следующим магазином
# Каждая волна начинается с магазина. Номер волны боевого шага всегда совпадает
# с EconomyManager.round_number (растёт только в give_round_income, 1 раз за бой).
# Тип боя — по номеру волны: каждая MINIBOSS_EVERY-я — мини-босс,
# последняя — главный босс. Расширение королевства — BattleManager.EXPANSION_EVERY.
const TOTAL_WAVES: int = 15
const MINIBOSS_EVERY: int = 5
const EVENT_AFTER_WAVES: Array[int] = [4, 8, 12, 14]   # решение пользователя

@export var nodes: Array[RunMapNode] = []
@export var total_waves: int = 0

func get_node_by_id(id: int) -> RunMapNode:
	if id < 0 or id >= nodes.size():
		return null
	return nodes[id]

static func get_battle_type_for_wave(wave: int, waves: int = TOTAL_WAVES) -> String:
	if wave >= waves:
		return RunMapNode.BOSS
	if wave % MINIBOSS_EVERY == 0:
		return RunMapNode.MINIBOSS
	return RunMapNode.BATTLE

# -------------------------------------------------------
# ГЕНЕРАЦИЯ
# -------------------------------------------------------
# rng пока не нужен (цепочка фиксирована) — оставлен для случайных шагов в будущем
static func generate(_rng: RandomNumberGenerator = null, waves: int = TOTAL_WAVES) -> RunMapData:
	var map = RunMapData.new()
	for wave in range(1, waves + 1):
		_add_node(map, RunMapNode.SHOP, 0)
		_add_node(map, get_battle_type_for_wave(wave, waves), wave)
		if wave in EVENT_AFTER_WAVES and wave < waves:
			_add_node(map, RunMapNode.EVENT, 0)
	for i in range(map.nodes.size() - 1):
		map.nodes[i].next.append(i + 1)
	map.total_waves = waves
	return map

# Какое по счёту событие забега шаг id (0 — первое) — от него RunEvents.for_run
func get_event_index(id: int) -> int:
	var index = 0
	for i in range(mini(id, nodes.size())):
		if nodes[i].type == RunMapNode.EVENT:
			index += 1
	return index

# Волна проставляется только боевым шагам (у магазина и события 0)
static func _add_node(map: RunMapData, type: String, node_wave: int) -> void:
	var n = RunMapNode.new()
	n.id = map.nodes.size()
	n.type = type
	n.wave = node_wave
	map.nodes.append(n)
