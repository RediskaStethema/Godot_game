class_name RunMapData
extends Resource

# Забег — линейная цепочка шагов, игрок путь не выбирает:
#   магазин → волна 1 → магазин → волна 2 → … → магазин → волна TOTAL_WAVES
# Каждая волна начинается с магазина. Номер волны боевого шага всегда совпадает
# с EconomyManager.round_number (растёт только в give_round_income, 1 раз за бой).
# Тип боя — по номеру волны: каждая MINIBOSS_EVERY-я — мини-босс,
# последняя — главный босс. Расширение королевства — BattleManager.EXPANSION_EVERY.
const TOTAL_WAVES: int = 15
const MINIBOSS_EVERY: int = 5

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
	for i in range(map.nodes.size() - 1):
		map.nodes[i].next.append(i + 1)
	map.total_waves = waves
	return map

# Волна проставляется только боевым шагам (у магазина 0)
static func _add_node(map: RunMapData, type: String, node_wave: int) -> void:
	var n = RunMapNode.new()
	n.id = map.nodes.size()
	n.type = type
	n.wave = node_wave
	map.nodes.append(n)
