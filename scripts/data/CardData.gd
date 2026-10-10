class_name CardData
extends Resource

# --- Идентификация ---
@export var id: String = ""
@export var title: String = ""
@export var description: String = ""
@export var faction: String = ""
@export var cost: int = 10
@export var rarity: String = "common"

# --- Тип карты ---
# "squad" — даёт юнитов
# "building" — ставит здание
# "upgrade" — улучшает существующих юнитов
@export var card_type: String = "squad"

# --- Если squad ---
@export var unit_factory_id: String = ""  # "tactical_marine", "assault_marine"
@export var unit_count: int = 3

# --- Если building ---
@export var building_type: String = ""  # "tower", "barracks", "altar"
@export var building_stats: Dictionary = {}

# --- Если upgrade ---
@export var upgrade_type: String = ""   # "hp_boost", "damage_boost"
@export var upgrade_value: float = 0.0  # 0.2 = +20%
@export var affects_tag: String = ""    # "marine", "chaos" — кого затрагивает

# Куда класть карту в бою — подсказка для магазина и скамейки. Новый тип карты:
# строка здесь + обработчик в BattleScene._card_handlers
const PLAY_HINTS = {
	"upgrade": "на свой отряд",
	"building": "здание → на клетку",
}

func get_play_hint() -> String:
	return PLAY_HINTS.get(card_type, "")

# Строка состава/характеристик отряда («×3  HP 100  УРН 12  ДАЛ 250»), пусто — не отряд
func get_stats_line() -> String:
	if card_type != "squad":
		return ""
	var u = UnitFactory.create(unit_factory_id)
	return "×%d   HP %d   УРН %d   ДАЛ %d" % [unit_count, u.hp, u.damage, u.attack_range]
