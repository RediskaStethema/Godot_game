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
# Бойцов в отряде не больше (сложность множит состав): прежний наибольший — 12 культистов ×SQUAD_SPLIT.
# Больше — отряд вылезает за свою клетку, а бой тяжелеет (tests/bench_battle.gd)
const MAX_SQUAD_SOLDIERS: int = 36

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

# Космодесант-враг (забег за Хаос, решение пользователя 16.10.2026): те же правила волн. Архетипы —
# отряды Космодесанта игрока (дальность не больше MAX_ENEMY_RANGE), power — от √(HP × DPS) с поправкой
# как у Хаоса (черновые, подобрать tests/balance_sim.gd); элита и боссы — статы Хаоса, вид Космодесанта
const SM_ARCHETYPES = {
	"assault_marine":  {"power": 1.6, "from_wave": 4, "weight": 2, "max_share": 0.34, "max_count": 6,  "order": 0},
	"tactical_marine": {"power": 1.1, "from_wave": 1, "weight": 3, "max_share": 1.0,  "max_count": 6,  "order": 1},
	"devastator":      {"power": 2.6, "from_wave": 3, "weight": 2, "max_share": 0.34, "max_count": 6,  "order": 2},
	"scout_marine":    {"power": 0.6, "from_wave": 1, "weight": 2, "max_share": 0.34, "max_count": 10, "order": 3},
}
const SM_MINIBOSS = {
	"unit": "dreadnought_boss",
	"soldiers": 1,
	"elite_unit": "veteran_terminator",
	"elite_soldiers": 2,
	"elite_base": 0,
	"elite_wave_div": 5,
}
const SM_BOSS = {
	"unit": "chapter_master_boss",
	"soldiers": 1,
	"replaces_squads": 2,
}
# Раса врага → набор волн (FactionTheme.enemy_of)
const ENEMY_SETS = {
	"chaos": {"archetypes": ARCHETYPES, "miniboss": MINIBOSS, "boss": BOSS},
	"space_marines": {"archetypes": SM_ARCHETYPES, "miniboss": SM_MINIBOSS, "boss": SM_BOSS},
}
# Дальность врага не больше: иначе он бьёт цитадель из-за её орудия (дальность + Citadel.HIT_RADIUS
# < Citadel.ATTACK_RANGE) и штурм не отбить. У Хаоса наибольшая — Havoc 260; Scout и Devastator
# Космодесанта-врага стреляют не дальше (BattleScene._place_enemy_squads)
const MAX_ENEMY_RANGE: float = 260.0

static func _enemy_set(enemy: String) -> Dictionary:
	return ENEMY_SETS.get(enemy, ENEMY_SETS["chaos"])

# Данные архетипа любой расы (id юнитов у рас разные)
static func _archetype_data(unit: String) -> Dictionary:
	return ARCHETYPES[unit] if ARCHETYPES.has(unit) else SM_ARCHETYPES[unit]

static func get_stat_mult(wave: int) -> float:
	return 1.0 + max(wave - 1, 0) * STAT_STEP_PER_WAVE

static func get_normal_squads(wave: int) -> int:
	return SQUADS_BASE + (max(wave, 1) - 1) / SQUADS_EVERY_WAVES

static func get_soldiers_per_squad(wave: int) -> int:
	return mini(SOLDIERS_BASE + (max(wave, 1) - 1) / SOLDIERS_EVERY_WAVES, MAX_SOLDIERS_PER_SQUAD)

# Сколько бойцов архетипа дают бюджет отряда (бюджет — в бойцах Chaos Marine прежнего размера;
# в отряде их ×UnitFactory.SQUAD_SPLIT — build())
static func get_archetype_count(unit: String, budget: int) -> int:
	var a: Dictionary = _archetype_data(unit)
	return clampi(roundi(budget / a["power"]), 1, a["max_count"])

# Архетип с поправкой уровня сложности (Difficulty): сильные — чаще, раньше и большей долей
static func get_archetype(unit: String, difficulty: int = Difficulty.DEFAULT) -> Dictionary:
	var a: Dictionary = _archetype_data(unit)
	if not unit in Difficulty.STRONG:
		return a
	var d = Difficulty.get_level(difficulty)
	a = a.duplicate()
	a["weight"] = a["weight"] * d["strong_weight"]
	a["from_wave"] = maxi(a["from_wave"] - d["strong_earlier"], 1)
	a["max_share"] = maxf(a["max_share"], d["strong_share"])
	return a

# Архетипы обычных отрядов волны, от переднего края в тыл
static func pick_archetypes(wave: int, squads: int, seed_value: int,
		difficulty: int = Difficulty.DEFAULT, enemy: String = "chaos") -> Array[String]:
	var archetypes: Dictionary = _enemy_set(enemy)["archetypes"]
	var rng = RandomNumberGenerator.new()
	rng.seed = hash([seed_value, wave])
	var picked: Array[String] = []
	var taken: Dictionary = {}
	for i in range(squads):
		var pool: Array[String] = []
		var total = 0.0
		for unit in archetypes:
			var a: Dictionary = get_archetype(unit, difficulty)
			var cap = maxi(ceili(squads * a["max_share"]), 1)
			if wave >= a["from_wave"] and taken.get(unit, 0) < cap:
				pool.append(unit)
				total += a["weight"]
		# Веса целые (уровень Difficulty.DEFAULT и ниже без дробей) — прежний целый бросок: состав волн
		# прежнего баланса не меняется; дробные (поправка сложности) — бросок по доле
		var roll: float = rng.randi_range(1, int(total)) if is_equal_approx(total, roundf(total)) else rng.randf() * total
		for unit in pool:
			roll -= get_archetype(unit, difficulty)["weight"]
			if roll <= 0.0 or unit == pool[-1]:
				picked.append(unit)
				taken[unit] = taken.get(unit, 0) + 1
				break
	picked.sort_custom(func(a, b): return archetypes[a]["order"] < archetypes[b]["order"])
	return picked

# Возвращает [{ "unit": factory_id, "count": бойцов, "mult": множитель hp/урона }].
# seed_value — seed забега (RunManager.rng.seed): от него случайный состав волны.
# difficulty — уровень сложности забега (Difficulty): бойцов в обычных отрядах и сильные архетипы
# enemy — раса врага (FactionTheme.enemy_of расы игрока): Хаос или Космодесант
static func build(wave: int, node_type: String, max_squads: int, seed_value: int = 0,
		difficulty: int = Difficulty.DEFAULT, enemy: String = "chaos") -> Array[Dictionary]:
	wave = max(wave, 1)
	var boss: Dictionary = _enemy_set(enemy)["boss"]
	var miniboss: Dictionary = _enemy_set(enemy)["miniboss"]
	var mult = get_stat_mult(wave)
	var squads: Array[Dictionary] = []
	var replaced = 0   # сколько отрядов обычной волны заменено
	match node_type:
		RunMapNode.BOSS:
			squads.append({"unit": boss["unit"], "count": boss["soldiers"], "mult": mult})
			replaced = boss["replaces_squads"]
		RunMapNode.MINIBOSS:
			squads.append({"unit": miniboss["unit"], "count": miniboss["soldiers"], "mult": mult})
			var elites = miniboss["elite_base"] + wave / miniboss["elite_wave_div"]
			for i in range(mini(elites, max_squads - squads.size())):
				squads.append({"unit": miniboss["elite_unit"], "count": miniboss["elite_soldiers"], "mult": mult})
				replaced += 1
	# Обычная волна за спинами босса и элиты
	var budget = get_soldiers_per_squad(wave)
	var normal = mini(maxi(get_normal_squads(wave) - replaced, 1), max_squads - squads.size())
	var enemies: float = Difficulty.get_level(difficulty)["enemies"]
	for unit in pick_archetypes(wave, normal, seed_value, difficulty, enemy):
		var count = clampi(roundi(get_archetype_count(unit, budget) * UnitFactory.SQUAD_SPLIT * enemies), 1,
			MAX_SQUAD_SOLDIERS)
		squads.append({"unit": unit, "count": count, "mult": mult})
	return squads
