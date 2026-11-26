class_name Casings
extends Node2D

# Гильзы (решение пользователя 18.11.2026, «эффекты»): выстрел из болтера выбрасывает пару латунных гильз — взлетают
# с дугой, падают, лежат миг и тают. Только вид: своя случайность (не randf боя), не больше MAX_ALIVE живых и
# MAX_PER_FRAME за кадр — сотни стрелков не заливают поле.

const MAX_ALIVE: int = 36
const MAX_PER_FRAME: int = 3
const GRAVITY: float = 260.0      # px/с²
const LIE_TIME: float = 0.7       # лежит на земле
const FADE_TIME: float = 0.4
const COLOR_BRASS = Color(0.78, 0.6, 0.28)
const COLOR_DARK = Color(0.35, 0.24, 0.12)

static var _alive: int = 0
static var _frame: int = -1
static var _this_frame: int = 0
static var _rng := RandomNumberGenerator.new()

var _vel := Vector2.ZERO
var _lift: float = 0.0       # высота над землёй, px
var _vlift: float = 0.0
var _age: float = 0.0
var _rot: float = 0.0
var _spin: float = 0.0
var _landed: bool = false

# at — ствол в мире, side — куда выбрасывает (знак по x), parent — мир боя
static func eject(parent: Node, at: Vector2, side: float) -> void:
	if parent == null or not GameSettings.atmosphere or _alive >= MAX_ALIVE:
		return
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_this_frame = 0
	if _this_frame >= MAX_PER_FRAME:
		return
	_this_frame += 1
	var c := Casings.new()
	c.z_index = 2
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c._vel = Vector2(side * _rng.randf_range(10.0, 26.0), _rng.randf_range(-4.0, 4.0) * 0.5)
	c._vlift = _rng.randf_range(35.0, 60.0)
	c._spin = _rng.randf_range(-12.0, 12.0)
	_alive += 1
	parent.add_child(c)
	c.global_position = at
	c.tree_exiting.connect(func(): _alive = maxi(_alive - 1, 0))

func _process(delta: float) -> void:
	_age += delta
	if not _landed:
		_vlift -= GRAVITY * delta
		_lift += _vlift * delta
		position += _vel * delta
		_rot += _spin * delta
		if _lift <= 0.0:
			_lift = 0.0
			_landed = true
			_age = 0.0
	elif _age > LIE_TIME + FADE_TIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var a := 1.0
	if _landed and _age > LIE_TIME:
		a = 1.0 - (_age - LIE_TIME) / FADE_TIME
	draw_set_transform(Vector2(0.0, -_lift), _rot, Vector2.ONE)
	draw_rect(Rect2(-1.0, -0.5, 2.0, 1.0), Color(COLOR_BRASS, a))
	draw_rect(Rect2(-1.0, 0.5, 2.0, 0.5), Color(COLOR_DARK, a))
