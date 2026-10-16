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
# Цифры — черновые, на одобрение.

const FACTION: String = "space_marines"   # раса с цветом брони орденов (Soldier._apply_chapter_colors)

const CHAPTERS = [
	{"id": "ultramarines", "name": "Ultramarines", "faction": "space_marines",
		"desc": "+10% дальности атаки всем",
		"bonus": {"attack_range_mult": 1.10}, "tag": ""},
	{"id": "blood_angels", "name": "Blood Angels", "faction": "space_marines",
		"desc": "+15% урона бойцам ближнего боя",
		"bonus": {"damage_mult": 1.15}, "tag": "melee",
		"armor": {"hue": 0.97, "sat": 0.95, "val": 0.55}},   # тёмный бордовый — не путать с рыже-красным Хаосом (решение пользователя 16.10.2026)
	{"id": "imperial_fists", "name": "Imperial Fists", "faction": "space_marines",
		"desc": "Здания: +50% щита стен, +20% урона",
		"building": {"shield": 1.5, "damage": 1.2},
		"armor": {"hue": 0.13, "sat": 1.0, "val": 1.5}},
	{"id": "space_wolves", "name": "Space Wolves", "faction": "space_marines",
		"desc": "+15% скорости бега и атаки всем",
		"bonus": {"move_speed_mult": 1.15, "attack_speed_mult": 1.15}, "tag": "",
		"armor": {"hue": 0.58, "sat": 0.35, "val": 1.3}},
	{"id": "salamanders", "name": "Salamanders", "faction": "space_marines",
		"desc": "Атаки поджигают цель (2 ур/с, 2 с)",
		"on_hit_status": "burning", "on_hit_status_power": 2.0, "on_hit_status_duration": 2.0,
		"armor": {"hue": 0.36, "sat": 0.9, "val": 1.0}},
	# Боги Хаоса — метка на всю армию
	{"id": "khorne", "name": "Khorne", "faction": "chaos",
		"desc": "Метка Кровавого бога: +20% урона бойцам ближнего боя",
		"bonus": {"damage_mult": 1.20}, "tag": "melee"},
	{"id": "nurgle", "name": "Nurgle", "faction": "chaos",
		"desc": "Метка Чумного бога: +15% HP всем",
		"bonus": {"hp_mult": 1.15}, "tag": ""},
	{"id": "tzeentch", "name": "Tzeentch", "faction": "chaos",
		"desc": "Метка Изменяющего Пути: +20% урона стрелкам",
		"bonus": {"damage_mult": 1.20}, "tag": "ranged"},
	{"id": "slaanesh", "name": "Slaanesh", "faction": "chaos",
		"desc": "Метка Принца Наслаждений: +15% скорости бега и атаки всем",
		"bonus": {"move_speed_mult": 1.15, "attack_speed_mult": 1.15}, "tag": ""},
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
