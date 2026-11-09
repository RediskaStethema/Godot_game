extends Control

# Главное меню — главная сцена. «Продолжить» — есть сохранение забега
# (SaveManager), «Новый забег» — сброс и магазин 1-й волны (при сохранении —
# с подтверждением), «Настройки» — GameSettings.
# Вид — по концепту assets_menu.png, арт — лист UI_assets.png (tools/ui_from_sheet.py): слева золотая
# аквила, название, разделитель с черепом и кнопки (UITheme «MainMenuButton» с иконками),
# справа сцена с башней над планетой.
# UI собирается кодом, стили — из UITheme.

const BUTTON_SIZE = Vector2(320, 52)
const MENU_LEFT: float = 72.0          # отступ колонки меню от левого края
const LOGO_SCALE: float = 1.25
const SCENE_FADE_WIDTH: float = 260.0  # переход сцены справа в фон, px
const ART_DIR = "res://assets/ui/menu/"
const MenuSceneArt = preload("res://scenes/menu/MenuSceneArt.gd")
const MenuStarfield = preload("res://scenes/menu/MenuStarfield.gd")
# Туманности за меню: [цвет (альфа — сила), центр, радиус — доли экрана]
# Решение пользователя 08.11.2026 (образец assets/source_sheets/FInalUI/exampel.png): фон — почти чёрный космос без туманностей
# (были NEBULA_BLUE в 0.22, 0.3 и NEBULA_WARP в 0.48, 0.85); вернуть — записи сюда
const NEBULAE = []
# Аквила над названием (решение пользователя 07.11.2026: logo_eagle 152×56 — мутная вырезка старого листа,
# на большом окне «слишком низкое качество») — логотип художника logo_eagle_hd.png (1024 px, исходник 2073 px —
# assets/source_sheets/ui_logo_2026-11-07), на экране LOGO_WIDTH, мип-уровни; нет файла — аквила рамки окна
# (UITheme.WINDOW_EAGLE областью LOGO_REGION). Блик — шейдером
const LOGO_HD = "res://assets/ui/menu/logo_eagle_hd.png"
const LOGO_WIDTH: float = 210.0
const LOGO_REGION = Rect2(4, 16, 144, 56)
const SHINE_PERIOD: float = 5.0        # блик пробегает раз в 5 с
const SHINE_TIME: float = 0.7          # с — проход полосы света слева направо
const SHINE_WIDTH: float = 0.12        # доля ширины — полуширина полосы
const SHINE_STRENGTH: float = 0.55
const SHINE_SHADER = """
shader_type canvas_item;
uniform float pos = -1.0;      // центр полосы по x (доля ширины), вне 0..1 — блика нет
uniform float width = 0.12;
uniform float strength = 0.55;
uniform vec4 glow : source_color;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float x = UV.x + (UV.y - 0.5) * 0.35;   // полоса чуть наклонена
	float k = 1.0 - smoothstep(0.0, width, abs(x - pos));
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	COLOR = vec4(c.rgb + glow.rgb * k * strength * smoothstep(0.15, 0.6, lum), c.a);   // по золоту, не по чёрному контуру
}
"""
const MENU_ICON_TEX: int = 72            # px текстуры иконки кнопки — ×2 к UITheme.MENU_ICON_SIZE

var continue_button: Button = null
var _scene_art: Control = null   # живая сцена: десантник оборачивается, пока курсор на кнопке меню
var _menu_buttons: Array = []
var info_label: Label = null
var _eagle: TextureRect = null
var _shine_time: float = 0.0

func _ready() -> void:
	AudioManager.play_music("menu")
	UITheme.apply_cursors()
	_build_layout()
	continue_button.visible = SaveManager.has_save()
	if continue_button.visible:
		info_label.text = "Есть сохранённый забег"
	# Ни одна кнопка не горит, пока курсор не на ней (решение пользователя 08.11.2026; было: первая — в фокусе
	# и подсвечена с открытия меню). Стрелки / Tab — фокус появится по первому нажатию

func _build_layout() -> void:
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_make_backdrop())
	for n in NEBULAE:   # туманности — мягкие пятна света (ADD) по космосу за меню
		add_child(_make_nebula(n[0], n[1], n[2]))
	# Звёзды: при целой планете (MenuSceneArt.has_wide_planet) — под сценой: проступают сквозь прозрачный край её
	# космоса, планета их закрывает; иначе — поверх полосы растворения сцены (гаснут к её левому краю)
	var stars = MenuStarfield.new()
	stars.name = "Starfield"
	stars.fade_width = SCENE_FADE_WIDTH
	var wide: bool = MenuSceneArt.available() and MenuSceneArt.has_wide_planet()
	if wide:
		add_child(stars)
		stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var art := _add_scene_art(not wide)
	_scene_art = art
	stars.mask_node = art
	if not wide:
		add_child(stars)
		stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

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
	var arsenal = _make_button("АРСЕНАЛ", "icon_skull", _on_arsenal_pressed)
	arsenal.name = "ArsenalButton"
	col.add_child(arsenal)
	if RunManager.test_mode_available():   # тестовый режим — только в сборке для разработки
		# своя иконка — UI_NEEDED 7.2 (icon_test.png), пока нет — череп, как у «Арсенала»
		var test_icon := "icon_test" if ResourceLoader.exists(ART_DIR + "icon_test.png") else "icon_skull"
		var test = _make_button("ТЕСТОВЫЙ РЕЖИМ", test_icon, _on_test_mode_pressed)
		test.name = "TestModeButton"
		col.add_child(test)
	col.add_child(_make_button("НАСТРОЙКИ", "icon_settings", _on_settings_pressed))
	col.add_child(_make_button("ВЫХОД", "icon_quit", _on_quit_pressed))

	info_label = UITheme.make_label("", "SmallLabel")
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", UITheme.MENU_AMBER)
	col.add_child(info_label)

# Фон: космос (решение пользователя 06.11.2026) — чуть светлее за меню, к сцене справа — глубина космоса,
# ровно цвет растворения сцены (без шва)
func _make_backdrop() -> TextureRect:
	var g = Gradient.new()
	g.set_color(0, Palette.MENU_SPACE)   # 08.11.2026, образец exampel.png: ровный тёмный космос (было SPACE_MID → DEEP)
	g.set_color(1, Palette.MENU_SPACE)
	g.set_offset(1, 0.55)
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

# Туманность: радиальное пятно цвета color (альфа — сила) с центром center и радиусом radius (доли экрана), ADD
func _make_nebula(color: Color, center: Vector2, radius: float) -> TextureRect:
	var g = Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color, 0.0))
	var tex = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = center
	tex.fill_to = center + Vector2(radius, 0.0)
	var r = TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	r.material = mat
	return r

# Сцена справа на всю высоту; левый край растворяется в фоне
# (живая — слоями пакета assets/ui/menu/anim, MenuSceneArt; нет пакета — неподвижная menu_scene.png)
func _add_scene_art(fade_edge: bool = true) -> Control:
	var art: Control
	if MenuSceneArt.available():
		art = MenuSceneArt.new()
		art.name = "MenuSceneArt"
		add_child(art)
		art.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		art.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	else:
		var still = TextureRect.new()
		still.texture = load(ART_DIR + "menu_scene.png")
		still.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		still.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		still.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		still.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		still.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(still)
		art = still
	if not fade_edge:   # край сцены растворяет её собственный космос (layer_space_edge) — полоса не нужна
		return art
	# Растворение: от цвета фона к прозрачному поверх левого края сцены
	var g = Gradient.new()
	g.set_color(0, Palette.SPACE_DEEP)
	g.set_color(1, Color(Palette.SPACE_DEEP, 0.0))
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
	return art

# Аквила, название, подпись — как шапка меню в концепте
func _make_title_block() -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var eagle = TextureRect.new()
	if ResourceLoader.exists(LOGO_HD) or ResourceLoader.exists(UITheme.WINDOW_EAGLE):
		if ResourceLoader.exists(LOGO_HD):
			eagle.texture = load(LOGO_HD)
			eagle.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		else:
			var atlas = AtlasTexture.new()
			atlas.atlas = load(UITheme.WINDOW_EAGLE)
			atlas.region = LOGO_REGION
			eagle.texture = atlas
		var shader = Shader.new()
		shader.code = SHINE_SHADER
		var mat = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("width", SHINE_WIDTH)
		mat.set_shader_parameter("strength", SHINE_STRENGTH)
		mat.set_shader_parameter("glow", Palette.GOLD_PALE)
		eagle.material = mat
		_eagle = eagle
	else:
		eagle.texture = load(ART_DIR + "logo_eagle.png")
	var tex_size = eagle.texture.get_size()
	eagle.custom_minimum_size = Vector2(LOGO_WIDTH, LOGO_WIDTH * tex_size.y / tex_size.x) 		if eagle.texture.resource_path == LOGO_HD else tex_size * LOGO_SCALE
	eagle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eagle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(eagle)
	var title = UITheme.make_label("WH40KINGS", "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UITheme.ui_px(42))
	title.add_theme_color_override("font_color", Palette.MENU_TITLE)   # светлый беж (образец exampel.png)
	title.add_theme_color_override("font_outline_color", Color(0.03, 0.025, 0.02))
	title.add_theme_constant_override("outline_size", 6)
	box.add_child(title)
	var sub = UITheme.make_label("———  УДЕРЖИТЕ ЦИТАДЕЛЬ 15 ВОЛН  ———", "DimLabel")
	sub.add_theme_color_override("font_color", Palette.MENU_SUBTITLE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	if ResourceLoader.exists(UITheme.DIVIDER_SKULL):   # разделитель с черепом листа UI_assets.png
		var divider = TextureRect.new()
		divider.texture = load(UITheme.DIVIDER_SKULL)
		divider.custom_minimum_size = Vector2(0, divider.texture.get_height() * UITheme.UI_ART_SCALE)   # арт ×2
		divider.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		divider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(divider)
	return box

# Иконка кнопки меню (128 px, UI_NEEDED 7.2) — заранее уменьшена фильтром Lanczos до ×2 к экрану (MENU_ICON_TEX):
# иконку кнопки рисует сама кнопка, а её фильтр с мип-уровнями размыл бы и пиксельный шрифт надписи
static var _icon_cache: Dictionary = {}
static func _menu_icon(icon_name: String) -> Texture2D:
	if _icon_cache.has(icon_name):
		return _icon_cache[icon_name]
	var path := ART_DIR + icon_name + ".png"
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	var k := float(MENU_ICON_TEX) / maxf(img.get_width(), img.get_height())
	if k < 1.0:
		img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	var out := ImageTexture.create_from_image(img)
	_icon_cache[icon_name] = out
	return out

# Блик по аквиле: полоса света проходит слева направо за SHINE_TIME раз в SHINE_PERIOD
func _process(delta: float) -> void:
	if _scene_art and _scene_art.has_method("set_marine_look"):
		if _menu_buttons.is_empty():
			_menu_buttons = find_children("*", "Button", true, false).filter(
				func(b): return b.theme_type_variation == "MainMenuButton")
		var hovered := false
		for b in _menu_buttons:
			if is_instance_valid(b) and b.visible and b.is_hovered():
				hovered = true
				break
		_scene_art.set_marine_look(hovered)
	if _eagle == null:
		return
	_shine_time = fmod(_shine_time + delta, SHINE_PERIOD)
	var t = _shine_time / SHINE_TIME
	var pos = lerpf(-SHINE_WIDTH * 2.0, 1.0 + SHINE_WIDTH * 2.0, t) if t <= 1.0 else -1.0
	_eagle.material.set_shader_parameter("pos", pos)

func _spacer(h: float) -> Control:
	var c = Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _make_button(text: String, icon_name: String, handler: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.theme_type_variation = "MainMenuButton"
	b.icon = _menu_icon(icon_name)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = BUTTON_SIZE
	b.pressed.connect(handler)
	b.mouse_entered.connect(b.grab_focus)   # наведение и фокус — одна подсветка
	b.mouse_exited.connect(func():   # курсор ушёл — кнопка гаснет (фокус не держит подсветку)
		if b.has_focus():
			b.release_focus())
	return b

func _on_continue_pressed() -> void:
	if not SaveManager.load_run():
		continue_button.visible = false
		info_label.text = "Сохранение не читается — начните новый забег"
		return
	RunManager.resume()

# Новый забег: при сохранении — подтверждение, затем выбор расы
func _on_new_run_pressed() -> void:
	if not SaveManager.has_save():
		_open_race_select()
		return
	var dialog = ConfirmDialog.new()
	add_child(dialog)
	dialog.setup("Начать новый забег? Сохранённый забег будет потерян.", "НАЧАТЬ ЗАНОВО")
	dialog.confirmed.connect(_open_race_select)

func _open_race_select() -> void:
	var dialog = RaceSelectDialog.new()
	add_child(dialog)
	dialog.setup()
	dialog.chosen.connect(_on_race_chosen)

# Раса с орденами / богами (Космодесант, Хаос) — следом их выбор, затем сложности; «Отмена» в любом
# окне — забег не начат
func _on_race_chosen(faction: String) -> void:
	if not Chapters.has_chapters(faction):
		_open_difficulty_select(faction, "")
		return
	var dialog = ChapterSelectDialog.new()
	add_child(dialog)
	dialog.setup(faction)
	dialog.chosen.connect(func(chapter): _open_difficulty_select(faction, chapter))

func _open_difficulty_select(faction: String, chapter: String) -> void:
	var dialog = DifficultySelectDialog.new()
	add_child(dialog)
	dialog.setup()
	dialog.chosen.connect(func(level): _open_start_card_select(faction, chapter, level))

# Открыты стартовые карты (мета-прогрессия) — выбор одной; нет — сразу забег
func _open_start_card_select(faction: String, chapter: String, level: int) -> void:
	if MetaProgress.available_start_cards().is_empty():
		_start_new_run(faction, chapter, level)
		return
	var dialog = StartCardDialog.new()
	add_child(dialog)
	dialog.setup(faction)
	dialog.chosen.connect(func(card_id):
		MetaProgress.select_start_card(card_id)
		_start_new_run(faction, chapter, level))

func _start_new_run(faction: String, chapter: String, level: int) -> void:
	RunManager.player_faction = faction   # раньше сброса: стартовая карта — карта этой расы
	BattleManager.reset_run()   # + MetaProgress.apply_run_start: «Резервы», стартовая карта
	RunManager.player_chapter = chapter
	RunManager.difficulty = level
	SaveManager.delete_save()
	# Взлёт в космос (MenuLaunch), потом магазин; на первом поле забега — посадка (BattleLanding)
	RunManager.landing_pending = true
	_play_launch()

const MenuLaunch = preload("res://scenes/menu/MenuLaunch.gd")
func _play_launch() -> void:
	var col := find_children("*", "VBoxContainer", false, false)
	for c in col:   # колонка меню уезжает вбок за левый край (решение пользователя 08.11.2026: «не вниз, а в бок»)
		var tw := c.create_tween().set_parallel(true)
		tw.tween_property(c, "position:x", c.position.x - c.size.x - MENU_LEFT - 40.0, 0.7) 			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _scene_art and _scene_art.has_method("launch"):
		_scene_art.launch(MenuLaunch.DURATION)
	MenuLaunch.start(self, RunManager.advance)

# Тестовый режим (решение пользователя 06.11.2026): раса → орден / бог (все открыты) → сразу расстановка;
# сохранение забега не трогается
func _on_test_mode_pressed() -> void:
	var dialog = RaceSelectDialog.new()
	add_child(dialog)
	dialog.setup()
	dialog.chosen.connect(func(faction):
		if not Chapters.has_chapters(faction):
			RunManager.start_test_mode(faction, "")
			return
		var chapters = ChapterSelectDialog.new()
		add_child(chapters)
		chapters.setup(faction, true)
		chapters.chosen.connect(func(chapter): RunManager.start_test_mode(faction, chapter)))

func _on_arsenal_pressed() -> void:
	var dialog = ArsenalDialog.new()
	add_child(dialog)
	dialog.setup()

func _on_settings_pressed() -> void:
	var panel = SettingsPanel.new()
	add_child(panel)
	panel.setup()

func _on_quit_pressed() -> void:
	get_tree().quit()
