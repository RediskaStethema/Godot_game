class_name ChapterSelectDialog
extends ModalOverlay

# Выбор ордена (Космодесант) или бога-покровителя (Хаос) нового забега (Chapters) — после выбора расы.
# chosen(chapter) — по выбору; «Отмена» закрывает окно без старта забега.

const CARD_SIZE = Vector2(170, 330)   # эмблема, бонус, минус и особые карты ордена
const EMBLEM_SIZE: float = 64.0
const CARD_PADDING: float = 10.0

signal chosen(chapter: String)

var _chosen: bool = false   # двойной клик в одном кадре не запустит забег дважды

func setup(faction: String = Chapters.FACTION) -> void:
	close_on_cancel = true
	build_frame(860.0)
	var text: Array = Chapters.SELECT_TEXT.get(faction, Chapters.SELECT_TEXT[Chapters.FACTION])
	add_title(text[0])
	add_title(text[1], "DimLabel")
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	var first: Control = null
	for c in Chapters.for_faction(faction):
		var card = _make_card(c)
		row.add_child(card)
		if first == null and not card.disabled:
			first = card
	_focus_taken = true   # фокус — на первый орден, а не на «Отмена»
	add_button("Отмена", close)
	ModalOverlay.focus_later(first)

func _make_card(c: Dictionary) -> Control:
	var card = Button.new()
	card.name = "Chapter_" + c["id"]
	card.custom_minimum_size = CARD_SIZE
	var open := MetaProgress.is_chapter_unlocked(c["id"])
	card.disabled = not open
	card.theme_type_variation = "SelectCard"
	card.pressed.connect(choose.bind(c["id"]))
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = CARD_PADDING
	box.offset_right = -CARD_PADDING
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var emblem := UITheme.make_icon("emblems", c["id"], EMBLEM_SIZE)   # эмблема ордена / бога (пакет интерфейса)
	if emblem:
		emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if not open:
			emblem.modulate = Color(0.45, 0.45, 0.5)
		box.add_child(emblem)
	var name_label = UITheme.make_label(c["name"], "HeaderLabel")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	var desc = UITheme.make_label(c["desc"] if open else MetaProgress.unlock_text(MetaProgress.CHAPTER_UNLOCKS[c["id"]]),
		"SmallLabel" if open else "DimLabel")
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(CARD_SIZE.x - CARD_PADDING * 2.0, 0)
	box.add_child(desc)
	# Минус и особые карты (решение пользователя 18.10.2026) — у открытых орденов
	if open:
		if c.has("malus_desc"):
			var malus = _wrapped_label("Минус: " + c["malus_desc"], "SmallLabel")
			malus.add_theme_color_override("font_color", UITheme.RED_BRIGHT)
			box.add_child(malus)
		var specials: Array[String] = []
		for key in ["unit_card", "building_card"]:
			var card_data := CardFactory.special_card(c.get(key, ""))
			if card_data:
				specials.append(card_data.title)
		if not specials.is_empty():
			box.add_child(_wrapped_label("Особые: " + ", ".join(specials), "DimLabel"))
	for child in box.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card

func _wrapped_label(text: String, variation: String) -> Label:
	var l = UITheme.make_label(text, variation)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(CARD_SIZE.x - CARD_PADDING * 2.0, 0)
	return l

func choose(chapter: String) -> void:
	if _chosen or Chapters.get_chapter(chapter).is_empty() or not MetaProgress.is_chapter_unlocked(chapter):
		return
	_chosen = true
	emit_signal("chosen", chapter)
	close()
