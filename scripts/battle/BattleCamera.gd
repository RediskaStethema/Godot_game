class_name BattleCamera
extends Camera2D

# Камера боя: вписывает мир (IsoGrid.get_world_bounds) в свободную от UI
# область экрана. При расстановке — ближе (PLACEMENT_ZOOM), якорь в левом
# верхнем углу мира: королевство и цитадель крупнее, зона врага может
# обрезаться (враги до боя скрыты). В бою — весь мир по центру области.

const TWEEN_TIME: float = 0.6
const PLACEMENT_ZOOM: float = 1.15

func fit(bounds: Rect2, area: Rect2, placement: bool, animate: bool) -> void:
	var z = minf(area.size.x / bounds.size.x, area.size.y / bounds.size.y)
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
	if animate:
		var tw = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(self, "zoom", Vector2(z, z), TWEEN_TIME)
		tw.tween_property(self, "position", pos, TWEEN_TIME)
	else:
		zoom = Vector2(z, z)
		position = pos

# Экран ↔ мир (UI живёт в CanvasLayer, камера на него не влияет)
func screen_to_world(p: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * p

func world_to_screen(p: Vector2) -> Vector2:
	return get_canvas_transform() * p
