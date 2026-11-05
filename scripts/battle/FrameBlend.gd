class_name FrameBlend
extends Sprite2D

# Перетекание кадров (решение пользователя 19.10.2026: «добавь плавности зданиям, персонажам и эффектам»):
# покадровая анимация листов идёт 5–16 к/с и на смене кадра дёргается. Ребёнок AnimatedSprite2D рисует
# поверх следующий кадр с прозрачностью = доле прошедшего времени текущего (frame_progress) — к смене кадра
# он уже целиком виден, скачка нет. Так же перетекают анимированные плиты поля (TerrainTiles.draw_theme_tile).
# Материал — родителя (use_parent_material: вспышка попадания, броня ордена, подсветка края, ADD эффектов),
# цвет — родителя (modulate наследуется). additive — эффект с ADD-смешением: сумма кадров дала бы вспышку
# яркости, поэтому родитель гаснет на ту же долю (self_modulate дети не наследуют).
# Только вид: на бой не влияет. Выключается GameSettings.atmosphere (как цветокор и частицы)

# Только эффекты и снаряды (решение пользователя 20.10.2026): у бойцов, зданий и цитадели наложение
# следующего кадра мелькало — пиксели старого кадра пропадают скачком, а полупрозрачная постройка
# (OcclusionFader) пульсировала прозрачностью. max_fps — порог для быстрых анимаций (они и так плавные)
const MAX_FPS: float = 13.0

var _source: AnimatedSprite2D
var _additive := false
var _max_fps := INF

# Подключить к анимированному спрайту (повторный вызов — ничего не делает)
static func attach(source: AnimatedSprite2D, additive: bool = false, max_fps: float = INF) -> FrameBlend:
	for c in source.get_children():
		if c is FrameBlend:
			return c
	var b := FrameBlend.new()
	b._source = source
	b._additive = additive
	b._max_fps = max_fps
	b.use_parent_material = true
	b.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	b.show_behind_parent = false
	b.visible = false
	source.add_child(b)
	return b

func _process(_delta: float) -> void:
	var src := _source
	var frames := src.sprite_frames
	if frames == null or not src.is_playing() or not _enabled():
		_hide()
		return
	var anim := src.animation
	var count := frames.get_frame_count(anim)
	if frames.get_animation_speed(anim) * absf(src.speed_scale) * Engine.time_scale > _max_fps:
		_hide()   # быстрая анимация и так плавная
		return
	if count < 2:   # один кадр (стойка цитадели) — перетекать не во что
		_hide()
		return
	var next := src.frame + 1
	if next >= count:
		if not frames.get_animation_loop(anim):
			_hide()   # последний кадр разовой анимации — дальше не во что перетекать
			return
		next = 0
	var t: float = clampf(src.frame_progress, 0.0, 1.0)
	texture = frames.get_frame_texture(anim, next)
	centered = src.centered
	offset = src.offset
	flip_h = src.flip_h
	flip_v = src.flip_v
	self_modulate.a = t
	visible = true
	if _additive:
		src.self_modulate.a = 1.0 - t

func _hide() -> void:
	visible = false
	if _additive:
		_source.self_modulate.a = 1.0

# Автолоад — из дерева: FrameBlend компилируется и из скриптов -s (через Vfx) раньше автолоадов
static func _enabled() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var gs = tree.root.get_node_or_null("GameSettings") if tree else null
	return gs == null or gs.atmosphere
