extends SceneTree

# Статус-эффекты (StatusEffects): яд, горение, усиление, замедление — стаки до 3,
# источники (Plague Marine, Havoc, Chaplain, Святилище Slaanesh). Бойцы тикаются вручную
# (FIXED_TICK) на расстановке — бой не идёт, ход теста детерминирован.
# Сохранение выключено — забег игрока не трогает.
#   godot --headless --path . -s tests/test_status_effects.gd
const TICK: float = 0.1
const EPS: float = 0.01

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _ticks(s, seconds: float) -> void:
	for i in range(roundi(seconds / TICK)):
		s.tick(TICK)

func _of(team: int, id: String) -> Array:
	return root.get_node("SoldierRegistry").get_alive_soldiers_of_team(team) \
		.filter(func(s): return s.data.factory_id == id)

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(3)
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	var army: Array[UnitData] = []
	var placements = {}
	for p in [["tactical_marine", Vector2i(1, 0), 3], ["chaplain", Vector2i(1, 1), 1], ["assault_marine", Vector2i(2, 2), 2]]:
		var d = UnitFactory.create(p[0])
		var hp: Array[float] = []
		for i in range(p[2]):
			hp.append(1.0)
		d.saved_hp = hp
		army.append(d)
		placements[d] = p[1]
	bm.player_units = army
	bm.player_placements = placements
	# Замедляет аурой Святилище Slaanesh (стена владений — преграда, ауры у неё нет: KingdomWall)
	var shrine = CardFactory.create("pleasure_shrine")
	bm.player_buildings[shrine] = Vector2i(0, 1)
	var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var tacs = _of(0, "tactical_marine")
	var a = tacs[0]
	var b = tacs[1]

	# 1. Яд: 2 ур/с за стак, тик раз в 0.5 с; стаки до 3. Боец пехоты — доля прежнего (unit_weight)
	var w: float = a.data.unit_weight
	var hp0 = a.current_hp
	a.apply_status(StatusEffects.POISONED, 2.0, 4.0)
	_ticks(a, 1.0)
	var one_stack = hp0 - a.current_hp
	for i in range(4):
		a.apply_status(StatusEffects.POISONED, 2.0, 4.0)
	var hp1 = a.current_hp
	_ticks(a, 1.0)
	_check("яд: 1 стак — %.1f урона за 1 с, 3 стака (4 повтора не больше 3) — %.1f" % [one_stack, hp1 - a.current_hp],
		absf(one_stack - 2.0 * w) < EPS and a.get_status_stacks(StatusEffects.POISONED) == 3 		and absf(hp1 - a.current_hp - 6.0 * w) < EPS)

	# 2. Яд ослабляет лечение вдвое; эффект проходит по времени
	var before = a.current_hp
	a.heal(4.0)   # мелкий боец ранен меньше чем на 4 — лечение не упирается в максимум
	var healed = a.current_hp - before
	_ticks(a, 4.0)
	_check("яд: лечение вдвое (%.1f из 4), через 4 с эффект снят" % healed,
		absf(healed - 2.0) < EPS and not a.status_effects.has(StatusEffects.POISONED))

	# 3. Огонь перекидывается на соседа (1 стак), сам наносит урон
	b.global_position = a.global_position + Vector2(20, 0)
	a.apply_status(StatusEffects.BURNING, 3.0, 3.0)
	_ticks(a, 1.0)
	_check("горение: через 1 с сосед в 20 px горит (1 стак)",
		b.get_status_stacks(StatusEffects.BURNING) == 1 and a.status_effects.has(StatusEffects.BURNING))
	# Огонь с остатком времени: пара соседей не поджигает друг друга по кругу
	_ticks(a, 0.1)
	for i in range(60):
		a.tick(TICK)
		b.tick(TICK)
	_check("горение гаснет: через 6 с ни один из пары не горит",
		not a.status_effects.has(StatusEffects.BURNING) and not b.status_effects.has(StatusEffects.BURNING))

	# 4. Усиление и замедление — множители, runtime-поля и UnitData не меняются
	var dmg = a.current_damage
	a.apply_status(StatusEffects.EMPOWERED, 0.2, 5.0)
	a.apply_status(StatusEffects.EMPOWERED, 0.2, 5.0)
	a.apply_status(StatusEffects.SLOWED, 0.4, 5.0, false)
	a.apply_status(StatusEffects.SLOWED, 0.4, 5.0, false)
	_check("усиление 2 стака ×%.2f, замедление аурой — 1 стак: бег ×%.2f, атака ×%.2f" % [a.get_damage_mult(), a.get_move_speed_mult(), a.get_attack_speed_mult()],
		absf(a.get_damage_mult() - 1.4) < EPS and a.get_status_stacks(StatusEffects.SLOWED) == 1
		and absf(a.get_move_speed_mult() - 0.6) < EPS and absf(a.get_attack_speed_mult() - 0.8) < EPS
		and absf(a.current_damage - dmg) < EPS)
	b.apply_status(StatusEffects.SLOWED, 0.4, 5.0)
	b.apply_status(StatusEffects.SLOWED, 0.4, 5.0)
	b.apply_status(StatusEffects.SLOWED, 0.4, 5.0)
	_check("замедление ударами — 3 стака, не ниже ×%.1f" % StatusEffects.MIN_SPEED_MULT,
		absf(b.get_move_speed_mult() - StatusEffects.MIN_SPEED_MULT) < EPS)

	# 5. Смерть от яда; у павшего эффекты сняты
	var c = tacs[2]
	# Яд за 1 с — 2 × доля бойца (unit_weight); раньше 1.5 HP «добивало» случайно: боец стоял в 18 px от горящего
	# и ловил огонь, при строе под размер модели (11.11.2026) — дальше 45 px
	c.current_hp = 1.5 * c.data.unit_weight
	c.apply_status(StatusEffects.POISONED, 2.0, 4.0)
	_ticks(c, 1.0)
	_check("яд добивает, у павшего эффектов нет", c.current_state == c.State.DEAD and c.status_effects.is_empty())

	# 6. Источники: Plague Marine травит ударом, Havoc поджигает снарядом
	var plague = UnitFactory.create("plague_marine")
	var havoc = UnitFactory.create("chaos_havoc")
	var chaplain_d = UnitFactory.create("chaplain")
	_check("источники в данных: чумные — яд, хавоки — огонь, Chaplain — клич усиления",
		plague.on_hit_status == StatusEffects.POISONED and havoc.on_hit_status == StatusEffects.BURNING
		and havoc.projectile != "" and chaplain_d.battle_cry_status == StatusEffects.EMPOWERED)
	scene._spawn_squad(plague, GameConstants.TEAM_ENEMY, Vector2i(2, 1), 1)
	var p = _of(1, "plague_marine")[0]
	var victim = _of(0, "assault_marine")[0]
	p.target = victim
	# Свой лист с hit_frame: урон — на кадре замаха, вплотную к цели
	p.global_position = victim.global_position + Vector2(20, 0)
	for i in range(2):
		p._do_attack()
		p._resolve_melee_hit()
	_check("удар чумного: +1 стак яда за удар (2 удара — 2 стака)", victim.get_status_stacks(StatusEffects.POISONED) == 2)

	# 7. Боевой клич Chaplain — один раз, союзникам в радиусе
	var chaplain = _of(0, "chaplain")[0]
	var near = _of(0, "assault_marine")[1]
	near.global_position = chaplain.global_position + Vector2(50, 0)
	chaplain.target = p
	chaplain.transition_to(chaplain.State.ATTACK)
	# Клич виден: кадр клича (лист Chaplain), первый выстрел — через BATTLE_CRY_TIME
	var cry_anim = chaplain.sprite.animation
	var cry_delay = chaplain.attack_timer
	chaplain.transition_to(chaplain.State.CHASE)
	chaplain.transition_to(chaplain.State.ATTACK)
	# Повторный вход: клича нет, стойка до первого выстрела со сдвигом бойца (отряд бьёт вразнобой)
	_check("клич Chaplain: союзник рядом усилен (1 стак, повторный вход в атаку не добавляет), кадр клича, выстрел через %.1f с" % cry_delay,
		near.get_status_stacks(StatusEffects.EMPOWERED) == 1 and chaplain.battle_cry_used
		and cry_anim == "battle_cry" and absf(cry_delay - chaplain.BATTLE_CRY_TIME) < EPS
		and chaplain.sprite.animation == "idle"
		and chaplain.attack_timer <= chaplain.ATTACK_STAGGER / chaplain.current_attack_speed + EPS)

	# 8. Святилище Slaanesh: аура замедляет врага в радиусе 1 стаком, вне радиуса — проходит за 0.5 с
	var wall_node = null
	for bld in bm.buildings:
		if bld.building_type == "pleasure_shrine":
			wall_node = bld
	p.global_position = wall_node.global_position + Vector2(30, 0)
	for i in range(5):
		wall_node.tick(TICK)
	var in_aura = p.get_move_speed_mult()
	var stacks_in = p.get_status_stacks(StatusEffects.SLOWED)
	p.global_position = wall_node.global_position + Vector2(1000, 0)
	wall_node.tick(TICK)
	_ticks(p, 0.6)
	_check("святилище: в ауре бег ×%.2f (1 стак), вне — замедление прошло" % in_aura,
		absf(in_aura - 0.55) < EPS and stacks_in == 1 and not p.status_effects.has(StatusEffects.SLOWED))

	scene.queue_free()
	await process_frame
	quit()
