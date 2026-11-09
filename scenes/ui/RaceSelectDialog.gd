class_name RaceSelectDialog
extends ModalOverlay

# Выбор расы нового забега (FactionTheme.FACTIONS): карточка на расу, закрытые
# расы видны, но недоступны («Скоро»). chosen(faction) — по выбору доступной;
# окно закрывается и при выборе, и по «Отмена».

const CARD_SIZE = Vector2(200, 220)
const CARD_PADDING: float = 14.0
const ART_ICON = "res://assets/ui/menu/icon_eagle.png"   # нет эмблемы расы (assets/ui/races/<id>.png)
const EMBLEM_SIZE: float = 84.0

signal chosen(faction: String)

var _chosen: bool = false   # двойной клик в одном кадре не запустит забег дважды

func setup() -> void:
	close_on_cancel = true
	build_frame(700.0)
	add_title("ВЫБОР РАСЫ")
	add_title("Раса определяет армию, поле боя и цитадель", "DimLabel")
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	content.add_child(row)
	var first_available: Control = null
	for f in FactionTheme.FACTIONS:
		var card = _make_card(f)
		row.add_child(card)
		if f["available"] and first_available == null:
			first_available = card
	_focus_taken = true   # фокус — на первую доступную расу, а не на «Отмена»
	add_button("Отмена", close)
	ModalOverlay.focus_later(first_available)

func _make_card(f: Dictionary) -> Control:
	var available: bool = f["available"]
	var card = Button.new()
	card.name = "Race_" + f["id"]
	card.custom_minimum_size = CARD_SIZE
	card.disabled = not available
	card.theme_type_variation = "SelectCard"
	card.pressed.connect(choose.bind(f["id"]))
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = CARD_PADDING
	box.offset_right = -CARD_PADDING
	# от верха (решение пользователя 07.11.2026, Screenshot 2026-11-07 114006.png): по центру значок и имя у карточек
	# с описанием разной длины стояли на разной высоте
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var emblem := UITheme.make_icon("races", f["id"], EMBLEM_SIZE)   # эмблема расы пакета интерфейса
	if emblem:
		emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if not available:
			emblem.modulate = Color(0.45, 0.45, 0.5)
		box.add_child(emblem)
	elif available:
		var icon = TextureRect.new()
		icon.texture = load(ART_ICON)
		icon.custom_minimum_size = Vector2(0, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = UITheme.GOLD_BRIGHT
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
	var name_label = UITheme.make_label(f["name"], "HeaderLabel")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not available:
		name_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(name_label)
	var desc = UITheme.make_label(f["desc"] if available else "Скоро", "SmallLabel" if available else "DimLabel")
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(CARD_SIZE.x - CARD_PADDING * 2.0, 0)
	box.add_child(desc)
	for c in box.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ModalOverlay.fit_card_to_content(card, box, CARD_PADDING)
	return card

# Выбор расы; закрытую выбрать нельзя
func choose(faction: String) -> void:
	if _chosen or not FactionTheme.is_available(faction):
		return
	_chosen = true
	emit_signal("chosen", faction)
	close()
