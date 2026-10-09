extends SceneTree

# Симуляция баланса забега: для каждой волны 1..15 собирается армия, которую
# игрок может купить на накопленный доход (модель ниже), и прогоняется бой
# без рендера. Запуск:
#   godot --headless --path . -s tests/balance_sim.gd -- [стратегия] [прогонов] [с волны] [по волну]
# Стратегии: tactical (только Tactical), mixed (смешанная армия), elite (Rare/Epic), all (все).
#
# Модель игрока (оптимистичная — верхняя оценка силы):
#   * каждую волну выигрывает, бонус к доходу BONUS_NORMAL / BONUS_BOSS;
#   * тратит весь Requisition, магазин всегда даёт нужные карты;
#   * армия каждую волну свежая (потери между волнами не учитываются);
#   * на волнах расширения покупает 1 клетку.

const WAVES: int = 15
const BONUS_NORMAL: int = 4   # синергия marine +2..4, «без потерь» — редко
const BONUS_BOSS: int = 8     # мини-босс: элитные враги +3 каждый, кап 8
const TIME_SCALE: float = 20.0
const MAX_GAME_SECONDS: float = 300.0

# Порядок, в котором стратегия заполняет клетки (id карт CardFactory)
const STRATEGIES = {
	"tactical": ["tactical_squad"],
	"mixed": ["tactical_squad", "assault_squad", "devastator_squad", "tactical_squad",
		"terminator_squad", "apothecary", "dreadnought", "chaplain", "chapter_master",
		"tactical_squad", "assault_squad", "devastator_squad", "librarian", "tactical_squad",
		"terminator_squad", "land_speeder"],
	# В основном Rare/Epic, Tactical — только если на дорогие не хватает
	"elite": ["terminator_squad", "devastator_squad", "dreadnought", "librarian",
		"chaplain", "apothecary", "chapter_master", "land_speeder", "terminator_squad",
		"devastator_squad", "dreadnought", "tactical_squad"],
}
# Карты-улучшения: по одной каждого вида на отряд
const UPGRADES: Array[String] = ["blessed_armour", "battle_fury"]
# Клетки сверх стартовых 3×3 — в порядке покупки (рамка 4×4)
const EXTRA_TILES: Array[Vector2i] = [Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2),
	Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]

var ended := false
var winner := -99
var game_time := 0.0
var cards := {}
var first_wave := 1
var last_wave := WAVES
# Autoload-ы в скрипте -s не видны по имени при компиляции — берём узлы
var em: Node
var bm: Node

func _initialize() -> void:
	# Скорость боя игрока (GameSettings) не должна влиять на тест
	root.get_node("GameSettings").battle_speed = 1.0
	# Бои сами пишут сохранение — в тестах выключаем, чтобы не затереть сохранение игрока
	root.get_node("SaveManager").enabled = false
	_main()

func _process(delta: float) -> bool:
	game_time += delta
	return false

func _on_end(w: int) -> void:
	ended = true
	winner = w

func _main() -> void:
	var args = OS.get_cmdline_user_args()
	em = root.get_node("EconomyManager")
	bm = root.get_node("BattleManager")
	var strategy: String = args[0] if args.size() > 0 else "all"
	var runs: int = int(args[1]) if args.size() > 1 else 3
	first_wave = int(args[2]) if args.size() > 2 else 1
	last_wave = int(args[3]) if args.size() > 3 else WAVES
	for c in CardFactory.build_pool():
		cards[c.id] = c
	Engine.time_scale = TIME_SCALE
	var names = STRATEGIES.keys() if strategy == "all" else [strategy]
	for s in names:
		await _run_strategy(s, runs)
	Engine.time_scale = 1.0
	quit()

# -------------------------------------------------------
# ЭКОНОМИКА
# -------------------------------------------------------
func _income(wave: int) -> int:
	var t = RunMapData.get_battle_type_for_wave(wave)
	var bonus = BONUS_BOSS if t != RunMapNode.BATTLE else BONUS_NORMAL
	return em.calculate_wave_income(wave, bonus)

# Весь Requisition к началу волны и число клеток королевства
func _budget(wave: int) -> Dictionary:
	var req = em.STARTING_REQUISITION
	var tiles = 9
	var bought = 0
	for w in range(1, wave + 1):
		if w > 1:
			req += _income(w - 1)
		if w % bm.EXPANSION_EVERY == 0 and bought < EXTRA_TILES.size():
			var cost = bm.TILE_BASE_COST + bought * bm.TILE_COST_STEP
			if req >= cost:
				req -= cost
				bought += 1
				tiles += 1
	# Расширение раньше тратит те же деньги, что армия: считаем только накопленное
	return {"req": req, "tiles": tiles, "bought": bought}

# -------------------------------------------------------
# АРМИЯ
# -------------------------------------------------------
# Возвращает {"units": Array[UnitData], "spent": int, "desc": String}
func _build_army(strategy: String, budget: int, tiles: int) -> Dictionary:
	var order: Array = STRATEGIES[strategy]
	var units: Array[UnitData] = []
	var ids: Array[String] = []
	var left = budget
	# 1) Заполняем клетки
	var i = 0
	var skipped = 0
	while units.size() < tiles and skipped < order.size():
		var card: CardData = cards[order[i % order.size()]]
		i += 1
		if card.cost > left:
			skipped += 1
			continue
		skipped = 0
		left -= card.cost
		var d = UnitFactory.create(card.unit_factory_id)
		d.squad_size = card.unit_count
		units.append(d)
		ids.append(card.id)
	# 2) Слияния (уровень до MAX) и улучшения — по кругу, пока хватает денег
	var progress = true
	while progress:
		progress = false
		for k in range(units.size()):
			var d = units[k]
			var card: CardData = cards[ids[k]]
			if d.can_merge_upgrade() and card.cost <= left:
				left -= card.cost
				d.apply_merge_upgrade()
				progress = true
		if progress:
			continue
		for up_id in UPGRADES:
			var up: CardData = cards[up_id]
			for d in units:
				if up.cost <= left and d.can_apply_upgrade(up) and not d.applied_upgrades.has(up.title):
					left -= up.cost
					d.apply_upgrade(up)
					progress = true
	for d in units:
		var hp: Array[float] = []
		for j in range(d.squad_size):
			hp.append(1.0)
		d.saved_hp = hp
	var counts := {}
	for k in range(units.size()):
		var key = "%s L%d" % [ids[k].replace("_squad", ""), units[k].squad_level]
		counts[key] = counts.get(key, 0) + 1
	var parts: Array[String] = []
	for key in counts:
		parts.append("%s×%d" % [key, counts[key]])
	return {"units": units, "spent": budget - left, "desc": ", ".join(parts)}

# -------------------------------------------------------
# БОЙ
# -------------------------------------------------------
func _run_strategy(strategy: String, runs: int) -> void:
	print("\n=== Стратегия: %s, прогонов на волну: %d ===" % [strategy, runs])
	print("волна | тип      | Req  | клет | отр | бойц игрока | врагов: отр/бойц/HP×  | побед | выжило | урон цитадели | время, с")
	for wave in range(first_wave, last_wave + 1):
		var b = _budget(wave)
		var wins = 0
		var survived = 0.0
		var cit_dmg = 0.0
		var time_sum = 0.0
		var army_desc = ""
		var p_soldiers = 0
		var p_squads = 0
		var e_info = ""
		for r in range(runs):
			var army = _build_army(strategy, b["req"], b["tiles"])
			army_desc = army["desc"]
			p_squads = army["units"].size()
			var res = await _battle(wave, army["units"], b["bought"])
			p_soldiers = res["p_start"]
			e_info = res["e_info"]
			if res["winner"] == GameConstants.TEAM_PLAYER:
				wins += 1
			survived += res["survived"]
			cit_dmg += res["citadel_dmg"]
			time_sum += res["time"]
		print("%5d | %-8s | %4d | %4d | %3d | %11d | %-21s | %d/%d   | %5.0f%% | %13.0f | %6.1f" % [
			wave, RunMapData.get_battle_type_for_wave(wave), b["req"], b["tiles"],
			p_squads, p_soldiers, e_info, wins, runs,
			survived / runs * 100.0, cit_dmg / runs, time_sum / runs])
		print("      армия: %s" % army_desc)

func _battle(wave: int, units: Array[UnitData], bought: int) -> Dictionary:
	var rm = root.get_node("RunManager")
	bm.reset_run()
	for k in range(bought):
		bm.kingdom_tiles.append(EXTRA_TILES[k])
	rm.new_run(1000 + wave)
	# Текущий шаг — бой нужной волны
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == wave:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	em.round_number = wave
	bm.player_units = units
	ended = false
	winner = -99
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var sr = root.get_node("SquadRegistry")
	var so = root.get_node("SoldierRegistry")
	var enemies = so.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY)
	var e_squads = sr.get_alive_squads_of_team(GameConstants.TEAM_ENEMY).size()
	var e_info = "%d/%d/%.2f" % [e_squads, enemies.size(), EnemyWaves.get_stat_mult(wave)]
	bm.battle_ended.connect(_on_end)
	scene._on_start_pressed()
	var p_start = scene.player_soldiers_at_start
	var t0 = game_time
	while not ended and game_time - t0 < MAX_GAME_SECONDS:
		await process_frame
	# Реестры BattleScene очищает сама в конце боя — считаем по узлам отрядов
	var p_alive = 0
	# (классы Squad/Soldier здесь не упоминаем: скрипт -s компилируется до autoload-ов;
	# павшие бойцы удаляются из squad.soldiers)
	for sq in scene.units_container.get_children():
		if sq.get("soldiers") != null and sq.get("team") == GameConstants.TEAM_PLAYER:
			p_alive += sq.soldiers.size()
	var res = {
		"winner": winner if ended else -2,
		"p_start": p_start,
		"survived": float(p_alive) / maxf(p_start, 1.0),
		"citadel_dmg": bm.CITADEL_MAX_HP - bm.citadel_hp,
		"time": game_time - t0,
		"e_info": e_info,
	}
	bm.battle_ended.disconnect(_on_end)
	# После боя сцена может сама уйти в магазин — сбрасываем без ожидания
	bm.phase = bm.BattlePhase.IDLE
	sr.clear()
	so.clear()
	if is_instance_valid(scene):
		scene.queue_free()
	current_scene = null
	await process_frame
	return res
