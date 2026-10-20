class_name SoldierShadows
extends MultiMeshInstance2D

# Тени и кольца стороны под всеми бойцами — один MultiMesh, один вызов отрисовки (только вид).
# Раньше каждый боец рисовал их в своём _draw примитивами без текстуры: бойцы отсортированы по глубине и
# перемежаются, поэтому пакет рвался на каждом — «примитивы → спрайт → примитивы…», ~600 лишних вызовов
# на 300 бойцов (21.10.2026: FPS 105 → 146 в test_performance). Слой — под отрядами (тень лежит на земле).
# Кольцо белое в текстуре, цвет стороны — цвет экземпляра (тень чёрная — от умножения не меняется).

const TEXTURE_SIZE := Vector2i(128, 64)   # эллипс 2:1 — как Soldier.SHADOW_FLATTEN
const START_CAPACITY: int = 256

var units: Node2D                          # контейнер отрядов (BattleScene.units_container)
static var _texture: Texture2D

func setup(units_container: Node2D) -> void:
	units = units_container
	texture = _get_texture()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = START_CAPACITY
	mm.visible_instance_count = 0
	multimesh = mm

func _process(_delta: float) -> void:
	if units == null:
		return
	var mm := multimesh
	var to_local_xf := global_transform.affine_inverse()
	var n := 0
	for squad in units.get_children():
		if not (squad is Squad) or not squad.is_visible_in_tree():
			continue   # враги скрыты до боя — и их тени
		var ring := Color(Palette.PLAYER_SIDE if squad.team == GameConstants.TEAM_PLAYER else Palette.ENEMY_SIDE)
		for s in squad.soldiers:
			if not is_instance_valid(s) or s.current_state == Soldier.State.DEAD or s.data == null:
				continue
			if n >= mm.instance_count:
				_grow()
				mm = multimesh
			var d: float = Soldier.SHADOW_RADIUS * s.data.sprite_scale * Soldier.SHADOW_SOFT_SCALE * 2.0
			var pos: Vector2 = to_local_xf * s.global_position
			mm.set_instance_transform_2d(n, Transform2D(0.0, Vector2(d, d * Soldier.SHADOW_FLATTEN), 0.0, pos))
			mm.set_instance_color(n, ring)
			n += 1
	mm.visible_instance_count = n

# Бойцов больше, чем мест: instance_count сбрасывает данные — их всё равно пишем заново каждый кадр
func _grow() -> void:
	var mm := multimesh
	var count := mm.instance_count * 2
	mm.visible_instance_count = -1
	mm.instance_count = count
	mm.visible_instance_count = 0

# Текстура: мягкий край, ядро тени, кольцо (белое) на радиусе тени — пропорции Soldier.SHADOW_*
static func _get_texture() -> Texture2D:
	if _texture:
		return _texture
	var img := Image.create(TEXTURE_SIZE.x, TEXTURE_SIZE.y, false, Image.FORMAT_RGBA8)
	var half := Vector2(TEXTURE_SIZE) / 2.0
	var core := 1.0 / Soldier.SHADOW_SOFT_SCALE   # радиус тени в долях мягкого края
	var ring_w := Soldier.RING_WIDTH / (Soldier.SHADOW_RADIUS * Soldier.SHADOW_SOFT_SCALE)
	for y in TEXTURE_SIZE.y:
		for x in TEXTURE_SIZE.x:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5) - half) / half
			var r := p.length()   # 0 — центр, 1 — край мягкой тени
			var c := Color(0, 0, 0, 0)
			if r <= 1.0:
				c = Color(0, 0, 0, Soldier.SHADOW_SOFT.a)
			if r <= core:
				var a := Soldier.SHADOW_SOFT.a + Soldier.SHADOW_COLOR.a * (1.0 - Soldier.SHADOW_SOFT.a)
				c = Color(0, 0, 0, a)
			var ring := 1.0 - clampf(absf(r - core) / ring_w, 0.0, 1.0)
			if ring > 0.0:
				c = c.lerp(Color(1, 1, 1, Soldier.RING_ALPHA), ring)
			img.set_pixel(x, y, c)
	_texture = ImageTexture.create_from_image(img)
	return _texture
