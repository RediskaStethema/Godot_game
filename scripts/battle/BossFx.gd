class_name BossFx
extends Node2D

# Подача финальных боссов-примархов кодом (решение пользователя 09.11.2026: «импакт и объём» — выход, предупреждение
# о приёме, ударная волна и трещины, тень и кольцо, смерть; без подсветки края, ауры частиц и полосы HP). Только вид:
# на бой не влияет, своя случайность (общий randf боя не сдвигается), время дерева — стоп-кадр и замедление
# тормозят и эти эффекты. Слой — земля поля (AuraRing.layer, ставит BattleScene._build_field): под бойцами.
#   ground(босс)                       — большая тень и кольцо с рунами цвета босса, идёт за ним; ярость — пульс
#   telegraph(босс, вид, из, в, радиус, время) — метка зоны приёма на время замаха, заливка доходит до края к удару
#   shockwave(точка, радиус, цвет)     — кольцо ударной волны по земле
#   cracks(точка, размер, жизнь, цвет) — трещины с тлеющей кромкой, гаснут
#   title(сцена, имя, подпись, цвет)   — титр поверх поля (выход, смерть), по реальному времени
#   cloud(точка, ось, полуугол, радиус, цвет) — облако по сектору конуса (Мортарион, 4.12, 09.11.2026): мягкие клубы
#     дрейфуют от босса и тают
#   furrow(из, в, цвет)                — борозда рывка (Русс, 4.12, 09.11.2026): трещины вдоль пути, тлеют и гаснут

enum Kind { GROUND, TELEGRAPH, SHOCKWAVE, CRACKS, CLOUD }

# Тень и кольцо
const SHADOW_W: float = 0.95        # полуширина тени — доля роста фигуры на экране (TARGET × sprite_scale)
const SHADOW_LAYERS = [[1.0, 0.10], [0.78, 0.12], [0.55, 0.16], [0.32, 0.22]]   # доля радиуса, прозрачность
const CONTACT_W: float = 0.3        # плотное пятно у ног
const RING_W: float = 0.62          # кольцо — доля роста
const RUNES: int = 12
const RUNE_PERIOD: float = 24.0     # оборот рун, сек
const RAGE_PULSE: float = 5.0       # 1/с — пульс кольца в ярости
# Метка приёма
const TELEGRAPH_FADE: float = 0.15
const TELEGRAPH_PULSE: float = 9.0
const TELEGRAPH_EDGE: float = 2.5     # кромка метки, px мира: на общем плане боя 1.5 терялась (снимок 09.11.2026)
const TELEGRAPH_GLOW: float = 7.0
const TITLE_TOP: float = 84.0          # титр — ниже плашки сообщения шапки (налезал на «Построение…»)
# Ударная волна
const WAVE_TIME: float = 0.45
const WAVE_FROM: float = 0.2
const WAVE_TO: float = 1.3
# Трещины
const CRACK_COUNT = Vector2i(5, 8)
# Облако конуса
const CLOUD_TIME: float = 2.6
const CLOUD_PUFFS: int = 16
const CLOUD_ALPHA: float = 0.32     # клубы приглушённые: яркие читались светящимися лужами (как пыль стены)
const CLOUD_DRIFT: float = 0.25     # доля радиуса — клубы отползают от босса за жизнь
const CLOUD_MUTE: float = 0.45      # цвет приёма → пыль поля (чистый ядовитый зелёный выбивался)
const CLOUD_LAYERS = [[1.3, 0.18], [1.0, 0.3], [0.7, 0.45], [0.4, 0.6]]   # доля радиуса, доля прозрачности
# Борозда рывка
const FURROW_TIME: float = 2.0
# Титр
const TITLE_IN: float = 0.35
const TITLE_HOLD: float = 1.5
const TITLE_OUT: float = 0.6
const TITLE_SIZE: int = 40
const SUBTITLE_SIZE: int = 18

static var _add: CanvasItemMaterial
static var _rng := RandomNumberGenerator.new()

var kind: Kind = Kind.GROUND
var color: Color = Palette.FIRE
var radius: float = 60.0
var life: float = 1.0
var _t: float = 0.0
# ground
var boss: Node2D = null
var enraged: bool = false
var _size: float = 40.0
# telegraph
var shape: String = "circle"      # circle / cone / line
var from_point: Vector2 = Vector2.ZERO
var to_point: Vector2 = Vector2.ZERO
var follow: Node2D = null         # bolt: метка едет за целью
var _released: float = -1.0
# cracks
var _lines: Array = []            # [PackedVector2Array]

static func _layer() -> Node2D:
	return AuraRing.layer if is_instance_valid(AuraRing.layer) else null

static func _make(k: Kind, add: bool) -> BossFx:
	var parent := _layer()
	if parent == null:
		return null
	var n := BossFx.new()
	n.kind = k
	if add:
		if _add == null:
			_add = CanvasItemMaterial.new()
			_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		n.material = _add
	n.process_priority = 1   # после хода бойцов (как SoldierShadows): за боссом без скачка
	parent.add_child(n)
	return n

static func ground(soldier: Node2D) -> BossFx:
	var n := _make(Kind.GROUND, false)
	if n:
		n.boss = soldier
		n.color = soldier.data.special_color
		n._size = Soldier.TARGET_SPRITE_HEIGHT * soldier.data.sprite_scale
		n.global_position = soldier.global_position
	return n

# Зона приёма: вид Soldier.special_kind; from — босс, to — точка удара (прыжок, рывок), follow — цель снаряда
static func telegraph(soldier: Node2D, special_kind: String, from: Vector2, to: Vector2, r: float, time: float,
		target: Node2D = null) -> BossFx:
	var n := _make(Kind.TELEGRAPH, true)
	if n == null:
		return null
	n.color = Palette.ENEMY_SIDE.lerp(soldier.data.special_color, 0.35)
	n.radius = r
	n.life = maxf(time, 0.05)
	n.from_point = from
	n.to_point = to
	match special_kind:
		"cone":
			n.shape = "cone"
			n.global_position = from
		"dash":
			n.shape = "line"
			n.global_position = from
		"bolt":
			n.follow = target
			n.global_position = target.global_position if is_instance_valid(target) else to
		"leap":
			n.global_position = to
		_:
			n.global_position = from
	return n

func release() -> void:
	if _released < 0.0:
		_released = TELEGRAPH_FADE

static func shockwave(point: Vector2, r: float, col: Color) -> BossFx:
	var n := _make(Kind.SHOCKWAVE, true)
	if n:
		n.global_position = point
		n.radius = r
		n.color = col
		n.life = WAVE_TIME
		DustLayer.puff(point, r * 0.35, 6, r * 0.25)
	return n

static func cracks(point: Vector2, size: float, time: float, col: Color) -> BossFx:
	var n := _make(Kind.CRACKS, false)
	if n == null:
		return null
	n.global_position = point
	n.radius = size
	n.life = time
	n.color = col
	for i in _rng.randi_range(CRACK_COUNT.x, CRACK_COUNT.y):
		var a := _rng.randf() * TAU
		var p := Vector2.ZERO
		var line := PackedVector2Array([p])
		var steps := _rng.randi_range(3, 5)
		var length := size * _rng.randf_range(0.5, 1.0)
		for s in steps:
			a += _rng.randf_range(-0.6, 0.6)
			p += Vector2.from_angle(a) * length / steps
			line.append(Vector2(p.x, p.y * 0.5))   # по земле: сплюснуто 2:1, как клетка изометрии
		n._lines.append(line)
	return n

static func cloud(point: Vector2, axis: Vector2, half: float, r: float, col: Color) -> BossFx:
	var n := _make(Kind.CLOUD, false)
	if n == null:
		return null
	n.global_position = point
	n.radius = r
	n.life = CLOUD_TIME
	n.color = col
	var base := axis.angle()
	for i in CLOUD_PUFFS:
		var ang := base + _rng.randf_range(-half, half) * 0.9
		var dist := r * sqrt(_rng.randf_range(0.08, 1.0))   # ровнее по площади сектора
		n._lines.append({"dir": Vector2.from_angle(ang), "dist": dist, "size": r * _rng.randf_range(0.14, 0.26),
			"phase": _rng.randf() * TAU, "delay": dist / r * 0.25})
	return n

static func furrow(from: Vector2, to: Vector2, col: Color) -> BossFx:
	var n := _make(Kind.CRACKS, false)
	if n == null:
		return null
	n.global_position = from
	n.life = FURROW_TIME
	n.color = col
	var v := to - from
	var side := v.orthogonal().normalized()
	for lane: float in [-1.0, 1.0]:   # две борозды по краям пути, мелкие трещины в стороны
		var line := PackedVector2Array()
		var steps := maxi(int(v.length() / 14.0), 3)
		for j in steps + 1:
			var u := float(j) / steps
			line.append(v * u + side * lane * (5.0 + _rng.randf_range(-1.5, 1.5)))
		n._lines.append(line)
		for j in steps / 2:
			var at: Vector2 = line[_rng.randi_range(0, line.size() - 1)]
			var off := side * lane * _rng.randf_range(5.0, 11.0) + v.normalized() * _rng.randf_range(-6.0, 6.0)
			n._lines.append(PackedVector2Array([at, at + Vector2(off.x, off.y * 0.5)]))
	return n

# Титр поверх поля: имя крупно, подпись, линия цвета босса; въезд, держится, тает — по реальному времени
static func title(scene: Node, name_text: String, subtitle: String, col: Color) -> CanvasLayer:
	if scene == null or not scene.is_inside_tree():
		return null
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.name = "BossTitle"
	scene.add_child(layer)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.offset_top = UITheme.HUD_HEIGHT + TITLE_TOP
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.modulate.a = 0.0
	layer.add_child(box)
	for part in [[name_text, TITLE_SIZE, col.lerp(Color.WHITE, 0.35)], [subtitle, SUBTITLE_SIZE, Palette.DUST_PALE]]:
		if part[0] == "":
			continue
		var l := Label.new()
		l.text = part[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", load(UITheme.FONT_UI_BOLD))
		l.add_theme_font_size_override("font_size", part[1])
		l.add_theme_color_override("font_color", part[2])
		l.add_theme_color_override("font_outline_color", Palette.OUTLINE)
		l.add_theme_constant_override("outline_size", 6)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
		if part[1] == TITLE_SIZE:
			var rule := ColorRect.new()
			rule.color = Color(col, 0.8)
			rule.custom_minimum_size = Vector2(320, 2)
			rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(rule)
	var tw := layer.create_tween().set_ignore_time_scale(true)
	tw.tween_property(box, "modulate:a", 1.0, TITLE_IN)
	tw.parallel().tween_property(box, "offset_top", box.offset_top - 14.0, TITLE_IN + TITLE_HOLD)
	tw.tween_interval(maxf(TITLE_HOLD - TITLE_IN, 0.0))
	tw.tween_property(box, "modulate:a", 0.0, TITLE_OUT)
	tw.tween_callback(layer.queue_free)
	return layer

func _process(delta: float) -> void:
	_t += delta
	match kind:
		Kind.GROUND:
			if not is_instance_valid(boss) or boss.current_state == boss.State.DEAD:
				queue_free()
				return
			global_position = boss.global_position
		Kind.TELEGRAPH:
			if is_instance_valid(follow):
				global_position = follow.global_position
			if _released >= 0.0:
				_released -= delta
				if _released <= 0.0:
					queue_free()
					return
			elif _t > life + 1.0:   # приём сорван без release — не висим
				queue_free()
				return
		_:
			if _t >= life:
				queue_free()
				return
	queue_redraw()

func _draw() -> void:
	match kind:
		Kind.GROUND: _draw_ground()
		Kind.TELEGRAPH: _draw_telegraph()
		Kind.SHOCKWAVE: _draw_shockwave()
		Kind.CRACKS: _draw_cracks()
		Kind.CLOUD: _draw_cloud()

func _ellipse(r: float, col: Color) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, r, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_ground() -> void:
	var w := _size * SHADOW_W
	for layer_def in SHADOW_LAYERS:
		_ellipse(w * layer_def[0], Color(0, 0, 0, layer_def[1]))
	_ellipse(_size * CONTACT_W, Color(0, 0, 0, 0.35))
	var pulse := 0.5 + 0.5 * sin(_t * RAGE_PULSE) if enraged else 0.0
	var a := 0.45 + 0.35 * pulse
	var r := _size * RING_W
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(color, 0.12 + 0.12 * pulse), 6.0)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(color, a), 1.5, true)
	draw_arc(Vector2.ZERO, r * 0.86, 0.0, TAU, 64, Color(color, a * 0.5), 1.0, true)
	var turn := _t / RUNE_PERIOD * TAU
	for i in RUNES:   # засечки-руны между двумя кругами, медленно идут по кругу
		var ang := turn + i * TAU / RUNES
		var d := Vector2.from_angle(ang)
		var t := Vector2(-d.y, d.x)
		var mid := d * r * 0.93
		var s := r * 0.05
		draw_line(mid - d * s, mid + d * s, Color(color, a), 1.5)
		if i % 3 == 0:
			draw_line(mid - t * s * 0.7, mid + t * s * 0.7, Color(color, a), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_telegraph() -> void:
	var fill := clampf(_t / life, 0.0, 1.0)
	var fade := 1.0 if _released < 0.0 else _released / TELEGRAPH_FADE
	var pulse := 0.75 + 0.25 * sin(_t * TELEGRAPH_PULSE)
	var edge := Color(color, 0.85 * pulse * fade)
	var body := Color(color, 0.2 * fade)
	var halo := Color(color, 0.18 * pulse * fade)
	var inner := Color(color, (0.18 + 0.22 * fill) * fade)
	match shape:
		"cone":
			var dir := (to_point - from_point).angle() if to_point != from_point else 0.0
			var half := Soldier.SPECIAL_CONE_HALF
			_sector(radius, dir, half, body)
			_sector(radius * fill, dir, half, inner)
			var pts := PackedVector2Array([Vector2.ZERO])
			for i in 17:
				pts.append(Vector2.from_angle(dir - half + half * 2.0 * i / 16.0) * radius)
			pts.append(Vector2.ZERO)
			draw_polyline(pts, halo, TELEGRAPH_GLOW)
			draw_polyline(pts, edge, TELEGRAPH_EDGE, true)
		"line":
			var v := to_point - from_point
			var n := Vector2(-v.y, v.x).normalized() * radius
			var rect := PackedVector2Array([n, v + n, v - n, -n])
			draw_colored_polygon(rect, body)
			var vf := v * fill
			draw_colored_polygon(PackedVector2Array([n, vf + n, vf - n, -n]), inner)
			rect.append(n)
			draw_polyline(rect, halo, TELEGRAPH_GLOW)
			draw_polyline(rect, edge, TELEGRAPH_EDGE, true)
		_:
			draw_circle(Vector2.ZERO, radius, body)
			draw_circle(Vector2.ZERO, radius * fill, inner)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, halo, TELEGRAPH_GLOW)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, edge, TELEGRAPH_EDGE, true)

func _sector(r: float, dir: float, half: float, col: Color) -> void:
	if r <= 1.0:
		return
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in 17:
		pts.append(Vector2.from_angle(dir - half + half * 2.0 * i / 16.0) * r)
	draw_colored_polygon(pts, col)

func _draw_shockwave() -> void:
	var k := clampf(_t / life, 0.0, 1.0)
	var r := radius * lerpf(WAVE_FROM, WAVE_TO, 1.0 - pow(1.0 - k, 2.0))
	var a := 1.0 - k
	# круг, как зона приёма и кольца аур (AuraRing): радиус — расстояние в px мира
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(color, 0.25 * a), 10.0 * (1.0 - k * 0.6))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(color.lerp(Color.WHITE, 0.4), 0.8 * a), 2.0, true)

func _draw_cracks() -> void:
	var a := 1.0 - clampf(_t / life, 0.0, 1.0)
	var glow := a * a
	for line in _lines:
		draw_polyline(line, Color(0, 0, 0, 0.6 * a), 2.0, true)
		draw_polyline(line, Color(color, 0.55 * glow), 1.0, true)

func _draw_cloud() -> void:
	var k := clampf(_t / life, 0.0, 1.0)
	for p in _lines:
		var t := clampf((_t - p["delay"]) / (life - p["delay"]), 0.0, 1.0)
		if t <= 0.0:
			continue
		var a := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.45, 1.0, t)) * CLOUD_ALPHA
		var dist: float = p["dist"] * (1.0 + CLOUD_DRIFT * k)
		var at: Vector2 = p["dir"] * dist
		at.y *= 0.5   # по земле
		at += Vector2(sin(_t * 1.3 + p["phase"]) * 2.0, -6.0 * k)   # колышется и чуть поднимается
		var r: float = p["size"] * (0.7 + 0.6 * k)
		# мягкий клуб: слои от широкого бледного к плотному ядру (один круг читался плоской яркой лужей),
		# цвет приёма приглушён к пыли поля
		var body := color.lerp(Palette.DUST, CLOUD_MUTE)
		draw_set_transform(at, 0.0, Vector2(1.0, 0.6))
		for layer_def in CLOUD_LAYERS:
			draw_circle(Vector2(-r * 0.1, -r * 0.15) * (1.0 - layer_def[0]), r * layer_def[0],
				Color(body, a * layer_def[1]), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)
