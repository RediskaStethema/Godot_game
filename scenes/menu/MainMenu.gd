extends Control

# Главное меню — главная сцена. «Продолжить» — есть сохранение забега
# (SaveManager), «Новый забег» — сброс и магазин 1-й волны (при сохранении —
# с подтверждением), «Настройки» — GameSettings.
# Вид — по концепту assets_menu.png: слева аквила, название и кнопки
# (UITheme «MainMenuButton» с иконками), справа сцена с башней над планетой.
# UI собирается кодом, стили — из UITheme.

const BUTTON_SIZE = Vector2(320, 52)
const MENU_LEFT: float = 72.0          # отступ колонки меню от левого края
const LOGO_SCALE: float = 1.25
const SCENE_FADE_WIDTH: float = 260.0  # переход сцены справа в фон, px
const ART_DIR = "res://assets/ui/menu/"

var continue_button: Button = null
var info_label: Label = null

func _ready() -> void:
	_build_layout()
	continue_button.visible = SaveManager.has_save()
	if continue_button.visible:
		info_label.text = "Есть сохранённый забег"
	# Первая кнопка в фокусе — подсвечена, как в концепте (и Enter сразу работает)
	(continue_button if continue_button.visible else _new_run_button()).grab_focus()

func _build_layout() -> void:
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_make_backdrop())
	_add_scene_art()

	var col = VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = MENU_LEFT
	col.offset_right = MENU_LEFT + BUTTON_SIZE.x
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	col.add_child(_make_title_block())
	col.add_child(_spacer(14))
	continue_button = _make_button("ПРОДОЛЖИТЬ", "icon_continue", _on_continue_pressed)
	col.add_child(continue_button)
	var new_run = _make_button("НОВЫЙ ЗАБЕГ", "icon_eagle", _on_new_run_pressed)
	new_run.name = "NewRunButton"
	col.add_child(new_run)
	col.add_child(_make_button("НАСТРОЙКИ", "icon_settings", _on_settings_pressed))
	col.add_child(_make_button("ВЫХОД", "icon_quit", _on_quit_pressed))

	info_label = UITheme.make_label("", "SmallLabel")
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", UITheme.MENU_AMBER)
	col.add_child(info_label)

func _new_run_button() -> Button:
	return find_child("NewRunButton", true, false)

# Фон: холодная ночь — светлее слева за меню, к сцене справа темнее
func _make_backdrop() -> TextureRect:
	var g = Gradient.new()
	g.set_color(0, UITheme.MENU_BG_LIGHT)
	g.set_color(1, UITheme.MENU_BG)
	g.set_offset(1, 0.55)   # к сцене справа — ровно цвет растворения, без шва
	var tex = GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

# Сцена справа на всю высоту; левый край растворяется в фоне
func _add_scene_art() -> void:
	var art = TextureRect.new()
	art.texture = load(ART_DIR + "menu_scene.png")
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	art.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	# Растворение: от цвета фона к прозрачному поверх левого края сцены
	var g = Gradient.new()
	g.set_color(0, UITheme.MENU_BG)
	g.set_color(1, Color(UITheme.MENU_BG, 0.0))
	var tex = GradientTexture2D.new()
	tex.gradient = g
	var fade = TextureRect.new()
	fade.texture = tex
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Полоса — дочерняя сцене, прижата к её левому краю на всю высоту
	art.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	fade.offset_left = -2.0
	fade.offset_right = SCENE_FADE_WIDTH

# Аквила, название, подпись — как шапка меню в концепте
func _make_title_block() -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var eagle = TextureRect.new()
	eagle.texture = load(ART_DIR + "logo_eagle.png")
	eagle.custom_minimum_size = eagle.texture.get_size() * LOGO_SCALE
	eagle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eagle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	eagle.modulate = UITheme.TEXT
	box.add_child(eagle)
	var title = UITheme.make_label("WH40KINGS", "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", UITheme.TEXT)
	box.add_child(title)
	var sub = UITheme.make_label("———  УДЕРЖИТЕ ЦИТАДЕЛЬ 15 ВОЛН  ———", "DimLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	return box

func _spacer(h: float) -> Control:
	var c = Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _make_button(text: String, icon_name: String, handler: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.theme_type_variation = "MainMenuButton"
	b.icon = load(ART_DIR + icon_name + ".png")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = BUTTON_SIZE
	b.pressed.connect(handler)
	b.mouse_entered.connect(b.grab_focus)   # наведение и фокус — одна подсветка
	return b

func _on_continue_pressed() -> void:
	if not SaveManager.load_run():
		continue_button.visible = false
		info_label.text = "Сохранение не читается — начните новый забег"
		return
	RunManager.resume()

func _on_new_run_pressed() -> void:
	if not SaveManager.has_save():
		_start_new_run()
		return
	var dialog = ConfirmDialog.new()
	add_child(dialog)
	dialog.setup("Начать новый забег? Сохранённый забег будет потерян.", "НАЧАТЬ ЗАНОВО")
	dialog.confirmed.connect(_start_new_run)

func _start_new_run() -> void:
	BattleManager.reset_run()
	SaveManager.delete_save()
	RunManager.advance()

func _on_settings_pressed() -> void:
	var panel = SettingsPanel.new()
	add_child(panel)
	panel.setup()

func _on_quit_pressed() -> void:
	get_tree().quit()
