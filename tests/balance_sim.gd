extends SceneTree

# Симуляция баланса забега: для каждой волны 1..15 собирается армия, которую
# игрок может купить на накопленный доход (модель ниже), и прогоняется бой
# без рендера. Запуск:
#   godot --headless --path . -s tests/balance_sim.gd -- [стратегия] [прогонов] [с волны] [по волну]
# Стратегии: tactical (только Tactical), mixed (смешанная армия), elite (Rare/Epic), all (все).
#
# Забег целиком (реалистичнее, см. «ЗАБЕГ ЦЕЛИКОМ» ниже):
#   godot --headless --path . -s tests/balance_sim.gd -- campaign [стратегия|all] [забегов] [орден из Chapters или none] [сложность 1..7, по умолчанию Difficulty.DEFAULT]
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
# Забег целиком: приоритет карт (что игрок берёт из выпавшего набора магазина)
const CAMPAIGN_PRIORITY = {
	"tactical": ["tactical_squad", "blessed_armour", "battle_fury"],
	"mixed": ["tactical_squad", "plasma_generatorium", "assault_squad", "devastator_squad", "terminator_squad",
		"orbital_strike", "bolter_turret", "thunderfire_cannon", "barracks", "apothecarion", "apothecary", "dreadnought", "chaplain", "chapter_master",
		"fortress_wall", "librarian", "land_speeder", "emergency_reinforcements", "scout_squad",
		"iron_halo", "blessed_armour", "battle_fury", "combat_stimms", "chapter_banner"],
	"elite": ["terminator_squad", "devastator_squad", "dreadnought", "librarian", "chaplain",
		"apothecary", "chapter_master", "land_speeder", "orbital_strike", "tactical_squad",
		"iron_halo", "blessed_armour", "battle_fury", "combat_stimms", "chapter_banner"],
}
const CAMPAIGN_REROLLS: int = 2        # обновлений набора за магазин, если брать нечего
const CAMPAIGN_REROLL_RESERVE: int = 5 # обновляет, только если после него останется столько Req
const CAMPAIGN_SEED_BASE: int = 5000
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
	if args.size() > 0 and args[0] == "campaign":
		await _main_campaign(args)
		return
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
		d.squad_growth = UnitFactory.squad_growth_for(card)
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
	scene._on_start_pressed(false)
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

# -------------------------------------------------------
# ЗАБЕГ ЦЕЛИКОМ (campaign)
# -------------------------------------------------------
# Волны 1..15 подряд одним забегом, без сброса между боями: выжившие с их HP,
# возрождение павших отрядов, доход по итогу боя, HP цитадели, здания с
# уровнями и подкрепление — настоящей логикой игры (BattleScene._on_battle_ended,
# BattleManager, ShopManager). Магазин — случайные 4 карты от RunManager.rng:
# игрок берёт лучшее по CAMPAIGN_PRIORITY из выпавшего (неидеальный игрок),
# обновляет набор, только если брать нечего. Лечение слиянием не использует.
# Клетку королевства (волны расширения) покупает после карт, если остались Req —
# как в игре, где расширение идёт на расстановке после магазина.
# Забег кончается падением цитадели, боем с главным боссом или таймаутом боя.
func _main_campaign(args: Array) -> void:
	var strategy: String = args[1] if args.size() > 1 else "all"
	var runs: int = int(args[2]) if args.size() > 2 else 5
	root.get_node("RunManager").player_chapter = args[3] if args.size() > 3 and args[3] != "none" else ""
	root.get_node("RunManager").difficulty = int(args[4]) if args.size() > 4 else Difficulty.DEFAULT
	print("сложность: %s" % Difficulty.describe(root.get_node("RunManager").difficulty))
	for c in CardFactory.build_pool():
		cards[c.id] = c
	Engine.time_scale = TIME_SCALE
	var names = CAMPAIGN_PRIORITY.keys() if strategy == "all" else [strategy]
	for s in names:
		await _run_campaign(s, runs)
	Engine.time_scale = 1.0
	quit()

func _run_campaign(strategy: String, runs: int) -> void:
	var rm = root.get_node("RunManager")
	var sm = root.get_node("ShopManager")
	print("\n=== Забег целиком: %s, забегов: %d ===" % [strategy, runs])
	var reached: Array[int] = []
	var won_runs = 0
	var catch_ups = 0
	var hp_by_wave := {}
	for r in range(runs):
		bm.reset_run()
		rm.new_run(CAMPAIGN_SEED_BASE + r)
		var last_wave = 0
		var outcome = "?"
		print("\n-- забег %d (сид %d)" % [r + 1, CAMPAIGN_SEED_BASE + r])
		print("волна | тип      | Req до | клет | отр | здан | итог | цит. HP | Req после | армия")
		for wave in range(1, WAVES + 1):
			# Шаги по номеру волны: события (RunMapData.EVENT_AFTER_WAVES) сдвигают id шагов.
			# Сами события бот пропускает — баланс волн без их наград и цен
			var battle_id = _battle_node_id(rm, wave)
			rm.current_node_id = battle_id - 1   # магазин перед волной
			rm.current_completed = false
			sm.open_shop()
			if sm.catch_up_just_issued:
				catch_ups += 1
			var req_before = em.requisition
			var picked = _campaign_shop(strategy, wave)
			rm.current_node_id = battle_id   # бой волны
			rm.current_completed = false
			var w = await _campaign_battle()
			last_wave = wave
			hp_by_wave[wave] = hp_by_wave.get(wave, 0.0) + bm.citadel_hp
			print("%5d | %-8s | %6d | %4d | %3d | %4d | %4s | %7.0f | %9d | %s%s" % [
				wave, RunMapData.get_battle_type_for_wave(wave), req_before, bm.kingdom_tiles.size(),
				bm.player_units.size(), bm.player_buildings.size(),
				{0: "поб", 1: "пор", -1: "нич", -2: "тайм"}.get(w, "?"), bm.citadel_hp, em.requisition,
				_campaign_army_desc(), " + подкр. " + picked if picked != "" else ""])
			if w == -2:
				outcome = "таймаут боя на волне %d (итог не засчитан)" % wave
				break
			if bm.citadel_hp <= 0.0:
				outcome = "цитадель пала на волне %d" % wave
				break
			if wave == WAVES:
				outcome = "ПОБЕДА" if w == GameConstants.TEAM_PLAYER else "босс не побеждён"
				if w == GameConstants.TEAM_PLAYER:
					won_runs += 1
		reached.append(last_wave)
		print("итог: %s" % outcome)
	reached.sort()
	var avg_hp: Array[String] = []
	for wave in range(1, WAVES + 1):
		var alive = reached.filter(func(x): return x >= wave).size()
		if alive > 0:
			avg_hp.append("%d:%.0f" % [wave, hp_by_wave.get(wave, 0.0) / alive])
	print("\nСВОДКА %s: побед в забеге %d/%d; дошли до волн %s; подкреплений выдано %d" % [
		strategy, won_runs, runs, reached, catch_ups])
	print("средний HP цитадели после волны (среди дошедших): %s" % ", ".join(avg_hp))

# Покупки в магазине волны; возвращает id взятой карты подкрепления (или "")
func _campaign_shop(strategy: String, wave: int) -> String:
	var sm = root.get_node("ShopManager")
	var prio: Array = CAMPAIGN_PRIORITY[strategy]
	var picked = ""
	if sm.has_catch_up():
		var best = _campaign_best(sm.catch_up_offers, prio, false)
		if best >= 0:
			var card: CardData = sm.take_catch_up(best)
			_campaign_apply(card)
			picked = card.id
	var rerolls = 0
	while true:
		var i = _campaign_best(sm.current_offers, prio, true)
		if i >= 0:
			var card: CardData = sm.try_purchase(i)
			if card == null:
				break
			_campaign_apply(card)
			continue
		# Полезное есть, но не по карману — копит; полезного нет — обновляет набор
		if _campaign_best(sm.current_offers, prio, false) >= 0:
			break
		if rerolls < CAMPAIGN_REROLLS and em.requisition >= sm.get_reroll_cost() + CAMPAIGN_REROLL_RESERVE:
			sm.try_reroll()
			rerolls += 1
			continue
		break
	if wave % bm.EXPANSION_EVERY == 0:
		_campaign_buy_tile()
	return picked

func _campaign_buy_tile() -> void:
	for t in EXTRA_TILES:
		if not bm.kingdom_tiles.has(t):
			if bm.get_tile_cost() <= em.requisition:
				bm.try_buy_tile(t)
			return

# Индекс лучшей карты набора по приоритету; need_afford — только по карману
func _campaign_best(offers: Array, prio: Array, need_afford: bool) -> int:
	var sm = root.get_node("ShopManager")
	var best = -1
	var best_rank = 1 << 30
	for i in range(offers.size()):
		var card: CardData = offers[i]
		var rank = prio.find(card.id)
		if rank < 0 or rank >= best_rank or not _campaign_useful(card):
			continue
		if need_afford and sm.get_price(card) > em.requisition:
			continue
		best = i
		best_rank = rank
	return best

func _campaign_free_tiles() -> int:   # стена владений клетку не занимает
	return bm.kingdom_tiles.size() - bm.player_units.size() 		- bm.player_buildings.keys().filter(func(b): return b.building_type != "wall").size()

func _campaign_useful(card: CardData) -> bool:
	match card.card_type:
		"squad":
			if _campaign_free_tiles() > 0:
				return true
			return bm.player_units.any(func(d): return d.factory_id == card.unit_factory_id and d.can_merge_upgrade())
		"building":
			if card.building_type == "wall":   # стена владений — вне клеток
				return bm.get_wall_card() == null or bm.get_wall_card().can_level_up_building()
			if _campaign_free_tiles() > 0:
				return true
			return bm.player_buildings.keys().any(func(b): return b.id == card.id and b.can_level_up_building())
		"upgrade":
			return bm.player_units.any(func(d): return d.can_apply_upgrade(card) and not d.applied_upgrades.has(card.title))
		"event":
			match card.event_type:
				"reinforcements":
					return _campaign_free_tiles() > 0
				"orbital_strike":
					return bm.armed_events.is_empty()   # один удар на бой
	return false

# Карта сразу на поле: новая клетка, если есть, иначе улучшение такого же
func _campaign_apply(card: CardData) -> void:
	match card.card_type:
		"squad":
			if _campaign_free_tiles() > 0:
				var d = UnitFactory.create(card.unit_factory_id)
				d.squad_size = card.unit_count
				d.squad_growth = UnitFactory.squad_growth_for(card)
				var hp: Array[float] = []
				for j in range(card.unit_count):
					hp.append(1.0)
				d.saved_hp = hp
				bm.player_units.append(d)   # клетку назначит BattleScene
			else:
				for d in bm.player_units:
					if d.factory_id == card.unit_factory_id and d.can_merge_upgrade():
						d.apply_merge_upgrade()
						for j in range(d.squad_growth):   # новые бойцы уровня — как Squad.merge_upgrade
							d.saved_hp.append(1.0)
						return
		"building":
			if card.building_type == "wall":   # стена владений — вне клеток: первая строится, следующие — уровень
				var wall = bm.get_wall_card()
				if wall == null:
					bm.player_buildings[card] = bm.WALL_TILE
				else:
					wall.level_up_building()
				return
			if _campaign_free_tiles() > 0:
				bm.player_buildings[card] = _campaign_building_tile(card)
			else:
				for b in bm.player_buildings:
					if b.id == card.id and b.level_up_building():
						return
		"upgrade":
			for d in bm.player_units:
				if d.can_apply_upgrade(card) and not d.applied_upgrades.has(card.title):
					d.apply_upgrade(card)
					return
		"event":
			match card.event_type:
				"reinforcements":
					var rm = root.get_node("RunManager")
					var squad_card = CardFactory.random_squad_card(card.event_stats.get("rarity", "common"), rm.rng)
					_campaign_apply(squad_card)   # как карта отряда: на свободную клетку
				"orbital_strike":
					bm.armed_events.append(card.id)

# Здание — на последнюю свободную клетку (передние остаются отрядам)
# Свободная клетка под здание: с конца королевства; Казармы — рядом с наибольшим числом отрядов
# (по сторонам, BattleManager.NEIGHBOUR_TILES), как поставил бы игрок
func _campaign_building_tile(card: CardData = null) -> Vector2i:
	var used: Array = bm.player_buildings.values() + bm.player_placements.values()
	var best := Vector2i(-1, -1)
	var best_n := -1
	for k in range(bm.kingdom_tiles.size() - 1, -1, -1):
		var t: Vector2i = bm.kingdom_tiles[k]
		if used.has(t):
			continue
		if card == null or card.building_type != "barracks":
			return t
		var n = bm.player_placements.values().filter(func(p): return bm.NEIGHBOUR_TILES.has(p - t)).size()
		if n > best_n:
			best_n = n
			best = t
	return best if best_n >= 0 else bm.kingdom_tiles[-1]

func _campaign_army_desc() -> String:
	var counts := {}
	for d in bm.player_units:
		var key = "%s L%d" % [d.factory_id.replace("_marine", ""), d.squad_level]
		counts[key] = counts.get(key, 0) + 1
	for b in bm.player_buildings:
		var key = "%s L%d" % [b.id, b.building_level]
		counts[key] = counts.get(key, 0) + 1
	var parts: Array[String] = []
	for key in counts:
		parts.append("%s×%d" % [key, counts[key]])
	return ", ".join(parts)

# Бой текущего шага без сброса состояния; итог обрабатывает сама BattleScene
func _campaign_battle() -> int:
	ended = false
	winner = -99
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	bm.battle_ended.connect(_on_end)
	scene._on_start_pressed(false)
	var t0 = game_time
	var so = root.get_node("SoldierRegistry")
	while not ended and game_time - t0 < MAX_GAME_SECONDS:
		# Орудие игрока (Thunderfire Cannon): бот бьёт в центр строя врага, как только готово
		if not so.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY).is_empty():
			scene.fire_artillery(so.get_team_center(GameConstants.TEAM_ENEMY))
		await process_frame
	bm.battle_ended.disconnect(_on_end)
	var w = winner if ended else -2
	# Таймаут: итога не было — флаг «бой идёт» снимаем сами (иначе следующая
	# сцена решит, что загружено сохранение посреди боя)
	bm.battle_in_progress = false
	bm.phase = bm.BattlePhase.IDLE
	root.get_node("SquadRegistry").clear()
	root.get_node("SoldierRegistry").clear()
	# Переход в магазин сцена делает таймером (2 с игрового времени — при
	# TIME_SCALE это доли реальной секунды): удаляем сразу, связь снимается
	if is_instance_valid(scene):
		root.remove_child(scene)
		scene.free()
	current_scene = null
	await process_frame
	return w

# id боевого шага волны в цепочке забега
func _battle_node_id(rm, wave: int) -> int:
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == wave:
			return n.id
	return -1
