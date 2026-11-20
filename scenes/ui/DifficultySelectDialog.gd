class_name DifficultySelectDialog
extends ModalOverlay

# Выбор сложности нового забега (Difficulty) — после выбора ордена. Карточка на уровень:
# открытые (SaveManager.unlocked_difficulty) — кнопки, закрытые видны, но недоступны
# («Победите босса на N»). chosen(level) — по выбору; «Отмена» — забег не начат.
# Фокус — на самый высокий открытый уровень.

const CARD_SIZE = Vector2(132, 176)
const CARD_PADDING: float = 6.0
const NAME_FONT_SIZE: int = 15   # «Экстерминатус» — в одну строку
const ICON_SIZE: float = 56.0     # значок ранга assets/ui/difficulty/<уровень>.png

signal chosen(level: int)

var _chosen: bool = false   # двойной клик в одном кадре не запустит забег дважды

func setup() -> void:
	close_on_cancel = true
	build_frame(1040.0)
	add_title("СЛОЖНОСТЬ")
	add_title("Больше врагов в волнах и чаще сильные отряды Кровоподписантов", "DimLabel")
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	var focus: Control = null
	for level in range(1, Difficulty.COUNT + 1):
		var card = _make_card(level)
		row.add_child(card)
		if SaveManager.is_difficulty_unlocked(level):
			focus = card
	_focus_taken = true   # фокус — на самый высокий открытый уровень, а не на «Отмена»
	add_button("Отмена", close)
	ModalOverlay.focus_later(focus)

func _make_card(level: int) -> Control:
	var open = SaveManager.is_difficulty_unlocked(level)
	var d = Difficulty.get_level(level)
	var card = Button.new()
	card.name = "Difficulty_%d" % level
	card.custom_minimum_size = CARD_SIZE
	card.disabled = not open
	card.theme_type_variation = "SelectCard"
	card.pressed.connect(choose.bind(level))
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = CARD_PADDING
	box.offset_right = -CARD_PADDING
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var icon := UITheme.make_icon("difficulty", str(level), ICON_SIZE)
	if icon:
		icon.name = "RankIcon"
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if not open:
			icon.self_modulate = Color(0.45, 0.45, 0.5)
			UITheme.add_lock_badge(icon)
		box.add_child(icon)
	var num = UITheme.make_label(str(level), "TitleLabel")
	var name_label = UITheme.make_label(d["name"], "HeaderLabel")
	name_label.add_theme_font_size_override("font_size", UITheme.ui_px(NAME_FONT_SIZE))
	var info = UITheme.make_label("Враги ×%.2f\nСильные ×%.2f" % [d["enemies"], d["strong_weight"]] if open
		else "Победите босса на %d" % (level - 1), "SmallLabel" if open else "DimLabel")
	for l in [num, name_label, info]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(CARD_SIZE.x - CARD_PADDING * 2.0, 0)
		if not open:
			l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		box.add_child(l)
	for c in box.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ModalOverlay.fit_card_to_content(card, box, CARD_PADDING)
	return card

# Выбор уровня; закрытый выбрать нельзя
func choose(level: int) -> void:
	if _chosen or not SaveManager.is_difficulty_unlocked(level):
		return
	_chosen = true
	emit_signal("chosen", level)
	close()
