class_name BattleCamera
extends Camera2D

# Камера боя: вписывает мир (IsoGrid.get_world_bounds) в свободную от UI
# область экрана. При расстановке — ближе (PLACEMENT_ZOOM), якорь в левом
# верхнем углу мира: королевство и цитадель крупнее, зона врага может
# обрезаться (враги до боя скрыты). В бою — весь мир по центру области.

const TWEEN_TIME: float = 0.6
const PLACEMENT_ZOOM: float = 1.15
const SHAKE_TIME: float = 0.3
const SHAKE_STEP: float = 0.03

# Ручная камера (решение пользователя): колесо — зум к курсору, правая / средняя кнопка — тянуть.
# Зум — в пределах ZOOM_RANGE от вписанного fit(); центр не уходит дальше поля + PAN_MARGIN
const ZOOM_STEP: float = 1.12
const ZOOM_RANGE = Vector2(0.7, 3.0)
const PAN_MARGIN: float = 200.0

var _fit_zoom: float = 1.0
var _bounds: Rect2 = Rect2()
var _fit_tween: Tween
var _shake_tween: Tween
var _shake_rng := RandomNumberGenerator.new()   # своя случайность — общий randf боя не сдвигается

func fit(bounds: Rect2, area: Rect2, placement: bool, animate: bool) -> void:
	var z = minf(area.size.x / bounds.size.x, area.size.y / bounds.size.y)
	_fit_zoom = z
	_bounds = bounds
	var screen_center = get_viewport_rect().size / 2.0
	# Экран = (мир − position) × zoom + центр экрана
	var pos = bounds.get_center() - (area.get_center() - screen_center) / z
	if placement:
		z *= PLACEMENT_ZOOM
		pos = bounds.position - (area.position - screen_center) / z
		# Если после приближения мир всё ещё уже области — центрируем по этой оси
		var visible = area.size / z
		if bounds.size.x <= visible.x:
			pos.x = bounds.get_center().x - (area.get_center().x - screen_center.x) / z
		if bounds.size.y <= visible.y:
			pos.y = bounds.get_center().y - (area.get_center().y - screen_center.y) / z
	if _fit_tween and _fit_tween.is_valid():
		_fit_tween.kill()
	if animate:
		_fit_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_fit_tween.tween_property(self, "zoom", Vector2(z, z), TWEEN_TIME)
		_fit_tween.tween_property(self, "position", pos, TWEEN_TIME)
	else:
		zoom = Vector2(z, z)
		position = pos

# Зум колесом: точка мира под курсором остаётся под курсором
func zoom_at(screen_point: Vector2, steps: float) -> void:
	if _fit_tween and _fit_tween.is_valid():
		_fit_tween.kill()   # игрок взял камеру — отъезд после «В БОЙ» не перебивает
	# Формула камеры (как в fit): экран = (мир − position) × zoom + центр экрана. Не через
	# get_canvas_transform — он обновится только к следующему кадру (несколько щелчков за кадр)
	var from_center := screen_point - get_viewport_rect().size / 2.0
	var before := position + from_center / zoom.x
	var z := clampf(zoom.x * pow(ZOOM_STEP, steps), _fit_zoom * ZOOM_RANGE.x, _fit_zoom * ZOOM_RANGE.y)
	zoom = Vector2(z, z)
	position = before - from_center / z
	_clamp_position()

# Тянуть камеру мышью: сдвиг экрана → сдвиг мира
func pan(screen_delta: Vector2) -> void:
	if _fit_tween and _fit_tween.is_valid():
		_fit_tween.kill()
	position -= screen_delta / zoom.x
	_clamp_position()

func _clamp_position() -> void:
	if _bounds.size == Vector2.ZERO:
		return
	var area := _bounds.grow(PAN_MARGIN)
	position = position.clamp(area.position, area.end)

# Тряска (взрыв залпа): сдвиг offset гаснет за SHAKE_TIME — только вид, position не трогает
func shake(strength: float) -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	var steps := int(SHAKE_TIME / SHAKE_STEP)
	for i in steps:
		var k := strength * (1.0 - float(i) / steps)
		_shake_tween.tween_property(self, "offset", Vector2(_shake_rng.randf_range(-k, k), _shake_rng.randf_range(-k, k)), SHAKE_STEP)
	_shake_tween.tween_property(self, "offset", Vector2.ZERO, SHAKE_STEP)

# Экран ↔ мир (UI живёт в CanvasLayer, камера на него не влияет)
func screen_to_world(p: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * p

func world_to_screen(p: Vector2) -> Vector2:
	return get_canvas_transform() * p
