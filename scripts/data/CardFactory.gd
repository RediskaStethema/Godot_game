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

static func scout_squad() -> CardData:
	var c = CardData.new()
	c.id = "scout_squad"
	c.title = "Scout Squad"
	c.description = "Быстрые стрелки, добивают раненых"
	c.faction = "space_marines"
	c.cost = 4
	c.rarity = "common"
	c.card_type = "squad"
	c.unit_factory_id = "scout_marine"
	c.unit_count = 3
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
	c.unit_count = 2
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
	c.description = "Аура: союзники ближнего боя рядом +20% урона"
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
	c.description = "Командир: +15% урона всей армии"
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
	c.description = "Турель: стреляет в ближайшего врага. Стоит между раундами."
	c.faction = "space_marines"
	c.cost = 7   # в TDD турели нет — Rare по шкале цен TDD
	c.rarity = "rare"
	c.card_type = "building"
	c.building_type = "tower"
	c.building_stats = {
		"damage": 15.0,
		"attack_speed": 1.5,
		"attack_range": 300.0,
	}
	# Уровень (такая же карта на турель): +25% урона, +20% скорострельности
	c.building_level_bonuses = {"damage": 0.25, "attack_speed": 0.20}
	return c

static func fortress_wall() -> CardData:
	var c = CardData.new()
	c.id = "fortress_wall"
	c.title = "Fortress Wall"
	c.description = "Щит цитадели +200 в каждом бою. Замедляет врагов рядом на 40%."
	c.faction = "space_marines"
	c.cost = 5   # TDD: Common 3–5
	c.rarity = "common"
	c.card_type = "building"
	c.building_type = "wall"
	# TDD: «+20 HP базе» при базе 100 → у нас 20% от HP цитадели (1000), щитом на каждый бой
	c.building_stats = {
		"shield": 200.0,
		"slow_mult": 0.6,
		"slow_radius": 130.0,
	}
	# Уровень (такая же карта на стену): +50% щита, +20% радиуса замедления
	c.building_level_bonuses = {"shield": 0.50, "slow_radius": 0.20}
	return c

# -------------------------------------------------------
# КАРТЫ УЛУЧШЕНИЙ (upgrade)
# -------------------------------------------------------

static func blessed_armour() -> CardData:
	var c = CardData.new()
	c.id = "blessed_armour"
	c.title = "Blessed Armour"
	c.description = "Отряд Marines: +25% HP"
	c.faction = "space_marines"
	c.cost = 7
	c.rarity = "rare"
	c.card_type = "upgrade"
	c.upgrade_type = "hp_boost"
	c.upgrade_value = 0.25
	c.affects_tag = "marine"
	return c

static func battle_fury() -> CardData:
	var c = CardData.new()
	c.id = "battle_fury"
	c.title = "Battle Fury"
	c.description = "Отряд Marines: +20% урона"
	c.faction = "space_marines"
	c.cost = 7
	c.rarity = "rare"
	c.card_type = "upgrade"
	c.upgrade_type = "damage_boost"
	c.upgrade_value = 0.20
	c.affects_tag = "marine"
	return c

static func iron_halo() -> CardData:
	var c = CardData.new()
	c.id = "iron_halo"
	c.title = "Iron Halo"
	c.description = "Отряд Marines: щит 30% HP каждому бойцу в начале боя"
	c.faction = "space_marines"
	c.cost = 7
	c.rarity = "rare"
	c.card_type = "upgrade"
	c.upgrade_type = "shield"
	c.upgrade_value = 0.30
	c.affects_tag = "marine"
	return c

static func combat_stimms() -> CardData:
	var c = CardData.new()
	c.id = "combat_stimms"
	c.title = "Combat Stimms"
	c.description = "Отряд Marines: +20% скорости бега и атаки"
	c.faction = "space_marines"
	c.cost = 7
	c.rarity = "rare"
	c.card_type = "upgrade"
	c.upgrade_type = "stimms"
	c.upgrade_value = 0.20
	c.affects_tag = "marine"
	return c

static func chapter_banner() -> CardData:
	var c = CardData.new()
	c.id = "chapter_banner"
	c.title = "Chapter Banner"
	c.description = "Знамя отряду: союзники рядом +15% урона (не суммируется с аурами)"
	c.faction = "space_marines"
	c.cost = 7
	c.rarity = "rare"
	c.card_type = "upgrade"
	c.upgrade_type = "banner"
	c.upgrade_value = 0.15
	c.affects_tag = "marine"
	return c

# -------------------------------------------------------
# КАРТЫ СОБЫТИЙ (event)
# -------------------------------------------------------

# Случайный Common отряд полным составом (RunManager.rng) — дешевле любого из них
static func emergency_reinforcements() -> CardData:
	var c = CardData.new()
	c.id = "emergency_reinforcements"
	c.title = "Emergency Reinforcements"
	c.description = "Случайный Common отряд на пустую клетку"
	c.faction = "space_marines"
	c.cost = 3
	c.rarity = "common"
	c.card_type = "event"
	c.event_type = "reinforcements"
	c.event_stats = {"rarity": "common"}
	return c

# Заряжается на расстановке, бьёт в начале боя по самому плотному скоплению врагов
# (враги до боя скрыты — целиться вслепую незачем)
static func orbital_strike() -> CardData:
	var c = CardData.new()
	c.id = "orbital_strike"
	c.title = "Orbital Strike"
	c.description = "В начале боя: 160 урона всем врагам в радиусе 130 — по самой плотной группе"
	c.faction = "space_marines"
	c.cost = 7
	c.rarity = "rare"
	c.card_type = "event"
	c.event_type = "orbital_strike"
	c.event_stats = {"damage": 160.0, "radius": 130.0}
	return c

# -------------------------------------------------------
# ПУЛ КАРТ ДЛЯ МАГАЗИНА
# -------------------------------------------------------
# ShopManager будет брать карты отсюда.
# Карты с большим весом появляются чаще.

# Веса по TDD ~60/30/10: common 24, rare 13, epic 4 — из 41 копии.
# Новая карта по id (сохранения). Все карты игрока есть в пуле магазина.
static func create(id: String) -> CardData:
	for card in build_pool():
		if card.id == id:
			return card
	push_warning("CardFactory: неизвестная карта '%s'" % id)
	return null

# Случайная карта отряда нужной редкости из пула (веса копий) — Emergency Reinforcements
static func random_squad_card(rarity: String, rng: RandomNumberGenerator) -> CardData:
	var squads = build_pool().filter(func(c): return c.card_type == "squad" and c.rarity == rarity)
	return squads[rng.randi_range(0, squads.size() - 1)]

# id карт (сохранения) и обратно
static func ids_of(cards: Array) -> Array:
	var ids: Array = []
	for c in cards:
		ids.append(c.id)
	return ids

static func create_many(ids: Array) -> Array[CardData]:
	var cards: Array[CardData] = []
	for id in ids:
		var c = create(str(id))
		if c:
			cards.append(c)
	return cards

static func build_pool() -> Array:
	var pool = []
	# Common — 24 копии
	# Враги (chaos_*) в пул игрока не входят
	for i in range(8): pool.append(tactical_squad())
	for i in range(6): pool.append(assault_squad())
	for i in range(5): pool.append(scout_squad())
	for i in range(2): pool.append(fortress_wall())
	for i in range(3): pool.append(emergency_reinforcements())
	# Rare — 13 копий
	pool.append(devastator_squad())
	pool.append(terminator_squad())
	pool.append(apothecary_card())
	pool.append(librarian_card())
	pool.append(chaplain_card())
	pool.append(land_speeder_card())
	pool.append(bolter_turret())
	pool.append(blessed_armour())
	pool.append(battle_fury())
	pool.append(iron_halo())
	pool.append(combat_stimms())
	pool.append(chapter_banner())
	pool.append(orbital_strike())
	# Epic — 4 копии
	for i in range(2): pool.append(dreadnought_card())
	for i in range(2): pool.append(chapter_master_card())
	return pool
