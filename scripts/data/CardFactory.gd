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
	c.unit_count = 9   # уровень: +UnitFactory.SQUAD_GROWTH бойцов
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
	c.unit_count = 6   # уровень: +UnitFactory.SQUAD_GROWTH бойцов
	return c

static func scout_squad() -> CardData:
	var c = CardData.new()
	c.id = "scout_squad"
	c.title = "Scout Squad"
	c.description = "Снайперы: бьют дальше всех, но хрупкие; добивают раненых"
	c.faction = "space_marines"
	c.cost = 4
	c.rarity = "common"
	c.card_type = "squad"
	c.unit_factory_id = "scout_marine"
	c.unit_count = 9   # уровень: +UnitFactory.SQUAD_GROWTH бойцов
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
	c.unit_count = 6   # уровень: +UnitFactory.SQUAD_GROWTH бойцов
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
	c.unit_count = 6   # уровень: +UnitFactory.SQUAD_GROWTH бойцов
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
	c.unit_count = 2   # пара: уровень +UnitFactory.PAIR_GROWTH бойца
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
	c.unit_count = 2   # пара: уровень +UnitFactory.PAIR_GROWTH бойца
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
	c.unit_count = 2   # пара: уровень +UnitFactory.PAIR_GROWTH бойца
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
	c.unit_count = 2   # пара: уровень +UnitFactory.PAIR_GROWTH бойца
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
	c.unit_count = 2   # пара: уровень +UnitFactory.PAIR_GROWTH бойца
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
	c.unit_count = 2   # пара: уровень +UnitFactory.PAIR_GROWTH бойца
	return c

# -------------------------------------------------------
# КАРТЫ ЗДАНИЙ (building)
# -------------------------------------------------------

static func bolter_turret() -> CardData:
	var c = CardData.new()
	c.id = "bolter_turret"
	c.title = "Bolter Turret"
	c.description = "Турель: стреляет в ближайшего врага на всём поле. Стоит между раундами."
	c.faction = "space_marines"
	c.cost = 7   # в TDD турели нет — Rare по шкале цен TDD
	c.rarity = "rare"
	c.card_type = "building"
	c.building_type = "tower"
	c.building_stats = {
		"damage": 15.0,
		"attack_speed": 1.5,
		# attack_range нет — бьёт на всё поле (решение пользователя; было 300 px)
	}
	# Уровень (такая же карта на турель): +25% урона, +20% скорострельности
	c.building_level_bonuses = {"damage": 0.25, "attack_speed": 0.20}
	return c

# Орудие под управлением игрока (решение пользователя, как в 9 Kings): в бою клик
# по полю — снаряд из здания, взрыв по площади только по врагам, затем перезарядка.
static func thunderfire_cannon() -> CardData:
	var c = CardData.new()
	c.id = "thunderfire_cannon"
	c.title = "Thunderfire Cannon"
	c.description = "Орудие: в бою кликните по полю — залп по площади. Перезарядка 4 с."
	c.faction = "space_marines"
	c.cost = 8
	c.rarity = "rare"
	c.card_type = "building"
	c.building_type = "artillery"
	c.building_stats = {
		"damage": 40.0,          # каждому врагу в радиусе взрыва
		"splash_radius": 60.0,
		"cooldown": 4.0,         # сек между залпами (решение пользователя: было 10)
	}
	# Уровень (такая же карта на орудие): +25% урона, перезарядка −15%
	c.building_level_bonuses = {"damage": 0.25, "cooldown": -0.15}
	return c

# Казармы (решение пользователя): после каждого выигранного боя возвращают погибших бойцов
# отрядам на соседних клетках — по сторонам клетки, не по диагонали (BattleManager.refill_from_barracks).
# Не лечат: живые бойцы остаются с тем HP, что есть; новые — с полным HP, не больше состава отряда
static func barracks() -> CardData:
	var c = CardData.new()
	c.id = "barracks"
	c.title = "Barracks"
	c.description = "После победы возвращают павших (2 / 3 / 4 по уровню) отрядам на соседних клетках по сторонам. Не лечат."
	c.faction = "space_marines"
	c.cost = 7
	c.rarity = "common"   # решение пользователя 15.10.2026: Common, 3 копии в пуле — выпадает чаще; цена прежняя
	c.card_type = "building"
	c.building_type = "barracks"
	c.building_stats = {"refill": 2.0}   # бойцов каждому соседнему отряду за ход
	# Уровень: 2 → 3 → 4 бойца (2 × 1.5^(ур − 1), дробь вниз: 2, 3, 4.5 → 4)
	c.building_level_bonuses = {"refill": 0.5}
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

# TDD: «+2 Req/волна» (Rare 7–10). Доход после каждого боя, при любом итоге
static func plasma_generatorium() -> CardData:
	var c = CardData.new()
	c.id = "plasma_generatorium"
	c.title = "Plasma Generatorium"
	c.description = "+2 Req после каждого боя. Стоит между раундами."
	c.faction = "space_marines"
	c.cost = 8
	c.rarity = "rare"
	c.card_type = "building"
	c.building_type = "generator"
	c.building_stats = {"income": 2.0}
	# Уровень: +50% дохода (2 → 3 → 4.5 ≈ 5)
	c.building_level_bonuses = {"income": 0.50}
	return c

# TDD: «Reanimation 15%». Павший рядом боец игрока встаёт с 30% HP (раз за бой)
static func apothecarion() -> CardData:
	var c = CardData.new()
	c.id = "apothecarion"
	c.title = "Apothecarion"
	c.description = "Павший рядом боец встаёт с 30% HP (шанс 15%, раз за бой)."
	c.faction = "space_marines"
	c.cost = 8
	c.rarity = "rare"
	c.card_type = "building"
	c.building_type = "apothecarion"
	c.building_stats = {"revive_chance": 0.15, "revive_radius": 260.0, "revive_hp": 0.3}
	# Уровень: +33% шанса (15% → 20% → 26.6%)
	c.building_level_bonuses = {"revive_chance": 0.33}
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
# ХАОС ИГРОКА (решение пользователя 16.10.2026: 8 отрядов + общие карты под названиями Хаоса)
# -------------------------------------------------------
# Отряды — юниты Хаоса (UnitFactory); цены — паритет силы отряда за Req с Космодесантом.
# Цифры — на одобрение
static func _chaos_squad(id: String, title: String, desc: String, cost: int, rarity: String,
		unit: String, count: int) -> CardData:
	var c = CardData.new()
	c.id = id
	c.title = title
	c.description = desc
	c.faction = "chaos"
	c.cost = cost
	c.rarity = rarity
	c.card_type = "squad"
	c.unit_factory_id = unit
	c.unit_count = count
	return c

static func chaos_marines() -> CardData:
	return _chaos_squad("chaos_marines", "Chaos Marines", "Предатели с болтерами: бьют сильнее Tactical, но ближе",
		5, "common", "chaos_marine", 9)

static func cultists() -> CardData:
	return _chaos_squad("cultists", "Cultists", "Дешёвая толпа фанатиков со стабберами", 3, "common", "chaos_cultist", 12)

static func raptors() -> CardData:
	return _chaos_squad("raptors", "Raptors", "Прыжковые ранцы: быстро летят к стрелкам врага", 5, "common", "chaos_raptor", 6)

static func havocs() -> CardData:
	return _chaos_squad("havocs", "Havocs", "Тяжёлые огнемёты: бьют самых опасных, поджигают", 7, "rare", "chaos_havoc", 6)

static func plague_marines() -> CardData:
	return _chaos_squad("plague_marines", "Plague Marines", "Живучие носители чумы: удар отравляет", 7, "rare", "plague_marine", 6)

static func chaos_champions() -> CardData:
	return _chaos_squad("chaos_champions", "Chaos Champions", "Пара избранных бойцов ближнего боя", 7, "rare", "chaos_champion", 2)

static func hellbrute_card() -> CardData:
	return _chaos_squad("hellbrute", "Hellbrute", "Безумная машина: удар отбрасывает врага", 14, "epic", "hellbrute", 2)

static func chaos_lord_card() -> CardData:
	return _chaos_squad("chaos_lord", "Chaos Lord", "Командир: +15% урона всей армии", 16, "epic", "chaos_lord_player", 2)

# Общие карты (здания, улучшения, события) — механика Космодесанта, свои id и названия:
# id Космодесанта → [id, название, описание]. Улучшения — на свои отряды (тег chaos)
const CHAOS_RESKINS = {
	"bolter_turret": ["heretic_autocannon", "Heretic Autocannon", "Турель: стреляет в ближайшего врага на всём поле. Стоит между раундами."],
	"thunderfire_cannon": ["hellfire_mortar", "Hellfire Mortar", "Орудие: в бою кликните по полю — залп по площади. Перезарядка 4 с."],
	"barracks": ["cult_shrine", "Cult Shrine", "После победы возвращают павших (2 / 3 / 4 по уровню) отрядам на соседних клетках по сторонам. Не лечат."],
	"fortress_wall": ["spiked_barricade", "Spiked Barricade", "Щит цитадели +200 в каждом бою. Замедляет врагов рядом на 40%."],
	"plasma_generatorium": ["dark_altar", "Dark Altar", "+2 Req после каждого боя. Стоит между раундами."],
	"apothecarion": ["warp_rift", "Warp Rift", "Павший рядом боец встаёт с 30% HP (шанс 15%, раз за бой)."],
	"blessed_armour": ["daemonic_armour", "Daemonic Armour", "Отряд Хаоса: +25% HP"],
	"battle_fury": ["blood_rage", "Blood Rage", "Отряд Хаоса: +20% урона"],
	"iron_halo": ["warp_ward", "Warp Ward", "Отряд Хаоса: щит 30% HP каждому бойцу в начале боя"],
	"combat_stimms": ["combat_drugs", "Combat Drugs", "Отряд Хаоса: +20% скорости бега и атаки"],
	"chapter_banner": ["icon_of_chaos", "Icon of Chaos", "Икона отряду: союзники рядом +15% урона (не суммируется с аурами)"],
	"emergency_reinforcements": ["cult_uprising", "Cult Uprising", "Случайный Common отряд на пустую клетку"],
	"orbital_strike": ["warp_strike", "Warp Strike", "В начале боя: 160 урона всем врагам в радиусе 130 — по самой плотной группе"],
}
# Отряд Космодесанта → отряд Хаоса той же роли (стартовая карта мета-прогрессии в забеге за Хаос)
const CHAOS_SQUAD_EQUIVALENTS = {
	"tactical_squad": "chaos_marines", "assault_squad": "raptors", "scout_squad": "cultists",
	"devastator_squad": "havocs", "terminator_squad": "plague_marines", "apothecary": "chaos_champions",
	"librarian": "chaos_champions", "chaplain": "chaos_champions", "land_speeder": "raptors",
	"dreadnought": "hellbrute", "chapter_master": "chaos_lord",
}

static func _chaos_version(card: CardData) -> CardData:
	var r: Array = CHAOS_RESKINS[card.id]
	card.id = r[0]
	card.title = r[1]
	card.description = r[2]
	card.faction = "chaos"
	if card.affects_tag == "marine":
		card.affects_tag = "chaos"
	return card

# id карты Космодесанта, от которой сделана карта Хаоса (мета-прогрессия открывает обе); своя — как есть
static func base_id(id: String) -> String:
	for sm_id in CHAOS_RESKINS:
		if CHAOS_RESKINS[sm_id][0] == id:
			return sm_id
	return id

# Карта расы faction вместо карты Космодесанта id (стартовая карта); нет пары — сама карта
static func equivalent(id: String, faction: String) -> CardData:
	if faction == "chaos":
		if CHAOS_RESKINS.has(id):
			id = CHAOS_RESKINS[id][0]
		else:
			id = CHAOS_SQUAD_EQUIVALENTS.get(id, id)
	return create(id)

# -------------------------------------------------------
# ПУЛ КАРТ ДЛЯ МАГАЗИНА
# -------------------------------------------------------
# ShopManager будет брать карты отсюда.
# Карты с большим весом появляются чаще.

# Расы с картами игрока (build_pool)
const FACTIONS = ["space_marines", "chaos"]

# Веса по TDD ~60/30/10: common 26, rare 15, epic 4 — из 45 копий.
# Новая карта по id (сохранения). Все карты игрока есть в пуле магазина своей расы; id у рас
# разные — карта находится при любой текущей расе (сохранение грузит руку раньше расы)
static func create(id: String) -> CardData:
	for faction in FACTIONS:
		for card in build_pool(faction):
			if card.id == id:
				return card
	push_warning("CardFactory: неизвестная карта '%s'" % id)
	return null

# Случайная карта отряда нужной редкости из пула расы забега (веса копий) — Emergency Reinforcements
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

# Раса забега (RunManager.player_faction). Через дерево, не по имени автолоада: CardFactory берут
# тестовые скрипты, а они компилируются раньше автолоадов
static func run_faction() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var rm: Node = tree.root.get_node_or_null("RunManager") if tree else null
	return rm.player_faction if rm else "space_marines"

# Пул магазина расы faction ("" — раса забега RunManager.player_faction)
static func build_pool(faction: String = "") -> Array:
	if faction == "":
		faction = run_faction()
	if faction == "chaos":
		return _chaos_pool()
	var pool = []
	# Common — 27 копий: доли ~60/30/10 держатся — на 6 новых Rare базовых отрядов по +1 (на одобрение цифр)
	# Враги (chaos_*) в пул игрока не входят
	for i in range(8): pool.append(tactical_squad())
	for i in range(6): pool.append(assault_squad())
	for i in range(5): pool.append(scout_squad())
	for i in range(2): pool.append(fortress_wall())
	for i in range(3): pool.append(barracks())
	for i in range(3): pool.append(emergency_reinforcements())
	# Rare — 16 копий (по одной; MVP: Iron Halo, Combat Stimms, Chapter Banner, Orbital Strike,
	# здания TDD: Plasma Generatorium, Apothecarion)
	pool.append(devastator_squad())
	pool.append(terminator_squad())
	pool.append(apothecary_card())
	pool.append(librarian_card())
	pool.append(chaplain_card())
	pool.append(land_speeder_card())
	pool.append(bolter_turret())
	pool.append(thunderfire_cannon())
	pool.append(blessed_armour())
	pool.append(battle_fury())
	pool.append(iron_halo())
	pool.append(combat_stimms())
	pool.append(chapter_banner())
	pool.append(orbital_strike())
	pool.append(plasma_generatorium())
	pool.append(apothecarion())
	# Epic — 4 копии
	for i in range(2): pool.append(dreadnought_card())
	for i in range(2): pool.append(chapter_master_card())
	return pool

# Хаос: те же доли ~60/30/10 (27 / 16 / 4): Common — 3 отряда (как у Космодесанта), Rare — 3 отряда
# по 2 копии вместо 6 по одной; общие карты — тем же числом копий
static func _chaos_pool() -> Array:
	var pool = []
	for i in range(8): pool.append(chaos_marines())
	for i in range(6): pool.append(cultists())
	for i in range(5): pool.append(raptors())
	for i in range(2): pool.append(havocs())
	for i in range(2): pool.append(plague_marines())
	for i in range(2): pool.append(chaos_champions())
	for i in range(2): pool.append(hellbrute_card())
	for i in range(2): pool.append(chaos_lord_card())
	for card in build_pool("space_marines"):
		if card.card_type != "squad":
			pool.append(_chaos_version(card))
	return pool
