class_name BuildingGlow
extends Node2D

# Свечение зданий кодом (решение пользователя 21.11.2026: «добавь анимацию для зданий кодом — свечение и тому прочее»).
# Ребёнок AnimatedSprite2D здания: точки света находятся САМИ по кадру стойки уровня — яркие насыщенные пиксели
# (пламя свечей и факелов, лампы, глаза, варп-кристаллы, лава) собираются в пятна; на каждое — мягкое радиальное
# свечение ADD (цвет — средний цвет пятна), оно спокойно дышит (±FLICKER, у каждой точки своя фаза и темп),
# и на расстановке — как и стойка здания (Building.IDLE_ON_PLACEMENT); над самыми яркими точками изредка
# поднимается уголёк. Точки и кадры не хранятся в файлах: кэш в metadata листа («glow_<ряд>»), считается один раз.
# Только вид: на бой не влияет, своя случайность, выключается GameSettings.atmosphere.

const STEP: int = 2               # px — шаг просмотра кадра при поиске ярких пикселей
const MIN_V: float = 0.5          # нижний предел яркости света; порог кадра — ближе к его самым ярким (adaptive_v)
const TOP_SHARE: float = 0.9      # порог = эта доля от яркости 98-го перцентиля кадра (здания Хаоса приглушены — 0.7 и выше)
const MIN_S: float = 0.30         # насыщенность (белое и серое — не свет)
const CELL: int = 12              # px — размер ячейки накопления пятна
const MERGE_DIST: float = 16.0    # px — пятна ближе сливаются
const MAX_POINTS: int = 8
const MIN_WEIGHT: float = 6.0     # меньше — шум (одиночные блики)
const RADIUS_MIN: float = 9.0     # px кадра
const RADIUS_MAX: float = 36.0
const ALPHA: float = 0.34         # сила свечения в центре
const FLICKER: float = 0.12       # доля, на которую свет дышит в бою
const EMBER_CHANCE: float = 0.55  # уголька в секунду на самую яркую точку
const EMBER_LIFE: float = 1.3
const EMBER_RISE: float = 26.0    # px кадра в секунду вверх

# Ручные точки света (цитадели, решение пользователя 23.11.2026: «улучшить анимации огней, свечения, факелов у цитаделей»):
# автопоиск находил у цитадели Космодесанта одну жаровню из десятка огней — точки задаёт тема (`"lights"`:
# [вид, x, y] в px кадра). Вид задаёт характер: t — факел (быстрое неровное мерцание, языки пламени кодом, угольки),
# c — свеча (среднее), w — окно (медленное дыхание)
const KINDS := {
	"t": {"r": 14.0, "a": 0.40, "amp": 0.32, "sp": [5.0, 9.0], "col": Color(1.0, 0.62, 0.15)},
	"c": {"r": 8.0, "a": 0.30, "amp": 0.22, "sp": [3.0, 5.5], "col": Color(1.0, 0.76, 0.32)},
	"w": {"r": 6.5, "a": 0.24, "amp": 0.09, "sp": [0.8, 1.6], "col": Color(1.0, 0.70, 0.26)},
}
const FLAME_H: float = 8.0        # px кадра — высота языка пламени факела
const FLAME_OUTER := Color(1.0, 0.50, 0.12, 0.34)
const FLAME_CORE := Color(1.0, 0.86, 0.45, 0.42)

static var _tex: ImageTexture = null
static var _rng := RandomNumberGenerator.new()

var sprite: AnimatedSprite2D
var _row: String = ""
var _points: Array = []           # [{p: Vector2 (px кадра), r: float, c: Color, ph: float, sp: float}]
var _nodes: Array[Sprite2D] = []
var _embers: Array = []           # [{p: Vector2, age: float, c: Color}]
var _t: float = 0.0
var _custom: Array = []           # ручные точки (lights_from); пусто — автопоиск по кадру

static func attach(s: AnimatedSprite2D, lights: Array = []) -> BuildingGlow:
	var g := BuildingGlow.new()
	g.sprite = s
	g._custom = lights_from(lights)
	g.material = Vfx.soft_add_material()
	s.add_child(g)
	return g

# [[вид, x, y], …] → точки свечения (у каждой своя фаза и темп из диапазона вида)
static func lights_from(list: Array) -> Array:
	var out: Array = []
	for e in list:
		var kd: Dictionary = KINDS[str(e[0])]
		var sp: Array = kd["sp"]
		out.append({"p": Vector2(float(e[1]), float(e[2])), "r": kd["r"], "c": kd["col"], "ph": _rng.randf() * TAU,
			"sp": _rng.randf_range(sp[0], sp[1]), "w": 100.0, "kind": str(e[0])})
	return out

func _ready() -> void:
	z_index = 0
	_refresh(true)

func _process(delta: float) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var on := GameSettings.atmosphere and String(sprite.animation) != "fall"   # обрушенная цитадель не светится
	visible = on
	if not on:
		return
	_refresh(false)
	var fighting := true   # дышит и на расстановке (стойка здания играет всегда)
	_t += delta
	var size := _frame_size()
	for i in _nodes.size():
		var pt: Dictionary = _points[i]
		var n := _nodes[i]
		var p: Vector2 = pt["p"]
		var x := (size.x - p.x) if sprite.flip_h else p.x
		n.position = sprite.offset + Vector2(x, p.y)
		var k := 1.0
		var alpha := ALPHA
		var amp := FLICKER
		var kind: String = pt.get("kind", "")
		if kind != "":
			# ручные точки: неровное мерцание — три несоизмеримых синуса, амплитуда и темп по виду света
			var kd: Dictionary = KINDS[kind]
			alpha = kd["a"]
			amp = kd["amp"]
			k = 1.0 + amp * (0.5 * sin(_t * pt["sp"] + pt["ph"]) + 0.3 * sin(_t * pt["sp"] * 1.9 + pt["ph"] * 2.3)
				+ 0.2 * sin(_t * pt["sp"] * 3.7 + pt["ph"] * 0.7))
		elif fighting:
			k = 1.0 + FLICKER * (0.65 * sin(_t * pt["sp"] + pt["ph"]) + 0.35 * sin(_t * pt["sp"] * 2.3 + pt["ph"] * 1.7))
		n.modulate = Color(pt["c"], alpha * k)
		n.scale = Vector2.ONE * (float(pt["r"]) / 32.0) * (1.0 + 0.04 * (k - 1.0) / maxf(amp, 0.01))
	_tick_embers(delta, fighting, size)

# Ряд стойки уровня сменился (улучшили здание) — точки заново: другой рисунок
func _refresh(force: bool) -> void:
	var anim := String(sprite.animation)
	if not _custom.is_empty():   # ручные точки — один раз, от ряда не зависят
		if _nodes.is_empty():
			_points = _custom
			_build_nodes()
		return
	if not anim.begins_with("idle"):
		return
	if not force and anim == _row:
		return
	_row = anim
	# Ручные огни по уровням (24.11.2026, Пирамида Редута): metadata/level_lights {уровень: [[вид, x, y], …]} — у каждого уровня
	# свой рисунок, огни окон / жаровен лежат по-разному; нет записи уровня — автопоиск
	var by_level: Dictionary = sprite.sprite_frames.get_meta("level_lights", {})
	var parts := anim.rsplit("_", true, 1)
	var level := parts[1].to_int() if parts.size() == 2 and parts[1].is_valid_int() else 1
	if by_level.has(level):
		_points = lights_from(by_level[level])
	else:
		_points = points_for(sprite.sprite_frames, anim)
	_build_nodes()

func _build_nodes() -> void:
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	for pt in _points:
		var n := Sprite2D.new()
		n.texture = _glow_texture()
		n.centered = true
		n.use_parent_material = true   # ADD-материал узла
		add_child(n)
		_nodes.append(n)

func _frame_size() -> Vector2:
	return Vector2(sprite.sprite_frames.get_frame_texture("idle", 0).get_size())

# Точки света кадра 0 ряда (кэш в metadata листа). Пусто — свечения нет
static func points_for(frames: SpriteFrames, anim: String) -> Array:
	var key := "glow_" + anim
	if frames.has_meta(key):
		return frames.get_meta(key)
	var out: Array = []
	if frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
		var tex := frames.get_frame_texture(anim, 0)
		var img: Image = tex.get_image() if tex else null
		if img != null:
			out = find_points(img)
	frames.set_meta(key, out)
	return out

static func find_points(img: Image) -> Array:
	var cells := {}
	var w := img.get_width()
	var h := img.get_height()
	var vs: Array = []
	for y in range(0, h, STEP * 2):
		for x in range(0, w, STEP * 2):
			var c0 := img.get_pixel(x, y)
			if c0.a >= 0.6 and c0.s >= MIN_S:
				vs.append(c0.v)
	if vs.size() < 20:
		return []
	vs.sort()
	var min_v := maxf(MIN_V, float(vs[int(vs.size() * 0.98)]) * TOP_SHARE)
	for y in range(0, h, STEP):
		for x in range(0, w, STEP):
			var c := img.get_pixel(x, y)
			if c.a < 0.6 or c.v < min_v or c.s < MIN_S:
				continue
			var wt := c.v * c.s
			var key := Vector2i(x / CELL, y / CELL)
			var e: Dictionary = cells.get(key, {"w": 0.0, "p": Vector2.ZERO, "c": Color(0, 0, 0, 0)})
			e["w"] += wt
			e["p"] += Vector2(x, y) * wt
			e["c"] += Color(c.r * wt, c.g * wt, c.b * wt, 0.0)
			cells[key] = e
	var list: Array = []
	for key in cells:
		var e: Dictionary = cells[key]
		if e["w"] >= MIN_WEIGHT:
			list.append({"w": e["w"], "p": e["p"] / e["w"], "c": Color(e["c"].r / e["w"], e["c"].g / e["w"], e["c"].b / e["w"], 1.0)})
	list.sort_custom(func(a, b): return a["w"] > b["w"])
	var picked: Array = []
	for e in list:
		if picked.size() >= MAX_POINTS:
			break
		var near := false
		for q in picked:
			if (q["p"] as Vector2).distance_to(e["p"]) < MERGE_DIST:
				near = true
				break
		if near:
			continue
		var col: Color = e["c"]
		picked.append({"p": e["p"], "r": clampf(RADIUS_MIN + sqrt(e["w"]) * 0.9, RADIUS_MIN, RADIUS_MAX),
			"c": Color(minf(col.r * 1.15 + 0.08, 1.0), minf(col.g * 1.05 + 0.04, 1.0), col.b, 1.0),
			"ph": _rng.randf() * TAU, "sp": _rng.randf_range(1.6, 3.2), "w": e["w"]})
	return picked

static func _glow_texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_tex = ImageTexture.create_from_image(img)
	return _tex

# Угольки: над самой яркой точкой — крошечный квадрат поднимается и гаснет
func _tick_embers(delta: float, fighting: bool, size: Vector2) -> void:
	if fighting and not _points.is_empty() and _rng.randf() < EMBER_CHANCE * delta * (2.0 if not _custom.is_empty() else 1.0):
		var pt: Dictionary = _ember_source()
		var p: Vector2 = pt["p"] + Vector2(_rng.randf_range(-6.0, 6.0), -4.0)
		_embers.append({"p": p, "age": 0.0, "c": pt["c"], "dx": _rng.randf_range(-5.0, 5.0)})
	for e in _embers:
		e["age"] += delta
		e["p"] = e["p"] + Vector2(e["dx"] * delta, -EMBER_RISE * delta)
	_embers = _embers.filter(func(e): return e["age"] < EMBER_LIFE)
	queue_redraw()

# Источник уголька: у автопоиска — самая яркая точка, у ручных — случайный факел
func _ember_source() -> Dictionary:
	if _custom.is_empty():
		return _points[0]
	var torches: Array = _points.filter(func(q): return q.get("kind", "") == "t")
	return torches[_rng.randi() % torches.size()] if not torches.is_empty() else _points[0]

# Язык пламени факела кодом: три языка разной высоты качаются несоизмеримыми темпами, внутри — светлое ядро
func _draw_flame(pt: Dictionary) -> void:
	var base: Vector2 = sprite.offset + (pt["p"] as Vector2) + Vector2(0, 2)
	var ph: float = pt["ph"]
	var sp: float = pt["sp"]
	for i in 3:
		var wave := 0.5 + 0.5 * sin(_t * sp * (1.0 + 0.37 * i) + ph + i * 2.1)
		var h := FLAME_H * (0.55 + 0.75 * wave) * (1.0 if i == 1 else 0.7)
		var w := 2.2 if i == 1 else 1.6
		var x := (i - 1) * 2.6 + sin(_t * sp * 0.8 + ph + i) * 1.1
		var tip := base + Vector2(x * 0.5 + sin(_t * sp * 1.3 + i) * 1.5, -h)
		draw_colored_polygon(PackedVector2Array([base + Vector2(x - w, 0), tip, base + Vector2(x + w, 0)]), FLAME_OUTER)
		var core_tip := base + Vector2(tip.x - base.x, -h * 0.55)
		draw_colored_polygon(PackedVector2Array([base + Vector2(x - w * 0.5, 0), core_tip, base + Vector2(x + w * 0.5, 0)]), FLAME_CORE)

func _draw() -> void:
	if sprite == null:
		return
	for pt in _points:
		if pt.get("kind", "") == "t":
			_draw_flame(pt)
	var size := _frame_size()
	for e in _embers:
		var p: Vector2 = e["p"]
		var x := (size.x - p.x) if sprite.flip_h else p.x
		var a := 1.0 - float(e["age"]) / EMBER_LIFE
		draw_rect(Rect2(sprite.offset + Vector2(x, p.y) - Vector2(1, 1), Vector2(2, 2)), Color(e["c"], a * 0.8))
