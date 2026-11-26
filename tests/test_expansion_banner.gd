extends SceneTree

# Объявление этапа расширения (решение пользователя): экран «Пришло время расширяться» — в конце
# боя перед волной, на расстановке которой продаются клетки (после боёв 2, 5, 8…), до магазина;
# дальше — по кнопке «В МАГАЗИН». После других боёв его нет. На расстановке волны расширения
# баннера нет — подсказка в шапке с ценой клетки. Сохранение выключено — забег игрока не трогает.
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

# Конец боя волны wave: шаг завершён, доход выдан (round_number — уже следующей волны), затем
# то же, что делает сцена через 2 с после итога
func _finish_battle(battle, wave: int) -> void:
	root.get_node("RunManager").complete_current_node(true)
	root.get_node("EconomyManager").round_number = wave + 1
	battle._go_to_next_step()
	await _frames(3)

func _banner_text(banner) -> String:
	var text = ""
	for l in banner.find_children("*", "Label", true, false):
		text += l.text + "\n"
	return text

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")

	# 1. После боя волны 1 (следующая — 2) — экрана нет, сразу дальше
	var battle = await _open_battle(1)
	await _finish_battle(battle, 1)
	_check("после волны 1: экрана расширения нет, сразу дальше (%s)" % current_scene.name,
		current_scene != battle)

	# 2. После боя волны 2 (следующая — 3, расширение) — экран с ценой, переход ждёт кнопку
	battle = await _open_battle(2)
	await _finish_battle(battle, 2)
	var banner = battle.expansion_banner
	var text = _banner_text(banner) if is_instance_valid(banner) else ""
	_check("после волны 2: экран «Пришло время расширяться», цена %d Req, ещё в бою" % bm.get_tile_cost(),
		current_scene == battle and text.contains("РАСШИРЯТЬСЯ") and text.contains(GameConstants.coins(bm.get_tile_cost())))

	# 3. «ДАЛЕЕ» — дальше по цепочке (выбор карты волны 3)
	_check("кнопка экрана — «ДАЛЕЕ» (%s)" % banner.button.text, banner.button.text == "ДАЛЕЕ")
	banner.button.pressed.emit()
	await _frames(3)

	# После волны 8 следующим идёт событие — на кнопке «ДАЛЕЕ», а не «В МАГАЗИН»
	battle = await _open_battle(8)
	await _finish_battle(battle, 8)
	_check("после волны 8 (дальше событие): кнопка «%s»" % battle.expansion_banner.button.text,
		battle.expansion_banner.button.text == "ДАЛЕЕ")
	bm.stop_battle()

	# 4. Расстановка волны 3: баннера нет, подсказка с ценой клетки в шапке
	battle = await _open_battle(3)
	var hint: String = battle.hud._message.text
	_check("расстановка волны 3: баннера нет, подсказка «%s»" % hint,
		bm.can_expand_kingdom() and not is_instance_valid(battle.expansion_banner) \
		and hint.contains(GameConstants.coins(bm.get_tile_cost())))
	quit()
