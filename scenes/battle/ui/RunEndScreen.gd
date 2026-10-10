class_name RunEndScreen
extends ColorRect

# Экран конца забега (TDD: Victory / Game Over): затемнение, итог и кнопка
# «НОВЫЙ ЗАБЕГ» (сигнал new_run_pressed — что делать, решает BattleScene).

signal new_run_pressed

const PANEL_WIDTH: float = 480.0

func setup(victory: bool, subtitle: String, stats: String) -> void:
	color = Color(0, 0, 0, 0.65)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = UITheme.make_panel("")
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	center.add_child(panel)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	var title = UITheme.make_label("ПОБЕДА" if victory else "ЦИТАДЕЛЬ ПАЛА", "TitleLabel")
	if not victory:
		title.add_theme_color_override("font_color", UITheme.RED_BRIGHT)
	for l in [title, UITheme.make_label(subtitle, "HeaderLabel"), UITheme.make_label(stats, "SmallLabel")]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	col.add_child(UITheme.make_button("НОВЫЙ ЗАБЕГ", "PrimaryButton", func(): emit_signal("new_run_pressed")))
