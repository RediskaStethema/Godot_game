extends Node

# -------------------------------------------------------
# КОНСТАНТЫ И СОСТОЯНИЕ
# -------------------------------------------------------

# Фиксированный тик берём из GameConstants —
# одно значение используется везде, меняем в одном месте
# Добавь переменную

var player_placements: Dictionary = {}
# Рука — карты, ещё не выложенные на поле (pending_cards). Переносятся между раундами.
const MAX_HAND_SIZE: int = 10
const FIXED_TICK: float = GameConstants.FIXED_TICK
var pending_cards: Array[CardData] = []

# Королевство: открытые клетки для расстановки. Живут весь забег.
# Каждую EXPANSION_EVERY-ю волну (3, 6, 9, 12, 15) во время расстановки можно
# докупать соседние клетки; цена растёт с каждой купленной.
const START_KINGDOM_SIZE = Vector2i(3, 3)
const EXPANSION_EVERY: int = 3
const TILE_BASE_COST: int = 6
const TILE_COST_STEP: int = 2
var kingdom_tiles: Array[Vector2i] = []
var tiles_bought: int = 0

# Цитадель: HP живёт весь забег. Если армия игрока погибла, начинается штурм —
# бой цитадели с уцелевшими врагами: враги бьют её своими атаками, она стреляет
# в ответ (статы — в Citadel.gd). Все враги убиты — волна отбита; HP = 0 — забег окончен.
const CITADEL_MAX_HP: float = 1000.0
var citadel_hp: float = CITADEL_MAX_HP
var citadel: Node2D = null          # цитадель текущего боя (ставит BattleScene)
var siege_started: bool = false     # армия игрока пала, враги штурмуют цитадель
# Игрок сдался в текущем бою: подписчик battle_ended заканчивает забег
var surrendered: bool = false
# «В БОЙ» нажата, итога ещё нет. Сохраняется: «Продолжить» ставит армию как была
# и сразу запускает бой (без повторной расстановки)
var battle_in_progress: bool = false
# Щит цитадели на текущий бой (Fortress Wall): урон штурма сначала снимает его
var citadel_shield: float = 0.0
# Подкрепление (catch-up, решение пользователя): цитадель получила урон в бою и
# после него у неё меньше CATCH_UP_HP_RATIO от максимума — в следующем магазине
# выбор одной Common карты из нескольких бесплатно (ShopManager.open_shop
# забирает флаг). Не копится: пока выбор не взят, новый не выдаётся.
const CATCH_UP_HP_RATIO: float = 0.5
var catch_up_pending: bool = false
var _citadel_hp_at_start: float = CITADEL_MAX_HP
# Последствие события (RunEvents, эффект enemy_hp) на следующий бой: HP врагов ×, подпись для шапки.
# Сохраняется; сбрасывает BattleScene по итогу боя
var next_battle_enemy_hp: float = 1.0
var next_battle_note: String = ""

# Заряженные карты-события (id карт): разыгрываются на расстановке, срабатывают
# в начале боя (fire_armed_events). Сохраняются — «Продолжить» их не теряет
var armed_events: Array[String] = []

# Здания: стоят между раундами на своих клетках (CardData → Vector2i)
var player_buildings: Dictionary = {}
var buildings: Array = []           # узлы Building текущего боя (ставит BattleScene)
# Стена вокруг владений (карта building_type "wall") клетку не занимает: в player_buildings — на WALL_TILE вне поля
const WALL_TILE := Vector2i(-100, -100)
var kingdom_wall: Node2D = null     # KingdomWall текущего боя (ставит BattleScene), null — стены нет
var projectiles: Array = []         # снаряды в полёте (Projectile.launch) — тикают в бою, урон при попадании

signal citadel_hp_changed(hp: float)
signal citadel_destroyed
# нам нужно различать "ещё не начался" и "уже закончился"
enum BattlePhase { IDLE, RUNNING, FINISHED }
var player_units: Array[UnitData] = []
var phase: BattlePhase = BattlePhase.IDLE
var winner_team: int = -1       # 0 = игрок, 1 = враг, -1 = ничья
var _accumulator: float = 0.0   # накопитель времени между тиками

# Сигналы для UI и GameManager —
# они подпишутся и будут знать о событиях боя
signal battle_started
signal battle_ended(winner_team: int)

# -------------------------------------------------------
# ЗАПУСК И ОСТАНОВКА
# -------------------------------------------------------

func start_battle() -> void:
	if phase == BattlePhase.RUNNING:
		return  # защита от двойного запуска
	damage_by_unit.clear()

	phase = BattlePhase.RUNNING
	winner_team = -1
	_accumulator = 0.0
	siege_started = false
	surrendered = false
	_citadel_hp_at_start = citadel_hp
	clear_projectiles()
	emit_signal("battle_started")
	print("BattleManager: бой начался")

# Схватка идёт (после «В БОЙ», до итога) — выход из неё предлагает сдаться
func is_battle_running() -> bool:
	return phase == BattlePhase.RUNNING

# Сдача посреди боя (решение пользователя) — конец забега: battle_ended
# (поражение) с флагом surrendered, подписчик (BattleScene) синхронно
# показывает итог и удаляет сохранение.
func surrender() -> void:
	if phase != BattlePhase.RUNNING:
		return
	phase = BattlePhase.FINISHED
	winner_team = GameConstants.TEAM_ENEMY
	surrendered = true
	clear_projectiles()
	_stand_down_soldiers()
	print("BattleManager: игрок сдался")
	emit_signal("battle_ended", winner_team)

# Итог боя: выжившие обеих сторон в стойку — иначе застыли бы на кадре выстрела;
# у победившей стороны — поза победы, если она есть в листе (Дредноут)
func _stand_down_soldiers(winner: int = -1) -> void:
	for s in SoldierRegistry.get_all_alive_soldiers().duplicate():
		s.stand_down(s.team == winner)

func stop_battle() -> void:
	phase = BattlePhase.IDLE
	surrendered = false
	clear_projectiles()
	SquadRegistry.clear()
	SoldierRegistry.clear()

# -------------------------------------------------------
# ГЛАВНЫЙ ЦИКЛ
# -------------------------------------------------------

# _process вызывается каждый кадр — но мы используем
# его только как источник времени. Реальная логика боя
# происходит в _battle_tick() по фиксированному расписанию.
func _process(delta: float) -> void:
	if phase != BattlePhase.RUNNING:
		return

	# Накапливаем время. Когда накопилось достаточно —
	# делаем тик и вычитаем. Остаток переносится на следующий кадр.
	# Это называется "accumulator pattern" — стандартный подход
	# для фиксированного шага симуляции.
	_accumulator += delta
	# Бой мог закончиться на одном из тиков кадра — дальше не тикаем,
	# иначе при длинном кадре battle_ended придёт несколько раз (двойной доход)
	while _accumulator >= FIXED_TICK and phase == BattlePhase.RUNNING:
		_battle_tick()
		_accumulator -= FIXED_TICK

# -------------------------------------------------------
# ТИК БОЯ
# -------------------------------------------------------

func _battle_tick() -> void:
	SoldierRegistry.begin_tick()
	# Тикаем все живые отряды
	var squads = SquadRegistry.get_all_alive_squads()
	for squad in squads:
		squad.tick(FIXED_TICK)
	for b in buildings:
		if is_instance_valid(b):
			b.tick(FIXED_TICK)
	if siege_started and has_citadel():
		citadel.tick(FIXED_TICK)
	_tick_projectiles()
	SoldierRegistry.end_tick()
	_check_battle_end()

# Снаряды летят после выстрелов этого тика; попавшие и сгинувшие со сценой — из списка
func _tick_projectiles() -> void:
	for p in projectiles.duplicate():
		if is_instance_valid(p):
			p.tick(FIXED_TICK)
	projectiles = projectiles.filter(func(p): return is_instance_valid(p) and not p.finished)

# Бой кончился — снаряды в полёте больше не попадут, убираем с поля
func clear_projectiles() -> void:
	for p in projectiles:
		if is_instance_valid(p):
			p.queue_free()
	projectiles.clear()

# Урон отрядов игрока за бой (UnitData → урон по HP: без щита и перебора сверх HP цели) — итоги боя.
# По UnitData, а не по узлу: отряд, павший целиком, тоже в итогах. Яд и огонь не считаются
var damage_by_unit: Dictionary = {}
func credit_damage(source, amount: float) -> void:
	if amount <= 0.0 or not is_instance_valid(source) or source.team != GameConstants.TEAM_PLAYER:
		return
	damage_by_unit[source.data] = damage_by_unit.get(source.data, 0.0) + amount

# Лучший отряд по урону за бой: [UnitData, урон] или [] — никто не нанёс
func top_damage_dealer() -> Array:
	var best = null
	for d in damage_by_unit:
		if best == null or damage_by_unit[d] > damage_by_unit[best]:
			best = d
	return [best, damage_by_unit[best]] if best != null else []

# Доля FIXED_TICK, накопленная с последнего тика (0..1) — для плавной отрисовки между тиками
func get_tick_alpha() -> float:
	return clampf(_accumulator / FIXED_TICK, 0.0, 1.0)

func _check_battle_end() -> void:
	var team0_alive = SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER).size() > 0
	var team1_alive = SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_ENEMY).size() > 0

	# Цитадель тоже сторона игрока: пока она стоит, игрок не проиграл
	var citadel_alive = has_citadel() and citadel_hp > 0.0
	var player_alive = team0_alive or citadel_alive
	if team1_alive and player_alive:
		# Армия пала, цитадель стоит — штурм: бой цитадели с врагами
		if not team0_alive and not siege_started:
			siege_started = true
			print("BattleManager: армия пала — штурм цитадели")
		return

	phase = BattlePhase.FINISHED
	clear_projectiles()
	if player_alive and not team1_alive:
		winner_team = GameConstants.TEAM_PLAYER   # в т.ч. цитадель отбила штурм
	elif team1_alive:
		winner_team = GameConstants.TEAM_ENEMY
	else:
		winner_team = -1
	_stand_down_soldiers(winner_team)
	_check_catch_up()

	print("BattleManager: бой закончен, победитель — команда ", winner_team)
	emit_signal("battle_ended", winner_team)

# -------------------------------------------------------
# КОРОЛЕВСТВО
# -------------------------------------------------------
func _ready() -> void:
	reset_kingdom()

func reset_kingdom() -> void:
	kingdom_tiles.clear()
	tiles_bought = 0
	for row in range(START_KINGDOM_SIZE.y):
		for col in range(START_KINGDOM_SIZE.x):
			kingdom_tiles.append(Vector2i(col, row))

# -------------------------------------------------------
# ЦИТАДЕЛЬ
# -------------------------------------------------------
func has_citadel() -> bool:
	return is_instance_valid(citadel)

func has_kingdom_wall() -> bool:
	return kingdom_wall != null and is_instance_valid(kingdom_wall)

# Карта стены владений в забеге (null — не построена)
func get_wall_card() -> CardData:
	for card in player_buildings:
		if card.building_type == "wall":
			return card
	return null

func damage_citadel(amount: float) -> void:
	if citadel_hp <= 0.0:
		return
	var absorbed = minf(citadel_shield, amount)
	citadel_shield -= absorbed
	citadel_hp = maxf(citadel_hp - (amount - absorbed), 0.0)
	emit_signal("citadel_hp_changed", citadel_hp)
	if citadel_hp <= 0.0:
		print("BattleManager: цитадель пала")
		emit_signal("citadel_destroyed")

# Ремонт цитадели (события карты забега). Возвращает, сколько HP восстановлено.
func heal_citadel(amount: float) -> float:
	var before = citadel_hp
	citadel_hp = minf(citadel_hp + maxf(amount, 0.0), CITADEL_MAX_HP)
	emit_signal("citadel_hp_changed", citadel_hp)
	return citadel_hp - before

# После боя: Кузня Вулкана чинит цитадель (статы по уровню и ордену); цитадель пала — не чинит
func repair_from_forges() -> float:
	if citadel_hp <= 0.0:
		return 0.0
	var amount := 0.0
	for card in player_buildings:
		if card.building_type == "vulkan_forge":
			amount += Chapters.apply_building_stats(card.get_building_stats(), RunManager.player_chapter).get("repair", 0.0)
	return heal_citadel(amount) if amount > 0.0 else 0.0

# Итог боя: цитадель ранена и ниже порога — подкрепление в следующем магазине
func _check_catch_up() -> void:
	if citadel_hp > 0.0 and citadel_hp < _citadel_hp_at_start \
			and citadel_hp < CITADEL_MAX_HP * CATCH_UP_HP_RATIO:
		catch_up_pending = true
		print("BattleManager: цитадель ниже %d%% — подкрепление в магазине" % int(CATCH_UP_HP_RATIO * 100))

# Новый забег: цитадель, королевство, армия, рука, экономика, синергии, цепочка забега
func reset_run() -> void:
	battle_in_progress = false
	armed_events.clear()
	catch_up_pending = false
	next_battle_enemy_hp = 1.0
	next_battle_note = ""
	citadel_hp = CITADEL_MAX_HP
	emit_signal("citadel_hp_changed", citadel_hp)
	citadel_shield = 0.0
	reset_kingdom()
	player_buildings.clear()
	player_units.clear()
	player_placements.clear()
	pending_cards.clear()
	EconomyManager.reset()
	SynergyManager.reset()
	ShopManager.reset()
	RunManager.new_run()
	MetaProgress.apply_run_start()   # пассивка «Резервы» и выбранная стартовая карта

# -------------------------------------------------------
# АРМИЯ ИГРОКА МЕЖДУ БОЯМИ
# -------------------------------------------------------
# Отряды с поля → забег: новые отряды из карт, уровни, улучшения, доли HP
# (расстановка и «В БОЙ» — чтобы сохранение вернуло поле как было)
func sync_army_from_squads(squads: Array) -> void:
	for squad in squads:
		var hp_list: Array[float] = []
		var kinds: Array[String] = []
		for soldier in squad.soldiers:
			hp_list.append(clampf(soldier.current_hp / soldier.max_hp, 0.01, 1.0))
			kinds.append(soldier.convert_kind)
		if not kinds.any(func(k): return k != ""):
			kinds.clear()   # все свои — список типов не нужен
		squad.data.saved_hp = hp_list
		squad.data.saved_kinds = kinds
		if not player_units.has(squad.data):
			player_units.append(squad.data)
		player_placements[squad.data] = squad.tile

# Итог победы: армия = выжившие отряды; павшие целиком возрождаются на свою
# клетку (UnitData.respawn_after_wipe — уровень −1, без улучшений).
# at_start — [{ "data": UnitData, "tile": Vector2i }] на начало боя.
# Возвращает имена возрождённых отрядов.
func store_survivors(alive_squads: Array, at_start: Array) -> Array[String]:
	player_units.clear()
	player_placements.clear()
	sync_army_from_squads(alive_squads)
	var revived: Array[String] = []
	for entry in at_start:
		var data: UnitData = entry["data"]
		if player_units.has(data):
			continue
		data.respawn_after_wipe()
		player_units.append(data)
		player_placements[data] = entry["tile"]
		revived.append(data.unit_name)
	return revived

# Ход Казарм (после выигранного боя, после store_survivors) — отрядам на соседних клетках (по сторонам):
# Казармы Космодесанта лечат живых на heal (доля max HP) и возвращают до refill павших с полным HP (решение
# пользователя 21.10.2026). Святилище культа Хаоса (та же карта, раса chaos) не лечит; если среди соседей есть
# отряд бога Хаоса, павшие ДРУГИХ соседей встают бойцами этого бога (UnitData.saved_kinds, сила — по редкости
# отряда, UnitFactory.convert_fighter), иначе — свои. Не больше squad_size. Возвращает, сколько бойцов вернулось
const NEIGHBOUR_TILES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

func refill_from_barracks() -> int:
	var total = 0
	for card in player_buildings:
		if card.building_type != "barracks":
			continue
		var stats: Dictionary = card.get_building_stats()
		var refill = floori(stats.get("refill", 0.0))
		var heal: float = stats.get("heal", 0.0) if card.faction != "chaos" else 0.0
		var neighbours: Array[UnitData] = []
		for d in player_units:
			if player_placements.has(d) and NEIGHBOUR_TILES.has(player_placements[d] - player_buildings[card]):
				neighbours.append(d)
		var god := _god_squad_among(neighbours) if card.faction == "chaos" else null
		for d in neighbours:
			if heal > 0.0:
				for i in d.saved_hp.size():
					d.saved_hp[i] = minf(d.saved_hp[i] + heal, 1.0)
			var added = mini(refill, d.squad_size - d.saved_hp.size())
			var kind := ""
			if god and d != god:
				kind = UnitFactory.convert_kind(god.factory_id, d.rarity)
				while d.saved_kinds.size() < d.saved_hp.size():   # свои бойцы, дописанные без типа
					d.saved_kinds.append("")
			for i in range(added):
				d.saved_hp.append(1.0)
				if kind != "":
					d.saved_kinds.append(kind)
			total += maxi(added, 0)
			if added > 0:   # вид: ворота казарм на поле (анимация refill листа, если есть)
				for b in buildings:
					if is_instance_valid(b) and b.card == card:
						b.play_once("refill")
	return total

# Отряд бога Хаоса (особый юнит бога — Chapters unit_card) среди отрядов или null
func _god_squad_among(squads: Array[UnitData]) -> UnitData:
	var gods: Array = Chapters.for_faction("chaos").map(func(c): return c.get("unit_card", ""))
	for d in squads:
		if d.factory_id in gods:
			return d
	return null

# Поражение / ничья — армия потеряна
func lose_army() -> void:
	player_units.clear()
	player_placements.clear()

# -------------------------------------------------------
# СОХРАНЕНИЕ (SaveManager) — своё состояние забега
# -------------------------------------------------------
# Клетки — [x, y]; отряды — UnitData.save_state() + клетка; карты — по id
func save_state() -> Dictionary:
	var units: Array = []
	for d in player_units:
		var u = d.save_state()
		if player_placements.has(d):
			u["tile"] = _v2i_to_arr(player_placements[d])
		units.append(u)
	var builds: Array = []
	for card in player_buildings:
		builds.append({"card": card.id, "tile": _v2i_to_arr(player_buildings[card]), "level": card.building_level})
	var kingdom: Array = []
	for t in kingdom_tiles:
		kingdom.append(_v2i_to_arr(t))
	return {
		"citadel_hp": citadel_hp,
		"kingdom_tiles": kingdom,
		"tiles_bought": tiles_bought,
		"units": units,
		"buildings": builds,
		"hand": CardFactory.ids_of(pending_cards),
		"in_progress": battle_in_progress,
		"catch_up_pending": catch_up_pending,
		"next_enemy_hp": next_battle_enemy_hp,
		"next_note": next_battle_note,
		"armed_events": Array(armed_events.duplicate()),
	}

func load_state(d: Dictionary) -> void:
	citadel_hp = float(d["citadel_hp"])
	kingdom_tiles.clear()
	for t in d["kingdom_tiles"]:
		kingdom_tiles.append(_arr_to_v2i(t))
	tiles_bought = int(d["tiles_bought"])
	for u in d["units"]:
		var data = UnitData.from_save_state(u)
		player_units.append(data)
		if u.has("tile"):
			player_placements[data] = _arr_to_v2i(u["tile"])
	for entry in d["buildings"]:
		var card = CardFactory.create(entry["card"])
		if card:
			card.building_level = clampi(int(entry.get("level", 1)), 1, CardData.MAX_BUILDING_LEVEL)
			# Стена — вне клеток (старые сохранения: стояла на клетке — клетка освобождается; две стены — одна
			# уровнем выше)
			var wall := get_wall_card() if card.building_type == "wall" else null
			if wall:
				wall.building_level = mini(wall.building_level + card.building_level, CardData.MAX_BUILDING_LEVEL)
				continue
			player_buildings[card] = WALL_TILE if card.building_type == "wall" else _arr_to_v2i(entry["tile"])
	pending_cards = CardFactory.create_many(d["hand"])
	battle_in_progress = bool(d.get("in_progress", false))
	catch_up_pending = bool(d.get("catch_up_pending", false))
	next_battle_enemy_hp = float(d.get("next_enemy_hp", 1.0))
	next_battle_note = str(d.get("next_note", ""))
	armed_events.clear()
	for id in d.get("armed_events", []):
		armed_events.append(str(id))
	emit_signal("citadel_hp_changed", citadel_hp)

static func _v2i_to_arr(v: Vector2i) -> Array:
	return [v.x, v.y]

static func _arr_to_v2i(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))

# Начало боя: заряженные события срабатывают. Возвращает [{pos, radius}] —
# куда пришёлся удар (вспышку рисует сцена)
func fire_armed_events() -> Array:
	var hits: Array = []
	for id in armed_events:
		var card = CardFactory.create(id)
		if card and card.event_type == "orbital_strike":
			var r: float = card.event_stats.get("radius", 0.0)
			var pos = _densest_enemy_point(r)
			if pos != null:
				for e in SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY).duplicate():
					if e.global_position.distance_to(pos) <= r:
						# Пехоту в толпе накрывает втрое больше бойцов — урон × доля юнита, как у взрывов
						e.take_damage(card.event_stats.get("damage", 0.0) * e.data.unit_weight)
				hits.append({"pos": pos, "radius": r})
				AudioManager.play("orbital_strike")
	armed_events.clear()
	return hits

# Точка удара: боец врага, вокруг которого в радиусе больше всего врагов
func _densest_enemy_point(radius: float) -> Variant:
	var enemies = SoldierRegistry.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY)
	var best = null
	var best_count = 0
	for e in enemies:
		var n = 0
		for o in enemies:
			if e.global_position.distance_to(o.global_position) <= radius:
				n += 1
		if n > best_count:
			best_count = n
			best = e.global_position
	return best

# Щит цитадели на бой — от стены владений (Fortress Wall) и зданий со щитом (бастион Imperial Fists)
func prepare_citadel_shield() -> void:
	citadel_shield = MetaProgress.passive_value("walls")   # пассивка «Освящённые стены»
	for b in buildings:
		if is_instance_valid(b):
			citadel_shield += b.get_citadel_shield()
	if has_kingdom_wall():
		citadel_shield += kingdom_wall.get_citadel_shield()
	emit_signal("citadel_hp_changed", citadel_hp)

# Волна, в которой можно расширять королевство
func can_expand_kingdom() -> bool:
	return is_expansion_wave(EconomyManager.round_number)

# Волна с этапом расширения (3, 6, 9, 12, 15) — на её расстановке продаются клетки
func is_expansion_wave(wave: int) -> bool:
	return wave % EXPANSION_EVERY == 0

func get_tile_cost() -> int:
	return TILE_BASE_COST + tiles_bought * TILE_COST_STEP

# Списывает Requisition и открывает клетку. Соседство и рамку проверяет вызывающий.
func try_buy_tile(tile: Vector2i) -> bool:
	if not can_expand_kingdom() or kingdom_tiles.has(tile) or kingdom_tiles.size() >= IsoGrid.MAX_KINGDOM_TILES:
		return false
	if not EconomyManager.try_spend(get_tile_cost()):
		return false
	kingdom_tiles.append(tile)
	tiles_bought += 1
	print("BattleManager: куплена клетка %s, всего %d" % [tile, kingdom_tiles.size()])
	return true
