extends Node

# Мета-прогрессия между забегами — древо Арсенала (решение пользователя 10.11.2026, было — пассивки
# списком + достижения по статистике 16.10.2026):
# - Слава — валюта за каждый забег (и проигранный): бои, мини-боссы, главный босс × сложность;
# - всё открывается узлами древа TREE за Славу: пассивки на все забеги (уровень — отдельный узел),
#   стартовые карты (одна выбирается при новом забеге), ордены Космодесанта, карты магазина;
# - 4 ветки BRANCHES, у каждой свой корень; узел покупается, только когда куплен родитель (requires);
#   потраченная Слава не возвращается (сброса нет).
# Хранится в профиле игрока (SaveManager.profile_path, секция "meta", ключ "nodes"); старый профиль
# (уровни пассивок, стартовые карты, достижения) переносится в узлы при чтении — _migrate_legacy.
# Сохранение выключено (SaveManager.enabled = false: тесты, balance_sim) — всё открыто, пассивок нет,
# ничего не пишется. Цифры — черновые, на одобрение.

const SECTION: String = "meta"
const GLORY_PER_WIN: int = 1
const GLORY_PER_MINIBOSS: int = 3
const GLORY_PER_BOSS: int = 10

# Пассивки: value — прибавка за уровень; уровни — узлы древа с "kind": "passive"
const PASSIVES = [
	{"id": "reserves", "name": "Резервы братства", "desc": "+%d монет в начале забега", "value": 3},
	{"id": "walls", "name": "Пентаклевые стены", "desc": "Щит цитадели +%d в каждом бою", "value": 100},
	{"id": "veterans", "name": "Выучка седоусых", "desc": "+%d%% HP всем своим бойцам", "value": 5},
	{"id": "munitorum", "name": "Связи в Ревизской палате", "desc": "Первое обновление магазина за волну — бесплатно", "value": 1},
]

# Ветки древа: колонки окна Арсенала слева направо
const BRANCHES = [
	{"id": "economy", "name": "Ревизская палата"},
	{"id": "defense", "name": "Редут"},
	{"id": "army", "name": "Сечь"},
	{"id": "command", "name": "Совет Монструваканов"},
]

# Узлы древа. kind: passive (target — id из PASSIVES, level — какой уровень), start_card (target — id карты),
# chapter (орден Chapters), card (карта магазина, закрыта до покупки). row — ряд сверху вниз (0 — корень),
# lane — смещение в колонке ветки (-1 / 0 / 1); requires — родитель ("" — корень ветки)
const TREE = [
	# МУНИТОРУМ
	{"id": "reserves_1", "branch": "economy", "row": 0, "lane": 0, "cost": 10, "requires": "", "kind": "passive", "target": "reserves", "level": 1},
	{"id": "reserves_2", "branch": "economy", "row": 1, "lane": 0, "cost": 20, "requires": "reserves_1", "kind": "passive", "target": "reserves", "level": 2},
	{"id": "munitorum_1", "branch": "economy", "row": 2, "lane": -1, "cost": 25, "requires": "reserves_2", "kind": "passive", "target": "munitorum", "level": 1},
	{"id": "reserves_3", "branch": "economy", "row": 2, "lane": 1, "cost": 35, "requires": "reserves_2", "kind": "passive", "target": "reserves", "level": 3},
	{"id": "card_plasma_generatorium", "branch": "economy", "row": 3, "lane": -1, "cost": 30, "requires": "munitorum_1", "kind": "card", "target": "plasma_generatorium"},
	# БАСТИОН
	{"id": "walls_1", "branch": "defense", "row": 0, "lane": 0, "cost": 15, "requires": "", "kind": "passive", "target": "walls", "level": 1},
	{"id": "start_fortress_wall", "branch": "defense", "row": 1, "lane": -1, "cost": 10, "requires": "walls_1", "kind": "start_card", "target": "fortress_wall"},
	{"id": "walls_2", "branch": "defense", "row": 1, "lane": 1, "cost": 30, "requires": "walls_1", "kind": "passive", "target": "walls", "level": 2},
	{"id": "start_bolter_turret", "branch": "defense", "row": 2, "lane": -1, "cost": 20, "requires": "start_fortress_wall", "kind": "start_card", "target": "bolter_turret"},
	{"id": "walls_3", "branch": "defense", "row": 2, "lane": 1, "cost": 50, "requires": "walls_2", "kind": "passive", "target": "walls", "level": 3},
	# ВОИНСТВО
	{"id": "start_scout_squad", "branch": "army", "row": 0, "lane": 0, "cost": 5, "requires": "", "kind": "start_card", "target": "scout_squad"},
	{"id": "veterans_1", "branch": "army", "row": 1, "lane": -1, "cost": 20, "requires": "start_scout_squad", "kind": "passive", "target": "veterans", "level": 1},
	{"id": "start_apothecary", "branch": "army", "row": 1, "lane": 1, "cost": 15, "requires": "start_scout_squad", "kind": "start_card", "target": "apothecary"},
	{"id": "veterans_2", "branch": "army", "row": 2, "lane": -1, "cost": 40, "requires": "veterans_1", "kind": "passive", "target": "veterans", "level": 2},
	{"id": "card_apothecarion", "branch": "army", "row": 2, "lane": 1, "cost": 35, "requires": "start_apothecary", "kind": "card", "target": "apothecarion"},
	{"id": "start_terminator_squad", "branch": "army", "row": 3, "lane": -1, "cost": 30, "requires": "veterans_2", "kind": "start_card", "target": "terminator_squad"},
	# КОМАНДОВАНИЕ (Ultramarines и боги Хаоса открыты сразу — их в древе нет)
	{"id": "chapter_blood_angels", "branch": "command", "row": 0, "lane": 0, "cost": 15, "requires": "", "kind": "chapter", "target": "blood_angels"},
	{"id": "card_orbital_strike", "branch": "command", "row": 1, "lane": -1, "cost": 20, "requires": "chapter_blood_angels", "kind": "card", "target": "orbital_strike"},
	{"id": "chapter_space_wolves", "branch": "command", "row": 1, "lane": 1, "cost": 25, "requires": "chapter_blood_angels", "kind": "chapter", "target": "space_wolves"},
	{"id": "chapter_imperial_fists", "branch": "command", "row": 2, "lane": -1, "cost": 30, "requires": "card_orbital_strike", "kind": "chapter", "target": "imperial_fists"},
	{"id": "card_chapter_banner", "branch": "command", "row": 2, "lane": 1, "cost": 35, "requires": "chapter_space_wolves", "kind": "card", "target": "chapter_banner"},
	{"id": "chapter_salamanders", "branch": "command", "row": 3, "lane": -1, "cost": 50, "requires": "chapter_imperial_fists", "kind": "chapter", "target": "salamanders"},
]

# Перенос старого профиля: что открывали достижения (stat ≥ value) — узел даётся без оплаты
const LEGACY_UNLOCKS = {
	"chapter_blood_angels": ["best_wave", 5], "chapter_space_wolves": ["best_wave", 8],
	"chapter_imperial_fists": ["minibosses_total", 2], "chapter_salamanders": ["runs_won", 1],
	"card_orbital_strike": ["minibosses_total", 3], "card_plasma_generatorium": ["total_wins", 10],
	"card_chapter_banner": ["best_wave", 12], "card_apothecarion": ["total_wins", 25],
}
const LEVEL_NUMERALS = ["I", "II", "III", "IV", "V"]

signal changed

var glory: int = 0
var owned_nodes: Array[String] = []     # купленные узлы древа
var selected_start_card: String = ""    # последняя выбранная (НОВЫЙ ЗАБЕГ с экрана итога берёт её же)
# Забег (в сохранении забега, SaveManager.SYSTEMS): мини-боссов побеждено в этом забеге
var run_minibosses: int = 0
var _loaded_path: String = ""   # чей профиль в памяти: путь сменили (тесты) — перечитать

func _ready() -> void:
	load_profile()

# Мета действует только с включённым сохранением (игра); в тестах и симуляции — выключена.
# Тесты подменяют SaveManager.profile_path — профиль перечитывается сам (не настоящий игрока)
func active() -> bool:
	_ensure_loaded()
	return SaveManager.enabled

func _ensure_loaded() -> void:
	if _loaded_path != SaveManager.profile_path:
		load_profile()

func load_profile() -> void:
	_loaded_path = SaveManager.profile_path
	glory = 0
	owned_nodes.clear()
	selected_start_card = ""
	var cfg := ConfigFile.new()
	if cfg.load(SaveManager.profile_path) != OK:
		return
	glory = int(cfg.get_value(SECTION, "glory", 0))
	if cfg.has_section_key(SECTION, "nodes"):
		for id in cfg.get_value(SECTION, "nodes", []):
			if not get_node_data(str(id)).is_empty() and not owned_nodes.has(str(id)):
				owned_nodes.append(str(id))
	else:
		_migrate_legacy(cfg)
	selected_start_card = str(cfg.get_value(SECTION, "selected_start_card", ""))

# Профиль до древа: уровни пассивок → узлы уровней, стартовые карты → свои узлы, достижения → ордены и карты
func _migrate_legacy(cfg: ConfigFile) -> void:
	var levels: Dictionary = cfg.get_value(SECTION, "passives", {})
	var cards: Array = cfg.get_value(SECTION, "start_cards", [])
	var stats: Dictionary = cfg.get_value(SECTION, "stats", {})
	for n in TREE:
		var own := false
		match n["kind"]:
			"passive":
				own = int(levels.get(n["target"], 0)) >= int(n["level"])
			"start_card":
				own = cards.has(n["target"])
		if LEGACY_UNLOCKS.has(n["id"]):
			var rule: Array = LEGACY_UNLOCKS[n["id"]]
			own = own or int(stats.get(rule[0], 0)) >= int(rule[1])
		if own:
			owned_nodes.append(n["id"])

func save_profile() -> void:
	if not active():
		return
	var cfg := ConfigFile.new()
	cfg.load(SaveManager.profile_path)   # секция сложности (SaveManager) остаётся
	for old in ["passives", "start_cards", "stats"]:   # ключи профиля до древа
		if cfg.has_section_key(SECTION, old):
			cfg.erase_section_key(SECTION, old)
	cfg.set_value(SECTION, "glory", glory)
	cfg.set_value(SECTION, "nodes", Array(owned_nodes))
	cfg.set_value(SECTION, "selected_start_card", selected_start_card)
	cfg.save(SaveManager.profile_path)

func get_glory() -> int:
	_ensure_loaded()
	return glory

# -------------------------------------------------------
# ДРЕВО
# -------------------------------------------------------
static func get_node_data(id: String) -> Dictionary:
	for n in TREE:
		if n["id"] == id:
			return n
	return {}

static func get_branch(id: String) -> Dictionary:
	for b in BRANCHES:
		if b["id"] == id:
			return b
	return {}

static func branch_nodes(branch: String) -> Array:
	return TREE.filter(func(n): return n["branch"] == branch)

static func _node_for(kind: String, target: String) -> Dictionary:
	for n in TREE:
		if n["kind"] == kind and n["target"] == target:
			return n
	return {}

func owns(id: String) -> bool:
	_ensure_loaded()
	return owned_nodes.has(id)

# Можно купить: не куплен и родитель куплен (Славы может не хватать — см. can_buy)
func is_available(id: String) -> bool:
	var n := get_node_data(id)
	if n.is_empty() or owns(id):
		return false
	return n["requires"] == "" or owns(n["requires"])

func can_buy(id: String) -> bool:
	return is_available(id) and get_glory() >= int(get_node_data(id)["cost"])

func buy_node(id: String) -> bool:
	if not can_buy(id):
		return false
	glory -= int(get_node_data(id)["cost"])
	owned_nodes.append(id)
	save_profile()
	changed.emit()
	return true

# Название узла для окна Арсенала: «Резервы Ордена II», «Орден Blood Angels», название карты
static func node_title(n: Dictionary) -> String:
	match n["kind"]:
		"passive":
			var p := get_passive(n["target"])
			var levels := TREE.filter(func(x): return x["kind"] == "passive" and x["target"] == n["target"]).size()
			return p["name"] if levels == 1 else "%s %s" % [p["name"], LEVEL_NUMERALS[int(n["level"]) - 1]]
		"chapter":
			return "Братство %s" % Names.of(Chapters.get_chapter(n["target"]).get("name", n["target"]))
		_:
			var card := CardFactory.create(n["target"])
			return card.display_title() if card else str(n["target"])

static func node_desc(n: Dictionary) -> String:
	match n["kind"]:
		"passive":
			var p := get_passive(n["target"])
			if not "%" in p["desc"]:
				return p["desc"]
			var lvl := int(n["level"])
			var text: String = p["desc"] % (lvl * int(p["value"]))
			return text + (" — всего с прошлыми уровнями" if lvl > 1 else "")
		"chapter":
			return "Братство для выбора в новом забеге Криспинцев.\n" + str(Chapters.get_chapter(n["target"]).get("desc", ""))
		"start_card":
			var card := CardFactory.create(n["target"])
			return "Стартовая карта — одна на выбор в руку в начале забега.\n" + (card.description if card else "")
		_:
			var card := CardFactory.create(n["target"])
			return "Карта начнёт выпадать в магазине.\n" + (card.description if card else "")

# Подпись закрытого ордена в окне выбора (ChapterSelectDialog): «Откройте в «Арсенале»: Командование · 15 Славы»
func chapter_lock_text(id: String) -> String:
	var n := _node_for("chapter", id)
	if n.is_empty():
		return ""
	return "Откройте в «Арсенале»: %s · %d Славы" % [get_branch(n["branch"]).get("name", ""), int(n["cost"])]

# -------------------------------------------------------
# ПАССИВКИ И СТАРТОВЫЕ КАРТЫ
# -------------------------------------------------------
static func get_passive(id: String) -> Dictionary:
	for p in PASSIVES:
		if p["id"] == id:
			return p
	return {}

# Уровень пассивки — сколько её узлов куплено; мета выключена — 0
func passive_level(id: String) -> int:
	if not active():
		return 0
	return TREE.filter(func(n): return n["kind"] == "passive" and n["target"] == id and owned_nodes.has(n["id"])).size()

# Суммарный бонус пассивки (уровень × value); мета выключена — 0
func passive_value(id: String) -> float:
	return passive_level(id) * float(get_passive(id).get("value", 0))

func _owns_start_card(card_id: String) -> bool:
	var n := _node_for("start_card", card_id)
	return not n.is_empty() and owned_nodes.has(n["id"])

func available_start_cards() -> Array[String]:
	var out: Array[String] = []
	if active():
		for n in TREE:
			if n["kind"] == "start_card" and owned_nodes.has(n["id"]):
				out.append(n["target"])
	return out

func select_start_card(card_id: String) -> void:
	_ensure_loaded()
	selected_start_card = card_id if _owns_start_card(card_id) else ""
	save_profile()

# Начало забега (BattleManager.reset_run): резервы Ордена и выбранная стартовая карта
func apply_run_start() -> void:
	run_minibosses = 0
	if not active():
		return
	EconomyManager.requisition += int(passive_value("reserves"))
	if selected_start_card != "" and _owns_start_card(selected_start_card):
		var card := CardFactory.equivalent(selected_start_card, RunManager.player_faction)
		if card:
			BattleManager.pending_cards.append(card)

# -------------------------------------------------------
# ОТКРЫТОЕ ДРЕВОМ — ордены и карты магазина
# -------------------------------------------------------
# Ордена без узла (Ultramarines, боги Хаоса) открыты сразу
func is_chapter_unlocked(id: String) -> bool:
	if not active():
		return true
	var n := _node_for("chapter", id)
	return n.is_empty() or owned_nodes.has(n["id"])

# Карта Хаоса открывается вместе со своей картой Космодесанта (CardFactory.base_id)
func is_card_unlocked(id: String) -> bool:
	if not active():
		return true
	var n := _node_for("card", CardFactory.base_id(id))
	return n.is_empty() or owned_nodes.has(n["id"])

# Бой выигран (BattleScene): счётчик мини-боссов забега — для Славы
func on_battle_won(battle_type: String) -> void:
	if battle_type == RunMapNode.MINIBOSS:
		run_minibosses += 1

# Слава за забег: победы, мини-боссы, главный босс × сложность (1 → ×0.75, 2 → ×1, … 7 → ×2.25)
func glory_for_run(wins: int, minibosses: int, boss_beaten: bool, difficulty: int) -> int:
	var base := wins * GLORY_PER_WIN + minibosses * GLORY_PER_MINIBOSS + (GLORY_PER_BOSS if boss_beaten else 0)
	return roundi(base * (0.75 + 0.25 * (difficulty - 1)))

# Конец забега (экран итога, сдача): Слава. {"glory", "total"}
func on_run_end(won: bool) -> Dictionary:
	# Победа над главным боссом идёт мимо дохода (EconomyManager.wins её не считает) — +1 бой
	var gained := glory_for_run(EconomyManager.wins + (1 if won else 0), run_minibosses, won, RunManager.difficulty)
	var result := {"glory": gained, "total": glory}
	if not active():
		return result
	glory += gained
	save_profile()
	result["total"] = glory
	changed.emit()
	return result

# -------------------------------------------------------
# СОХРАНЕНИЕ ЗАБЕГА (SaveManager.SYSTEMS) — только счётчик этого забега
# -------------------------------------------------------
func save_state() -> Dictionary:
	return {"run_minibosses": run_minibosses}

func load_state(d: Dictionary) -> void:
	run_minibosses = int(d.get("run_minibosses", 0))
