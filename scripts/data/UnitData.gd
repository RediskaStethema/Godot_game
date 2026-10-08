class_name UnitData
extends Resource

# UnitData.gd — добавь:
@export var damage_variance: float = 0.2
@export var sprite_path: String = "res://assets/sprites/space_marine"  # "res://assets/sprites/space_marine"

# --- Идентификация ---
@export var unit_name: String = ""
@export var faction: String = ""
@export var tags: Array = []  

# --- Боевые характеристики ---
@export var hp: float = 100.0
@export var damage: float = 10.0
@export var attack_speed: float = 1.0    # атак в секунду
@export var attack_range: float = 150.0  # в пикселях (десктоп — пиксели удобнее тайлов)
@export var move_speed: float = 80.0     # пикселей в секунду

# --- Поведение ---
@export var priority: String = "nearest" # nearest / lowest_hp / highest_threat
@export var vision_range: float = 350.0          # MOVE → CHASE, когда враг ближе
@export var cast_time: float = 0.0               # > 0 — перед ударом есть CASTING
@export var retreat_hp_threshold: float = 0.15   # HP < 15% → RETREATING (один раз)
@export var retreat_duration: float = 1.5        # сек отступления, потом снова в бой

# --- Поддержка (Apothecary) ---
@export var heal_per_second: float = 0.0   # > 0 — лечит раненого союзника рядом
@export var heal_radius: float = 0.0       # пиксели

# --- Визуал ---
# Пока у новых юнитов нет своих спрайтов — различаем их тинтом и размером
@export var tint: Color = Color.WHITE
@export var sprite_scale: float = 1.0

# --- Фракционные флаги ---
@export var has_reanimation: bool = false
@export var reanimation_chance: float = 0.30

# --- Мета ---
@export var cost: int = 5               # стоимость в Requisition
@export var rarity: String = "common"  # common / rare / epic
@export var sprite: Texture2D

# --- Состояние между боями ---
# Один UnitData = один отряд. saved_hp — доля HP (0..1] каждого выжившего бойца,
# размер массива = сколько бойцов вернётся в следующий бой. Доля, а не абсолют,
# чтобы баффы (синергии, улучшения) не обрезались при следующем спавне.
@export var saved_hp: Array[float] = []
# Множители от карт-улучшений этого отряда (и от масштабирования врагов по волнам).
# Базовые hp/damage не трогаем. Живут вместе с отрядом между раундами.
@export var hp_multiplier: float = 1.0
@export var damage_multiplier: float = 1.0
@export var applied_upgrades: Array[String] = []   # названия карт — для UI

func get_max_hp() -> float:
	return hp * hp_multiplier

func get_damage() -> float:
	return damage * damage_multiplier

# Может ли карта-улучшение быть применена к этому отряду
func can_apply_upgrade(card: CardData) -> bool:
	return card.card_type == "upgrade" and (card.affects_tag == "" or card.affects_tag in tags)

# Улучшение отряда — множитель накапливается (две карты = ×1.2 × 1.2)
func apply_upgrade(card: CardData) -> void:
	match card.upgrade_type:
		"hp_boost":
			hp_multiplier *= 1.0 + card.upgrade_value
		"damage_boost":
			damage_multiplier *= 1.0 + card.upgrade_value
	applied_upgrades.append(card.title)
