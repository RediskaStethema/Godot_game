class_name UITheme
extends RefCounted

# Палитра — scripts/ui/Palette.gd (без зависимостей); здесь те же имена для UI-кода
const BG_DEEP = Palette.BG_DEEP
const BG_MID = Palette.BG_MID
const PANEL = Palette.PANEL
const PANEL_DARK = Palette.PANEL_DARK
const GOLD = Palette.GOLD
const GOLD_BRIGHT = Palette.GOLD_BRIGHT
const GOLD_DIM = Palette.GOLD_DIM
const TEXT = Palette.TEXT
const TEXT_DIM = Palette.TEXT_DIM
const RED = Palette.RED
const RED_BRIGHT = Palette.RED_BRIGHT
const GREEN = Palette.GREEN
const OUTLINE = Palette.OUTLINE
const DIM_OVERLAY = Palette.DIM_OVERLAY
const PLAYER_SIDE = Palette.PLAYER_SIDE
const ENEMY_SIDE = Palette.ENEMY_SIDE
const AMBER_LIGHT = Palette.AMBER_LIGHT
const FIRE = Palette.FIRE
const POISON = Palette.POISON
const HEAL = Palette.HEAL
const SHIELD_BLUE = Palette.SHIELD_BLUE
const SLOW_BLUE = Palette.SLOW_BLUE
const HIT_RED = Palette.HIT_RED

const RARITY_COLORS = {
	"common": Color("9a917f"),   # кость
	"rare":   Color("5384b8"),   # сталь-синий
	"epic":   Color("9a62b8"),   # варп-фиолетовый
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
const BENCH_HEIGHT: float = 176.0   # панель синергий на расстановке
const BENCH_PEEK: float = 90.0      # видимая часть карт руки на расстановке (Bench) — камера вписывает поле выше

# Текстуры интерфейса — лист assets/source_sheets/UI_assets.png, нарезка tools/ui_from_sheet.py. Поля 9-slice:
# (лево, верх, право, низ) — края, которые не тянутся, и отступы содержимого
const UI_ART_DIR = "res://assets/ui/"
const BUTTON_TEXTURE_MARGIN = Vector4(16, 14, 16, 14)
const BUTTON_CONTENT_MARGIN = Vector4(18, 8, 18, 8)
const WINDOW_FRAME_MARGIN = Vector4(48, 44, 48, 44)
# Отступ содержимого — за уголками рамки и под аквилой (25.10.2026: кнопки и текст налезали на уголки)
const WINDOW_CONTENT_MARGIN = Vector4(38, 48, 38, 38)
const WINDOW_EAGLE = "res://assets/ui/frame_eagle.png"
const DIVIDER_SKULL = "res://assets/ui/divider_skull.png"

# Шрифты — пиксельные шрифты пользователя (assets/fonts/pixel, решение пользователя 23.10.2026; из 19 файлов
# кириллица есть у 10): ImpactfulBits — шапки, кнопки, заголовки окон, названия карт и надписи над полем,
# RetroSans — основной текст (описания, справки, подсказки). Было: Play / Play Bold, антиква Cormorant Garamond,
# Press Start 2P. Файла нет — системный, как раньше
const FONT_DIR = "res://assets/fonts/"
const FONT_UI = FONT_DIR + "pixel/RetroSans.ttf"
const FONT_UI_BOLD = FONT_DIR + "pixel/ImpactfulBits.ttf"
const FONT_WORLD = FONT_DIR + "pixel/ImpactfulBits.ttf"
# Заглавные у пиксельных шрифтов ниже доли кегля, чем у Play (0.70): ImpactfulBits 0.54, RetroSans 0.41 — кегли
# прежней разметки × множитель: заглавные чуть ниже прежних, строки почти той же ширины (иначе текст не влезает
# в кнопки и плашки: при той же высоте заглавных ImpactfulBits шире на 10%, RetroSans — на 27%).
# Надписи над полем — цифры той же высоты, что у Press Start 2P (у него заглавные — весь кегль)
const UI_FONT_SCALE: float = 1.2       # ImpactfulBits: шапки, кнопки, заголовки
const TEXT_FONT_SCALE: float = 1.45    # RetroSans: основной текст
const WORLD_FONT_SCALE: float = 1.85   # ImpactfulBits над полем

# Кегль прежней разметки (под Play) → кегль пиксельного шрифта
static func ui_px(size: int) -> int:
	return roundi(size * UI_FONT_SCALE)

static func text_px(size: int) -> int:
	return roundi(size * TEXT_FONT_SCALE)

static func world_px(size: float) -> int:
	return roundi(size * WORLD_FONT_SCALE)

# Иконки пакета интерфейса — assets/ui/<группа>/<имя>.png, нарезка tools/ui_atlas_slice.py:
# cards (карты улучшений и событий по id), emblems (ордены и боги по id Chapters), synergy, hud, ribbon,
# banners, rarity, races (по id расы), screens
const ICON_DIR = "res://assets/ui/"

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
	t.default_font_size = text_px(16)
	if ResourceLoader.exists(FONT_UI):
		t.default_font = load(FONT_UI)

	var sans = ui_font()

	# --- Label ---
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))

	# Заголовки окон и экранов, шапки и цифры — шрифт кнопок (ImpactfulBits); остальное — основной (RetroSans)
	_label_variation(t, "TitleLabel", sans, ui_px(30), TEXT, 4)
	_label_variation(t, "HeaderLabel", sans, ui_px(20), GOLD, 2)
	_label_variation(t, "CardTitleLabel", sans, ui_px(24), GOLD_BRIGHT, 3)   # название карты магазина
	_label_variation(t, "ValueLabel", sans, ui_px(19), GOLD_BRIGHT, 2)
	_label_variation(t, "DimLabel", null, text_px(13), TEXT_DIM, 0)
	_label_variation(t, "SmallLabel", null, text_px(14), TEXT, 0)

	# --- Панели: тёмный металл, стальная рамка, срезанные углы ---
	# Текстуры пластин tools/ui_panels_gen.py (стилизация 20.10.2026) поверх плоских, если файлы на месте
	var plate = panel_texture("panel")
	t.set_stylebox("panel", "PanelContainer", plate if plate else panel_style(PANEL, GOLD_DIM, 2, 10, 10))
	t.set_stylebox("panel", "Panel", plate if plate else panel_style(PANEL, GOLD_DIM, 2, 10, 10))
	t.set_type_variation("HudPanel", "PanelContainer")
	var hud = panel_style(PANEL_DARK, GOLD_DIM, 0, 0, 10)
	hud.border_width_bottom = 2
	hud.border_width_top = 2
	var hud_tex = panel_texture("hud")
	t.set_stylebox("panel", "HudPanel", hud_tex if hud_tex else hud)

	# --- Кнопки: сталь (обычная) и янтарь (главное действие) ---
	_button_styles(t, "Button", Color(BG_DEEP, 0.92), GOLD_DIM, ui_px(16), sans, 0.0)
	t.set_type_variation("PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton", Color("2b1d0d"), GOLD, ui_px(19), sans, 0.25)
	_primary_button_textures(t)
	_menu_button_styles(t)
	_select_card_styles(t)

	# --- Окна (ModalOverlay): рамка листа UI_assets.png, аквила сверху — WINDOW_EAGLE ---
	t.set_type_variation("WindowPanel", "PanelContainer")
	var frame := texture_style("frame", WINDOW_FRAME_MARGIN, WINDOW_CONTENT_MARGIN)
	t.set_stylebox("panel", "WindowPanel", frame if frame else panel_style(PANEL, GOLD_DIM, 2, 10, 10))

	# --- Полоса прокрутки: тонкая сталь, наведение — янтарь ---
	var track = panel_style(Color(BG_DEEP, 0.6), Color(0, 0, 0, 0), 0, 2, 0)
	track.content_margin_left = 3
	track.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", panel_style(GOLD_DIM, GOLD_DIM, 0, 2, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", panel_style(GOLD, GOLD, 0, 2, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", panel_style(GOLD_BRIGHT, GOLD_BRIGHT, 0, 2, 0))
	t.set_stylebox("scroll", "HScrollBar", track)
	t.set_stylebox("grabber", "HScrollBar", panel_style(GOLD_DIM, GOLD_DIM, 0, 2, 0))
	t.set_stylebox("grabber_highlight", "HScrollBar", panel_style(GOLD, GOLD, 0, 2, 0))
	t.set_stylebox("grabber_pressed", "HScrollBar", panel_style(GOLD_BRIGHT, GOLD_BRIGHT, 0, 2, 0))

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

# Шрифт кнопок, шапок, заголовков и названий карт: ImpactfulBits, без файла — системный
static func ui_font() -> Font:
	if ResourceLoader.exists(FONT_UI_BOLD):
		return load(FONT_UI_BOLD)
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "sans-serif"])
	font.font_weight = 600
	return font

# Шрифт надписей в мире (цифры урона, счётчики отрядов, цены клеток) — ImpactfulBits, кегли — world_px;
# без файла — шрифт интерфейса; один на всех: рисуется каждый кадр
static var _world_font: Font

static func world_font() -> Font:
	if _world_font == null:
		_world_font = load(FONT_WORLD) if ResourceLoader.exists(FONT_WORLD) else ui_font()
	return _world_font

# Иконка пакета интерфейса (ICON_DIR) или null, если файла нет
static func ui_icon(group: String, name: String) -> Texture2D:
	var path := "%s%s/%s.png" % [ICON_DIR, group, name]
	return load(path) if ResourceLoader.exists(path) else null

# Иконка высотой height (ширина — по пропорциям) для строк и шапок; нет файла — null
static func make_icon(group: String, name: String, height: float) -> TextureRect:
	var tex := ui_icon(group, name)
	if tex == null:
		return null
	var r = TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(height * tex.get_width() / float(tex.get_height()), height)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# Иконка + метка в одну строку (шапки боя и магазина); иконки нет — только метка
static func icon_row(group: String, name: String, label: Control, height: float = HUD_ICON_SIZE) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := make_icon(group, name, height)
	if icon:
		icon.name = "Icon"
		row.add_child(icon)
	if label.get_parent():
		label.reparent(row)
	else:
		row.add_child(label)
	return row

const HUD_ICON_SIZE: float = 26.0
const CHAPTER_BADGE_SIZE: float = 42.0

# Значок бога / ордена забега (решение пользователя 25.10.2026) — первым в шапке боя и магазина: эмблема
# (пакет интерфейса emblems), под курсором — название, бонус и минус. Ордена нет — null
static func make_chapter_badge() -> Control:
	var c: Dictionary = Chapters.get_chapter(RunManager.player_chapter)
	if c.is_empty():
		return null
	var badge := make_icon("emblems", c["id"], CHAPTER_BADGE_SIZE)
	if badge == null:
		return null
	badge.name = "ChapterBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_STOP
	var tip: String = "%s — %s" % [c["name"], c.get("desc", "")]
	if c.has("malus_desc"):
		tip += "\nМинус: " + c["malus_desc"]
	badge.tooltip_text = tip
	return badge

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
	# Кнопки листа UI_assets.png (сталь / янтарь / нажата) — поверх плоских, если файлы на месте
	var normal_tex := texture_style("button_normal", BUTTON_TEXTURE_MARGIN, BUTTON_CONTENT_MARGIN)
	var hover_tex := texture_style("button_hover", BUTTON_TEXTURE_MARGIN, BUTTON_CONTENT_MARGIN)
	var pressed_tex := texture_style("button_pressed", BUTTON_TEXTURE_MARGIN, BUTTON_CONTENT_MARGIN)
	if normal_tex and hover_tex and pressed_tex:
		t.set_stylebox("normal", type, normal_tex)
		t.set_stylebox("hover", type, hover_tex)
		t.set_stylebox("focus", type, hover_tex)
		t.set_stylebox("pressed", type, pressed_tex)
		var disabled := normal_tex.duplicate() as StyleBoxTexture
		disabled.modulate_color = Color(0.55, 0.55, 0.6, 0.8)
		t.set_stylebox("disabled", type, disabled)
	t.set_font("font", type, ui_font())
	t.set_font_size("font_size", type, ui_px(18))
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

# Карточка окон выбора (раса, орден / бог, сложность) — SelectCard: железная пластина card_select,
# наведение и фокус — светлее с янтарной надписью, закрытая — темнее (стилизация 20.10.2026: янтарные
# кнопки PrimaryButton рядом горели все разом). Нет файла — как PrimaryButton
static func _select_card_styles(t: Theme) -> void:
	var type = "SelectCard"
	t.set_type_variation(type, "Button")
	var normal := panel_texture("card_select")
	if normal == null:
		t.set_type_variation(type, "PrimaryButton")
		return
	var hover := panel_texture("card_select")
	hover.modulate_color = CARD_HIGHLIGHT
	var pressed := panel_texture("card_select")
	pressed.modulate_color = Color(0.8, 0.8, 0.85)
	var disabled := panel_texture("card_select")
	disabled.modulate_color = Color(0.55, 0.55, 0.6)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("focus", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)

# Главная кнопка (PrimaryButton) — янтарная кнопка листа: обычная — «hover» листа, наведение — она же
# светлее, нажата — «pressed»; фокус — без рамки, как у плоской
static func _primary_button_textures(t: Theme) -> void:
	var amber := texture_style("button_hover", BUTTON_TEXTURE_MARGIN, BUTTON_CONTENT_MARGIN)
	var pressed := texture_style("button_pressed", BUTTON_TEXTURE_MARGIN, BUTTON_CONTENT_MARGIN)
	if amber == null or pressed == null:
		return
	t.set_stylebox("normal", "PrimaryButton", amber)
	var bright := amber.duplicate() as StyleBoxTexture
	bright.modulate_color = Color(1.25, 1.2, 1.1)
	t.set_stylebox("hover", "PrimaryButton", bright)
	t.set_stylebox("pressed", "PrimaryButton", pressed)

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

# Пластины интерфейса assets/ui/panels/<имя>.png (tools/ui_panels_gen.py, пиксель ×2): поля 9-slice
# (лево, верх, право, низ) — кант и латунные уголки; отступы содержимого
const PANEL_TEXTURES = {
	"card_common": [Vector4(16, 16, 16, 16), Vector4(10, 10, 10, 10)],
	"card_rare":   [Vector4(16, 16, 16, 16), Vector4(10, 10, 10, 10)],
	"card_epic":   [Vector4(16, 16, 16, 16), Vector4(10, 10, 10, 10)],
	"panel":       [Vector4(12, 12, 12, 12), Vector4(10, 10, 10, 10)],
	"hud":         [Vector4(4, 10, 4, 10), Vector4(10, 10, 10, 10)],
	"card_select": [Vector4(18, 20, 18, 18), Vector4(10, 12, 10, 10)],
}
const CARD_HIGHLIGHT = Color(1.45, 1.35, 1.2)

# Новая копия на каждый вызов (у карт меняется modulate_color при наведении); нет файла — null
static func panel_texture(name: String) -> StyleBoxTexture:
	var m: Array = PANEL_TEXTURES[name]
	var s := texture_style("panels/" + name, m[0], m[1])
	if s:
		s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return s

# Текстура интерфейса assets/ui/<name>.png как 9-slice (края — texture_margin, середина тянется);
# файла нет — null (тема остаётся плоской)
static func texture_style(name: String, texture_margin: Vector4, content_margin: Vector4) -> StyleBoxTexture:
	var path := UI_ART_DIR + name + ".png"
	if not ResourceLoader.exists(path):
		return null
	var s = StyleBoxTexture.new()
	s.texture = load(path)
	s.texture_margin_left = texture_margin.x
	s.texture_margin_top = texture_margin.y
	s.texture_margin_right = texture_margin.z
	s.texture_margin_bottom = texture_margin.w
	s.content_margin_left = content_margin.x
	s.content_margin_top = content_margin.y
	s.content_margin_right = content_margin.z
	s.content_margin_bottom = content_margin.w
	return s

static func _add_glow(s: StyleBoxFlat, glow: float) -> void:
	if glow > 0.0:
		s.shadow_color = Color(GOLD_BRIGHT, glow)
		s.shadow_size = 8

static func rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS["common"])

# Рамка карты: железная пластина с кантом цвета редкости (assets/ui/panels/card_<редкость>.png), наведение —
# светлее; нет файла — плоская: цвет редкости, сверху — толстая полоса
static func card_style(rarity: String, highlighted: bool = false) -> StyleBox:
	var tex = panel_texture("card_" + rarity)
	if tex:
		if highlighted:
			tex.modulate_color = CARD_HIGHLIGHT
		return tex
	var c = rarity_color(rarity)
	var s = panel_style(PANEL, c.darkened(0.25) if not highlighted else c.lightened(0.2), 2, 10, 10)
	s.border_width_top = 4
	s.shadow_color = Color(c, 0.35) if highlighted else Color(0, 0, 0, 0.5)
	s.shadow_size = 8 if highlighted else 6
	return s

# Портрет карты: отряд — первый кадр idle юнита, здание — кадр стойки листа (или блок тайлсета),
# улучшение и событие — значок пакета интерфейса assets/ui/cards/<id>.png (нет — null)
static func card_portrait(card: CardData) -> Texture2D:
	if card.card_type in ["upgrade", "event"]:
		return ui_icon("cards", card.id)
	if card.card_type == "building":
		var frames := Building.get_frames(card.building_type, card.faction)
		if frames and frames.has_animation("idle") and frames.get_frame_count("idle") > 0:
			return frames.get_frame_texture("idle", 0)
		# Своих спрайтов у зданий нет — блок тайлсета, из которого здание собрано
		var blocks = Building.BLOCKS.get(card.building_type, [])
		return TerrainTiles.tile(blocks[-1][0]) if not blocks.is_empty() else null
	if card.card_type != "squad":
		return null
	var unit = UnitFactory.create(card.unit_factory_id)
	return _cropped_portrait(unit.sprite_path + "/idle/0.png")

# Кадр бойца — по силуэту: на холсте анимации (≈ 200×200) боец занимает малую часть, портрет был крошечным
const PORTRAIT_PAD: int = 2
static var _portrait_cache: Dictionary = {}   # путь кадра → AtlasTexture
static func _cropped_portrait(path: String) -> Texture2D:
	if _portrait_cache.has(path):
		return _portrait_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	var used := img.get_used_rect() if img else Rect2i()
	var out: Texture2D = tex
	if used.size.x > 0:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(used.grow(PORTRAIT_PAD).intersection(Rect2i(Vector2i.ZERO, img.get_size())))
		out = at
	_portrait_cache[path] = out
	return out

# Окно портрета карты (решение пользователя 19.10.2026, стилизация магазина): портрет бойца / здания
# на грунте поля расы игрока под тёмной виньеткой; без портрета — название типа карты
# framed — рамка редкости пакета интерфейса поверх (assets/ui/rarity/<редкость>.png) целиком, без 9-slice
# (решение пользователя 20.10.2026: повтор середин краёв в 112 px давал цепочку мелких черепов): рамка растянута
# на окно портрета (окно — в пропорции рамки), портрет — в её проёме (RARITY_FRAME_OPENING, доли окна; края
# портрета под брусьями рамки)
static var _portrait_vignette: GradientTexture2D
static func make_portrait_frame(card: CardData, height: float, framed: bool = false) -> Control:
	var border := ui_icon("rarity", card.rarity) if framed else null
	if border:
		var holder = Control.new()
		holder.custom_minimum_size = Vector2(0, height)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var inner := make_portrait_frame(card, 0.0)
		holder.add_child(inner)
		inner.anchor_left = RARITY_FRAME_OPENING.x
		inner.anchor_top = RARITY_FRAME_OPENING.y
		inner.anchor_right = 1.0 - RARITY_FRAME_OPENING.z
		inner.anchor_bottom = 1.0 - RARITY_FRAME_OPENING.w
		var tr = TextureRect.new()
		tr.name = "RarityFrame"
		tr.texture = border
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return holder
	var frame = PanelContainer.new()
	frame.custom_minimum_size = Vector2(0, height)
	frame.clip_contents = true
	frame.add_theme_stylebox_override("panel", panel_style(BG_DEEP, GOLD_DIM, 1, 4, 4))
	var ground := _portrait_ground()
	if ground:
		var bg = TextureRect.new()
		bg.texture = ground
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.modulate = PORTRAIT_GROUND_DIM
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(bg)
	if _portrait_vignette == null:
		var g = Gradient.new()
		g.set_color(0, Color(BG_DEEP, 0.0))
		g.set_color(1, Color(BG_DEEP, 0.9))
		_portrait_vignette = GradientTexture2D.new()
		_portrait_vignette.gradient = g
		_portrait_vignette.fill = GradientTexture2D.FILL_RADIAL
		_portrait_vignette.fill_from = Vector2(0.5, 0.6)
		_portrait_vignette.fill_to = Vector2(1.05, 1.05)
	var vignette = TextureRect.new()
	vignette.texture = _portrait_vignette
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(vignette)
	var tex = card_portrait(card)
	if tex:
		var img = TextureRect.new()
		img.texture = tex
		img.modulate = card_tint(card)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(img)
	else:
		var l = make_label(TYPE_NAMES.get(card.card_type, "").to_upper(), "HeaderLabel")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", TEXT_DIM)
		frame.add_child(l)
	return frame

# Рамка редкости (текстура 448 px по ширине, ширина / высота RARITY_FRAME_ASPECT): проём под портрет —
# доли окна от краёв (лево, верх, право, низ), чуть заходит под брусья
const RARITY_FRAME_ASPECT: float = 1.17
const RARITY_FRAME_OPENING = Vector4(0.19, 0.2, 0.19, 0.24)

# Грунт поля расы игрока для фона портрета: середина верхней грани ромба плиты королевства
const PORTRAIT_GROUND_DIM = Color(0.55, 0.55, 0.6)
static func _portrait_ground() -> Texture2D:
	var tiles: Array = FactionTheme.current().get("kingdom", [])
	if tiles.is_empty() or not (tiles[0] is Dictionary) or not tiles[0].has("texture"):
		return null
	var tex := FactionTheme.load_texture(tiles[0]["texture"])
	if tex == null:
		return null
	var w := float(tex.get_width())
	var top: float = tiles[0].get("top", 0) * w / IsoGrid.TILE_WIDTH
	var at := AtlasTexture.new()
	at.atlas = tex
	# внутри ромба: |dx| / (w/2) + |dy| / (w/4) < 1
	at.region = Rect2(w * 0.3, top + w * 0.25 - w * 0.08, w * 0.4, w * 0.16)
	return at

static func card_tint(card: CardData) -> Color:
	if card.card_type == "building" and Building.get_frames(card.building_type, card.faction) == null:
		return FactionTheme.current().get("building_tint", Color.WHITE)   # блок — в тон зданий на поле
	if card.card_type != "squad":
		return Color.WHITE
	return UnitFactory.create(card.unit_factory_id).tint

# -------------------------------------------------------
# ИГРАЛЬНАЯ КАРТА (решение пользователя 20.10.2026: у каждой карты своя иллюстрация, как в 9 Kings;
# ТЗ — CARD_ART_NEEDED.txt). Файлы assets/ui/card_art: <id карты>.png 360×504 без текста, рамки
# frame_<редкость>.png (окно прозрачное), значки мастей suit_<тип>.png 32×32, рубашки back_<раса>.png.
# Название, цену и масть рисует игра — на плашке и в медальонах рамки
# -------------------------------------------------------
const CARD_ART_DIR = "res://assets/ui/card_art/"
const CARD_ART_SIZE = Vector2(360, 504)
# Раскладка рамки в пикселях арта: окно под иллюстрацию, плашка названия, медальоны (центр) — цена сверху
# слева, масть снизу справа; footer — нижняя плашка (у эпической: тип карты)
const CARD_FRAME_LAYOUT = {
	"common": {"window": Rect2(38, 54, 284, 402), "title": Rect2(100, 38, 186, 28),
		"cost": Vector2(49, 64), "suit": Vector2(310, 440), "medallion": 20.0},
	"rare": {"window": Rect2(35, 78, 289, 371), "title": Rect2(91, 40, 178, 28),
		"cost": Vector2(40, 65), "suit": Vector2(309, 446), "medallion": 19.0},
	"epic": {"window": Rect2(50, 85, 259, 328), "title": Rect2(100, 58, 160, 31),
		"cost": Vector2(50, 65), "suit": Vector2(317, 430), "medallion": 21.0,
		"footer": Rect2(95, 414, 165, 34)},
}
const CARD_ART_BLEED: float = 10.0          # арт заходит под брусья рамки (px арта)
const CARD_INK = Color("2b1c10")            # надписи на костяных плашках
const CARD_PLATE_FONT: float = 0.82         # кегль надписи плашки — доля её высоты
const CARD_CAP_HEIGHT: float = 0.54         # высота заглавных ImpactfulBits — доля кегля (у Play было 0.7)
const CARD_PLATE_MIN_FONT: int = 7          # меньше — уже не читается: длинное название обрезается
# Маленькая карта (скамейка, перетаскивание): на плашке кегль вышел бы мельче CARD_PLATE_READABLE — пиксельный
# шрифт не читается (решение пользователя 24.10.2026); название — на тёмной полосе под плашкой во всю ширину арта
const CARD_PLATE_READABLE: int = 11
const CARD_STRIP_FONT_MAX: int = 12
const CARD_STRIP_FONT_MIN: int = 8
const CARD_STRIP_BG = Color(0.02, 0.02, 0.03, 0.78)
const CARD_COST_COLOR = GOLD_BRIGHT

# Иллюстрация карты или null (арта нет — карта показывается портретом, как раньше)
static func card_art(card: CardData) -> Texture2D:
	return _card_file(card.id)

# Рубашка карты расы (back_<раса>.png) или null
static func card_back(faction: String) -> Texture2D:
	return _card_file("back_" + faction)

static func has_card_art(card: CardData) -> bool:
	return card_art(card) != null

static func _card_file(name: String) -> Texture2D:
	var path := CARD_ART_DIR + name + ".png"
	return load(path) if ResourceLoader.exists(path) else null

# Лицо игральной карты шириной width: арт в окне рамки редкости, название на плашке, цена (cost_text,
# "" — без цены) в верхнем медальоне, масть — в нижнем. Узлы: Art, Frame, Title, Cost, Suit (Footer)
static func make_card_face(card: CardData, width: float, cost_text: String = "") -> Control:
	var k := width / CARD_ART_SIZE.x
	var layout: Dictionary = CARD_FRAME_LAYOUT.get(card.rarity, CARD_FRAME_LAYOUT["common"])
	var face = Control.new()
	face.name = "CardFace"
	face.custom_minimum_size = CARD_ART_SIZE * k
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := _card_file("frame_" + card.rarity)
	# Иллюстрация: в окне рамки с запасом под брусья, по большей стороне (лишнее срезано)
	var window: Rect2 = layout["window"].grow(CARD_ART_BLEED) if frame else Rect2(Vector2.ZERO, CARD_ART_SIZE)
	var clip = Control.new()
	clip.name = "Art"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = window.position * k
	clip.size = window.size * k
	face.add_child(clip)
	var art = TextureRect.new()
	art.texture = card_art(card)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if frame:
		var f = TextureRect.new()
		f.name = "Frame"
		f.texture = frame
		f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		f.stretch_mode = TextureRect.STRETCH_SCALE
		f.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(f)
		f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title_rect := Rect2(layout["title"].position * k, layout["title"].size * k)
	if ui_px(int(title_rect.size.y * CARD_PLATE_FONT)) >= CARD_PLATE_READABLE:
		face.add_child(_plate_label("Title", card.title, title_rect))
	else:
		# под плашкой и под медальоном цены (иначе он закрывает начало названия)
		var strip_y := maxf(title_rect.end.y, (layout["cost"].y + layout["medallion"]) * k)
		face.add_child(_title_strip(card.title, Rect2(layout["window"].position.x * k, strip_y,
			layout["window"].size.x * k, 0.0)))
	if layout.has("footer"):
		var kind: String = TYPE_NAMES.get(card.card_type, "")
		if card.card_type == "squad" and card.unit_count > 0:
			kind += " ×%d" % card.unit_count
		face.add_child(_plate_label("Footer", kind, Rect2(layout["footer"].position * k, layout["footer"].size * k)))
	var r: float = layout["medallion"] * k
	var cost := make_label(cost_text, "ValueLabel")
	cost.name = "Cost"
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.add_theme_font_size_override("font_size", maxi(ui_px(int(r * 1.15)), 9))
	cost.add_theme_color_override("font_color", CARD_COST_COLOR)
	cost.position = layout["cost"] * k - Vector2(r, r)
	cost.size = Vector2(r, r) * 2.0
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(cost)
	var suit_tex := _card_file("suit_" + card.card_type)
	if suit_tex:
		var suit = TextureRect.new()
		suit.name = "Suit"
		suit.texture = suit_tex
		suit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		suit.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		suit.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		suit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s := r * 1.5
		suit.position = layout["suit"] * k - Vector2(s, s) / 2.0
		suit.size = Vector2(s, s)
		face.add_child(suit)
	return face

# Иллюстрация фоном маленькой карты (рука магазина, скамейка): по большей стороне, верх — лицо / силуэт,
# приглушена под текст (CARD_BACKDROP_DIM); арта нет — null
const CARD_BACKDROP_DIM = Color(0.5, 0.5, 0.55)
static func make_card_backdrop(card: CardData) -> TextureRect:
	var tex := card_art(card)
	if tex == null:
		return null
	var bg = TextureRect.new()
	bg.name = "CardArt"
	bg.texture = tex
	bg.modulate = CARD_BACKDROP_DIM
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg

# Надпись на костяной плашке рамки: жирный гротеск тёмными чернилами (решение пользователя 20.10.2026: антиква
# мелкая и съезжала вниз — у неё большой межстрочный запас), кегль — по высоте плашки, длинное название
# уменьшается под её ширину
static func _plate_label(name: String, text: String, rect: Rect2) -> Label:
	var l = Label.new()
	l.name = name
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font := ui_font()
	var size := ui_px(int(rect.size.y * CARD_PLATE_FONT))   # заглавные — почти той же высоты, что у Play
	var room := rect.size.x * 0.92
	while size > CARD_PLATE_MIN_FONT and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
		size -= 1
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", CARD_INK)
	l.add_theme_constant_override("outline_size", 0)
	# По вертикали — середина заглавных (CARD_CAP_HEIGHT кегля над базовой линией) в середине плашки: строка
	# шрифта выше плашки, центровка Label опускала надпись к нижнему краю
	var ascent := font.get_ascent(size)
	var top := rect.get_center().y - ascent + size * CARD_CAP_HEIGHT / 2.0
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # и на CARD_PLATE_MIN_FONT не влезло
	l.position = Vector2(rect.position.x, top)
	l.size = Vector2(rect.size.x, font.get_height(size))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Кегль не больше max_size, при котором text шрифтом font влезает в width (не меньше min_size)
static func fit_font_size(font: Font, text: String, width: float, max_size: int, min_size: int) -> int:
	var size := max_size
	while size > min_size and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		size -= 1
	return size

# Название маленькой карты: светлые буквы с обводкой на тёмной полосе (rect — левый верх и ширина полосы)
static func _title_strip(text: String, rect: Rect2) -> Control:
	var font := ui_font()
	var size := fit_font_size(font, text, rect.size.x - 6.0, ui_px(CARD_STRIP_FONT_MAX), ui_px(CARD_STRIP_FONT_MIN))
	var strip := Panel.new()
	strip.name = "TitleStrip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_STRIP_BG
	strip.add_theme_stylebox_override("panel", sb)
	strip.position = rect.position
	strip.size = Vector2(rect.size.x, font.get_height(size) + 2.0)
	var l := Label.new()
	l.name = "Title"
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD_BRIGHT)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return strip

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
	b.pressed.connect(play_click)
	return b

# Щелчок кнопки (AudioManager «ui_click»); автолоад — из дерева, без имени при компиляции
static func play_click() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var audio = tree.root.get_node_or_null("AudioManager") if tree else null
	if audio:
		audio.play("ui_click")

static func make_spacer() -> Control:
	var c = Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
