class_name GodPickDialog
extends ModalOverlay

# Выбор нового бога отряда Хаоса — карта «Chaos Gods' Blessing» на расстановке (BattleScene._play_change_god,
# решение пользователя 25.10.2026). Четыре бога (ChaosGods), нынешний бог отряда — недоступен; chosen(god) —
# по выбору, «Отмена» — карта остаётся в руке

const CARD_SIZE = Vector2(170, 210)
const EMBLEM_SIZE: float = 64.0
const CARD_PADDING: float = 10.0
# Что даёт благословение бога — подпись карточки
const HINTS = {
	"khorne": "Благословения: урон ближнего боя, без отступления",
	"nurgle": "Благословения: HP и яд в атаках, меньше урона",
	"tzeentch": "Благословения стрелкам: дальность и урон, реже стреляют",
	"slaanesh": "Благословения: шанс поработить врага, статы ниже",
}

signal chosen(god: String)

var _chosen: bool = false

func setup(squad_name: String, current_god: String) -> void:
	close_on_cancel = true
	build_frame(780.0)
	add_title("БЛАГОСЛОВЕНИЕ БОГОВ ХАОСА")
	add_title("%s: сейчас — %s. Новый бог; благословения отряда пропадут" % [squad_name,
		ChaosGods.god_name(current_god) if current_god != "" else "без бога"], "DimLabel")
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var first: Control = null
	for god in ChaosGods.GODS:
		var card = _make_card(god, god == current_god)
		row.add_child(card)
		if first == null and not card.disabled:
			first = card
	_focus_taken = true
	add_button("Отмена", close)
	ModalOverlay.focus_later(first)

func _make_card(god: String, current: bool) -> Button:
	var card = Button.new()
	card.name = "God_" + god
	card.custom_minimum_size = CARD_SIZE
	card.disabled = current
	card.theme_type_variation = "SelectCard"
	card.pressed.connect(choose.bind(god))
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = CARD_PADDING
	box.offset_right = -CARD_PADDING
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var emblem := UITheme.make_icon("emblems", god, EMBLEM_SIZE)
	if emblem:
		emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if current:
			emblem.modulate = Color(0.45, 0.45, 0.5)
		box.add_child(emblem)
	var name_label = UITheme.make_label(ChaosGods.god_name(god), "HeaderLabel")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # «Король Второго Акта» (201 px) раздувал карточку 170 px
	name_label.custom_minimum_size = Vector2(CARD_SIZE.x - CARD_PADDING * 2.0, 0)
	box.add_child(name_label)
	var hint = UITheme.make_label("Бог отряда сейчас" if current else HINTS[god], "DimLabel" if current else "SmallLabel")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(CARD_SIZE.x - CARD_PADDING * 2.0, 0)
	box.add_child(hint)
	for child in box.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ModalOverlay.fit_card_to_content(card, box, CARD_PADDING)
	return card

func choose(god: String) -> void:
	if _chosen or not god in ChaosGods.GODS:
		return
	_chosen = true
	emit_signal("chosen", god)
	close()
