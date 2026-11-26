class_name UnitAbilities
extends Object

# Способности отрядов (данными в UnitData; решение пользователя 17.10.2026): прыжок Assault, окапывание Devastator,
# стрельба на ходу Land Speeder, боевой клич Chaplain. Вынесено из Soldier.gd 26.11.2026: функции статические,
# состояние и константы — на бойце (`s`).

# Прыжок (Assault): враг-стрелок ближе jump_range, но не вплотную — прыжок к нему (раз за бой)
static func try_jump(s: Soldier) -> bool:
	var prey := SoldierRegistry.find_nearest(1 - s.team, s.global_position, s.data.jump_range, true)
	if prey == null or s.global_position.distance_to(prey.global_position) <= s.current_attack_range * 2.0:
		return false
	s.jump_used = true
	s._leap_target = prey
	s._leap_from = s.global_position
	# Приземление — перед целью со стороны прыжка, бойцы отряда — своим строем, не в одну точку
	var back := (s.global_position - prey.global_position).normalized()
	s._leap_to = prey.global_position + back * s.current_attack_range * 0.5 + s.formation_offset * 0.5
	s._leap_duration = maxf(s._leap_from.distance_to(s._leap_to) / Soldier.JUMP_SPEED, Soldier.JUMP_MIN_TIME) * (1.0 + s.attack_stagger * Soldier.JUMP_STAGGER)
	s._leap_time = s._leap_duration
	s._leap_t = 0.0
	s._leap_prev = 0.0
	s._face(prey.global_position - s.global_position)
	s._play_animation("jump" if s.sprite.sprite_frames.has_animation("jump") else "idle")   # полёт на ранце (Assault)
	# Шлейф ранца — хвостом назад по полёту, на высоте спины (дугу спрайта повторяет _process)
	s._jump_trail = Vfx.attach(s, "jump_trail", s.data.sprite_scale * Soldier.EFFECT_SCALE)
	if s._jump_trail:
		s._jump_trail.rotation = (s._leap_to - s._leap_from).angle()
		s._jump_trail.position.y = -Soldier.JUMP_TRAIL_RISE * s.data.sprite_scale
	return true

static func clear_jump_trail(s: Soldier) -> void:
	Vfx.dismiss(s._jump_trail)
	s._jump_trail = null

static func tick_leap(s: Soldier, delta: float) -> void:
	s._leap_time -= delta
	if s._leap_time <= Soldier.TIMER_EPSILON:
		s._leap_time = 0.0
	s._leap_t = 1.0 - s._leap_time / s._leap_duration
	s.global_position = s._leap_from.lerp(s._leap_to, s._leap_t)
	if s._leap_time <= 0.0:
		_land(s)

# Приземление: удар по всем врагам в jump_radius (урон удара × jump_damage_mult) и оглушение; дальше —
# бой с тем, на кого прыгал
static func _land(s: Soldier) -> void:
	var dmg := s._roll_damage() * s.data.jump_damage_mult
	var r2 := s.data.jump_radius * s.data.jump_radius
	for e in SoldierRegistry.get_alive_soldiers_of_team(1 - s.team).duplicate():
		if s.global_position.distance_squared_to(e.global_position) > r2:
			continue
		BattleManager.credit_damage(s.parent_squad, clampf(dmg - e.shield, 0.0, e.current_hp))
		e.take_damage(dmg)
		if s.data.jump_stun > 0.0:
			e.apply_stun(s.data.jump_stun)
	clear_jump_trail(s)
	Vfx.spawn(s._world_parent(), "jump_land", s.feet(), s.data.sprite_scale * Soldier.EFFECT_SCALE)
	AudioManager.play("jump_land")
	DustLayer.puff(s.global_position, 8.0 * s.data.sprite_scale, 3, 6.0)
	Soldier.request_hitstop(s)
	s.target = s._leap_target if is_instance_valid(s._leap_target) and s._leap_target.current_state != Soldier.State.DEAD \
		else s._find_target()
	s._leap_target = null
	if s.target and s.global_position.distance_to(s.target.global_position) <= s.current_attack_range:
		s.transition_to(Soldier.State.ATTACK)
	elif s.target:
		s.transition_to(Soldier.State.CHASE)
	# Приземление листа (Assault: пыль из-под ног) — до первого удара, потом стойка
	if s.current_state == Soldier.State.ATTACK and s.sprite.sprite_frames.has_animation("landing"):
		s.sprite.play("landing")
	elif s.current_state != Soldier.State.ATTACK:   # переход в то же состояние анимацию не меняет — снимаем jump
		s._play_animation("walk" if s.current_state in [Soldier.State.MOVE, Soldier.State.CHASE] else "idle")

# Прыжок прерван итогом боя или гибелью — спрайт обратно на землю
static func end_leap_view(s: Soldier) -> void:
	s._leap_time = 0.0
	s._leap_t = 1.0
	s._leap_prev = 1.0
	s._leap_target = null
	s.sprite.position.y = 0.0
	clear_jump_trail(s)

# Окапывание (Devastator): стоял весь тик — копит, сдвинулся (бег, кружение, отброс) — с нуля
static func tick_entrench(s: Soldier, delta: float) -> void:
	var was := s.is_entrenched()
	if s._moved or s.current_state == Soldier.State.KNOCKBACK:
		s._still_time = 0.0
	else:
		s._still_time = minf(s._still_time + delta, s.data.entrench_time)
	if s.is_entrenched() != was:
		show_entrench(s, s.is_entrenched())

# Бруствер (лист entrench, пакет художника; было — дуга кодом в _draw): вырастает у ног и стоит, сдвинулся — тает
static func show_entrench(s: Soldier, on: bool) -> void:
	Vfx.dismiss(s._entrench_vfx)
	s._entrench_vfx = Vfx.attach(s, "entrench", s.data.sprite_scale * Soldier.EFFECT_SCALE) if on else null

# Стрельба на ходу (Land Speeder): кружит вокруг цели, держась на MOBILE_FIRE_DISTANCE дальности
static func strafe_around(s: Soldier, center: Vector2, delta: float) -> void:
	var to_me := s.global_position - center
	var dist := to_me.length()
	if dist < 0.01:
		return
	var radial := to_me / dist
	var tangent := Vector2(-radial.y, radial.x) * s._orbit_sign
	var want := s.current_attack_range * Soldier.MOBILE_FIRE_DISTANCE
	var dir := (tangent + radial * clampf((want - dist) / want * 3.0, -1.0, 1.0)).normalized()
	var speed := s.current_move_speed * s.get_move_speed_mult() * Soldier.MOBILE_FIRE_SPEED
	s.global_position += dir * speed * delta
	s._moved = true
	if s.sprite.animation != "attack":   # выстрел доигрывается, между выстрелами — ход
		s._play_animation("walk")
		s.sprite.speed_scale = s.walk_anim_scale(speed)
	s._face(center - s.global_position)

# Боевой клич (Chaplain): один раз за бой, при первом сближении с врагом
static func try_battle_cry(s: Soldier) -> bool:
	if s.battle_cry_used or s.data.battle_cry_status == "":
		return false
	s.battle_cry_used = true
	AudioManager.play("battle_cry")
	Vfx.spawn(s._world_parent(), "chaplain_warcry", s.global_position, s.data.battle_cry_radius)   # кольцо по радиусу клича
	var r2 = s.data.battle_cry_radius * s.data.battle_cry_radius
	for ally in SoldierRegistry.get_alive_soldiers_of_team(s.team):
		if s.global_position.distance_squared_to(ally.global_position) <= r2:
			# Без стаков: клич пары Chaplain (UnitFactory.PAIR_UNITS) — как клич одного
			ally.apply_status(s.data.battle_cry_status, s.data.battle_cry_power, s.data.battle_cry_duration, false)
	return true
