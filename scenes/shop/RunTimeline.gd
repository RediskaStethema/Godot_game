class_name RunTimeline
extends Control

# Лента забега в шапке магазина (решение пользователя): 15 волн слева направо — пройденные тусклые,
# ближайшая крупно янтарём, мини-боссы — ромбы, главный босс — большой красный ромб, события —
# точки между волнами. Подсказка при наведении — что за волна. Только вид: читает RunMapData и
# EconomyManager.round_number (номер ближайшей волны).

const NODE_R: float = 4.0
const CURRENT_R: float = 6.5
const MINIBOSS_R: float = 6.0
const BOSS_R: float = 8.5
const EVENT_R: float = 2.0
const PAD: float = 10.0
const WIDTH: float = 300.0

var current_wave: int = 1

func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_PASS   # подсказки по наведению
	tooltip_text = " "   # подсказка включена; текст — _get_tooltip по волне под курсором

func _ready() -> void:
	refresh()

func refresh() -> void:
	current_wave = clampi(EconomyManager.round_number, 1, RunMapData.TOTAL_WAVES)
	queue_redraw()

static func wave_kind(wave: int) -> String:
	if wave == RunMapData.TOTAL_WAVES:
		return "boss"
	if wave % RunMapData.MINIBOSS_EVERY == 0:
		return "miniboss"
	return "battle"

func _wave_x(wave: int) -> float:
	return PAD + (size.x - 2.0 * PAD) * (wave - 1) / float(RunMapData.TOTAL_WAVES - 1)

func _draw() -> void:
	var y := size.y / 2.0
	draw_line(Vector2(_wave_x(1), y), Vector2(_wave_x(RunMapData.TOTAL_WAVES), y), UITheme.GOLD_DIM, 2.0)
	if current_wave > 1:
		draw_line(Vector2(_wave_x(1), y), Vector2(_wave_x(current_wave), y), UITheme.MENU_AMBER_DIM, 2.0)
	for w in RunMapData.EVENT_AFTER_WAVES:
		if w < RunMapData.TOTAL_WAVES:
			var ex := (_wave_x(w) + _wave_x(w + 1)) / 2.0
			draw_circle(Vector2(ex, y), EVENT_R, UITheme.TEXT if w >= current_wave else UITheme.TEXT_DIM)
	for w in range(1, RunMapData.TOTAL_WAVES + 1):
		var p := Vector2(_wave_x(w), y)
		var done := w < current_wave
		var kind := wave_kind(w)
		var fill: Color = UITheme.GOLD_DIM if done else UITheme.PANEL_DARK
		var edge: Color = UITheme.TEXT_DIM if done else UITheme.TEXT
		if kind == "battle":
			draw_circle(p, NODE_R, fill)
			draw_arc(p, NODE_R, 0.0, TAU, 16, edge, 1.0)
		else:
			var r := BOSS_R if kind == "boss" else MINIBOSS_R
			var c: Color = UITheme.RED_BRIGHT if kind == "boss" else UITheme.GOLD
			_draw_diamond(p, r, UITheme.GOLD_DIM if done else Color(c, 0.35), UITheme.TEXT_DIM if done else c)
		if w == current_wave:
			draw_arc(p, CURRENT_R + (2.0 if kind != "battle" else 0.0), 0.0, TAU, 24, UITheme.GOLD_BRIGHT, 2.0)

func _draw_diamond(p: Vector2, r: float, fill: Color, edge: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, edge, 1.5)

func _get_tooltip(at_position: Vector2) -> String:
	var best := 1
	for w in range(1, RunMapData.TOTAL_WAVES + 1):
		if absf(_wave_x(w) - at_position.x) < absf(_wave_x(best) - at_position.x):
			best = w
	var names := {"battle": "бой", "miniboss": "мини-босс", "boss": "главный босс"}
	var text := "Волна %d — %s" % [best, names[wave_kind(best)]]
	if best in RunMapData.EVENT_AFTER_WAVES:
		text += ", после неё — событие"
	if best < current_wave:
		text += " (пройдена)"
	elif best == current_wave:
		text += " (следующая)"
	return text
