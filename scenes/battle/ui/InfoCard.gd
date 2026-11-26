class_name InfoCard
extends PanelContainer

# Карточка-справка на поле (решение пользователя 23.10.2026, образец — справка 9 Kings,
# `Screenshot 2026-10-23 134613.png`): портрет в рамке слева в шапке, имя на плашке, справа — значок (бойцы, HP);
# ниже — текст с цветными числами (BBCode), снизу по кромке — ромбики уровня. Отряд и цитадель — SquadInspector.
#   setup(портрет, имя, значок, текст, уровень, макс. уровень, цвет плашки) — max_level 0: ромбиков нет
#   fit(высота) — не выше доступной: шире (WIDTHS), не помогло — мельче текст (BODY_FONT_STEPS); решение
#   пользователя 24.10.2026: справка цитадели с синергиями уходила за низ экрана

const WIDTH: float = 270.0
const PORTRAIT: float = 58.0
const PIP: float = 7.0            # полудиагональ ромбика уровня
const PIP_STEP: float = 22.0
const TITLE_FONT: int = 17
const BADGE_FONT: int = 16
const BODY_FONT: int = 14
const WIDTHS: Array[float] = [270.0, 340.0, 420.0, 520.0]
const BODY_FONT_STEPS: Array[int] = [14, 12, 11, 10]
const BODY_MARGIN: float = 12.0   # поля текста слева и справа
const PORTRAIT_INSET: float = 5.5 # окно рамки портрета: ~12 px с края из 128 → на 58 px
const NAME_PLATE_HEIGHT: float = 28.0   # плашка имени (арт 400×56, ×0.5)
const PIP_ART: float = 18.0       # ромбик уровня художника на экране (32 px арта)

var _portrait: TextureRect
var _plate: PanelContainer
var _title: Label
var _badge: Label
var _body: RichTextLabel
var _pips: Control
var _level := 0
# Ромбики художника — загружены заранее: текстура, загруженная в _draw, освобождается до отрисовки (белый квадрат)
var _pip_on: Texture2D = UITheme.ui_icon("info", "pip_on")
var _pip_off: Texture2D = UITheme.ui_icon("info", "pip_off")
var _max_level := 0

func _init() -> void:
	theme = UITheme.get_theme()   # без темы текст — системным шрифтом, не пиксельным основным (RetroSans)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0)
	# Рамка карточки — арт info/info_frame (UI_NEEDED 8.1), нет файла — плоская
	var frame_art := UITheme.art_style("info/info_frame", UITheme.INFO_FRAME_MARGIN, UITheme.INFO_CONTENT_MARGIN)
	add_theme_stylebox_override("panel", frame_art if frame_art
		else UITheme.panel_style(Palette.PANEL, Palette.GOLD_DIM, 2, 8, 0.0))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	add_child(col)

	# Шапка: портрет + плашка с именем и значком
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 0)
	col.add_child(head)
	# Портрет — в окне рамки info/portrait_frame (128 px арта, окно ~104 — PORTRAIT_INSET с краю), нет файла — плоская
	var frame_tex: Texture2D = UITheme.ui_icon("info", "portrait_frame")
	var frame := Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	head.add_child(frame)
	if frame_tex == null:
		var flat := Panel.new()
		flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flat.add_theme_stylebox_override("panel", UITheme.panel_style(Palette.BG_DEEP, Palette.GOLD_DIM, 2, 6, 2.0))
		frame.add_child(flat)
		flat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:   # тёмная подложка под портретом в окне рамки
		var back := ColorRect.new()
		back.color = Palette.BG_DEEP
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(back)
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_inset(back, PORTRAIT_INSET)
	_portrait = TextureRect.new()
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	frame.add_child(_portrait)
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inset(_portrait, PORTRAIT_INSET if frame_tex else 2.0)
	if frame_tex:
		var over := TextureRect.new()
		over.name = "PortraitFrame"
		over.texture = frame_tex
		over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		over.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		over.stretch_mode = TextureRect.STRETCH_SCALE
		over.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		frame.add_child(over)
		over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_plate)
	var plate_row := HBoxContainer.new()
	plate_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(plate_row)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.add_theme_font_override("font", UITheme.ui_font())
	_title.add_theme_font_size_override("font_size", UITheme.ui_px(TITLE_FONT))
	_title.add_theme_color_override("font_color", Palette.TEXT)
	_title.add_theme_constant_override("outline_size", 0)
	plate_row.add_child(_title)
	_badge = Label.new()
	_badge.add_theme_font_override("font", UITheme.ui_font())
	_badge.add_theme_font_size_override("font_size", UITheme.ui_px(BADGE_FONT))
	_badge.add_theme_color_override("font_color", Palette.TEXT)
	plate_row.add_child(_badge)

	# Текст
	var body_margin := MarginContainer.new()
	body_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		body_margin.add_theme_constant_override("margin_" + side, int(BODY_MARGIN))
	body_margin.add_theme_constant_override("margin_top", 8)
	body_margin.add_theme_constant_override("margin_bottom", 4)
	col.add_child(body_margin)
	_body = RichTextLabel.new()
	# Ловит мышь: подсказки [hint] по названиям бафов (решение пользователя 10.11.2026); клик по тексту
	# справки до поля не доходит — справка не закрывается и не выбирает отряд под ней
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(WIDTH - BODY_MARGIN * 2.0, 0)
	_body.add_theme_font_size_override("normal_font_size", UITheme.text_px(BODY_FONT))
	_body.add_theme_color_override("default_color", Palette.TEXT)
	body_margin.add_child(_body)

	# Ромбики уровня — по нижней кромке
	_pips = Control.new()
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.custom_minimum_size = Vector2(0, PIP * 2.0 + 6.0)
	_pips.draw.connect(_draw_pips)
	col.add_child(_pips)

func setup(portrait: Texture2D, title: String, badge: String, body: String, level: int, max_level: int,
		accent: Color) -> void:
	_portrait.texture = portrait
	_portrait.get_parent().visible = portrait != null
	_title.text = title
	_badge.text = badge
	# Плашка имени — арт info/name_plate_<редкость> (светлое поле, имя тёмными чернилами, как на картах);
	# редкость — по цвету accent (UITheme.RARITY_COLORS), иначе (цитадель, золото) — эпическая
	var plate_art := UITheme.art_style("info/name_plate_" + _rarity_of(accent), UITheme.NAME_PLATE_MARGIN,
		UITheme.NAME_PLATE_CONTENT_MARGIN)
	if plate_art:
		_plate.add_theme_stylebox_override("panel", plate_art)
		_plate.custom_minimum_size.y = NAME_PLATE_HEIGHT
		for l in [_title, _badge]:
			l.add_theme_color_override("font_color", UITheme.CARD_INK)
	else:
		_plate.add_theme_stylebox_override("panel", UITheme.panel_style(accent.darkened(0.55), accent.darkened(0.2), 1, 0, 6.0))
	if _body.text != body:
		_body.text = body
	_level = level
	_max_level = max_level
	_pips.visible = max_level > 0
	_pips.queue_redraw()

# Ширина и кегль текста, при которых карточка не выше max_height (самая узкая из подходящих; ничего не
# подошло — самая широкая с самым мелким текстом). Высота текста — по его ширине сразу, без кадра раскладки
func fit(max_height: float) -> void:
	var chrome := get_combined_minimum_size().y - _body.get_combined_minimum_size().y   # шапка, поля, ромбики
	for font in BODY_FONT_STEPS:
		_body.add_theme_font_size_override("normal_font_size", UITheme.text_px(font))
		for w in WIDTHS:
			_set_width(w)
			if chrome + _body.get_content_height() <= max_height:
				return
	# Ничего не подошло — остаётся самое компактное (последнее)

func _set_width(w: float) -> void:
	custom_minimum_size.x = w
	_body.custom_minimum_size.x = w - BODY_MARGIN * 2.0
	_body.size.x = w - BODY_MARGIN * 2.0

func _draw_pips() -> void:
	var w := _pips.size.x
	var y := _pips.size.y - PIP - 2.0
	var on := _pip_on
	var off := _pip_off
	for i in _max_level:
		var c := Vector2(w / 2.0 + (i - (_max_level - 1) / 2.0) * PIP_STEP, y)
		if on and off:   # ромбики художника (UI_NEEDED 8.1d): горит — янтарь, не набран — тёмная сталь
			var sz := Vector2(PIP_ART, PIP_ART)
			_pips.draw_texture_rect(on if i < _level else off, Rect2(c - sz / 2.0, sz), false)
			continue
		var pts := PackedVector2Array([c + Vector2(0, -PIP), c + Vector2(PIP, 0), c + Vector2(0, PIP), c + Vector2(-PIP, 0)])
		_pips.draw_colored_polygon(pts, Palette.GOLD_BRIGHT if i < _level else Palette.BG_DEEP)
		pts.append(pts[0])
		_pips.draw_polyline(pts, Palette.TEXT, 1.5, true)
		if i < _level:   # дошёл — светлое ядро, как на образце
			_pips.draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), Palette.BG_DEEP)

func _inset(c: Control, px: float) -> void:
	c.offset_left = px
	c.offset_top = px
	c.offset_right = -px
	c.offset_bottom = -px

static func _rarity_of(accent: Color) -> String:
	for r in UITheme.RARITY_COLORS:
		if UITheme.RARITY_COLORS[r].is_equal_approx(accent):
			return r
	return "epic"

# Числа в тексте — цветом (описание карты: «+3 золотых», «25% HP»)
static func color_numbers(text: String, color: Color) -> String:
	var re := RegEx.new()
	re.compile("([+−-]?\\d+(?:[.,]\\d+)?%?)")
	return re.sub(text, "[color=#%s]$1[/color]" % color.to_html(false), true)

# Название бафа с подсказкой при наведении (BBCode [hint], подчёркнуто): tip — коротко, что делает.
# Кавычки в подсказке экранировать нельзя — двойные заменяются одинарными
static func hint(text: String, tip: String) -> String:
	if tip == "":
		return text
	return "[hint=\"%s\"]%s[/hint]" % [tip.replace("\"", "'"), text]

# Строка «Подпись: значение» со значением цветом
static func stat(label: String, value: String, color: Color = Palette.GOLD_BRIGHT) -> String:
	return "%s: [color=#%s]%s[/color]" % [label, color.to_html(false), value]
