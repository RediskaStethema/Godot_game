extends SceneTree

# Стена вокруг владений (KingdomWall, решение пользователя 22.10.2026): карта Fortress Wall клетку не занимает,
# стена — по контуру королевства и цитадели; физическая преграда: враг снаружи не входит через целое звено и
# ломает его, разбитое — проход, свои ходят сквозь; уровень такой же картой; щит цитадели — вспышкой по стене;
# сохранение (стена — вне клеток, старая стена на клетке переезжает с неё).
# Сохранение выключено — забег игрока не трогает.
#   godot --headless --path . -s tests/test_kingdom_wall.gd

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _squad(card: CardData) -> UnitData:
	var d = UnitFactory.create(card.unit_factory_id)
	d.squad_size = card.unit_count
	var hp: Array[float] = []
	for i in card.unit_count:
		hp.append(1.0)
	d.saved_hp = hp
	return d

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(7)
	for n in rm.map.nodes:
		if n.type == "battle" and n.wave == 3:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 3
	var tac = _squad(CardFactory.tactical_squad())
	bm.player_units = [tac] as Array[UnitData]
	bm.player_placements = {tac: Vector2i(1, 1)}
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(3)
	var s = current_scene

	# 1. Карта стены — на клетку своего отряда: стена встаёт, клетка не занята стеной, здания-узла нет
	var card := CardFactory.fortress_wall()
	var verdict0: String = s._drop_verdict(card, Vector2i(1, 1))
	var ok: bool = s._play_building_card(card, Vector2i(1, 1))
	var wall = bm.kingdom_wall
	_check("стена построена на клетке отряда (%s), клетку не заняла, здания-узла нет" % verdict0,
		ok and verdict0 == "playable" and wall != null and bm.player_buildings[card] == bm.WALL_TILE
		and s._get_player_squad_at(Vector2i(1, 1)) != null and bm.buildings.is_empty())
	var segs: Array = wall.segments
	var inside_all := iso_tiles_inside(s, wall)
	_check("контур: %d звеньев, внутри — вся рамка королевства и цитадель" % segs.size(),
		segs.size() >= 20 and inside_all and wall.is_inside(bm.citadel.global_position))

	# 2. Уровень: такая же карта на любую клетку — звенья крепче на 50%; на максимуме — нельзя
	var hp1: float = segs[0].max_hp
	var verdict1: String = s._drop_verdict(CardFactory.fortress_wall(), Vector2i(0, 0))
	s._play_building_card(CardFactory.fortress_wall(), Vector2i(0, 0))
	_check("стена → ур.2 (%s): звено %.0f → %.0f HP" % [verdict1, hp1, segs[0].max_hp],
		verdict1 == "compatible" and card.building_level == 2 and is_equal_approx(segs[0].max_hp, hp1 * 1.5))
	s._play_building_card(CardFactory.fortress_wall(), Vector2i(0, 0))
	_check("ур.3 — максимум: карта не тратится, ромб «нельзя»",
		not s._play_building_card(CardFactory.fortress_wall(), Vector2i(0, 0))
		and s._drop_verdict(CardFactory.fortress_wall(), Vector2i(0, 0)) == "invalid")

	# 3. Преграда: шаг снаружи внутрь через целое звено — стоп; изнутри наружу и снаружи вдоль — свободно
	var front_in: Vector2 = s.iso_grid.lattice_to_screen(3.6, 1.5)
	var front_out: Vector2 = s.iso_grid.lattice_to_screen(4.2, 1.5)
	var seg = wall.blocking_segment(front_out, front_in)
	_check("снаружи внутрь — звено; изнутри наружу и снаружи вдоль — нет",
		seg != null and wall.blocking_segment(front_in, front_out) == null
		and wall.blocking_segment(front_out, s.iso_grid.lattice_to_screen(4.2, 2.5)) == null)

	# 4. Бой: враг у стены упирается и ломает звено; звено разбито — проходит
	s._on_start_pressed(false)
	await _frames(2)
	_check("щит цитадели от стены (%.0f) — вспышкой по стене" % bm.citadel_shield,
		bm.citadel_shield >= card.get_building_stats()["shield"] and segs.all(func(x): return x.flash_left > 0.0))
	var enemy = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(1)[0]
	enemy.global_position = front_out
	enemy.transition_to(1)   # MOVE
	for i in 30:   # идёт к стене, пока не упрётся
		enemy._move_towards(front_in, 0.1)
		if enemy.wall_segment != null:
			break
	var pos0: Vector2 = enemy.global_position
	enemy._move_towards(front_in, 0.1)
	var blocked: bool = enemy.global_position == pos0 and enemy.wall_segment == seg and not wall.is_inside(pos0)
	var seg_hp: float = seg.hp
	enemy.attack_timer = 0.0
	enemy._attack_wall(0.1)
	await _frames(1)
	_check("враг упёрся в звено и ударил его (%.0f → %.0f HP)" % [seg_hp, seg.hp],
		blocked and (seg.hp < seg_hp or root.get_node("BattleManager").projectiles.size() > 0))
	seg.take_hit(seg.hp + 1.0)
	enemy._attack_wall(0.1)
	enemy._move_towards(front_in, 0.1)
	_check("звено разбито — враг идёт в пролом", seg.hp <= 0.0 and enemy.wall_segment == null
		and enemy.global_position != pos0)

	# 4б. Цель снаружи, а прямой путь срезает владения — враг обходит вдоль стены, не стоит и не ломает её
	# Точки — от отступа стены (MARGIN): снаружи у передней стороны и снаружи у задней
	var m: float = wall.MARGIN
	var u_front: float = s.iso_grid.grid_width - 0.5 + m
	var u_back: float = -1.5 - m
	var side_from: Vector2 = s.iso_grid.lattice_to_screen(u_front + 0.3, 3.2)
	var side_goal: Vector2 = s.iso_grid.lattice_to_screen(u_back - 0.4, 3.2)
	var side_seg = wall.blocking_segment(side_from, s.iso_grid.lattice_to_screen(u_front - 0.3, 3.2))
	var hp_before: float = side_seg.hp if side_seg else 0.0
	enemy.global_position = side_from
	var entered := false
	for i in 400:
		enemy._move_towards(side_goal, 0.1)
		entered = entered or wall.is_inside(enemy.global_position)
	var walked: float = enemy.global_position.distance_to(side_from)
	_check("цель за владениями: обход вдоль стены (прошёл %.0f px, внутрь — %s), звено цело" % [walked, entered],
		side_seg != null and not entered and walked > IsoGrid.TILE_WIDTH and enemy.wall_segment == null
		and side_seg.hp == hp_before)

	# 5. Свои — сквозь стену: боец игрока изнутри наружу через целое звено
	var other = segs.filter(func(x): return x.hp > 0.0 and x != seg)[0]
	var mine = root.get_node("SoldierRegistry").get_alive_soldiers_of_team(0)[0]
	var mid: Vector2 = other.global_position
	var lat: Vector2 = wall.lattice_of(mid)
	var inner: Vector2 = s.iso_grid.lattice_to_screen(lat.x - 0.2 * signf(lat.x - 1.5), lat.y)
	mine.global_position = inner
	var p_before: Vector2 = mine.global_position
	mine._move_towards(inner + (mid - inner) * 4.0, 0.1)
	_check("свой боец проходит сквозь стену", mine.global_position != p_before)
	bm.stop_battle()

	# 6. Сохранение: стена — вне клеток; старая стена на клетке переезжает с неё, две — одна уровнем выше
	var state: Dictionary = bm.save_state()
	var entry = state["buildings"].filter(func(e): return e["card"] == "fortress_wall")[0]
	state["buildings"] = [{"card": "fortress_wall", "tile": [0, 2], "level": 1},
		{"card": "fortress_wall", "tile": [1, 2], "level": 1}]
	bm.reset_run()
	bm.load_state(state)
	var walls = bm.player_buildings.keys().filter(func(c): return c.building_type == "wall")
	_check("сохранение: стена на %s; старые на клетках — одна вне поля, ур.2" % [entry["tile"]],
		entry["tile"] == [bm.WALL_TILE.x, bm.WALL_TILE.y] and walls.size() == 1
		and bm.player_buildings[walls[0]] == bm.WALL_TILE and walls[0].building_level == 2)
	quit()

# Все клетки рамки королевства — внутри стены
func iso_tiles_inside(s, wall) -> bool:
	for c in range(s.iso_grid.grid_width):
		for r in range(s.iso_grid.grid_height):
			if not wall.is_inside(s.iso_grid.tile_to_screen(Vector2i(c, r))):
				return false
	return true
