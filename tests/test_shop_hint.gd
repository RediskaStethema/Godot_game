extends SceneTree

# Сноска карты магазина: наведение на карту отряда / здания, который уже стоит на поле, —
# какого он уровня и пойдёт ли карта на улучшение (ShopManager.get_owned_note, ShopSlot).
# Сохранение выключено — забег игрока не трогает.
#   godot --headless --path . -s tests/test_shop_hint.gd

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _squad(card: CardData, level: int) -> UnitData:
	var d = UnitFactory.create(card.unit_factory_id)
	d.squad_size = card.unit_count
	d.squad_growth = UnitFactory.squad_growth_for(card)
	for i in level:
		d.apply_merge_upgrade()
	return d

func _slot(card: CardData):
	var slot = load("res://scenes/shop/ShopSlot.tscn").instantiate()
	root.add_child(slot)
	slot.setup(card, 0)
	return slot

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var sm = root.get_node("ShopManager")
	bm.reset_run()
	var tac_card = CardFactory.tactical_squad()

	# 1. На поле такого нет — сноски нет, и при наведении она не появляется
	var slot = _slot(tac_card)
	slot.mouse_entered.emit()
	_check("пустое поле: сноски нет", sm.get_owned_note(tac_card) == "" and not slot.owned_note.visible)

	# 2. Отряд ур.1 на поле — уровень и «можно улучшить», сноска видна при наведении
	var tac = _squad(tac_card, 1)
	bm.player_units = [tac] as Array[UnitData]
	bm.player_placements = {tac: Vector2i(1, 1)}
	slot.mouse_entered.emit()
	var shown: String = slot._owned_label.text
	_check("отряд ур.1: «%s»" % shown.replace("\n", " / "), slot.owned_note.visible
		and shown == "На поле: ур. 1/3\nможно улучшить")

	# 3. Курсор ушёл с карты — сноска скрыта
	slot.position = Vector2(600, 400)   # курсор (0, 0) теперь вне карты
	slot.mouse_exited.emit()
	_check("курсор ушёл: сноска скрыта", not slot.owned_note.visible)

	# 4. Отряд на максимуме — «максимум», карта пойдёт только на лечение
	var tac_max = _squad(tac_card, UnitFactory.MAX_SQUAD_LEVEL)
	bm.player_units = [tac_max] as Array[UnitData]
	_check("отряд ур.3: максимум", sm.get_owned_note(tac_card) == "На поле: ур. 3/3\nмаксимум — только лечение")

	# 5. Два таких отряда — оба уровня; улучшить можно, если хоть один не на максимуме
	bm.player_units = [tac_max, _squad(tac_card, 0)] as Array[UnitData]
	_check("два отряда: оба уровня", sm.get_owned_note(tac_card) == "На поле ×2: ур. 3/3, ур. 0/3\nможно улучшить")

	# 6. Другой отряд, карта-улучшение — сноски нет
	_check("чужой отряд и улучшение: сноски нет", sm.get_owned_note(CardFactory.scout_squad()) == ""
		and sm.get_owned_note(CardFactory.blessed_armour()) == "")

	# 7. Здания: уровень постройки на поле, на максимуме — «максимум»
	var turret = CardFactory.bolter_turret()
	turret.level_up_building()
	bm.player_buildings = {turret: Vector2i(0, 0)}
	var turret_note = sm.get_owned_note(CardFactory.bolter_turret())
	turret.level_up_building()
	_check("здание ур.2 → ур.3: «%s», затем максимум" % turret_note.replace("\n", " / "),
		turret_note == "На поле: ур. 2/3\nможно улучшить"
		and sm.get_owned_note(CardFactory.bolter_turret()) == "На поле: ур. 3/3\nмаксимум"
		and sm.get_owned_note(CardFactory.fortress_wall()) == "")

	slot.queue_free()
	bm.reset_run()
	quit()
