class_name UnitFactory
extends RefCounted

# Статы — из таблицы TDD «Юниты MVP (Space Marines)».
# Дальности в пикселях: melee ≈ 60, ranged 200–320.

# Создание юнита по id карты (CardData.unit_factory_id)
static func create(factory_id: String) -> UnitData:
	match factory_id:
		"tactical_marine": return tactical_marine()
		"assault_marine":  return assault_marine()
		"chaos_marine":    return chaos_marine()
		"scout_marine":    return scout_marine()
		"devastator":      return devastator()
		"terminator":      return terminator()
		"apothecary":      return apothecary()
		_:
			push_warning("UnitFactory: неизвестный id '%s', создаю Tactical Marine" % factory_id)
			return tactical_marine()

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
	d.cost = 3
	d.rarity = GameConstants.RARITY_COMMON
	# TODO: свой спрайт scout_marine — пока space_marine с тинтом
	d.sprite_path = "res://assets/sprites/space_marine"
	d.tint = Color(0.75, 1.0, 0.75)
	d.sprite_scale = 0.85
	return d

# Тяжёлое оружие: медленный, бьёт редко и больно с большой дистанции
static func devastator() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Devastator"
	d.faction = "space_marines"
	d.tags = ["marine", "ranged", "heavy"]
	d.hp = 80.0
	d.damage = 22.0
	d.attack_speed = 0.5
	d.attack_range = 320.0
	d.move_speed = 60.0
	d.priority = GameConstants.PRIORITY_HIGHEST_THREAT
	d.cost = 7
	d.rarity = GameConstants.RARITY_RARE
	# TODO: свой спрайт devastator
	d.sprite_path = "res://assets/sprites/space_marine"
	d.tint = Color(0.6, 0.75, 1.0)
	return d

# Элитный танк ближнего боя
static func terminator() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Terminator"
	d.faction = "space_marines"
	d.tags = ["marine", "melee", "elite"]
	d.hp = 200.0
	d.damage = 20.0
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
	d.hp = 85.0
	d.damage = 5.0
	d.attack_speed = 0.8
	d.attack_range = 60.0
	d.move_speed = 80.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.heal_per_second = 8.0
	d.heal_radius = 150.0
	d.cost = 7
	d.rarity = GameConstants.RARITY_RARE
	# TODO: свой спрайт apothecary
	d.sprite_path = "res://assets/sprites/space_marine"
	d.tint = Color(1.0, 0.7, 0.7)
	d.sprite_scale = 0.95
	return d
