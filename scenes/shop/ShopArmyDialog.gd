class_name ShopArmyDialog
extends ModalOverlay

# «Армия» — значок в шапке магазина (решение пользователя 12.11.2026, образец download.png): отряды на поле
# (уровень, бойцы из полного состава, здоровье), здания с уровнем и прочность цитадели. Только просмотр.

const WIDTH: float = 520.0
const LIST_MAX_HEIGHT: float = 330.0

func setup() -> void:
	close_on_cancel = true
	build_frame(WIDTH)
	add_title("АРМИЯ")
	add_title("Цитадель: %d/%d" % [ceili(BattleManager.citadel_hp), int(BattleManager.CITADEL_MAX_HP)], "DimLabel")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var squads := 0
	for unit in BattleManager.player_units:
		if unit.saved_hp.is_empty():
			continue
		squads += 1
		var hp := 0.0
		for h in unit.saved_hp:
			hp += h
		var line := "%s · ур. %d/%d · бойцов %d/%d · здоровье %d%%" % [unit.display_name(), unit.squad_level, UnitFactory.MAX_SQUAD_LEVEL,
			unit.saved_hp.size(), maxi(unit.squad_size, unit.saved_hp.size()), roundi(hp / unit.saved_hp.size() * 100.0)]
		list.add_child(_row(line, "ValueLabel"))
	if squads == 0:
		list.add_child(_row("Отрядов на поле нет", "DimLabel"))
	if not BattleManager.player_buildings.is_empty():
		list.add_child(_row("ЗДАНИЯ", "HeaderLabel"))
		for card in BattleManager.player_buildings:
			list.add_child(_row("%s · ур. %d" % [card.display_title(), card.building_level], "ValueLabel"))
	# Список не выше экрана: дальше — прокрутка
	(func():
		if is_instance_valid(list):
			scroll.custom_minimum_size.y = minf(list.get_combined_minimum_size().y, LIST_MAX_HEIGHT)).call_deferred()
	add_button("Закрыть", close)

func _row(text: String, variation: String) -> Label:
	var l := UITheme.make_label(text, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
