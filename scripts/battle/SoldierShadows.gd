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
# Тень прыгающего бойца (Assault) в верхней точке дуги: на столько меньше и бледнее (Soldier._leap_prev / _leap_t)
const CONTACT_WIDTH: float = 11.0    # px мира × sprite_scale
const CONTACT_FLATTEN: float = 0.45
const CONTACT_ALPHA: float = 0.55
const JUMP_SHADOW_SHRINK: float = 0.35
const JUMP_SHADOW_FADE: float = 0.5

var units: Node2D                          # контейнер отрядов (BattleScene.units_container)
var _fire: MultiMeshInstance2D = null
var _t: float = 0.0
var _fire_count: int = 0   # из них тени от огня (в том же MultiMesh лежат и отброшенные тени — fire_shadow_count)
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

# Данные экземпляров пишутся в массив и уходят в MultiMesh одним присваиванием buffer (оптимизация 14.11.2026:
# по 2 вызова set_instance_* на тень × 2 тени × 300 бойцов — 1.2 мс кадра; вызов сервера отрисовки на каждую
# тень дороже записи 12 чисел). Формат экземпляра (TRANSFORM_2D + цвет), 12 чисел:
# [x.x, y.x, 0, origin.x,  x.y, y.y, 0, origin.y,  r, g, b, a]
const STRIDE: int = 12
var _buf := PackedFloat32Array()
var _fbuf := PackedFloat32Array()

func _process(delta: float) -> void:
	if units == null:
		return
	_t += delta
	var cast_dir: Vector2 = WorldLight.param("shadow_dir")
	var cast_len: float = Soldier.TARGET_SPRITE_HEIGHT * float(WorldLight.param("unit_cast_length"))
	var cast_width := float(WorldLight.param("unit_cast_width"))
	var cast_alpha := float(WorldLight.param("unit_cast_alpha"))
	var fires := IsoGridRenderer.fire_sources()
	var has_fires := not fires.is_empty()
	var mm := multimesh
	var fm := _fire.multimesh
	var xf := global_transform.affine_inverse()
	# отброшенная тень: поворот и сдвиг центра одинаковы у всех — считаются раз за кадр
	var cast_cos := cos(cast_dir.angle())
	var cast_sin := sin(cast_dir.angle())
	var cast_half: Vector2 = xf.basis_xform(cast_dir) * 0.5
	var ring_k: float = Soldier.SHADOW_RADIUS * Soldier.SHADOW_SOFT_SCALE * 2.0
	var flat: float = Soldier.SHADOW_FLATTEN
	var tick_alpha := BattleManager.get_tick_alpha()
	if _buf.size() != mm.instance_count * STRIDE:
		_buf.resize(mm.instance_count * STRIDE)
	if _fbuf.size() != fm.instance_count * STRIDE:
		_fbuf.resize(fm.instance_count * STRIDE)
	var buf := _buf
	var fbuf := _fbuf
	var n := 0
	var nf := 0
	_fire_count = 0
	for squad in units.get_children():
		if not (squad is Squad) or not squad.is_visible_in_tree():
			continue   # враги скрыты до боя — и их тени
		var ring := Color(Palette.PLAYER_SIDE if squad.team == GameConstants.TEAM_PLAYER else Palette.ENEMY_SIDE)
		var fade: float = squad.modulate.a
		if not BattleManager.is_battle_running():
			ring.a = 0.0   # на расстановке жёлтого кольца под отрядами нет (решение пользователя 18.11.2026); в бою оно показывает сторону
		ring.a *= fade   # отряд проявляется (выход врагов на «В БОЙ») — тень и кольцо вместе с ним
		var shadow_a := cast_alpha * fade
		for s in squad.soldiers:
			if not is_instance_valid(s) or s.current_state == Soldier.State.DEAD or s.data == null:
				continue
			var gp: Vector2 = s.global_position + Vector2(0.0, Soldier.GROUND_SINK)   # тень и кольцо — под втопленными ступнями
			var pos: Vector2 = xf * gp
			var k: float = s.data.sprite_scale
			# отброшенная тень бойца от общего света поля (WorldLight): вытянутый эллипс от ног вдоль shadow_dir
			if (nf + 1) * STRIDE > fbuf.size():
				fbuf.resize(fbuf.size() * 2)
			# в прыжке (Assault) спрайт над землёй: тень меньше и бледнее, чем выше — тем сильнее
			var lift := 0.0
			if s._leap_prev < 1.0:
				lift = sin(PI * lerpf(s._leap_prev, s._leap_t, tick_alpha))
			var length := cast_len * k * (1.0 - JUMP_SHADOW_SHRINK * lift)
			var w := cast_width * k * (1.0 - JUMP_SHADOW_SHRINK * lift)
			var o := nf * STRIDE
			fbuf[o] = cast_cos * length
			fbuf[o + 1] = -cast_sin * w
			fbuf[o + 2] = 0.0
			fbuf[o + 3] = pos.x + cast_half.x * length
			fbuf[o + 4] = cast_sin * length
			fbuf[o + 5] = cast_cos * w
			fbuf[o + 6] = 0.0
			fbuf[o + 7] = pos.y + cast_half.y * length
			fbuf[o + 8] = 1.0
			fbuf[o + 9] = 1.0
			fbuf[o + 10] = 1.0
			fbuf[o + 11] = shadow_a * (1.0 - JUMP_SHADOW_FADE * lift)
			nf += 1
			# контактная тень (18.11.2026): тугое тёмное пятно прямо под подошвами — модель «стоит» на земле
			if (nf + 1) * STRIDE > fbuf.size():
				fbuf.resize(fbuf.size() * 2)
			var cd: float = CONTACT_WIDTH * k
			o = nf * STRIDE
			fbuf[o] = cd
			fbuf[o + 1] = 0.0
			fbuf[o + 2] = 0.0
			fbuf[o + 3] = pos.x
			fbuf[o + 4] = 0.0
			fbuf[o + 5] = cd * CONTACT_FLATTEN
			fbuf[o + 6] = 0.0
			fbuf[o + 7] = pos.y
			fbuf[o + 8] = 1.0
			fbuf[o + 9] = 1.0
			fbuf[o + 10] = 1.0
			fbuf[o + 11] = CONTACT_ALPHA * fade * (1.0 - JUMP_SHADOW_FADE * lift)
			nf += 1
			if s.data.special_kind != "":
				continue   # примарх: своя большая тень и кольцо с рунами (BossFx.ground)
			if (n + 1) * STRIDE > buf.size():
				buf.resize(buf.size() * 2)
			var d: float = ring_k * k * (1.0 - Soldier.STEP_SHADOW_SHRINK * float(s.step_lift))   # шаг: на ступне шире, к середине шага уже
			o = n * STRIDE
			buf[o] = d
			buf[o + 1] = 0.0
			buf[o + 2] = 0.0
			buf[o + 3] = pos.x
			buf[o + 4] = 0.0
			buf[o + 5] = d * flat
			buf[o + 6] = 0.0
			buf[o + 7] = pos.y + Soldier.SHADOW_DROP * k
			buf[o + 8] = ring.r
			buf[o + 9] = ring.g
			buf[o + 10] = ring.b
			buf[o + 11] = ring.a * (1.0 - Soldier.STEP_SHADOW_FADE * float(s.step_lift))
			n += 1
			if has_fires:
				for f in fires:
					# грубо отсечь далёких без вызова и sqrt: пар боец × огонь — сотни
					var r: float = f[1]
					var away: Vector2 = gp - f[0]
					if absf(away.x) >= r or absf(away.y) * 2.0 >= r:
						continue
					if (nf + 1) * STRIDE > fbuf.size():
						fbuf.resize(fbuf.size() * 2)
					if _write_fire_shadow(fbuf, nf, away, r, f[2], k, pos, xf):
						nf += 1
						_fire_count += 1
	_buf = buf
	_fbuf = fbuf
	_flush(mm, buf, n)
	_flush(fm, fbuf, nf)

# Массив — в MultiMesh: мест меньше, чем в массиве, — расширить (instance_count сбрасывает данные — их пишем заново)
func _flush(mm: MultiMesh, buf: PackedFloat32Array, count: int) -> void:
	if mm.instance_count * STRIDE != buf.size():
		mm.visible_instance_count = -1
		mm.instance_count = buf.size() / STRIDE
	mm.buffer = buf
	mm.visible_instance_count = count

# Тень от огня (away — от огня к бойцу, r — радиус, phase — фаза пламени): вытянутый эллипс от ног прочь от огня.
# false — боец вне круга огня, ничего не записано
func _write_fire_shadow(fbuf: PackedFloat32Array, nf: int, away: Vector2, r: float, phase: float, k: float,
		pos: Vector2, xf: Transform2D) -> bool:
	var dist := Vector2(away.x, away.y * 2.0).length()   # расстояние по земле (изометрия 2:1)
	if dist >= r or dist < 2.0:
		return false
	var u := dist / r
	var flicker := IsoGridRenderer.fire_flicker(_t, phase)
	var jitter := 1.0 + FIRE_SHADOW_JITTER * (flicker - 1.0) / IsoGridRenderer.GLOW_FLICKER
	var length := lerpf(FIRE_SHADOW_LEN.x, FIRE_SHADOW_LEN.y, u) * k * jitter
	var dir := away.normalized()
	var center := pos + xf.basis_xform(dir) * length * 0.5
	var w := FIRE_SHADOW_WIDTH * k
	var o := nf * STRIDE
	fbuf[o] = dir.x * length
	fbuf[o + 1] = -dir.y * w
	fbuf[o + 2] = 0.0
	fbuf[o + 3] = center.x
	fbuf[o + 4] = dir.y * length
	fbuf[o + 5] = dir.x * w
	fbuf[o + 6] = 0.0
	fbuf[o + 7] = center.y
	fbuf[o + 8] = 1.0
	fbuf[o + 9] = 1.0
	fbuf[o + 10] = 1.0
	fbuf[o + 11] = minf(FIRE_SHADOW_ALPHA * (1.0 - u * 0.7) * flicker, 1.0)
	return true

# Сколько теней от огня сейчас рисуется (тесты)
func fire_shadow_count() -> int:
	return _fire_count if _fire else 0

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
