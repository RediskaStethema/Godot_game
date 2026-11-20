class_name RunTimeline
extends Control

# Лента забега в шапке магазина (решение пользователя): 15 волн слева направо, мини-боссы — ромбы, главный
# босс — большой красный ромб, события — значки между волнами. Решения пользователя 10.11.2026:
# - пройденный путь горит красным (линия и значки пройденных волн — `Palette.TIMELINE_DONE`);
# - текущая волна (та, что сейчас играется, — EconomyManager.round_number): светится сам её кристалл
#   (значок ярче и пульсирует, без ореола вокруг);
# - маркер над текущей волной (значок `current`) при открытии магазина переезжает с прошлой волны на текущую,
#   красная линия растёт вместе с ним (`MARKER_MOVE_TIME`);
# - подпись «событие» — только при наведении на значок события (и в подсказке).
# Значки пакета интерфейса (assets/ui/ribbon) — шлем, череп, рогатый череп, звезда Хаоса, маркер. Только вид.

const NODE_R: float = 4.0
const MINIBOSS_R: float = 6.0
const BOSS_R: float = 8.5
const EVENT_R: float = 2.5
const PAD: float = 12.0
# Значки пакета интерфейса (assets/ui/ribbon): высота px; нет файла — прежние круги и ромбы
const ICON_SIZES = {"battle": 15.0, "miniboss": 20.0, "boss": 28.0, "event": 12.0, "current": 12.0}
const WIDTH: float = 400.0
const LINE_Y: float = 0.45           # линия ленты — доля высоты (снизу место под подпись события)
const LINE_WIDTH: float = 2.0
const DONE_LINE_WIDTH: float = 3.0
# Свечение кристалла текущей волны: тот же значок поверх себя ADD цветом TIMELINE_GLOW (светится только
# по форме кристалла, без ореола), сила GEM_GLOW_MIN..MAX по пульсу, рост GEM_GROW
const GEM_GLOW_MIN: float = 0.5
const GEM_GLOW_MAX: float = 0.95
const GEM_GROW: float = 0.12
const GEM_PULSE_HZ: float = 0.9
# Переезд маркера с прошлой волны на текущую
const MARKER_MOVE_DELAY: float = 0.35
const MARKER_MOVE_TIME: float = 0.9
const EVENT_LABEL: String = "событие"
const EVENT_LABEL_FONT: int = 8      # кегль подписи до UITheme.text_px
const EVENT_LABEL_GAP: float = 2.0   # от линии / соседнего значка

var current_wave: int = 1
var marker_wave: float = 1.0         # где сейчас маркер (дробное — в пути между волнами)
var _hover_x: float = -1.0           # курсор над лентой (x), -1 — нет
var _move_tween: Tween = null
var _gem_layer: Control = null       # слой ADD над лентой — свет кристалла текущей волны
var _pulse: float = 0.0

func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # значки ленты в 6–8 раз мельче файла
	mouse_filter = Control.MOUSE_FILTER_PASS   # подсказки и подпись события по наведению
	tooltip_text = " "   # подсказка включена; текст — _get_tooltip по месту под курсором
	mouse_exited.connect(func():
		_hover_x = -1.0
		queue_redraw())
	_gem_layer = Control.new()
	_gem_layer.name = "GemGlow"
	_gem_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gem_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_gem_layer.material = add
	_gem_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_gem_layer.draw.connect(_draw_gem_glow)
	add_child(_gem_layer)

func _ready() -> void:
	refresh()

func refresh() -> void:
	current_wave = clampi(EconomyManager.round_number, 1, RunMapData.TOTAL_WAVES)
	if _move_tween:
		_move_tween.kill()
	marker_wave = float(maxi(current_wave - 1, 1))
	if current_wave > 1:   # маркер переезжает с прошлой волны (время дерева: в магазине паузы нет)
		_move_tween = create_tween()
		_move_tween.tween_interval(MARKER_MOVE_DELAY)
		_move_tween.tween_property(self, "marker_wave", float(current_wave), MARKER_MOVE_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	queue_redraw()

# Пульс кристалла и переезд маркера — перерисовка каждый кадр, пока лента видна
func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * GEM_PULSE_HZ)
		queue_redraw()
		_gem_layer.queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_x = event.position.x

static func wave_kind(wave: int) -> String:
	if wave == RunMapData.TOTAL_WAVES:
		return "boss"
	if wave % RunMapData.MINIBOSS_EVERY == 0:
		return "miniboss"
	return "battle"

func _wave_x(wave: float) -> float:
	return PAD + (size.x - 2.0 * PAD) * (wave - 1.0) / float(RunMapData.TOTAL_WAVES - 1)

func _event_x(w: int) -> float:
	return (_wave_x(w) + _wave_x(w + 1)) / 2.0

func _icon_half(kind: String) -> float:
	return ICON_SIZES[kind] / 2.0

# Событие под курсором: после какой волны (0 — курсор не на событии). На событии — если к нему ближе,
# чем к любой волне
func hovered_event_at(x: float) -> int:
	if x < 0.0:
		return 0
	var half_step := (_wave_x(2) - _wave_x(1)) / 2.0
	for w in RunMapData.EVENT_AFTER_WAVES:
		if w < RunMapData.TOTAL_WAVES and absf(x - _event_x(w)) < half_step / 2.0:
			return w
	return 0

func _draw() -> void:
	var y := size.y * LINE_Y
	draw_line(Vector2(_wave_x(1), y), Vector2(_wave_x(RunMapData.TOTAL_WAVES), y), UITheme.GOLD_DIM, LINE_WIDTH)
	if marker_wave > 1.0:   # пройденный путь — красным до маркера
		draw_line(Vector2(_wave_x(1), y), Vector2(_wave_x(marker_wave), y), Palette.TIMELINE_DONE, DONE_LINE_WIDTH)
	for w in RunMapData.EVENT_AFTER_WAVES:
		if w < RunMapData.TOTAL_WAVES:
			var done := w < current_wave
			if not _draw_icon("event", Vector2(_event_x(w), y), Palette.TIMELINE_DONE if done else Color.WHITE):
				draw_circle(Vector2(_event_x(w), y), EVENT_R, Palette.TIMELINE_DONE if done else UITheme.TEXT)
	for w in range(1, RunMapData.TOTAL_WAVES + 1):
		var p := Vector2(_wave_x(w), y)
		var done := w < current_wave
		var kind := wave_kind(w)
		var tint: Color = Palette.TIMELINE_DONE if done else Color.WHITE
		var grow := _gem_grow() if w == current_wave else 1.0   # кристалл текущей волны дышит (свет — _draw_gem_glow)
		if _draw_icon(kind, p, tint, grow):
			continue
		var fill: Color = Color(Palette.TIMELINE_DONE, 0.45) if done else UITheme.PANEL_DARK
		var edge: Color = Palette.TIMELINE_DONE if done else UITheme.TEXT
		if w == current_wave:
			fill = Color(Palette.TIMELINE_GLOW, 0.5 + 0.5 * _pulse)
			edge = Palette.TIMELINE_GLOW
		if kind == "battle":
			draw_circle(p, NODE_R * grow, fill)
			draw_arc(p, NODE_R * grow, 0.0, TAU, 16, edge, 1.0)
		else:
			var r := (BOSS_R if kind == "boss" else MINIBOSS_R) * grow
			var c: Color = UITheme.RED_BRIGHT if kind == "boss" else UITheme.GOLD
			var current := w == current_wave
			_draw_diamond(p, r, fill if done or current else Color(c, 0.35), edge if done or current else c)
	_draw_marker(y)
	var ev := hovered_event_at(_hover_x)
	if ev > 0:
		_draw_event_label(ev, y)

func _gem_grow() -> float:
	return 1.0 + GEM_GROW * _pulse

# Свет кристалла текущей волны (слой ADD): тот же значок поверх него цветом TIMELINE_GLOW — светлеет сам кристалл
func _draw_gem_glow() -> void:
	var k := lerpf(GEM_GLOW_MIN, GEM_GLOW_MAX, _pulse)
	var c := Color(Palette.TIMELINE_GLOW.r * k, Palette.TIMELINE_GLOW.g * k, Palette.TIMELINE_GLOW.b * k, 1.0)
	var kind := wave_kind(current_wave)
	if not _icons.has(kind):
		return
	var tex: Texture2D = _icons[kind]
	if tex == null:
		return
	var h: float = ICON_SIZES[kind] * _gem_grow()
	var sz := Vector2(h * tex.get_width() / float(tex.get_height()), h)
	var p := Vector2(_wave_x(current_wave), size.y * LINE_Y)
	_gem_layer.draw_texture_rect(tex, Rect2(p - sz / 2.0, sz), false, c)

# Маркер над текущей волной; в пути — между волнами, высота над значком — по ближайшей волне
func _draw_marker(y: float) -> void:
	var near := clampi(roundi(marker_wave), 1, RunMapData.TOTAL_WAVES)
	var p := Vector2(_wave_x(marker_wave), y - _icon_half(wave_kind(near)) - _icon_half("current") + 1.0)
	if not _draw_icon("current", p, Color.WHITE):
		var pts := PackedVector2Array([p + Vector2(-4, -3), p + Vector2(4, -3), p + Vector2(0, 3)])
		draw_colored_polygon(pts, Palette.TIMELINE_GLOW)

# Подпись «событие» под значком события w (при наведении); не заходит под крупный значок соседней волны
func _draw_event_label(w: int, y: float) -> void:
	var font := get_theme_font("font", "Label")
	var fs := UITheme.text_px(EVENT_LABEL_FONT)
	var text_w := font.get_string_size(EVENT_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var top := y + _icon_half("event") + EVENT_LABEL_GAP
	var x := _event_x(w) - text_w / 2.0
	for nb in [w, w + 1]:
		var half := _icon_half(wave_kind(nb))
		if y + half <= top:
			continue
		if nb > w:
			x = minf(x, _wave_x(nb) - half - EVENT_LABEL_GAP - text_w)
		else:
			x = maxf(x, _wave_x(nb) + half + EVENT_LABEL_GAP)
	draw_string(font, Vector2(x, top + font.get_ascent(fs)), EVENT_LABEL, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UITheme.GOLD_BRIGHT)

# Значок ленты по центру p; false — файла нет (рисуется прежняя фигура)
# Текстуры — в кэше узла: загруженная в _draw освобождается до отрисовки (белый прямоугольник)
var _icons: Dictionary = {}
func _draw_icon(kind: String, p: Vector2, tint: Color, grow: float = 1.0) -> bool:
	if not _icons.has(kind):
		_icons[kind] = UITheme.ui_icon("ribbon", "wave" if kind == "battle" else kind)
	var tex: Texture2D = _icons[kind]
	if tex == null:
		return false
	var h: float = ICON_SIZES[kind] * grow
	var sz := Vector2(h * tex.get_width() / float(tex.get_height()), h)
	draw_texture_rect(tex, Rect2(p - sz / 2.0, sz), false, tint)
	return true

func _draw_diamond(p: Vector2, r: float, fill: Color, edge: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, edge, 1.5)

func _get_tooltip(at_position: Vector2) -> String:
	var ev := hovered_event_at(at_position.x)
	if ev > 0:
		return "Событие после волны %d — выбор с наградой и риском%s" % [ev, " (пройдено)" if ev < current_wave else ""]
	var best := 1
	for w in range(1, RunMapData.TOTAL_WAVES + 1):
		if absf(_wave_x(w) - at_position.x) < absf(_wave_x(best) - at_position.x):
			best = w
	var names := {"battle": "бой", "miniboss": "мини-босс", "boss": "главный босс"}
	var text := "Волна %d из %d — %s" % [best, RunMapData.TOTAL_WAVES, names[wave_kind(best)]]
	if best < current_wave:
		text += " (пройдена)"
	elif best == current_wave:
		text += " (сейчас)"
	return text
