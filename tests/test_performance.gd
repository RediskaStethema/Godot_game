extends SceneTree

# Производительность боя: просадки FPS, рывки, тормоза и утечки.
# Худший реальный бой: волна 15 на сложности 7, королевство 4×4, 12 отрядов на макс. уровне,
# все четыре вида зданий, орудие бьёт при каждой готовности. Кадр — 60 FPS при скорости боя ×2:
# тик боя каждые 3 кадра, как у игрока на ×2. Тики гоняет тест (накопитель как у BattleManager),
# чтобы мерить каждый тик отдельно; кадр — время между соседними process_frame (весь кадр:
# тики, _process узлов, отрисовка).
#   godot --headless --path . -s tests/test_performance.gd   — логика без рендера: тик, кадр, переходы, плавность, утечки
#   godot --path . -s tests/test_performance.gd              — в окне (vsync выкл.): настоящий FPS, 1% low, draw calls
# Бюджеты — константы ниже, с запасом ×2–3 к замеру на машине разработки: рост в разы — регрессия.
# Строки REPORT — цифры для сравнения между прогонами.

const WAVE: int = 15
const DIFFICULTY: int = 7
const SEED: int = 7
const FRAME_DT: float = 1.0 / 60.0
const BATTLE_SPEED: float = 2.0
const MAX_FRAMES: int = 4000     # ≈ 133 с боя на ×2 — бой кончится раньше
const WARMUP_FRAMES: int = 10    # первые кадры — загрузка текстур и шейдеров, в просадки не идут
const LEAK_BATTLES: int = 3
const LEAK_FRAMES: int = 300

# Бюджеты (мс). Тик должен влезать в кадр 60 FPS (16.7 мс) — иначе рывок; логике кадра — не больше
# 12 мс в 99% кадров, остальное — отрисовке. Самые долгие тики (≈ 11 мс) — сближение армий:
# сотни бойцов на краю поля зрения друг друга, поиск по сетке просматривает соседей
const TICK_AVG_MS: float = 4.0
const TICK_MAX_MS: float = 16.0
const LOGIC_FRAME_P99_MS: float = 12.0
const SCENE_COLD_MS: float = 3000.0   # первый бой процесса: чтение ресурсов с диска (между магазином и боем)
const SCENE_WARM_MS: float = 200.0    # следующие бои — ресурсы уже в кэше
const SHOP_LOAD_MS: float = 800.0
const START_PRESS_MS: float = 60.0
const BATTLE_END_MS: float = 120.0     # тик итога боя: доход, армия, экран итога (переход, не бой)
const SAVE_MS: float = 30.0            # сохранение забега — после каждого действия расстановки
const FLOOR_REDRAW_MS: float = 3.0
const SMOOTH_FRAMES_SHARE: float = 0.8   # доля кадров, в которых идущий боец сдвинулся на экране
# В окне
const RENDER_AVG_FPS: float = 60.0
const RENDER_LOW1_FPS: float = 30.0
const HITCH_MS: float = 50.0             # кадр дольше — заметный рывок
const MAX_HITCHES: int = 2
# Утечки за LEAK_BATTLES боёв подряд
const LEAK_NODES: int = 20
const LEAK_OBJECTS: int = 2000
const LEAK_MEMORY_MB: float = 32.0

var bm
var rm
var em
var headless: bool
var failures: int = 0

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	bm = root.get_node("BattleManager")
	rm = root.get_node("RunManager")
	em = root.get_node("EconomyManager")
	headless = DisplayServer.get_name() == "headless"
	if headless:   # без окна Godot спит ~6.9 мс за кадр (low_processor_mode_sleep_usec) — замер кадра врал бы
		OS.low_processor_usage_mode_sleep_usec = 0
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_main()

func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _report(label: String, value) -> void:
	print("REPORT %s: %s" % [label, value])

func _main() -> void:
	await process_frame
	print("Режим: %s" % ("headless — только логика" if headless else "окно, рендер %s" % RenderingServer.get_video_adapter_name()))
	await _test_battle()
	await _test_shop_load()
	if headless:
		await _test_leaks()
	print("ИТОГ: %s" % ("все бюджеты выдержаны" if failures == 0 else "провалов: %d" % failures))
	quit()

# -------------------------------------------------------
# ПОДГОТОВКА
# -------------------------------------------------------
func _max_squad(card: CardData) -> UnitData:
	var d = UnitFactory.create(card.unit_factory_id)
	d.squad_size = card.unit_count
	d.squad_growth = UnitFactory.squad_growth_for(card)
	while d.can_merge_upgrade():
		d.apply_merge_upgrade()
	var hp: Array[float] = []
	for i in range(d.squad_size):
		hp.append(1.0)
	d.saved_hp = hp
	return d

func _setup_run() -> void:
	bm.reset_run()
	rm.new_run(SEED)
	rm.difficulty = DIFFICULTY
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == WAVE:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	em.round_number = WAVE
	var size: Vector2i = load("res://scripts/battle/IsoGrid.gd").MAX_KINGDOM_SIZE
	for x in range(size.x):
		for y in range(size.y):
			if not bm.kingdom_tiles.has(Vector2i(x, y)):
				bm.kingdom_tiles.append(Vector2i(x, y))
	# Задний ряд — здания, остальные 12 клеток — отряды
	var buildings = [CardFactory.bolter_turret(), CardFactory.thunderfire_cannon(),
		CardFactory.fortress_wall(), CardFactory.barracks()]
	var b_tiles = {}
	for i in range(buildings.size()):
		b_tiles[buildings[i]] = Vector2i(0, i)
	bm.player_buildings = b_tiles
	var cards = [CardFactory.tactical_squad(), CardFactory.tactical_squad(), CardFactory.tactical_squad(),
		CardFactory.assault_squad(), CardFactory.assault_squad(), CardFactory.devastator_squad(),
		CardFactory.terminator_squad(), CardFactory.scout_squad(), CardFactory.dreadnought_card(),
		CardFactory.land_speeder_card(), CardFactory.librarian_card(), CardFactory.chapter_master_card()]
	var units: Array[UnitData] = []
	var placements = {}
	var i := 0
	for x in range(1, size.x):
		for y in range(size.y):
			var d = _max_squad(cards[i])
			units.append(d)
			placements[d] = Vector2i(x, y)
			i += 1
	bm.player_units = units
	bm.player_placements = placements

func _load_battle() -> Array:
	var t0 = Time.get_ticks_usec()
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	return [scene, (Time.get_ticks_usec() - t0) / 1000.0]

func _free_scene(scene) -> void:
	bm.stop_battle()
	Engine.time_scale = 1.0
	scene.queue_free()
	current_scene = null
	await process_frame
	await process_frame

# Кадр боя: накопитель как у BattleManager._process, тики — с замером. Возвращает время тиков (мс)
var _acc: float = 0.0
func _drive_ticks(scene, tick_ms: Array) -> void:
	_acc += FRAME_DT * BATTLE_SPEED
	while _acc >= GameConstants.FIXED_TICK and bm.is_battle_running():
		var t = Time.get_ticks_usec()
		bm._battle_tick()
		tick_ms.append((Time.get_ticks_usec() - t) / 1000.0)
		_acc -= GameConstants.FIXED_TICK
	bm._accumulator = _acc   # снаряды досчитывают долю шага (get_tick_alpha)
	scene.fire_artillery(root.get_node("SoldierRegistry").get_team_center(GameConstants.TEAM_ENEMY))

static func _percentile(values: Array, p: float) -> float:
	if values.is_empty():
		return 0.0
	var s = values.duplicate()
	s.sort()
	return s[clampi(int(ceil(p * s.size())) - 1, 0, s.size() - 1)]

static func _avg(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += v
	return sum / values.size()

# -------------------------------------------------------
# 1. БОЙ: тик, кадр, рывки движения, перерисовка пола
# -------------------------------------------------------
func _test_battle() -> void:
	_setup_run()
	var cold = await _load_battle()
	await _free_scene(cold[0])
	_setup_run()
	var loaded = await _load_battle()
	var scene = loaded[0]
	var reg = root.get_node("SoldierRegistry")
	_report("загрузка сцены боя", "первая %.0f мс, повторная %.0f мс" % [cold[1], loaded[1]])
	_check("первая загрузка боя быстрее %.0f мс: %.0f" % [SCENE_COLD_MS, cold[1]], cold[1] < SCENE_COLD_MS)
	_check("повторная загрузка боя быстрее %.0f мс: %.0f" % [SCENE_WARM_MS, loaded[1]], loaded[1] < SCENE_WARM_MS)

	# Пол: кадр с полной перерисовкой пола минус кадр без неё (анимированный туман — 12 раз/с).
	# Без рендера _draw не зовётся — только в окне
	if not headless:
		var floor_ms := await _floor_redraw_cost(scene)
		_report("перерисовка пола", "%.2f мс за раз" % floor_ms)
		_check("перерисовка пола дешевле %.1f мс: %.2f" % [FLOOR_REDRAW_MS, floor_ms], floor_ms < FLOOR_REDRAW_MS)

	var t0 = Time.get_ticks_usec()
	scene._on_start_pressed()
	var start_ms = (Time.get_ticks_usec() - t0) / 1000.0
	bm.set_process(false)   # тикает тест
	Engine.time_scale = 1.0
	var soldiers_start: int = reg.get_all_alive_soldiers().size()
	_report("бойцов в начале боя", "%d (игрок %d, враг %d)" % [soldiers_start,
		reg.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER).size(),
		reg.get_alive_soldiers_of_team(GameConstants.TEAM_ENEMY).size()])
	_report("нажатие «В БОЙ»", "%.1f мс" % start_ms)
	_check("«В БОЙ» без зависания (< %.0f мс): %.1f" % [START_PRESS_MS, start_ms], start_ms < START_PRESS_MS)

	# Плавность: первый боец игрока на марше — сдвигается ли на экране каждый кадр
	var walker = reg.get_alive_soldiers_of_team(GameConstants.TEAM_PLAYER)[0]
	var last_pos: Vector2 = walker.sprite.global_position
	var moved_frames := 0
	var watched_frames := 0

	var tick_ms: Array = []
	var frame_ms: Array = []
	var draw_calls: Array = []
	var peak_nodes := 0
	var peak_projectiles := 0
	_acc = 0.0
	var prev = Time.get_ticks_usec()
	var frames := 0
	var grid_checks := 0
	var grid_misses := 0
	while bm.is_battle_running() and frames < MAX_FRAMES:
		_drive_ticks(scene, tick_ms)
		# Сверка сетки возвращает бойцов в логические позиции — после замера плавности марша
		if frames > 90 and frames % 15 == 0 and bm.is_battle_running():
			var r = _compare_grid_search(reg)
			grid_checks += r[0]
			grid_misses += r[1]
			prev = Time.get_ticks_usec()   # сверка — не кадр игры
		await process_frame
		var now = Time.get_ticks_usec()
		frames += 1
		if frames > WARMUP_FRAMES:
			frame_ms.append((now - prev) / 1000.0)
			if not headless:
				draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prev = now
		peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		peak_projectiles = maxi(peak_projectiles, bm.projectiles.size())
		if is_instance_valid(walker) and walker.current_state == walker.State.MOVE and watched_frames < 60:
			watched_frames += 1
			if walker.sprite.global_position.distance_to(last_pos) > 0.01:
				moved_frames += 1
		if is_instance_valid(walker):
			last_pos = walker.sprite.global_position

	# Последний тик — итог боя (на волне 15 — ещё и экран конца забега): мерится отдельно
	var end_ms: float = tick_ms.pop_back() if not bm.is_battle_running() and not tick_ms.is_empty() else 0.0
	if not bm.is_battle_running() and not frame_ms.is_empty():
		frame_ms.pop_back()   # кадр итога — тоже
	var tick_avg := _avg(tick_ms)
	var tick_max: float = tick_ms.max() if not tick_ms.is_empty() else 0.0
	_report("бой", "%d кадров, %d тиков, итог — команда %d" % [frames, tick_ms.size(), bm.winner_team])
	_report("тик итога боя", "%.1f мс" % end_ms)
	_check("итог боя без долгого зависания (< %.0f мс): %.1f" % [BATTLE_END_MS, end_ms], end_ms < BATTLE_END_MS)
	_report("тик боя", "сред. %.2f мс, p99 %.2f, макс %.2f" % [tick_avg, _percentile(tick_ms, 0.99), tick_max])
	_report("пик узлов / снарядов", "%d / %d" % [peak_nodes, peak_projectiles])
	_check("тик в среднем < %.1f мс: %.2f" % [TICK_AVG_MS, tick_avg], tick_avg < TICK_AVG_MS)
	# Один выброс (планировщик ОС) допустим; два и больше долгих тика — уже рывки боя
	var long_ticks := tick_ms.filter(func(t): return t >= TICK_MAX_MS).size()
	_check("тики влезают в кадр 60 FPS (≥ %.1f мс — не больше 1): %d, самый долгий %.2f" % [TICK_MAX_MS, long_ticks, tick_max],
		long_ticks <= 1)

	var f_avg := _avg(frame_ms)
	var f_p99 := _percentile(frame_ms, 0.99)
	var f_max: float = frame_ms.max() if not frame_ms.is_empty() else 0.0
	var hitches := frame_ms.filter(func(f): return f > HITCH_MS).size()
	_report("кадр", "сред. %.2f мс, p99 %.2f, макс %.2f, рывков > %.0f мс: %d" % [f_avg, f_p99, f_max, HITCH_MS, hitches])
	if headless:
		_check("логика кадра p99 < %.1f мс: %.2f" % [LOGIC_FRAME_P99_MS, f_p99], f_p99 < LOGIC_FRAME_P99_MS)
	else:
		var fps_avg := 1000.0 / maxf(f_avg, 0.001)
		var fps_low := 1000.0 / maxf(f_p99, 0.001)
		_report("FPS", "сред. %.0f, 1%% low %.0f, draw calls сред. %.0f / макс %.0f" % [fps_avg, fps_low,
			_avg(draw_calls), draw_calls.max() if not draw_calls.is_empty() else 0])
		_check("средний FPS ≥ %.0f: %.0f" % [RENDER_AVG_FPS, fps_avg], fps_avg >= RENDER_AVG_FPS)
		_check("1%% low FPS ≥ %.0f: %.0f" % [RENDER_LOW1_FPS, fps_low], fps_low >= RENDER_LOW1_FPS)
		_check("рывков > %.0f мс не больше %d: %d" % [HITCH_MS, MAX_HITCHES, hitches], hitches <= MAX_HITCHES)

	_check("поиск ближайшего по сетке = полный перебор: расхождений %d из %d" % [grid_misses, grid_checks],
		grid_checks > 0 and grid_misses == 0)
	var smooth := float(moved_frames) / maxi(watched_frames, 1)
	_report("плавность марша", "боец сдвинулся в %d из %d кадров" % [moved_frames, watched_frames])
	_check("боец на марше движется каждый кадр, а не рывками раз в тик (≥ %.0f%%): %.0f%%"
		% [SMOOTH_FRAMES_SHARE * 100.0, smooth * 100.0], watched_frames > 0 and smooth >= SMOOTH_FRAMES_SHARE)
	bm.set_process(true)
	await _free_scene(scene)

# Ближайший враг (и в поле зрения, и стрелок) — по сетке реестра и полным перебором: одно и то же
func _compare_grid_search(reg) -> Array:
	var checks := 0
	var misses := 0
	reg.begin_tick()   # сетка — как в тике боя
	var all: Array = reg.get_all_alive_soldiers()
	for i in range(0, all.size(), 7):
		var s = all[i]
		for q in [[INF, false], [s.data.vision_range, false], [INF, true]]:
			var by_grid = reg.find_nearest(1 - s.team, s.global_position, q[0], q[1])
			var by_list = reg._find_nearest_linear(1 - s.team, s.global_position, q[0], q[1])
			checks += 1
			var d1 = s.global_position.distance_squared_to(by_grid.global_position) if by_grid else -1.0
			var d2 = s.global_position.distance_squared_to(by_list.global_position) if by_list else -1.0
			if not is_equal_approx(d1, d2):
				misses += 1
	reg.end_tick()
	return [checks, misses]

func _floor_redraw_cost(scene) -> float:
	var renderer = scene.renderer
	var frames := 30
	var plain: Array = []
	var redraw: Array = []
	renderer.set_process(false)   # своя анимация пола не мешает замеру
	for i in range(frames * 2):
		var forced := i % 2 == 1
		if forced:
			renderer._floor.queue_redraw()
		var t = Time.get_ticks_usec()
		await process_frame
		await process_frame
		(redraw if forced else plain).append((Time.get_ticks_usec() - t) / 1000.0)
	renderer.set_process(true)
	return maxf(_percentile(redraw, 0.5) - _percentile(plain, 0.5), 0.0)

# -------------------------------------------------------
# 2. ПЕРЕХОД В МАГАЗИН
# -------------------------------------------------------
func _test_shop_load() -> void:
	bm.reset_run()
	rm.new_run(SEED)
	for i in range(bm.MAX_HAND_SIZE):   # полная рука — самая тяжёлая раскладка
		bm.pending_cards.append(CardFactory.tactical_squad())
	var t0 = Time.get_ticks_usec()
	var shop = load("res://scenes/shop/ShopScene.tscn").instantiate()
	root.add_child(shop)
	current_scene = shop
	await process_frame
	var ms = (Time.get_ticks_usec() - t0) / 1000.0
	_report("загрузка магазина (рука 10)", "%.0f мс" % ms)
	_check("магазин грузится быстрее %.0f мс: %.0f" % [SHOP_LOAD_MS, ms], ms < SHOP_LOAD_MS)
	# Сохранение — в свой файл: сохранение игрока не трогаем
	var sm = root.get_node("SaveManager")
	var old_path: String = sm.save_path
	sm.save_path = "user://perf_test_save.json"
	sm.enabled = true
	_setup_run()
	var t1 = Time.get_ticks_usec()
	sm.save_run()
	var save_ms = (Time.get_ticks_usec() - t1) / 1000.0
	sm.delete_save()
	sm.enabled = false
	sm.save_path = old_path
	_report("сохранение забега (армия 12 отрядов, 4 здания)", "%.1f мс" % save_ms)
	_check("сохранение быстрее %.0f мс: %.1f" % [SAVE_MS, save_ms], save_ms < SAVE_MS)
	shop.queue_free()
	current_scene = null
	await process_frame
	await process_frame

# -------------------------------------------------------
# 3. УТЕЧКИ: несколько боёв подряд — узлы, объекты, память и реестры возвращаются
# -------------------------------------------------------
func _test_leaks() -> void:
	var nodes0 := 0
	var objects0 := 0
	var memory0 := 0.0
	var orphans0 := 0
	for b in range(LEAK_BATTLES + 1):
		_setup_run()
		var loaded = await _load_battle()
		var scene = loaded[0]
		scene._on_start_pressed()
		bm.set_process(false)
		Engine.time_scale = 1.0
		_acc = 0.0
		var ticks: Array = []
		for i in range(LEAK_FRAMES):
			if not bm.is_battle_running():
				break
			_drive_ticks(scene, ticks)
			await process_frame
		bm.set_process(true)
		await _free_scene(scene)
		for i in range(5):   # отложенные queue_free (эффекты, снаряды) успевают уйти
			await process_frame
		var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		var memory: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		_report("после боя %d" % b, "узлов %d, объектов %d, сирот %d, память %.1f МБ" % [nodes, objects, orphans, memory])
		if b == 0:   # первый бой — прогрев (кэши кадров, текстур), отсчёт от него
			nodes0 = nodes
			objects0 = objects
			orphans0 = orphans
			memory0 = memory
		elif b == LEAK_BATTLES:
			_check("узлы не копятся за %d боя: +%d (≤ %d)" % [LEAK_BATTLES, nodes - nodes0, LEAK_NODES], nodes - nodes0 <= LEAK_NODES)
			_check("узлы-сироты не копятся: +%d" % (orphans - orphans0), orphans - orphans0 <= 0)
			_check("объекты не копятся: +%d (≤ %d)" % [objects - objects0, LEAK_OBJECTS], objects - objects0 <= LEAK_OBJECTS)
			_check("память не растёт: +%.1f МБ (≤ %.0f)" % [memory - memory0, LEAK_MEMORY_MB], memory - memory0 <= LEAK_MEMORY_MB)
	var sr = root.get_node("SoldierRegistry")
	var qr = root.get_node("SquadRegistry")
	_check("реестры и снаряды пусты после боя: бойцов %d, отрядов %d, снарядов %d" % [
		sr.get_all_alive_soldiers().size(), qr.get_all_alive_squads().size(), bm.projectiles.size()],
		sr.get_all_alive_soldiers().is_empty() and qr.get_all_alive_squads().is_empty() and bm.projectiles.is_empty())
