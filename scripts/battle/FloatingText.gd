class_name FloatingText
extends Node2D

# Всплывающая надпись над полем (решение пользователя): крупный удар, лечение, павший отряд.
# Поднимается и гаснет за LIFETIME; только вид — таймер кадров, не тик боя. Живых надписей
# не больше MAX_ALIVE: в свалке сотен бойцов иначе каша (лишние просто не появляются).

const LIFETIME: float = 0.9
const RISE: float = 22.0
const FONT_SIZE: int = 26          # крупный кегль, уменьшенный SCALE — мелкий рассыпается
const SCALE: float = 0.5
const MAX_ALIVE: int = 40
const MAX_PER_FRAME: int = 6      # залп по толпе — не десятки узлов за один тик (рывок кадра)
const Z_INDEX: int = 60            # поверх полосок отрядов (SquadBar — 50)
const JITTER: float = 5.0
# Числа в одной точке складываются (решение пользователя 24.10.2026: в сшибке «22 23 23» налезали друг
# на друга): новое число того же цвета ближе MERGE_RADIUS к живому моложе MERGE_AGE — прибавляется к нему,
# надпись вздрагивает (BUMP) и живёт заново; лечение «+N» — так же
const MERGE_RADIUS: float = 18.0
const MERGE_AGE: float = 0.45
const BUMP: float = 0.25
const BUMP_TIME: float = 0.12

static var alive_count: int = 0
static var _frame: int = -1
static var _spawned_this_frame: int = 0
static var _numbers: Array = []   # живые числовые надписи — кандидаты на сложение

var text: String = ""
var color: Color = Color.WHITE
var size_mult: float = 1.0
var _age: float = 0.0
var _origin: Vector2
var _value: int = 0
var _prefix: String = ""
var _numeric: bool = false
var _bump_left: float = 0.0

# Надпись в мировой точке; null — лимит надписей исчерпан или некуда добавить.
# important (павший отряд) — мимо лимитов: её не должны вытеснить цифры урона того же кадра
static func spawn(parent: Node, at: Vector2, label: String, tint: Color, size: float = 1.0,
		important: bool = false) -> FloatingText:
	if parent == null or not parent.is_inside_tree():
		return null
	if Engine.get_process_frames() != _frame:
		_frame = Engine.get_process_frames()
		_spawned_this_frame = 0
	var prefix := "+" if label.begins_with("+") else ""
	var digits := label.substr(prefix.length())
	if not important and digits.is_valid_int():
		for n in _numbers:
			if is_instance_valid(n) and n._prefix == prefix and n.color == tint and n._age < MERGE_AGE 					and n._origin.distance_to(at) < MERGE_RADIUS:
				n._add(int(digits))
				return n
	if not important:
		if alive_count >= MAX_ALIVE or _spawned_this_frame >= MAX_PER_FRAME:
			return null
		_spawned_this_frame += 1
	var t := FloatingText.new()
	t.text = label
	t.color = tint
	t._numeric = not important and digits.is_valid_int()
	t._prefix = prefix
	t._value = int(digits) if t._numeric else 0
	t.size_mult = size
	t.top_level = true   # до add_child: position — сразу мировая, _ready запомнит верную точку
	# Разброс по горизонтали по счётчику (без случайности): соседние цифры не слипаются
	t.position = at + Vector2(float((alive_count * 7) % 5 - 2) * JITTER, 0.0)
	parent.add_child(t)
	return t

func _enter_tree() -> void:
	alive_count += 1
	if _numeric:
		_numbers.append(self)

func _exit_tree() -> void:
	alive_count -= 1
	_numbers.erase(self)

func _add(v: int) -> void:
	_value += v
	text = _prefix + str(_value)
	_age = 0.0
	_bump_left = BUMP_TIME
	queue_redraw()

func _ready() -> void:
	z_index = Z_INDEX
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_origin = global_position

func _process(delta: float) -> void:
	_age += delta
	_bump_left = maxf(_bump_left - delta, 0.0)
	if _age >= LIFETIME:
		queue_free()
		return
	var k := _age / LIFETIME
	global_position = _origin + Vector2(0.0, -RISE * (1.0 - (1.0 - k) * (1.0 - k)))   # быстро вверх, плавно стоп
	modulate.a = 1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4
	queue_redraw()

func _draw() -> void:
	var font := UITheme.world_font()
	var fs := UITheme.world_px(FONT_SIZE * size_mult)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var s := SCALE * (1.0 + BUMP * _bump_left / BUMP_TIME)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	draw_string_outline(font, Vector2(-w / 2.0, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, UITheme.OUTLINE)
	draw_string(font, Vector2(-w / 2.0, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
