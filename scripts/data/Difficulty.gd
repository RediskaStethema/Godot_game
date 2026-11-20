class_name Difficulty
extends RefCounted

# Уровни сложности забега (решения пользователя 14.10.2026): всего COUNT, в начале открыты
# первые START_UNLOCKED; победа над главным боссом на самом высоком открытом уровне открывает
# следующий (SaveManager.unlocked_difficulty — профиль игрока, не забег). Уровень DEFAULT —
# прежний баланс. Выбор — после ордена (DifficultySelectDialog), уровень забега —
# RunManager.difficulty (в сохранении забега).
#
# Уровень меняет только обычные отряды волн (EnemyWaves.build):
#   enemies        — бойцов в каждом отряде ×
#   strong_weight  — вес сильных архетипов (STRONG) ×
#   strong_earlier — сильные появляются на столько волн раньше (не раньше 1-й)
#   strong_share   — наибольшая доля отрядов волны одного сильного архетипа (не меньше своей в ARCHETYPES)
# Цифры черновые — подобраны tests/balance_sim.gd campaign … [уровень]
const COUNT: int = 7
const START_UNLOCKED: int = 3
const DEFAULT: int = 2
const STRONG = ["chaos_havoc", "chaos_raptor", "plague_marine",
	"assault_marine", "devastator"]   # Космодесант-враг (забег за Хаос)

const LEVELS = [
	{"name": "Новик",        "enemies": 0.80, "strong_weight": 0.75, "strong_earlier": 0, "strong_share": 0.34},
	{"name": "Брат Криспина",   "enemies": 1.00, "strong_weight": 1.00, "strong_earlier": 0, "strong_share": 0.34},
	{"name": "Седоусый",       "enemies": 1.15, "strong_weight": 1.25, "strong_earlier": 0, "strong_share": 0.34},
	{"name": "Куренной",       "enemies": 1.30, "strong_weight": 1.50, "strong_earlier": 1, "strong_share": 0.40},
	{"name": "Кошевой",       "enemies": 1.45, "strong_weight": 1.75, "strong_earlier": 1, "strong_share": 0.45},
	{"name": "Монструвакан", "enemies": 1.60, "strong_weight": 2.00, "strong_earlier": 2, "strong_share": 0.50},
	{"name": "Обесцвечивание", "enemies": 1.80, "strong_weight": 2.50, "strong_earlier": 2, "strong_share": 0.60},
]

# Параметры уровня (1..COUNT; вне диапазона — ближайший)
static func get_level(level: int) -> Dictionary:
	return LEVELS[clampi(level, 1, COUNT) - 1]

static func level_name(level: int) -> String:
	return get_level(level)["name"]

# Подпись для шапок и итога: «Сложность 3 · Ветеран»
static func describe(level: int) -> String:
	return "Сложность %d · %s" % [clampi(level, 1, COUNT), level_name(level)]
