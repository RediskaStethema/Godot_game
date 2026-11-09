class_name SoldierShadows
extends MultiMeshInstance2D

# Тени и кольца стороны под всеми бойцами — один MultiMesh, один вызов отрисовки (только вид).
# Раньше каждый боец рисовал их в своём _draw примитивами без текстуры: бойцы отсортированы по глубине и
# перемежаются, поэтому пакет рвался на каждом — «примитивы → спрайт → примитивы…», ~600 лишних вызовов
# на 300 бойцов (21.10.2026: FPS 105 → 146 в test_performance). Слой — под отрядами (тень лежит на земле).
# Кольцо белое в текстуре, цвет стороны — цвет экземпляра (тень чёрная — от умножения не меняется).

const TEXTURE_SIZE := Vector2i(128, 64)   # эллипс 2:1 — как Soldier.SHADOW_FLATTEN
const START_CAPACITY: int = 256
# Тени от огня (решение пользователя 09.11.2026): у бойца ближе радиуса костра / жаровни — вытянутая тень прочь
# от огня, длиннее дальше от него, бледнеет к краю радиуса и дрожит с пламенем; второй MultiMesh — один вызов
const FIRE_SHADOW_ALPHA: float = 1.0   # грунт тёмный и в отсвете костра: 0.55–0.8 почти не читались (снимки 09.11.2026)
const FIRE_SHADOW_LEN = Vector2(20.0, 38.0)   # px мира × sprite_scale: у огня — короче, на краю радиуса — длиннее
const FIRE_SHADOW_WIDTH: float = 7.0          # px мира × sprite_scale
const FIRE_SHADOW_JITTER: float = 0.12        # доля длины — дрожь с пламенем

var units: Node2D                          # контейнер отрядов (BattleScene.units_container)
var _fire: MultiMeshInstance2D = null
var _t: float = 0.0
static var _texture: Texture2D
static var _fire_texture: Texture2D

func setup(units_container: Node2D) -> void:
	units = units_container
	# Позиции — после Soldier._process (плавный ход между тиками): слой стоит в дереве раньше отрядов, и в кадр
	# тика брал логическую позицию на шаг впереди — кольцо скакало вперёд-назад 10 раз/с (23.10.2026)
	process_priority = 1
	# Текстура 128 px сжата до ~17: без мип-уровней тонкое кольцо рябило при сдвиге на доли пикселя
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	_fire = MultiMeshInstance2D.new()
	_fire.name = "FireShadows"
	# не show_behind_parent: с ним слой уходил под грунт и тени не было видно (снимок 09.11.2026)
	_fire.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_fire.texture = _get_fire_texture()
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_2D
	fm.use_colors = true
	var fq := QuadMesh.new()
	fq.size = Vector2.ONE
	fm.mesh = fq
	fm.instance_count = 64
	fm.visible_instance_count = 0
	_fire.multimesh = fm
	add_child(_fire)

func _process(delta: float) -> void:
	if units == null:
		return
	_t += delta
	var fires := IsoGridRenderer.fire_sources()
	var mm := multimesh
	var to_local_xf := global_transform.affine_inverse()
	var n := 0
	var nf := 0
	for squad in units.get_children():
		if not (squad is Squad) or not squad.is_visible_in_tree():
			continue   # враги скрыты до боя — и их тени
		var ring := Color(Palette.PLAYER_SIDE if squad.team == GameConstants.TEAM_PLAYER else Palette.ENEMY_SIDE)
		for s in squad.soldiers:
			if not is_instance_valid(s) or s.current_state == Soldier.State.DEAD or s.data == null:
				continue
			if s.data.special_kind != "":
				continue   # примарх: своя большая тень и кольцо с рунами (BossFx.ground)
			if n >= mm.instance_count:
				_grow()
				mm = multimesh
			var d: float = Soldier.SHADOW_RADIUS * s.data.sprite_scale * Soldier.SHADOW_SOFT_SCALE * 2.0
			var pos: Vector2 = to_local_xf * s.global_position
			mm.set_instance_transform_2d(n, Transform2D(0.0, Vector2(d, d * Soldier.SHADOW_FLATTEN), 0.0, pos))
			mm.set_instance_color(n, ring)
			n += 1
			for f in fires:
				nf = _add_fire_shadow(nf, s, f, pos, to_local_xf)
	mm.visible_instance_count = n
	if _fire:
		_fire.multimesh.visible_instance_count = nf

# Тень бойца s от огня f [точка, радиус, фаза]: вытянутый эллипс от ног прочь от огня
func _add_fire_shadow(nf: int, s: Soldier, f: Array, pos: Vector2, xf: Transform2D) -> int:
	if _fire == null:
		return nf
	var away: Vector2 = s.global_position - f[0]
	var r: float = f[1]
	if absf(away.x) >= r or absf(away.y) * 2.0 >= r:   # грубо отсечь далёких без sqrt: пар боец × огонь — сотни
		return nf
	var dist := Vector2(away.x, away.y * 2.0).length()   # расстояние по земле (изометрия 2:1)
	if dist >= r or dist < 2.0:
		return nf
	var fm := _fire.multimesh
	if nf >= fm.instance_count:   # данные сбрасываются — их всё равно пишем заново каждый кадр
		fm.visible_instance_count = -1
		fm.instance_count = fm.instance_count * 2
		fm.visible_instance_count = 0
	var u := dist / r
	var flicker := IsoGridRenderer.fire_flicker(_t, f[2])
	var k: float = s.data.sprite_scale
	var jitter := 1.0 + FIRE_SHADOW_JITTER * (flicker - 1.0) / IsoGridRenderer.GLOW_FLICKER
	var length := lerpf(FIRE_SHADOW_LEN.x, FIRE_SHADOW_LEN.y, u) * k * jitter
	var dir := away.normalized()
	var center := pos + xf.basis_xform(dir) * length * 0.5
	fm.set_instance_transform_2d(nf, Transform2D(dir.angle(), Vector2(length, FIRE_SHADOW_WIDTH * k), 0.0, center))
	fm.set_instance_color(nf, Color(1, 1, 1, minf(FIRE_SHADOW_ALPHA * (1.0 - u * 0.7) * flicker, 1.0)))
	return nf + 1

# Сколько теней от огня сейчас рисуется (тесты)
func fire_shadow_count() -> int:
	return _fire.multimesh.visible_instance_count if _fire else 0

# Бойцов больше, чем мест: instance_count сбрасывает данные — их всё равно пишем заново каждый кадр
func _grow() -> void:
	var mm := multimesh
	var count := mm.instance_count * 2
	mm.visible_instance_count = -1
	mm.instance_count = count
	mm.visible_instance_count = 0

# Текстура тени от огня: мягкий чёрный эллипс без кольца, у ног (левый край) плотнее
static func _get_fire_texture() -> Texture2D:
	if _fire_texture:
		return _fire_texture
	var size := Vector2i(64, 32)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var half := Vector2(size) / 2.0
	for y in size.y:
		for x in size.x:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5) - half) / half
			var fall := clampf(1.05 - (p.x + 1.0) * 0.4, 0.15, 0.95)   # у ног плотная, к дальнему концу тает
			img.set_pixel(x, y, Color(0, 0, 0, (1.0 - smoothstep(0.45, 1.0, p.length())) * fall))
	img.generate_mipmaps()
	_fire_texture = ImageTexture.create_from_image(img)
	return _fire_texture

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
	img.generate_mipmaps()
	_texture = ImageTexture.create_from_image(img)
	return _texture
