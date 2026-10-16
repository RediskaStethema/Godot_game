class_name UITheme
extends RefCounted

# -------------------------------------------------------
# ПАЛИТРА — по концепту меню assets_menu.png: холодный тёмно-синий металл,
# стальная окантовка, янтарь для акцентов (наведение, главное действие, цифры).
# Имена исторические: GOLD* — янтарные акценты, GOLD_DIM — сталь рамок.
# -------------------------------------------------------
const BG_DEEP      = Color("0a0e15")
const BG_MID       = Color("16202e")
const PANEL        = Color(0.055, 0.075, 0.105, 0.99)
const PANEL_DARK   = Color(0.035, 0.05, 0.075, 0.96)
const GOLD         = Color("d39a3a")
const GOLD_BRIGHT  = Color("f0b04a")
const GOLD_DIM     = Color("3b4350")
const TEXT         = Color("d5dae0")
const TEXT_DIM     = Color("7f8893")
const RED          = Color("8e2620")
const RED_BRIGHT   = Color("c8463a")
const BLUE         = Color("3f6fb0")
const GREEN        = Color("6fbf5a")

const RARITY_COLORS = {
	"common": Color("8f8a80"),
	"rare":   Color("4a8fd8"),
	"epic":   Color("b06ad8"),
}
const RARITY_NAMES = {"common": "Обычная", "rare": "Редкая", "epic": "Эпическая"}
const TYPE_NAMES = {"squad": "Отряд", "building": "Здание", "upgrade": "Улучшение", "event": "Событие"}

# Подпись типа шага забега (RunMapNode.*) — в HUD боя
const NODE_NAMES = {
	"battle": "БОЙ",
	"miniboss": "МИНИ-БОСС",
	"boss":   "БОСС",
	"shop":   "МАГАЗИН",
}

# Высота HUD сверху и панели скамейки снизу (бой) — сетки ставятся между ними
const HUD_HEIGHT: float = 60.0
const BENCH_HEIGHT: float = 176.0

static var _theme: Theme = null

# -------------------------------------------------------
# ТЕМА
# -------------------------------------------------------
# Тему вешаем на корневые Control'ы сцены (theme наследуется детьми).
static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme

static func _build() -> Theme:
	var t = Theme.new()
	t.default_font_size = 16

	var serif = SystemFont.new()
	serif.font_names = PackedStringArray(["Cambria", "Georgia", "Times New Roman", "serif"])
	serif.font_weight = 600
	var sans = ui_font()

	# --- Label ---
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))

	# Заголовки окон и экранов — антиква, как «WH40KINGS» в меню; шапки и цифры — гротеск кнопок меню
	_label_variation(t, "TitleLabel", serif, 30, TEXT, 4)
	_label_variation(t, "HeaderLabel", sans, 20, GOLD, 2)
	_label_variation(t, "ValueLabel", sans, 19, GOLD_BRIGHT, 2)
	_label_variation(t, "DimLabel", null, 13, TEXT_DIM, 0)
	_label_variation(t, "SmallLabel", null, 14, TEXT, 0)

	# --- Панели: тёмный металл, стальная рамка, срезанные углы ---
	t.set_stylebox("panel", "PanelContainer", panel_style(PANEL, GOLD_DIM, 2, 10, 10))
	t.set_stylebox("panel", "Panel", panel_style(PANEL, GOLD_DIM, 2, 10, 10))
	t.set_type_variation("HudPanel", "PanelContainer")
	var hud = panel_style(PANEL_DARK, GOLD_DIM, 0, 0, 10)
	hud.border_width_bottom = 2
	hud.border_width_top = 2
	t.set_stylebox("panel", "HudPanel", hud)

	# --- Кнопки: сталь (обычная) и янтарь (главное действие) ---
	_button_styles(t, "Button", Color(BG_DEEP, 0.92), GOLD_DIM, 16, sans, 0.0)
	t.set_type_variation("PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton", Color("2b1d0d"), GOLD, 19, sans, 0.25)
	_menu_button_styles(t)

	# --- Прочие контролы окон (настройки) ---
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", GOLD_BRIGHT)
	t.set_stylebox("slider", "HSlider", panel_style(PANEL_DARK, GOLD_DIM, 1, 3, 2))
	var fill = panel_style(GOLD, GOLD, 0, 3, 2)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	return t

# -------------------------------------------------------
# МЕНЮ (главное меню, пауза) — по концепту assets_menu.png: холодный
# тёмно-синий металл, скошенные углы, иконка слева; наведение и фокус —
# золотая окантовка с подсветкой
# -------------------------------------------------------
const MENU_BG       = BG_DEEP
const MENU_BG_LIGHT = BG_MID
const MENU_STEEL    = GOLD_DIM
const MENU_TEXT     = Color("b9c0c8")
const MENU_AMBER    = GOLD_BRIGHT
const MENU_AMBER_DIM = Color("a8742a")

# Шрифт кнопок и шапок (гротеск, как в концепте)
static func ui_font() -> SystemFont:
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "sans-serif"])
	font.font_weight = 600
	return font

static func menu_button_style(bg: Color, border: Color, glow: float) -> StyleBoxFlat:
	var s = panel_style(bg, border, 2, 12, 10)
	s.content_margin_left = 18
	s.content_margin_right = 18
	if glow > 0.0:
		s.shadow_color = Color(MENU_AMBER, glow)
		s.shadow_size = 8
	return s

static func _menu_button_styles(t: Theme) -> void:
	var type = "MainMenuButton"
	t.set_type_variation(type, "Button")
	t.set_stylebox("normal", type, menu_button_style(Color(MENU_BG, 0.92), MENU_STEEL, 0.0))
	var hover = menu_button_style(Color("2b1d0d"), MENU_AMBER, 0.35)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("focus", type, hover)
	t.set_stylebox("pressed", type, menu_button_style(Color("3b270f"), MENU_AMBER_DIM, 0.2))
	t.set_stylebox("disabled", type, menu_button_style(Color(MENU_BG, 0.6), Color("262b33"), 0.0))
	t.set_font("font", type, ui_font())
	t.set_font_size("font_size", type, 18)
	t.set_color("font_color", type, MENU_TEXT)
	t.set_color("font_hover_color", type, MENU_AMBER)
	t.set_color("font_focus_color", type, MENU_AMBER)
	t.set_color("font_pressed_color", type, MENU_AMBER_DIM)
	t.set_color("font_hover_pressed_color", type, MENU_AMBER)
	t.set_color("font_disabled_color", type, Color("4a525c"))
	t.set_color("icon_normal_color", type, Color("8f98a3"))
	t.set_color("icon_hover_color", type, MENU_AMBER)
	t.set_color("icon_focus_color", type, MENU_AMBER)
	t.set_color("icon_pressed_color", type, MENU_AMBER_DIM)
	t.set_color("icon_hover_pressed_color", type, MENU_AMBER)
	t.set_constant("icon_max_width", type, 30)
	t.set_constant("h_separation", type, 16)

static func _label_variation(t: Theme, name: String, font: Font, size: int, color: Color, outline: int) -> void:
	t.set_type_variation(name, "Label")
	if font:
		t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)
	t.set_constant("outline_size", name, outline)
	t.set_color("font_outline_color", name, Color(0, 0, 0, 0.85))

# Кнопка как в меню: срезанные углы; наведение — янтарная рамка с подсветкой.
# glow — подсветка в обычном состоянии (у главной кнопки — всегда немного)
static func _button_styles(t: Theme, type: String, base: Color, border: Color, size: int, font: Font, glow: float) -> void:
	var normal = panel_style(base, border, 2, 8, 8)
	_add_glow(normal, glow)
	t.set_stylebox("normal", type, normal)
	var hover = panel_style(base.lightened(0.08) if glow == 0.0 else Color("3b270f"), GOLD_BRIGHT, 2, 8, 8)
	_add_glow(hover, 0.35)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, panel_style(base.darkened(0.3), GOLD, 2, 8, 8))
	t.set_stylebox("disabled", type, panel_style(Color(BG_DEEP, 0.6), Color("262b33"), 2, 8, 8))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, TEXT if glow == 0.0 else GOLD_BRIGHT)
	t.set_color("font_hover_color", type, GOLD_BRIGHT)
	t.set_color("font_pressed_color", type, GOLD)
	t.set_color("font_disabled_color", type, Color("4a525c"))
	t.set_font_size("font_size", type, size)
	if font:
		t.set_font("font", type, font)

# -------------------------------------------------------
# ХЕЛПЕРЫ
# -------------------------------------------------------
# radius — размер среза угла (как у кнопок меню: прямой срез, не скругление)
static func panel_style(bg: Color, border: Color, border_w: int, radius: int, margin: float) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.corner_detail = 1
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s

static func _add_glow(s: StyleBoxFlat, glow: float) -> void:
	if glow > 0.0:
		s.shadow_color = Color(GOLD_BRIGHT, glow)
		s.shadow_size = 8

static func rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS["common"])

# Рамка карты: цвет редкости, сверху — толстая полоса
static func card_style(rarity: String, highlighted: bool = false) -> StyleBoxFlat:
	var c = rarity_color(rarity)
	var s = panel_style(PANEL, c.darkened(0.25) if not highlighted else c.lightened(0.2), 2, 10, 10)
	s.border_width_top = 4
	s.shadow_color = Color(c, 0.35) if highlighted else Color(0, 0, 0, 0.5)
	s.shadow_size = 8 if highlighted else 6
	return s

# Портрет для карты отряда — первый кадр idle юнита (null для зданий/улучшений)
static func card_portrait(card: CardData) -> Texture2D:
	if card.card_type == "building":
		# Своих спрайтов у зданий нет — блок тайлсета, из которого здание собрано
		var blocks = Building.BLOCKS.get(card.building_type, [])
		return TerrainTiles.tile(blocks[-1][0]) if not blocks.is_empty() else null
	if card.card_type != "squad":
		return null
	var unit = UnitFactory.create(card.unit_factory_id)
	var path = unit.sprite_path + "/idle/0.png"
	return load(path) if ResourceLoader.exists(path) else null

static func card_tint(card: CardData) -> Color:
	if card.card_type != "squad":
		return Color.WHITE
	return UnitFactory.create(card.unit_factory_id).tint

# Фон-виньетка: холодная ночь — светлее в центре, к краям в черноту
static func make_background() -> TextureRect:
	var g = Gradient.new()
	g.set_color(0, BG_MID)
	g.set_color(1, BG_DEEP)
	var tex = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.45)
	tex.fill_to = Vector2(1.1, 1.1)
	tex.width = 256
	tex.height = 256
	var rect = TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

static func make_label(text: String, variation: String = "") -> Label:
	var l = Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	return l

# Панель в стиле UITheme (по умолчанию HudPanel). ignore_mouse — подсказки
# и всплывающие панели, которые не должны перехватывать клики
static func make_panel(variation: String = "HudPanel", ignore_mouse: bool = false) -> PanelContainer:
	var p = PanelContainer.new()
	p.theme = get_theme()
	p.theme_type_variation = variation
	if ignore_mouse:
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func make_button(text: String, variation: String = "", on_pressed: Callable = Callable()) -> Button:
	var b = Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b

static func make_spacer() -> Control:
	var c = Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
