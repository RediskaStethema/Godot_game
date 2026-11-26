extends CanvasLayer

# Экран загрузки (решение пользователя 25.11.2026: «нужен экран загрузки»). Первый вход в бой за запуск игры читает
# листы эффектов и снарядов, звуки и кадры капсулы — секунды без картинки. Экран закрывает окно (слой над шторкой
# RunManager.FADE_LAYER), прогревает кэши по шагам — по кадру на шаг, полоса и подпись успевают нарисоваться, — грузит
# сцену боя потоком, меняет сцену и тает. Прогрето один раз за запуск: дальше смена сцены — прежняя шторка.
# Не нужен в headless (тесты меняют сцену синхронно) и когда кэши уже тёплые (`needed`). Запускает RunManager._go.
# Без class_name: скрипт грузят по пути (RunManager._go, тест), глобальный класс не нужен
# Новый шаг прогрева — строка в STEPS (подпись, метод) и метод `_warm_*`.

const LAYER: int = 101
const BAR_SIZE := Vector2(420.0, 14.0)
const FADE_OUT: float = 0.4
const MIN_SHOW: float = 0.6     # сек — экран не мигает, даже если всё уже в кэше
const BAR_LERP: float = 10.0    # полоса догоняет цель плавно
# Круговая загрузка (решение пользователя 25.11.2026): алхимический круг с фонарём, 16 кадров из Layer + код
# (`tools/loading_spinner_build.py`), правый нижний угол экрана
const SPIN_DIR := "res://assets/ui/loading/spin/"
const SPIN_FRAMES: int = 16
const SPIN_FPS: float = 8.0
const SPIN_SIZE: float = 144.0
const SPIN_MARGIN: float = 28.0

# Подсказки — только то, что уже есть в игре (по правилам и обучению)
const TIPS: Array[String] = [
	"Цитадель падёт — забег окончен. Пока она стоит, ты жив.",
	"Одинаковые карты складываются: брось карту отряда на такой же отряд — уровень вырастет, раны залатаются.",
	"Казармы после победы лечат соседние отряды и возвращают павших.",
	"Монеты нужны, чтобы покупать карты в магазине и новые клетки королевства.",
	"Карта события — разовое действие: сыграл, и она сгорает.",
	"Выбор карты после боя: откроешь две, заберёшь одну.",
	"В руке всегда остаются две карты: без них в бой не выйти.",
	"Орудие бьёт по твоему клику — целься в самую густую толпу.",
]

# Шаги прогрева: [подпись, метод]. Метод вызывается на отдельном кадре
const STEPS: Array = [
	["Листы эффектов", "_warm_vfx"],
	["Снаряды", "_warm_projectiles"],
	["Звуки", "_warm_audio"],
	["Десантные капсулы", "_warm_pods"],
]

static var warmed: bool = false
static var _running: bool = false

var _bar: Control
var _spinner: TextureRect
var _spin_textures: Array[Texture2D] = []
var _caption: Label
var _progress: float = 0.0       # доля 0..1, куда идёт полоса
var _shown: float = 0.0          # то, что нарисовано сейчас
var _age: float = 0.0

# Показывать ли экран для смены сцены на path: сцена боя, кэши не тёплые, не headless (тесты)
static func needed(path: String) -> bool:
	if warmed or _running or DisplayServer.get_name() == "headless":
		return false
	return path.ends_with("BattleScene.tscn")

static func busy() -> bool:
	return _running

# Показать экран, прогреть кэши, загрузить сцену, сменить её и убрать экран. Корутина: вызывающий не ждёт
static func run(tree: SceneTree, path: String) -> void:
	if _running:
		return
	_running = true
	var screen: Node = new()
	tree.root.add_child(screen)
	ResourceLoader.load_threaded_request(path)   # сама сцена — потоком, пока идёт прогрев
	await tree.process_frame
	await tree.process_frame   # экран нарисован до первой тяжёлой работы
	var total: float = STEPS.size() + 2.0
	for i in STEPS.size():
		screen.set_step(STEPS[i][0], i / total)
		await tree.process_frame
		screen.call(STEPS[i][1])
	screen.set_step("Строим поле", STEPS.size() / total)
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame
	var packed: Variant = ResourceLoader.load_threaded_get(path)
	screen.set_step("Строим поле", (STEPS.size() + 1.0) / total)
	await tree.process_frame
	warmed = true
	if packed is PackedScene:
		tree.change_scene_to_packed(packed)
	else:
		tree.change_scene_to_file(path)
	await tree.process_frame
	await tree.process_frame
	while screen._age < MIN_SHOW:
		await tree.process_frame
	screen.set_step("Готово", 1.0)
	await screen.finish()
	_running = false

func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	var back := ColorRect.new()
	back.color = Palette.BG_DEEP
	back.mouse_filter = Control.MOUSE_FILTER_STOP   # клики под экраном не нужны
	add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.theme = UITheme.get_theme()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := UITheme.make_label("ЗАГРУЗКА", "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var bar_holder := CenterContainer.new()
	bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bar_holder)
	_bar = Control.new()
	_bar.custom_minimum_size = BAR_SIZE
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	bar_holder.add_child(_bar)
	_caption = UITheme.make_label("", "DimLabel")
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_caption)
	var tip := UITheme.make_label(TIPS[RandomNumberGenerator.new().randi() % TIPS.size()], "SmallLabel")   # своя случайность
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(520.0, 0.0)
	tip.add_theme_color_override("font_color", Palette.TEXT_DIM)
	var tip_holder := CenterContainer.new()
	tip_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_holder.add_child(tip)
	col.add_child(tip_holder)
	_build_spinner(back)
	set_step("", 0.0)

# Круговая анимация в правом нижнем углу; нет кадров — экран без неё (полоса остаётся)
func _build_spinner(parent: Control) -> void:
	for i in SPIN_FRAMES:
		var path := "%s%d.png" % [SPIN_DIR, i]
		if not ResourceLoader.exists(path):
			_spin_textures.clear()
			return
		_spin_textures.append(load(path))
	_spinner = TextureRect.new()
	_spinner.texture = _spin_textures[0]
	_spinner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spinner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_spinner.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # кадры 256 px на экране вдвое мельче
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_spinner)
	_spinner.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_spinner.offset_right = -SPIN_MARGIN
	_spinner.offset_bottom = -SPIN_MARGIN
	_spinner.offset_left = -SPIN_MARGIN - SPIN_SIZE
	_spinner.offset_top = -SPIN_MARGIN - SPIN_SIZE

func set_step(text: String, progress: float) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	if _caption != null:
		_caption.text = text

func _process(delta: float) -> void:
	_age += delta
	if _spinner != null:
		_spinner.texture = _spin_textures[int(_age * SPIN_FPS) % SPIN_FRAMES]
	_shown = lerpf(_shown, _progress, minf(1.0, delta * BAR_LERP))
	if _bar != null:
		_bar.queue_redraw()

# Полоса: тёмная подложка, медная кромка, янтарная заливка (Palette — цветов в файле нет)
func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, BAR_SIZE)
	_bar.draw_rect(r, Palette.PANEL_DARK, true)
	var fill := Rect2(r.position + Vector2(2, 2), Vector2((BAR_SIZE.x - 4.0) * _shown, BAR_SIZE.y - 4.0))
	_bar.draw_rect(fill, Palette.GOLD, true)
	_bar.draw_rect(Rect2(fill.position, Vector2(fill.size.x, 2.0)), Palette.GOLD_BRIGHT, true)   # свет сверху
	_bar.draw_rect(r, Palette.SHOP_FRAME, false, 2.0)

# Экран тает и освобождается; корутина — вызывающий может дождаться
func finish() -> void:
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_method(func(a: float): _set_alpha(a), 1.0, 0.0, FADE_OUT)
	await tw.finished
	queue_free()

func _set_alpha(a: float) -> void:
	for c in get_children():
		if c is CanvasItem:
			c.modulate.a = a
	var mouse := Control.MOUSE_FILTER_STOP if a > 0.5 else Control.MOUSE_FILTER_IGNORE
	for c in get_children():
		if c is Control:
			c.mouse_filter = mouse

func _warm_vfx() -> void:
	Vfx.warm_cache()

func _warm_projectiles() -> void:
	Projectile.warm_cache()

func _warm_audio() -> void:
	AudioManager.warm_cache()

func _warm_pods() -> void:
	if RunManager.player_faction != "chaos":
		DropPod.warm()
