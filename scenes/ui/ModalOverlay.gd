class_name ModalOverlay
extends ColorRect

# Модальное окно: затемнение на весь экран (ловит клики) и панель по центру.
# Наследники наполняют content (VBoxContainer) в своём setup().
# Работает и на паузе (PROCESS_MODE_ALWAYS) — пауза, настройки, подтверждения.

const DIM_COLOR = UITheme.DIM_OVERLAY

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
	add_child(_make_vignette())
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = UITheme.make_panel("WindowPanel")
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	add_frame_eagle(panel)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)

# Виньетка поверх затемнения: края экрана темнее, окно — в круге света (стилизация 20.10.2026)
const VIGNETTE_EDGE = Color(0, 0, 0, 0.55)
static var _vignette_tex: GradientTexture2D
static func _make_vignette() -> TextureRect:
	if _vignette_tex == null:
		var g = Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0))
		g.set_color(1, VIGNETTE_EDGE)
		g.add_point(0.45, Color(0, 0, 0, 0))
		_vignette_tex = GradientTexture2D.new()
		_vignette_tex.gradient = g
		_vignette_tex.fill = GradientTexture2D.FILL_RADIAL
		_vignette_tex.fill_from = Vector2(0.5, 0.5)
		_vignette_tex.fill_to = Vector2(1.0, 1.0)
	var r = TextureRect.new()
	r.texture = _vignette_tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return r

# Аквила рамки — по центру верхней кромки окна (9-slice её бы растянул — рисуется отдельно).
# Static — рамку окна берут и сцены без затемнения (EventScene)
static func add_frame_eagle(panel: PanelContainer) -> void:
	if not ResourceLoader.exists(UITheme.WINDOW_EAGLE):
		return
	var eagle: Texture2D = load(UITheme.WINDOW_EAGLE)
	var size := eagle.get_size() * UITheme.UI_ART_SCALE   # нарисована ×2 к экрану (пакет menu_ui)
	panel.draw.connect(func():
		panel.draw_texture_rect(eagle, Rect2(Vector2(round((panel.size.x - size.x) / 2.0), 0.0), size), false))

func add_title(text: String, variation: String = "TitleLabel") -> Label:
	var l = UITheme.make_label(text, variation)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(l)
	if variation == "TitleLabel":
		_add_divider()
	return l

# Разделитель с черепом (лист UI_assets.png) под заголовком окна — как в главном меню
const DIVIDER_HEIGHT: float = 22.0
func _add_divider() -> void:
	var d := make_divider()
	if d:
		content.add_child(d)

static func make_divider() -> TextureRect:
	if not ResourceLoader.exists(UITheme.DIVIDER_SKULL):
		return null
	var d = TextureRect.new()
	d.name = "TitleDivider"
	d.texture = load(UITheme.DIVIDER_SKULL)
	d.custom_minimum_size = Vector2(0, DIVIDER_HEIGHT)
	d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	d.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	d.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

# Карточка выбора (кнопка, внутри VBox на всю площадь с отступом pad): текст выше карточки — карточка растёт
# по нему, а не обрезает (25.10.2026: описание ордена / бога вылезало за низ). Звать после add_child карточки —
# высота текста с переносом считается по шрифту темы в дереве; соседи в ряду HBox тянутся до той же высоты
static func fit_card_to_content(card: Control, box: Control, pad: float) -> void:
	box.offset_top = pad
	box.offset_bottom = -pad
	(func():
		if is_instance_valid(card) and is_instance_valid(box):
			card.custom_minimum_size.y = maxf(card.custom_minimum_size.y,
				box.get_combined_minimum_size().y + pad * 2.0)).call_deferred()

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

# Фокус в следующем кадре — если окно к тому времени не закрыли вместе со сценой. Скрытый (hide_focus, Godot 4.6):
# Enter / стрелки работают, но рамка фокуса не горит, пока игрок не начал навигацию клавиатурой (решение
# пользователя 07.11.2026, Screenshot 2026-11-07 114006.png: первый орден / бог подсвечивался сразу — подсвечен
# должен быть только тот, что выбирает игрок)
static func focus_later(c: Control) -> void:
	(func():
		if is_instance_valid(c) and c.is_inside_tree():
			c.grab_focus(true)).call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if close_on_cancel and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	queue_free()
