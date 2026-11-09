class_name KingdomWall
extends Node2D

# Стена вокруг владений игрока (решение пользователя 22.10.2026, ориентир — 9 Kings,
# Screenshot 2026-10-22 110838.png): карта Fortress Wall (у Хаоса — Spiked Barricade) клетку не занимает —
# стена встаёт по контуру рамки королевства вместе с цитаделью. Физическая преграда: враг, чей шаг ведёт
# снаружи внутрь через целое звено, встаёт у стены и ломает это звено (Soldier._attack_wall); разбитое звено —
# проход. Свои ходят сквозь неё, снаряды летят поверх, прыжок и Deep Strike — через неё.
# Каждый бой — заново целая (сцена боя строит её с полным HP). Щит цитадели на бой — тоже от стены.
# Карта стены лежит в BattleManager.player_buildings на клетке BattleManager.WALL_TILE (вне поля): сохранение,
# уровень такой же картой и события «здание +1 уровень» — как у зданий.
#   KingdomWall.build(контейнер, сетка, карта) — звенья в y-sort контейнере бойцов

# Клетки: от края рамки до стены. 23.10.2026 (решение пользователя: «стена задевает здания») — было 0.4: основание
# здания на крайней клетке шире клетки, переднее звено со столбами ложилось на него
const MARGIN: float = 0.65
const SEG_LEN: float = 0.5       # клетки: длина звена
const HEIGHT: float = 16.0       # px: высота стены
const POST_HEIGHT: float = 22.0  # px: столб на стыке звеньев
const THICK: float = 7.0         # px: толщина (верхняя грань)
const RISE_TIME: float = 0.35    # стена вырастает из земли (сыграна карта)
const RISE_WAVE: float = 0.6     # звенья — волной по контуру
const FLASH_TIME: float = 0.9    # вспышка щита в начале боя

var card: CardData
var stats: Dictionary = {}
var grid: IsoGrid
var segments: Array = []    # Segment по контуру
var _u0: float
var _u1: float
var _v0: float
var _v1: float

static func build(container: Node, iso_grid: IsoGrid, wall_card: CardData, rising: bool = false) -> KingdomWall:
	var w := KingdomWall.new()
	w.card = wall_card
	w.grid = iso_grid
	container.add_child(w)
	w._build_segments(container, rising)
	return w

# Статы по уровню карты и ордену (Imperial Fists — крепче), HP звеньев — полные
func refresh_stats() -> void:
	stats = Chapters.apply_building_stats(card.get_building_stats(), RunManager.player_chapter)
	for s in segments:
		s.max_hp = stats.get("wall_hp", 0.0)
		s.hp = s.max_hp
		s.mark_dirty()

func get_citadel_shield() -> float:
	return stats.get("shield", 0.0)

# Контур стены в координатах сетки (u — колонка, v — ряд): рамка королевства и ряд цитадели, с отступом MARGIN.
# Карта поля держит полосу вдоль него свободной (IsoGridRenderer._on_wall_line): стену можно купить в любом забеге
static func contour(g: IsoGrid) -> Rect2:
	var u0 := IsoGrid.KINGDOM_FRAME_MIN.x - 0.5 - MARGIN
	var v0 := IsoGrid.KINGDOM_FRAME_MIN.y - 0.5 - MARGIN
	var u1 := g.grid_width - 0.5 + MARGIN
	var v1 := maxf(g.grid_height, g.citadel_tile.y + 1) - 0.5 + MARGIN
	return Rect2(u0, v0, u1 - u0, v1 - v0)

func _build_segments(container: Node, rising: bool) -> void:
	var r := contour(grid)
	_u0 = r.position.x
	_v0 = r.position.y
	_u1 = r.end.x
	_v1 = r.end.y
	var corners := [Vector2(_u0, _v0), Vector2(_u1, _v0), Vector2(_u1, _v1), Vector2(_u0, _v1)]
	var total := 0
	for e in 4:
		var a: Vector2 = corners[e]
		var b: Vector2 = corners[(e + 1) % 4]
		var n := maxi(1, ceili(a.distance_to(b) / SEG_LEN))
		for i in n:
			var s := Segment.new()
			s.wall = self
			s.a = grid.lattice_to_screen(lerpf(a.x, b.x, float(i) / n), lerpf(a.y, b.y, float(i) / n))
			s.b = grid.lattice_to_screen(lerpf(a.x, b.x, float(i + 1) / n), lerpf(a.y, b.y, float(i + 1) / n))
			s.index = total
			total += 1
			segments.append(s)
	for s in segments:
		s.position = (s.a + s.b) / 2.0   # y-sort с бойцами — по середине звена
		s.rise_delay = (float(s.index) / total) * RISE_WAVE if rising else -1.0
		container.add_child(s)
	refresh_stats()

# Мировая точка → координаты сетки (u — колонка, v — ряд), как IsoGrid.screen_to_tile без округления
func lattice_of(p: Vector2) -> Vector2:
	var local := p - grid.player_origin
	var x := local.x / (IsoGrid.TILE_WIDTH / 2.0)
	var y := local.y / (IsoGrid.TILE_HEIGHT / 2.0)
	return Vector2((x + y) / 2.0, (y - x) / 2.0)

func is_inside(p: Vector2) -> bool:
	var l := lattice_of(p)
	return l.x > _u0 and l.x < _u1 and l.y > _v0 and l.y < _v1

# Шаг from → to ведёт снаружи внутрь через целое звено — это звено (враг встаёт у стены), иначе null
func blocking_segment(from: Vector2, to: Vector2) -> Segment:
	var lt := lattice_of(to)
	if not (lt.x > _u0 and lt.x < _u1 and lt.y > _v0 and lt.y < _v1):
		return null
	var lf := lattice_of(from)
	if lf.x > _u0 and lf.x < _u1 and lf.y > _v0 and lf.y < _v1:
		return null   # уже внутри (прыжок, Deep Strike, пролом) — не мешает
	# Где шаг входит в прямоугольник: наибольший параметр входа по осям
	var d := lt - lf
	var t := 0.0
	if lf.x <= _u0 and d.x > 0.0:
		t = maxf(t, (_u0 - lf.x) / d.x)
	if lf.x >= _u1 and d.x < 0.0:
		t = maxf(t, (_u1 - lf.x) / d.x)
	if lf.y <= _v0 and d.y > 0.0:
		t = maxf(t, (_v0 - lf.y) / d.y)
	if lf.y >= _v1 and d.y < 0.0:
		t = maxf(t, (_v1 - lf.y) / d.y)
	var hit := grid.lattice_to_screen(lf.x + d.x * t, lf.y + d.y * t)
	var best: Segment = null
	var best_d := INF
	for s in segments:
		var dist: float = Geometry2D.get_closest_point_to_segment(hit, s.a, s.b).distance_squared_to(hit)
		if dist < best_d:
			best_d = dist
			best = s
	return best if best and best.hp > 0.0 else null

# Начало боя: щит цитадели от стены — вспышка по всем звеньям (вместо купола, решение пользователя);
# broken — щит кончился: вспышка красным
func flash_shield(broken: bool = false) -> void:
	for s in segments:
		s.flash_left = FLASH_TIME
		s.flash_color = Palette.HIT_RED if broken else Palette.SHIELD_BLUE
		s.set_process(true)

func set_highlighted(on: bool) -> void:
	for s in segments:
		s.modulate = Palette.GOLD_PALE if on else Color.WHITE

func _exit_tree() -> void:
	for s in segments:
		if is_instance_valid(s):
			s.queue_free()


# Звено стены: свой HP, рисуется призмой от a до b (мировые точки); y-sort — по середине
class Segment extends Node2D:
	var wall: KingdomWall
	var a: Vector2
	var b: Vector2
	var index := 0
	var hp := 0.0
	var max_hp := 0.0
	var rise_delay := -1.0     # ≥ 0 — вырастает из земли через столько секунд
	var flash_left := 0.0      # вспышка щита
	var flash_color := Palette.SHIELD_BLUE
	var _hit_left := 0.0       # белая вспышка попадания
	var _t := 0.0

	func _ready() -> void:
		set_process(rise_delay >= 0.0)

	# Попадание (удар врага, снаряд — Projectile зовёт take_hit у всего, у кого он есть)
	func take_hit(amount: float) -> void:
		if hp <= 0.0:
			return
		hp = maxf(hp - amount, 0.0)
		AudioManager.play("wall_hit")
		_hit_left = Soldier.HIT_FLASH_TIME
		set_process(true)
		var chaos := wall.card.faction == "chaos"
		if hp <= 0.0:
			AudioManager.play("wall_break")
			BuildingFx.wall_break(get_parent(), a, b, chaos)   # камни и пыль (было: ground_slam пака Pixel)
		else:
			BuildingFx.wall_chips(get_parent(), self, a, b, chaos)
		mark_dirty()

	# HP или статы изменились — геометрию звена собрать заново
	func mark_dirty() -> void:
		_dirty = true
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		flash_left = maxf(flash_left - delta, 0.0)
		_hit_left = maxf(_hit_left - delta, 0.0)
		var rising := rise_delay >= 0.0 and _t < rise_delay + KingdomWall.RISE_TIME
		if flash_left <= 0.0 and _hit_left <= 0.0 and not rising:
			if rise_delay >= 0.0:
				_dirty = true   # дорос — последний кадр в полную высоту
			rise_delay = -1.0
			set_process(false)
		queue_redraw()

	# Звено — одна команда отрисовки (треугольники с цветом вершин): 48 звеньев в y-sort между бойцами из
	# десятка draw_* каждое рвали пакеты — +275 draw calls и −25 FPS в худшем бою (test_performance, 23.10.2026)
	var _pts := PackedVector2Array()
	var _cols := PackedColorArray()
	var _idx := PackedInt32Array()
	# Геометрия звена собирается только при смене HP / статов и пока звено растёт; вспышки (щит, попадание) —
	# один многоугольник поверх готовой: сборка на GDScript ~70 мкс, а вспышка щита в начале боя перерисовывает
	# все 48 звеньев каждый кадр 0.9 с — было +3.5 мс на кадр (test_performance, 23.10.2026)
	var _dirty := true
	var _base_pts := 0
	var _base_idx := 0
	var _face := PackedVector2Array()   # лицевая грань — под вспышки

	func _poly(p: PackedVector2Array, col: Color) -> void:   # выпуклый многоугольник — веером
		var base := _pts.size()
		for v in p:
			_pts.append(v)
			_cols.append(col)
		for i in range(1, p.size() - 1):
			_idx.append_array([base, base + i, base + i + 1])

	func _line(p: Vector2, q: Vector2, col: Color, w: float = 1.0) -> void:
		var n := (q - p).orthogonal().normalized() * (w * 0.5)
		_poly(PackedVector2Array([p - n, q - n, q + n, p + n]), col)

	func _rect(r: Rect2, col: Color) -> void:
		_poly(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), col)

	func _draw() -> void:
		if _dirty or rise_delay >= 0.0:
			_pts.clear()
			_cols.clear()
			_idx.clear()
			_face.clear()
			_build()
			_dirty = false
			_base_pts = _pts.size()
			_base_idx = _idx.size()
		else:   # вспышки прошлого кадра — прочь
			_pts.resize(_base_pts)
			_cols.resize(_base_pts)
			_idx.resize(_base_idx)
		if not _face.is_empty():
			if flash_left > 0.0:   # щит стен: голубой отсвет по стене
				var f := sin(flash_left / KingdomWall.FLASH_TIME * PI) * 0.6
				_poly(_face, Color(flash_color, f))
			if _hit_left > 0.0:
				_poly(_face, Color(1, 1, 1, 0.7 * _hit_left / Soldier.HIT_FLASH_TIME))
		if not _idx.is_empty():
			RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _pts, _cols)

	func _build() -> void:
		var h := KingdomWall.HEIGHT
		if rise_delay >= 0.0:
			var k := clampf((_t - rise_delay) / KingdomWall.RISE_TIME, 0.0, 1.0)
			if k <= 0.0:
				return
			h *= 1.0 - pow(1.0 - k, 3.0)
		var chaos := wall.card.faction == "chaos"
		var face_col: Color = Palette.CHAOS_WALL_STONE if chaos else Palette.WALL_STONE
		var top_col: Color = Palette.CHAOS_WALL_TOP if chaos else Palette.WALL_STONE_TOP
		var dark_col: Color = Palette.CHAOS_WALL_DARK if chaos else Palette.WALL_STONE_DARK
		var la := a - position
		var lb := b - position
		var ratio := hp / maxf(max_hp, 1.0)
		if hp <= 0.0:   # пролом: груда камня
			h = KingdomWall.HEIGHT * 0.25
			face_col = dark_col
			top_col = face_col.lerp(top_col, 0.4)
		var up := Vector2(0.0, -h)
		# Верхняя грань — полоса толщины KingdomWall.THICK по нормали к звену в плоскости земли (изометрия: y ×0.5)
		var along := (lb - la).normalized()
		var n := Vector2(-along.y, along.x)
		n = Vector2(n.x, n.y * 0.5).normalized() * KingdomWall.THICK * 0.5
		_face = PackedVector2Array([la, lb, lb + up, la + up])
		_poly(_face, face_col)
		_poly(PackedVector2Array([la + up - n, lb + up - n, lb + up + n, la + up + n]), top_col)
		_line(la + up, lb + up, dark_col, 1.0)
		_line(la, lb, dark_col, 1.0)
		if hp > 0.0:
			# Кладка: шов посередине и стыки камней вразбежку
			var seam := dark_col.lerp(face_col, 0.35)
			_line(la + up * 0.5, lb + up * 0.5, seam, 1.0)
			for j in 4:
				var k := (j + (0.25 if j % 2 == 0 else 0.75)) / 4.0
				var lo := la.lerp(lb, k)
				var hi_k := clampf(k + 0.125, 0.0, 1.0)
				_line(lo, lo + up * 0.5, seam, 1.0)
				_line(la.lerp(lb, hi_k) + up * 0.5, la.lerp(lb, hi_k) + up, seam, 1.0)
			# Зубцы по верху и столб на начале звена: латунь у Космодесанта, костяной шип у Хаоса
			var crenels := 3
			for i in crenels:
				var p := la.lerp(lb, (i + 0.5) / crenels) + up
				if ratio < 0.34 and i == 1:
					continue   # сильно побито — зубец выбит
				_rect(Rect2(p + Vector2(-2.0, -3.0), Vector2(4.0, 3.0)), top_col)
			var post_up := Vector2(0.0, -KingdomWall.POST_HEIGHT * h / KingdomWall.HEIGHT)
			_poly(PackedVector2Array([la + Vector2(-3, 0), la + Vector2(3, 0), la + Vector2(3, 0) + post_up,
				la + Vector2(-3, 0) + post_up]), dark_col.lerp(face_col, 0.6))
			if chaos:
				_poly(PackedVector2Array([la + post_up + Vector2(-2, 0), la + post_up + Vector2(2, 0),
					la + post_up + Vector2(0, -6)]), Palette.CHAOS_WALL_SPIKE)
			else:
				_rect(Rect2(la + post_up + Vector2(-3, -2), Vector2(6, 2)), Palette.WALL_TRIM)
			if ratio < 0.67:   # трещины
				var c := la.lerp(lb, 0.4) + up * 0.8
				_line(c, c + Vector2(2, 4), dark_col)
				_line(c + Vector2(2, 4), c + Vector2(-1, 8), dark_col)
				_line(c + Vector2(-1, 8), c + Vector2(1, 11), dark_col)
			if ratio < 1.0 and BattleManager.is_battle_running():   # HP звена — над ним
				var w := la.distance_to(lb) * 0.6
				var bar := Rect2(Vector2(-w / 2.0, -KingdomWall.POST_HEIGHT - 6.0), Vector2(w, 2.0))
				_rect(bar, Palette.OUTLINE)
				_rect(Rect2(bar.position, Vector2(w * ratio, 2.0)), Palette.HIT_RED)
