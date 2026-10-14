class_name ArtilleryReticle
extends Node2D

# Прицел орудия игрока (Thunderfire Cannon): в бою ходит за курсором и показывает
# радиус залпа там, куда упадёт ракета. Готово — янтарный круг с заливкой и пульсом,
# перезарядка — тусклый контур и дуга оставшегося времени. Орудий нет / не бой — скрыт.
# Только вид: залп по клику делает BattleScene._unhandled_input.

const COLOR_READY = Color(1.0, 0.72, 0.25)
const COLOR_RELOAD = Color(0.7, 0.75, 0.85)
const FILL_ALPHA: float = 0.12
const LINE_WIDTH: float = 2.0
const PULSE_SPEED: float = 5.0         # рад/с — «дыхание» готового прицела
const PULSE_AMOUNT: float = 0.06       # доля радиуса
const CROSS_SIZE: float = 8.0          # px — перекрестие в центре
const RELOAD_ARC_GAP: float = 6.0      # px — дуга перезарядки снаружи круга
const SEGMENTS: int = 48

var camera: BattleCamera

var _radius: float = 0.0
var _ready_now: bool = false
var _reload_ratio: float = 0.0         # 0..1 — сколько перезарядки осталось
var _time: float = 0.0

func _ready() -> void:
	z_index = 11   # поверх бойцов и снарядов
	visible = false

func _process(delta: float) -> void:
	var cannon = _pick_cannon()
	visible = cannon != null and camera != null
	if not visible:
		return
	_time += delta
	global_position = camera.screen_to_world(get_viewport().get_mouse_position())
	_radius = cannon.stats.get("splash_radius", 0.0)
	_ready_now = cannon.is_artillery_ready()
	var cooldown: float = cannon.stats.get("cooldown", 1.0)
	_reload_ratio = clampf(cannon.cooldown_left / cooldown, 0.0, 1.0) if cooldown > 0.0 else 0.0
	queue_redraw()

# Орудие, которое выстрелит по клику (первое готовое, как BattleScene.fire_artillery);
# готовых нет — то, что зарядится раньше. null — орудий нет или бой не идёт
func _pick_cannon():
	if not BattleManager.is_battle_running():
		return null
	var best = null
	for b in BattleManager.buildings:
		if not is_instance_valid(b) or b.building_type != "artillery":
			continue
		if b.is_artillery_ready():
			return b
		if best == null or b.cooldown_left < best.cooldown_left:
			best = b
	return best

func _draw() -> void:
	if _radius <= 0.0:
		return
	if _ready_now:
		var r = _radius * (1.0 + sin(_time * PULSE_SPEED) * PULSE_AMOUNT)
		draw_circle(Vector2.ZERO, r, Color(COLOR_READY, FILL_ALPHA))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, SEGMENTS, COLOR_READY, LINE_WIDTH, true)
		_draw_cross(COLOR_READY)
	else:
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, SEGMENTS, Color(COLOR_RELOAD, 0.35), LINE_WIDTH * 0.5, true)
		_draw_cross(Color(COLOR_RELOAD, 0.35))
		# Дуга перезарядки: убывает по часовой от верха
		var start = -PI / 2.0
		draw_arc(Vector2.ZERO, _radius + RELOAD_ARC_GAP, start, start + TAU * _reload_ratio, SEGMENTS,
			Color(COLOR_RELOAD, 0.8), LINE_WIDTH, true)

func _draw_cross(color: Color) -> void:
	draw_line(Vector2(-CROSS_SIZE, 0), Vector2(CROSS_SIZE, 0), color, LINE_WIDTH, true)
	draw_line(Vector2(0, -CROSS_SIZE), Vector2(0, CROSS_SIZE), color, LINE_WIDTH, true)
