class_name GameConstants
extends RefCounted

# --- Валюта ---
# Валюта в текстах — «монеты» (решение пользователя 12.11.2026: «убери Req, оставь монеты»; в коде прежнее имя
# requisition). coins(5) → «5 монет», coins(21) → «21 монета», coins(3) → «3 монеты»
static func coins(n: int) -> String:
	var a := absi(n)
	var word := "монет"
	if a % 10 == 1 and a % 100 != 11:
		word = "монета"
	elif a % 10 in [2, 3, 4] and not (a % 100 in [12, 13, 14]):
		word = "монеты"
	return "%d %s" % [n, word]

# --- Battle ---
const FIXED_TICK: float =0.1    # используется в BattleManager и Unit

# --- Приоритеты целей ---
# Выносим строки чтобы не писать "nearest" руками в разных местах.
# Опечатка в строке — молчаливый баг. Опечатка в константе — ошибка компилятора.
const PRIORITY_NEAREST: String = "nearest"
const PRIORITY_LOWEST_HP: String = "lowest_hp"
const PRIORITY_HIGHEST_THREAT: String = "highest_threat"
const PRIORITY_FARTHEST:String="farthest"      # снайперы
const PRIORITY_RANDOM:String="random"
const PRIORITY_RANGED_FIRST: String = "ranged_first"   # ближайший стрелок [ranged], иначе ближайший
# --- Команды ---
const TEAM_PLAYER: int = 0
const TEAM_ENEMY: int = 1

# --- Редкости карт ---
const RARITY_COMMON: String = "common"
const RARITY_RARE: String = "rare"
const RARITY_EPIC: String = "epic"
