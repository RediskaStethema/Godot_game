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
# Прыжок (Assault Marine): раз за бой боец прыгает на ближайшего вражеского стрелка ближе jump_range;
# при приземлении — удар по всем врагам в jump_radius (урон удара × jump_damage_mult) и оглушение
@export var jump_range: float = 0.0          # 0 — не прыгает
@export var jump_damage_mult: float = 0.0
@export var jump_radius: float = 0.0
@export var jump_stun: float = 0.0
# Окапывание (Devastator): стоит на месте — урон растёт до +entrench_bonus за entrench_time сек;
# сдвинулся (бег, отброс) — с нуля
@export var entrench_time: float = 0.0       # 0 — не окапывается
@export var entrench_bonus: float = 0.0
# Deep Strike (Terminator): через deep_strike_delay сек боя отряд телепортируется к ближайшему врагу
@export var deep_strike_delay: float = 0.0   # 0 — нет
# Стрельба на ходу (Land Speeder): в ATTACK не стоит — кружит вокруг цели, держит дистанцию
@export var mobile_fire: bool = false

# --- Визуал ---
# Пока у новых юнитов нет своих спрайтов — различаем их тинтом и размером
@export var tint: Color = Color.WHITE
@export var sprite_scale: float = 1.0
# Броня в цвет ордена игрока (Soldier.ARMOR_SHADER); false — лист уже в цветах своего ордена (особые юниты)
@export var chapter_armor: bool = true
# Снаряд стрелка — вид из Projectile.EFFECTS ("bolt" / "charged" / "spark"), "" — без снаряда.
# Урон и эффекты попадания (стан, отбрасывание) — когда снаряд долетит (Projectile._impact).
@export var projectile: String = ""
@export var projectile_warm: bool = false   # синий эффект → красно-оранжевый (Хаос)
# Цвет крови при попадании (Vfx.BLOOD_COLORS), "" — по тегам: get_blood()
@export var blood: String = ""

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
# Тип каждого бойца по тем же индексам, что saved_hp: "" — боец этого отряда, иначе боец бога Хаоса,
# вставший на место павшего (Святилище культа, UnitFactory.convert_fighter: "<factory_id>:<редкость>").
# Может быть короче saved_hp — недостающие "" (кто дописывает своих бойцов, kinds не трогает)
@export var saved_kinds: Array[String] = []
# Множители от карт-улучшений этого отряда (и от масштабирования врагов по волнам).
# Базовые hp/damage не трогаем. Живут вместе с отрядом между раундами.
@export var hp_multiplier: float = 1.0
@export var damage_multiplier: float = 1.0
@export var attack_speed_multiplier: float = 1.0
@export var applied_upgrades: Array[String] = []   # названия карт — для UI
# Карты-улучшения со своими эффектами (живут с отрядом, сбрасываются при возрождении):
# Iron Halo — щит каждому бойцу в начале боя (доля max HP), Combat Stimms — бег
# быстрее, Chapter Banner — аура урона союзникам рядом (не суммируется с другими аурами)
@export var shield_ratio: float = 0.0
@export var move_speed_multiplier: float = 1.0
@export var banner_aura_bonus: float = 0.0
const BANNER_RADIUS: float = 107.0   # 23.10.2026 (решение пользователя): было 160 — круг на пол-поля
# Полный состав отряда (CardData.unit_count) — до него лечение возвращает павших
@export var squad_size: int = 0
# Уровень отряда: сколько раз его улучшили картой того же отряда (0..MAX_SQUAD_LEVEL)
@export var squad_level: int = 0
# Бойцов, которых добавляет каждый уровень (пехота — UnitFactory.SQUAD_GROWTH, герои — 0)
@export var squad_growth: int = 0
# Доля прежнего бойца (пехота — 1 / UnitFactory.SQUAD_SPLIT, остальные — 1): столько юнитов боец
# значит в синергиях и такую долю получает урона по площади и от яда / огня. Из UnitFactory, не сохраняется
var unit_weight: float = 1.0
# Возрождён после боя (respawn_after_wipe) — на расстановке следующего боя свет появления; не сохраняется
var respawned: bool = false

# Бог-покровитель отряда Хаоса (ChaosGods; решение пользователя 25.10.2026): "" — по юниту (по лору), у Common
# бога нет. Карта «Chaos Gods' Blessing» меняет его, благословения (blessings, до ChaosGods.MAX_BLESSINGS) — только
# своего бога, при смене бога пропадают. Сохраняются
@export var god: String = ""
@export var blessings: int = 0

func get_god() -> String:
	return god if god != "" else ChaosGods.default_god(factory_id)

# Прибавки благословений бога отряда (множители и +урон) — в статах ниже
func _blessing() -> Dictionary:
	return ChaosGods.stat_mods(get_god(), blessings, tags, unit_weight)

func get_max_hp() -> float:
	return hp * hp_multiplier * _blessing()["hp"]

func get_damage() -> float:
	var b := _blessing()
	return (damage * damage_multiplier + b["flat_damage"]) * b["damage"]

func get_attack_speed() -> float:
	return attack_speed * attack_speed_multiplier * _blessing()["attack_speed"]

func get_move_speed() -> float:
	return move_speed * move_speed_multiplier * _blessing()["move_speed"]

func get_attack_range() -> float:
	return attack_range * _blessing()["range"]

# Порог отступления: благословение Кхорна — не отступает
func get_retreat_threshold() -> float:
	return 0.0 if ChaosGods.no_retreat(get_god(), blessings) else retreat_hp_threshold

# Благословение бога: только отряд этого бога (у Common бога нет — сначала «Chaos Gods' Blessing»), не больше
# MAX_BLESSINGS; Тзинч — только стрелкам
func can_bless(card_god: String) -> bool:
	return card_god != "" and card_god == get_god() and blessings < ChaosGods.MAX_BLESSINGS 		and (card_god != "tzeentch" or "ranged" in tags)

# Смена бога отряда (карта «Chaos Gods' Blessing»): любой отряд Хаоса, в том числе Common без бога (решение
# пользователя 25.10.2026) — получает выбранного бога; благословения пропадают
func can_change_god() -> bool:
	return "chaos" in tags

func change_god(new_god: String) -> void:
	god = new_god
	blessings = 0

# Цвет крови (Vfx.BLOOD_COLORS): свой blood или по тегам — техника масло, Космодесант тёмно-красная,
# Космодесант Хаоса фиолетовая, остальные (люди) красная
func get_blood() -> String:
	if blood != "":
		return blood
	if "vehicle" in tags:
		return "oil"
	if "marine" in tags:
		return "dark_red"
	if "chaos" in tags:
		return "purple"
	return "red"

# Тип бойца i (saved_kinds): "" — свой
func kind_at(i: int) -> String:
	return saved_kinds[i] if i < saved_kinds.size() else ""

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
	shield_ratio = 0.0
	move_speed_multiplier = 1.0
	banner_aura_bonus = 0.0
	applied_upgrades.clear()
	saved_kinds.clear()   # бойцы богов не возрождаются — весь состав свой
	squad_size -= squad_growth * squad_level
	squad_level = 0
	for i in range(new_level):
		apply_merge_upgrade()
	var hp_list: Array[float] = []
	for i in range(maxi(squad_size, 1)):
		hp_list.append(1.0)
	saved_hp = hp_list
	blessings = 0   # благословения — карты-улучшения: сбрасываются, бог остаётся
	respawned = true

# Сохранение отряда игрока: тип (factory_id) + состояние между боями.
# Базовые статы не храним — берутся из UnitFactory (правки баланса применяются)
func save_state() -> Dictionary:
	return {
		"id": factory_id,
		"saved_hp": Array(saved_hp),
		"kinds": Array(saved_kinds),
		"hp_mult": hp_multiplier,
		"dmg_mult": damage_multiplier,
		"as_mult": attack_speed_multiplier,
		"upgrades": Array(applied_upgrades),
		"shield": shield_ratio,
		"move_mult": move_speed_multiplier,
		"banner": banner_aura_bonus,
		"squad_size": squad_size,
		"level": squad_level,
		"growth": squad_growth,
		"god": god,
		"blessings": blessings,
	}

static func from_save_state(d: Dictionary) -> UnitData:
	var u = UnitFactory.create(d["id"])
	var hp: Array[float] = []
	for v in d["saved_hp"]:
		hp.append(float(v))
	u.saved_hp = hp
	var kinds: Array[String] = []
	for k in d.get("kinds", []):
		kinds.append(str(k))
	u.saved_kinds = kinds
	u.hp_multiplier = float(d["hp_mult"])
	u.damage_multiplier = float(d["dmg_mult"])
	u.attack_speed_multiplier = float(d["as_mult"])
	var ups: Array[String] = []
	for s in d["upgrades"]:
		ups.append(str(s))
	u.applied_upgrades = ups
	u.shield_ratio = float(d.get("shield", 0.0))
	u.move_speed_multiplier = float(d.get("move_mult", 1.0))
	u.banner_aura_bonus = float(d.get("banner", 0.0))
	u.squad_size = int(d["squad_size"])
	u.squad_level = int(d["level"])
	u.squad_growth = int(d.get("growth", 0))
	u.god = str(d.get("god", ""))
	u.blessings = int(d.get("blessings", 0))
	# Сохранение до пехоты ×SQUAD_SPLIT: бойцов втрое больше с той же долей HP, состав растёт с уровнем
	if not d.has("growth") and u.factory_id in UnitFactory.SPLIT_UNITS:
		u.squad_growth = UnitFactory.SQUAD_GROWTH
		u.squad_size = u.squad_size * UnitFactory.SQUAD_SPLIT + u.squad_growth * u.squad_level
		u.saved_hp = _split_hp(u.saved_hp, UnitFactory.SQUAD_SPLIT)
	# Сохранение до пар героев: одиночка → пара с той же долей HP, состав растёт с уровнем
	elif u.factory_id in UnitFactory.PAIR_UNITS and u.squad_growth == 0:
		u.squad_growth = UnitFactory.PAIR_GROWTH
		u.squad_size = u.squad_size * UnitFactory.PAIR_SPLIT + u.squad_growth * u.squad_level
		u.saved_hp = _split_hp(u.saved_hp, UnitFactory.PAIR_SPLIT)
	return u

# Каждый боец старого сохранения → n бойцов с той же долей HP
static func _split_hp(hp: Array[float], n: int) -> Array[float]:
	var out: Array[float] = []
	for v in hp:
		for i in n:
			out.append(v)
	return out

# Может ли карта-улучшение быть применена к этому отряду
func can_apply_upgrade(card: CardData) -> bool:
	if card.card_type != "upgrade" or not (card.affects_tag == "" or card.affects_tag in tags):
		return false
	if card.upgrade_type == "blessing":   # благословение бога — только отряду этого бога
		return can_bless(card.blessing_god)
	if card.upgrade_type == "change_god":
		return can_change_god()
	# Знамя не складывается — второе такое же на отряд ничего бы не дало
	return not (card.upgrade_type == "banner" and banner_aura_bonus >= card.upgrade_value)

# Улучшение отряда — множитель накапливается (две карты = ×1.2 × 1.2)
func apply_upgrade(card: CardData) -> void:
	match card.upgrade_type:
		"blessing":   # благословение бога — счётчик (ChaosGods), в список улучшений не идёт: пропадает со сменой бога
			blessings += 1
			return
		"change_god":   # бога выбирает игрок — BattleScene зовёт change_god
			return
		"hp_boost":
			hp_multiplier *= 1.0 + card.upgrade_value
		"damage_boost":
			damage_multiplier *= 1.0 + card.upgrade_value
		"shield":   # Iron Halo — щиты складываются
			shield_ratio += card.upgrade_value
		"stimms":   # Combat Stimms — бег и скорострельность
			move_speed_multiplier *= 1.0 + card.upgrade_value
			attack_speed_multiplier *= 1.0 + card.upgrade_value
		"banner":   # Chapter Banner — аура, берётся сильнейшая
			banner_aura_bonus = maxf(banner_aura_bonus, card.upgrade_value)
	applied_upgrades.append(card.title)
