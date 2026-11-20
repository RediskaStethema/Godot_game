class_name FlameStream
extends Node2D

# Струя огнемёта (Firedrakes, Havoc; решение пользователя 16.11.2026, листы художника assets/effects/flamethrower,
# ТЗ EFFECTS_NEEDED 10.1): от ствола до цели тянется непрерывная струя, а не летящий язык пламени. Только вид:
# урон, поджог и попадание — по-прежнему у снаряда Projectile вида "flame" (он невидим, в тик попадания бьёт цель).
# Три слоя: start — вспышка у дула (6 кадров, 24 к/с), jet — тело струи (8 кадров, 20 к/с, бесшовное по длине,
# кладётся копиями от ствола до цели), hit — огонь на цели (8 кадров, 20 к/с, один раз). Струя вытягивается от ствола
# со скоростью GROW_SPEED, держится LIFE сек и гаснет за FADE. Ствол и цель — живые (стрелок кружит, цель движется).

const SHEET_DIR := "res://assets/effects/flamethrower/"
const START_FRAMES: int = 6
const START_FPS: float = 24.0
const START_SIZE := Vector2(64, 64)      # якорь — левый край, середина высоты (дуло)
const JET_FRAMES: int = 8
const JET_FPS: float = 20.0
const JET_SIZE := Vector2(128, 48)
const HIT_FRAMES: int = 8
const HIT_FPS: float = 20.0
const HIT_SIZE := Vector2(64, 64)        # якорь — центр
const TAIL_FRAMES: int = 4               # лист tail — угасающий хвост у дула, 64×48, 20 к/с (якорь — левый край)
const TAIL_SIZE := Vector2(64, 48)
const TAIL_FPS: float = 20.0
const SCALE: float = 0.55                # толщина тела ~10 px мира при росте бойца 31 px
const GROW_SPEED: float = 900.0          # px/сек — вытягивание струи от ствола
const LIFE: float = 0.42                 # сек до начала затухания (замах + попадание + пауза)
const FADE: float = 0.2
# Форма пламени (решение пользователя 16.11.2026: «из ствола не вылетает, выглядит обрезанным» — ровная тонкая полоса с
# резким срезом у цели читалась лазером): струя режется на узкие ломтики, у дула уже, к цели шире (конус), последняя
# часть тает по прозрачности — среза нет; гаснет мягким материалом (пиксельная альфа давала шашечку)
const SLICE: float = 4.0                 # px мира — ширина ломтика
const CONE_FROM: float = 0.55            # толщина у дула, доли от тела листа
const CONE_TO: float = 1.55              # у цели
const TAPER_FROM: float = 0.62           # с какой доли длины струя начинает таять (у цели — до нуля)
const TIP_FADE: float = 16.0             # px мира: мягкий конец у растущей струи и у цели
const ROOT_FADE: float = 4.0             # px мира: мягкое начало у дула — без ровного среза листа
const LIGHT_EVERY: float = 0.12          # сек между пятнами света на цели

static var _start_tex: Texture2D
static var _jet_tex: Texture2D
static var _hit_tex: Texture2D
static var _tail_tex: Texture2D

var origin_fn: Callable                  # () -> Vector2 — ствол сейчас
var _target: Node2D = null
var _aim_offset: Vector2 = Vector2.ZERO
var _from: Vector2
var _to: Vector2
var _age: float = 0.0
var _hit_node: Node2D
var _light_wait: float = 0.0

# Струя из ствола (origin) в цель target (+ aim_offset) или в точку point; origin_fn — ствол стрелка сейчас
static func spawn(parent: Node, origin: Vector2, origin_fn: Callable, target: Node2D, aim_offset: Vector2,
		point: Vector2) -> FlameStream:
	var s := FlameStream.new()
	s.origin_fn = origin_fn
	s._target = target if is_instance_valid(target) else null
	s._aim_offset = aim_offset if s._target else Vector2.ZERO
	s._from = origin
	s._to = (s._target.global_position + aim_offset) if s._target else point
	s.z_index = 10   # как у снарядов: поверх бойцов
	s.texture_filter = Vfx.filter
	s.material = Vfx.soft_mix_material()
	parent.add_child(s)
	s.global_position = origin
	return s

static func warm_cache() -> void:
	_load_textures()

static func _load_textures() -> void:
	if _start_tex != null:
		return
	_start_tex = load(SHEET_DIR + "start.png")
	_jet_tex = load(SHEET_DIR + "jet.png")
	_hit_tex = load(SHEET_DIR + "hit.png")
	_tail_tex = load(SHEET_DIR + "tail.png")

func _ready() -> void:
	_load_textures()
	_hit_node = Node2D.new()
	_hit_node.top_level = true   # огонь на цели не поворачивается вместе со струёй
	_hit_node.use_parent_material = true
	_hit_node.z_index = 10
	_hit_node.draw.connect(_draw_hit)
	add_child(_hit_node)

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE + FADE:
		queue_free()
		return
	if origin_fn.is_valid():
		_from = origin_fn.call()
	if _target != null:
		if is_instance_valid(_target) and not (_target is Soldier and _target.current_state == Soldier.State.DEAD):
			_to = _target.global_position + _aim_offset
		else:
			_target = null   # цель пала — струя бьёт в последнюю точку
	global_position = _from
	var dir := _to - _from
	rotation = dir.angle()
	scale = Vector2(1.0, -1.0 if dir.x < 0.0 else 1.0)   # влево — отразить по вертикали, дым остаётся сверху
	modulate.a = 1.0 if _age < LIFE else 1.0 - 0.5 * (_age - LIFE) / FADE   # конец — оторвавшееся от дула пламя (_draw)
	_hit_node.global_position = _to
	_light_wait -= delta
	if _light_wait <= 0.0 and _reach() >= dir.length() - 1.0:
		_light_wait = LIGHT_EVERY
		IsoGridRenderer.flash_light(_to, Color(Palette.FIRE, 0.6), 40.0, 0.2)
	queue_redraw()
	_hit_node.queue_redraw()

# Длина струи сейчас: вытягивается от ствола и упирается в цель
func _reach() -> float:
	return minf(_age * GROW_SPEED, _to.distance_to(_from))

func _draw() -> void:
	if _jet_tex == null:
		return
	var length := _reach()
	var full := _to.distance_to(_from)
	var fi := int(_age * JET_FPS) % JET_FRAMES
	# после LIFE пламя отрывается от ствола и улетает к цели (хвост у дула — лист tail), а не гаснет целиком
	var gone := clampf((_age - LIFE) / FADE, 0.0, 1.0)
	var detach := gone * length * 0.9
	var x := detach
	var tex_x := detach / SCALE   # где в листе (px листа по длине), чтобы стык копий оставался бесшовным
	while x < length - 0.5:
		var w := minf(SLICE, length - x)
		var u := (x + w * 0.5) / maxf(full, 1.0)   # 0 — дуло, 1 — цель (по полной длине, не по растущей)
		var thick := JET_SIZE.y * SCALE * lerpf(CONE_FROM, CONE_TO, u)
		var a := 1.0
		if u > TAPER_FROM:
			a = 1.0 - (u - TAPER_FROM) / (1.0 - TAPER_FROM) * 0.9
		a *= smoothstep(0.0, ROOT_FADE, x + w * 0.5 - detach)   # начало у дула (или у оторвавшегося пламени)
		a *= smoothstep(0.0, TIP_FADE, length - (x + w * 0.5))   # конец — и у растущей струи, и у цели
		var src_x := fposmod(tex_x, JET_SIZE.x)
		var src_w := minf(w / SCALE, JET_SIZE.x - src_x)
		draw_texture_rect_region(_jet_tex,
				Rect2(x, -thick * 0.5, src_w * SCALE, thick),
				Rect2(fi * JET_SIZE.x + src_x, 0.0, src_w, JET_SIZE.y), Color(1, 1, 1, a))
		x += src_w * SCALE
		tex_x += src_w
	if _age >= LIFE:   # хвост у дула
		var ti := mini(int((_age - LIFE) * TAIL_FPS), TAIL_FRAMES - 1)
		draw_texture_rect_region(_tail_tex,
				Rect2(0.0, -TAIL_SIZE.y * SCALE * 0.5, TAIL_SIZE.x * SCALE, TAIL_SIZE.y * SCALE),
				Rect2(ti * TAIL_SIZE.x, 0.0, TAIL_SIZE.x, TAIL_SIZE.y))
	var si := int(_age * START_FPS)
	if si < START_FRAMES:   # вспышка у дула поверх начала струи
		draw_texture_rect_region(_start_tex,
				Rect2(0.0, -START_SIZE.y * SCALE * 0.5, START_SIZE.x * SCALE, START_SIZE.y * SCALE),
				Rect2(si * START_SIZE.x, 0.0, START_SIZE.x, START_SIZE.y))

func _draw_hit() -> void:
	if _hit_tex == null:
		return
	var reach_time := _to.distance_to(_from) / GROW_SPEED
	if _age < reach_time:
		return
	var hi := int((_age - reach_time) * HIT_FPS)
	hi = mini(hi, HIT_FRAMES - 1)   # один раз: последний кадр — гаснущий дым, дальше гаснет вся струя
	_hit_node.draw_texture_rect_region(_hit_tex,
			Rect2(-HIT_SIZE * SCALE * 0.5, HIT_SIZE * SCALE),
			Rect2(hi * HIT_SIZE.x, 0.0, HIT_SIZE.x, HIT_SIZE.y))
