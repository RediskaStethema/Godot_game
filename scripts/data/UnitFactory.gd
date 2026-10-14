class_name UnitFactory
extends RefCounted

# Статы — из таблицы TDD «Юниты MVP (Space Marines)».
# Дальности в пикселях: melee ≈ 60, ranged 200–320.

# Карта того же отряда, брошенная на отряд: улучшение (до MAX_SQUAD_LEVEL раз)
# или лечение (без ограничений). Бонусы зависят от фракции.
const MAX_SQUAD_LEVEL: int = 3
const SQUAD_MERGE_BONUSES = {
	"space_marines": {
		"damage": 0.20,         # +20% урона за уровень
		"hp": 0.20,             # +20% максимального HP за уровень
		"attack_speed": 0.15,   # +15% скорострельности за уровень
		"heal": 0.35,           # лечение: 35% максимального HP каждому бойцу
	},
}
const DEFAULT_FACTION: String = "space_marines"

# Пехота (решение пользователя): бойцы вдвое мельче, в отряде их ×SQUAD_SPLIT, HP и урон бойца
# ÷SQUAD_SPLIT — отряд 1-го уровня по силе как прежний. Статы в функциях ниже — прежние «на бойца»
# прежнего отряда (таблица TDD), делятся в create(). Такой боец — 1/SQUAD_SPLIT юнита (unit_weight):
# в синергиях и в уроне по площади / яда / огня (мелких бойцов в толпе накрывает втрое больше)
# Каждое из MAX_SQUAD_LEVEL улучшений пехоты добавляет SQUAD_GROWTH бойцов (UnitData.squad_growth):
# Tactical / Scout 9 → 11 → 13 → 15 (самый крупный отряд — 15, решение пользователя),
# Assault / Devastator / Terminator 6 → 8 → 10 → 12. Герои, техника, элита и боссы — по одному
const SQUAD_SPLIT: int = 3
const SQUAD_GROWTH: int = 2

# Бойцов за уровень у отряда карты: пехота — SQUAD_GROWTH, одиночки — 0
static func squad_growth_for(card: CardData) -> int:
	return SQUAD_GROWTH if card.unit_count > 1 else 0
const SPLIT_UNITS = ["tactical_marine", "assault_marine", "scout_marine", "devastator", "terminator",
	"chaos_marine", "chaos_cultist", "chaos_havoc", "chaos_raptor", "plague_marine"]

static func get_merge_bonuses(faction: String) -> Dictionary:
	return SQUAD_MERGE_BONUSES.get(faction, SQUAD_MERGE_BONUSES[DEFAULT_FACTION])

# Создание юнита по id карты (CardData.unit_factory_id)
static func create(factory_id: String) -> UnitData:
	var d: UnitData
	match factory_id:
		"tactical_marine": d = tactical_marine()
		"assault_marine":  d = assault_marine()
		"chaos_marine":    d = chaos_marine()
		"chaos_champion":  d = chaos_champion()
		"chaos_lord":      d = chaos_lord()
		"chaos_hellbrute": d = chaos_hellbrute()
		"chaos_cultist":   d = chaos_cultist()
		"chaos_havoc":     d = chaos_havoc()
		"chaos_raptor":    d = chaos_raptor()
		"plague_marine":   d = plague_marine()
		"scout_marine":    d = scout_marine()
		"devastator":      d = devastator()
		"terminator":      d = terminator()
		"apothecary":      d = apothecary()
		"librarian":       d = librarian()
		"chaplain":        d = chaplain()
		"land_speeder":    d = land_speeder()
		"dreadnought":     d = dreadnought()
		"chapter_master":  d = chapter_master()
		_:
			push_warning("UnitFactory: неизвестный id '%s', создаю Tactical Marine" % factory_id)
			d = tactical_marine()
			factory_id = "tactical_marine"
	# По нему карта узнаёт «свой» отряд
	d.factory_id = factory_id
	if factory_id in SPLIT_UNITS:
		d.hp /= SQUAD_SPLIT
		d.damage /= SQUAD_SPLIT
		d.unit_weight = 1.0 / SQUAD_SPLIT
	return d

static func tactical_marine() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Tactical Marine"
	d.faction = "space_marines"
	d.tags = ["marine", "ranged", "infantry"]
	d.hp = 100.0
	d.damage = 12.0
	d.attack_speed = 0.9
	d.attack_range = 250.0
	d.move_speed = 80.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.cost = 5
	d.rarity = GameConstants.RARITY_COMMON
	d.sprite_path = "res://assets/sprites/space_marine"  # ← путь
	d.projectile = "bolt"
	return d


static func assault_marine() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Assault Marine"
	d.faction = "space_marines"
	d.tags = ["marine", "melee", "jump"]
	d.hp = 90.0
	d.damage = 18.0
	d.attack_speed = 1.2
	d.attack_range = 60.0
	d.move_speed = 120.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.cost = 5
	d.rarity = GameConstants.RARITY_COMMON
	d.sprite_path = "res://assets/sprites/space_marine"  # пока тот же спрайт
	return d

static func chaos_marine() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Chaos Marine"
	d.faction = "chaos"
	d.tags = ["chaos", "ranged", "infantry"]
	d.hp = 100.0
	d.damage = 14.0
	d.attack_speed = 0.9
	d.attack_range = 130.0
	d.move_speed = 75.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.cost = 5
	d.rarity = GameConstants.RARITY_COMMON
	d.sprite_path = "res://assets/sprites/chaos"  # ← временно тот же
	d.projectile = "bolt"
	d.projectile_warm = true
	return d

# Элита Хаоса (эскорт мини-босса): усиленный Chaos Marine ближнего боя.
# Своего спрайта нет — спрайт chaos, крупнее и с красным тинтом.
static func chaos_champion() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Chaos Champion"
	d.projectile = ""   # ближний бой — без снаряда Chaos Marine
	d.tags = ["chaos", "melee", "elite"]
	d.hp = 180.0
	d.damage = 22.0
	d.attack_speed = 1.0
	d.attack_range = 70.0
	d.move_speed = 80.0
	d.retreat_hp_threshold = 0.0
	d.rarity = GameConstants.RARITY_RARE
	d.tint = Color(1.0, 0.55, 0.5)
	d.sprite_scale = 1.25
	return d

# Главный босс последней волны: Chaos Lord — один огромный боец, удар отбрасывает.
# Спрайт chaos, фиолетовый тинт, ×1.8 размера. Баланс — черновой.
static func chaos_lord() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Chaos Lord"
	d.projectile = ""   # ближний бой — без снаряда Chaos Marine
	d.tags = ["chaos", "melee", "elite", "boss"]
	d.hp = 2200.0
	d.damage = 50.0
	d.attack_speed = 0.8
	d.attack_range = 80.0
	d.move_speed = 60.0
	d.on_hit_knockback = 250.0
	d.retreat_hp_threshold = 0.0
	d.rarity = GameConstants.RARITY_EPIC
	d.tint = Color(0.85, 0.5, 1.0)
	d.sprite_scale = 1.8
	return d

# Мини-босс каждой 5-й волны: Hellbrute — медленная машина ближнего боя,
# удар отбрасывает. Спрайт chaos, оранжевый тинт, ×1.5 размера. Баланс — черновой.
static func chaos_hellbrute() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Hellbrute"
	d.projectile = ""   # ближний бой — без снаряда Chaos Marine
	d.tags = ["chaos", "melee", "vehicle", "elite"]
	d.hp = 600.0
	d.damage = 30.0
	d.attack_speed = 0.7
	d.attack_range = 75.0
	d.move_speed = 55.0
	d.on_hit_knockback = 150.0
	d.retreat_hp_threshold = 0.0
	d.rarity = GameConstants.RARITY_EPIC
	d.tint = Color(1.0, 0.65, 0.35)
	d.sprite_scale = 1.5
	return d

# Архетипы обычных волн Хаоса (EnemyWaves.ARCHETYPES). Статы — от √(HP × DPS)
# Chaos Marine (35.5): культист 0.4 от него, рапторы 1.25, хавоки и чумные 1.5;
# сколько бойцов в отряде (EnemyWaves power) — подобрано tests/balance_sim.gd.
# Своих спрайтов нет — спрайт chaos с тинтом и масштабом.

# Культисты: толпа слабых стрелков с коротким стволом
static func chaos_cultist() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Chaos Cultist"
	d.tags = ["chaos", "ranged", "light"]
	d.hp = 40.0
	d.damage = 6.0
	d.attack_speed = 0.85
	d.attack_range = 110.0
	d.move_speed = 85.0
	d.tint = Color(0.75, 0.7, 0.6)
	d.sprite_scale = 0.85
	return d

# Хавоки: тяжёлое оружие из тыла, бьют самого опасного
static func chaos_havoc() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Havoc"
	d.tags = ["chaos", "ranged", "heavy"]
	d.hp = 130.0
	d.damage = 40.0
	d.attack_speed = 0.55
	d.attack_range = 260.0   # дальше Tactical, но в зоне орудия цитадели (260 + HIT_RADIUS < 320)
	d.move_speed = 60.0
	d.priority = GameConstants.PRIORITY_HIGHEST_THREAT
	d.projectile = "charged"
	d.on_hit_status = StatusEffects.BURNING   # попадание поджигает, огонь перекидывается
	d.on_hit_status_power = 3.0
	d.on_hit_status_duration = 3.0
	d.tint = Color(0.75, 0.85, 1.0)
	d.sprite_scale = 1.1
	return d

# Рапторы: быстрые бойцы ближнего боя, летят к стрелкам в тылу
static func chaos_raptor() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Raptor"
	d.projectile = ""
	d.tags = ["chaos", "melee", "jump"]
	d.hp = 120.0
	d.damage = 15.0
	d.attack_speed = 0.9
	d.attack_range = 60.0
	d.move_speed = 140.0
	d.priority = GameConstants.PRIORITY_RANGED_FIRST
	d.tint = Color(0.6, 0.6, 0.75)
	return d

# Чумные десантники: медленные и живучие, урон слабый, не отступают
static func plague_marine() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Plague Marine"
	d.projectile = ""
	d.tags = ["chaos", "melee", "heavy"]
	d.hp = 300.0
	d.damage = 12.0
	d.attack_speed = 0.8
	d.attack_range = 60.0
	d.move_speed = 55.0
	d.retreat_hp_threshold = 0.0
	d.on_hit_status = StatusEffects.POISONED   # яд Nurgle: стак за удар
	d.on_hit_status_power = 2.0
	d.on_hit_status_duration = 4.0
	d.tint = Color(0.7, 1.0, 0.55)
	d.sprite_scale = 1.15
	return d

# Лёгкий стрелок: хрупкий, быстрый, добивает раненых
static func scout_marine() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Scout Marine"
	d.faction = "space_marines"
	d.tags = ["marine", "ranged", "light"]
	d.hp = 60.0
	d.damage = 8.0
	d.attack_speed = 1.2
	d.attack_range = 220.0
	d.move_speed = 110.0
	d.priority = GameConstants.PRIORITY_LOWEST_HP
	d.cost = 4
	d.rarity = GameConstants.RARITY_COMMON
	# TODO: свой спрайт scout_marine — пока space_marine с тинтом
	d.sprite_path = "res://assets/sprites/space_marine"
	d.tint = Color(0.75, 1.0, 0.75)
	d.sprite_scale = 0.85
	d.projectile = "spark"
	return d

# Тяжёлое оружие: медленный, бьёт редко и больно с большой дистанции
static func devastator() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Devastator"
	d.faction = "space_marines"
	d.tags = ["marine", "ranged", "heavy"]
	d.hp = 200.0
	d.damage = 44.0
	d.attack_speed = 0.5
	d.attack_range = 320.0
	d.move_speed = 60.0
	d.priority = GameConstants.PRIORITY_HIGHEST_THREAT
	d.cost = 7
	d.rarity = GameConstants.RARITY_RARE
	# TODO: свой спрайт devastator
	d.sprite_path = "res://assets/sprites/space_marine"
	d.tint = Color(0.6, 0.75, 1.0)
	d.projectile = "charged"
	return d

# Элитный танк ближнего боя
static func terminator() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Terminator"
	d.faction = "space_marines"
	d.tags = ["marine", "melee", "elite"]
	d.hp = 320.0
	d.damage = 38.0
	d.attack_speed = 0.8
	d.attack_range = 60.0
	d.move_speed = 55.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.retreat_hp_threshold = 0.0   # терминаторы не отступают
	d.cost = 10
	d.rarity = GameConstants.RARITY_RARE
	# TODO: свой спрайт terminator
	d.sprite_path = "res://assets/sprites/space_marine"
	d.tint = Color(1.0, 0.9, 0.55)
	d.sprite_scale = 1.35
	return d

# Медик: слабо бьёт, лечит раненых союзников в радиусе
static func apothecary() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Apothecary"
	d.faction = "space_marines"
	d.tags = ["marine", "support", "heal"]
	d.hp = 300.0
	d.damage = 10.0
	d.attack_speed = 0.8
	d.attack_range = 60.0
	d.move_speed = 80.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.heal_per_second = 20.0
	d.heal_radius = 150.0
	d.cost = 7
	d.rarity = GameConstants.RARITY_RARE
	# TODO: свой спрайт apothecary
	d.sprite_path = "res://assets/sprites/space_marine"
	d.tint = Color(1.0, 0.7, 0.7)
	d.sprite_scale = 0.95
	return d

# Псайкер: бьёт через каст (CASTING), попадание оглушает цель
static func librarian() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Librarian"
	d.faction = "space_marines"
	d.tags = ["marine", "psyker", "elite"]
	d.hp = 450.0
	d.damage = 90.0
	d.attack_speed = 0.6
	d.attack_range = 220.0
	d.move_speed = 75.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.cast_time = 0.8
	d.on_hit_stun = 1.0
	d.cost = 10
	d.rarity = GameConstants.RARITY_RARE
	# TODO: свой спрайт librarian
	d.sprite_path = "res://assets/sprites/space_marine"
	d.tint = Color(0.55, 0.7, 1.0)
	d.sprite_scale = 1.05
	d.projectile = "charged"
	return d

# Капеллан: боец ближнего боя, аура +урон союзным melee рядом
static func chaplain() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Chaplain"
	d.faction = "space_marines"
	d.tags = ["marine", "melee", "support"]
	d.hp = 480.0
	d.damage = 36.0
	d.attack_speed = 1.0
	d.attack_range = 60.0
	d.move_speed = 75.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.aura_damage_bonus = 0.20
	d.aura_radius = 180.0
	d.aura_tag = "melee"
	# Боевой клич при первом сближении: всем союзникам рядом +20% урона на 6 с
	d.battle_cry_status = StatusEffects.EMPOWERED
	d.battle_cry_power = 0.20
	d.battle_cry_duration = 6.0
	d.battle_cry_radius = 180.0
	d.cost = 8
	d.rarity = GameConstants.RARITY_RARE
	# TODO: свой спрайт chaplain
	d.sprite_path = "res://assets/sprites/space_marine"
	d.tint = Color(0.45, 0.45, 0.5)
	d.sprite_scale = 1.05
	return d

# Скоростная техника: налетает на тыл врага, не отступает
static func land_speeder() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Land Speeder"
	d.faction = "space_marines"
	d.tags = ["marine", "ranged", "vehicle", "fast"]
	d.hp = 380.0
	d.damage = 70.0
	d.attack_speed = 1.0
	d.attack_range = 200.0
	d.move_speed = 160.0
	d.priority = GameConstants.PRIORITY_FARTHEST
	d.retreat_hp_threshold = 0.0
	d.cost = 9
	d.rarity = GameConstants.RARITY_RARE
	# TODO: свой спрайт land_speeder
	d.sprite_path = "res://assets/sprites/space_marine"
	d.tint = Color(1.0, 0.85, 0.4)
	d.sprite_scale = 1.1
	d.projectile = "bolt"
	return d

# Шагающая машина: огромный HP, удар отбрасывает цель
static func dreadnought() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Dreadnought"
	d.faction = "space_marines"
	d.tags = ["marine", "vehicle", "elite"]
	d.hp = 1400.0
	d.damage = 90.0
	d.attack_speed = 0.6
	d.attack_range = 70.0
	d.move_speed = 45.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.on_hit_knockback = 300.0
	d.retreat_hp_threshold = 0.0
	d.cost = 14
	d.rarity = GameConstants.RARITY_EPIC
	# TODO: свой спрайт dreadnought
	d.sprite_path = "res://assets/sprites/space_marine"
	d.tint = Color(0.7, 0.7, 0.75)
	d.sprite_scale = 1.6
	return d

# Магистр ордена: +10% урона всей армии на старте боя
static func chapter_master() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Chapter Master"
	d.faction = "space_marines"
	d.tags = ["marine", "elite", "commander"]
	d.hp = 1000.0
	d.damage = 75.0
	d.attack_speed = 1.0
	d.attack_range = 60.0
	d.move_speed = 70.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.commander_damage_bonus = 0.15
	d.retreat_hp_threshold = 0.0
	d.cost = 16
	d.rarity = GameConstants.RARITY_EPIC
	# TODO: свой спрайт chapter_master
	d.sprite_path = "res://assets/sprites/space_marine"
	d.tint = Color(1.0, 0.8, 0.3)
	d.sprite_scale = 1.3
	return d
