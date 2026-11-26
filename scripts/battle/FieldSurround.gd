class_name FieldSurround
extends Node2D

# Земля за стеной поля (решение пользователя 23.11.2026, эталон — `Screenshot 2026-11-23 091657.png`: поле
# «висело в пустоте», нужно, чтобы грунт заполнял весь экран): вместо пустоты с огнями (VoidFx) и грани помоста —
# сплошной грунт на весь запас камеры и предметы окружения (деревья, камни, кости, кусты) за стеной. Ключ темы "surround":
#  — словарь (Хаос, Космодесант): "ground" — бесшовная текстура (Layer, tools/surround_build.py), подогнанная под цвет внутреннего
#    грунта, рисуется крупнее на "ground_scale"; "kinds" — предметы по имени, часть анимирована лентой кадров (кровь по жилам
#    дерева, глаз черепа, свет в дупле, куст на ветру — кодом из утверждённого спрайта); "groves" — рощи / заросли рядом с полем
#    (решение пользователя 23.11.2026: «сгруппируй деревья в лес, кусты в заросли»), "scatter" — редкие одиночные предметы
#    между ними. Предметы стоят не ближе DECOR_MARGIN клеток от стены. Предметы ВНУТРИ стены ("inside") ставит IsoGridRenderer;
#  — true: прежний вариант — пятнистый грунт шейдером field_surround и декор темы.
# Только вид; под полом и стеной, боёвку и камеру не затрагивает; анимированные предметы перерисовываются ANIM_FPS раз/с

const SHADER := preload("res://shaders/field_surround.gdshader")
const REACH: float = 3200.0           # px: запас грунта вокруг границ мира (отъезд камеры + пан + широкий экран)
const PROP_REACH: float = 1700.0      # px: запас для предметов (дальше камера не заезжает — лишнее не рисуем)
const DECOR_MARGIN: int = 2           # клеток от кольца пола до первого объекта (стена и её тень чистые)
const GROVE_VIEW: float = 40.0        # px: центры рощ — внутри рамки вписанной камеры (get_world_bounds) + столько: видны сразу, не за кадром
const GROVE_GAP: float = 5.0          # клеток: центры рощ не ближе друг к другу
const DECOR_SPAN: int = 30            # клеток за кольцом пола, где ищем места для декора
const ANIM_FPS: float = 12.0          # частота перерисовки анимированных предметов
const OUTER_LUM_MULT: float = 3.2     # прежний вариант (true): яркость грунта = опора floor_calm × столько

var _rect: Rect2
var _ground_tex: Texture2D
var _ground_scale: float = 1.0
var _decor: Node2D                    # неподвижные предметы (рисуются один раз)
var _anim: Node2D                     # анимированные предметы
var _props_static: Array = []         # [предмет, точка, отражение]
var _props_anim: Array = []           # [предмет, точка, отражение, сдвиг по времени]
var _prop_scale: float = 1.0
var _prop_mod: Color = Color.WHITE
var _step: int = -1

# calm — параметры floor_calm темы (прежний вариант); decor_material — материал пола для предметов
func setup(grid: IsoGrid, theme: Dictionary, pad: int, seed_value: int, floor_modulate: Color, calm: Dictionary,
		decor_material: Material) -> void:
	show_behind_parent = true
	modulate = floor_modulate
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 0
	var cfg = theme.get("surround", true)
	_rect = grid.get_world_bounds().grow(REACH)
	var plan: Dictionary = {}
	if cfg is Dictionary:
		_ground_tex = FactionTheme.load_texture(cfg["ground"])
		_ground_scale = float(cfg.get("ground_scale", 1.0))
		_prop_scale = float(cfg.get("scale", 1.0))
		plan = cfg
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if _ground_tex == null:
		var ground: Array = theme.get("ground", theme.get("floor", []))
		var base := _average_color(ground[0] if not ground.is_empty() else null) * IsoGridRenderer.FLOOR_TINT
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("base_color", Color(base.r, base.g, base.b, 1.0))
		m.set_shader_parameter("target_lum", float(calm["pivot"]) * OUTER_LUM_MULT)
		material = m
		var kinds: Dictionary = {}
		var mix: Dictionary = {}
		for i in theme.get("decorations", []).size():
			var d: Dictionary = theme["decorations"][i]
			if not d.get("flag", false):
				kinds["d%d" % i] = d
				mix["d%d" % i] = 1.0
		plan = {"kinds": kinds, "scatter": {"chance": 9, "mix": mix}}
		_prop_scale = 1.0
	_prop_mod = IsoGridRenderer.FLOOR_TINT
	_decor = Node2D.new()
	# Предметы рисуются в дробном масштабе (SURROUND_SCALE 1.1 × зум камеры): NEAREST давал рваные края и срезы соседних
	# кадров ленты («tearing» на деревьях) — гладкий фильтр с мип-уровнями не рябит
	_decor.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_decor.material = decor_material
	_decor.draw.connect(_draw_decor)
	add_child(_decor)
	_anim = Node2D.new()
	_anim.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_anim.material = decor_material
	_anim.draw.connect(_draw_anim)
	add_child(_anim)
	_scatter(grid, plan, pad, seed_value)
	queue_redraw()
	_decor.queue_redraw()
	_anim.queue_redraw()
	set_process(not _props_anim.is_empty())

func _draw() -> void:
	if _ground_tex != null:
		# Текстура крупнее в _ground_scale раз: масштаб кладём в преобразование, прямоугольник — в его координатах
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(_ground_scale, _ground_scale))
		var r := Rect2(_rect.position / _ground_scale, _rect.size / _ground_scale)
		draw_texture_rect(_ground_tex, r, true)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_rect(_rect, Color.WHITE)

func _process(_delta: float) -> void:
	var step := int(Time.get_ticks_msec() * ANIM_FPS / 1000.0)
	if step != _step:
		_step = step
		_anim.queue_redraw()

func _draw_decor() -> void:
	for p in _props_static:
		_draw_one(_decor, p[0], p[1], p[2], 0.0)

func _draw_anim() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for p in _props_anim:
		_draw_one(_anim, p[0], p[1], p[2], t + p[3])

func _draw_one(canvas: CanvasItem, prop: Dictionary, foot: Vector2, flip: bool, time: float) -> void:
	var pr := prop
	if _prop_scale != 1.0:
		pr = prop.duplicate()
		pr["scale"] = prop.get("scale", 1.0) * _prop_scale
	TerrainTiles.draw_prop(canvas, pr, foot, _prop_mod, flip, time)

# Места объектов. Клетки решётки за кольцом пола (не ближе DECOR_MARGIN), в пределах PROP_REACH. Сначала рощи (центры рядом с
# полем, не ближе GROVE_GAP друг к другу; члены — клетки в радиусе, плотнее к центру, виды по весам "mix", "min" / "max" на вид),
# потом редкие одиночные предметы между ними. Порядок рисования — от дальних к ближним (u + v)
func _scatter(grid: IsoGrid, plan: Dictionary, pad: int, seed_value: int) -> void:
	var kinds: Dictionary = plan.get("kinds", {})
	if kinds.is_empty():
		return
	var cols := grid.get_layout_cols()
	var rows := grid.get_layout_rows()
	var lo_u := -pad - DECOR_MARGIN
	var lo_v := -pad - DECOR_MARGIN
	var hi_u := cols + pad + DECOR_MARGIN
	var hi_v := rows + pad + DECOR_MARGIN
	var prop_rect := grid.get_world_bounds().grow(PROP_REACH)
	var free: Dictionary = {}   # клетка → true (ещё не занята)
	var near: Array = []        # клетки в видимых углах вокруг поля (рамка камеры + GROVE_VIEW)
	var view_rect := grid.get_world_bounds().grow(GROVE_VIEW)
	for u in range(lo_u - DECOR_SPAN, hi_u + DECOR_SPAN):
		for v in range(lo_v - DECOR_SPAN, hi_v + DECOR_SPAN):
			if u >= lo_u and u < hi_u and v >= lo_v and v < hi_v:
				continue
			if not prop_rect.has_point(grid.lattice_to_screen(u, v)):
				continue
			var c := Vector2i(u, v)
			free[c] = true
			if view_rect.has_point(grid.lattice_to_screen(u, v)):
				near.append(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var placed: Array = []   # [клетка, вид]
	var centers: Array = []
	for g in plan.get("groves", []):
		for i in int(g.get("count", 0)):
			var center := Vector2i.ZERO
			var ok := false
			for attempt in 60:
				center = near[rng.randi() % near.size()] if not near.is_empty() else Vector2i.ZERO
				ok = true
				for o in centers:
					if Vector2(center - o).length() < GROVE_GAP:
						ok = false
						break
				if ok:
					break
			if not ok:
				continue
			centers.append(center)
			_plant_grove(g, center, kinds, free, rng, placed)
	var sc: Dictionary = plan.get("scatter", {})
	var chance := int(sc.get("chance", 0))
	if chance > 0 and not sc.get("mix", {}).is_empty():
		for c in free.keys():
			if free[c] and TerrainTiles.hash_cell(c, seed_value + 7) % 100 < chance:
				placed.append([c, _pick(sc["mix"], rng, {})])
	placed.sort_custom(func(a, b) -> bool: return a[0].x + a[0].y < b[0].x + b[0].y)
	for p in placed:
		var c: Vector2i = p[0]
		var prop: Dictionary = kinds[p[1]]
		var jitter := Vector2((TerrainTiles.hash_cell(c, 21) % 41) - 20, (TerrainTiles.hash_cell(c, 29) % 17) - 8)
		var foot := grid.lattice_to_screen(c.x, c.y) + jitter
		var flip := TerrainTiles.hash_cell(c, 37) % 2 == 1
		if prop.get("frames", 1) > 1:
			_props_anim.append([prop, foot, flip, (TerrainTiles.hash_cell(c, 61) % 1000) / 1000.0 * 4.0])   # у каждого свой сдвиг
		else:
			_props_static.append([prop, foot, flip])

# Роща: size предметов в радиусе radius клеток от центра (в решётке), ближе к центру плотнее
func _plant_grove(g: Dictionary, center: Vector2i, kinds: Dictionary, free: Dictionary, rng: RandomNumberGenerator, placed: Array) -> void:
	var radius: float = g.get("radius", 2.5)
	var size: Array = g.get("size", [8, 12])
	var want := rng.randi_range(int(size[0]), int(size[1]))
	var cells: Array = []
	var r := int(ceil(radius))
	for du in range(-r, r + 1):
		for dv in range(-r, r + 1):
			var c := center + Vector2i(du, dv)
			var d := Vector2(du, dv).length()
			if d <= radius and free.get(c, false):
				cells.append([c, d + rng.randf() * 1.2])   # неровный край рощи
	cells.sort_custom(func(a, b) -> bool: return a[1] < b[1])   # ближние к центру — первыми
	var counts: Dictionary = {}
	var mins: Dictionary = g.get("min", {})
	var maxs: Dictionary = g.get("max", {})
	var picked: Array = []
	for m in cells:
		if picked.size() >= want:
			break
		picked.append(m[0])
	# сначала обязательные виды (min), остальным — по весам с учётом max
	var order: Array = []
	for kind in mins:
		for i in int(mins[kind]):
			order.append(kind)
	for i in picked.size():
		var kind: String = order[i] if i < order.size() else _pick(g.get("mix", {}), rng, _full(counts, maxs))
		counts[kind] = counts.get(kind, 0) + 1
		var c: Vector2i = picked[i]
		# обязательные виды (деревья) — ближе к центру: picked уже отсортирован от центра
		placed.append([c, kind])
		free[c] = false

# виды, достигшие max, из выбора исключаются: возвращает {вид: true} для исключаемых
func _full(counts: Dictionary, maxs: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for kind in maxs:
		if counts.get(kind, 0) >= int(maxs[kind]):
			out[kind] = true
	return out

func _pick(mix: Dictionary, rng: RandomNumberGenerator, banned: Dictionary) -> String:
	var total := 0.0
	for k in mix:
		if not banned.has(k):
			total += float(mix[k])
	var t := rng.randf() * total
	var last := ""
	for k in mix:
		if banned.has(k):
			continue
		last = k
		t -= float(mix[k])
		if t <= 0.0:
			return k
	return last

# Средний цвет непрозрачных пикселей плиты (грунт темы)
static func _average_color(entry) -> Color:
	var fallback := Color(0.14, 0.1, 0.1)
	if entry == null:
		return fallback
	var path: String = entry["texture"] if entry is Dictionary else str(entry)
	var tex := FactionTheme.load_texture(path)
	if tex == null:
		return fallback
	var img := tex.get_image()
	if img == null:
		return fallback
	if img.is_compressed():
		img.decompress()
	var sum := Vector3.ZERO
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a > 0.9:
				sum += Vector3(c.r, c.g, c.b)
				n += 1
	if n == 0:
		return fallback
	sum /= float(n)
	return Color(sum.x, sum.y, sum.z)
