class_name UnitData
extends Resource

# UnitData.gd — добавь:
@export var damage_variance: float = 0.2
@export var sprite_path: String = "res://assets/sprites/space_marine"  # "res://assets/sprites/space_marine"

# --- Идентификация ---
@export var factory_id: String = ""   # id из UnitFactory.create (= CardData.unit_factory_id)
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

# --- Способности (0 = выключено) ---
@export var on_hit_stun: float = 0.0        # сек оглушения цели при попадании (Librarian)
@export var on_hit_knockback: float = 0.0   # сила отбрасывания цели, px/сек (Dreadnought)
# Статус-эффект на цель при попадании (StatusEffects): +1 стак за удар
@export var on_hit_status: String = ""      # Plague Marine — poisoned, Havoc — burning
@export var on_hit_status_power: float = 0.0   # яд/огонь — урон в секунду за стак
@export var on_hit_status_duration: float = 0.0
# Боевой клич: при первом сближении с врагом — эффект союзникам в радиусе (Chaplain)
@export var battle_cry_status: String = ""
@export var battle_cry_power: float = 0.0    # empowered — доля урона за стак
@export var battle_cry_duration: float = 0.0
@export var battle_cry_radius: float = 0.0
# Аура: союзники с тегом aura_tag в радиусе бьют сильнее (Chaplain). Не суммируется
# с другими такими же аурами — берётся самая сильная.
@export var aura_damage_bonus: float = 0.0  # 0.15 = +15% урона
@export var aura_radius: float = 0.0        # пиксели
@export var aura_tag: String = ""
# Командир: +урон всем союзникам на старте боя (Chapter Master). Не суммируется.
@export var commander_damage_bonus: float = 0.0

# --- Визуал ---
# Пока у новых юнитов нет своих спрайтов — различаем их тинтом и размером
@export var tint: Color = Color.WHITE
@export var sprite_scale: float = 1.0
# Снаряд стрелка — вид из Projectile.EFFECTS ("bolt" / "charged" / "spark"), "" — без снаряда.
# Урон и эффекты попадания (стан, отбрасывание) — когда снаряд долетит (Projectile._impact).
@export var projectile: String = ""
@export var projectile_warm: bool = false   # синий эффект → красно-оранжевый (Хаос)

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
@export var attack_speed_multiplier: float = 1.0
@export var applied_upgrades: Array[String] = []   # названия карт — для UI
# Полный состав отряда (CardData.unit_count) — до него лечение возвращает павших
@export var squad_size: int = 0
# Уровень отряда: сколько раз его улучшили картой того же отряда (0..MAX_SQUAD_LEVEL)
@export var squad_level: int = 0
# Бойцов, которых добавляет каждый уровень (пехота — UnitFactory.SQUAD_GROWTH, герои — 0)
@export var squad_growth: int = 0
# Доля прежнего бойца (пехота — 1 / UnitFactory.SQUAD_SPLIT, остальные — 1): столько юнитов боец
# значит в синергиях и такую долю получает урона по площади и от яда / огня. Из UnitFactory, не сохраняется
var unit_weight: float = 1.0

func get_max_hp() -> float:
	return hp * hp_multiplier

func get_damage() -> float:
	return damage * damage_multiplier

func get_attack_speed() -> float:
	return attack_speed * attack_speed_multiplier

# Карта того же отряда: улучшить можно, пока не достигнут максимальный уровень
func can_merge_upgrade() -> bool:
	return squad_level < UnitFactory.MAX_SQUAD_LEVEL

# Улучшение картой того же отряда — множители накапливаются, как у карт-улучшений
func apply_merge_upgrade() -> void:
	var b = UnitFactory.get_merge_bonuses(faction)
	damage_multiplier *= 1.0 + b["damage"]
	hp_multiplier *= 1.0 + b["hp"]
	attack_speed_multiplier *= 1.0 + b["attack_speed"]
	squad_level += 1
	squad_size += squad_growth

# Отряд пал целиком в выигранном бою: возрождается полным составом с полным HP,
# на уровень ниже и без карт-улучшений (с базового уровня — просто возрождается).
func respawn_after_wipe() -> void:
	var new_level = maxi(squad_level - 1, 0)
	hp_multiplier = 1.0
	damage_multiplier = 1.0
	attack_speed_multiplier = 1.0
	applied_upgrades.clear()
	squad_size -= squad_growth * squad_level
	squad_level = 0
	for i in range(new_level):
		apply_merge_upgrade()
	var hp_list: Array[float] = []
	for i in range(maxi(squad_size, 1)):
		hp_list.append(1.0)
	saved_hp = hp_list

# Сохранение отряда игрока: тип (factory_id) + состояние между боями.
# Базовые статы не храним — берутся из UnitFactory (правки баланса применяются)
func save_state() -> Dictionary:
	return {
		"id": factory_id,
		"saved_hp": Array(saved_hp),
		"hp_mult": hp_multiplier,
		"dmg_mult": damage_multiplier,
		"as_mult": attack_speed_multiplier,
		"upgrades": Array(applied_upgrades),
		"squad_size": squad_size,
		"level": squad_level,
		"growth": squad_growth,
	}

static func from_save_state(d: Dictionary) -> UnitData:
	var u = UnitFactory.create(d["id"])
	var hp: Array[float] = []
	for v in d["saved_hp"]:
		hp.append(float(v))
	u.saved_hp = hp
	u.hp_multiplier = float(d["hp_mult"])
	u.damage_multiplier = float(d["dmg_mult"])
	u.attack_speed_multiplier = float(d["as_mult"])
	var ups: Array[String] = []
	for s in d["upgrades"]:
		ups.append(str(s))
	u.applied_upgrades = ups
	u.squad_size = int(d["squad_size"])
	u.squad_level = int(d["level"])
	u.squad_growth = int(d.get("growth", 0))
	# Сохранение до пехоты ×SQUAD_SPLIT: бойцов втрое больше с той же долей HP, состав растёт с уровнем
	if not d.has("growth") and u.unit_weight < 1.0:
		u.squad_growth = UnitFactory.SQUAD_GROWTH
		u.squad_size = u.squad_size * UnitFactory.SQUAD_SPLIT + u.squad_growth * u.squad_level
		var split_hp: Array[float] = []
		for v in u.saved_hp:
			for i in UnitFactory.SQUAD_SPLIT:
				split_hp.append(v)
		u.saved_hp = split_hp
	return u

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
