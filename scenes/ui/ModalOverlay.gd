class_name ModalOverlay
extends ColorRect

# Модальное окно: затемнение на весь экран (ловит клики) и панель по центру.
# Наследники наполняют content (VBoxContainer) в своём setup().
# Работает и на паузе (PROCESS_MODE_ALWAYS) — пауза, настройки, подтверждения.

const DIM_COLOR = Color(0, 0, 0, 0.65)

var content: VBoxContainer
# Esc (ui_cancel) закрывает окно. Включают окна-вопросы (подтверждение, выбор расы,
# настройки); меню паузы — нет, Esc там обрабатывает PauseMenu (снимает паузу)
var close_on_cancel: bool = false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# Вызвать из setup() наследника после add_child
func build_frame(width: float) -> void:
	color = DIM_COLOR
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = UITheme.make_panel("WindowPanel")
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	_add_frame_eagle(panel)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)

# Аквила рамки — по центру верхней кромки окна (9-slice её бы растянул — рисуется отдельно)
func _add_frame_eagle(panel: PanelContainer) -> void:
	if not ResourceLoader.exists(UITheme.WINDOW_EAGLE):
		return
	var eagle: Texture2D = load(UITheme.WINDOW_EAGLE)
	panel.draw.connect(func():
		panel.draw_texture(eagle, Vector2(round((panel.size.x - eagle.get_width()) / 2.0), 0.0)))

func add_title(text: String, variation: String = "TitleLabel") -> Label:
	var l = UITheme.make_label(text, variation)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(l)
	return l

func add_button(text: String, on_pressed: Callable, variation: String = "") -> Button:
	var b = UITheme.make_button(text, variation, on_pressed)
	b.custom_minimum_size = Vector2(0, 46)
	content.add_child(b)
	# Фокус — на первую кнопку окна: иначе он остаётся на кнопке под затемнением
	# (Enter / пробел нажали бы её — второе окно, выход из игры)
	if not _focus_taken:
		_focus_taken = true
		ModalOverlay.focus_later(b)
	return b

var _focus_taken: bool = false

# Фокус в следующем кадре — если окно к тому времени не закрыли вместе со сценой
static func focus_later(c: Control) -> void:
	(func():
		if is_instance_valid(c) and c.is_inside_tree():
			c.grab_focus()).call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if close_on_cancel and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	queue_free()
