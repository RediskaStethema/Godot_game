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
	d.tags = ["marine", "vehicle", "fast"]
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
