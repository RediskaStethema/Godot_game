class_name RunEndScreen
extends ModalOverlay

# Экран конца забега (TDD: Victory / Game Over): итог и выбор — новый забег
# или главное меню. Что делать, решает BattleScene по сигналам.
# Между заголовком и итогами — иллюстрация screens/run_victory / run_defeat (Хаос — с суффиксом _chaos).

signal new_run_pressed
signal main_menu_pressed

# Решение пользователя 07.11.2026 («надписи выезжают за поля»): с длинным итогом (слава, открытое, новая сложность)
# окно было выше экрана 648 px — кнопки уходили за нижний край. Окно шире (меньше переносов), строки итога после
# первой — мельче, иллюстрация ниже, когда строк итога больше SHORT_LINES
const PANEL_WIDTH: float = 720.0
const ART_HEIGHT: float = 250.0   # 16:9 по ширине окна — края чуть срезаны
const ART_HEIGHT_COMPACT: float = 160.0
const SHORT_LINES: int = 2

func setup(victory: bool, subtitle: String, stats: String) -> void:
	build_frame(PANEL_WIDTH)
	var title = add_title("ПОБЕДА" if victory else "ЦИТАДЕЛЬ ПАЛА")
	if not victory:
		title.add_theme_color_override("font_color", UITheme.RED_BRIGHT)
	var lines := subtitle.split("\n")
	var art := UITheme.make_illustration("screens", art_name(victory, RunManager.player_faction),
		ART_HEIGHT if lines.size() <= SHORT_LINES else ART_HEIGHT_COMPACT)
	if art:
		content.add_child(art)
	add_title(lines[0], "HeaderLabel")
	if lines.size() > 1:
		add_title("\n".join(lines.slice(1)), "ValueLabel")
	add_title(stats, "SmallLabel")
	add_button("НОВЫЙ ЗАБЕГ", func(): emit_signal("new_run_pressed"), "PrimaryButton")
	add_button("В главное меню", func(): emit_signal("main_menu_pressed"))

# Имя иллюстрации итога: своя у Хаоса, остальные расы — как Космодесант
static func art_name(victory: bool, faction: String) -> String:
	var base := "run_victory" if victory else "run_defeat"
	if faction != "space_marines" and UITheme.ui_icon("screens", base + "_" + faction) != null:
		return base + "_" + faction
	return base
