class_name SideCritters
extends RefCounted

# Мелкие существа по краям поля (решение пользователя 23.10.2026: «маленькие сайд-NPC, просто двигаются по бокам
# карты, стилизуй под игру»): демоны и кровавые твари пака Tiny RPG 02 (листы — tools/critters_from_tiny.py, палитра
# поля Хаоса) бродят вне боевой полосы, контура стены владений (с рядом цитадели) и клеток с постройками: стоят,
# потом идут на 1–3 соседние клетки своей местности. Время от времени двое из одной местности дерутся (решение
# пользователя: «периодически бьются друг с другом, к полю боя не приближаются, не умирают, просто расходятся»):
# один подходит к другому, обмен ударами по очереди (attack / hurt), потом оба расходятся. Только вид: в бою не
# участвуют, реестров нет, случайность своя (не seed забега). Тема расы — ключ "critters" {count}; по двое на
# местность (иначе не с кем драться); в y-sort контейнере бойцов (BattleScene._build_field).
#   SideCritters.spawn(контейнер, рендерер пола, сетка)

const DIR = "res://assets/sprites/critters/"
# Вид: кадр листа, ноги по x в кадре и рост фигурки в стойке (px листа — печатает critters_from_tiny.py),
# высота фигурки на поле (px мира — мельче бойца, TARGET_SPRITE_HEIGHT 31), скорость (px/с)
const KINDS = {
	"demon":         {"frame": Vector2i(160, 96), "feet_x": 52.0, "body": 80.0, "height": 17.0, "speed": 20.0},
	"blood_monster": {"frame": Vector2i(140, 112), "feet_x": 56.0, "body": 60.0, "height": 13.0, "speed": 14.0},
}
const ANIM_FPS = {"idle": 6.0, "walk": 10.0, "attack": 12.0, "hurt": 10.0}
const IDLE_TIME = Vector2(1.5, 5.0)     # сек стоит между переходами
const STEPS = Vector2i(1, 3)            # клеток за переход
const CELL_JITTER: float = 0.3          # доля клетки — точка внутри клетки
const MIN_AREA: int = 4                 # местность меньше — не заселять
const SHADOW = Color(0, 0, 0, 0.35)
# Драка: шанс после стоянки, перерыв существа после драки, до кого дойти (клеток пути), ударов на каждого,
# расстояние между дерущимися (px мира), пауза между ударами
const FIGHT_CHANCE: float = 0.3
const FIGHT_COOLDOWN = Vector2(10.0, 20.0)
const FIGHT_REACH: int = 4
const FIGHT_RUN: float = 2.2   # к сопернику — бегом (×скорость)
const FIGHT_ROUNDS = Vector2i(2, 3)
const FIGHT_GAP: float = 15.0
const FIGHT_PAUSE: float = 0.25
const FLOCK_PULL: float = 0.5   # доля переходов — к соседу по местности (пара держится рядом)

static var _frames: Dictionary = {}   # вид → SpriteFrames

static func spawn(container: Node, r: IsoGridRenderer, grid: IsoGrid) -> Array:
	var conf: Dictionary = r.theme.get("critters", {})
	var out: Array = []
	if conf.is_empty() or not _sheets_present():
		return out
	var areas := _areas(r, grid)
	if areas.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var kinds: Array = KINDS.keys()
	var flocks: Dictionary = {}   # номер местности → существа в ней (общий массив)
	for i in int(conf.get("count", 6)):
		var a: int = (i / 2) % areas.size()   # по двое на местность
		if not flocks.has(a):
			flocks[a] = []
		var c := Critter.new()
		c.flock = flocks[a]
		c.setup(kinds[i % kinds.size()], areas[a], grid, rng)
		flocks[a].append(c)
		container.add_child(c)
		out.append(c)
	return out

# Все листы всех видов на месте (нет хоть одного — существ нет, а не ошибка в frames_for)
static func _sheets_present() -> bool:
	for kind in KINDS:
		for anim in ANIM_FPS:
			if not ResourceLoader.exists(DIR + kind + "/" + anim + ".png"):
				return false
	return true

# Местности, где можно бродить: связные группы клеток вне боевой полосы, рамки королевства, цитадели, реки, края
# поля и полосы стены, без построек и анимированных деталей (руины, кристаллы, яма с глазами)
static func _areas(r: IsoGridRenderer, grid: IsoGrid) -> Array:
	var cells := r._floor_cells()
	var rivers := r._river_cells()
	var terrain := r._terrain_cells(cells, rivers)
	var ok := {}
	var wall := KingdomWall.contour(grid).grow(IsoGridRenderer.WALL_CLEAR)   # внутри стены владений — не бродят
	for c in cells:
		if wall.has_point(Vector2(c)) or r._is_battle_strip(c) or grid.is_in_bounds(c) or r._near_citadel(c) \
				or rivers.has(c) or r._is_floor_edge(c) or r._on_wall_line(c):
			continue
		var e = terrain[c][0] if terrain.has(c) else null
		if e is Dictionary and (e.has("prop") or e.has("frames")):
			continue
		ok[c] = true
	var areas: Array = []
	var seen := {}
	for c in ok:
		if seen.has(c):
			continue
		var area: Array = []
		var stack: Array = [c]
		seen[c] = true
		while not stack.is_empty():
			var x: Vector2i = stack.pop_back()
			area.append(x)
			for d in IsoGridRenderer.NEIGHBOURS:
				if ok.has(x + d) and not seen.has(x + d):
					seen[x + d] = true
					stack.append(x + d)
		if area.size() >= MIN_AREA:
			areas.append(area)
	areas.sort_custom(func(a, b): return a.size() > b.size())
	return areas

static func frames_for(kind: String) -> SpriteFrames:
	if _frames.has(kind):
		return _frames[kind]
	var size: Vector2i = KINDS[kind]["frame"]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim in ANIM_FPS:
		var sheet: Texture2D = load(DIR + kind + "/" + anim + ".png")
		sf.add_animation(anim)
		sf.set_animation_loop(anim, anim == "idle" or anim == "walk")
		sf.set_animation_speed(anim, ANIM_FPS[anim])
		for i in sheet.get_width() / size.x:
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(i * size.x, 0, size.x, size.y)
			sf.add_frame(anim, at)
	_frames[kind] = sf
	return sf

class Critter extends Node2D:
	enum State { IDLE, WALK, SEEK, WAIT_FOE, DUEL }
	var kind := ""
	var area: Array = []
	var area_set := {}
	var flock: Array = []       # существа той же местности
	var grid: IsoGrid
	var rng: RandomNumberGenerator
	var sprite := AnimatedSprite2D.new()
	var cell := Vector2i.ZERO
	var path: Array = []        # точки мира до цели
	var state := State.IDLE
	var wait := 0.0
	var speed := 20.0
	var shadow_r := 6.0
	var foe: Critter = null
	var fight_cooldown := 0.0
	var _duel_t := 0.0
	var _duel_events: Array = []   # [время, Callable] — ведёт тот, кто начал драку
	var _feet_shift := 0.0

	func setup(k: String, cells: Array, g: IsoGrid, random: RandomNumberGenerator) -> void:
		kind = k
		area = cells
		grid = g
		rng = random
		for c in area:
			area_set[c] = true
		var conf: Dictionary = SideCritters.KINDS[k]
		speed = conf["speed"] * rng.randf_range(0.85, 1.15)
		sprite.sprite_frames = SideCritters.frames_for(k)
		var frame: Vector2i = conf["frame"]
		var s: float = conf["height"] / conf["body"]
		sprite.scale = Vector2(s, s)
		_feet_shift = frame.x / 2.0 - conf["feet_x"]   # фигурка не в центре кадра (удар шире стойки)
		sprite.offset = Vector2(_feet_shift, -frame.y / 2.0)   # ноги — в точке узла
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		shadow_r = conf["height"] * 0.35
		add_child(sprite)
		cell = area[rng.randi() % area.size()]
		position = _point_in(cell)
		wait = rng.randf_range(0.0, IDLE_TIME.y)
		fight_cooldown = rng.randf_range(0.0, FIGHT_COOLDOWN.x)
		_face(rng.randf() < 0.5)
		sprite.play("idle")
		sprite.frame = rng.randi() % sprite.sprite_frames.get_frame_count("idle")

	# Лист смотрит вправо; отражение — вокруг ног (смещение фигурки в кадре тоже отражается)
	func _face(left: bool) -> void:
		sprite.flip_h = left
		sprite.offset.x = -_feet_shift if left else _feet_shift

	func _point_in(c: Vector2i) -> Vector2:
		return grid.lattice_to_screen(c.x + rng.randf_range(-CELL_JITTER, CELL_JITTER),
			c.y + rng.randf_range(-CELL_JITTER, CELL_JITTER))   # центр грани клетки (как рисует пол)

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, shadow_r, SHADOW)
		draw_set_transform(Vector2.ZERO)

	func _process(delta: float) -> void:
		fight_cooldown -= delta
		match state:
			State.IDLE:
				wait -= delta
				if wait <= 0.0 and not _try_fight():
					_plan()
			State.WALK, State.SEEK:
				_walk(delta)
			State.WAIT_FOE:
				if not is_instance_valid(foe):   # тот, кто шёл драться, пропал — не ждать вечно
					foe = null
					_rest()
			State.DUEL:
				_duel_t += delta
				while not _duel_events.is_empty() and _duel_t >= _duel_events[0][0]:
					var ev: Array = _duel_events.pop_front()
					ev[1].call()

	func _walk(delta: float) -> void:
		var to: Vector2 = path[0]
		var step := speed * delta * (FIGHT_RUN if state == State.SEEK else 1.0)
		var d := to - position
		if absf(d.x) > 0.5:
			_face(d.x < 0.0)
		if d.length() > step:
			position += d / d.length() * step
			return
		position = to
		path.pop_front()
		if not path.is_empty():
			return
		if state == State.SEEK:
			_start_duel()
		else:
			_rest()

	func _rest() -> void:
		state = State.IDLE
		sprite.play("idle")
		wait = rng.randf_range(IDLE_TIME.x, IDLE_TIME.y)

	# Переход: 1–3 шага по соседним клеткам своей местности (не срезает через постройки);
	# away — расходятся после драки: каждый шаг — дальше всего от этой точки
	func _plan(away := Vector2.INF) -> void:
		var n := rng.randi_range(STEPS.x, STEPS.y)
		# Пара держится рядом (FLOCK_PULL переходов — к соседу по местности): иначе в большой местности двое почти не
		# сходились бы на FIGHT_REACH и не дрались
		var mate: Critter = null
		if away == Vector2.INF and rng.randf() < FLOCK_PULL:
			for o in flock:
				if o != self and is_instance_valid(o):
					mate = o
					break
		for i in n:
			var options: Array = []
			for d in IsoGridRenderer.NEIGHBOURS:
				if area_set.has(cell + d):
					options.append(cell + d)
			if options.is_empty():
				break
			if away != Vector2.INF:
				var far: Vector2i = options[0]
				for o in options:
					if grid.lattice_to_screen(o.x, o.y).distance_to(away) > grid.lattice_to_screen(far.x, far.y).distance_to(away):
						far = o
				cell = far
			elif mate and (cell - mate.cell).length_squared() > 4:
				var near: Vector2i = options[0]
				for o in options:
					if (o - mate.cell).length_squared() < (near - mate.cell).length_squared():
						near = o
				cell = near
			else:
				cell = options[rng.randi() % options.size()]
			path.append(_point_in(cell))
		if path.is_empty():
			_rest()
		else:
			state = State.WALK
			sprite.play("walk")

	# Драка: свободное существо своей местности не дальше FIGHT_REACH клеток пути — оно ждёт, этот идёт к нему
	func _try_fight() -> bool:
		if fight_cooldown > 0.0 or rng.randf() >= FIGHT_CHANCE:
			return false
		for other in flock:
			if other == self or not is_instance_valid(other) or other.state != State.IDLE or other.fight_cooldown > 0.0:
				continue
			var route := _route_to_neighbour(other.cell)
			if route.is_empty() or route.size() > FIGHT_REACH:
				continue
			foe = other
			other.foe = self
			other.state = State.WAIT_FOE
			other.sprite.play("idle")
			path.clear()
			for c in route:
				path.append(_point_in(c))
			cell = route[-1]
			var side := 1.0 if path[-1].x >= other.position.x else -1.0
			path[-1] = other.position + Vector2(side * FIGHT_GAP, 0.0)   # встать сбоку, лицом к нему
			state = State.SEEK
			sprite.play("walk")
			sprite.speed_scale = FIGHT_RUN
			return true
		return false

	# Путь по клеткам местности до соседней с целью (поиск в ширину); [] — не дойти
	func _route_to_neighbour(target: Vector2i) -> Array:
		var prev := {cell: cell}
		var queue: Array = [cell]
		while not queue.is_empty():
			var c: Vector2i = queue.pop_front()
			if (c - target).length_squared() == 1:
				var route: Array = []
				while c != cell:
					route.push_front(c)
					c = prev[c]
				return route if not route.is_empty() else [cell]
			for d in IsoGridRenderer.NEIGHBOURS:
				var n: Vector2i = c + d
				if area_set.has(n) and not prev.has(n) and n != target:
					prev[n] = c
					queue.append(n)
		return []

	# Обмен ударами по очереди: удар — у соперника «больно» на середине замаха; потом оба расходятся
	func _start_duel() -> void:
		sprite.speed_scale = 1.0   # бежал к сопернику
		if not is_instance_valid(foe):
			_rest()
			return
		state = State.DUEL
		foe.state = State.DUEL
		_face(foe.position.x < position.x)
		foe._face(position.x < foe.position.x)
		sprite.play("idle")
		_duel_t = 0.0
		_duel_events.clear()
		var t := FIGHT_PAUSE
		var pair: Array = [self, foe]
		for k in rng.randi_range(FIGHT_ROUNDS.x, FIGHT_ROUNDS.y) * 2:
			var hitter: Critter = pair[k % 2]
			var target: Critter = pair[(k + 1) % 2]
			var swing: float = hitter.sprite.sprite_frames.get_frame_count("attack") / SideCritters.ANIM_FPS["attack"]
			_duel_events.append([t, hitter.sprite.play.bind("attack")])
			_duel_events.append([t + swing * 0.55, target.sprite.play.bind("hurt")])
			_duel_events.append([t + swing, _both_idle])
			t += swing + FIGHT_PAUSE
		_duel_events.append([t, _end_duel])

	func _both_idle() -> void:
		sprite.play("idle")
		if is_instance_valid(foe):
			foe.sprite.play("idle")

	# Расходятся: каждый — на 1–3 клетки прочь от соперника, перерыв до следующей драки
	func _end_duel() -> void:
		var other := foe
		var me_at := position
		var other_at := other.position if is_instance_valid(other) else position
		for pair in [[self, other_at], [other, me_at]]:
			var c: Critter = pair[0]
			if not is_instance_valid(c):
				continue
			c.foe = null
			c._duel_events.clear()
			c.fight_cooldown = c.rng.randf_range(FIGHT_COOLDOWN.x, FIGHT_COOLDOWN.y)
			c.path.clear()
			c._plan(pair[1])
