class_name BattleCardPlay
extends Node

# Розыгрыш карт на расстановке: бросок карты на клетку, слияние отрядов, здания, события, появление модельки из клетки
# (капсула, разлом варпа) и автостарт боя при минимальной руке. Узел-помощник BattleScene (вынесен 26.11.2026):
# поле, реестры отрядов и сообщения — у сцены (`scene`).
# Новый тип карты: функция play_<тип>(card, tile) -> bool + строка в _handlers (setup) + подсказка в CardData.PLAY_HINTS

const AUTO_START_DELAY: float = 1.0   # пауза между последней сыгранной картой и автостартом боя (сек, время дерева)
const UPGRADE_FX_RISE := Vector2(0, -48)   # знак карты-улучшения — над головами отряда

var scene: BattleScene
var _auto_start_pending: bool = false   # бой уже вот-вот начнётся сам (в руке MIN_HAND_CARDS карты)
# Тип карты → розыгрыш на клетку (card, tile) → разыграна ли
var _handlers: Dictionary = {}

func setup(battle: BattleScene) -> void:
	scene = battle
	_handlers = {
		"squad": play_squad,
		"upgrade": play_upgrade,
		"building": play_building,
		"event": play_event,
	}

# Метка Orbital Strike на клетке — до «В БОЙ» (и после «Продолжить»)
func add_strike_mark(tile: Vector2i) -> void:
	_strike_marks.append(TileGlow.target(scene.renderer, "strike", scene.iso_grid.tile_to_screen(tile)))

# «В БОЙ»: всё, что ещё появляется, — сразу на месте, метки ударов сняты
func settle() -> void:
	for pod in _drop_pods:   # капсула ещё падает / раскрывается — отряд сразу на месте
		if is_instance_valid(pod):
			pod.finish()
	_drop_pods.clear()
	for tw in _spawn_tweens:   # моделька ещё растёт из клетки / бойцы выходят из капсулы — сразу на месте
		if tw.is_valid():
			tw.custom_step(SPAWN_TIME + POD_EXIT_TIME + POD_EXIT_STAGGER * 16.0)
	_spawn_tweens.clear()
	for mark in _strike_marks:   # удар — в начале боя, метка больше не нужна
		if is_instance_valid(mark):
			mark.queue_free()
	_strike_marks.clear()

func on_card_dropped(card: CardData, screen_pos: Vector2) -> void:
	scene._update_drag_target(null, Vector2i.ZERO)   # карту отпустили — ромб под ней гаснет
	if not scene.is_placement_phase:
		return
	var tile = scene.iso_grid.screen_to_tile(scene._screen_to_world(screen_pos))
	if not scene.iso_grid.is_valid_tile(tile):
		scene._show_message("Мимо сетки")
		return
	var handler: Callable = _handlers.get(card.card_type, Callable())
	if not handler.is_valid():
		scene._show_message("%s: эту карту нельзя сыграть на поле" % card.display_title())
		return
	if scene._tutorial_live() and not scene.tutorial.allow_drop(card, tile):   # обучение: пока есть цель — только она и её клетка
		return
	if hand_floor_applies() and BattleManager.pending_cards.size() <= BattleManager.MIN_HAND_CARDS:
		scene._show_message("В руке должны остаться %d карты — «В БОЙ»" % BattleManager.MIN_HAND_CARDS)
		return
	if handler.call(card, tile):
		AudioManager.play("place")
		consume_bench_card(card)
		scene._tutorial_notify("card_played", card)
		auto_start_if_hand_low()

# Правило минимальной руки (решение пользователя 17.11.2026) действует везде, кроме тестового режима и расстановки
# перед финальным боссом (волна 15 — BOSS): там можно сыграть всё
func hand_floor_applies() -> bool:
	if scene._tutorial_live() and scene.tutorial.exempts_hand_floor():   # обучение ведёт карту (орудие) на клетку — рука может опустеть
		return false
	return not RunManager.test_mode and scene.battle_type != RunMapNode.BOSS

# Сыграна карта, в руке осталось MIN_HAND_CARDS — бой начинается сам (после короткой паузы: карта «приземляется»)
func auto_start_if_hand_low() -> void:
	if not hand_floor_applies() or _auto_start_pending or BattleManager.pending_cards.size() > BattleManager.MIN_HAND_CARDS:
		return
	if scene._tutorial_live() and (scene.tutorial.holds_start() or scene.tutorial.no_auto_start()):   # обучение: бой — только кнопкой «В БОЙ»
		return
	_auto_start_pending = true
	scene._show_message("В руке %d карты — бой начинается" % BattleManager.MIN_HAND_CARDS)
	scene.get_tree().create_timer(AUTO_START_DELAY, false).timeout.connect(_auto_start_fire, CONNECT_ONE_SHOT)

func _auto_start_fire() -> void:
	_auto_start_pending = false
	if scene.is_inside_tree() and scene.is_placement_phase and not scene.shop_phase and not BattleManager.is_battle_running():
		scene._on_start_pressed()

# Отряд на пустую клетку; на свой отряд того же типа — улучшение с лечением (merge_squad)
func play_squad(card: CardData, tile: Vector2i) -> bool:
	var own = scene._get_player_squad_at(tile)
	if own and own.data.factory_id == card.unit_factory_id:
		return merge_squad(card, own)
	if scene._is_tile_occupied(tile):
		scene._show_message("Тайл занят")
		return false
	var unit_data = UnitFactory.create(card.unit_factory_id)
	unit_data.squad_size = card.unit_count
	unit_data.squad_growth = UnitFactory.squad_growth_for(card)
	var squad := scene._spawn_squad(unit_data, GameConstants.TEAM_PLAYER, tile, card.unit_count)
	if RunManager.test_mode:   # тест: отряд сразу нужного уровня (как слиянием — с пополнением бойцов)
		for i in RunManager.test_level:
			squad.merge_upgrade()
	materialize(squad)
	return true

# Улучшение бросают НА свой отряд
func play_upgrade(card: CardData, tile: Vector2i) -> bool:
	var squad = scene._get_player_squad_at(tile)
	if squad == null:
		scene._show_message("%s: перетащите на свой отряд" % card.display_title())
		return false
	if card.upgrade_type in ["blessing", "change_god"]:
		return _play_god(card, squad)
	if not squad.apply_upgrade(card):
		scene._show_message("%s: не подходит этому отряду (только «%s», знамя не складывается)" % [card.display_title(), card.affects_tag])
		return false
	# Знак карты над отрядом (у Хаоса — свои id карт: daemonic_armour, icon_of_chaos…)
	Vfx.spawn(scene.units_container, "upgrade_" + card.id, squad.global_position + UPGRADE_FX_RISE)
	scene._show_message("%s → %s (%s)" % [card.display_title(), squad.data.display_name(), card.description])
	return true

# Карты богов Хаоса (ChaosGods, решение пользователя 25.10.2026): благословение — только на отряд своего бога, до 3 раз;
# «Chaos Gods' Blessing» — на любой отряд Хаоса (и Common без бога): окно выбора бога, карта уходит из руки по выбору
# (Отмена — остаётся)
func _play_god(card: CardData, squad: Squad) -> bool:
	var god: String = squad.data.get_god()
	if not "chaos" in squad.data.tags:
		scene._show_message("%s: только на отряд Кровоподписантов" % card.display_title())
		return false
	if card.upgrade_type == "change_god":
		var dialog := GodPickDialog.new()
		scene.get_node("UI").add_child(dialog)
		dialog.setup(squad.data.display_name(), god)
		dialog.chosen.connect(_on_god_chosen.bind(card, squad))
		return false   # карта уйдёт из руки, когда бог выбран (_on_god_chosen)
	if god == "":
		scene._show_message("%s: у отряда нет бога — сначала «Recasting»" % card.display_title())
		return false
	if card.blessing_god != god:
		scene._show_message("%s: только на отряд бога %s (у этого — %s)" % [card.display_title(), ChaosGods.god_name(card.blessing_god),
			ChaosGods.god_name(god)])
		return false
	if squad.data.blessings >= ChaosGods.MAX_BLESSINGS:
		scene._show_message("%s: у отряда уже %d/%d благословений" % [card.display_title(), squad.data.blessings, ChaosGods.MAX_BLESSINGS])
		return false
	if not squad.apply_upgrade(card):   # Вестник — только стрелкам
		scene._show_message("%s: действует только на стрелков" % card.display_title())
		return false
	scene._bless_sigils(squad)
	scene._show_message("%s → %s: %s" % [card.display_title(), squad.data.display_name(),
		ChaosGods.describe(squad.data.get_god(), squad.data.blessings, squad.data.tags)])
	return true

func _on_god_chosen(new_god: String, card: CardData, squad: Squad) -> void:
	if not is_instance_valid(squad) or not scene.is_placement_phase or not scene.bench.bench_cards.has(card):
		return
	squad.data.change_god(new_god)
	for s in squad.soldiers:
		s.refresh_stats_from_data()
	scene._bless_sigils(squad)
	AudioManager.play("place")
	scene._show_message("%s теперь служит богу %s" % [squad.data.display_name(), ChaosGods.god_name(new_god)])
	consume_bench_card(card)

# Здание на пустую клетку; такая же карта на своё здание — уровень +1. Стена владений — на любую клетку
func play_building(card: CardData, tile: Vector2i) -> bool:
	if card.building_type == "wall":
		return _play_wall(card)
	var own = scene._get_player_building_at(tile)
	if own and own.card.id == card.id:
		if not own.card.level_up_building():
			scene._show_message("%s: максимальный уровень" % own.card.display_title())
			return false
		var from_scale: Vector2 = own.sprite.scale if own.sprite else Vector2.ONE
		own.refresh_stats()
		own.play_level_up(from_scale)
		TileGlow.burst(scene.renderer, own.global_position, "level", own.card.faction)
		AudioManager.play("building_level_up")
		scene._show_message("%s улучшено до уровня %d/%d" % [own.card.display_title(), own.card.building_level, CardData.MAX_BUILDING_LEVEL])
		scene._tutorial_notify("building_level")
		return true
	if scene._is_tile_occupied(tile):
		scene._show_message("Тайл занят")
		return false
	if RunManager.test_mode:   # тест: здание сразу нужного уровня
		while card.building_level < 1 + RunManager.test_level and card.level_up_building():
			pass
	materialize(scene._spawn_building(card, tile))
	BattleManager.player_buildings[card] = tile
	scene._show_message("Построено: %s" % card.display_title())
	return true

# Стена владений (решение пользователя 22.10.2026): клетку не занимает. Нет стены — вырастает по контуру,
# есть — уровень +1 (звенья крепче, щит больше)
func _play_wall(card: CardData) -> bool:
	var own := BattleManager.get_wall_card()
	if own:
		if not own.level_up_building():
			scene._show_message("%s: максимальный уровень" % own.display_title())
			return false
		BattleManager.kingdom_wall.refresh_stats()
		BattleManager.kingdom_wall.flash_shield()
		scene._show_message("%s улучшена до уровня %d/%d" % [own.display_title(), own.building_level, CardData.MAX_BUILDING_LEVEL])
		scene._tutorial_notify("building_level")
		return true
	BattleManager.player_buildings[card] = BattleManager.WALL_TILE
	scene._build_kingdom_wall(true)
	AudioManager.play("tile_bought")
	scene._show_message("Возведена стена вокруг владений: %s" % card.display_title())
	return true

# Карты-события: подкрепление — сразу отряд; орбитальный удар — заряжается до боя
func play_event(card: CardData, tile: Vector2i) -> bool:
	match card.event_type:
		"reinforcements":
			if scene._is_tile_occupied(tile):
				scene._show_message("%s: нужна пустая клетка" % card.display_title())
				return false
			# Своя случайность (забег, шаг, клетка): общий RunManager.rng не сдвигается — наборы магазина те же
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([RunManager.rng.seed, RunManager.current_node_id, tile])
			var squad_card = CardFactory.random_squad_card(card.event_stats.get("rarity", "common"), rng)
			var unit_data = UnitFactory.create(squad_card.unit_factory_id)
			unit_data.squad_size = squad_card.unit_count
			unit_data.squad_growth = UnitFactory.squad_growth_for(squad_card)
			materialize(scene._spawn_squad(unit_data, GameConstants.TEAM_PLAYER, tile, squad_card.unit_count))
			scene._show_message("Подкрепление: %s" % squad_card.title)
			return true
		"orbital_strike":
			BattleManager.armed_events.append(card.id)
			BattleManager.armed_tiles.append(tile)
			_strike_marks.append(TileGlow.target(scene.renderer, "strike", scene.iso_grid.tile_to_screen(tile)))
			scene._show_message("Орбитальный удар наведён: ударит в начале боя")
			return true
	return false

# Карта легла на клетку — моделька проявляется (решение пользователя 21.10.2026: на поле кладут карту, а не
# модельку): вырастает из клетки — на каждом бойце свет телепорта (LevelUpGlow "arrive", у Хаоса — бордо), под
# зданием волна света по клетке (TileGlow "build"); решение пользователя 22.10.2026: столбы и «вата» пакета
# выбивались из стиля. Только вид, расстановка
const SPAWN_TIME: float = 0.3
const SPAWN_FROM_SCALE: float = 0.35
var _spawn_tweens: Array[Tween] = []   # «В БОЙ» раньше конца — доводим сразу (масштаб отряда сдвигает бойцов)
var _strike_marks: Array = []          # метки Orbital Strike на клетках (TileGlow) — до «В БОЙ»
var _drop_pods: Array = []             # капсулы в полёте / раскрытии — «В БОЙ» доводит сразу (DropPod.finish)
func materialize(node: Node2D) -> void:
	# Отряд Космодесанта на пустую клетку — прилетает в десантной капсуле (решение пользователя 12.11.2026,
	# ART_TZ_DROP_POD_2026-11-12.txt): пока капсула падает и раскрывается, отряда не видно; виден — с кадра,
	# когда падают двери (DropPod.REVEAL_FRAME), дальше — как обычно (вырастает из клетки). Хаос — разлом варпа
	if node is Squad and node.team == GameConstants.TEAM_PLAYER:
		var chaos: bool = RunManager.player_faction == "chaos"
		if not chaos and DropPod.available():
			node.modulate.a = 0.0
			_drop_pods = _drop_pods.filter(func(p): return is_instance_valid(p))
			_drop_pods.append(DropPod.drop(scene.units_container, node.position, node.data.tags.has("vehicle"),
				_pod_exit.bind(node)))
			return
		if chaos:
			BuildingFx.rift(node.global_position, Soldier.TARGET_SPRITE_HEIGHT * node.data.sprite_scale * 1.6)
	_grow_in(node, true)

# Моделька вырастает из клетки и проявляется; glow — свет на бойцах / волна по клетке здания
func _grow_in(node: Node2D, glow: bool) -> void:
	if not is_instance_valid(node):
		return
	node.scale = Vector2(SPAWN_FROM_SCALE, SPAWN_FROM_SCALE)
	node.modulate.a = 0.0
	var tw := node.create_tween().set_parallel(true)
	_spawn_tweens = _spawn_tweens.filter(func(t: Tween): return t.is_valid())
	_spawn_tweens.append(tw)
	tw.tween_property(node, "scale", Vector2.ONE, SPAWN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, SPAWN_TIME * 0.6)
	if not glow:
		return
	if node is Building:
		TileGlow.burst(scene.renderer, node.global_position, "build", node.card.faction)
	elif node is Squad:
		scene._glow_soldiers(node, "arrive")

# Выход из капсулы (решение пользователя 12.11.2026, стилизация «удар и выход»): двери упали — бойцы выбегают
# от дверей (чуть впереди центра клетки) на свои места в строю, по очереди, бегом; отряд виден сразу.
# «В БОЙ» раньше конца — твины доводятся (_spawn_tweens), бойцы на местах и в стойке
const POD_EXIT_TIME: float = 0.45
const POD_EXIT_STAGGER: float = 0.05
const POD_EXIT_FROM := Vector2(0.0, 6.0)   # точка дверей относительно клетки, px мира
const POD_EXIT_FADE: float = 0.12
func _pod_exit(squad: Squad) -> void:
	if not is_instance_valid(squad):
		return
	squad.scale = Vector2.ONE
	squad.modulate.a = 1.0
	var alive: Array = squad.soldiers.filter(func(s): return s.current_state != Soldier.State.DEAD)
	_spawn_tweens = _spawn_tweens.filter(func(t: Tween): return t.is_valid())
	for i in alive.size():
		var s: Soldier = alive[i]
		var target: Vector2 = s.position
		s.position = POD_EXIT_FROM
		s.modulate.a = 0.0
		var dist := target.distance_to(POD_EXIT_FROM)
		var tw := s.create_tween()
		_spawn_tweens.append(tw)
		tw.tween_interval(i * POD_EXIT_STAGGER)
		tw.tween_callback(func(): s.deploy_walk(dist / POD_EXIT_TIME, target - POD_EXIT_FROM))
		tw.tween_property(s, "modulate:a", 1.0, POD_EXIT_FADE)
		tw.parallel().tween_property(s, "position", target, POD_EXIT_TIME).set_trans(Tween.TRANS_SINE) 			.set_ease(Tween.EASE_OUT)
		tw.tween_callback(s.deploy_stand)

# Карта отряда на свой отряд того же типа (решение пользователя 21.10.2026, меню «улучшить / вылечить» убрано):
# уровень +1 (бойцы роста — с полным HP), затем лечение — живым доля max HP, павшие возвращаются с той же долей.
# На максимальном уровне — только лечение; отряд здоров и на максимуме — карта не тратится
func merge_squad(card: CardData, squad: Squad) -> bool:
	var leveled := squad.merge_upgrade()
	if not leveled and not squad.is_wounded():
		scene._show_message("%s: максимальный уровень, отряд здоров" % squad.data.display_name())
		return false
	var revived := squad.heal_by_ratio(UnitFactory.get_merge_bonuses(squad.data.faction)["heal"])
	# Уровень — свет на каждом бойце (Squad.merge_upgrade → LevelUpGlow), только лечение — зелёный свет на бойцах
	if not leveled:
		scene._glow_soldiers(squad, "heal")
	var extra := ", вернулось бойцов: %d" % revived if revived > 0 else ""
	if leveled:
		scene._show_message("%s улучшен до уровня %d/%d и вылечен%s" % [squad.data.display_name(),
			squad.data.squad_level, UnitFactory.MAX_SQUAD_LEVEL, extra])
	else:
		scene._show_message("%s вылечен%s (уровень максимальный)" % [squad.data.display_name(), extra])
	scene._update_synergy_preview()
	scene._tutorial_notify("merge")
	return true

func consume_bench_card(card: CardData) -> void:
	scene.bench.bench_cards.erase(card)
	scene.bench._populate()
	scene._save_placement()
