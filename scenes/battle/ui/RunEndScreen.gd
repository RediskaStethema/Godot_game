class_name RunEndScreen
extends ModalOverlay

# Экран конца забега (TDD: Victory / Game Over): итог и выбор — новый забег
# или главное меню. Что делать, решает BattleScene по сигналам.

signal new_run_pressed
signal main_menu_pressed

const PANEL_WIDTH: float = 480.0

func setup(victory: bool, subtitle: String, stats: String) -> void:
	build_frame(PANEL_WIDTH)
	var title = add_title("ПОБЕДА" if victory else "ЦИТАДЕЛЬ ПАЛА")
	if not victory:
		title.add_theme_color_override("font_color", UITheme.RED_BRIGHT)
	add_title(subtitle, "HeaderLabel")
	add_title(stats, "SmallLabel")
	add_button("НОВЫЙ ЗАБЕГ", func(): emit_signal("new_run_pressed"), "PrimaryButton")
	add_button("В главное меню", func(): emit_signal("main_menu_pressed"))
