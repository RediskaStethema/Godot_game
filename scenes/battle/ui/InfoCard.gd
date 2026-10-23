class_name InfoCard
extends PanelContainer

# Карточка-справка на поле (решение пользователя 23.10.2026, образец — справка 9 Kings,
# `Screenshot 2026-10-23 134613.png`): портрет в рамке слева в шапке, имя на плашке, справа — значок (бойцы, HP);
# ниже — текст с цветными числами (BBCode), снизу по кромке — ромбики уровня. Отряд и цитадель — SquadInspector.
#   setup(портрет, имя, значок, текст, уровень, макс. уровень, цвет плашки) — max_level 0: ромбиков нет

const WIDTH: float = 270.0
const PORTRAIT: float = 58.0
const PIP: float = 7.0            # полудиагональ ромбика уровня
const PIP_STEP: float = 22.0
const TITLE_FONT: int = 17
const BADGE_FONT: int = 16
const BODY_FONT: int = 14

var _portrait: TextureRect
var _plate: PanelContainer
var _title: Label
var _badge: Label
var _body: RichTextLabel
var _pips: Control
var _level := 0
var _max_level := 0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", UITheme.panel_style(Palette.PANEL, Palette.GOLD_DIM, 2, 8, 0.0))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	add_child(col)

	# Шапка: портрет + плашка с именем и значком
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 0)
	col.add_child(head)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	frame.clip_contents = true
	frame.add_theme_stylebox_override("panel", UITheme.panel_style(Palette.BG_DEEP, Palette.GOLD_DIM, 2, 6, 2.0))
	head.add_child(frame)
	_portrait = TextureRect.new()
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	frame.add_child(_portrait)
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
	_title.add_theme_font_size_override("font_size", TITLE_FONT)
	_title.add_theme_color_override("font_color", Palette.TEXT)
	plate_row.add_child(_title)
	_badge = Label.new()
	_badge.add_theme_font_override("font", UITheme.ui_font())
	_badge.add_theme_font_size_override("font_size", BADGE_FONT)
	_badge.add_theme_color_override("font_color", Palette.TEXT)
	plate_row.add_child(_badge)

	# Текст
	var body_margin := MarginContainer.new()
	body_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		body_margin.add_theme_constant_override("margin_" + side, 12)
	body_margin.add_theme_constant_override("margin_top", 8)
	body_margin.add_theme_constant_override("margin_bottom", 4)
	col.add_child(body_margin)
	_body = RichTextLabel.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(WIDTH - 24.0, 0)
	_body.add_theme_font_size_override("normal_font_size", BODY_FONT)
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
	_plate.add_theme_stylebox_override("panel", UITheme.panel_style(accent.darkened(0.55), accent.darkened(0.2), 1, 0, 6.0))
	if _body.text != body:
		_body.text = body
	_level = level
	_max_level = max_level
	_pips.visible = max_level > 0
	_pips.queue_redraw()

func _draw_pips() -> void:
	var w := _pips.size.x
	var y := _pips.size.y - PIP - 2.0
	for i in _max_level:
		var c := Vector2(w / 2.0 + (i - (_max_level - 1) / 2.0) * PIP_STEP, y)
		var pts := PackedVector2Array([c + Vector2(0, -PIP), c + Vector2(PIP, 0), c + Vector2(0, PIP), c + Vector2(-PIP, 0)])
		_pips.draw_colored_polygon(pts, Palette.GOLD_BRIGHT if i < _level else Palette.BG_DEEP)
		pts.append(pts[0])
		_pips.draw_polyline(pts, Palette.TEXT, 1.5, true)
		if i < _level:   # дошёл — светлое ядро, как на образце
			_pips.draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), Palette.BG_DEEP)

# Числа в тексте — цветом (описание карты: «+3 золотых», «25% HP»)
static func color_numbers(text: String, color: Color) -> String:
	var re := RegEx.new()
	re.compile("([+−-]?\\d+(?:[.,]\\d+)?%?)")
	return re.sub(text, "[color=#%s]$1[/color]" % color.to_html(false), true)

# Строка «Подпись: значение» со значением цветом
static func stat(label: String, value: String, color: Color = Palette.GOLD_BRIGHT) -> String:
	return "%s: [color=#%s]%s[/color]" % [label, color.to_html(false), value]
