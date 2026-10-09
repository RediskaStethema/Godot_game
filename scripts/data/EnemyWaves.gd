class_name EnemyWaves
extends RefCounted

# Состав врагов по волне и типу боя шага забега — данными.
# BattleScene расставляет отряды в порядке списка: с переднего края зоны врага в тыл.
# Баланс черновой (дальше — balance-analyst).

# Обычная волна (прежняя формула BattleScene): отрядов = волна + 1,
# бойцов в отряде = волна + 1 (не больше 6), статы ×(1 + 0.15 за волну после первой)
const NORMAL_UNIT: String = "chaos_marine"
const STAT_STEP_PER_WAVE: float = 0.15
const MAX_SOLDIERS_PER_SQUAD: int = 6

# Мини-босс (каждая 5-я волна): Hellbrute на переднем крае, за ним отряды
# элиты Хаоса (elite_base + волна / elite_wave_div), дальше — обычные отряды волны
const MINIBOSS = {
	"unit": "chaos_hellbrute",
	"soldiers": 1,
	"elite_unit": "chaos_champion",
	"elite_soldiers": 2,    # бойцов в элитном отряде
	"elite_base": 0,
	"elite_wave_div": 5,    # волна 5 — 1 элитный отряд, волна 10 — 2
	"escort_squads": 2,
}

# Главный босс (последняя волна): Chaos Lord на переднем крае + эскорт из обычных отрядов волны
const BOSS = {
	"unit": "chaos_lord",
	"soldiers": 1,
	"escort_squads": 4,
}

static func get_stat_mult(wave: int) -> float:
	return 1.0 + max(wave - 1, 0) * STAT_STEP_PER_WAVE

# Возвращает [{ "unit": factory_id, "count": бойцов, "mult": множитель hp/урона }]
static func build(wave: int, node_type: String, max_squads: int) -> Array[Dictionary]:
	wave = max(wave, 1)
	var mult = get_stat_mult(wave)
	var soldiers = mini(wave + 1, MAX_SOLDIERS_PER_SQUAD)
	var squads: Array[Dictionary] = []
	match node_type:
		RunMapNode.BOSS:
			squads.append({"unit": BOSS["unit"], "count": BOSS["soldiers"], "mult": mult})
			for i in range(mini(BOSS["escort_squads"], max_squads - 1)):
				squads.append({"unit": NORMAL_UNIT, "count": soldiers, "mult": mult})
		RunMapNode.MINIBOSS:
			squads.append({"unit": MINIBOSS["unit"], "count": MINIBOSS["soldiers"], "mult": mult})
			var elites = MINIBOSS["elite_base"] + wave / MINIBOSS["elite_wave_div"]
			for i in range(mini(elites, max_squads - squads.size())):
				squads.append({"unit": MINIBOSS["elite_unit"], "count": MINIBOSS["elite_soldiers"], "mult": mult})
			for i in range(mini(MINIBOSS["escort_squads"], max_squads - squads.size())):
				squads.append({"unit": NORMAL_UNIT, "count": soldiers, "mult": mult})
		_:
			for i in range(mini(wave + 1, max_squads)):
				squads.append({"unit": NORMAL_UNIT, "count": soldiers, "mult": mult})
	return squads
