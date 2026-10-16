class_name SquadBar
extends Node2D

# Полоска HP отряда над его бойцами — вместо полосок над каждым из сотен мелких бойцов
# (решение пользователя: бой читается по отрядам). Заливка — HP живых от полного состава
# (павшие — пустая часть), справа — число бойцов, над ней — уровень отряда ромбиками.
# Только вид: ходит за бойцами каждый кадр, перерисовывается, когда меняются цифры.

const SIZE = Vector2(30, 4)
const GAP: float = 6.0            # над головой самого высокого бойца
const COUNT_FONT_SIZE: int = 20         # крупный кегль, уменьшенный COUNT_SCALE — мелкий рассыпается
const COUNT_SCALE: float = 0.5
const PIP_R: float = 2.0
const PIP_STEP: float = 5.0
const PIP_GAP: float = 4.0

var squad: Squad
var _ratio: float = -1.0
var _count: int = -1
var _level: int = -1

func _ready() -> void:
	top_level = true   # своя позиция в мире — над бойцами, а не над клеткой отряда
	z_index = 50       # поверх бойцов и построек
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # текст — не пиксельным фильтром мира

func _process(_delta: float) -> void:
	if squad == null or squad.data == null:
		return
	var alive := 0
	var hp := 0.0
	var max_sum := 0.0
	var x_sum := 0.0
	var top := INF
	for s in squad.soldiers:
		if s.current_state == Soldier.State.DEAD:
			continue
		alive += 1
		hp += s.current_hp
		max_sum += s.max_hp
		x_sum += s.global_position.x
		top = minf(top, s.global_position.y)
	if alive == 0:
		visible = false
		return
	visible = true
	global_position = Vector2(x_sum / alive, top - Soldier.TARGET_SPRITE_HEIGHT * squad.data.sprite_scale - GAP)
	# Полный состав — павшие считаются бойцами со средним max HP живых
	var full := max_sum + maxi(squad.data.squad_size - alive, 0) * (max_sum / alive)
	var ratio := clampf(hp / maxf(full, 0.001), 0.0, 1.0)
	if absf(ratio - _ratio) * SIZE.x >= 0.5 or alive != _count or squad.data.squad_level != _level:
		_ratio = ratio
		_count = alive
		_level = squad.data.squad_level
		queue_redraw()

func _draw() -> void:
	if _count <= 0:
		return
	var rect := Rect2(Vector2(-SIZE.x / 2.0, -SIZE.y), SIZE)
	draw_rect(rect.grow(1.0), Color(0, 0, 0, 0.75))
	var color := UITheme.GREEN if squad.team == GameConstants.TEAM_PLAYER else UITheme.RED_BRIGHT
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * _ratio, rect.size.y)), color)
	if squad.data.squad_size > 1:
		draw_set_transform(Vector2(rect.end.x + 3.0, 1.0), 0.0, Vector2(COUNT_SCALE, COUNT_SCALE))
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2.ZERO, "×%d" % _count, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE,
			4, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2.ZERO, "×%d" % _count, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNT_FONT_SIZE,
			Color(1, 1, 1, 0.9))
		draw_set_transform(Vector2.ZERO)
	for i in _level:
		var c := Vector2((i - (_level - 1) / 2.0) * PIP_STEP, rect.position.y - PIP_GAP)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -PIP_R), c + Vector2(PIP_R, 0),
			c + Vector2(0, PIP_R), c + Vector2(-PIP_R, 0)]), UITheme.GOLD_BRIGHT)
