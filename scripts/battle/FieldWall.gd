class_name FieldWall
extends Node2D

# Стена края поля (решение пользователя 10.11.2026, образец — «Мимо сетки_ готическая битва Империума.png», поле
# Хаоса): высокая готическая стена кодом по внешнему кольцу пола вместо плоских плит края (тема "field_wall"):
# грань с кладкой, толстый верх, столбы с шипами, на каждом LANTERN_EVERY-м столбе — горящий фонарь (его свет на
# земле и на бойцах — IsoGridRenderer, lantern_lights). Две стороны — два узла в y-sort контейнере бойцов: дальние
# рёбра — раньше всех бойцов, ближние — после всех (бойцы и существа к кольцу края не подходят — за ближней стеной
# стоят только те, кто внутри поля); каждая сторона — одна команда отрисовки треугольниками (звено узлом — +78
# вызовов отрисовки в y-sort между бойцами, как было у KingdomWall до 23.10.2026). Только вид: не
# преграда, не цель. Тень стены на земле и грань платформы — IsoGridRenderer (_draw_wall_shade / _draw_base).
#   FieldWall.build(контейнер, сетка, тема "field_wall") — звенья в контейнер
# Спрайты художника (тема "field_wall"."sprites", пакет 10.11.2026 по ART_TZ_FIELD_2026-11-10.txt): пролёты span_0..2
# (с башнями на обоих концах — шаг цепи «от башни до башни» period, башня следующего ложится на башню предыдущего),
# столб с фонарём (лента кадров, на каждом LANTERN_EVERY-м стыке) и столб с черепом (углы); одно направление
# «вниз-вправо», второе — отражением; всё — один атлас (сторона — одним пакетом отрисовки). Без "sprites" — кодом

const INSET: float = 0.15        # клетки: стена отступает от внешнего края пола внутрь — узкий карниз платформы
const SEG_LEN: float = 1.0       # клетки: звено = промежуток между столбами
const HEIGHT: float = 44.0       # px
const POST_HEIGHT: float = 58.0  # px: столб выше стены
const POST_HALF: float = 4.5     # px: полуширина столба
const THICK: float = 14.0        # px: толщина (верхняя грань)
const LANTERN_EVERY: int = 3     # фонарь — на каждом таком столбе по контуру
const LANTERN_UP: float = 0.62   # высота фонаря на столбе — доля HEIGHT
const LANTERN_INWARD: float = 0.18   # клетки: пятно света фонаря — у основания стены, чуть внутрь поля
const LANTERN_SPRITE_INWARD: float = 8.0   # px: пятно у столба-спрайта — к середине поля
const SLIT_ALPHA: float = 0.55   # бойницы в грани — тлеют огнём (образец: огоньки вдоль всей стены)
const FAR_LIGHT: float = 1.12    # дальние стены видны внутренней гранью — к свету поля чуть светлее
const NEAR_SHADE: float = 0.7    # ближние — внешней гранью, к пустоте: темнее

var segments: Array = []

# Контур стены в координатах сетки (u — колонка, v — ряд): внешний край кольца пола минус INSET
static func contour(g: IsoGrid) -> Rect2:
	var pad := IsoGridRenderer.FLOOR_PAD_TILES
	var u0 := -pad - 0.5 + INSET
	var v0 := -pad - 0.5 + INSET
	var u1 := g.get_layout_cols() + pad - 0.5 - INSET
	var v1 := g.get_layout_rows() + pad - 0.5 - INSET
	return Rect2(u0, v0, u1 - u0, v1 - v0)

static func _corners(g: IsoGrid) -> Array:
	var r := contour(g)
	return [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]

# Звено по контуру — клетки: кодом SEG_LEN, спрайтами — шаг пролёта «от башни до башни» (period / полуширина клетки)
static func _seg_len(cfg: Dictionary) -> float:
	if not cfg.has("sprites"):
		return SEG_LEN
	var sp: Dictionary = cfg["sprites"]
	return Vector2(sp["period"]).x * float(sp["scale"]) / (IsoGrid.TILE_WIDTH / 2.0)

# Стыки по контуру (координаты сетки): [точка, индекс по контуру, ребро, следующий стык, номер на ребре]; от угла
# к углу ровным шагом не длиннее _seg_len (пролёты спрайтов слегка заходят друг на друга — башня на башню)
static func _posts(g: IsoGrid, cfg: Dictionary = {}) -> Array:
	var out: Array = []
	var corners := _corners(g)
	var idx := 0
	var seg := _seg_len(cfg)
	for e in 4:
		var a: Vector2 = corners[e]
		var b: Vector2 = corners[(e + 1) % 4]
		var n := maxi(1, ceili(a.distance_to(b) / seg))
		for i in n:
			out.append([a.lerp(b, float(i) / n), idx, e, a.lerp(b, float(i + 1) / n), i])
			idx += 1
	return out

# Фонарь на стыке: каждый LANTERN_EVERY-й; у спрайтов — не в углу (там столб с черепом)
static func _has_lantern(p: Array, cfg: Dictionary) -> bool:
	return p[1] % LANTERN_EVERY == 0 and not (cfg.has("sprites") and p[4] == 0)

# Свет фонарей для IsoGridRenderer: [точка на земле (мир сетки), индекс] — внутрь поля от стены
static func lantern_lights(g: IsoGrid, cfg: Dictionary = {}) -> Array:
	var out: Array = []
	var r := contour(g)
	var center := r.get_center()
	if cfg.has("sprites"):   # спрайты: от столба с фонарём (стык + сдвиг к башне), чуть к середине поля
		var mid := g.lattice_to_screen(center.x, center.y)
		for near in [false, true]:
			for it in _sprite_items(g, cfg, near):
				if it[1] == "lantern":
					var at: Vector2 = it[3]
					out.append([at + (mid - at).normalized() * LANTERN_SPRITE_INWARD, int(it[2]) / 3])
		return out
	for p in _posts(g, cfg):
		if not _has_lantern(p, cfg):
			continue
		var at: Vector2 = p[0]
		at += (center - at).sign() * Vector2(LANTERN_INWARD, LANTERN_INWARD) * _inward_mask(p[2])
		out.append([g.lattice_to_screen(at.x, at.y), p[1]])
	return out

# Ребро e (0 — верх-право v0, 1 — право-низ u1, 2 — низ-лево v1, 3 — лево-верх u0): по какой оси внутрь
static func _inward_mask(e: int) -> Vector2:
	return Vector2(0.0, 1.0) if e == 0 or e == 2 else Vector2(1.0, 0.0)

# Ближние рёбра (видна внешняя грань): u1 и v1
static func _is_near(e: int) -> bool:
	return e == 1 or e == 2

const SORT_FAR: float = -100000.0   # y-sort: дальняя сторона — раньше всех
const SORT_NEAR: float = 100000.0   # ближняя — после всех

static func build(container: Node, g: IsoGrid, cfg: Dictionary) -> FieldWall:
	var w := FieldWall.new()
	container.add_child(w)
	for near in [false, true]:
		var side := Segment.new()
		side.cfg = cfg
		side.near = near
		side.position = Vector2(0.0, SORT_NEAR if near else SORT_FAR)
		if cfg.has("sprites"):
			side.parts = _sprite_parts(cfg["sprites"])
			side.items = _sprite_items(g, cfg, near)
		for p in _posts(g, cfg):
			if _is_near(p[2]) == near:
				side.segs.append([g.lattice_to_screen(p[0].x, p[0].y), g.lattice_to_screen(p[3].x, p[3].y),
					_has_lantern(p, cfg)])
		# внутри стороны — от дальних к ближним (столб ближнего звена поверх стены дальнего)
		side.segs.sort_custom(func(x, y): return x[0].y + x[1].y < y[0].y + y[1].y)
		w.segments.append(side)
		container.add_child(side)
		side.set_process(side.items.any(func(it): return it[1] == "lantern"))
	return w

# Атлас спрайтов стены (один на папку, статичный кэш): {"atlas": ImageTexture, "regions": {имя: Rect2}};
# собирается в build (не в _draw — ImageTexture из _draw рисовалась пустой)
static var _parts_cache: Dictionary = {}
static func _sprite_parts(sp: Dictionary) -> Dictionary:
	var dir: String = sp["dir"]
	if _parts_cache.has(dir):
		return _parts_cache[dir]
	var pieces: Array = []   # [имя, Image]
	for i in sp["spans"]:
		pieces.append(["span_%d" % i, FactionTheme.load_texture(dir + "span_%d.png" % i).get_image()])
	pieces.append(["post_corner", FactionTheme.load_texture(dir + sp["corner"]).get_image()])
	var strip: Image = FactionTheme.load_texture(dir + sp["lantern"]).get_image()
	var lf: int = sp["lantern_frames"]
	var fw := strip.get_width() / lf
	for i in lf:
		pieces.append(["lantern_%d" % i, strip.get_region(Rect2i(i * fw, 0, fw, strip.get_height()))])
	var w := 0
	var h := 0
	for pc in pieces:
		var im: Image = pc[1]
		if im.is_compressed():
			im.decompress()
		im.convert(Image.FORMAT_RGBA8)
		w += im.get_width() + 2
		h = maxi(h, im.get_height())
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var regions := {}
	var x := 0
	for pc in pieces:
		var im: Image = pc[1]
		img.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x, 0))
		regions[pc[0]] = Rect2(x, 0, im.get_width(), im.get_height())
		x += im.get_width() + 2
	var parts := {"atlas": ImageTexture.create_from_image(img), "regions": regions}
	_parts_cache[dir] = parts
	return parts

# Что рисует сторона спрайтами: [y сортировки, вид, имя куска / сдвиг фазы фонаря, точка (мир), отражение].
# Пролёт — верхним концом звена в точку sprites.anchor листа, звено вниз-влево — отражён; столб — в точке стыка
# + сдвиг к центру башни (post_offset); в углу — столб с черепом
static func _sprite_items(g: IsoGrid, cfg: Dictionary, near: bool) -> Array:
	var sp: Dictionary = cfg["sprites"]
	var k: float = sp["scale"]
	var spans: Array = sp["spans"]
	var out: Array = []
	for p in _posts(g, cfg):
		if _is_near(p[2]) != near:
			continue
		var a := g.lattice_to_screen(p[0].x, p[0].y)
		var b := g.lattice_to_screen(p[3].x, p[3].y)
		var top := a if a.y <= b.y else b
		var low := b if a.y <= b.y else a
		var flip := low.x < top.x
		var variant: int = spans[0]
		var h := TerrainTiles.hash_cell(Vector2i(p[1], p[2]), 91) % 100
		if spans.size() > 2 and h < 12:
			variant = spans[2]   # побитый — реже
		elif spans.size() > 1 and h < 30:
			variant = spans[1]
		out.append([top.y, "span", "span_%d" % variant, top, flip])
		# стык a — у звена вниз-вправо это его верхний конец, у отражённого — тоже верхний (top), сдвиг к башне
		# зеркалится вместе с листом
		var off := Vector2(sp["post_offset"]) * k * Vector2(-1.0 if flip else 1.0, 1.0)   # к башне — в масштабе пролёта
		if p[4] == 0:
			out.append([a.y + 0.5, "post", "post_corner", a + off, false])
		elif _has_lantern(p, cfg):
			out.append([a.y + 0.5, "lantern", p[1] * 3, a + off, flip])
	out.sort_custom(func(x, y): return x[0] < y[0])
	return out

func _exit_tree() -> void:
	for s in segments:
		if is_instance_valid(s):
			s.queue_free()
	_parts_cache.clear()   # атлас — на бой (сборка ~мс); статичный кэш держал бы ImageTexture до выхода из игры


# Сторона стены (дальняя или ближняя): звенья segs [a, b, фонарь] — стена от a до b (мировые точки) и столб с шипом
# в a; вся сторона — один массив треугольников, собирается один раз (статично)
class Segment extends Node2D:
	var cfg: Dictionary
	var segs: Array = []
	var parts: Dictionary = {}   # спрайты: атлас и куски (FieldWall._sprite_parts)
	var items: Array = []        # спрайты: что рисовать (FieldWall._sprite_items)
	var _lantern_frame := 0

	func _process(_delta: float) -> void:   # огонь фонарей — кадр ленты по часам (только вид)
		var f := int(Time.get_ticks_msec() * float(cfg["sprites"]["lantern_fps"]) / 1000.0)
		if f != _lantern_frame:
			_lantern_frame = f
			queue_redraw()

	func _draw_sprites() -> void:
		var sp: Dictionary = cfg["sprites"]
		var k: float = sp["scale"]
		var atlas: Texture2D = parts["atlas"]
		var regions: Dictionary = parts["regions"]
		var lf: int = sp["lantern_frames"]
		for it in items:
			var region: Rect2
			var anchor: Vector2
			if it[1] == "span":
				region = regions[it[2]]
				anchor = sp["anchor"]
			elif it[1] == "post":
				region = regions[it[2]]
				anchor = sp["post_base"]
			else:
				region = regions["lantern_%d" % posmod(_lantern_frame + int(it[2]), lf)]
				anchor = sp["post_base"]
			var ks: float = k if it[1] == "span" else float(sp.get("post_scale", k))   # столбы — свой масштаб
			draw_set_transform(it[3] - position, 0.0, Vector2(-ks if it[4] else ks, ks))
			draw_texture_rect_region(atlas, Rect2(-anchor, region.size), region)
		draw_set_transform(Vector2.ZERO)
	var near := false
	var a: Vector2
	var b: Vector2
	var lantern := false
	var _pts := PackedVector2Array()
	var _cols := PackedColorArray()
	var _idx := PackedInt32Array()

	func _poly(p: PackedVector2Array, col: Color) -> void:   # выпуклый многоугольник — веером
		var base := _pts.size()
		for v in p:
			_pts.append(v)
			_cols.append(col)
		for i in range(1, p.size() - 1):
			_idx.append_array([base, base + i, base + i + 1])

	func _grad(p: PackedVector2Array, cols: Array) -> void:   # четырёхугольник с цветом по вершинам
		var base := _pts.size()
		for i in 4:
			_pts.append(p[i])
			_cols.append(cols[i])
		_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func _line(p: Vector2, q: Vector2, col: Color, w: float = 1.0) -> void:
		var n := (q - p).orthogonal().normalized() * (w * 0.5)
		_poly(PackedVector2Array([p - n, q - n, q + n, p + n]), col)

	func _rect(r: Rect2, col: Color) -> void:
		_poly(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), col)

	func _draw() -> void:
		if not items.is_empty():
			_draw_sprites()
			return
		if _idx.is_empty():
			for sg in segs:
				a = sg[0]
				b = sg[1]
				lantern = sg[2]
				_build()
		if not _idx.is_empty():
			RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _pts, _cols)

	func _build() -> void:
		var stone: Color = cfg["stone"]
		var top_col: Color = cfg["top"]
		var dark: Color = cfg["dark"]
		var k := FieldWall.NEAR_SHADE if near else FieldWall.FAR_LIGHT
		var face := Color(stone.r * k, stone.g * k, stone.b * k)
		var la := a - position
		var lb := b - position
		var up := Vector2(0.0, -FieldWall.HEIGHT)
		var along := (lb - la).normalized()
		var n := Vector2(-along.y, along.x)
		n = Vector2(n.x, n.y * 0.5).normalized() * FieldWall.THICK * 0.5
		# Грань: к земле темнее (тень у основания), к верху — как камень
		var foot := face.lerp(dark, 0.6)
		_grad(PackedVector2Array([la, lb, lb + up, la + up]), [foot, foot, face, face])
		_poly(PackedVector2Array([la + up - n, lb + up - n, lb + up + n, la + up + n]), top_col)
		_line(la + up, lb + up, dark, 1.0)
		_line(la, lb, dark, 1.5)
		# Кладка: два шва и стыки камней вразбежку
		var seam := dark.lerp(face, 0.3)
		for row in 3:
			var y0 := float(row) / 3.0
			var y1 := float(row + 1) / 3.0
			if row > 0:
				_line(la + up * y0, lb + up * y0, seam, 1.0)
			for j in 5:
				var t := (j + (0.3 if row % 2 == 0 else 0.8)) / 5.0
				_line(la.lerp(lb, t) + up * y0, la.lerp(lb, t) + up * y1, seam, 1.0)
		# Бойницы: две узкие щели в звене, тлеют огнём изнутри
		var flame: Color = cfg["lantern"]
		for t in [0.33, 0.67]:
			var c := la.lerp(lb, t) + up * 0.55
			_rect(Rect2(c + Vector2(-2.0, -5.0), Vector2(4.0, 8.0)), dark)
			_rect(Rect2(c + Vector2(-1.0, -4.0), Vector2(2.0, 6.0)), Color(flame, FieldWall.SLIT_ALPHA))
		# Зубцы по верху
		for i in 4:
			var p := la.lerp(lb, (i + 0.5) / 4.0) + up
			_rect(Rect2(p + Vector2(-3.0, -4.0), Vector2(6.0, 4.0)), top_col)
			_line(p + Vector2(-3.0, -4.0), p + Vector2(3.0, -4.0), top_col.lerp(Color.WHITE, 0.08), 1.0)
		# Столб в a: тело, верхушка, шип
		var post_up := Vector2(0.0, -FieldWall.POST_HEIGHT)
		var hw := FieldWall.POST_HALF
		var post_col := dark.lerp(face, 0.75)
		_grad(PackedVector2Array([la + Vector2(-hw, 0), la + Vector2(hw, 0), la + Vector2(hw, 0) + post_up,
			la + Vector2(-hw, 0) + post_up]), [dark, dark, post_col, post_col])
		_line(la + Vector2(-hw, 0) + post_up, la + Vector2(-hw, 0), dark, 1.0)
		_rect(Rect2(la + post_up + Vector2(-hw - 1.5, -3.0), Vector2(hw * 2.0 + 3.0, 3.0)), top_col)
		var spike: Color = cfg["spike"]
		_poly(PackedVector2Array([la + post_up + Vector2(-hw + 0.5, -3.0), la + post_up + Vector2(hw - 0.5, -3.0),
			la + post_up + Vector2(0.0, -14.0)]), spike)
		_line(la + post_up + Vector2(0.0, -3.0), la + post_up + Vector2(0.0, -13.0), spike.lerp(Color.WHITE, 0.2), 1.0)
		if lantern:
			# Фонарь на столбе: железная клетка, горящее ядро; ореол — WorldGrade bloom, свет на земле — IsoGridRenderer
			var c := la + Vector2(0.0, -FieldWall.HEIGHT * FieldWall.LANTERN_UP)
			# ореол по камню вокруг: ромб, к краю — в ноль (веер от центра с цветом по вершинам)
			var base := _pts.size()
			_pts.append(c)
			_cols.append(Color(flame, 0.32))
			var ring := 10
			for i in ring:
				var ang := TAU * i / ring
				_pts.append(c + Vector2(cos(ang) * 22.0, sin(ang) * 16.0))
				_cols.append(Color(flame, 0.0))
			for i in ring:
				_idx.append_array([base, base + 1 + i, base + 1 + (i + 1) % ring])
			_rect(Rect2(c + Vector2(-5.5, -8.0), Vector2(11.0, 14.0)), dark)
			_rect(Rect2(c + Vector2(-3.5, -6.0), Vector2(7.0, 10.0)), flame)
			_rect(Rect2(c + Vector2(-1.5, -4.0), Vector2(3.0, 6.0)), flame.lerp(Color.WHITE, 0.6))
			_rect(Rect2(c + Vector2(-0.5, -8.0), Vector2(1.0, 14.0)), dark)   # прут клетки
			_rect(Rect2(c + Vector2(-7.0, -10.0), Vector2(14.0, 2.5)), dark)
