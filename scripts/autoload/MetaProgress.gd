extends Node

# Мета-прогрессия между забегами (решение пользователя 16.10.2026, смешанная схема):
# - Слава — валюта за каждый забег (и проигранный): бои, мини-боссы, главный босс × сложность;
#   тратится в «Арсенале» (ArsenalDialog) на пассивки на все забеги и стартовые карты;
# - достижения по прогрессу (лучшая волна, побед всего, мини-боссов всего, выигранных забегов)
#   открывают ордены и часть карт магазина.
# Хранится в профиле игрока (SaveManager.profile_path, секция "meta"). Сохранение выключено
# (SaveManager.enabled = false: тесты, balance_sim) — всё открыто, пассивок нет, ничего не пишется:
# прежний баланс и тесты не меняются. Цифры — черновые, на одобрение.

const SECTION: String = "meta"
const GLORY_PER_WIN: int = 1
const GLORY_PER_MINIBOSS: int = 3
const GLORY_PER_BOSS: int = 10

# Пассивки: value — прибавка за уровень, costs — цена каждого уровня в Славе
const PASSIVES = [
	{"id": "reserves", "name": "Резервы Ордена", "desc": "+%d Req в начале забега", "value": 3, "costs": [10, 20, 35]},
	{"id": "walls", "name": "Освящённые стены", "desc": "Щит цитадели +%d в каждом бою", "value": 100, "costs": [15, 30, 50]},
	{"id": "veterans", "name": "Ветеранская выучка", "desc": "+%d%% HP всем своим бойцам", "value": 5, "costs": [20, 40]},
	{"id": "munitorum", "name": "Связи в Муниторуме", "desc": "Первое обновление магазина за волну — бесплатно", "value": 1, "costs": [25]},
]
# Стартовые карты: открываются за Славу, одна выбирается при новом забеге (в руку на старте)
const START_CARDS = [
	{"card": "scout_squad", "cost": 5},
	{"card": "fortress_wall", "cost": 10},
	{"card": "apothecary", "cost": 15},
	{"card": "bolter_turret", "cost": 20},
	{"card": "terminator_squad", "cost": 30},
]
# Достижения: stat ≥ value — открыто. Ордена без записи открыты сразу
const STAT_NAMES = {"best_wave": "лучшая волна", "total_wins": "побед всего",
	"minibosses_total": "мини-боссов всего", "runs_won": "выигранных забегов"}
const CHAPTER_UNLOCKS = {
	"blood_angels": {"stat": "best_wave", "value": 5, "text": "Дойдите до волны 5"},
	"space_wolves": {"stat": "best_wave", "value": 8, "text": "Дойдите до волны 8"},
	"imperial_fists": {"stat": "minibosses_total", "value": 2, "text": "Победите 2 мини-боссов"},
	"salamanders": {"stat": "runs_won", "value": 1, "text": "Выиграйте забег"},
}
const CARD_UNLOCKS = {
	"orbital_strike": {"stat": "minibosses_total", "value": 3, "text": "Победите 3 мини-боссов"},
	"plasma_generatorium": {"stat": "total_wins", "value": 10, "text": "Выиграйте 10 боёв"},
	"chapter_banner": {"stat": "best_wave", "value": 12, "text": "Дойдите до волны 12"},
	"apothecarion": {"stat": "total_wins", "value": 25, "text": "Выиграйте 25 боёв"},
}

signal changed

var glory: int = 0
var passive_levels: Dictionary = {}     # id → уровень
var owned_start_cards: Array[String] = []
var selected_start_card: String = ""    # последняя выбранная (НОВЫЙ ЗАБЕГ с экрана итога берёт её же)
var stats: Dictionary = {"best_wave": 0, "total_wins": 0, "minibosses_total": 0, "runs_won": 0}
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
	passive_levels.clear()
	owned_start_cards.clear()
	selected_start_card = ""
	stats = {"best_wave": 0, "total_wins": 0, "minibosses_total": 0, "runs_won": 0}
	var cfg := ConfigFile.new()
	if cfg.load(SaveManager.profile_path) != OK:
		return
	glory = int(cfg.get_value(SECTION, "glory", 0))
	passive_levels = cfg.get_value(SECTION, "passives", {}).duplicate()
	for id in cfg.get_value(SECTION, "start_cards", []):
		owned_start_cards.append(str(id))
	selected_start_card = str(cfg.get_value(SECTION, "selected_start_card", ""))
	var saved: Dictionary = cfg.get_value(SECTION, "stats", {})
	for k in stats:
		stats[k] = int(saved.get(k, 0))

func save_profile() -> void:
	if not active():
		return
	var cfg := ConfigFile.new()
	cfg.load(SaveManager.profile_path)   # секция сложности (SaveManager) остаётся
	cfg.set_value(SECTION, "glory", glory)
	cfg.set_value(SECTION, "passives", passive_levels)
	cfg.set_value(SECTION, "start_cards", Array(owned_start_cards))
	cfg.set_value(SECTION, "selected_start_card", selected_start_card)
	cfg.set_value(SECTION, "stats", stats)
	cfg.save(SaveManager.profile_path)

# -------------------------------------------------------
# ПАССИВКИ И СТАРТОВЫЕ КАРТЫ
# -------------------------------------------------------
static func get_passive(id: String) -> Dictionary:
	for p in PASSIVES:
		if p["id"] == id:
			return p
	return {}

func passive_level(id: String) -> int:
	return int(passive_levels.get(id, 0)) if active() else 0

func get_glory() -> int:
	_ensure_loaded()
	return glory

# Суммарный бонус пассивки (уровень × value); мета выключена — 0
func passive_value(id: String) -> float:
	return passive_level(id) * float(get_passive(id).get("value", 0))

# Цена следующего уровня; -1 — максимум
func next_passive_cost(id: String) -> int:
	_ensure_loaded()
	var costs: Array = get_passive(id).get("costs", [])
	var lvl := int(passive_levels.get(id, 0))
	return costs[lvl] if lvl < costs.size() else -1

func buy_passive(id: String) -> bool:
	_ensure_loaded()
	var cost := next_passive_cost(id)
	if cost < 0 or glory < cost:
		return false
	glory -= cost
	passive_levels[id] = int(passive_levels.get(id, 0)) + 1
	save_profile()
	changed.emit()
	return true

static func start_card_cost(card_id: String) -> int:
	for s in START_CARDS:
		if s["card"] == card_id:
			return s["cost"]
	return -1

func buy_start_card(card_id: String) -> bool:
	_ensure_loaded()
	var cost := start_card_cost(card_id)
	if cost < 0 or owned_start_cards.has(card_id) or glory < cost:
		return false
	glory -= cost
	owned_start_cards.append(card_id)
	save_profile()
	changed.emit()
	return true

func available_start_cards() -> Array[String]:
	var out: Array[String] = []
	if active():
		out.assign(owned_start_cards)
	return out

func select_start_card(card_id: String) -> void:
	_ensure_loaded()
	selected_start_card = card_id if owned_start_cards.has(card_id) else ""
	save_profile()

# Начало забега (BattleManager.reset_run): резервы Ордена и выбранная стартовая карта
func apply_run_start() -> void:
	run_minibosses = 0
	if not active():
		return
	EconomyManager.requisition += int(passive_value("reserves"))
	if selected_start_card != "" and owned_start_cards.has(selected_start_card):
		var card := CardFactory.create(selected_start_card)
		if card:
			BattleManager.pending_cards.append(card)

# -------------------------------------------------------
# ДОСТИЖЕНИЯ
# -------------------------------------------------------
func _reached(rule: Dictionary) -> bool:
	return int(stats.get(rule["stat"], 0)) >= int(rule["value"])

func is_chapter_unlocked(id: String) -> bool:
	return not active() or not CHAPTER_UNLOCKS.has(id) or _reached(CHAPTER_UNLOCKS[id])

func is_card_unlocked(id: String) -> bool:
	return not active() or not CARD_UNLOCKS.has(id) or _reached(CARD_UNLOCKS[id])

# «Дойдите до волны 8 (лучшая волна 5/8)»
func unlock_text(rule: Dictionary) -> String:
	return "%s (%s %d/%d)" % [rule["text"], STAT_NAMES.get(rule["stat"], rule["stat"]),
		mini(int(stats.get(rule["stat"], 0)), int(rule["value"])), int(rule["value"])]

# Названия того, что открылось бы при новых stats (сравнение «до / после»)
func _unlocked_names() -> Array[String]:
	var out: Array[String] = []
	for id in CHAPTER_UNLOCKS:
		if _reached(CHAPTER_UNLOCKS[id]):
			out.append("орден %s" % Chapters.get_chapter(id).get("name", id))
	for id in CARD_UNLOCKS:
		if _reached(CARD_UNLOCKS[id]):
			var card := CardFactory.create(id)
			out.append("карта %s" % (card.title if card else id))
	return out

# Бой выигран (BattleScene): статистика и что открылось (названия) — показать в итоге боя
func on_battle_won(wave: int, battle_type: String) -> Array[String]:
	if battle_type == RunMapNode.MINIBOSS:
		run_minibosses += 1
	if not active():
		return [] as Array[String]
	var before := _unlocked_names()
	stats["total_wins"] = int(stats["total_wins"]) + 1
	stats["best_wave"] = maxi(int(stats["best_wave"]), wave)
	if battle_type == RunMapNode.MINIBOSS:
		stats["minibosses_total"] = int(stats["minibosses_total"]) + 1
	save_profile()
	return _new_since(before)

func _new_since(before: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for n in _unlocked_names():
		if not before.has(n):
			out.append(n)
	return out

# Слава за забег: победы, мини-боссы, главный босс × сложность (1 → ×0.75, 2 → ×1, … 7 → ×2.25)
func glory_for_run(wins: int, minibosses: int, boss_beaten: bool, difficulty: int) -> int:
	var base := wins * GLORY_PER_WIN + minibosses * GLORY_PER_MINIBOSS + (GLORY_PER_BOSS if boss_beaten else 0)
	return roundi(base * (0.75 + 0.25 * (difficulty - 1)))

# Конец забега (экран итога, сдача): Слава и открытия. {"glory", "total", "unlocks"}
func on_run_end(won: bool) -> Dictionary:
	# Победа над главным боссом идёт мимо дохода (EconomyManager.wins её не считает) — +1 бой
	var gained := glory_for_run(EconomyManager.wins + (1 if won else 0), run_minibosses, won, RunManager.difficulty)
	var result := {"glory": gained, "total": glory, "unlocks": [] as Array[String]}
	if not active():
		return result
	var before := _unlocked_names()
	glory += gained
	if won:
		stats["runs_won"] = int(stats["runs_won"]) + 1
	save_profile()
	result["total"] = glory
	result["unlocks"] = _new_since(before)
	changed.emit()
	return result

# -------------------------------------------------------
# СОХРАНЕНИЕ ЗАБЕГА (SaveManager.SYSTEMS) — только счётчик этого забега
# -------------------------------------------------------
func save_state() -> Dictionary:
	return {"run_minibosses": run_minibosses}

func load_state(d: Dictionary) -> void:
	run_minibosses = int(d.get("run_minibosses", 0))
