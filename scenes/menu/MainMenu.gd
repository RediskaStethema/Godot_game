extends Control

# Главное меню — главная сцена. «Продолжить» — есть сохранение забега
# (SaveManager), «Новый забег» — сброс и магазин 1-й волны (при сохранении —
# с подтверждением), «Настройки» — GameSettings.
# Вид — по концепту assets_menu.png, арт — лист UI_assets.png (tools/ui_from_sheet.py): слева золотая
# аквила, название, разделитель с черепом и кнопки (UITheme «MainMenuButton» с иконками),
# справа сцена с башней над планетой.
# UI собирается кодом, стили — из UITheme.

const BUTTON_SIZE = Vector2(320, 52)
const COLUMN_SHADE: float = 0.62        # затемнение слева под колонкой меню
const COLUMN_SHADE_WIDTH: float = 0.42  # доля ширины окна
const MENU_LEFT: float = 52.0          # отступ колонки меню от левого края (эталон меню 16.11.2026: 4% ширины)
const ART_DIR = "res://assets/ui/menu/"
const MenuSceneArt = preload("res://scenes/menu/MenuSceneArt.gd")
# Шапка меню по эталону (решение пользователя 16.11.2026, ассеты — NewAssets/07_ui, tools/menu_v2_assets.py): череп в венке
# между двумя половинками шипастого разделителя, название, подпись и разделитель целиком. Аквила с бликом и логотип
# logo_eagle* больше не используются (прежние файлы — assets/source_sheets/_backup_before_redesign_2026-11-15/ui/menu_anim)
const HEADER_WREATH = "res://assets/ui/menu/header_wreath.png"
const HEADER_RULE = "res://assets/ui/menu/header_rule.png"
const WREATH_HEIGHT: float = 80.0
const RULE_WIDTH: float = 280.0         # разделитель целиком; половинки у венка — по RULE_WIDTH / 2.4
# Кнопка: иконка | вертикальный разделитель | надпись (эталон). Иконка — UITheme.MENU_ICON_SIZE от левого поля
const BUTTON_DIVIDER_X: float = 70.0
const BUTTON_DIVIDER_COLOR = Color("8a4a30", 0.85)
const MENU_ICON_TEX: int = 72            # px текстуры иконки кнопки — ×2 к UITheme.MENU_ICON_SIZE

var continue_button: Button = null
var _col: VBoxContainer = null   # колонка меню (аквила, название, кнопки)
var _launching: bool = false
var _scene_art: Control = null   # живая сцена: десантник оборачивается, пока курсор на кнопке меню
var _menu_buttons: Array = []
var info_label: Label = null

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
	_scene_art = _add_scene_art()
	add_child(_make_column_shade())

	var col = VBoxContainer.new()
	col.name = "MenuColumn"
	_col = col
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = MENU_LEFT
	col.offset_right = MENU_LEFT + BUTTON_SIZE.x
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	col.add_child(_make_title_block())
	col.add_child(_spacer(14))
	continue_button = _make_button("ПРОДОЛЖИТЬ", "icon_chevrons", _on_continue_pressed)
	col.add_child(continue_button)
	var new_run = _make_button("НОВЫЙ ЗАБЕГ", "icon_wreath", _on_new_run_pressed)
	new_run.name = "NewRunButton"
	col.add_child(new_run)
	var arsenal = _make_button("АРСЕНАЛ", "icon_ammo", _on_arsenal_pressed)
	arsenal.name = "ArsenalButton"
	col.add_child(arsenal)
	if RunManager.test_mode_available():   # тестовый режим — только в сборке для разработки
		var test = _make_button("ТЕСТОВЫЙ РЕЖИМ", "icon_gear", _on_test_mode_pressed)
		test.name = "TestModeButton"
		col.add_child(test)
		var tut = _make_button("ОБУЧЕНИЕ (ТЕСТ)", "icon_wreath", _on_tutorial_test_pressed)   # сценарий «Козёл учит» с начала
		tut.name = "TutorialTestButton"
		col.add_child(tut)
	col.add_child(_make_button("НАСТРОЙКИ", "icon_gear", _on_settings_pressed))
	col.add_child(_make_button("ВЫХОД", "icon_exit", _on_quit_pressed))

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

# Сцена справа на всю высоту; левый край растворяется в фоне
# (живая — слоями пакета assets/ui/menu/anim, MenuSceneArt)
# Затемнение под колонкой меню (эталон 16.11.2026: слева облака темнее): надписи шапки читаются поверх флагмана и облаков
func _make_column_shade() -> TextureRect:
	var g = Gradient.new()
	g.set_color(0, Color(0.02, 0.01, 0.03, COLUMN_SHADE))
	g.set_color(1, Color(0.02, 0.01, 0.03, 0.0))
	var tex = GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var r = TextureRect.new()
	r.name = "ColumnShade"
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_right = COLUMN_SHADE_WIDTH
	r.anchor_bottom = 1.0
	return r

func _add_scene_art() -> Control:
	if not MenuSceneArt.available():
		return null
	var art := MenuSceneArt.new()
	art.name = "MenuSceneArt"
	add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # сцена — на всё окно, меню — поверх неё
	return art

# Шапка: венок с черепом между половинками разделителя, название, подпись, разделитель — как в эталоне
func _make_title_block() -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var rule: Texture2D = load(HEADER_RULE) if ResourceLoader.exists(HEADER_RULE) else null
	var wreath: Texture2D = load(HEADER_WREATH) if ResourceLoader.exists(HEADER_WREATH) else null
	if wreath:
		var top = HBoxContainer.new()
		top.alignment = BoxContainer.ALIGNMENT_CENTER
		top.add_theme_constant_override("separation", 0)
		if rule:
			top.add_child(_rule_part(rule, true))
		var w = TextureRect.new()
		w.texture = wreath
		w.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		w.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		w.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		w.custom_minimum_size = Vector2(WREATH_HEIGHT * wreath.get_width() / wreath.get_height(), WREATH_HEIGHT)
		top.add_child(w)
		if rule:
			top.add_child(_rule_part(rule, false))
		box.add_child(top)
	var title = UITheme.make_label("GRIM KINGDOM", "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UITheme.ui_px(42))
	title.add_theme_color_override("font_color", Palette.MENU_TITLE)   # светлый беж (образец exampel.png)
	title.add_theme_color_override("font_outline_color", Color(0.03, 0.025, 0.02))
	title.add_theme_constant_override("outline_size", 6)
	box.add_child(title)
	# Подписи «Удержите цитадель 15 волн» под названием больше нет (решение пользователя 23.11.2026: «убери вообще»)
	if rule:
		var divider = TextureRect.new()
		divider.texture = rule
		divider.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		divider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		divider.custom_minimum_size = Vector2(0, RULE_WIDTH * rule.get_height() / rule.get_width())
		box.add_child(divider)
	return box

# Половинка разделителя: левая (шип у правого конца) или правая — по краям венка
func _rule_part(rule: Texture2D, left: bool) -> TextureRect:
	var half := RULE_WIDTH / 2.4
	var atlas := AtlasTexture.new()
	atlas.atlas = rule
	var w := rule.get_width() / 2.0
	atlas.region = Rect2(0.0 if left else w, 0.0, w, rule.get_height())
	var r = TextureRect.new()
	r.texture = atlas
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(half, half * rule.get_height() / rule.get_width() * 2.0)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r

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

# Окна кораблей горят ярче, пока курсор на кнопке меню (MenuSceneArt.set_menu_hover)
func _process(delta: float) -> void:
	if _scene_art and _scene_art.has_method("set_menu_hover"):
		if _menu_buttons.is_empty():
			_menu_buttons = find_children("*", "Button", true, false).filter(
				func(b): return b.theme_type_variation == "MainMenuButton")
		var hovered := false
		for b in _menu_buttons:
			if is_instance_valid(b) and b.visible and b.is_hovered():
				hovered = true
				break
		_scene_art.set_menu_hover(hovered)

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
	var sep := ColorRect.new()   # вертикальный разделитель между иконкой и надписью (эталон меню 16.11.2026)
	sep.color = BUTTON_DIVIDER_COLOR
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.position = Vector2(BUTTON_DIVIDER_X, 12.0)
	sep.size = Vector2(2.0, BUTTON_SIZE.y - 24.0)
	b.add_child(sep)
	b.pressed.connect(handler)
	ButtonVolume.attach(b, 6.0)   # объём и отклик, как у кнопок окон (стилизация 12.11.2026)
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
	_track_select(dialog)
	dialog.setup()
	dialog.chosen.connect(_on_race_chosen)

# Выбор расы / ордена — на фоне меню без самого меню (решение пользователя 13.11.2026: «меню должно уезжать
# влево, колесо — на фоне космоса, солдата»): с первым окном выбора колонка уезжает за левый край, когда окон
# цепочки (раса → орден → сложность → стартовая карта) не осталось и забег не стартовал — возвращается
const MENU_SLIDE_TIME: float = 0.35
const SELECT_DIALOGS = ["RaceSelectDialog", "ChapterSelectDialog", "DifficultySelectDialog", "StartCardDialog"]

func _track_select(dialog: Node) -> void:
	slide_menu(true)
	dialog.tree_exited.connect(func(): _check_menu_return.call_deferred())

func _check_menu_return() -> void:
	if _launching or not is_inside_tree():
		return
	for c in get_children():
		if c.get_script() and SELECT_DIALOGS.has(c.get_script().get_global_name()) and not c.is_queued_for_deletion():
			return
	slide_menu(false)

var menu_hidden: bool = false
func slide_menu(out: bool) -> void:
	if _col == null or menu_hidden == out:
		return
	menu_hidden = out
	var x := -_col.size.x - 40.0 if out else MENU_LEFT
	var tw := _col.create_tween().set_parallel(true)
	tw.tween_property(_col, "position:x", x, MENU_SLIDE_TIME).set_trans(Tween.TRANS_CUBIC) 		.set_ease(Tween.EASE_IN if out else Tween.EASE_OUT)
	tw.tween_property(_col, "modulate:a", 0.0 if out else 1.0, MENU_SLIDE_TIME)
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE if out else Control.MOUSE_FILTER_PASS
	for b in _col.find_children("*", "Button", true, false):
		b.disabled = out   # уехавшее меню не ловит Enter / клики

# Раса с орденами / богами (Космодесант, Хаос) — следом их выбор, затем сложности; «Отмена» в любом
# окне — забег не начат
func _on_race_chosen(faction: String) -> void:
	if not Chapters.has_chapters(faction):
		_open_difficulty_select(faction, "")
		return
	var dialog = ChapterSelectDialog.new()
	add_child(dialog)
	_track_select(dialog)
	dialog.setup(faction)
	dialog.chosen.connect(func(chapter): _open_difficulty_select(faction, chapter))

func _open_difficulty_select(faction: String, chapter: String) -> void:
	var dialog = DifficultySelectDialog.new()
	add_child(dialog)
	_track_select(dialog)
	dialog.setup()
	dialog.chosen.connect(func(level): _open_start_card_select(faction, chapter, level))

# Открыты стартовые карты (мета-прогрессия) — выбор одной; нет — сразу забег
func _open_start_card_select(faction: String, chapter: String, level: int) -> void:
	if MetaProgress.available_start_cards().is_empty():
		_start_new_run(faction, chapter, level)
		return
	var dialog = StartCardDialog.new()
	add_child(dialog)
	_track_select(dialog)
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
	_launching = true
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
	_track_select(dialog)
	dialog.setup()
	dialog.chosen.connect(func(faction):
		if not Chapters.has_chapters(faction):
			RunManager.start_test_mode(faction, "")
			return
		var chapters = ChapterSelectDialog.new()
		add_child(chapters)
		_track_select(chapters)
		chapters.setup(faction, true)
		chapters.chosen.connect(func(chapter): RunManager.start_test_mode(faction, chapter)))

# Режим проверки обучения (решение пользователя 24.11.2026: «сделай отдельный режим в меню типа туториал для теста
# туториала»; только в сборке для разработки, как тестовый режим): раса → орден / бог (все открыты) → обычный забег
# с обучением, включённым и начатым с INTRO (`GameSettings.set_tutorial_enabled(true)` стирает прогресс и показанные
# подсказки), сложность 1, без стартовой карты Арсенала; сохранение забега заменяется, как при новом забеге
func _on_tutorial_test_pressed() -> void:
	var dialog = RaceSelectDialog.new()
	add_child(dialog)
	_track_select(dialog)
	dialog.setup()
	dialog.chosen.connect(func(faction):
		if not Chapters.has_chapters(faction):
			_start_tutorial_run(faction, "")
			return
		var chapters = ChapterSelectDialog.new()
		add_child(chapters)
		_track_select(chapters)
		chapters.setup(faction, true)
		chapters.chosen.connect(func(chapter): _start_tutorial_run(faction, chapter)))

func _start_tutorial_run(faction: String, chapter: String) -> void:
	GameSettings.set_tutorial_enabled(true)
	_start_new_run(faction, chapter, 1)

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
