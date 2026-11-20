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
		{"threshold": 3, "name": "We Few", "bonus": {"hp_mult": 1.15},
			"desc": "+15% HP всем Криспинцам"},
		{"threshold": 6, "name": "More Light!", "bonus": {"damage_mult": 1.10},
			"desc": "+10% урона всем Криспинцам"},
	],
	# Хаос игрока (решение пользователя 16.10.2026): те же пороги, бонусы в обратном порядке
	"chaos": [
		{"threshold": 3, "name": "Thane's Path", "bonus": {"damage_mult": 1.10},
			"desc": "+10% урона всем Кровоподписантам"},
		{"threshold": 6, "name": "The Second Act", "bonus": {"hp_mult": 1.15},
			"desc": "+15% HP всем Кровоподписантам"},
	],
	"elite": [
		{"threshold": 2, "name": "Greymoustaches", "bonus": {"epic_discount": 1},
			"desc": "−1 монета к цене следующей Epic карты"},
	],
}

# Позиция в королевстве (TDD [frontline] / [backline]): ряд клеток по оси col —
# ближний к врагу (наибольший col открытых клеток) и дальний (наименьший).
# Средние ряды без бонуса; королевство в один ряд — бонусов нет.
# Щит фронта из TDD заменён на +HP: поля щита в main пока нет (PR #9).
# tag — бонус только бойцам с этим тегом ("" — всем)
const FRONT: String = "front"
const BACK: String = "back"
const POSITION_BONUSES = {
	FRONT: {"name": "Передний ряд", "bonus": {"hp_mult": 1.10}, "tag": "",
		"desc": "+10% HP отрядам ближнего к врагу ряда"},
	BACK: {"name": "Задний ряд", "bonus": {"damage_mult": 1.15}, "tag": "ranged",
		"desc": "+15% урона стрелкам дальнего от врага ряда"},
}

# Доход TDD: «Синергия-бонус (3+ юнита фракции) — +2 за каждые 3 юнита»: тег расы забега
const INCOME_TAG: String = "marine"
const FACTION_TAGS = {"space_marines": "marine", "chaos": "chaos"}

# Тег расы забега (синергия дохода, подсказки)
func faction_tag() -> String:
	return FACTION_TAGS.get(RunManager.player_faction, INCOME_TAG)
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
# Название расы синергии для игрока (тег marine / chaos — внутренний; RENAMING_MAP 17.11.2026)
func tag_label(tag: String) -> String:
	match tag:
		"marine":
			return "Криспинцы"
		"chaos":
			return "Кровоподписанты"
	return tag.capitalize()

func calculate_synergies(soldiers: Array) -> void:
	tag_counts.clear()
	active_synergies.clear()
	# Боец пехоты — доля юнита (UnitData.unit_weight): пороги как при прежних отрядах
	var weights: Dictionary = {}
	for soldier in soldiers:
		for tag in soldier.data.tags:
			weights[tag] = weights.get(tag, 0.0) + soldier.data.unit_weight
	for tag in weights:
		tag_counts[tag] = int(weights[tag] + 0.001)

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

	income_bonus = (tag_counts.get(faction_tag(), 0) / INCOME_GROUP_SIZE) * INCOME_PER_GROUP
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

# Ключ бонуса → runtime-поле бойца. Новый бонус синергии — строка здесь
# и ключ в SYNERGY_DEFINITIONS (hp_mult — отдельно: сохраняет долю HP)
const BONUS_MULT_FIELDS = {
	"damage_mult": "current_damage",
	"move_speed_mult": "current_move_speed",
	"attack_speed_mult": "current_attack_speed",
	"heal_mult": "current_heal_per_second",
	"attack_range_mult": "current_attack_range",
	"damage_taken_mult": "damage_taken_mult",   # получаемый урон (минус Slaanesh)
}
const BONUS_ADD_FIELDS = {
	"attack_range_add": "current_attack_range",
}

func _apply_bonus(soldier, bonus: Dictionary) -> void:
	if bonus.has("hp_mult"):
		# Раненые остаются ранеными в той же пропорции
		var ratio = soldier.current_hp / soldier.max_hp
		soldier.max_hp *= bonus["hp_mult"]
		soldier.current_hp = soldier.max_hp * ratio
	for key in BONUS_MULT_FIELDS:
		if bonus.has(key):
			soldier.set(BONUS_MULT_FIELDS[key], soldier.get(BONUS_MULT_FIELDS[key]) * bonus[key])
	for key in BONUS_ADD_FIELDS:
		if bonus.has(key):
			soldier.set(BONUS_ADD_FIELDS[key], soldier.get(BONUS_ADD_FIELDS[key]) + bonus[key])
	soldier.queue_redraw()

# Ряд клетки королевства: FRONT, BACK или "" (средний ряд / королевство в один ряд)
func get_tile_position(tile: Vector2i, kingdom: Array[Vector2i]) -> String:
	if kingdom.is_empty():
		return ""
	var front = kingdom[0].x
	var back = kingdom[0].x
	for t in kingdom:
		front = maxi(front, t.x)
		back = mini(back, t.x)
	if front == back:
		return ""
	if tile.x == front:
		return FRONT
	if tile.x == back:
		return BACK
	return ""

# Бонус ряда отряду (или "", если его ряд или теги бонуса не дают)
func get_squad_position_bonus(squad) -> String:
	var pos = get_tile_position(squad.tile, BattleManager.kingdom_tiles)
	if pos == "":
		return ""
	var tag: String = POSITION_BONUSES[pos]["tag"]
	return pos if tag == "" or tag in squad.data.tags else ""

# Один раз при старте боя, после синергий: бонусы рядов бойцам своих отрядов
func apply_position_bonuses(squads: Array) -> void:
	for squad in squads:
		var pos = get_squad_position_bonus(squad)
		if pos == "":
			continue
		for soldier in squad.soldiers:
			_apply_bonus(soldier, POSITION_BONUSES[pos]["bonus"])

# Сколько отрядов получат бонус каждого ряда — для панели синергий
func count_position_bonuses(squads: Array) -> Dictionary:
	var counts = {FRONT: 0, BACK: 0}
	for squad in squads:
		var pos = get_squad_position_bonus(squad)
		if pos != "":
			counts[pos] += 1
	return counts

# Орден забега (Chapters, RunManager.player_chapter): один раз при старте боя
func apply_chapter_bonus(soldiers: Array) -> void:
	var c: Dictionary = Chapters.get_chapter(RunManager.player_chapter)
	if c.is_empty():
		return
	var tag: String = c.get("tag", "")
	for s in soldiers:
		if c.has("bonus") and (tag == "" or tag in s.data.tags):
			_apply_bonus(s, c["bonus"])
		# Минус ордена / бога (решение пользователя 18.10.2026: плата за бонус) — те же ключи, свой тег
		var malus_tag: String = c.get("malus_tag", "")
		if c.has("malus") and (malus_tag == "" or malus_tag in s.data.tags):
			_apply_bonus(s, c["malus"])
		if c.has("on_hit_status"):
			s.extra_on_hit_status = c["on_hit_status"]
			s.extra_on_hit_status_power = c["on_hit_status_power"]
			s.extra_on_hit_status_duration = c["on_hit_status_duration"]

# Пассивка мета-прогрессии «Ветеранская выучка»: +% HP своим бойцам, один раз перед боем
# (runtime-поля, доля HP сохраняется)
func apply_meta_bonus(soldiers: Array) -> void:
	var hp_bonus: float = MetaProgress.passive_value("veterans") / 100.0
	if hp_bonus <= 0.0:
		return
	for s in soldiers:
		var ratio: float = s.current_hp / s.max_hp
		s.max_hp *= 1.0 + hp_bonus
		s.current_hp = s.max_hp * ratio

# Командир (Chapter Master): +урон всем союзникам, один раз перед боем.
# Несколько командиров не суммируются — берётся самый сильный бонус.
func apply_commander_bonus(soldiers: Array) -> void:
	var bonus: float = 0.0
	for s in soldiers:
		bonus = maxf(bonus, s.data.commander_damage_bonus)
	if bonus <= 0.0:
		return
	for s in soldiers:
		s.current_damage *= 1.0 + bonus
	print("SynergyManager: командир — +%d%% урона армии" % roundi(bonus * 100.0))

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
# СОХРАНЕНИЕ (SaveManager) — своё состояние забега
# -------------------------------------------------------
# Синергии пересчитываются по полю — между боями живёт только скидка Epic
func save_state() -> Dictionary:
	return {"epic_discount_pending": epic_discount_pending}

func load_state(d: Dictionary) -> void:
	epic_discount_pending = int(d["epic_discount_pending"])

# Новая игра
func reset() -> void:
	tag_counts.clear()
	active_synergies.clear()
	income_bonus = 0
	epic_discount_pending = 0
