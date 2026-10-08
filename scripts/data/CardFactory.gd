class_name CardFactory
extends RefCounted

# -------------------------------------------------------
# КАРТЫ ОТРЯДОВ (squad)
# -------------------------------------------------------
# Каждая функция возвращает готовую CardData.
# Позже заменим на загрузку из JSON —
# но сейчас важно быстро получить рабочий магазин.

static func tactical_squad() -> CardData:
	var c = CardData.new()
	c.id = "tactical_squad"
	c.title = "Tactical Squad"
	c.description = "Надёжные бойцы линии фронта"
	c.faction = "space_marines"
	c.cost = 5
	c.rarity = "common"
	c.card_type = "squad"
	c.unit_factory_id = "tactical_marine"
	c.unit_count = 3
	return c

static func assault_squad() -> CardData:
	var c = CardData.new()
	c.id = "assault_squad"
	c.title = "Assault Squad"
	c.description = "Быстрые бойцы ближнего боя"
	c.faction = "space_marines"
	c.cost = 5
	c.rarity = "common"
	c.card_type = "squad"
	c.unit_factory_id = "assault_marine"
	c.unit_count = 2
	return c

static func chaos_warband() -> CardData:
	var c = CardData.new()
	c.id = "chaos_warband"
	c.title = "Chaos Warband"
	c.description = "Берсерки Хаоса жаждут крови"
	c.faction = "chaos"
	c.cost = 5
	c.rarity = "common"
	c.card_type = "squad"
	c.unit_factory_id = "chaos_marine"
	c.unit_count = 4
	return c

static func scout_squad() -> CardData:
	var c = CardData.new()
	c.id = "scout_squad"
	c.title = "Scout Squad"
	c.description = "Быстрые стрелки, добивают раненых"
	c.faction = "space_marines"
	c.cost = 3
	c.rarity = "common"
	c.card_type = "squad"
	c.unit_factory_id = "scout_marine"
	c.unit_count = 4
	return c

static func devastator_squad() -> CardData:
	var c = CardData.new()
	c.id = "devastator_squad"
	c.title = "Devastator Squad"
	c.description = "Тяжёлое оружие: огромная дальность, бьют самых опасных"
	c.faction = "space_marines"
	c.cost = 7
	c.rarity = "rare"
	c.card_type = "squad"
	c.unit_factory_id = "devastator"
	c.unit_count = 2
	return c

static func terminator_squad() -> CardData:
	var c = CardData.new()
	c.id = "terminator_squad"
	c.title = "Terminator"
	c.description = "Элитный ветеран в тактической броне дредноута"
	c.faction = "space_marines"
	c.cost = 10
	c.rarity = "rare"
	c.card_type = "squad"
	c.unit_factory_id = "terminator"
	c.unit_count = 1
	return c

static func apothecary_card() -> CardData:
	var c = CardData.new()
	c.id = "apothecary"
	c.title = "Apothecary"
	c.description = "Лечит раненых союзников рядом"
	c.faction = "space_marines"
	c.cost = 7
	c.rarity = "rare"
	c.card_type = "squad"
	c.unit_factory_id = "apothecary"
	c.unit_count = 1
	return c

static func librarian_card() -> CardData:
	var c = CardData.new()
	c.id = "librarian"
	c.title = "Librarian"
	c.description = "Псайкер: после каста удар оглушает цель на 1 с"
	c.faction = "space_marines"
	c.cost = 10
	c.rarity = "rare"
	c.card_type = "squad"
	c.unit_factory_id = "librarian"
	c.unit_count = 1
	return c

static func chaplain_card() -> CardData:
	var c = CardData.new()
	c.id = "chaplain"
	c.title = "Chaplain"
	c.description = "Аура: союзники ближнего боя рядом +15% урона"
	c.faction = "space_marines"
	c.cost = 8
	c.rarity = "rare"
	c.card_type = "squad"
	c.unit_factory_id = "chaplain"
	c.unit_count = 1
	return c

static func land_speeder_card() -> CardData:
	var c = CardData.new()
	c.id = "land_speeder"
	c.title = "Land Speeder"
	c.description = "Быстрая техника: налетает на дальний тыл врага"
	c.faction = "space_marines"
	c.cost = 9
	c.rarity = "rare"
	c.card_type = "squad"
	c.unit_factory_id = "land_speeder"
	c.unit_count = 1
	return c

static func dreadnought_card() -> CardData:
	var c = CardData.new()
	c.id = "dreadnought"
	c.title = "Dreadnought"
	c.description = "Шагающая машина: удар отбрасывает врага"
	c.faction = "space_marines"
	c.cost = 14
	c.rarity = "epic"
	c.card_type = "squad"
	c.unit_factory_id = "dreadnought"
	c.unit_count = 1
	return c

static func chapter_master_card() -> CardData:
	var c = CardData.new()
	c.id = "chapter_master"
	c.title = "Chapter Master"
	c.description = "Командир: +10% урона всей армии"
	c.faction = "space_marines"
	c.cost = 16
	c.rarity = "epic"
	c.card_type = "squad"
	c.unit_factory_id = "chapter_master"
	c.unit_count = 1
	return c

# -------------------------------------------------------
# КАРТЫ ЗДАНИЙ (building)
# -------------------------------------------------------

static func bolter_turret() -> CardData:
	var c = CardData.new()
	c.id = "bolter_turret"
	c.title = "Bolter Turret"
	c.description = "Автоматическая турель. Атакует ближайшего врага."
	c.faction = "space_marines"
	c.cost = 2
	c.rarity = "rare"
	c.card_type = "building"
	c.building_type = "tower"
	c.building_stats = {
		"hp": 200.0,
		"damage": 15.0,
		"attack_speed": 1.5,
		"attack_range": 300.0
	}
	return c

static func fortress_wall() -> CardData:
	var c = CardData.new()
	c.id = "fortress_wall"
	c.title = "Fortress Wall"
	c.description = "Замедляет врагов. Принимает урон вместо цитадели."
	c.faction = "space_marines"
	c.cost = 15
	c.rarity = "common"
	c.card_type = "building"
	c.building_type = "wall"
	c.building_stats = {
		"hp": 500.0,
	}
	return c

# -------------------------------------------------------
# КАРТЫ УЛУЧШЕНИЙ (upgrade)
# -------------------------------------------------------

static func blessed_armour() -> CardData:
	var c = CardData.new()
	c.id = "blessed_armour"
	c.title = "Blessed Armour"
	c.description = "Отряд Marines: +20% HP"
	c.faction = "space_marines"
	c.cost = 10
	c.rarity = "rare"
	c.card_type = "upgrade"
	c.upgrade_type = "hp_boost"
	c.upgrade_value = 0.2
	c.affects_tag = "marine"
	return c

static func battle_fury() -> CardData:
	var c = CardData.new()
	c.id = "battle_fury"
	c.title = "Battle Fury"
	c.description = "Отряд Marines: +15% урона"
	c.faction = "space_marines"
	c.cost = 12
	c.rarity = "rare"
	c.card_type = "upgrade"
	c.upgrade_type = "damage_boost"
	c.upgrade_value = 0.15
	c.affects_tag = "marine"
	return c

# -------------------------------------------------------
# ПУЛ КАРТ ДЛЯ МАГАЗИНА
# -------------------------------------------------------
# ShopManager будет брать карты отсюда.
# Карты с большим весом появляются чаще.

# Веса по TDD: common 60% (18), rare 30% (9), epic 10% (3) — из 30 копий.
# Здания не кладём в пул, пока их drop на тайл не реализован (BattleScene: building → pass).
static func build_pool() -> Array:
	var pool = []
	# Common — 18 копий
	for i in range(6): pool.append(tactical_squad())
	for i in range(4): pool.append(assault_squad())
	for i in range(5): pool.append(scout_squad())
	for i in range(3): pool.append(chaos_warband())
	# Rare — 9 копий
	for i in range(2): pool.append(devastator_squad())
	pool.append(terminator_squad())
	pool.append(apothecary_card())
	pool.append(librarian_card())
	pool.append(chaplain_card())
	pool.append(land_speeder_card())
	pool.append(blessed_armour())
	pool.append(battle_fury())
	# Epic — 3 копии
	for i in range(2): pool.append(dreadnought_card())
	pool.append(chapter_master_card())
	return pool
