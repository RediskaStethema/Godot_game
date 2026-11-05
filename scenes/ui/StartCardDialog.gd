class_name StartCardDialog
extends ModalOverlay

# Выбор стартовой карты нового забега (мета-прогрессия: открытые за Славу, MetaProgress) — после
# выбора сложности, только если хоть одна открыта. chosen(card_id) — "" — без карты; «Отмена» —
# забег не начат. Фокус — на прошлый выбор.

signal chosen(card_id: String)

var _chosen: bool = false

func setup() -> void:
	close_on_cancel = true
	build_frame(520.0)
	add_title("СТАРТОВАЯ КАРТА")
	add_title("Ляжет в руку в начале забега", "DimLabel")
	var focus: Button = null
	for id in MetaProgress.available_start_cards():
		var card := CardFactory.create(id)
		var b := add_button("%s · %s" % [card.title, card.description], choose.bind(id),
			"PrimaryButton" if id == MetaProgress.selected_start_card else "")
		b.name = "Start_" + id
		if id == MetaProgress.selected_start_card:
			focus = b
	add_button("Без стартовой карты", choose.bind(""))
	add_button("Отмена", close)
	if focus:
		ModalOverlay.focus_later(focus)

func choose(card_id: String) -> void:
	if _chosen:
		return
	_chosen = true
	emit_signal("chosen", card_id)
	close()
