class_name GameConstants
extends RefCounted

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
