class_name BossSpecial
extends Object

# Приём финального босса (UnitData.special_*; решение пользователя 09.11.2026 — свой приём у каждого примарха):
# замах, срабатывание, вид, ярость и шаг. Вынесено из Soldier.gd 26.11.2026: функции статические, состояние и константы
# приёма — на бойце (`s`). Пока идёт приём (s._special_left > 0), FSM стоит, оглушение и отброс не действуют.

static func step(s: Soldier) -> void:
	var now := Time.get_ticks_msec()
	if now - s._step_shake_at < Soldier.BOSS_STEP_GAP_MS:
		return
	s._step_shake_at = now
	s._shake_camera(Soldier.BOSS_STEP_SHAKE)
	AudioManager.play("boss_step")
	BossFx.cracks(s.feet(), Soldier.TARGET_SPRITE_HEIGHT * s.data.sprite_scale * 0.35, Soldier.BOSS_STEP_CRACK_LIFE, s.data.special_color)

static func try_start(s: Soldier) -> bool:
	var reach := s.data.special_range if s.data.special_range > 0.0 else s.data.special_radius
	var t: Soldier = s.target if s._has_valid_target() else s._find_target()
	if s.data.special_kind == "leap":   # прыжок — на стрелков, если они в досягаемости (как Assault)
		var prey := SoldierRegistry.find_nearest(1 - s.team, s.global_position, reach, true)
		if prey:
			t = prey
	if t == null or s.global_position.distance_to(t.global_position) > reach:
		return false
	s._special_target = t
	s._special_from = s.global_position
	s._special_to = s.global_position
	var dir := (t.global_position - s.global_position).normalized()
	s._special_aim = dir if dir != Vector2.ZERO else (Vector2.LEFT if s.sprite.flip_h else Vector2.RIGHT)
	match s.data.special_kind:
		"leap":   # приземлиться перед целью
			s._special_to = t.global_position - dir * s.current_attack_range * 0.5
		"dash":   # насквозь: за цель на свою дальность
			s._special_to = t.global_position + dir * s.current_attack_range
	s._face(t.global_position - s.global_position)
	var frames := s.sprite.sprite_frames
	var length := Soldier.SPECIAL_FALLBACK_TIME
	s._special_wind = Soldier.SPECIAL_FALLBACK_TIME * 0.5
	if frames.has_animation("special") and frames.get_frame_count("special") > 0:
		var fps: float = frames.get_animation_speed("special")
		length = frames.get_frame_count("special") / fps
		s._special_wind = minf(frames.get_meta("special_frame", frames.get_frame_count("special") / 2) / fps, length)
	s._special_left = length
	s._special_release = maxf(s._special_wind, GameConstants.FIXED_TICK)
	s._special_cd = s.data.special_cooldown * (Soldier.ENRAGE_COOLDOWN_MULT if s.enraged else 1.0)
	clear_telegraph(s)
	s._telegraph = BossFx.telegraph(s, s.data.special_kind, s._special_from,
		s._special_to if s._special_to != s._special_from else s._special_from + s._special_aim * s.data.special_radius,
		s.data.special_radius, s._special_release, t)
	s._hit_timer = 0.0   # замах обычного удара снят
	s._hit_target = null
	s.sprite.stop()
	s.sprite.play("special" if frames.has_animation("special") else "attack")
	return true

static func tick(s: Soldier, delta: float) -> void:
	s._special_left -= delta
	if s._special_release > 0.0:
		s._special_release -= delta
		if s._special_to != s._special_from:
			var t := clampf(1.0 - s._special_release / maxf(s._special_wind, GameConstants.FIXED_TICK), 0.0, 1.0)
			s.global_position = s._special_from.lerp(s._special_to, t)
			s._moved = true
			# рывок / прыжок примарха за тик дальше GRID_SLACK (special_range до 280, замах короче 0.5 с) —
			# сетка поиска ближайших пересобирается (ревью 09.11.2026)
			SoldierRegistry.invalidate_grid()
		if s._special_release <= Soldier.TIMER_EPSILON:
			s._special_release = 0.0
			s.global_position = s._special_to
			clear_telegraph(s)
			release(s)
	if s._special_left <= Soldier.TIMER_EPSILON:
		s._special_left = 0.0
		s._special_target = null
		# FSM стояла в ATTACK / CHASE: цель могла пасть или отойти — дальше обычным ходом состояний
		if not s._has_valid_target():
			s.target = s._find_target()
		if s.target and s.global_position.distance_to(s.target.global_position) <= s.current_attack_range:
			if s.current_state != Soldier.State.ATTACK:
				s.transition_to(Soldier.State.ATTACK)
			else:
				s.sprite.play("idle")
		elif s.target:
			if s.current_state != Soldier.State.CHASE:
				s.transition_to(Soldier.State.CHASE)
			else:
				s._play_animation("walk")
		else:
			s.transition_to(Soldier.State.MOVE)
			s._play_animation("walk")

# Кадр срабатывания: урон по виду приёма, статус, оглушение; вид — свет, тряска, стоп-кадр
static func release(s: Soldier) -> void:
	WorldGrade.pulse(0.55)   # приём босса — удар по экрану (аберрация)
	var dmg := s._roll_damage() * s.data.special_mult
	var victims: Array = []
	var foes: Array = SoldierRegistry.get_alive_soldiers_of_team(1 - s.team)
	var r2 := s.data.special_radius * s.data.special_radius
	var aim := s._special_aim
	match s.data.special_kind:
		"leap", "nova", "shield":
			for e in foes:
				if s.global_position.distance_squared_to(e.global_position) <= r2:
					victims.append(e)
		"cone":
			for e in foes:
				var to: Vector2 = e.global_position - s.global_position
				if to.length_squared() <= r2 and (to.length_squared() < 1.0 or absf(aim.angle_to(to)) <= Soldier.SPECIAL_CONE_HALF):
					victims.append(e)
		"dash":
			for e in foes:
				if Geometry2D.get_closest_point_to_segment(e.global_position, s._special_from, s._special_to) \
						.distance_squared_to(e.global_position) <= r2:
					victims.append(e)
		"bolt":
			_bolt(s, dmg)
	for e in victims.duplicate():
		_hit(s, e, dmg)
	if s.data.special_shield > 0.0:
		s.shield += s.max_hp * s.data.special_shield
		Vfx.attach(s, "shield", s.data.sprite_scale * Soldier.EFFECT_SCALE)
	_view(s)

static func _hit(s: Soldier, e: Soldier, dmg: float) -> void:
	if not is_instance_valid(e) or e.current_state == Soldier.State.DEAD:
		return
	var amount: float = dmg * e.data.unit_weight
	BattleManager.credit_damage(s.parent_squad, clampf(amount - e.shield, 0.0, e.current_hp))
	e.take_damage(amount, true, true)
	if s.data.special_stun > 0.0:
		e.apply_stun(s.data.special_stun)
	if s.data.special_status != "":
		e.apply_status(s.data.special_status, s.data.special_status_power, s.data.special_status_duration)

# Магнус: сгусток варпа в цель, взрыв по площади со статусом
static func _bolt(s: Soldier, dmg: float) -> void:
	if not is_instance_valid(s._special_target) or s.parent_squad == null:
		return
	var shot := Projectile.launch(s.parent_squad.get_parent(), s.data.special_projectile, s._muzzle_point(), s._special_target,
		Vector2(0.0, -Soldier.TARGET_SPRITE_HEIGHT * 0.45 * s._special_target.data.sprite_scale + Soldier.GROUND_SINK))
	shot.source = s.parent_squad
	if s.data.projectile in ["bolt", "spark"] and "vehicle" not in s.data.tags:   # гильза из затвора (18.11.2026)
		Casings.eject(s.parent_squad.get_parent(), s._muzzle_point(), -1.0 if s.sprite.flip_h else 1.0)
	shot.damage = dmg
	shot.splash_radius = s.data.special_radius
	shot.splash_team = 1 - s.team
	shot.heavy = true
	shot.light_color = s.data.special_color
	var status := s.data.special_status
	var power := s.data.special_status_power
	var duration := s.data.special_status_duration
	var radius := s.data.special_radius
	var foe_team := 1 - s.team
	var col := s.data.special_color
	shot.on_impact = func(point: Vector2) -> void:
		BossFx.shockwave(point, radius, col)
		BossFx.cracks(point, radius * 0.8, Soldier.BOSS_CRACK_LIFE, col)
		if status == "":
			return
		for e in SoldierRegistry.get_alive_soldiers_of_team(foe_team).duplicate():
			if e.global_position.distance_to(point) <= radius:
				e.apply_status(status, power, duration)

# Вид приёма (кроме снаряда — у него свой взрыв): удар о землю, свет цвета приёма, тряска камеры, стоп-кадр
static func _view(s: Soldier) -> void:
	if s.data.special_kind == "bolt":
		AudioManager.play("boss_special")
		IsoGridRenderer.flash_light(s._muzzle_point(), Color(s.data.special_color, 0.9), 70.0, 0.25)
		return
	var parent := s._world_parent()
	var k := s.data.special_radius / 60.0
	match s.data.special_kind:
		"leap":
			Vfx.spawn(parent, "jump_land", s.global_position, k)
			DustLayer.puff(s.global_position, 10.0 * s.data.sprite_scale, 4, 8.0)
		"dash":
			Vfx.spawn(parent, "retreat_dust", s._special_from, s.data.sprite_scale * Soldier.EFFECT_SCALE)
			Vfx.spawn(parent, "ground_slam", s.global_position, k)
			# Борозда и пыль по всему пути рывка (EFFECTS_NEEDED 4.12, кодом 09.11.2026; было — пыль только на старте)
			BossFx.furrow(s._special_from, s._special_to, s.data.special_color)
			var path := s._special_to - s._special_from
			for i in 4:
				DustLayer.puff(s._special_from + path * (i + 0.5) / 4.0, 7.0 * s.data.sprite_scale, 2, 6.0)
		"cone":
			if s.data.special_status == StatusEffects.POISONED:
				# Чумное облако по зоне конуса (4.12, кодом 09.11.2026): клубы висят и тают — видно, куда пришёлся удар
				BossFx.cloud(s.global_position, s._special_aim, Soldier.SPECIAL_CONE_HALF, s.data.special_radius, s.data.special_color)
			else:
				# Огонь — языки по всему конусу: три у тела и два дальше (было три у тела — дальняя часть зоны пустая)
				for i in Soldier.CONE_FLAMES.size():
					var f: Vector2 = Soldier.CONE_FLAMES[i]
					var a: float = s._special_aim.angle() + f.x * Soldier.SPECIAL_CONE_HALF
					Vfx.spawn(parent, "flame_burst", s.global_position + Vector2.from_angle(a) * s.data.special_radius * f.y,
						k * (0.8 if f.y < 0.5 else 0.65), a)
		_:
			Vfx.spawn(parent, "ground_slam", s.global_position, k)
			Vfx.spawn(parent, "explosion", s.global_position, k * 0.8)
	BossFx.shockwave(s.global_position, s.data.special_radius, s.data.special_color)
	BossFx.cracks(s.feet(), s.data.special_radius * 0.8, Soldier.BOSS_CRACK_LIFE, s.data.special_color)
	ScarLayer.scorch(s.global_position, s.data.special_radius * 0.35)   # шрам поля от удара приёма
	AudioManager.play("boss_special")
	IsoGridRenderer.flash_light(s.global_position, Color(s.data.special_color, 0.95), s.data.special_radius * 1.6, 0.4)
	s._shake_camera(Soldier.SPECIAL_SHAKE)
	Soldier.request_hitstop(s)

static func clear_telegraph(s: Soldier) -> void:
	if is_instance_valid(s._telegraph):
		s._telegraph.release()
	s._telegraph = null

# Ярость (решение пользователя 09.11.2026): босс впервые ≤ ENRAGE_AT HP — рёв: приём скоро, дальше в
# 1 / ENRAGE_COOLDOWN_MULT раза чаще; вид — вспышка, ударная волна, тряска, кольцо пульсирует, тело тлеет
static func enrage(s: Soldier) -> void:
	s.enraged = true
	s._special_cd = minf(s._special_cd, Soldier.ENRAGE_FIRST)
	if is_instance_valid(s._ground):
		s._ground.enraged = true
	s._sync_status_vfx()
	s._flash_hit()
	BossFx.shockwave(s.global_position, s.data.special_radius * 1.2, s.data.special_color)
	IsoGridRenderer.flash_light(s.global_position, Color(s.data.special_color, 0.9), s.data.special_radius * 2.0, 0.5)
	AudioManager.play("boss_appear")
	s._shake_camera(Soldier.SPECIAL_SHAKE)
	var scene := s.get_tree().current_scene if s.is_inside_tree() else null
	if scene and scene.has_method("boss_enraged"):
		scene.boss_enraged(s)
