class_name SquadBar
extends Node2D

# Полоска HP отряда над его бойцами — вместо полосок над каждым из сотен мелких бойцов
# (решение пользователя: бой читается по отрядам). Заливка — HP живых от полного состава
# (павшие — пустая часть), справа — число бойцов, над ней — уровень отряда ромбиками.
# Только вид: ходит за бойцами каждый кадр, перерисовывается, когда меняются цифры.

const SIZE = Vector2(34, 5)
const GAP: float = 6.0            # над головой самого высокого бойца
const COUNT_FONT_SIZE: int = 14         # крупный кегль, уменьшенный COUNT_SCALE — мелкий рассыпается
# Сторона читается по полоске (решение пользователя 24.10.2026: в сшибке свои и чужие сливались): кромка и
# число бойцов — цветом стороны (свои янтарь, враги красный); было — чёрная кромка и белое число у всех
const COUNT_COLOR_PLAYER = Palette.GOLD_PALE
const COUNT_COLOR_ENEMY = Color(1.0, 0.62, 0.55)
const COUNT_SCALE: float = 0.75   # решение пользователя 18.11.2026: число бойцов было мелким
const PIP_R: float = 2.0
const PIP_STEP: float = 5.0
const PIP_GAP: float = 4.0
const SHIELD_COLOR = UITheme.SHIELD_BLUE   # щит Iron Halo — полоска под HP
const SHIELD_HEIGHT: float = 2.0

var squad: Squad
var _ratio: float = -1.0
var _count: int = -1
var _level: int = -1
var _shield: float = 0.0   # доля щита от полного HP отряда

func _ready() -> void:
	top_level = true   # своя позиция в мире — над бойцами, а не над клеткой отряда
	z_index = 50       # поверх бойцов и построек
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # текст — не пиксельным фильтром мира

func _process(_delta: float) -> void:
	if squad == null or squad.data == null:
		return
	var alive := 0
	var hp := 0.0
	var shield := 0.0
	var max_sum := 0.0
	var x_sum := 0.0
	var top := INF
	for s in squad.soldiers:
		if s.current_state == Soldier.State.DEAD:
			continue
		alive += 1
		hp += s.current_hp
		shield += s.shield
		max_sum += s.max_hp
		x_sum += s.global_position.x
		top = minf(top, s.global_position.y)
	if alive == 0:
		visible = false
		return
	visible = true
	modulate.a = squad.modulate.a   # top_level прозрачность отряда не наследует: отряд в капсуле / проявляется
	global_position = Vector2(x_sum / alive, top - Soldier.TARGET_SPRITE_HEIGHT * squad.data.sprite_scale - GAP)
	# Полный состав — павшие считаются бойцами со средним max HP живых
	var full := max_sum + maxi(squad.data.squad_size - alive, 0) * (max_sum / alive)
	var ratio := clampf(hp / maxf(full, 0.001), 0.0, 1.0)
	var shield_ratio := clampf(shield / maxf(full, 0.001), 0.0, 1.0)
	if absf(ratio - _ratio) * SIZE.x >= 0.5 or absf(shield_ratio - _shield) * SIZE.x >= 0.5 or alive != _count or squad.data.squad_level != _level:
		_ratio = ratio
		_shield = shield_ratio
		_count = alive
		_level = squad.data.squad_level
		queue_redraw()

func _draw() -> void:
	if _count <= 0:
		return
	var rect := Rect2(Vector2(-SIZE.x / 2.0, -SIZE.y), SIZE)
	var own: bool = squad.team == GameConstants.TEAM_PLAYER
	draw_rect(rect.grow(2.0), Color(0, 0, 0, 0.75))
	draw_rect(rect.grow(1.0), UITheme.PLAYER_SIDE if own else UITheme.ENEMY_SIDE)
	draw_rect(rect, Color(0.05, 0.05, 0.06))   # потерянное
	var color := UITheme.GREEN if own else UITheme.ENEMY_SIDE
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * _ratio, rect.size.y)), color)
	if _shield > 0.0:
		draw_rect(Rect2(Vector2(rect.position.x, rect.end.y + 1.0), Vector2(rect.size.x * _shield, SHIELD_HEIGHT)), SHIELD_COLOR)
	if squad.data.squad_size > 1:
		draw_set_transform(Vector2(rect.end.x + 3.0, 1.0), 0.0, Vector2(COUNT_SCALE, COUNT_SCALE))
		var font := UITheme.world_font()
		draw_string_outline(font, Vector2.ZERO, "×%d" % _count, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.world_px(COUNT_FONT_SIZE),
			4, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2.ZERO, "×%d" % _count, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.world_px(COUNT_FONT_SIZE),
			COUNT_COLOR_PLAYER if own else COUNT_COLOR_ENEMY)
		draw_set_transform(Vector2.ZERO)
	for i in _level:
		var c := Vector2((i - (_level - 1) / 2.0) * PIP_STEP, rect.position.y - PIP_GAP)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -PIP_R), c + Vector2(PIP_R, 0),
			c + Vector2(0, PIP_R), c + Vector2(-PIP_R, 0)]), UITheme.GOLD_BRIGHT)
