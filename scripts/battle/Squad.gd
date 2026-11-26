class_name Squad
extends Node2D

# -------------------------------------------------------
# СОСТОЯНИЯ ОТРЯДА
# -------------------------------------------------------
enum State { IDLE, MARCHING, FIGHTING, DEAD }

# -------------------------------------------------------
# ДАННЫЕ
# -------------------------------------------------------
var data: UnitData           # тип юнита в отряде
var team: int
var tile: Vector2i           # позиция на сетке
var soldiers: Array[Soldier] = []
var current_state: State = State.IDLE

signal squad_wiped(squad: Squad)  # все бойцы мертвы

# -------------------------------------------------------
# СЦЕНА БОЙЦА
# -------------------------------------------------------
# Боец — это отдельная сцена с AnimatedSprite2D
const SOLDIER_SCENE = preload("res://scenes/battle/Soldier.tscn")

# -------------------------------------------------------
# ИНИЦИАЛИЗАЦИЯ
# -------------------------------------------------------
# hp_list — доли HP выживших бойцов (пустой = все с полным HP)
# kinds — тип каждого бойца (UnitData.saved_kinds): "" — свой, иначе боец бога Хаоса на месте павшего
func setup(unit_data: UnitData, team_id: int, grid_tile: Vector2i, count: int, hp_list: Array[float] = [],
		kinds: Array[String] = []) -> void:
	data = unit_data
	team = team_id
	tile = grid_tile
	# Бойцы участвуют в общей сортировке по глубине (Units.y_sort_enabled)
	y_sort_enabled = true

	# Спавним бойцов в строю на клетке
	_spawn_soldiers(count, hp_list, kinds)
	# Полоска HP отряда над бойцами (у самих бойцов полосок нет)
	var bar := SquadBar.new()
	bar.squad = self
	add_child(bar)

func _spawn_soldiers(count: int, hp_list: Array[float], kinds: Array[String] = []) -> void:
	# Вычисляем смещения для строя на клетке
	# Бойцы расставляются в небольшой сетке внутри тайла
	var offsets = _get_formation_offsets(count)

	for i in range(count):
		var hp_ratio: float = hp_list[i] if i < hp_list.size() else 1.0
		_add_soldier(offsets[i], hp_ratio, kinds[i] if i < kinds.size() else "")

func _add_soldier(offset: Vector2, hp_ratio: float, kind: String = "") -> void:
	var soldier = SOLDIER_SCENE.instantiate()
	add_child(soldier)
	soldier.convert_kind = kind
	soldier.setup(UnitFactory.convert_fighter(kind) if kind != "" else data, team, self, offset, hp_ratio)
	soldier.position = offset
	soldier.died.connect(_on_soldier_died)
	soldiers.append(soldier)
	SoldierRegistry.register(soldier)

# Перестроить строй под текущее число бойцов (после возвращения павших)
func _reform() -> void:
	var offsets = _get_formation_offsets(soldiers.size())
	for i in range(soldiers.size()):
		soldiers[i].formation_offset = offsets[i]
		soldiers[i].position = offsets[i]

# Строй под размер модели (решение пользователя 11.11.2026, `Screenshot 2026-11-11 114144.png`: крупные бойцы
# вылезали на соседние клетки и стояли друг на друге — шаг был один на всех, 18×15 px по осям изометрии, и боец
# (ряд+1, шеренга+1) вставал ровно над соседом). Теперь — решётка кирпичом в экранных координатах: шаг по x —
# ширина модели на экране (соседи в ряду не накрывают друг друга), по y — половина (изометрия 2:1), ряды со сдвигом
# на полшага; ноги всех бойцов — внутри ромба своей клетки. Не влезают — шаг меньше, но наружу клетки строй не выходит.
const FORMATION_FILL: float = 0.85        # доля ромба клетки под ноги (запас до кромки)
const FORMATION_GAP: float = 1.5          # шаг в ряду, в ширинах модели (свободно; не влезают — теснее)
const FORMATION_ROW_RATIO: float = 0.5    # шаг рядов от шага в ряду
const FORMATION_BODY_INSET: float = 0.3   # ромб ног уже по x на эту долю ширины модели — тело не за кромкой
const FORMATION_SHRINK: float = 0.92      # шаг ×, пока точек меньше, чем бойцов
const FORMATION_MIN_STEP: float = 0.4     # не теснее этой доли ширины
const MODEL_WIDTH_FALLBACK: float = 0.6   # ширина без листа — доля роста
static var _width_cache: Dictionary = {}  # sprite_path → ширина фигуры / рост (кадр idle 0)

# Ширина модели на экране, px мира (непрозрачная часть кадра стойки, рост — как в Soldier._load_animations)
static func model_width(unit: UnitData) -> float:
	var height := Soldier.TARGET_SPRITE_HEIGHT * unit.sprite_scale
	var path := unit.sprite_path
	if not _width_cache.has(path):
		var ratio := MODEL_WIDTH_FALLBACK
		var frames: SpriteFrames = Soldier._get_frames(path) if path != "" else null
		if frames and frames.has_animation("idle") and frames.get_frame_count("idle") > 0:
			var tex := frames.get_frame_texture("idle", 0)
			var img := tex.get_image() if tex else null
			if img:
				var used := img.get_used_rect()
				var fig_h := float(frames.get_meta("figure_height", img.get_height()))
				if used.size.x > 0 and fig_h > 0.0:
					ratio = used.size.x / fig_h
		_width_cache[path] = ratio
	return _width_cache[path] * height

func _get_formation_offsets(count: int) -> Array[Vector2]:
	# Игрок наступает вдоль +advance, враг — навстречу
	var forward = IsoGrid.advance_direction() * (1.0 if team == GameConstants.TEAM_PLAYER else -1.0)
	return formation_offsets(count, model_width(data), forward)

# Ноги внутри ромба клетки (с запасом FORMATION_FILL; по x уже на часть ширины тела)
static func formation_half_size(width: float) -> Vector2:
	var hw := maxf(IsoGrid.TILE_WIDTH / 2.0 * FORMATION_FILL - width * FORMATION_BODY_INSET, IsoGrid.TILE_WIDTH * 0.15)
	return Vector2(hw, IsoGrid.TILE_HEIGHT / 2.0 * FORMATION_FILL)

static func _in_diamond(p: Vector2, half: Vector2) -> bool:
	return absf(p.x) / half.x + absf(p.y) / half.y <= 1.0 + 0.0001

# Строй из count бойцов шириной width (px мира); первый — ближе всех к врагу (forward — куда наступает отряд)
static func formation_offsets(count: int, width: float, forward: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if count <= 0:
		return result
	if count == 1:
		result.append(Vector2.ZERO)
		return result
	var half := formation_half_size(width)
	var dx := width * FORMATION_GAP
	var points: Array[Vector2] = []
	while true:
		points = _diamond_lattice(dx, dx * FORMATION_ROW_RATIO, half)
		if points.size() >= count or dx <= width * FORMATION_MIN_STEP:
			break
		dx = maxf(dx * FORMATION_SHRINK, width * FORMATION_MIN_STEP)
	# Ближние к центру (метрика ромба), при равенстве — порядок решётки (детерминированно)
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var da := absf(a.x) / half.x + absf(a.y) / half.y
		var db := absf(b.x) / half.x + absf(b.y) / half.y
		if absf(da - db) > 0.0001:
			return da < db
		return a.y < b.y if absf(a.y - b.y) > 0.0001 else a.x < b.x)
	var picked: Array[Vector2] = points.slice(0, mini(count, points.size()))
	while picked.size() < count:   # тесно даже на минимальном шаге (не бывает у отрядов игры) — в центр
		picked.append(Vector2.ZERO)
	# Строй — в центр клетки, если после сдвига все ноги внутри ромба
	var centroid := Vector2.ZERO
	for p in picked:
		centroid += p
	centroid /= picked.size()
	if picked.all(func(p: Vector2) -> bool: return _in_diamond(p - centroid, half)):
		for i in picked.size():
			picked[i] -= centroid
	# Первый ряд — к врагу, при равенстве — по оси шеренги
	var rank_dir := IsoGrid.rank_direction()
	picked.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var fa := a.dot(forward)
		var fb := b.dot(forward)
		if absf(fa - fb) > 0.5:
			return fa > fb
		return a.dot(rank_dir) < b.dot(rank_dir))
	return picked

# Точки решётки кирпичом (ряд через один сдвинут на dx/2) внутри ромба half
static func _diamond_lattice(dx: float, dy: float, half: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var rows := int(half.y / dy)
	for j in range(-rows, rows + 1):
		var shift := dx * 0.5 if absi(j) % 2 == 1 else 0.0
		var cols := int(half.x / dx) + 1
		for i in range(-cols, cols + 1):
			var p := Vector2(i * dx + shift, j * dy)
			if _in_diamond(p, half):
				points.append(p)
	return points

# -------------------------------------------------------
# ГЛАВНЫЙ ТИК
# -------------------------------------------------------
func tick(delta: float) -> void:
	if data.deep_strike_delay > 0.0 and not deep_struck and current_state == State.MARCHING:
		_tick_deep_strike(delta)
	match current_state:
		State.IDLE:     pass
		State.MARCHING: _tick_marching(delta)
		State.FIGHTING: _tick_fighting(delta)
		State.DEAD:     pass

func _tick_marching(delta: float) -> void:
	_tick_soldiers(delta)

	# Если хоть один боец вступил в бой — переходим в FIGHTING
	for soldier in soldiers:
		if soldier.current_state == Soldier.State.ATTACK:
			current_state = State.FIGHTING
			return

func _tick_fighting(delta: float) -> void:
	_tick_soldiers(delta)

func _tick_soldiers(delta: float) -> void:
	enemy_out_of_sight = _no_enemy_in_sight()
	# Копия: боец может погибнуть в своём же тике (яд, огонь) и выйти из soldiers
	for soldier in soldiers.duplicate():
		if soldier.current_state != Soldier.State.DEAD:
			soldier.tick(delta)
	enemy_out_of_sight = false   # только на время тика отряда: вне его бойцы спрашивают сами

# Поле зрения на марше (Soldier._state_move) — один запрос на отряд вместо запроса каждого бойца:
# врага нет ближе vision_range + радиус строя от центра идущих — его нет ни у одного из них
# (неравенство треугольника). На сближении армий сотни запросов за тик давали выброс до 15 мс
var enemy_out_of_sight: bool = false

func _no_enemy_in_sight() -> bool:
	var center := Vector2.ZERO
	var walking := 0
	for s in soldiers:
		if s.current_state == Soldier.State.MOVE:
			center += s.global_position
			walking += 1
	if walking < 2:
		return false   # одному бойцу проверка отряда ничего не сберегает
	center /= walking
	var radius := 0.0
	for s in soldiers:
		if s.current_state == Soldier.State.MOVE:
			radius = maxf(radius, center.distance_to(s.global_position))
	return SoldierRegistry.find_nearest(1 - team, center, data.vision_range + radius) == null

# -------------------------------------------------------
# КОМАНДЫ ОТ BATTLEMANAGER
# -------------------------------------------------------

# Бой начался — бойцы выдвигаются вперёд
func start_march() -> void:
	current_state = State.MARCHING
	for soldier in soldiers:
		soldier.transition_to(Soldier.State.MOVE)

# -------------------------------------------------------
# DEEP STRIKE (Terminator, UnitData.deep_strike_delay; решение пользователя 17.10.2026)
# -------------------------------------------------------
# Через deep_strike_delay сек марша отряд телепортируется строем к ближайшему врагу —
# на дальность удара + DEEP_STRIKE_GAP перед ним, со своей стороны. Раз за бой
const DEEP_STRIKE_GAP: float = 30.0
const DEEP_STRIKE_MIN_DIST: float = 150.0   # враг уже ближе — телепорт не нужен
const FALL_SHAKE: float = 2.0                # px — толчок камеры, когда свой отряд пал
const FALL_RING_RADIUS: float = 26.0         # px мира — кольцо «отряд пал» (× sprite_scale)
var deep_struck: bool = false
var _deep_strike_timer: float = 0.0

func _tick_deep_strike(delta: float) -> void:
	_deep_strike_timer += delta
	if _deep_strike_timer < data.deep_strike_delay - Soldier.TIMER_EPSILON:
		return
	var alive := soldiers.filter(func(s): return s.current_state != Soldier.State.DEAD)
	if alive.is_empty():
		deep_struck = true
		return
	var center := Vector2.ZERO
	for s in alive:
		center += s.global_position
	center /= alive.size()
	var foe := SoldierRegistry.find_nearest(1 - team, center)
	if foe == null:
		return   # врагов ещё нет — ждём
	deep_struck = true
	var back := (center - foe.global_position).normalized()
	var anchor := foe.global_position + back * (data.attack_range + DEEP_STRIKE_GAP)
	if center.distance_to(anchor) < DEEP_STRIKE_MIN_DIST:
		return
	# Телепорт — лист художника (EFFECTS_NEEDED 5.3, решение пользователя 09.11.2026; до того — полосы кодом
	# BuildingFx.teleport, ещё раньше — облачка poof): на месте ухода лист задом наперёд, на месте высадки — вперёд
	var size: float = data.sprite_scale * Soldier.EFFECT_SCALE
	for s in alive:
		Vfx.spawn_reversed(get_parent(), "teleport", s.global_position, size)
		s.teleport_to(anchor + s.formation_offset)
		Vfx.spawn(get_parent(), "teleport", s.global_position, size)
		DustLayer.puff(s.global_position, 7.0 * s.data.sprite_scale, 2, 5.0)
	SoldierRegistry.invalidate_grid()   # сдвиг больше GRID_SLACK за тик
	AudioManager.play("deep_strike")

# Карта-улучшение брошена на этот отряд: множители в data (живут между
# раундами), живым бойцам пересчитываем статы сразу
func apply_upgrade(card: CardData) -> bool:
	if not data.can_apply_upgrade(card):
		return false
	data.apply_upgrade(card)
	for soldier in soldiers:
		soldier.refresh_stats_from_data()
	SoldierRegistry.mark_dirty()   # знамя — новый носитель ауры в кэше реестра
	return true

# Карта того же отряда → улучшение (до UnitFactory.MAX_SQUAD_LEVEL раз)
func merge_upgrade() -> bool:
	if not data.can_merge_upgrade():
		return false
	data.apply_merge_upgrade()
	for soldier in soldiers:
		soldier.refresh_stats_from_data()
	# Уровень пехоты добавляет бойцов (UnitData.squad_growth) — новички с полным HP
	for i in range(data.squad_growth):
		_add_soldier(Vector2.ZERO, 1.0)
	if data.squad_growth > 0:
		_reform()
	# Свет уровня на каждом бойце (и на новичках) — волной по строю
	for i in soldiers.size():
		LevelUpGlow.play(soldiers[i], data.squad_level, float(i) / maxf(soldiers.size() - 1, 1.0))
	return true

# Карта того же отряда → лечение: каждому живому бойцу доля его максимального HP,
# павшие (до полного состава data.squad_size) возвращаются с той же долей HP.
# Возвращает, сколько бойцов вернулось.
func heal_by_ratio(ratio: float) -> int:
	for soldier in soldiers:
		soldier.heal(soldier.max_hp * ratio)
	var missing = get_missing_count()
	for i in range(missing):
		_add_soldier(Vector2.ZERO, ratio)
	if missing > 0:
		_reform()
	return missing

func get_missing_count() -> int:
	return max(data.squad_size - soldiers.size(), 0)

func is_wounded() -> bool:
	if get_missing_count() > 0:
		return true
	for soldier in soldiers:
		if soldier.current_hp < soldier.max_hp:
			return true
	return false

# -------------------------------------------------------
# ПОРАБОЩЕНИЕ (благословение Короля Второго Акта, Soldier.charm)
# -------------------------------------------------------
# Боец уходит из отряда: последний ушёл — отряд пал (бой кончается, когда у стороны нет отрядов)
func release_soldier(soldier: Soldier) -> void:
	if soldier.died.is_connected(_on_soldier_died):
		soldier.died.disconnect(_on_soldier_died)
	soldiers.erase(soldier)
	if soldiers.is_empty() and current_state != State.DEAD:
		current_state = State.DEAD
		emit_signal("squad_wiped", self)

# Порабощённый боец бьётся в этом отряде до конца боя (тикает с ним; в армию не сохраняется — charmed)
func adopt_soldier(soldier: Soldier) -> void:
	soldiers.append(soldier)
	soldier.died.connect(_on_soldier_died)

# -------------------------------------------------------
# СМЕРТЬ БОЙЦОВ
# -------------------------------------------------------
func _on_soldier_died(soldier: Soldier) -> void:
	soldiers.erase(soldier)

	# Если все бойцы мертвы — отряд уничтожен
	if soldiers.is_empty():
		current_state = State.DEAD
		# Отряд пал целиком (решение пользователя 09.11.2026): кольцо цвета стороны по земле и пыль — обе стороны
		if BattleManager.is_battle_running():
			BuildingFx.squad_fall(soldier.global_position, FALL_RING_RADIUS * data.sprite_scale,
				team == GameConstants.TEAM_PLAYER)
			if team == GameConstants.TEAM_PLAYER and is_inside_tree():   # свой отряд пал — короткий толчок
				var cam := get_viewport().get_camera_2d()
				if cam and cam.has_method("shake"):
					cam.shake(FALL_SHAKE)
		# Свой отряд пал целиком — надпись над местом гибели последнего бойца (только вид)
		if team == GameConstants.TEAM_PLAYER and BattleManager.is_battle_running():
			FloatingText.spawn(get_parent(), soldier.global_position + Vector2(0.0, -Soldier.TARGET_SPRITE_HEIGHT * 1.5),
				"%s пал" % data.display_name(), Soldier.FLOAT_HIT_TO_PLAYER, 0.9, true)
			Vfx.spawn(get_parent(), "squad_lost", soldier.global_position)   # сломанное знамя и черепа
		emit_signal("squad_wiped", self)

# -------------------------------------------------------
# УТИЛИТЫ
# -------------------------------------------------------
func is_alive() -> bool:
	return current_state != State.DEAD
