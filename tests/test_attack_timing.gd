extends SceneTree

# Удары по моделькам и вид поля:
# 1) бойцы отряда бьют вразнобой — первый удар после входа в ATTACK со сдвигом бойца;
# 2) удар ближнего боя с меткой hit_frame (Дредноут, Терминатор) проходит на кадре замаха,
#    а не в начале анимации; сорван оглушением; цель ушла — мимо; без метки — сразу;
# 3) река — пары «плита + отражение вдоль течения», одна плита на пару;
# 4) туман — группами (туманные местности), а не одиночными клетками;
# 5) высокие руины готики — только вне боевой полосы;
# 6) у цитадели — грунт, знамёна — на стороне игрока, нет декора на тумане и кратерах.
# Бойцы тикаются вручную (FIXED_TICK) на расстановке — бой не идёт.
#   godot --headless --path . -s tests/test_attack_timing.gd
const TICK: float = 0.1
const EPS: float = 0.01

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _ticks(s, seconds: float) -> void:
	for i in range(roundi(seconds / TICK)):
		s.tick(TICK)

func _of(team: int, id: String) -> Array:
	return root.get_node("SoldierRegistry").get_alive_soldiers_of_team(team) \
		.filter(func(s): return s.data.factory_id == id)

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(3)
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	var army: Array[UnitData] = []
	var placements = {}
	for p in [["terminator", Vector2i(1, 0), 6], ["dreadnought", Vector2i(1, 1), 2], ["assault_marine", Vector2i(2, 2), 2]]:
		var d = UnitFactory.create(p[0])
		var hp: Array[float] = []
		for i in range(p[2]):
			hp.append(1.0)
		d.saved_hp = hp
		d.squad_size = p[2]
		army.append(d)
		placements[d] = p[1]
	bm.player_units = army
	bm.player_placements = placements
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	scene._spawn_squad(UnitFactory.create("chaos_marine"), GameConstants.TEAM_ENEMY, Vector2i(2, 1), 4)
	var enemies = _of(1, "chaos_marine")

	# 1. Отряд бьёт вразнобой: первые удары бойцов сдвинуты по-разному, до удара — стойка
	var terms = _of(0, "terminator")
	var timers = {}
	var all_ok = true
	for t in terms:
		t.target = enemies[0]
		t.transition_to(t.State.ATTACK)
		var interval = 1.0 / t.current_attack_speed
		all_ok = all_ok and t.attack_timer >= 0.0 and t.attack_timer <= interval * t.ATTACK_STAGGER + EPS \
			and t.sprite.animation == "idle"
		timers[snappedf(t.attack_timer, 0.01)] = true
	_check("терминаторы бьют вразнобой: %d разных задержек первого удара из %d" % [timers.size(), terms.size()],
		all_ok and timers.size() >= terms.size() - 1)

	# 2. Дредноут: удар — на кадре hit_frame (кулак у цели), отброс — тогда же
	var dread = _of(0, "dreadnought")[0]
	var frames: SpriteFrames = dread.sprite.sprite_frames
	var hit_time: float = frames.get_meta("hit_frame", -1) / frames.get_animation_speed("attack")
	var e = enemies[1]
	e.global_position = dread.global_position + Vector2(40, 0)
	e.max_hp = 1000.0   # переживёт удар — виден отброс
	e.current_hp = 1000.0
	var hp0: float = e.current_hp
	dread.target = e
	dread._do_attack()
	var before = e.current_hp == hp0 and dread.sprite.animation == "attack"
	_ticks(dread, hit_time - TICK)
	var during = e.current_hp == hp0
	_ticks(dread, TICK)
	_check("Дредноут: в начале замаха урона нет, на кадре удара (%.1f с) — урон и отброс" % hit_time,
		hit_time > TICK and before and during and e.current_hp < hp0 and e.current_state == e.State.KNOCKBACK)

	# Оглушение посреди замаха — удар сорван; цель ушла дальше досягаемости — мимо
	var dread2 = _of(0, "dreadnought")[1]
	var e2 = enemies[2]
	e2.global_position = dread2.global_position + Vector2(40, 0)
	var hp2: float = e2.current_hp
	dread2.target = e2
	dread2._do_attack()
	_ticks(dread2, TICK)
	dread2.apply_stun(1.0)
	_ticks(dread2, hit_time)
	var stunned_miss = e2.current_hp == hp2
	dread2.stun_timer = 0.0
	dread2.transition_to(dread2.State.IDLE)
	dread2.target = e2
	dread2._do_attack()
	e2.global_position = dread2.global_position + Vector2(500, 0)
	_ticks(dread2, hit_time + TICK)
	_check("замах сорван оглушением; цель ушла — удар мимо", stunned_miss and e2.current_hp == hp2)

	# Поза победы: итог боя (BattleManager._stand_down_soldiers) — победившие Дредноуты поднимают
	# кулак (анимация victory), у проигравших и у юнитов без позы — стойка
	bm._stand_down_soldiers(GameConstants.TEAM_PLAYER)
	var victory_pose = dread.sprite.animation == "victory" and dread.current_state == dread.State.IDLE
	var term_idle = terms[0].sprite.animation == "idle"
	bm._stand_down_soldiers(GameConstants.TEAM_ENEMY)
	_check("победа: Дредноут — поза победы (victory), Терминатор — стойка; поражение — стойка",
		victory_pose and term_idle and dread.sprite.animation == "idle")

	# Новый замах раньше, чем дошёл прошлый (атака быстрее анимации) — прошлый удар засчитан, не потерян
	var dread3 = _of(0, "dreadnought")[0]
	var e4 = enemies[0]
	e4.global_position = dread3.global_position + Vector2(40, 0)
	e4.max_hp = 1000.0
	e4.current_hp = 1000.0
	if e4.current_state == e4.State.DEAD:
		e4.current_state = e4.State.IDLE
	dread3.target = e4
	dread3._do_attack()
	var hp4: float = e4.current_hp
	dread3.target = e4
	dread3._do_attack()   # второй замах сразу — первый удар проходит сейчас
	_check("быстрый повторный замах: прошлый удар засчитан, а не потерян", e4.current_hp < hp4)

	# Без метки hit_frame (Assault — спрайт из GIF) — удар сразу, как раньше
	var assault = _of(0, "assault_marine")[0]
	var e3 = enemies[3]
	var hp3: float = e3.current_hp
	assault.target = e3
	assault._do_attack()
	_check("без hit_frame — урон сразу", e3.current_hp < hp3)

	# Каст — часть перезарядки: Библиарий колдует раз в 1 / attack_speed, а не каст + перезарядка
	# (раньше вход в ATTACK после каста сбрасывал перезарядку на короткий сдвиг первого удара)
	scene._spawn_squad(UnitFactory.create("librarian"), GameConstants.TEAM_PLAYER, Vector2i(0, 0), 1)
	var lib = _of(0, "librarian")[0]
	var e5 = enemies[3]
	e5.max_hp = 1e9
	e5.current_hp = 1e9
	e5.global_position = lib.global_position + Vector2(120, 0)
	lib.target = e5
	lib.transition_to(lib.State.ATTACK)
	var casts := 0
	var was_casting := false
	var seconds := 10.0
	for i in range(roundi(seconds / TICK)):
		lib.tick(TICK)
		var casting: bool = lib.current_state == lib.State.CASTING
		if casting and not was_casting:
			casts += 1
		was_casting = casting
	var expected: float = seconds * lib.current_attack_speed
	_check("Библиарий: %d кастов за %.0f с (ожидалось ≈ %.1f — раз в 1 / attack_speed)" % [casts, seconds, expected],
		absf(casts - expected) <= 1.0)

	# 3. Река: плита и её отражение по очереди, плита одна на всю реку (стыки без перемычек);
	#    на линии по u — отражена по горизонтали
	var r = scene.renderer
	var pairs_ok = true
	var variants = {}
	for k in range(-4, 30, 2):
		var a = r.river_tile_for(Vector2i(7, k), "v")
		var b = r.river_tile_for(Vector2i(7, k + 1), "v")
		variants[a[0]["texture"]] = true
		pairs_ok = pairs_ok and a[0].has("mirror") and b[0]["texture"] == a[0]["mirror"]["texture"] \
			and not a[1] and not b[1]
	var u_tile = r.river_tile_for(Vector2i(3, -3), "u")
	_check("река: плита + её отражение по очереди, одна плита на всю реку (%d), по u — отражена" % variants.size(),
		pairs_ok and u_tile[1] and variants.size() == 1)
	# Река одна — вдоль поля боя, вне боевой полосы и не у цитадели
	var river_cells: Dictionary = r._river_cells()
	var river_rows = {}
	var river_ok = not river_cells.is_empty()
	for c in river_cells:
		river_rows[c.y] = true
		river_ok = river_ok and river_cells[c] == "u" and not r._is_battle_strip(c) and not r._near_citadel(c)
	_check("река одна: %d клеток в ряду вдоль поля, вне боевой полосы и не у цитадели" % river_cells.size(),
		river_ok and river_rows.size() == 1)

	# 4. Туман — местностями: клетки тумана держатся группами
	var terrain: Dictionary = r._terrain_cells(r._floor_cells(), r._river_cells())
	var fog: Array = []
	for c in terrain:
		var entry = terrain[c][0]
		if entry is Dictionary and entry.has("frames"):
			fog.append(c)
	var grouped = 0
	for c in fog:
		for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if fog.has(c + n):
				grouped += 1
				break
	_check("туман: %d клеток, в группах %d" % [fog.size(), grouped],
		fog.size() >= 10 and grouped >= fog.size() * 0.8)

	# 5. Руины готики: высокие — только вне боевой полосы (бойцы не ходят «сквозь» здания)
	var tall_total = 0
	var tall_in_strip = 0
	for c in terrain:
		var entry = terrain[c][0]
		if entry is Dictionary and entry.get("tall", false):
			tall_total += 1
			if r._is_battle_strip(c):
				tall_in_strip += 1
	_check("руины: высоких %d, в боевой полосе %d" % [tall_total, tall_in_strip],
		tall_total > 0 and tall_in_strip == 0)

	# 6. Вокруг цитадели — просто грунт; знамёна — только на стороне игрока; декора нет
	#    на тумане, больших кратерах и у цитадели
	var ground = r.theme["ground"]
	var citadel_plain = true
	var flags_ok = true
	var flags = 0
	var decor_ok = true
	var decor_count = 0
	var rivers: Dictionary = r._river_cells()
	for c in r._floor_cells():
		if r._near_citadel(c) and terrain.has(c) and not ground.has(terrain[c][0]):
			citadel_plain = false
		if terrain.has(c) and terrain[c][0] is Dictionary and terrain[c][0].get("flag", false):
			flags += 1
			flags_ok = flags_ok and r._is_player_side(c)
		var deco = r.decoration_for(c, rivers, terrain)
		if deco != null:
			decor_count += 1
			if deco.get("flag", false):
				flags_ok = flags_ok and r._is_player_side(c)
			if r._near_citadel(c) or (terrain.has(c) and terrain[c][0] is Dictionary \
					and terrain[c][0].get("no_decor", false)):
				decor_ok = false
	_check("у цитадели грунт; знамён-плиток %d — на стороне игрока; декор (%d) не на тумане, кратерах, у цитадели" \
		% [flags, decor_count], citadel_plain and flags_ok and decor_ok and decor_count > 0)
	quit()
