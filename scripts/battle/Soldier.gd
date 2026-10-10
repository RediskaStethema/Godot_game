class_name Soldier
extends Node2D

# -------------------------------------------------------
# СОСТОЯНИЯ
# -------------------------------------------------------
enum State { IDLE, MOVE, CHASE, ATTACK, CASTING, STUNNED, KNOCKBACK, RETREATING, DEAD }

# Затухание отбрасывания, пикселей/сек²
const KNOCKBACK_FRICTION: float = 600.0
# Ниже этой скорости отбрасывание считается законченным
const KNOCKBACK_STOP_SPEED: float = 5.0
# Высота бойца на экране (px) при sprite_scale = 1. Тайл — 128×64,
# спрайты разного исходного размера (marine 197 px, chaos 170 px) приводим к одной высоте.
const TARGET_SPRITE_HEIGHT: float = 62.0
const HP_BAR_SIZE = Vector2(26, 4)
const SHIELD_BAR_COLOR = Color(0.45, 0.75, 1.0)
const HP_BAR_GAP: float = 6.0
const LEVEL_PIP_R: float = 3.0
const LEVEL_PIP_STEP: float = 8.0
const LEVEL_PIP_GAP: float = 5.0
# Таймеры уменьшаются на 0.1 — из-за погрешности float 1.0 - 10*0.1 != 0
const TIMER_EPSILON: float = 0.001

# -------------------------------------------------------
# ДАННЫЕ
# -------------------------------------------------------
var data: UnitData          # данные типа юнита (общие для всего отряда)
var team: int
# Runtime-статы: инициализируются из data, синергии меняют только их
var current_hp: float
var max_hp: float
var current_damage: float
var current_move_speed: float
# Щит Iron Halo на этот бой: снимается уроном раньше HP (runtime, из data.shield_ratio)
var shield: float = 0.0
var has_revived: bool = false   # Apothecarion поднимает бойца не больше раза за бой
var current_attack_range: float
var current_attack_speed: float
var current_heal_per_second: float
var target: Soldier = null  # цель — другой боец
var parent_squad: Squad     # отряд которому принадлежит боец

var current_state: State = State.IDLE
var previous_state: State = State.IDLE
var attack_timer: float = 0.0
var cast_timer: float = 0.0
var stun_timer: float = 0.0
var retreat_timer: float = 0.0
var has_retreated: bool = false   # отступаем максимум один раз за бой
var knockback_velocity: Vector2 = Vector2.ZERO

# Позиция в строю — смещение относительно центра отряда
var formation_offset: Vector2 = Vector2.ZERO

@onready var sprite: AnimatedSprite2D = $Sprite

signal died(soldier: Soldier)

# -------------------------------------------------------
# ИНИЦИАЛИЗАЦИЯ
# -------------------------------------------------------
# start_hp_ratio — доля HP: 1.0 свежий боец, меньше — раненый выживший
func setup(unit_data: UnitData, team_id: int, squad: Squad, offset: Vector2, start_hp_ratio: float = 1.0) -> void:
	data = unit_data
	team = team_id
	parent_squad = squad
	max_hp = data.get_max_hp()
	current_damage = data.get_damage()
	current_hp = max_hp * clampf(start_hp_ratio, 0.01, 1.0)
	current_move_speed = data.get_move_speed()
	shield = max_hp * data.shield_ratio
	current_attack_range = data.attack_range
	current_attack_speed = data.get_attack_speed()
	current_heal_per_second = data.heal_per_second
	formation_offset = offset
	attack_timer = 0.0
	current_state = State.IDLE
	previous_state = State.IDLE
	has_retreated = false
	has_revived = false

	_load_animations()

	# Враги смотрят влево
	if team == GameConstants.TEAM_ENEMY:
		sprite.flip_h = true

# -------------------------------------------------------
# АНИМАЦИИ
# -------------------------------------------------------
# Анимация → подпапка спрайтов. Кадры: <sprite_path>/<папка>/0.png, 1.png, ...
const ANIMATION_FOLDERS = {"idle": "idle", "walk": "run", "attack": "attack", "death": "death"}
const ANIMATION_FPS: float = 8.0
# Набор кадров на папку спрайтов собирается один раз и общий для всех бойцов
# этого вида (раньше — заново на каждого бойца, с проверкой файлов на диске)
static var _frames_cache: Dictionary = {}   # sprite_path → SpriteFrames

static func _get_frames(sprite_path: String) -> SpriteFrames:
	if _frames_cache.has(sprite_path):
		return _frames_cache[sprite_path]
	var frames = SpriteFrames.new()
	frames.remove_animation("default")
	for anim_name in ANIMATION_FOLDERS:
		var folder = sprite_path + "/" + ANIMATION_FOLDERS[anim_name] + "/"
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, anim_name != "attack" and anim_name != "death")
		frames.set_animation_speed(anim_name, ANIMATION_FPS)
		var i = 0
		while ResourceLoader.exists(folder + str(i) + ".png"):
			frames.add_frame(anim_name, load(folder + str(i) + ".png"))
			i += 1
	_frames_cache[sprite_path] = frames
	return frames

func _load_animations() -> void:
	var frames = _get_frames(data.sprite_path)
	sprite.sprite_frames = frames
	# Масштаб по высоте первого кадра idle — все юниты одного роста,
	# sprite_scale делает Терминатора крупнее, а скаута мельче
	var base_h = TARGET_SPRITE_HEIGHT
	if frames.get_frame_count("idle") > 0:
		base_h = frames.get_frame_texture("idle", 0).get_height()
	var k = TARGET_SPRITE_HEIGHT / base_h * data.sprite_scale
	sprite.scale = Vector2(k, k)
	# Ноги — в точке бойца (стоит на тайле, а не висит центром над ним)
	sprite.offset = Vector2(0, -base_h / 2.0)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.modulate = data.tint
	queue_redraw()
	sprite.play("idle")

func _play_animation(anim_name: String) -> void:
	if sprite.animation != anim_name:
		sprite.play(anim_name)

# -------------------------------------------------------
# ГЛАВНЫЙ ТИК
# -------------------------------------------------------
func tick(delta: float) -> void:
	_tick_support(delta)
	match current_state:
		State.IDLE:       _state_idle()
		State.MOVE:       _state_move(delta)
		State.CHASE:      _state_chase(delta)
		State.ATTACK:     _state_attack(delta)
		State.CASTING:    _state_casting(delta)
		State.STUNNED:    _state_stunned(delta)
		State.KNOCKBACK:  _state_knockback(delta)
		State.RETREATING: _state_retreating(delta)
		State.DEAD:       pass

# -------------------------------------------------------
# СОСТОЯНИЯ
# -------------------------------------------------------
func _state_idle() -> void:
	# В IDLE просто ждём команды от Squad
	pass

# Идём в сторону вражеской армии, пока кто-то не попадёт в поле зрения
func _state_move(delta: float) -> void:
	var enemies = SoldierRegistry.get_alive_soldiers_of_team(1 - team)
	if enemies.is_empty():
		if _is_sieging():
			_march_on_citadel(delta)
		else:
			_play_animation("idle")
		return

	var nearest = _get_nearest(enemies)
	if global_position.distance_squared_to(nearest.global_position) <= data.vision_range * data.vision_range:
		target = _find_target()
		transition_to(State.CHASE)
		return

	var center = SoldierRegistry.get_team_center(1 - team)
	# Марш строем (как в 9 Kings): цель каждого бойца — центр врага + его
	# смещение в строю, поэтому весь отряд идёт параллельно, не сбиваясь в кучу.
	# Строй рассыпается только в CHASE, когда враг в поле зрения.
	_move_towards(center + formation_offset, delta)

# -------------------------------------------------------
# ШТУРМ ЦИТАДЕЛИ — армия игрока пала, враги бьются с цитаделью
# -------------------------------------------------------
func _is_sieging() -> bool:
	return team == GameConstants.TEAM_ENEMY and BattleManager.has_citadel() \
		and BattleManager.citadel_hp > 0.0 \
		and SoldierRegistry.get_alive_soldiers_of_team(1 - team).is_empty()

func _citadel_in_range() -> bool:
	return global_position.distance_to(BattleManager.citadel.global_position) \
		<= current_attack_range + Citadel.HIT_RADIUS

func _march_on_citadel(delta: float) -> void:
	if _citadel_in_range():
		transition_to(State.ATTACK)
	else:
		_move_towards(BattleManager.citadel.global_position, delta)

# ATTACK по цитадели: тот же таймер и урон, что по бойцам
func _attack_citadel(delta: float) -> void:
	var citadel = BattleManager.citadel
	if not _citadel_in_range():
		transition_to(State.MOVE)
		return
	_face(citadel.global_position - global_position)
	attack_timer -= delta
	if attack_timer <= TIMER_EPSILON:
		attack_timer = 1.0 / current_attack_speed
		citadel.take_hit(_roll_damage())
		sprite.stop()
		sprite.play("attack")

# Преследуем конкретную цель до дальности атаки
func _state_chase(delta: float) -> void:
	if not _has_valid_target():
		target = _find_target()
		if not target:
			transition_to(State.MOVE)
			return

	if global_position.distance_to(target.global_position) <= current_attack_range:
		transition_to(State.ATTACK)
	else:
		_move_towards(target.global_position, delta)

func _state_attack(delta: float) -> void:
	if _is_sieging():
		_attack_citadel(delta)
		return
	if not _has_valid_target():
		target = _find_target()
		if not target:
			transition_to(State.MOVE)
			return

	if global_position.distance_to(target.global_position) > current_attack_range:
		transition_to(State.CHASE)
		return

	_face(target.global_position - global_position)
	attack_timer -= delta
	if attack_timer <= TIMER_EPSILON:
		attack_timer = 1.0 / current_attack_speed
		if data.cast_time > 0.0:
			transition_to(State.CASTING)   # замах/каст перед ударом
		else:
			_do_attack()

# Каст: удар срабатывает через cast_time. Цель умерла — каст сорван.
func _state_casting(delta: float) -> void:
	if not _has_valid_target():
		transition_to(State.CHASE)
		return
	cast_timer -= delta
	if cast_timer <= TIMER_EPSILON:
		if global_position.distance_to(target.global_position) <= current_attack_range:
			_do_attack()
		transition_to(State.ATTACK)

func _state_stunned(delta: float) -> void:
	stun_timer -= delta
	if stun_timer <= TIMER_EPSILON:
		stun_timer = 0.0
		_resume_after_control()

func _state_knockback(delta: float) -> void:
	global_position += knockback_velocity * delta
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)
	if knockback_velocity.length() <= KNOCKBACK_STOP_SPEED:
		knockback_velocity = Vector2.ZERO
		transition_to(State.CHASE)

# Отходим от ближайшего врага retreat_duration секунд, затем снова в бой.
# HP не регенерирует — без таймера боец бегал бы вечно и бой не кончился бы.
func _state_retreating(delta: float) -> void:
	retreat_timer -= delta
	var enemies = SoldierRegistry.get_alive_soldiers_of_team(1 - team)
	if retreat_timer <= TIMER_EPSILON or enemies.is_empty():
		transition_to(State.CHASE)
		return
	var threat = _get_nearest(enemies)
	var away = global_position - threat.global_position
	_move_towards(global_position + away, delta)

# -------------------------------------------------------
# ПОДДЕРЖКА — лечение (Apothecary). Работает параллельно с FSM.
# -------------------------------------------------------
func _tick_support(delta: float) -> void:
	if current_heal_per_second <= 0.0:
		return
	if current_state in [State.IDLE, State.STUNNED, State.DEAD]:
		return
	# Лечим самого раненого (по доле HP) союзника в радиусе, включая себя
	var patient: Soldier = null
	var lowest_ratio: float = 1.0
	var r2 = data.heal_radius * data.heal_radius
	for ally in SoldierRegistry.get_alive_soldiers_of_team(team):
		if global_position.distance_squared_to(ally.global_position) > r2:
			continue
		var ratio = ally.current_hp / ally.max_hp
		if ratio < lowest_ratio:
			lowest_ratio = ratio
			patient = ally
	if patient:
		patient.heal(current_heal_per_second * delta)

# Пересчитать базовые статы после изменения множителей отряда (карта-улучшение
# во время расстановки). Доля HP сохраняется.
func refresh_stats_from_data() -> void:
	var ratio = current_hp / max_hp if max_hp > 0.0 else 1.0
	max_hp = data.get_max_hp()
	current_hp = max_hp * ratio
	current_damage = data.get_damage()
	current_attack_speed = data.get_attack_speed()
	current_move_speed = data.get_move_speed()
	shield = max_hp * data.shield_ratio
	queue_redraw()

func heal(amount: float) -> void:
	if current_state == State.DEAD:
		return
	current_hp = min(current_hp + amount, max_hp)
	queue_redraw()

# -------------------------------------------------------
# ПОЛОСКА HP над головой
# -------------------------------------------------------
func _draw() -> void:
	if data == null or current_state == State.DEAD or max_hp <= 0.0:
		return
	var top = -TARGET_SPRITE_HEIGHT * data.sprite_scale - HP_BAR_GAP
	var rect = Rect2(Vector2(-HP_BAR_SIZE.x / 2.0, top), HP_BAR_SIZE)
	draw_rect(rect.grow(1.0), Color(0, 0, 0, 0.75))
	var ratio = clampf(current_hp / max_hp, 0.0, 1.0)
	var color = UITheme.GREEN if team == GameConstants.TEAM_PLAYER else UITheme.RED_BRIGHT
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), color)
	if shield > 0.0:   # щит Iron Halo — голубая полоска под HP
		var s_ratio = clampf(shield / max_hp, 0.0, 1.0)
		draw_rect(Rect2(rect.position + Vector2(0, rect.size.y + 1), Vector2(rect.size.x * s_ratio, 2)), SHIELD_BAR_COLOR)
	# Уровень отряда — золотые ромбики над полоской HP
	for i in data.squad_level:
		var c = Vector2((i - (data.squad_level - 1) / 2.0) * LEVEL_PIP_STEP, top - LEVEL_PIP_GAP)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -LEVEL_PIP_R), c + Vector2(LEVEL_PIP_R, 0),
			c + Vector2(0, LEVEL_PIP_R), c + Vector2(-LEVEL_PIP_R, 0)]), UITheme.GOLD_BRIGHT)

# -------------------------------------------------------
# ДВИЖЕНИЕ
# -------------------------------------------------------
func _move_towards(point: Vector2, delta: float) -> void:
	var direction = (point - global_position).normalized()
	var speed = current_move_speed
	if team == GameConstants.TEAM_ENEMY:
		speed *= Building.slow_mult_at(global_position)   # стены игрока замедляют
	global_position += direction * speed * delta
	_face(direction)
	_play_animation("walk")

func _face(direction: Vector2) -> void:
	if absf(direction.x) > 0.01:
		sprite.flip_h = direction.x < 0.0

func _has_valid_target() -> bool:
	return is_instance_valid(target) and target.current_state != State.DEAD

# После стана возвращаемся туда, где были; из «контроля» — сразу в погоню
func _resume_after_control() -> void:
	match previous_state:
		State.IDLE, State.MOVE, State.CHASE, State.ATTACK, State.RETREATING:
			transition_to(previous_state)
		_:
			transition_to(State.CHASE)

# -------------------------------------------------------
# КОНТРОЛЬ (стан, отбрасывание) — вызывают способности/здания
# -------------------------------------------------------
func apply_stun(duration: float) -> void:
	if current_state == State.DEAD:
		return
	# Повторный стан не перезаписывает previous_state, только продлевает таймер
	stun_timer = max(stun_timer, duration)
	transition_to(State.STUNNED)

func apply_knockback(direction: Vector2, force: float) -> void:
	if current_state == State.DEAD or current_state == State.STUNNED:
		return
	knockback_velocity = direction.normalized() * force
	transition_to(State.KNOCKBACK)

# -------------------------------------------------------
# АТАКА И УРОН
# -------------------------------------------------------
func _do_attack() -> void:
	if is_instance_valid(target):
		target.take_damage(_roll_damage())
		_apply_on_hit_effects()
		sprite.stop()
		sprite.play("attack")

# Урон одного удара: аура союзников + разброс damage_variance
func _roll_damage() -> float:
	var damage = current_damage * (1.0 + get_aura_damage_bonus())
	var variance = damage * data.damage_variance
	return randf_range(damage - variance, damage + variance)

# Эффекты попадания из данных юнита (Librarian — стан, Dreadnought — отбрасывание)
func _apply_on_hit_effects() -> void:
	if not _has_valid_target():
		return
	if data.on_hit_stun > 0.0:
		target.apply_stun(data.on_hit_stun)
	if data.on_hit_knockback > 0.0:
		target.apply_knockback(target.global_position - global_position, data.on_hit_knockback)

# Бонус урона от аур союзников рядом (Chaplain). Считается в момент удара —
# runtime-поля не меняются, поэтому аура пропадает, как только отошли из радиуса.
func get_aura_damage_bonus() -> float:
	var best: float = 0.0
	for ally in SoldierRegistry.get_alive_soldiers_of_team(team):
		var a: UnitData = ally.data
		if a.aura_damage_bonus <= best:
			continue
		if a.aura_tag != "" and not (a.aura_tag in data.tags):
			continue
		if global_position.distance_squared_to(ally.global_position) <= a.aura_radius * a.aura_radius:
			best = a.aura_damage_bonus
	# Chapter Banner — аура карты-улучшения: всем союзникам в радиусе
	for ally in SoldierRegistry.get_alive_soldiers_of_team(team):
		var b: float = ally.data.banner_aura_bonus
		if b > best and global_position.distance_squared_to(ally.global_position) \
				<= UnitData.BANNER_RADIUS * UnitData.BANNER_RADIUS:
			best = b
	return best

func take_damage(amount: float) -> void:
	if current_state == State.DEAD:
		return
	if shield > 0.0:
		var absorbed = minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
	current_hp -= amount
	queue_redraw()
	if current_hp <= 0.0:
		if _try_revive():
			return
		_die()
		return
	if not has_retreated and current_hp / max_hp < data.retreat_hp_threshold \
			and current_state not in [State.IDLE, State.STUNNED, State.KNOCKBACK]:
		has_retreated = true
		retreat_timer = data.retreat_duration
		transition_to(State.RETREATING)

# Apothecarion рядом: шанс встать с долей HP (один раз за бой, только игрок)
func _try_revive() -> bool:
	if team != GameConstants.TEAM_PLAYER or has_revived:
		return false
	var r = Building.revive_at(global_position)
	if r["chance"] <= 0.0 or randf() >= r["chance"]:
		return false
	has_revived = true
	current_hp = max_hp * r["hp"]
	return true

func _die() -> void:
	if current_state == State.DEAD:
		return
	transition_to(State.DEAD)
	queue_redraw()   # убрать полоску HP
	emit_signal("died", self)

# -------------------------------------------------------
# ПОИСК ЦЕЛИ
# -------------------------------------------------------
# Боец спрашивает свой отряд о врагах —
# отряд знает о всех вражеских бойцах
func _find_target() -> Soldier:
	var enemies = SoldierRegistry.get_alive_soldiers_of_team(1 - team)
	if enemies.is_empty():
		return null

	match data.priority:
		GameConstants.PRIORITY_NEAREST:
			return _get_nearest(enemies)
		GameConstants.PRIORITY_LOWEST_HP:
			return _get_lowest_hp(enemies)
		GameConstants.PRIORITY_HIGHEST_THREAT:
			return _get_highest_threat(enemies)
		GameConstants.PRIORITY_FARTHEST:
			return _get_farthest(enemies)
		GameConstants.PRIORITY_RANDOM:
			return enemies[randi() % enemies.size()]
		_:
			return _get_nearest(enemies)

func _get_nearest(units: Array) -> Soldier:
	var closest: Soldier = null
	var min_dist: float = INF
	for u in units:
		var d = global_position.distance_squared_to(u.global_position)
		if d < min_dist:
			min_dist = d
			closest = u
	return closest

func _get_farthest(units: Array) -> Soldier:
	var farthest: Soldier = null
	var max_dist: float = -INF
	for u in units:
		var d = global_position.distance_squared_to(u.global_position)
		if d > max_dist:
			max_dist = d
			farthest = u
	return farthest

func _get_lowest_hp(units: Array) -> Soldier:
	var result: Soldier = null
	var min_hp: float = INF
	for u in units:
		if u.current_hp < min_hp:
			min_hp = u.current_hp
			result = u
	return result

func _get_highest_threat(units: Array) -> Soldier:
	var result: Soldier = null
	var max_dmg: float = -INF
	for u in units:
		if u.current_damage > max_dmg:
			max_dmg = u.current_damage
			result = u
	return result

# -------------------------------------------------------
# ПЕРЕХОД МЕЖДУ СОСТОЯНИЯМИ
# -------------------------------------------------------
func transition_to(new_state: State) -> void:
	# Повторный вход в то же состояние и выход из DEAD запрещены
	if current_state == new_state or current_state == State.DEAD:
		return
	previous_state = current_state
	current_state = new_state
	_on_state_enter(new_state)

func _on_state_enter(state: State) -> void:
	match state:
		State.IDLE, State.STUNNED, State.KNOCKBACK:
			_play_animation("idle")
		State.MOVE, State.CHASE, State.RETREATING:
			_play_animation("walk")
		State.ATTACK:
			attack_timer = 0.0
			sprite.stop()
			sprite.play("attack")
		State.CASTING:
			cast_timer = data.cast_time
			_play_animation("idle")
		State.DEAD:
			sprite.stop()
			sprite.play("death")
			sprite.animation_finished.connect(_on_death_finished)

func _on_death_finished() -> void:
	if current_state == State.DEAD:
		var timer = get_tree().create_timer(0.3, false)   # на паузе не тикает
		timer.timeout.connect(queue_free)
