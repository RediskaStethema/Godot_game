extends SceneTree

# Замер производительности боя: большая армия против волны 15, время одного
# тика BattleManager и время входа в бой (спавн отрядов). Без рендера:
#   godot --headless --path . -s tests/bench_battle.gd
const WAVE: int = 15
const PLAYER_SQUADS: int = 14
const SOLDIERS_PER_SQUAD: int = 6
const TICKS: int = 300

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	_main()

func _main() -> void:
	var bm = root.get_node("BattleManager")
	var em = root.get_node("EconomyManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(7)
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == WAVE:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	em.round_number = WAVE
	for t in [Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]:
		bm.kingdom_tiles.append(t)
	var units: Array[UnitData] = []
	for i in range(PLAYER_SQUADS):
		var d = UnitFactory.create(["tactical_marine", "assault_marine", "devastator", "apothecary", "chaplain"][i % 5])
		d.squad_size = SOLDIERS_PER_SQUAD
		var hp: Array[float] = []
		for j in range(SOLDIERS_PER_SQUAD): hp.append(1.0)
		d.saved_hp = hp
		units.append(d)
	bm.player_units = units
	var t0 = Time.get_ticks_usec()
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var spawn_ms = (Time.get_ticks_usec() - t0) / 1000.0
	await process_frame
	var reg = root.get_node("SoldierRegistry")
	var soldiers = reg.get_all_alive_soldiers().size()
	scene._on_start_pressed()
	bm.phase = bm.BattlePhase.IDLE   # тикаем вручную, а не из _process
	var t1 = Time.get_ticks_usec()
	var ticks = 0
	for i in range(TICKS):
		if reg.get_all_alive_soldiers().size() < 2:
			break
		bm._battle_tick()
		ticks += 1
	var tick_ms = (Time.get_ticks_usec() - t1) / 1000.0 / maxi(ticks, 1)
	print("BENCH soldiers=%d spawn=%.1f ms tick=%.3f ms (ticks=%d)" % [soldiers, spawn_ms, tick_ms, ticks])
	quit()
