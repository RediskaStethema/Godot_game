class_name Chapters
extends RefCounted

# Ордены Космодесанта (TDD «Chapter Bonus»): выбор после расы в начале забега,
# пассивный бонус на весь забег (RunManager.player_chapter, сохраняется).
# Бонус бойцам — runtime-поля в начале боя (SynergyManager.apply_chapter_bonus):
#   ключи SynergyManager.BONUS_MULT_FIELDS (damage_mult, attack_range_mult, …),
#   tag — только бойцам с тегом ("" — всем),
#   on_hit_status — эффект при попадании (StatusEffects), если у юнита своего нет.
# building — множители статов зданий игрока (Building.refresh_stats): ключ стата → ×.
# armor — цвет брони ордена на бойцах игрока (Soldier: шейдер перекрашивает синие пиксели листа):
#   hue — тон 0..1, sat / val — множители насыщенности и яркости; нет ключа — синий как нарисовано.
# Цифры — черновые, на одобрение.

const FACTION: String = "space_marines"

const CHAPTERS = [
	{"id": "ultramarines", "name": "Ultramarines",
		"desc": "+10% дальности атаки всем",
		"bonus": {"attack_range_mult": 1.10}, "tag": ""},
	{"id": "blood_angels", "name": "Blood Angels",
		"desc": "+15% урона бойцам ближнего боя",
		"bonus": {"damage_mult": 1.15}, "tag": "melee",
		"armor": {"hue": 0.0, "sat": 1.1, "val": 1.05}},
	{"id": "imperial_fists", "name": "Imperial Fists",
		"desc": "Здания: +50% щита стен, +20% урона",
		"building": {"shield": 1.5, "damage": 1.2},
		"armor": {"hue": 0.13, "sat": 1.0, "val": 1.5}},
	{"id": "space_wolves", "name": "Space Wolves",
		"desc": "+15% скорости бега и атаки всем",
		"bonus": {"move_speed_mult": 1.15, "attack_speed_mult": 1.15}, "tag": "",
		"armor": {"hue": 0.58, "sat": 0.35, "val": 1.3}},
	{"id": "salamanders", "name": "Salamanders",
		"desc": "Атаки поджигают цель (2 ур/с, 2 с)",
		"on_hit_status": "burning", "on_hit_status_power": 2.0, "on_hit_status_duration": 2.0,
		"armor": {"hue": 0.36, "sat": 0.9, "val": 1.0}},
]

# Орден по id; пустой словарь — ордена нет (другая раса, старое сохранение)
static func get_chapter(id: String) -> Dictionary:
	for c in CHAPTERS:
		if c["id"] == id:
			return c
	return {}

static func has_chapters(faction: String) -> bool:
	return faction == FACTION

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
