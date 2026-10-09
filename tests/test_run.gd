extends SceneTree

var ended_count := 0
var last_winner := -99

func _on_end(w):
	ended_count += 1
	last_winner = w

func _army(n_squads:int, id:String, cnt:int) -> Array[UnitData]:
	var arr: Array[UnitData] = []
	for i in range(n_squads):
		var d = UnitFactory.create(id)
		var hp: Array[float] = []
		for j in range(cnt): hp.append(1.0)
		d.saved_hp = hp
		arr.append(d)
	return arr

func _run_battle(label:String, type:String, wave:int, army:Array[UnitData], max_ticks:int) -> void:
	var bm = root.get_node("BattleManager")
	var em = root.get_node("EconomyManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(12345)
	var node = null
	for n in rm.map.nodes:
		if n.type == type and n.wave == wave:
			node = n; break
	if node == null:
		print("[%s] FAIL: нет узла типа %s волны %d" % [label, type, wave]); return
	rm.current_node_id = node.id
	rm.current_completed = false
	em.round_number = node.wave
	bm.player_units = army
	ended_count = 0; last_winner = -99
	var req0 = em.requisition
	var round0 = em.round_number
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var enemies = root.get_node("SquadRegistry").get_alive_squads_of_team(1)
	var etypes := {}
	for s in enemies: etypes[s.data.factory_id] = etypes.get(s.data.factory_id,0)+1
	print("[%s] type=%s wave=%d enemy squads=%s player squads=%d" % [label, scene.battle_type, scene.battle_wave, etypes, root.get_node("SquadRegistry").get_alive_squads_of_team(0).size()])
	bm.battle_ended.connect(_on_end)
	scene._on_start_pressed()
	var frames := 0
	while ended_count == 0 and frames < max_ticks:
		await process_frame
		frames += 1
	print("[%s] frames=%d ended_count=%d winner=%d" % [label, frames, ended_count, last_winner])
	for i in range(30): await process_frame
	print("[%s] after extra frames ended_count=%d round %d->%d req %d->%d citadel_hp=%s siege=%s" % [label, ended_count, round0, em.round_number, req0, em.requisition, bm.citadel_hp, bm.siege_started])
	var sr = root.get_node("SquadRegistry")
	var so = root.get_node("SoldierRegistry")
	print("[%s] registries: squads=%d soldiers=%d node_completed=%s player_units=%d" % [label, sr.get_all_alive_squads().size(), so.get_alive_soldiers_of_team(0).size()+so.get_alive_soldiers_of_team(1).size(), rm.current_completed, bm.player_units.size()])
	for d in bm.player_units:
		for h in d.saved_hp:
			if h <= 0.0 or h > 1.0001: print("[%s] BAD saved_hp %s" % [label, h])
	bm.battle_ended.disconnect(_on_end)
	# После победы сцена сама уходит в магазин (RunManager.advance) — уже освобождена
	if is_instance_valid(scene):
		scene.queue_free()
	current_scene = null
	await process_frame

func _initialize() -> void:
	# Бои сами пишут сохранение — в тестах выключаем, чтобы не затереть сохранение игрока
	root.get_node("SaveManager").enabled = false
	Engine.time_scale = 8.0
	_main()

func _main() -> void:
	var bm = root.get_node("BattleManager")
	var em = root.get_node("EconomyManager")
	var rm = root.get_node("RunManager")
	# Цепочка: 15 волн, перед каждой магазин, мини-босс на 5 и 10, босс на 15
	rm.new_run(12345)
	var seq := []
	for n in rm.map.nodes:
		seq.append("%s%s" % [n.type, "" if n.wave == 0 else str(n.wave)])
	print("chain(%d): %s" % [rm.map.nodes.size(), " > ".join(seq)])
	var ok_chain = rm.map.nodes.size() == 30 and rm.map.total_waves == 15
	for i in range(rm.map.nodes.size()):
		var n = rm.map.nodes[i]
		var expect_next = [] if i == rm.map.nodes.size() - 1 else [i + 1]
		if n.next != expect_next: ok_chain = false
		if i % 2 == 0 and n.type != "shop": ok_chain = false
	for w in [5, 10]:
		if rm.map.nodes[w * 2 - 1].type != "miniboss": ok_chain = false
	if rm.map.nodes[29].type != "boss": ok_chain = false
	print("chain ok: %s" % ok_chain)
	rm.ensure_started()
	print("ensure_started: node=%d type=%s next=%d" % [rm.current_node_id, rm.get_current_node().type, rm.get_next_id()])

	await _run_battle("normal", "battle", 3, _army(4,"tactical_marine",5), 6000)
	await _run_battle("miniboss5", "miniboss", 5, _army(5,"tactical_marine",6), 6000)
	await _run_battle("miniboss10", "miniboss", 10, _army(6,"tactical_marine",6), 6000)
	await _run_battle("boss15", "boss", 15, _army(6,"tactical_marine",6), 6000)
	await _run_battle("siege(no army)", "battle", 1, _army(0,"tactical_marine",1), 6000)

	# Расширение королевства — каждая 3-я волна
	bm.reset_run()
	var waves := []
	for w in range(1, 16):
		em.round_number = w
		if bm.can_expand_kingdom(): waves.append(w)
	print("expansion waves: %s (expect [3, 6, 9, 12, 15])" % [waves])
	em.round_number = 3
	em.requisition = 20
	print("buy tile r3 (expect true): %s kingdom=%d req=%d" % [bm.try_buy_tile(Vector2i(3,0)), bm.kingdom_tiles.size(), em.requisition])
	em.round_number = 2
	print("buy tile r2 (expect false): %s" % bm.try_buy_tile(Vector2i(0,3)))
	Engine.time_scale = 1.0
	quit()
