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
		"heal": 0.30,           # и лечение: 30% максимального HP каждому бойцу, павшие возвращаются (решение пользователя 21.10.2026)
	},
	# Хаос игрока — пока те же цифры, что у Космодесанта (на одобрение)
	"chaos": {"damage": 0.20, "hp": 0.20, "attack_speed": 0.15, "heal": 0.30},
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
# Герои и техника игрока (решение пользователя: отрядов из одного бойца нет) — парами: HP, урон и
# лечение бойца ÷PAIR_SPLIT, отряд 1-го уровня по силе как прежний одиночка; уровень +PAIR_GROWTH
# бойца: 2 → 3 → 4 → 5. Ауры, командир и клич не складываются — у пары как у одного; оглушение и
# отбрасывание за удар ÷PAIR_SPLIT (ударов вдвое больше).
# Враги-одиночки (Hellbrute, Chaos Lord) остаются одиночками, чемпионы Хаоса и так парами (EnemyWaves)
const PAIR_SPLIT: int = 2
const PAIR_GROWTH: int = 1
# Космодесант в силовой броне и техника — на ARMOUR_SCALE крупнее (решение пользователя); люди
# (Scout, культисты) — прежнего роста
const ARMOUR_SCALE: float = 1.1
const UNIT_SCALE: float = 0.8   # все бойцы, кроме примархов (решение пользователя 11.11.2026: «уменьши модельки на 20%»)
# Дальность ближнего боя — ноги к ногам, px (решение пользователя 21.10.2026: при 60 бойцы ростом 31 px
# били через пустоту — «стоят слишком далеко»). Крупные модели (Champion, Дредноут, Hellbrute, Chaos Lord) — дальше
const MELEE_RANGE: float = 30.0

# Бойцы богов Хаоса в чужом отряде (Святилище культа, решение пользователя 21.10.2026): павший боец соседнего
# отряда встаёт бойцом отряда бога, сила — по редкости отряда, в который он встал
const CONVERT_RARITY_MULT = {"common": 0.7, "rare": 1.0, "epic": 1.3}
static var _convert_cache: Dictionary = {}   # kind → UnitData (шаблон, общий для всех таких бойцов)

static func convert_kind(god_factory_id: String, host_rarity: String) -> String:
	return "%s:%s" % [god_factory_id, host_rarity]

static func convert_fighter(kind: String) -> UnitData:
	if not _convert_cache.has(kind):
		var parts := kind.split(":")
		var d := create(parts[0])
		var k: float = CONVERT_RARITY_MULT.get(parts[1] if parts.size() > 1 else "rare", 1.0)
		d.hp_multiplier = k
		d.damage_multiplier = k
		_convert_cache[kind] = d
	return _convert_cache[kind]

# Бойцов за уровень у отряда карты: пехота — SQUAD_GROWTH, пары — PAIR_GROWTH
static func squad_growth_for(card: CardData) -> int:
	if card.unit_factory_id in SPLIT_UNITS:
		return SQUAD_GROWTH
	if card.unit_factory_id in PAIR_UNITS or card.unit_factory_id in PAIR_GROWTH_UNITS:
		return PAIR_GROWTH
	return 0
const SPLIT_UNITS = ["tactical_marine", "assault_marine", "scout_marine", "devastator", "terminator",
	"chaos_marine", "chaos_cultist", "chaos_havoc", "chaos_raptor", "plague_marine",
	"sanguinary_guard", "firedrakes", "khorne_berzerkers", "plaguebearers", "rubric_marines", "noise_marines"]
const PAIR_UNITS = ["apothecary", "librarian", "chaplain", "land_speeder", "dreadnought", "chapter_master",
	"hellbrute", "chaos_lord_player", "honour_guard", "centurion_devastators", "thunderwolf_cavalry"]
# Пары без деления статов: Chaos Champion — враг-элита и так парами с полными статами (EnemyWaves),
# у игрока та же пара растёт на PAIR_GROWTH бойца за уровень
const PAIR_GROWTH_UNITS = ["chaos_champion"]
const ARMOURED_UNITS = ["tactical_marine", "assault_marine", "devastator", "terminator",
	"apothecary", "librarian", "chaplain", "land_speeder", "dreadnought", "chapter_master",
	"honour_guard", "sanguinary_guard", "centurion_devastators", "thunderwolf_cavalry", "firedrakes"]

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
		# Хаос игрока (решение пользователя 16.10.2026): герои-пары по статам техники и командира Космодесанта
		"hellbrute":         d = hellbrute()
		"chaos_lord_player": d = chaos_lord_player()
		# Космодесант-враг (забег за Хаос): элита и боссы по статам Champion / Hellbrute / Chaos Lord
		"veteran_terminator":  d = veteran_terminator()
		"dreadnought_boss":    d = dreadnought_boss()
		"chapter_master_boss": d = chapter_master_boss()
		# Финальные боссы — примархи (решение пользователя 09.11.2026): EnemyWaves.BOSS / SM_BOSS "units"
		"daemon_angron":       d = daemon_angron()
		"daemon_mortarion":    d = daemon_mortarion()
		"daemon_magnus":       d = daemon_magnus()
		"daemon_fulgrim":      d = daemon_fulgrim()
		"primarch_guilliman":  d = primarch_guilliman()
		"primarch_sanguinius": d = primarch_sanguinius()
		"primarch_dorn":       d = primarch_dorn()
		"primarch_russ":       d = primarch_russ()
		"primarch_vulkan":     d = primarch_vulkan()
		# Особые юниты орденов и богов (решение пользователя 18.10.2026) — только в магазине своего ордена
		"honour_guard":          d = honour_guard()
		"sanguinary_guard":      d = sanguinary_guard()
		"centurion_devastators": d = centurion_devastators()
		"thunderwolf_cavalry":   d = thunderwolf_cavalry()
		"firedrakes":            d = firedrakes()
		"khorne_berzerkers":     d = khorne_berzerkers()
		"plaguebearers":         d = plaguebearers()
		"rubric_marines":        d = rubric_marines()
		"noise_marines":         d = noise_marines()
		_:
			push_warning("UnitFactory: неизвестный id '%s', создаю Crispin Plate" % factory_id)
			d = tactical_marine()
			factory_id = "tactical_marine"
	# По нему карта узнаёт «свой» отряд
	d.factory_id = factory_id
	if factory_id in SPLIT_UNITS:
		d.hp /= SQUAD_SPLIT
		d.damage /= SQUAD_SPLIT
		d.unit_weight = 1.0 / SQUAD_SPLIT
	elif factory_id in PAIR_UNITS:
		d.hp /= PAIR_SPLIT
		d.damage /= PAIR_SPLIT
		d.heal_per_second /= PAIR_SPLIT
		# Удары пары вдвое чаще — оглушение (Librarian) и отбрасывание (Dreadnought) за удар вдвое слабее
		d.on_hit_stun /= PAIR_SPLIT
		d.on_hit_knockback /= PAIR_SPLIT
		d.unit_weight = 1.0 / PAIR_SPLIT
	if factory_id in ARMOURED_UNITS:
		d.sprite_scale *= ARMOUR_SCALE
	# Все бойцы на UNIT_SCALE мельче (решение пользователя 11.11.2026); примархи (листы units/bosses) — свой рост
	# PRIMARCH_SCALE от TARGET_SPRITE_HEIGHT, не трогаются
	if not d.sprite_path.contains("/units/bosses/"):
		d.sprite_scale *= UNIT_SCALE
	return d

static func tactical_marine() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Crispin Plate"
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
	d.sprite_path = "res://assets/units/space_marines/tactical"  # лист assets/source_sheets/assetlist.png (tools/sheet_to_frames.py)
	d.projectile = "bolt"
	return d


static func assault_marine() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Arielite"
	d.faction = "space_marines"
	d.tags = ["marine", "melee", "jump"]
	d.hp = 90.0
	d.damage = 18.0
	d.attack_speed = 1.2
	d.attack_range = MELEE_RANGE
	d.move_speed = 120.0
	d.priority = GameConstants.PRIORITY_NEAREST
	# Прыжковый ранец (решение пользователя 17.10.2026): раз за бой — на вражеского стрелка, удар при
	# приземлении по площади и оглушение. Цифры — на одобрение
	d.jump_range = 320.0
	d.jump_damage_mult = 1.5
	d.jump_radius = 40.0
	d.jump_stun = 0.5
	d.cost = 5
	d.rarity = GameConstants.RARITY_COMMON
	d.sprite_path = "res://assets/units/space_marines/assault"  # лист assets/source_sheets/Assault_marine_assets.png (tools/sheet_to_frames.py)
	return d

static func chaos_marine() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Bloodsigned"
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
	d.sprite_path = "res://assets/units/chaos/marine"  # лист assets/source_sheets/chaos_marine_sheet.png (tools/prep_sheet.py + sheet_to_frames.py --counts)
	d.projectile = "chaos_bolt"
	return d

# Элита Хаоса (эскорт мини-босса): усиленный Chaos Marine ближнего боя.
static func chaos_champion() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Thane"
	d.projectile = ""   # ближний бой — без снаряда Chaos Marine
	d.tags = ["chaos", "melee", "elite"]
	d.hp = 180.0
	d.damage = 22.0
	d.attack_speed = 1.0
	d.attack_range = MELEE_RANGE * 1.15   # Champion крупнее
	d.move_speed = 80.0
	d.retreat_hp_threshold = 0.0
	d.rarity = GameConstants.RARITY_RARE
	d.sprite_path = "res://assets/units/chaos/champion"  # лист assets/source_sheets/chaos_champion_sheet.png (tools/prep_sheet.py + sheet_to_frames.py --counts)
	d.sprite_scale = 1.25
	return d

# Главный босс последней волны: Chaos Lord — один огромный боец, удар отбрасывает.
# Свой лист, ×1.8 размера. Баланс — черновой.
static func chaos_lord() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Signatory Lord"
	d.projectile = ""   # ближний бой — без снаряда Chaos Marine
	d.tags = ["chaos", "melee", "elite", "boss"]
	d.hp = 2200.0
	d.damage = 50.0
	d.attack_speed = 0.8
	d.attack_range = MELEE_RANGE * 1.35   # Chaos Lord крупнее всех
	d.move_speed = 60.0
	d.on_hit_knockback = 250.0
	d.retreat_hp_threshold = 0.0
	d.rarity = GameConstants.RARITY_EPIC
	d.sprite_path = "res://assets/units/chaos/lord"  # лист assets/source_sheets/chaos_lord_sheet.png (tools/prep_sheet.py + sheet_to_frames.py --counts)
	d.sprite_scale = 1.8
	return d

# Мини-босс каждой 5-й волны: Hellbrute — медленная машина ближнего боя,
# удар отбрасывает. Свой лист, ×1.5 размера. Баланс — черновой.
static func chaos_hellbrute() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Heath-King"
	d.projectile = ""   # ближний бой — без снаряда Chaos Marine
	d.tags = ["chaos", "melee", "vehicle", "elite"]
	d.hp = 600.0
	d.damage = 30.0
	d.attack_speed = 0.7
	d.attack_range = MELEE_RANGE * 1.25   # Hellbrute крупнее
	d.move_speed = 55.0
	d.on_hit_knockback = 150.0
	d.retreat_hp_threshold = 0.0
	d.rarity = GameConstants.RARITY_EPIC
	d.sprite_path = "res://assets/units/chaos/hellbrute"  # лист assets/source_sheets/chaos_hellbrute_sheet.png (tools/prep_sheet.py + sheet_to_frames.py --counts)
	d.sprite_scale = 1.5
	return d

# Архетипы обычных волн Хаоса (EnemyWaves.ARCHETYPES). Статы — от √(HP × DPS)
# Chaos Marine (35.5): культист 0.4 от него, рапторы 1.25, хавоки и чумные 1.5;
# сколько бойцов в отряде (EnemyWaves power) — подобрано tests/balance_sim.gd.
# У всех свои листы.

# Культисты: толпа слабых стрелков с коротким стволом
static func chaos_cultist() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Pallid Masquer"
	d.tags = ["chaos", "ranged", "light"]
	d.hp = 40.0
	d.damage = 6.0
	d.attack_speed = 0.85
	d.attack_range = 110.0
	d.move_speed = 85.0
	d.sprite_path = "res://assets/units/chaos/cultist"  # лист assets/source_sheets/Chaos_cultists.png (tools/sheet_to_frames.py)
	d.sprite_scale = 0.85
	d.blood = "red"   # люди, не десантники Хаоса
	return d

# Хавоки: тяжёлое оружие из тыла, бьют самого опасного
static func chaos_havoc() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Walpurger"
	d.tags = ["chaos", "ranged", "heavy"]
	d.hp = 130.0
	d.damage = 40.0
	d.attack_speed = 0.55
	d.attack_range = 260.0   # дальше Tactical, но в зоне орудия цитадели (260 + HIT_RADIUS < 320)
	d.move_speed = 60.0
	d.priority = GameConstants.PRIORITY_HIGHEST_THREAT
	d.projectile = "flame"   # огненная струя (Flamethrower-Sheet) — уже тёплая, без перекраски
	d.on_hit_status = StatusEffects.BURNING   # попадание поджигает, огонь перекидывается
	d.on_hit_status_power = 3.0
	d.on_hit_status_duration = 3.0
	d.sprite_path = "res://assets/units/chaos/havoc"  # лист assets/source_sheets/chaos_havoc_sheet.png (tools/prep_sheet.py + sheet_to_frames.py --counts)
	d.sprite_scale = 1.1
	return d

# Рапторы: быстрые бойцы ближнего боя, летят к стрелкам в тылу
static func chaos_raptor() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Hookwing"
	d.projectile = ""
	d.tags = ["chaos", "melee", "jump"]
	d.hp = 120.0
	d.damage = 15.0
	d.attack_speed = 0.9
	d.attack_range = MELEE_RANGE
	d.move_speed = 140.0
	d.priority = GameConstants.PRIORITY_RANGED_FIRST
	d.sprite_path = "res://assets/units/chaos/raptor"  # лист assets/source_sheets/chaos_raptor_sheet.png (tools/prep_sheet.py + sheet_to_frames.py --counts)
	return d

# Чумные десантники: медленные и живучие, урон слабый, не отступают
static func plague_marine() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Thousand-Young"
	d.projectile = ""
	d.tags = ["chaos", "melee", "heavy"]
	d.hp = 300.0
	d.damage = 12.0
	d.attack_speed = 0.8
	d.attack_range = MELEE_RANGE
	d.move_speed = 55.0
	d.retreat_hp_threshold = 0.0
	d.on_hit_status = StatusEffects.POISONED   # яд Nurgle: стак за удар
	d.on_hit_status_power = 2.0
	d.on_hit_status_duration = 4.0
	d.sprite_path = "res://assets/units/chaos/plague_marine"  # лист assets/source_sheets/Plague_Marine_assets.png (tools/sheet_to_frames.py, удар — кадр 7)
	d.sprite_scale = 1.15
	d.blood = "green"   # нурглиты
	return d

# Лёгкий стрелок: хрупкий, быстрый, добивает раненых
static func scout_marine() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Nightstrider"
	d.faction = "space_marines"
	d.tags = ["marine", "ranged", "light"]
	# Снайперы (решение пользователя): бьют дальше всех, но хрупкие; редкие сильные выстрелы —
	# урон в секунду почти прежний (было: HP 60, урон 8, 1.2/с, дальность 220)
	d.hp = 35.0
	d.damage = 20.0
	d.attack_speed = 0.5
	d.attack_range = 420.0
	d.move_speed = 110.0
	d.priority = GameConstants.PRIORITY_LOWEST_HP
	d.cost = 4
	d.rarity = GameConstants.RARITY_COMMON
	d.sprite_path = "res://assets/units/space_marines/scout"  # лист assets/source_sheets/Assets_scout.png (tools/sheet_to_frames.py)
	d.sprite_scale = 0.85
	d.projectile = "spark"
	return d

# Тяжёлое оружие: медленный, бьёт редко и больно с большой дистанции
static func devastator() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Dunsiner"
	d.faction = "space_marines"
	d.tags = ["marine", "ranged", "heavy"]
	d.hp = 200.0
	d.damage = 44.0
	d.attack_speed = 0.5
	d.attack_range = 320.0
	d.move_speed = 60.0
	d.priority = GameConstants.PRIORITY_HIGHEST_THREAT
	# Окапывание (решение пользователя 17.10.2026): стоит на месте — урон до +30% за 2 с. Цифры — на одобрение
	d.entrench_time = 2.0
	d.entrench_bonus = 0.3
	d.cost = 7
	d.rarity = GameConstants.RARITY_RARE
	d.sprite_path = "res://assets/units/space_marines/devastator"  # лист assets/source_sheets/Devastator_assets.png (tools/sheet_to_frames.py)
	d.projectile = "charged"
	return d

# Элитный танк ближнего боя
static func terminator() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Virgilian"
	d.faction = "space_marines"
	d.tags = ["marine", "melee", "elite"]
	d.hp = 320.0
	d.damage = 38.0
	d.attack_speed = 0.8
	d.attack_range = MELEE_RANGE
	d.move_speed = 55.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.retreat_hp_threshold = 0.0   # терминаторы не отступают
	# Deep Strike (решение пользователя 17.10.2026): через 1 с боя — телепорт к переднему отряду врага
	d.deep_strike_delay = 1.0
	d.cost = 10
	d.rarity = GameConstants.RARITY_RARE
	d.sprite_path = "res://assets/units/space_marines/terminator"  # лист assets/source_sheets/Terminator_assets.png (tools/sheet_to_frames.py)
	d.armor_protect = Rect2(106, 50, 20, 22)   # лицо и борода — не в цвет братства (17.11.2026)
	d.sprite_scale = 1.35
	return d

# Медик: слабо бьёт, лечит раненых союзников в радиусе
static func apothecary() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Friar-Leech"
	d.faction = "space_marines"
	d.tags = ["marine", "support", "heal"]
	d.hp = 300.0
	d.damage = 10.0
	d.attack_speed = 0.8
	d.attack_range = MELEE_RANGE
	d.move_speed = 80.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.heal_per_second = 20.0
	d.heal_radius = 150.0
	d.cost = 7
	d.rarity = GameConstants.RARITY_RARE
	d.sprite_path = "res://assets/units/space_marines/apothecary"  # лист assets/source_sheets/Apothecary_assets.png (tools/sheet_to_frames.py, + ряд лечения)
	d.armor_protect = Rect2(95, 33, 20, 24)   # лицо не в цвет братства (17.11.2026)
	d.sprite_scale = 0.95
	return d

# Псайкер: бьёт через каст (CASTING), попадание оглушает цель
static func librarian() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Armitager"
	d.faction = "space_marines"
	d.tags = ["marine", "psyker", "elite"]
	d.hp = 450.0
	d.damage = 90.0
	# 0.9: каст 0.8 с — часть перезарядки (цикл 1.1 с). Было 0.6, но вход в ATTACK после каста
	# сбрасывал перезарядку — по факту ≈ 0.86–0.95 удара/с; сила прежняя
	d.attack_speed = 0.9
	d.attack_range = 220.0
	d.move_speed = 75.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.cast_time = 0.8
	d.on_hit_stun = 1.0
	d.cost = 10
	d.rarity = GameConstants.RARITY_RARE
	d.sprite_path = "res://assets/units/space_marines/librarian"  # лист assets/source_sheets/Librarian_sheet_v2.png (07.11.2026; tools/tools.md — порядок нарезки)
	d.armor_protect = Rect2(78, 53, 24, 28)   # лицо не в цвет братства (17.11.2026)
	d.sprite_scale = 1.05
	d.projectile = "charged"
	return d

# Капеллан: боец ближнего боя, аура +урон союзным melee рядом
static func chaplain() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Bursak"
	d.faction = "space_marines"
	# Стреляет вблизи из болт-пистолета (решение пользователя по листу спрайтов; был ближний бой, 60 px)
	d.tags = ["marine", "ranged", "support"]
	d.hp = 480.0
	d.damage = 36.0
	d.attack_speed = 1.0
	d.attack_range = 140.0
	d.projectile = "bolt"
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
	d.sprite_path = "res://assets/units/space_marines/chaplain"  # лист assets/source_sheets/Chaplain_assets.png (tools/sheet_to_frames.py)
	d.armor_protect = Rect2(78, 54, 19, 24)   # лицо не в цвет братства (17.11.2026)
	d.sprite_scale = 1.05
	return d

# Скоростная техника: налетает на тыл врага, не отступает
static func land_speeder() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Wind Skiff"
	d.faction = "space_marines"
	d.tags = ["marine", "ranged", "vehicle", "fast"]
	d.hp = 380.0
	d.damage = 70.0
	d.attack_speed = 1.0
	d.attack_range = 200.0
	d.move_speed = 160.0
	d.priority = GameConstants.PRIORITY_FARTHEST
	d.retreat_hp_threshold = 0.0
	d.mobile_fire = true   # стреляет на ходу, кружит вокруг цели (решение пользователя 17.10.2026)
	d.cost = 9
	d.rarity = GameConstants.RARITY_RARE
	d.sprite_path = "res://assets/units/space_marines/land_speeder"  # лист assets/source_sheets/Landspeeder_assets.png (tools/sheet_to_frames.py)
	d.sprite_scale = 1.35   # холст листа выше машины (взрыв в смерти) — иначе выйдет мельче пехоты
	d.projectile = "bolt"
	return d

# Шагающая машина: огромный HP, удар отбрасывает цель
static func dreadnought() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Shadeking"
	d.faction = "space_marines"
	d.tags = ["marine", "vehicle", "elite"]
	d.hp = 1400.0
	d.damage = 90.0
	d.attack_speed = 0.6
	d.attack_range = MELEE_RANGE * 1.15   # Дредноут крупнее
	d.move_speed = 45.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.on_hit_knockback = 300.0
	d.retreat_hp_threshold = 0.0
	d.cost = 14
	d.rarity = GameConstants.RARITY_EPIC
	d.sprite_path = "res://assets/units/space_marines/dreadnought"  # лист assets/source_sheets/Dreadnought_assets.png (tools/sheet_to_frames.py)
	d.sprite_scale = 1.6
	return d

# Магистр ордена: +10% урона всей армии на старте боя
static func chapter_master() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Monstruwacan"
	d.faction = "space_marines"
	d.tags = ["marine", "elite", "commander"]
	d.hp = 1000.0
	d.damage = 75.0
	d.attack_speed = 1.0
	d.attack_range = MELEE_RANGE
	d.move_speed = 70.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.commander_damage_bonus = 0.15
	d.retreat_hp_threshold = 0.0
	d.cost = 16
	d.rarity = GameConstants.RARITY_EPIC
	d.sprite_path = "res://assets/units/space_marines/chapter_master"  # лист assets/source_sheets/chapter_master.png (tools/sheet_to_frames.py, + поза победы)
	d.armor_protect = Rect2(87, 61, 24, 22)   # лицо не в цвет братства (17.11.2026)
	d.sprite_scale = 1.3
	return d

# -------------------------------------------------------
# ХАОС ИГРОКА (решение пользователя 16.10.2026): отряды — те же архетипы, что у врага
# (chaos_cultist, chaos_marine, chaos_raptor, chaos_havoc, plague_marine, chaos_champion);
# Hellbrute и Chaos Lord врага — боссы-одиночки, у игрока свои пары: статы Dreadnought и
# Chapter Master (паритет HP×DPS за Req), вид — листы Hellbrute и Chaos Lord врага. Цифры — на одобрение
# -------------------------------------------------------
static func hellbrute() -> UnitData:
	var d = dreadnought()
	d.unit_name = "Heath-King"
	d.faction = "chaos"
	d.tags = ["chaos", "melee", "vehicle", "elite"]
	d.sprite_path = "res://assets/units/chaos/hellbrute"
	d.sprite_scale = 1.5
	return d

static func chaos_lord_player() -> UnitData:
	var d = chapter_master()
	d.unit_name = "Signatory Lord"
	d.faction = "chaos"
	d.tags = ["chaos", "melee", "elite", "commander"]
	d.sprite_path = "res://assets/units/chaos/lord"
	d.sprite_scale = 1.4
	return d

# -------------------------------------------------------
# КОСМОДЕСАНТ-ВРАГ (забег за Хаос): обычные волны — отряды игрока (EnemyWaves.SM_ARCHETYPES),
# элита и боссы — статы Chaos Champion / Hellbrute / Chaos Lord, вид Космодесанта:
# баланс волн тот же, что у Хаоса
# -------------------------------------------------------
static func veteran_terminator() -> UnitData:
	var d = chaos_champion()
	d.unit_name = "Virgilian Veteran"
	d.faction = "space_marines"
	d.tags = ["marine", "melee", "elite"]
	d.sprite_path = "res://assets/units/space_marines/terminator"
	d.armor_protect = Rect2(106, 50, 20, 22)   # лицо и борода — не в цвет братства (17.11.2026)
	d.projectile_warm = false
	d.tint = Color.WHITE
	d.sprite_scale = 1.5   # как Terminator игрока в броне (×ARMOUR_SCALE)
	return d

static func dreadnought_boss() -> UnitData:
	var d = chaos_hellbrute()
	d.unit_name = "Shadeking"
	d.faction = "space_marines"
	d.tags = ["marine", "melee", "vehicle", "elite"]
	d.sprite_path = "res://assets/units/space_marines/dreadnought"
	d.projectile_warm = false
	d.tint = Color.WHITE
	d.sprite_scale = 1.8
	return d

static func chapter_master_boss() -> UnitData:
	var d = chaos_lord()
	d.unit_name = "Monstruwacan"
	d.faction = "space_marines"
	d.tags = ["marine", "melee", "elite", "boss"]
	d.sprite_path = "res://assets/units/space_marines/chapter_master"
	d.armor_protect = Rect2(87, 61, 24, 22)   # лицо не в цвет братства (17.11.2026)
	d.projectile_warm = false
	d.tint = Color.WHITE
	d.sprite_scale = 1.8
	return d

# -------------------------------------------------------
# ФИНАЛЬНЫЕ БОССЫ — ПРИМАРХИ (решение пользователя 09.11.2026; арт — assets/source_sheets/bosses_pack,
# tools/boss_frames.py → assets/units/bosses/<id>). Против Космодесанта — демон-примарх, против Хаоса — лоялист,
# какой именно — от seed забега (EnemyWaves.boss_unit). Одиночка ~2.5 роста бойца (~78 px), не отступает,
# не отбрасывается; свой приём у каждого (UnitData.special_*, BossSpecial.release).
# Профили разные, но не хрупкие (решение пользователя): HP 2200–3200 против 2200 у прежнего Chaos Lord,
# быстрые — с меньшим HP, медленные — живучие. Статы — до множителя волны 15 (×2.4). Цифры — на одобрение
# -------------------------------------------------------
const PRIMARCH_SCALE: float = 2.5
const PRIMARCH_REACH: float = MELEE_RANGE * 1.6

static func _primarch(id: String, unit_name: String, faction: String, hp: float, damage: float, attack_speed: float,
		move_speed: float) -> UnitData:
	var d = chaos_lord()
	d.unit_name = unit_name
	d.faction = faction
	d.tags = (["chaos"] if faction == "chaos" else ["marine"]) + ["melee", "elite", "boss"]
	d.hp = hp
	d.damage = damage
	d.attack_speed = attack_speed
	d.move_speed = move_speed
	d.attack_range = PRIMARCH_REACH
	d.on_hit_knockback = 180.0
	d.knockback_immune = true
	d.special_first = 2.5
	d.projectile_warm = false
	d.tint = Color.WHITE
	d.sprite_path = "res://assets/units/bosses/" + id
	d.sprite_scale = PRIMARCH_SCALE
	return d

# Ангрон (Кипящий): быстрый и яростный — прыжок на стрелков, удар по кругу с оглушением
static func daemon_angron() -> UnitData:
	var d = _primarch("daemon_angron", "Coriol", "chaos", 2200.0, 62.0, 0.9, 72.0)
	d.special_name = "Прыжок ярости"
	d.special_kind = "leap"
	d.special_cooldown = 7.0
	d.special_range = 240.0
	d.special_radius = 70.0
	d.special_mult = 1.6
	d.special_stun = 0.6
	d.special_color = Palette.BLOOD
	return d

# Мортарион (Дедушка Тысячи): медленный и самый живучий из демонов — чумное облако конусом
static func daemon_mortarion() -> UnitData:
	var d = _primarch("daemon_mortarion", "Morviy", "chaos", 3000.0, 44.0, 0.7, 48.0)
	d.special_name = "Чумное дыхание"
	d.special_kind = "cone"
	d.special_cooldown = 6.0
	d.special_radius = 120.0
	d.special_mult = 1.0
	d.special_status = StatusEffects.POISONED
	d.special_status_power = 5.0
	d.special_status_duration = 5.0
	d.special_color = Palette.POISON
	return d

# Магнус Красный (Вестник): колдун — сгусток варпа издалека, взрыв с поджогом
static func daemon_magnus() -> UnitData:
	var d = _primarch("daemon_magnus", "Faustin the Crimson", "chaos", 2300.0, 48.0, 0.8, 55.0)
	d.special_name = "Пламя варпа"
	d.special_kind = "bolt"
	d.special_projectile = "warp_bolt"
	d.special_cooldown = 5.0
	d.special_range = 260.0
	d.special_radius = 75.0
	d.special_mult = 2.2
	d.special_status = StatusEffects.BURNING
	d.special_status_power = 5.0
	d.special_status_duration = 4.0
	d.special_color = Palette.WARP_EMBER
	d.on_hit_knockback = 150.0
	return d

# Фулгрим (Король Второго Акта): быстрый, частые удары без отброса — вихрь клинков замедляет всех вокруг
static func daemon_fulgrim() -> UnitData:
	var d = _primarch("daemon_fulgrim", "Geryonis", "chaos", 2400.0, 36.0, 1.4, 85.0)
	d.special_name = "Вихрь клинков"
	d.special_kind = "nova"
	d.special_cooldown = 5.0
	d.special_radius = 80.0
	d.special_mult = 1.3
	d.special_status = StatusEffects.SLOWED
	d.special_status_power = 0.4
	d.special_status_duration = 3.0
	d.special_color = Palette.SLAANESH
	d.on_hit_knockback = 0.0
	return d

# Робаут Жиллиман (Ультрамарины): ровный и стойкий — огненная дуга мечом перед собой
static func primarch_guilliman() -> UnitData:
	var d = _primarch("primarch_guilliman", "Wilhelm the Lexicarch", "space_marines", 2700.0, 54.0, 0.8, 60.0)
	d.special_name = "Пылающий клинок"
	d.special_kind = "cone"
	d.special_cooldown = 6.0
	d.special_radius = 110.0
	d.special_mult = 1.5
	d.special_status = StatusEffects.BURNING
	d.special_status_power = 5.0
	d.special_status_duration = 3.0
	d.special_color = Palette.FIRE
	return d

# Сангвиний (Кровавые Ангелы): быстрый — пикирует с крыльев на стрелков издалека
static func primarch_sanguinius() -> UnitData:
	var d = _primarch("primarch_sanguinius", "Ugolinus the Winged", "space_marines", 2300.0, 56.0, 1.0, 82.0)
	d.special_name = "Пикирование"
	d.special_kind = "leap"
	d.special_cooldown = 7.0
	d.special_range = 280.0
	d.special_radius = 75.0
	d.special_mult = 1.5
	d.special_stun = 0.5
	d.special_color = Palette.AMBER_LIGHT
	d.on_hit_knockback = 150.0
	return d

# Рогал Дорн (Имперские Кулаки): самый живучий, медленный — удар о землю оглушает, сам под щитом
static func primarch_dorn() -> UnitData:
	var d = _primarch("primarch_dorn", "Götz Ironhand", "space_marines", 3200.0, 46.0, 0.7, 48.0)
	d.special_name = "Несокрушимая стена"
	d.special_kind = "shield"
	d.special_cooldown = 8.0
	d.special_radius = 85.0
	d.special_mult = 1.0
	d.special_stun = 0.8
	d.special_shield = 0.12
	d.special_color = Palette.AMBER_LIGHT
	return d

# Леман Русс (Космические Волки): самый быстрый — рывок с воем сквозь строй
static func primarch_russ() -> UnitData:
	var d = _primarch("primarch_russ", "The Alder King", "space_marines", 2500.0, 56.0, 1.0, 88.0)
	d.special_name = "Волчий рывок"
	d.special_kind = "dash"
	d.special_cooldown = 6.0
	d.special_range = 240.0
	d.special_radius = 40.0
	d.special_mult = 1.5
	d.special_stun = 0.4
	d.special_color = Palette.FROST
	d.on_hit_knockback = 150.0
	return d

# Вулкан (Саламандры): медленный кузнец — удар молотом, огненная волна кругом
static func primarch_vulkan() -> UnitData:
	var d = _primarch("primarch_vulkan", "Vakulan the Smith", "space_marines", 2900.0, 52.0, 0.7, 52.0)
	d.special_name = "Огненная волна"
	d.special_kind = "nova"
	d.special_cooldown = 7.0
	d.special_radius = 100.0
	d.special_mult = 1.3
	d.special_status = StatusEffects.BURNING
	d.special_status_power = 5.0
	d.special_status_duration = 3.0
	d.special_color = Palette.FORGE
	return d

# -------------------------------------------------------
# ОСОБЫЕ ЮНИТЫ ОРДЕНОВ И БОГОВ (решение пользователя 18.10.2026): Epic, только в магазине своего ордена
# (Chapters "unit_card", CardFactory.build_pool). Статы — «за одиночку», делит create() (SPLIT / PAIR_UNITS);
# способности — готовыми полями UnitData. Свои листы (19.10.2026); Космодесант — уже в цветах ордена (chapter_armor = false).
# Цифры — черновые, на одобрение
# -------------------------------------------------------
# Ultramarines — Почётная стража Виктрикс: стойкая элита, щит в начале боя
static func honour_guard() -> UnitData:
	var d = UnitData.new()
	d.unit_name = "Expounders"
	d.faction = "space_marines"
	d.tags = ["marine", "melee", "elite"]
	d.hp = 1300.0
	d.damage = 70.0
	d.attack_speed = 0.9
	d.attack_range = MELEE_RANGE
	d.move_speed = 60.0
	d.priority = GameConstants.PRIORITY_NEAREST
	d.shield_ratio = 0.25
	d.retreat_hp_threshold = 0.0
	d.cost = 15
	d.rarity = GameConstants.RARITY_EPIC
	d.sprite_path = "res://assets/units/space_marines/honour_guard"  # лист assets/source_sheets/honour_guard.png (tools/sheet_to_frames.py)
	d.tint = Color.WHITE
	d.sprite_scale = 1.15
	return d

# Blood Angels — Сангвинарная стража: прыжок на стрелков, сильный удар с оглушением
static func sanguinary_guard() -> UnitData:
	var d = assault_marine()
	d.unit_name = "Hunger Tower Guard"
	d.tags = ["marine", "melee", "jump", "elite"]
	d.hp = 400.0
	d.damage = 50.0
	d.attack_speed = 1.1
	d.move_speed = 115.0
	d.jump_damage_mult = 2.0
	d.jump_stun = 0.7
	d.retreat_hp_threshold = 0.0
	d.cost = 15
	d.rarity = GameConstants.RARITY_EPIC
	d.sprite_path = "res://assets/units/space_marines/sanguinary_guard"  # пакет assets/source_sheets/sanguinary_guard_2026-11-12 (tools/unit_from_cells.py)
	d.chapter_armor = true   # цвета братства шейдером (17.11.2026: особые отряды — в палитре своего братства)
	d.sprite_scale = 1.1
	return d

# Imperial Fists — Центурионы-опустошители: тяжёлая огневая точка, окапываются сильнее
static func centurion_devastators() -> UnitData:
	var d = devastator()
	d.unit_name = "Walking Bastions"
	d.tags = ["marine", "ranged", "heavy", "elite"]
	d.hp = 1100.0
	d.damage = 80.0
	d.attack_speed = 0.6
	d.attack_range = 300.0
	d.move_speed = 40.0
	d.entrench_bonus = 0.4
	d.retreat_hp_threshold = 0.0
	d.cost = 14
	d.rarity = GameConstants.RARITY_EPIC
	d.sprite_path = "res://assets/units/space_marines/centurion"  # пакет assets/source_sheets/centurion_redraw_2026-11-11 (прежний лист — prep_sheet.py + sheet_to_frames.py, см. tools.md)
	d.chapter_armor = true   # цвета братства шейдером (17.11.2026: особые отряды — в палитре своего братства)
	d.sprite_scale = 1.35   # 11.11.2026: был 1.6 — новый лист шире, налезал на соседние клетки
	return d

# Space Wolves — Громовые волки: быстрая кавалерия, сбивает с ног
static func thunderwolf_cavalry() -> UnitData:
	var d = assault_marine()
	d.unit_name = "Erl-Riders"
	d.tags = ["marine", "melee", "fast", "elite"]
	d.hp = 1100.0
	d.damage = 65.0
	d.attack_speed = 1.0
	d.move_speed = 150.0
	d.jump_range = 0.0   # не прыгает — бежит
	d.on_hit_knockback = 200.0
	d.retreat_hp_threshold = 0.0
	d.cost = 15
	d.rarity = GameConstants.RARITY_EPIC
	d.sprite_path = "res://assets/units/space_marines/thunderwolf"  # пакет assets/source_sheets/thunderwolf_redraw_2026-11-11 (прежний лист — prep_sheet.py + sheet_to_frames.py, см. tools.md)
	d.armor_protect = Rect2(0, 100, 270, 120)   # волк: мех не в цвет братства (17.11.2026, «зелёные волки»)
	d.chapter_armor = true   # цвета братства шейдером (17.11.2026: особые отряды — в палитре своего братства)
	d.sprite_scale = 1.5
	return d

# Salamanders — Огненные драконы: огнемёты вблизи, сильный поджог
static func firedrakes() -> UnitData:
	var d = tactical_marine()
	d.unit_name = "Devil-Saddlers"
	d.tags = ["marine", "ranged", "elite"]
	d.hp = 380.0
	d.damage = 40.0
	d.attack_speed = 0.8
	d.attack_range = 110.0
	d.move_speed = 60.0
	d.projectile = "flame"
	d.on_hit_status = StatusEffects.BURNING
	d.on_hit_status_power = 4.0
	d.on_hit_status_duration = 3.0
	d.retreat_hp_threshold = 0.0
	d.cost = 14
	d.rarity = GameConstants.RARITY_EPIC
	d.sprite_path = "res://assets/units/space_marines/firedrakes"  # пакет assets/source_sheets/firedrakes_redraw_2026-11-11 (прежний лист — prep_sheet.py + sheet_to_frames.py, см. tools.md)
	d.chapter_armor = true   # цвета братства шейдером (17.11.2026: особые отряды — в палитре своего братства)
	d.sprite_scale = 1.05   # 11.11.2026: был 1.3 — новый лист шире, налезал на соседние клетки
	return d

# Khorne — Берсерки: ярость в ближнем бою, не отступают
static func khorne_berzerkers() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Seethers"
	d.tags = ["chaos", "melee", "elite"]
	d.projectile = ""
	d.hp = 180.0
	d.damage = 40.0
	d.attack_speed = 1.4
	d.attack_range = MELEE_RANGE
	d.move_speed = 100.0
	d.retreat_hp_threshold = 0.0
	d.cost = 14
	d.rarity = GameConstants.RARITY_EPIC
	d.sprite_path = "res://assets/units/chaos/berzerkers"  # лист assets/source_sheets/khorne_berzerkers_sheet.png (tools/prep_sheet.py + sheet_to_frames.py --counts)
	d.sprite_scale = 1.1
	return d

# Nurgle — Чумоносцы: живучие демоны, яд при каждом ударе
static func plaguebearers() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Goatspawn"
	d.tags = ["chaos", "melee", "daemon"]
	d.projectile = ""
	d.hp = 400.0
	d.damage = 18.0
	d.attack_speed = 0.8
	d.attack_range = MELEE_RANGE
	d.move_speed = 50.0
	d.on_hit_status = StatusEffects.POISONED
	d.on_hit_status_power = 3.0
	d.on_hit_status_duration = 4.0
	d.retreat_hp_threshold = 0.0
	d.cost = 14
	d.rarity = GameConstants.RARITY_EPIC
	d.blood = "green"
	d.sprite_path = "res://assets/units/chaos/plaguebearers"  # лист assets/source_sheets/plaguebearers_sheet.png (tools/prep_sheet.py + sheet_to_frames.py --counts)
	return d

# Tzeentch — Рубриковые десантники: варп-болты бьют сильно и издалека
static func rubric_marines() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Dustplate"
	d.tags = ["chaos", "ranged", "elite"]
	d.hp = 300.0
	d.damage = 40.0
	d.attack_speed = 0.7
	d.attack_range = 220.0
	d.move_speed = 55.0
	d.projectile = "warp_bolt"   # варп-болт FXpack13 — синий, без перекраски в тёплый
	d.projectile_warm = false
	d.retreat_hp_threshold = 0.0
	d.cost = 15
	d.rarity = GameConstants.RARITY_EPIC
	d.sprite_path = "res://assets/units/chaos/rubric_marines"  # лист assets/source_sheets/rubric_marines_sheet.png (tools/prep_sheet.py + sheet_to_frames.py --counts)
	d.sprite_scale = 1.1
	return d

# Slaanesh — Шумовые десантники: звуковое оружие оглушает
static func noise_marines() -> UnitData:
	var d = chaos_marine()
	d.unit_name = "Second Act Chorus"
	d.tags = ["chaos", "ranged"]
	d.hp = 120.0
	d.damage = 20.0
	d.attack_speed = 1.2
	d.attack_range = 200.0
	d.move_speed = 85.0
	d.on_hit_stun = 0.25
	d.projectile = "sonic_wave"   # звуковая волна (пакет эффектов), не болт Chaos Marine
	d.cost = 14
	d.rarity = GameConstants.RARITY_EPIC
	d.sprite_path = "res://assets/units/chaos/noise_marines"  # лист assets/source_sheets/noise_marines_sheet.png (tools/prep_sheet.py + sheet_to_frames.py --counts)
	return d
