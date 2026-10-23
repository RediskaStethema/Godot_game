class_name Chapters
extends RefCounted

# Ордены Космодесанта (TDD «Chapter Bonus») и боги-покровители Хаоса (TDD «Mark of the Gods»;
# решение пользователя 16.10.2026 — выбор бога на весь забег, как орден): выбор после расы в начале
# забега, пассивный бонус на весь забег (RunManager.player_chapter, сохраняется). faction — чья запись.
# Бонус бойцам — runtime-поля в начале боя (SynergyManager.apply_chapter_bonus):
#   ключи SynergyManager.BONUS_MULT_FIELDS (damage_mult, attack_range_mult, …),
#   tag — только бойцам с тегом ("" — всем),
#   on_hit_status — эффект при попадании (StatusEffects), если у юнита своего нет.
# building — множители статов зданий игрока (Building.refresh_stats): ключ стата → ×.
# armor — цвет брони ордена на бойцах игрока (Soldier: шейдер перекрашивает синие пиксели листа):
#   hue — тон 0..1, sat / val — множители насыщенности и яркости; нет ключа — синий как нарисовано.
# Особые (решение пользователя 18.10.2026): у каждого ордена / бога — минус («плата» за бонус) и свои карты
#   malus — те же ключи, что bonus, на бойцов с malus_tag ("" — всем), malus_desc — текст;
#   unit_card / building_card — id особых карт: только в магазине этого ордена (CardFactory.build_pool).
# Цифры — черновые, на одобрение.

const FACTION: String = "space_marines"   # раса с цветом брони орденов (Soldier._apply_chapter_colors)

const CHAPTERS = [
	{"id": "ultramarines", "name": "Ultramarines", "faction": "space_marines",
		"desc": "+10% дальности атаки всем",
		"bonus": {"attack_range_mult": 1.10}, "tag": "",
		"malus": {"move_speed_mult": 0.9}, "malus_desc": "−10% скорости бега всем",
		"unit_card": "honour_guard", "building_card": "codex_bastion",
		# Броня орденов темнее (решение пользователя 17.10.2026: были слишком яркими; Blood Angels — как были):
		# Ultramarines — синий листа (тон 0.638), но темнее
		"armor": {"hue": 0.638, "sat": 0.95, "val": 0.6}},
	{"id": "blood_angels", "name": "Blood Angels", "faction": "space_marines",
		"desc": "+15% урона бойцам ближнего боя",
		"bonus": {"damage_mult": 1.15}, "tag": "melee",
		"malus": {"damage_mult": 0.85}, "malus_tag": "ranged", "malus_desc": "−15% урона стрелкам",
		"unit_card": "sanguinary_guard", "building_card": "blood_chalice",
		"armor": {"hue": 0.97, "sat": 0.95, "val": 0.55}},   # тёмный бордовый — не путать с рыже-красным Хаосом (решение пользователя 16.10.2026)
	{"id": "imperial_fists", "name": "Imperial Fists", "faction": "space_marines",
		"desc": "Здания: стены крепче и щит +50%, +20% урона",
		"building": {"shield": 1.5, "damage": 1.2, "wall_hp": 1.5},
		"malus": {"move_speed_mult": 0.9}, "malus_desc": "−10% скорости бега всем",
		"unit_card": "centurion_devastators", "building_card": "fists_bastion",
		"armor": {"hue": 0.12, "sat": 1.0, "val": 0.85}},   # золото: темнее — уходит в оливковый
	{"id": "space_wolves", "name": "Space Wolves", "faction": "space_marines",
		"desc": "+15% скорости бега и атаки всем",
		"bonus": {"move_speed_mult": 1.15, "attack_speed_mult": 1.15}, "tag": "",
		"malus": {"attack_range_mult": 0.85}, "malus_tag": "ranged", "malus_desc": "−15% дальности стрелкам",
		"unit_card": "thunderwolf_cavalry", "building_card": "wolf_totem",
		"armor": {"hue": 0.58, "sat": 0.35, "val": 0.75}},
	{"id": "salamanders", "name": "Salamanders", "faction": "space_marines",
		"desc": "Атаки поджигают цель (2 ур/с, 2 с)",
		"on_hit_status": "burning", "on_hit_status_power": 2.0, "on_hit_status_duration": 2.0,
		"malus": {"move_speed_mult": 0.9}, "malus_desc": "−10% скорости бега всем",
		"unit_card": "firedrakes", "building_card": "vulkan_forge",
		"armor": {"hue": 0.36, "sat": 0.85, "val": 0.6}},
	# Боги Хаоса — метка на всю армию
	{"id": "khorne", "name": "Khorne", "faction": "chaos",
		"desc": "Метка Кровавого бога: +20% урона бойцам ближнего боя",
		"bonus": {"damage_mult": 1.20}, "tag": "melee",
		"malus": {"damage_mult": 0.8}, "malus_tag": "ranged", "malus_desc": "−20% урона стрелкам",
		"unit_card": "khorne_berzerkers", "building_card": "skull_altar"},
	{"id": "nurgle", "name": "Nurgle", "faction": "chaos",
		"desc": "Метка Чумного бога: +15% HP всем",
		"bonus": {"hp_mult": 1.15}, "tag": "",
		"malus": {"move_speed_mult": 0.85}, "malus_desc": "−15% скорости бега всем",
		"unit_card": "plaguebearers", "building_card": "plague_cauldron"},
	{"id": "tzeentch", "name": "Tzeentch", "faction": "chaos",
		"desc": "Метка Изменяющего Пути: +20% урона стрелкам",
		"bonus": {"damage_mult": 1.20}, "tag": "ranged",
		"malus": {"hp_mult": 0.85}, "malus_desc": "−15% HP всем",
		"unit_card": "rubric_marines", "building_card": "warp_spire"},
	{"id": "slaanesh", "name": "Slaanesh", "faction": "chaos",
		"desc": "Метка Принца Наслаждений: +15% скорости бега и атаки всем",
		"bonus": {"move_speed_mult": 1.15, "attack_speed_mult": 1.15}, "tag": "",
		"malus": {"damage_taken_mult": 1.1}, "malus_desc": "Бойцы получают +10% урона",
		"unit_card": "noise_marines", "building_card": "pleasure_shrine"},
]
# Окно выбора по расе: заголовок и подпись
const SELECT_TEXT = {
	"space_marines": ["ВЫБОР ОРДЕНА", "Орден даёт бонус на весь забег"],
	"chaos": ["БОГ-ПОКРОВИТЕЛЬ", "Метка бога — бонус всей армии на весь забег"],
}

# Орден по id; пустой словарь — ордена нет (другая раса, старое сохранение)
static func get_chapter(id: String) -> Dictionary:
	for c in CHAPTERS:
		if c["id"] == id:
			return c
	return {}

static func has_chapters(faction: String) -> bool:
	return not for_faction(faction).is_empty()

# Ордены / боги расы, по порядку
static func for_faction(faction: String) -> Array:
	return CHAPTERS.filter(func(c): return c["faction"] == faction)

# Статы здания с бонусом ордена (копия — статы карты не меняются)
static func apply_building_stats(stats: Dictionary, chapter_id: String) -> Dictionary:
	var mults: Dictionary = get_chapter(chapter_id).get("building", {})
	if mults.is_empty():
		return stats
	var out = stats.duplicate()
	for key in mults:
		if out.has(key):
			out[key] = out[key] * mults[key]
	return out
