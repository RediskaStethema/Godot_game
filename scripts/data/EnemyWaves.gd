class_name EnemyWaves
extends RefCounted

# Состав врагов по волне и типу боя шага забега — данными.
# BattleScene расставляет отряды в порядке списка: с переднего края зоны врага в тыл.
# Баланс черновой (дальше — balance-analyst).

# Обычная волна: отрядов = SQUADS_BASE + (волна − 1) / SQUADS_EVERY_WAVES,
# бюджет отряда = SOLDIERS_BASE + (волна − 1) / SOLDIERS_EVERY_WAVES (не больше 6)
# бойцов в пересчёте на Chaos Marine, статы ×(1 + STAT_STEP_PER_WAVE за волну после первой).
# Подбор — tests/balance_sim.gd

# Архетипы обычной волны: каждый отряд — случайный архетип (вес weight, с волны
# from_wave, не больше доли max_share отрядов волны). Бойцов = бюджет / power
# (power — во сколько Chaos Marine обходится боец в бою; начато от √(HP × DPS),
# подобрано tests/balance_sim.gd campaign: за строем хавоки фокусируют урон и
# опаснее своих статов, рапторы бьют стрелков, чумные — слабее), от 1 до max_count.
# order — место в строю: меньше — ближе к переднему краю.
# Случайность — от seed забега и волны: переигровка боя даёт тот же состав
const ARCHETYPES = {
	"plague_marine": {"power": 1.3,  "from_wave": 6, "weight": 2, "max_share": 0.34, "max_count": 6,  "order": 0},
	"chaos_cultist": {"power": 0.6,  "from_wave": 1, "weight": 2, "max_share": 0.34, "max_count": 12, "order": 1},
	"chaos_raptor":  {"power": 2.25, "from_wave": 4, "weight": 2, "max_share": 0.34, "max_count": 6,  "order": 2},
	"chaos_marine":  {"power": 1.0,  "from_wave": 1, "weight": 3, "max_share": 1.0,  "max_count": 6,  "order": 3},
	"chaos_havoc":   {"power": 2.5,  "from_wave": 3, "weight": 2, "max_share": 0.34, "max_count": 6,  "order": 4},
}
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

# Сколько бойцов архетипа дают бюджет отряда (бюджет — в бойцах Chaos Marine)
static func get_archetype_count(unit: String, budget: int) -> int:
	var a: Dictionary = ARCHETYPES[unit]
	return clampi(roundi(budget / a["power"]), 1, a["max_count"])

# Архетипы обычных отрядов волны, от переднего края в тыл
static func pick_archetypes(wave: int, squads: int, seed_value: int) -> Array[String]:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash([seed_value, wave])
	var picked: Array[String] = []
	var taken: Dictionary = {}
	for i in range(squads):
		var pool: Array[String] = []
		var total = 0
		for unit in ARCHETYPES:
			var a: Dictionary = ARCHETYPES[unit]
			var cap = maxi(ceili(squads * a["max_share"]), 1)
			if wave >= a["from_wave"] and taken.get(unit, 0) < cap:
				pool.append(unit)
				total += a["weight"]
		var roll = rng.randi_range(1, total)
		for unit in pool:
			roll -= ARCHETYPES[unit]["weight"]
			if roll <= 0:
				picked.append(unit)
				taken[unit] = taken.get(unit, 0) + 1
				break
	picked.sort_custom(func(a, b): return ARCHETYPES[a]["order"] < ARCHETYPES[b]["order"])
	return picked

# Возвращает [{ "unit": factory_id, "count": бойцов, "mult": множитель hp/урона }].
# seed_value — seed забега (RunManager.rng.seed): от него случайный состав волны
static func build(wave: int, node_type: String, max_squads: int, seed_value: int = 0) -> Array[Dictionary]:
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
	var budget = get_soldiers_per_squad(wave)
	var normal = mini(maxi(get_normal_squads(wave) - replaced, 1), max_squads - squads.size())
	for unit in pick_archetypes(wave, normal, seed_value):
		squads.append({"unit": unit, "count": get_archetype_count(unit, budget), "mult": mult})
	return squads
