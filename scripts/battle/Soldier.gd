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
const HP_BAR_GAP: float = 6.0
const LEVEL_PIP_R: float = 3.0
const LEVEL_PIP_STEP: float = 8.0
const LEVEL_PIP_GAP: float = 5.0
const STATUS_DOT_R: float = 2.0
const STATUS_DOT_GAP: float = 4.0
# Вспышка попадания: боец, получивший урон, на мгновение белеет (общий шейдер на всех)
const HIT_FLASH_TIME: float = 0.1
const HIT_FLASH_STRENGTH: float = 0.85   # доля белого поверх цвета спрайта (с тинтом)
const HIT_FLASH_SHADER = """shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(c.rgb, vec3(1.0), %.2f), c.a);
}"""
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
# Статус-эффекты (StatusEffects): имя → {stacks, power, time, duration, dot_timer, spread_timer}
var status_effects: Dictionary = {}
var battle_cry_used: bool = false
# Эффект при попадании от ордена (Salamanders) — если у юнита своего нет; ставит
# SynergyManager.apply_chapter_bonus в начале боя
var extra_on_hit_status: String = ""
var extra_on_hit_status_power: float = 0.0
var extra_on_hit_status_duration: float = 0.0

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
	current_move_speed = data.move_speed
	current_attack_range = data.attack_range
	current_attack_speed = data.get_attack_speed()
	current_heal_per_second = data.heal_per_second
	formation_offset = offset
	attack_timer = 0.0
	current_state = State.IDLE
	previous_state = State.IDLE
	has_retreated = false
	status_effects.clear()
	battle_cry_used = false

	_load_animations()

	# Враги смотрят влево
	if team == GameConstants.TEAM_ENEMY:
		sprite.flip_h = true

# -------------------------------------------------------
# АНИМАЦИИ
# -------------------------------------------------------
# Анимация → подпапка спрайтов. Кадры: <sprite_path>/<папка>/0.png, 1.png, ...
# Если рядом есть <sprite_path>/frames.tres (tools/gif_to_frames.py из GIF) — берём его:
# там скорость каждой анимации и метаданные muzzle / shot_frame для снарядов.
const ANIMATION_FOLDERS = {"idle": "idle", "walk": "run", "attack": "attack", "death": "death"}
const ANIMATION_FPS: float = 8.0
# Набор кадров на папку спрайтов собирается один раз и общий для всех бойцов
# этого вида (раньше — заново на каждого бойца, с проверкой файлов на диске)
static var _frames_cache: Dictionary = {}   # sprite_path → SpriteFrames
static var _hit_flash_material: ShaderMaterial
var _hit_flash_id: int = 0   # номер последней вспышки — старый таймер не гасит новую

static func _get_frames(sprite_path: String) -> SpriteFrames:
	if _frames_cache.has(sprite_path):
		return _frames_cache[sprite_path]
	if ResourceLoader.exists(sprite_path + "/frames.tres"):
		_frames_cache[sprite_path] = load(sprite_path + "/frames.tres")
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
	_tick_status_effects(delta)
	if current_state == State.DEAD:
		return
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
		attack_timer = 1.0 / (current_attack_speed * get_attack_speed_mult())
		sprite.stop()
		sprite.play("attack")
		var shot := _shoot_projectile(citadel, Vector2(0.0, -40.0))
		if shot:
			shot.damage = _roll_damage()   # урон — при попадании
		else:
			citadel.take_hit(_roll_damage())

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
		attack_timer = 1.0 / (current_attack_speed * get_attack_speed_mult())
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
	queue_redraw()

func heal(amount: float) -> void:
	if current_state == State.DEAD:
		return
	if status_effects.has(StatusEffects.POISONED):
		amount *= StatusEffects.POISON_HEAL_MULT
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
	# Уровень отряда — золотые ромбики над полоской HP
	for i in data.squad_level:
		var c = Vector2((i - (data.squad_level - 1) / 2.0) * LEVEL_PIP_STEP, top - LEVEL_PIP_GAP)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -LEVEL_PIP_R), c + Vector2(LEVEL_PIP_R, 0),
			c + Vector2(0, LEVEL_PIP_R), c + Vector2(-LEVEL_PIP_R, 0)]), UITheme.GOLD_BRIGHT)
	# Статус-эффекты — точки под полоской HP, по точке на стак
	var dot_x = -HP_BAR_SIZE.x / 2.0
	for effect in status_effects:
		for i in status_effects[effect]["stacks"]:
			draw_circle(Vector2(dot_x + STATUS_DOT_R, top + HP_BAR_SIZE.y + STATUS_DOT_GAP), STATUS_DOT_R,
				StatusEffects.COLORS.get(effect, Color.WHITE))
			dot_x += STATUS_DOT_R * 2.0 + 1.0

# -------------------------------------------------------
# ДВИЖЕНИЕ
# -------------------------------------------------------
func _move_towards(point: Vector2, delta: float) -> void:
	var direction = (point - global_position).normalized()
	var speed = current_move_speed * get_move_speed_mult()   # замедление (стены игрока)
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
# Стрелок (UnitData.projectile) выпускает снаряд — урон и эффекты при попадании
# (Projectile._impact); ближний бой бьёт сразу.
func _do_attack() -> void:
	if not is_instance_valid(target):
		return
	sprite.stop()
	sprite.play("attack")
	var shot := _shoot_projectile(target, Vector2(0.0, -TARGET_SPRITE_HEIGHT * 0.45 * target.data.sprite_scale))
	if shot:
		shot.damage = _roll_damage()
		shot.stun = data.on_hit_stun
		shot.knockback = data.on_hit_knockback
		var st = _on_hit_status()
		shot.status = st[0]
		shot.status_power = st[1]
		shot.status_duration = st[2]
		return
	target.take_damage(_roll_damage())
	_apply_on_hit_effects()

# Снаряд из ствола (метаданные muzzle кадров) на кадре вспышки (shot_frame);
# null — юнит без снаряда (ближний бой)
func _shoot_projectile(to: Node2D, aim_offset: Vector2) -> Projectile:
	if data.projectile == "" or parent_squad == null:
		return null
	var frames := sprite.sprite_frames
	var base_h := TARGET_SPRITE_HEIGHT / sprite.scale.y   # высота кадра idle
	var muzzle: Vector2 = frames.get_meta("muzzle", Vector2(base_h * 0.3, -base_h * 0.5))
	if sprite.flip_h:
		muzzle.x = -muzzle.x
	var delay := 0.0
	if frames.has_meta("shot_frame"):
		delay = frames.get_meta("shot_frame") / frames.get_animation_speed("attack")
	return Projectile.launch(parent_squad.get_parent(), data.projectile, global_position + muzzle * sprite.scale,
			to, aim_offset, delay, data.projectile_warm)

# Урон одного удара: аура союзников + разброс damage_variance
func _roll_damage() -> float:
	var damage = current_damage * (1.0 + get_aura_damage_bonus()) * get_damage_mult()
	var variance = damage * data.damage_variance
	return randf_range(damage - variance, damage + variance)

# Эффекты попадания из данных юнита (Librarian — стан, Dreadnought — отбрасывание)
func _apply_on_hit_effects() -> void:
	if not _has_valid_target():
		return
	if data.on_hit_stun > 0.0:
		target.apply_stun(data.on_hit_stun)
	var st = _on_hit_status()
	if st[0] != "":
		target.apply_status(st[0], st[1], st[2])
	if data.on_hit_knockback > 0.0:
		target.apply_knockback(target.global_position - global_position, data.on_hit_knockback)

# Эффект попадания: свой у юнита (Plague Marine, Havoc), иначе от ордена
func _on_hit_status() -> Array:
	if data.on_hit_status != "":
		return [data.on_hit_status, data.on_hit_status_power, data.on_hit_status_duration]
	return [extra_on_hit_status, extra_on_hit_status_power, extra_on_hit_status_duration]

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
	return best

# flash = false — урон яда/огня: без вспышки каждые полсекунды
func take_damage(amount: float, flash: bool = true) -> void:
	if current_state == State.DEAD:
		return
	current_hp -= amount
	queue_redraw()
	if flash:
		_flash_hit()
	if current_hp <= 0.0:
		_die()
		return
	if not has_retreated and current_hp / max_hp < data.retreat_hp_threshold \
			and current_state not in [State.IDLE, State.STUNNED, State.KNOCKBACK]:
		has_retreated = true
		retreat_timer = data.retreat_duration
		transition_to(State.RETREATING)

# Только визуал: таймер дерева (на паузе стоит, ×2 ускоряет), а не тик боя —
# иначе вспышка последнего тика осталась бы гореть после конца боя
func _flash_hit() -> void:
	if not is_inside_tree():
		return
	if _hit_flash_material == null:
		var shader := Shader.new()
		shader.code = HIT_FLASH_SHADER % HIT_FLASH_STRENGTH
		_hit_flash_material = ShaderMaterial.new()
		_hit_flash_material.shader = shader
	sprite.material = _hit_flash_material
	_hit_flash_id += 1
	var id := _hit_flash_id
	get_tree().create_timer(HIT_FLASH_TIME, false).timeout.connect(func():
		if is_instance_valid(self) and _hit_flash_id == id:
			sprite.material = null)

func _die() -> void:
	if current_state == State.DEAD:
		return
	transition_to(State.DEAD)
	status_effects.clear()
	queue_redraw()   # убрать полоску HP
	emit_signal("died", self)

# -------------------------------------------------------
# СТАТУС-ЭФФЕКТЫ (StatusEffects) — поверх FSM, тикают с боем
# -------------------------------------------------------
# stackable: удар добавляет стак (до MAX_STACKS); аура (false) держит 1 стак.
# Время обновляется, сила — наибольшая из наложенных.
func apply_status(effect: String, power: float, duration: float, stackable: bool = true) -> void:
	if current_state == State.DEAD or effect == "" or duration <= 0.0:
		return
	var e: Dictionary = status_effects.get(effect, {})
	if e.is_empty():
		e = {"stacks": 1, "power": power, "time": duration, "duration": duration,
			"dot_timer": StatusEffects.DOT_TICK, "spread_timer": StatusEffects.BURN_SPREAD_EVERY}
		status_effects[effect] = e
	else:
		if stackable:
			e["stacks"] = mini(e["stacks"] + 1, StatusEffects.MAX_STACKS)
		e["power"] = maxf(e["power"], power)
		e["time"] = maxf(e["time"], duration)
		e["duration"] = maxf(e["duration"], duration)
	queue_redraw()

func get_status_stacks(effect: String) -> int:
	return status_effects[effect]["stacks"] if status_effects.has(effect) else 0

# Сила эффекта с учётом стаков (0 — эффекта нет)
func _status_amount(effect: String) -> float:
	if not status_effects.has(effect):
		return 0.0
	var e: Dictionary = status_effects[effect]
	return e["power"] * e["stacks"]

func get_damage_mult() -> float:
	return 1.0 + _status_amount(StatusEffects.EMPOWERED)

func get_move_speed_mult() -> float:
	return maxf(1.0 - _status_amount(StatusEffects.SLOWED), StatusEffects.MIN_SPEED_MULT)

func get_attack_speed_mult() -> float:
	return maxf(1.0 - _status_amount(StatusEffects.SLOWED) * StatusEffects.SLOW_ATTACK_SHARE,
		StatusEffects.MIN_SPEED_MULT)

func _tick_status_effects(delta: float) -> void:
	if status_effects.is_empty() or current_state == State.DEAD:
		return
	var expired: Array[String] = []
	for effect in status_effects.keys():
		var e: Dictionary = status_effects[effect]
		if StatusEffects.is_dot(effect):
			e["dot_timer"] -= delta
			if e["dot_timer"] <= TIMER_EPSILON:
				e["dot_timer"] += StatusEffects.DOT_TICK
				take_damage(e["power"] * e["stacks"] * StatusEffects.DOT_TICK, false)
				if current_state == State.DEAD:
					return
		if effect == StatusEffects.BURNING:
			e["spread_timer"] -= delta
			if e["spread_timer"] <= TIMER_EPSILON:
				e["spread_timer"] += StatusEffects.BURN_SPREAD_EVERY
				_spread_burning(e)
		e["time"] -= delta
		if e["time"] <= TIMER_EPSILON:
			expired.append(effect)
	for effect in expired:
		status_effects.erase(effect)
	if not expired.is_empty():
		queue_redraw()

# Огонь перекидывается на ближайшего негорящего соседа своей команды (1 стак)
# с остатком своего времени: цепочка гаснет, соседи не поджигают друг друга вечно
func _spread_burning(e: Dictionary) -> void:
	if e["time"] <= StatusEffects.BURN_SPREAD_EVERY + TIMER_EPSILON:
		return
	var best: Soldier = null
	var best_d2: float = StatusEffects.BURN_SPREAD_RADIUS * StatusEffects.BURN_SPREAD_RADIUS
	for ally in SoldierRegistry.get_alive_soldiers_of_team(team):
		if ally == self or ally.status_effects.has(StatusEffects.BURNING):
			continue
		var d2 = global_position.distance_squared_to(ally.global_position)
		if d2 <= best_d2:
			best_d2 = d2
			best = ally
	if best:
		best.apply_status(StatusEffects.BURNING, e["power"], e["time"], false)

# Боевой клич (Chaplain): один раз за бой, при первом сближении с врагом
func _try_battle_cry() -> void:
	if battle_cry_used or data.battle_cry_status == "":
		return
	battle_cry_used = true
	var r2 = data.battle_cry_radius * data.battle_cry_radius
	for ally in SoldierRegistry.get_alive_soldiers_of_team(team):
		if global_position.distance_squared_to(ally.global_position) <= r2:
			ally.apply_status(data.battle_cry_status, data.battle_cry_power, data.battle_cry_duration)

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
		GameConstants.PRIORITY_RANGED_FIRST:
			return _get_nearest_ranged(enemies)
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

# Ближайший стрелок; стрелков нет — просто ближайший
func _get_nearest_ranged(units: Array) -> Soldier:
	var closest: Soldier = null
	var min_dist: float = INF
	for u in units:
		if not "ranged" in u.data.tags:
			continue
		var d = global_position.distance_squared_to(u.global_position)
		if d < min_dist:
			min_dist = d
			closest = u
	return closest if closest else _get_nearest(units)

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
			_try_battle_cry()
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
