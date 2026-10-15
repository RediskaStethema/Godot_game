extends SceneTree

# Объявление этапа расширения: на расстановке волны, где можно покупать клетки (3, 6, 9…), —
# баннер «Пришло время расширяться» с ценой клетки; на других волнах его нет; «В БОЙ» его убирает,
# клик по баннеру закрывает. Сохранение выключено — забег игрока не трогает.
#   godot --headless --path . -s tests/test_expansion_banner.gd

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _frames(n: int) -> void:
	for i in range(n): await process_frame

func _open_battle(wave: int):
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(5)
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == wave:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = wave
	root.get_node("EconomyManager").requisition = 50
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(3)
	return current_scene

func _banner_text(banner) -> String:
	var text = ""
	for l in banner.find_children("*", "Label", true, false):
		text += l.text + "\n"
	return text

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")

	# 1. Волна 1 — расширения нет, баннера нет
	var battle = await _open_battle(1)
	_check("волна 1: баннера расширения нет", not is_instance_valid(battle.expansion_banner))

	# 2. Волна 3 — баннер с заголовком и ценой клетки
	battle = await _open_battle(3)
	var banner = battle.expansion_banner
	var text = _banner_text(banner) if is_instance_valid(banner) else ""
	_check("волна 3: баннер «Пришло время расширяться», цена %d Req" % bm.get_tile_cost(),
		bm.can_expand_kingdom() and text.contains("РАСШИРЯТЬСЯ") and text.contains("%d Req" % bm.get_tile_cost()))

	# 3. «В БОЙ» — баннер убран
	battle._on_start_pressed()
	await _frames(2)
	_check("«В БОЙ» убирает баннер", not is_instance_valid(banner))
	bm.stop_battle()

	# 4. Клик по баннеру — закрыть
	battle = await _open_battle(6)
	banner = battle.expansion_banner
	var had_banner = is_instance_valid(banner)
	var closed = [false]
	if had_banner:
		banner.closed.connect(func(): closed[0] = true)
		var click = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		banner._on_panel_input(click)
	await _frames(2)
	_check("волна 6: баннер есть, клик по нему — закрыт", had_banner and closed[0] and not is_instance_valid(banner))
	bm.stop_battle()
	quit()
