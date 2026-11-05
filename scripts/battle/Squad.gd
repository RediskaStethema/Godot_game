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

# Строй как в 9 Kings: шеренги вдоль осей изометрии, фронт смотрит на врага.
# Шеренга (до FORMATION_MAX_RANK бойцов) — вдоль оси row, ряды уходят в тыл
# вдоль оси наступления. Первый ряд — ближе к противнику.
const FORMATION_MAX_RANK: int = 5   # 15 бойцов — 3 ряда по 5
# 23.10.2026 (решение пользователя: бойцы сливались в одно пятно) — было 14 / 12
const RANK_SPACING: float = 18.0   # между бойцами в шеренге, px
const FILE_SPACING: float = 15.0   # между рядами, px

func _get_formation_offsets(count: int) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	var cols = min(count, FORMATION_MAX_RANK)
	var rows = int(ceil(float(count) / cols))
	var rank_dir = IsoGrid.rank_direction()
	# Игрок наступает вдоль +advance, враг — навстречу
	var forward = IsoGrid.advance_direction() * (1.0 if team == GameConstants.TEAM_PLAYER else -1.0)

	for i in range(count):
		var col = i % cols
		var row = i / cols
		# Неполный последний ряд центрируем
		var in_row = cols if row < rows - 1 else count - row * cols
		var along_rank = (col - (in_row - 1) / 2.0) * RANK_SPACING
		var depth = ((rows - 1) / 2.0 - row) * FILE_SPACING   # row 0 — впереди
		offsets.append(rank_dir * along_rank + forward * depth)

	return offsets

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
const DEEP_STRIKE_ORIGIN_POOF: float = 2.5    # облачко на месте отряда — во столько раз крупнее
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
	# Облачко — у каждого бойца на месте высадки и одно крупное там, откуда отряд исчез
	# (по облачку на бойца с обеих сторон — 24 эффекта в один тик, выброс тика)
	var size: float = data.sprite_scale * Soldier.EFFECT_SCALE
	Vfx.spawn(get_parent(), "poof", center, size * DEEP_STRIKE_ORIGIN_POOF)
	for s in alive:
		s.teleport_to(anchor + s.formation_offset)
		Vfx.spawn(get_parent(), "poof", s.global_position, size)
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
# ПОРАБОЩЕНИЕ (благословение Слаанеш, Soldier.charm)
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
		# Свой отряд пал целиком — надпись над местом гибели последнего бойца (только вид)
		if team == GameConstants.TEAM_PLAYER and BattleManager.is_battle_running():
			FloatingText.spawn(get_parent(), soldier.global_position + Vector2(0.0, -Soldier.TARGET_SPRITE_HEIGHT * 1.5),
				"%s пал" % data.unit_name, Soldier.FLOAT_HIT_TO_PLAYER, 0.9, true)
			Vfx.spawn(get_parent(), "squad_lost", soldier.global_position)   # сломанное знамя и черепа
		emit_signal("squad_wiped", self)

# -------------------------------------------------------
# УТИЛИТЫ
# -------------------------------------------------------
func is_alive() -> bool:
	return current_state != State.DEAD
