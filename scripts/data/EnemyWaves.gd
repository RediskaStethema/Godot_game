class_name EnemyWaves
extends RefCounted

# Состав врагов по волне и типу боя шага забега — данными.
# BattleScene расставляет отряды в порядке списка: с переднего края зоны врага в тыл.
# Баланс черновой (дальше — balance-analyst).

# Обычная волна: отрядов = SQUADS_BASE + (волна − 1) / SQUADS_EVERY_WAVES,
# бойцов в отряде = SOLDIERS_BASE + (волна − 1) / SOLDIERS_EVERY_WAVES (не больше 6),
# статы ×(1 + STAT_STEP_PER_WAVE за волну после первой).
# Подбор — tests/balance_sim.gd
const NORMAL_UNIT: String = "chaos_marine"
const SQUADS_BASE: int = 2
const SQUADS_EVERY_WAVES: int = 2
const SOLDIERS_BASE: int = 3
const SOLDIERS_EVERY_WAVES: int = 3
const MAX_SOLDIERS_PER_SQUAD: int = 6
const STAT_STEP_PER_WAVE: float = 0.10

# Мини-босс (каждая 5-я волна): Hellbrute на переднем крае, за ним отряды
# элиты Хаоса (elite_base + волна / elite_wave_div). Hellbrute — сверх обычной
# волны, элита заменяет её передние отряды (не меньше 1 обычного)
const MINIBOSS = {
	"unit": "chaos_hellbrute",
	"soldiers": 1,
	"elite_unit": "chaos_champion",
	"elite_soldiers": 2,    # бойцов в элитном отряде
	"elite_base": 0,
	"elite_wave_div": 5,    # волна 5 — 1 элитный отряд, волна 10 — 2
}

# Главный босс (последняя волна): Chaos Lord заменяет передние отряды обычной волны
const BOSS = {
	"unit": "chaos_lord",
	"soldiers": 1,
	"replaces_squads": 2,
}

static func get_stat_mult(wave: int) -> float:
	return 1.0 + max(wave - 1, 0) * STAT_STEP_PER_WAVE

static func get_normal_squads(wave: int) -> int:
	return SQUADS_BASE + (max(wave, 1) - 1) / SQUADS_EVERY_WAVES

static func get_soldiers_per_squad(wave: int) -> int:
	return mini(SOLDIERS_BASE + (max(wave, 1) - 1) / SOLDIERS_EVERY_WAVES, MAX_SOLDIERS_PER_SQUAD)

# Возвращает [{ "unit": factory_id, "count": бойцов, "mult": множитель hp/урона }]
static func build(wave: int, node_type: String, max_squads: int) -> Array[Dictionary]:
	wave = max(wave, 1)
	var mult = get_stat_mult(wave)
	var squads: Array[Dictionary] = []
	var replaced = 0   # сколько отрядов обычной волны заменено
	match node_type:
		RunMapNode.BOSS:
			squads.append({"unit": BOSS["unit"], "count": BOSS["soldiers"], "mult": mult})
			replaced = BOSS["replaces_squads"]
		RunMapNode.MINIBOSS:
			squads.append({"unit": MINIBOSS["unit"], "count": MINIBOSS["soldiers"], "mult": mult})
			var elites = MINIBOSS["elite_base"] + wave / MINIBOSS["elite_wave_div"]
			for i in range(mini(elites, max_squads - squads.size())):
				squads.append({"unit": MINIBOSS["elite_unit"], "count": MINIBOSS["elite_soldiers"], "mult": mult})
				replaced += 1
	# Обычная волна за спинами босса и элиты
	var soldiers = get_soldiers_per_squad(wave)
	var normal = maxi(get_normal_squads(wave) - replaced, 1)
	for i in range(mini(normal, max_squads - squads.size())):
		squads.append({"unit": NORMAL_UNIT, "count": soldiers, "mult": mult})
	return squads
