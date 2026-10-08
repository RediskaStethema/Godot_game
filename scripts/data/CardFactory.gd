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

# Веса по TDD: common ~60%, rare ~30%, epic ~10% (epic-карт пока нет).
# Здания не кладём в пул, пока их drop на тайл не реализован (BattleScene: building → pass).
static func build_pool() -> Array:
	var pool = []
	# Common — 12 копий
	for i in range(4): pool.append(tactical_squad())
	for i in range(3): pool.append(assault_squad())
	for i in range(3): pool.append(scout_squad())
	for i in range(2): pool.append(chaos_warband())
	# Rare — 6 копий
	for i in range(2): pool.append(devastator_squad())
	pool.append(terminator_squad())
	pool.append(apothecary_card())
	pool.append(blessed_armour())
	pool.append(battle_fury())
	return pool
