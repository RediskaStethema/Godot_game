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
