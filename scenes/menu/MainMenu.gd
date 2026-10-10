extends Control

# Главное меню — главная сцена. «Продолжить» — есть сохранение забега
# (SaveManager), «Новый забег» — сброс и магазин 1-й волны.
# UI собирается кодом, стили — из UITheme.

const BUTTON_SIZE = Vector2(320, 56)

var continue_button: Button = null
var info_label: Label = null

func _ready() -> void:
	_build_layout()
	continue_button.visible = SaveManager.has_save()
	if continue_button.visible:
		info_label.text = "Есть сохранённый забег"
		continue_button.grab_focus()

func _build_layout() -> void:
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UITheme.make_background())

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title = UITheme.make_label("WH40KINGS", "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub = UITheme.make_label("Удержите цитадель 15 волн", "DimLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(Control.new())   # отступ под заголовком

	continue_button = _make_button("ПРОДОЛЖИТЬ", "PrimaryButton", _on_continue_pressed)
	col.add_child(continue_button)
	col.add_child(_make_button("НОВЫЙ ЗАБЕГ", "PrimaryButton", _on_new_run_pressed))
	col.add_child(_make_button("Выход", "", _on_quit_pressed))

	info_label = UITheme.make_label("", "SmallLabel")
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	col.add_child(info_label)

func _make_button(text: String, variation: String, handler: Callable) -> Button:
	var b = Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.custom_minimum_size = BUTTON_SIZE
	b.pressed.connect(handler)
	return b

func _on_continue_pressed() -> void:
	if not SaveManager.load_run():
		continue_button.visible = false
		info_label.text = "Сохранение не читается — начните новый забег"
		return
	RunManager.resume()

func _on_new_run_pressed() -> void:
	BattleManager.reset_run()
	SaveManager.delete_save()
	RunManager.advance()

func _on_quit_pressed() -> void:
	get_tree().quit()
