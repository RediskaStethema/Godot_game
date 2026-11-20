class_name ChaosGods
extends RefCounted

# Бог-покровитель отряда Хаоса и благословения богов (решение пользователя 25.10.2026, CARD_ABILITIES.txt).
# У каждого Rare / Epic отряда Хаоса свой бог (по лору, SQUAD_GODS), у Common — нет, пока на него не сыграли
# «Chaos Gods' Blessing» (бог — на выбор). Бог отряда — не бог забега
# (Chapters, метка на всю армию): карта «Chaos Gods' Blessing» меняет бога отряда (UnitData.god), накопленные
# благословения при этом пропадают. Карта «Blessing of <бог>» — только на отряд этого бога, до MAX_BLESSINGS раз
# (UnitData.blessings); действие — множители UnitData.get_* и поля бойца в начале боя (Soldier.setup). Без
# зависимостей от автолоадов: UnitData и тесты берут его до них. Цифры — на одобрение

const GODS = ["khorne", "nurgle", "tzeentch", "slaanesh"]
# Названия карт даров Внешних (CardFactory.BLESSING_TEXT) — в подсказке бога (RENAMING_MAP 17.11.2026)
const BLESSING_TITLES = {"khorne": "Gift of the Seething", "nurgle": "Gift of the Grandfather", "tzeentch": "Gift of the Herald",
	"slaanesh": "Gift of the King"}
const NAMES = {"khorne": "Кипящий", "nurgle": "Дедушка Тысячи", "tzeentch": "Вестник", "slaanesh": "Король Второго Акта"}
const MAX_BLESSINGS: int = 3

# Бог отряда по юниту (UnitData.factory_id) — по лору; особые юниты богов — своему богу. Нет в списке — бога нет
const SQUAD_GODS = {
	"plague_marine": "nurgle",
	"chaos_havoc": "tzeentch",
	"chaos_champion": "khorne",
	"hellbrute": "khorne",
	"chaos_lord_player": "slaanesh",
	"khorne_berzerkers": "khorne",
	"plaguebearers": "nurgle",
	"rubric_marines": "tzeentch",
	"noise_marines": "slaanesh",
}

# Благословения — за каждое наложение (n — сколько наложено, 1..3)
const KHORNE_MELEE_DAMAGE: float = 0.15   # +урона бойцам ближнего боя; с первого — не отступают
const NURGLE_HP: float = 0.20             # +HP
const NURGLE_POISON: float = 2.0          # яд в атаках, ур/с за наложение (на POISON_TIME)
const NURGLE_DAMAGE: float = 0.9          # урон ×
const TZEENTCH_RANGE: float = 0.15        # +дальности (только стрелки)
const TZEENTCH_FLAT_DAMAGE: float = 5.0   # +урона на «целого» бойца (× UnitData.unit_weight: пехота — доля)
const TZEENTCH_ATTACK_SPEED: float = 0.9  # скорострельность ×
const SLAANESH_CHARM = [0.03, 0.05, 0.10]   # шанс поработить при попадании на 1 / 2 / 3 наложении
const SLAANESH_STATS = [0.95, 0.92, 0.90]   # HP, урон, скорострельность и бег ×
const POISON_TIME: float = 3.0
const SLAANESH_HEAL: float = 0.25   # порабощённые, а состав полный — отряд лечится на эту долю (раз за бой)

static func default_god(factory_id: String) -> String:
	return SQUAD_GODS.get(factory_id, "")

static func god_name(god: String) -> String:
	return NAMES.get(god, "")

# Множители статов отряда бога god с n благословениями (UnitData.get_*): {"hp", "damage", "attack_speed",
# "move_speed", "range"} — × и "flat_damage" — +; tags — теги юнита (ближний бой / стрелки), weight — unit_weight
static func stat_mods(god: String, n: int, tags: Array, weight: float) -> Dictionary:
	var m := {"hp": 1.0, "damage": 1.0, "attack_speed": 1.0, "move_speed": 1.0, "range": 1.0, "flat_damage": 0.0}
	if n <= 0:
		return m
	match god:
		"khorne":
			if "melee" in tags:
				m["damage"] = 1.0 + KHORNE_MELEE_DAMAGE * n
		"nurgle":
			m["hp"] = 1.0 + NURGLE_HP * n
			m["damage"] = pow(NURGLE_DAMAGE, n)
		"tzeentch":
			if "ranged" in tags:
				m["range"] = 1.0 + TZEENTCH_RANGE * n
				m["flat_damage"] = TZEENTCH_FLAT_DAMAGE * n * weight
				m["attack_speed"] = pow(TZEENTCH_ATTACK_SPEED, n)
		"slaanesh":
			var k: float = SLAANESH_STATS[mini(n, SLAANESH_STATS.size()) - 1]
			for key in ["hp", "damage", "attack_speed", "move_speed"]:
				m[key] = k
	return m

# Яд в атаках (Дедушка Тысячи), ур/с; 0 — нет
static func poison_power(god: String, n: int) -> float:
	return NURGLE_POISON * n if god == "nurgle" else 0.0

# Шанс поработить при попадании (Король Второго Акта); 0 — нет
static func charm_chance(god: String, n: int) -> float:
	return SLAANESH_CHARM[mini(n, SLAANESH_CHARM.size()) - 1] if god == "slaanesh" and n > 0 else 0.0

# Отряд не отступает (Кипящий)
static func no_retreat(god: String, n: int) -> bool:
	return god == "khorne" and n > 0

# Текст для справки отряда: что дают благословения сейчас
# Цвет имени бога в тексте (Palette.GOD_TEXT); нет бога — янтарь
static func god_color(god: String) -> Color:
	return Palette.GOD_TEXT.get(god, Palette.AMBER_LIGHT)

# Подсказка к богу отряда в справке: что даёт каждое благословение (карта «Blessing of <бог>», до MAX_BLESSINGS)
static func blessing_hint(god: String) -> String:
	var per := ""
	match god:
		"khorne":
			per = "+%d%% урона бойцам ближнего боя, с первого — отряд не отступает" % roundi(KHORNE_MELEE_DAMAGE * 100.0)
		"nurgle":
			per = "+%d%% HP и яд %s ур/с в атаках, но урон ×%.2f" % [roundi(NURGLE_HP * 100.0), str(NURGLE_POISON), NURGLE_DAMAGE]
		"tzeentch":
			per = "стрелкам +%d%% дальности и +%d урона, но скорострельность ×%.2f" % [roundi(TZEENTCH_RANGE * 100.0),
				roundi(TZEENTCH_FLAT_DAMAGE), TZEENTCH_ATTACK_SPEED]
		"slaanesh":
			per = "шанс поработить врага при попадании (%d / %d / %d%%), но все статы ниже" % [
				roundi(SLAANESH_CHARM[0] * 100.0), roundi(SLAANESH_CHARM[1] * 100.0), roundi(SLAANESH_CHARM[2] * 100.0)]
	if per == "":
		return ""
	return "Покровитель отряда. Каждый дар (карта «%s», до %d): %s" % [
		BLESSING_TITLES.get(god, god.capitalize()), MAX_BLESSINGS, per]

static func describe(god: String, n: int, tags: Array) -> String:
	if god == "":
		return ""
	var text := "Бог: %s · благословений %d/%d" % [god_name(god), n, MAX_BLESSINGS]
	if n <= 0:
		return text
	match god:
		"khorne":
			text += " — +%d%% урона ближнего боя, не отступает" % roundi(KHORNE_MELEE_DAMAGE * n * 100.0)
		"nurgle":
			text += " — +%d%% HP, яд %s ур/с в атаках, урон ×%.2f" % [roundi(NURGLE_HP * n * 100.0),
				str(poison_power(god, n)), pow(NURGLE_DAMAGE, n)]
		"tzeentch":
			if "ranged" in tags:
				text += " — +%d%% дальности, +%d урона, скорострельность ×%.2f" % [roundi(TZEENTCH_RANGE * n * 100.0),
					roundi(TZEENTCH_FLAT_DAMAGE * n), pow(TZEENTCH_ATTACK_SPEED, n)]
			else:
				text += " — действует только на стрелков"
		"slaanesh":
			text += " — шанс поработить %d%%, статы ×%.2f" % [roundi(charm_chance(god, n) * 100.0),
				SLAANESH_STATS[mini(n, SLAANESH_STATS.size()) - 1]]
	return text
