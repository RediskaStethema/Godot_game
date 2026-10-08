extends Node

# Без class_name: имя класса совпало бы с именем autoload-синглтона.

# -------------------------------------------------------
# ОПРЕДЕЛЕНИЯ СИНЕРГИЙ (TDD, раздел 3 — MVP: marine x3, marine x6, elite x2)
# -------------------------------------------------------
# tag → список уровней. Уровни суммируются: при 6 marine работают оба.
# Бонусы к бойцам: hp_mult, damage_mult, move_speed_mult,
#                  attack_speed_mult, attack_range_add, heal_mult
# Бонусы к экономике: epic_discount — скидка на следующую Epic карту
const SYNERGY_DEFINITIONS = {
	"marine": [
		{"threshold": 3, "name": "Astartes Brotherhood", "bonus": {"hp_mult": 1.15},
			"desc": "+15% HP всем Marine"},
		{"threshold": 6, "name": "For the Emperor", "bonus": {"damage_mult": 1.10},
			"desc": "+10% урона всем Marine"},
	],
	"elite": [
		{"threshold": 2, "name": "Veteran Command", "bonus": {"epic_discount": 1},
			"desc": "-1 Req к следующей Epic карте"},
	],
}

# Доход TDD: «Синергия-бонус (3+ юнита фракции) — +2 за каждые 3 юнита»
const INCOME_TAG: String = "marine"
const INCOME_PER_GROUP: int = 2
const INCOME_GROUP_SIZE: int = 3

# -------------------------------------------------------
# СОСТОЯНИЕ (пересчитывается перед каждым боем, не накапливается)
# -------------------------------------------------------
var tag_counts: Dictionary = {}
var active_synergies: Array[Dictionary] = []
var income_bonus: int = 0
# Скидка живёт до покупки Epic карты, поэтому её не сбрасываем в calculate
var epic_discount_pending: int = 0

signal synergies_changed(active: Array)

# Считаем теги по бойцам (1 боец = 1 юнит, как в лимите армии)
func calculate_synergies(soldiers: Array) -> void:
	tag_counts.clear()
	active_synergies.clear()
	for soldier in soldiers:
		for tag in soldier.data.tags:
			tag_counts[tag] = tag_counts.get(tag, 0) + 1

	for tag in SYNERGY_DEFINITIONS:
		var count = tag_counts.get(tag, 0)
		for level in SYNERGY_DEFINITIONS[tag]:
			if count >= level["threshold"]:
				active_synergies.append({
					"tag": tag,
					"name": level["name"],
					"desc": level["desc"],
					"bonus": level["bonus"],
					"count": count,
					"threshold": level["threshold"],
				})

	income_bonus = (tag_counts.get(INCOME_TAG, 0) / INCOME_GROUP_SIZE) * INCOME_PER_GROUP
	emit_signal("synergies_changed", active_synergies)

# Вызывается один раз при старте боя, после calculate_synergies.
# Меняет только runtime-статы бойцов — UnitData не трогаем.
func apply_synergies_to_soldiers(soldiers: Array) -> void:
	for synergy in active_synergies:
		var bonus: Dictionary = synergy["bonus"]
		if bonus.has("epic_discount"):
			epic_discount_pending = max(epic_discount_pending, bonus["epic_discount"])
		for soldier in soldiers:
			if synergy["tag"] in soldier.data.tags:
				_apply_bonus(soldier, bonus)

func _apply_bonus(soldier, bonus: Dictionary) -> void:
	if bonus.has("hp_mult"):
		# Раненые остаются ранеными в той же пропорции
		var ratio = soldier.current_hp / soldier.max_hp
		soldier.max_hp *= bonus["hp_mult"]
		soldier.current_hp = soldier.max_hp * ratio
	if bonus.has("damage_mult"):
		soldier.current_damage *= bonus["damage_mult"]
	if bonus.has("move_speed_mult"):
		soldier.current_move_speed *= bonus["move_speed_mult"]
	if bonus.has("attack_speed_mult"):
		soldier.current_attack_speed *= bonus["attack_speed_mult"]
	if bonus.has("attack_range_add"):
		soldier.current_attack_range += bonus["attack_range_add"]
	if bonus.has("heal_mult"):
		soldier.current_heal_per_second *= bonus["heal_mult"]
	soldier.queue_redraw()

# -------------------------------------------------------
# ЭКОНОМИКА
# -------------------------------------------------------
# Цена карты с учётом скидок синергий (для отображения и покупки)
func get_discounted_cost(card: CardData) -> int:
	if card.rarity == GameConstants.RARITY_EPIC and epic_discount_pending > 0:
		return max(card.cost - epic_discount_pending, 0)
	return card.cost

func consume_discount(card: CardData) -> void:
	if card.rarity == GameConstants.RARITY_EPIC:
		epic_discount_pending = 0

# -------------------------------------------------------
# UI
# -------------------------------------------------------
func get_active_synergy_names() -> Array[String]:
	var names: Array[String] = []
	for s in active_synergies:
		names.append("%s (%s %d/%d): %s" % [s["name"], s["tag"], s["count"], s["threshold"], s["desc"]])
	return names

# Новая игра
func reset() -> void:
	tag_counts.clear()
	active_synergies.clear()
	income_bonus = 0
	epic_discount_pending = 0
