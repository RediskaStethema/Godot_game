class_name ScaledNinePatch
extends StyleBox

# 9-slice текстуры, нарисованной крупнее экрана (решение пользователя 06.11.2026: кнопки и рамки меню в высоком
# разрешении, пакет assets/menu_ui → UI_NEEDED 7.1 / 7.3). StyleBoxTexture рисует углы в пикселях текстуры
# один к одному — кнопка 640×104 с углами 32 / 28 px не влезла бы в кнопку 52 px; здесь углы и торцы берутся
# из текстуры (margin, px текстуры) и рисуются в art_scale раз (×0.5 — как прежние 16 / 14 px), середина тянется.
# Резкость — от крупной текстуры при любом масштабе окна (canvas_items). Поля содержимого — content_margin_*.

@export var texture: Texture2D
@export var margin: Vector4 = Vector4.ZERO        # left, top, right, bottom — px текстуры
@export var art_scale: float = 0.5
@export var modulate_color: Color = Color.WHITE
# Повтор по горизонтали (полоса шапки hud_bar, UI_NEEDED 8.3a): текстура целиком по высоте прямоугольника,
# повторяется вдоль него с шагом ширины текстуры в том же масштабе; margin не используется
@export var tile_x: bool = false

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if texture == null:
		return
	if tile_x:
		_draw_tiled(to_canvas_item, rect)
		return
	var ts := texture.get_size()
	var dl := margin.x * art_scale
	var dt := margin.y * art_scale
	var dr := margin.z * art_scale
	var db := margin.w * art_scale
	# Узкая / низкая кнопка — углы ужимаются пропорционально, а не налезают друг на друга
	var kx := minf(1.0, rect.size.x / maxf(dl + dr, 0.001))
	var ky := minf(1.0, rect.size.y / maxf(dt + db, 0.001))
	dl *= kx
	dr *= kx
	dt *= ky
	db *= ky
	var sx := [0.0, margin.x, ts.x - margin.z, ts.x]
	var sy := [0.0, margin.y, ts.y - margin.w, ts.y]
	var px := [rect.position.x, rect.position.x + dl, rect.end.x - dr, rect.end.x]
	var py := [rect.position.y, rect.position.y + dt, rect.end.y - db, rect.end.y]
	var rid := texture.get_rid()
	for j in 3:
		for i in 3:
			var dst := Rect2(px[i], py[j], px[i + 1] - px[i], py[j + 1] - py[j])
			var src := Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j])
			if dst.size.x <= 0.0 or dst.size.y <= 0.0 or src.size.x <= 0.0 or src.size.y <= 0.0:
				continue
			RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, dst, rid, src, modulate_color)

func _draw_tiled(to_canvas_item: RID, rect: Rect2) -> void:
	var ts := texture.get_size()
	var step := ts.x * rect.size.y / ts.y   # ширина плитки на экране — в масштабе высоты
	if step < 1.0:
		return
	var rid := texture.get_rid()
	var x := rect.position.x
	while x < rect.end.x - 0.01:
		var w := minf(step, rect.end.x - x)
		var src := Rect2(0.0, 0.0, ts.x * w / step, ts.y)
		RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, Rect2(x, rect.position.y, w, rect.size.y),
			rid, src, modulate_color)
		x += step
