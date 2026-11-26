extends SceneTree

# Свечение цитаделей кодом (23.11.2026, решение пользователя: «улучшить анимации огней, свечения, факелов у цитаделей»):
# точки света из темы расы, факелы / свечи / окна, мерцание живое, обрушенная цитадель не светится, «Атмосфера» выкл — нет.
#   godot --headless --path . -s tests/test_citadel_glow.gd

func _initialize() -> void:
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _glow_of(citadel: Node) -> Node:
	var sprite: Node = citadel.get("_sprite")
	if sprite == null:
		return null
	for c in sprite.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == "BuildingGlow":
			return c
	return null

func _main() -> void:
	await process_frame
	var rm = root.get_node("RunManager")
	var bm = root.get_node("BattleManager")
	var gs = root.get_node("GameSettings")
	root.get_node("SaveManager").enabled = false
	gs.config_path = "user://_tmp_citadel_glow.cfg"
	gs.battle_speed = 1.0
	gs.tutorial_enabled = false
	var theme_script = load("res://scripts/data/FactionTheme.gd")
	var BG = load("res://scripts/battle/BuildingGlow.gd")

	# 1. Точки в теме: у каждой расы свои, видов три, координаты внутри кадра
	for race in [["space_marines", theme_script.SM_CITADEL_LIGHTS, Vector2(211, 219)], ["chaos", theme_script.CH_CITADEL_LIGHTS, Vector2(272, 266)]]:
		var list: Array = race[1]
		var kinds := {}
		var inside := true
		for e in list:
			kinds[e[0]] = true
			inside = inside and e[1] >= 0 and e[1] < race[2].x and e[2] >= 0 and e[2] < race[2].y
		_check("%s: %d точек, есть факелы, все внутри кадра" % [race[0], list.size()], list.size() >= 8 and kinds.has("t") and inside)
		var pts: Array = BG.lights_from(list)
		_check("%s: у точек фаза и темп по виду" % race[0], pts.size() == list.size() and pts.all(func(p): return p["sp"] > 0.5 and p.has("kind")))

	# 2. В бою за обе расы: у цитадели есть свечение с точками темы
	for race in ["space_marines", "chaos"]:
		bm.reset_run()
		rm.new_run(5)
		rm.player_faction = race
		for n in rm.map.nodes:
			if n.is_battle() and n.wave == 1:
				rm.current_node_id = n.id
				rm.current_completed = false
				break
		root.get_node("EconomyManager").round_number = 1
		change_scene_to_file("res://scenes/battle/BattleScene.tscn")
		await _frames(4)
		var citadel = bm.citadel
		var glow = _glow_of(citadel)
		var want: int = (theme_script.SM_CITADEL_LIGHTS if race == "space_marines" else theme_script.CH_CITADEL_LIGHTS).size()
		_check("%s: свечение цитадели создано, точек %d" % [race, want], glow != null and glow._nodes.size() == want)
		if glow == null:
			continue
		var before: Array = glow._nodes.map(func(n): return n.modulate.a)
		await _frames(30)
		var after: Array = glow._nodes.map(func(n): return n.modulate.a)
		var changed := 0
		for i in before.size():
			if absf(before[i] - after[i]) > 0.002:
				changed += 1
		_check("%s: огни мерцают (изменились %d из %d)" % [race, changed, before.size()], changed >= before.size() / 2)
		var torch_flame: bool = glow._points.any(func(p): return p.get("kind", "") == "t")
		_check("%s: факелы с языками пламени" % race, torch_flame)
		# обрушенная цитадель не светится
		citadel.get("_sprite").play("fall")
		await _frames(3)
		_check("%s: после обрушения свечения нет" % race, not glow.visible)
		citadel.get("_sprite").play("idle")
		await _frames(3)
		_check("%s: стойка — свет вернулся" % race, glow.visible)
		gs.atmosphere = false
		await _frames(3)
		_check("%s: «Атмосфера» выкл — свечения нет" % race, not glow.visible)
		gs.atmosphere = true

	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.config_path))
	quit()
