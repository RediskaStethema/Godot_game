extends SceneTree

# Код под ассеты (решение пользователя 16.10.2026): графика и звук подключаются, как только
# появятся файлы. Листы и звуки здесь — сгенерированные в памяти (своих ассетов ещё нет):
# 1) здание со своим листом (Building: idle / attack / refill, уровни idle_2…): спрайт вместо блоков,
#    размер под клетку, рамка для прозрачности, выстрел из ствола листа, вид уровня, портрет карты;
#    без листа — блоки, как раньше;
# 2) Казармы вернули бойцов — анимация refill;
# 3) Apothecary с рядом heal — лечит → heal, некого лечить → стойка;
# 4) броня в цвет ордена: свои — шейдер с тоном ордена (Ultramarines — синий листа, темнее), враги — как нарисовано,
#    вспышка попадания не снимает перекраску;
# 5) звук: шины, событие без файла — тихо, с потоком — играет, предел частоты, выстрел снаряда и
#    музыка магазина вызывают свои события;
# 6) пакет эффектов (EFFECTS_NEEDED.txt): розыгрыш карт и начало боя вызывают свои эффекты, ромб под картой.
# Классы сцен по имени не упоминаются (скрипт компилируется до автолоадов) — через load().
#   godot --headless --path . -s tests/test_asset_hooks.gd

const BUILDING := "res://scripts/battle/Building.gd"
const SOLDIER := "res://scripts/battle/Soldier.gd"
const UI_THEME := "res://scripts/ui/UITheme.gd"

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _tex(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

func _sheet(anims: Dictionary) -> SpriteFrames:
	var f := SpriteFrames.new()
	f.remove_animation("default")
	for a in anims:
		f.add_animation(a)
		f.set_animation_loop(a, a.begins_with("idle") or a == "walk")
		f.set_animation_speed(a, 10.0)
		for i in anims[a]:
			f.add_frame(a, _tex(60, 80, Color(0.3, 0.4, 0.6)))
	return f

func _squad_unit(id: String, n: int, hp: float = 1.0) -> UnitData:
	var d = UnitFactory.create(id)
	d.squad_size = n
	var list: Array[float] = []
	for i in n:
		list.append(hp)
	d.saved_hp = list
	return d

func _battle(units: Array[UnitData], buildings: Dictionary = {}, placements: Dictionary = {}) -> Node:
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	var chapter: String = rm.player_chapter
	bm.reset_run()
	rm.new_run(3)
	rm.player_chapter = chapter
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	bm.player_units = units
	bm.player_placements = placements
	bm.player_buildings = buildings
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(3)
	return current_scene

func _main() -> void:
	await process_frame
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	var reg = root.get_node("SoldierRegistry")
	var B = load(BUILDING)
	var S = load(SOLDIER)

	# 1. Здание со своим листом: турель
	var tower_frames := _sheet({"idle": 2, "attack": 3, "idle_2": 2})
	tower_frames.set_meta("muzzle", Vector2(20, -60))
	tower_frames.set_meta("shot_frame", 1)
	B._frames_cache["space_marines/tower"] = tower_frames
	B._frames_cache["space_marines/generator"] = null
	var turret = CardFactory.bolter_turret()
	var gen = CardFactory.plasma_generatorium()
	await _battle([_squad_unit("tactical_marine", 3)] as Array[UnitData], {turret: Vector2i(0, 0), gen: Vector2i(0, 2)})
	var t = bm.buildings.filter(func(b): return b.card == turret)[0]
	var w = bm.buildings.filter(func(b): return b.card == gen)[0]
	var occ: Rect2 = t.get_occlusion_rect()
	var width_ok := absf(occ.size.x - 140.0 * B.SPRITE_WIDTH) < 1.0
	_check("здание со своим листом: спрайт вместо блоков (ширина %.0f ≈ %.0f), рамка прозрачности по нему; без листа — блоки" % [
		occ.size.x, 140.0 * B.SPRITE_WIDTH], t.sprite != null and width_ok and t.sprite.animation == "idle" and w.sprite == null)
	turret.level_up_building()
	t.refresh_stats()
	var portrait = load(UI_THEME).card_portrait(turret)
	_check("уровень 2 — вид idle_2; портрет карты — кадр листа", t.sprite.animation == "idle_2"
		and portrait == tower_frames.get_frame_texture("idle", 0))
	current_scene._on_start_pressed(false)
	bm.set_process(false)
	var enemy = reg.get_alive_soldiers_of_team(1)[0]
	t.attack_timer = 0.0
	t.tick(0.1)
	var shot = bm.projectiles[-1] if not bm.projectiles.is_empty() else null
	var expect_muzzle: Vector2 = t._sprite_muzzle()
	_check("выстрел турели: анимация attack, снаряд из ствола листа на кадре вспышки",
		t.sprite.animation == "attack" and shot != null and shot._origin.distance_to(expect_muzzle) < 0.5 and shot._delay > 0.0)
	# У ряда выстрела уровня свои стволы (пакет 05.11.2026): metadata/level_muzzle {уровень: Vector2}
	tower_frames.add_animation("attack_2")
	tower_frames.set_animation_loop("attack_2", false)
	for i in 3:
		tower_frames.add_frame("attack_2", tower_frames.get_frame_texture("attack", i))
	var before: Vector2 = t._sprite_muzzle()   # ряд уровня есть, точки уровня нет — ствол 1-го уровня
	tower_frames.set_meta("level_muzzle", {2: Vector2(-30, -90)})
	var after: Vector2 = t._sprite_muzzle()
	var d: Vector2 = Vector2(-30 - 20, -90 + 60) * t._level_k
	if t.aim.x < 0.0:
		d.x = -d.x
	var expect_delta: Vector2 = t.global_transform.basis_xform(d)
	t.attack_timer = 0.0
	t.tick(0.1)
	var shot2 = bm.projectiles[-1] if not bm.projectiles.is_empty() else null
	_check("ствол уровня: metadata/level_muzzle — снаряд из своего ствола ряда attack_2 (сдвиг %s ≈ %s)" % [after - before, expect_delta],
		(after - before).distance_to(expect_delta) < 0.5 and t.sprite.animation == "attack_2"
		and shot2 != null and shot2 != shot and shot2._origin.distance_to(after) < 0.5)
	# Heretic Autocannon не разворачивается (решение пользователя 13.11.2026, Building.NO_FLIP): цель слева —
	# спрайт как нарисован, ствол на своём месте; Bolter Turret — отражается, как раньше
	var aim_was: Vector2 = t.aim
	t.aim = Vector2(1, 0)
	var right_x: float = t.to_local(t._sprite_muzzle()).x   # ствол при выстреле вправо — как нарисован
	t.aim = Vector2(-1, 0)
	t.play_once("attack")
	var sm_flip: bool = t.sprite.flip_h
	var sm_x: float = t.to_local(t._sprite_muzzle()).x
	turret.faction = "chaos"
	t.play_once("attack")
	var ch_flip: bool = t.sprite.flip_h
	var ch_x: float = t.to_local(t._sprite_muzzle()).x
	turret.faction = ""
	t.aim = aim_was
	t._set_flip(false)
	_check("Heretic Autocannon: цель слева — не отражается, ствол как нарисован (%.0f = %.0f); Bolter Turret — отражён (%.0f)" % [
		ch_x, right_x, sm_x], sm_flip and not ch_flip and absf(ch_x - right_x) < 0.5 and absf(sm_x + right_x) < 0.5
		and absf(right_x) > 1.0)
	# Залп (06.11.2026): metadata/level_barrels — снаряд из каждого ствола, урон поровну, сумма прежняя
	tower_frames.set_meta("level_barrels", {2: [Vector2(-30, -90), Vector2(-30, -70), Vector2(-10, -80)]})
	var n_before: int = bm.projectiles.size()
	t.attack_timer = 0.0
	t.tick(0.1)
	var volley: Array = bm.projectiles.slice(n_before)
	var total := 0.0
	var origins := {}
	for s in volley:
		total += s.damage
		origins[Vector2i(s._origin.round())] = true
	_check("залп: 3 ствола — 3 снаряда из разных точек, урон %.2f = %.2f" % [total, t.stats["damage"]],
		volley.size() == 3 and origins.size() == 3 and is_equal_approx(total, t.stats["damage"])
		and volley[0]._origin.distance_to(after) < 0.5)
	tower_frames.remove_meta("level_barrels")
	bm.stop_battle()

	# 2. Казармы вернули бойцов — анимация refill
	B._frames_cache["space_marines/barracks"] = _sheet({"idle": 2, "refill": 3})
	var barracks = CardFactory.barracks()
	var wounded = _squad_unit("tactical_marine", 9)
	wounded.saved_hp = [1.0, 1.0, 1.0] as Array[float]
	await _battle([wounded] as Array[UnitData], {barracks: Vector2i(1, 1)}, {wounded: Vector2i(1, 0)})
	var bb = bm.buildings.filter(func(b): return b.card == barracks)[0]
	var added: int = bm.refill_from_barracks()
	_check("Казармы вернули бойцов (%d) — анимация refill" % added, added > 0 and bb.sprite.animation == "refill")
	for k in ["space_marines/tower", "space_marines/generator", "space_marines/barracks"]:
		B._frames_cache.erase(k)

	# 3. Apothecary с рядом heal
	var apo_path: String = UnitFactory.create("apothecary").sprite_path
	var old_frames = S._frames_cache.get(apo_path)
	S._frames_cache[apo_path] = _sheet({"idle": 2, "walk": 2, "attack": 2, "death": 2, "heal": 2})
	await _battle([_squad_unit("apothecary", 2), _squad_unit("tactical_marine", 3, 0.3)] as Array[UnitData])
	var apo = reg.get_alive_soldiers_of_team(0).filter(func(s): return s.data.factory_id == "apothecary")[0]
	var patient = reg.get_alive_soldiers_of_team(0).filter(func(s): return s.data.factory_id == "tactical_marine")[0]
	patient.global_position = apo.global_position + Vector2(20, 0)
	apo.current_state = apo.State.ATTACK   # лечит, когда не стоит в строю
	apo.sprite.play("idle")
	apo._tick_support(0.1)
	var healing_anim: bool = apo.sprite.animation == "heal"
	for s in reg.get_alive_soldiers_of_team(0):
		s.current_hp = s.max_hp
	apo._tick_support(0.1)
	_check("Apothecary с рядом heal: лечит — heal, некого — стойка", healing_anim and apo.sprite.animation == "idle")
	if old_frames:
		S._frames_cache[apo_path] = old_frames
	else:
		S._frames_cache.erase(apo_path)

	# 4. Броня в цвет ордена
	rm.player_chapter = "blood_angels"
	await _battle([_squad_unit("tactical_marine", 3)] as Array[UnitData])
	var marine = reg.get_alive_soldiers_of_team(0)[0]
	var foe = reg.get_alive_soldiers_of_team(1)[0]
	var mat = marine.sprite.material
	var ba_hue: float = load("res://scripts/data/Chapters.gd").get_chapter("blood_angels")["armor"]["hue"]
	var red_ok: bool = mat is ShaderMaterial and is_equal_approx(mat.get_shader_parameter("target_hue"), ba_hue)
	marine.take_damage(1.0)
	var flash_mat = marine.sprite.material
	var flashing: bool = flash_mat is ShaderMaterial and flash_mat.get_shader_parameter("flash") > 0.0 \
		and is_equal_approx(flash_mat.get_shader_parameter("target_hue"), ba_hue)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300:
		await process_frame
	var foe_mat = foe.sprite.material
	var foe_ok: bool = foe_mat is ShaderMaterial and not foe_mat.get_shader_parameter("armor") 		and foe_mat.get_shader_parameter("outline_px") > 0.0
	_check("Blood Angels: броня красная, враг как нарисован (только контур); вспышка — с перекраской, после — снова цвет ордена",
		red_ok and foe_ok and flashing and marine.sprite.material == mat)
	rm.player_chapter = "ultramarines"
	await _battle([_squad_unit("tactical_marine", 3)] as Array[UnitData])
	var um_mat = reg.get_alive_soldiers_of_team(0)[0].sprite.material
	var um: Dictionary = load("res://scripts/data/Chapters.gd").get_chapter("ultramarines")["armor"]
	_check("Ultramarines — синий листа, но темнее (шейдер: тон %.3f, яркость ×%.2f)" % [um["hue"], um["val"]],
		um_mat is ShaderMaterial and is_equal_approx(um_mat.get_shader_parameter("target_hue"), um["hue"])
		and um_mat.get_shader_parameter("val_mult") < 1.0)
	rm.player_chapter = ""

	# 5. Звук
	var audio = root.get_node("AudioManager")
	var buses_ok: bool = AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("Music") >= 0
	audio.record_history = true
	audio.set_streams("shot_bolt", [])   # как будто файла нет — не зависит от assets/audio
	var silent: bool = not audio.play("shot_bolt") and audio.history[-1] == "shot_bolt (нет файла)"
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var pcm := PackedByteArray()
	pcm.resize(2205 * 2)
	wav.data = pcm
	audio.set_streams("ui_click", [wav])
	audio._last_play.erase("ui_click")
	var played := 0
	for i in 40:
		if audio.play("ui_click"):
			played += 1
	_check("звук: шины SFX / Music; без файла — тихо; с потоком — играет, не чаще предела (%d из 40, предел %d)" % [
		played, audio.EVENTS["ui_click"]["max_per_sec"]], buses_ok and silent and played > 0
		and played <= audio.EVENTS["ui_click"]["max_per_sec"])
	audio.history.clear()
	await _battle([_squad_unit("tactical_marine", 3)] as Array[UnitData])
	var P = load("res://scripts/battle/Projectile.gd")
	P.launch(current_scene, "bolt", Vector2.ZERO, null, Vector2(100, 0)).tick(0.1)   # звук — при вылете из ствола
	_check("события звука: музыка боя, выстрел снаряда (%s)" % ", ".join(audio.history.slice(0, 4)),
		audio.current_music() == "battle" and audio.history.any(func(h): return h.begins_with("shot_bolt")))
	# Пакет звуков пользователя (09.11.2026): у подключённых событий есть файлы в assets/audio, музыка menu / shop /
	# battle грузится, боя с боссом своего трека нет — запасной боевой
	audio._streams.clear()   # сброс подмен выше — дальше настоящие файлы
	var need := ["shot_bolt", "shot_spark", "shot_charged", "melee_hit", "death", "death_vehicle", "hit", "buy", "place",
		"reroll", "sell", "ui_click", "pause", "no_money", "step", "step_heavy", "boss_step"]
	var missing: Array = need.filter(func(e): return audio._get_streams(e).is_empty())
	var music_ok: bool = ["menu", "shop", "battle"].all(func(t): return audio._find_music(t) != null)
	var boss_fallback: bool = audio._find_music("boss") == null and audio._find_music(audio.MUSIC_FALLBACK["boss"]) != null
	_check("звуки пакета: у %d событий файлы (нет у: %s), музыка menu / shop / battle, босс — боевая" % [
		need.size() - missing.size(), str(missing)], missing.is_empty() and music_ok and boss_fallback)
	# Щелчок у любой кнопки дерева (09.11.2026: кнопки не из UITheme.make_button молчали); со своим звуком — без щелчка
	var plain := Button.new()
	var own := Button.new()
	own.set_meta(audio.NO_CLICK, true)
	current_scene.add_child(plain)
	current_scene.add_child(own)
	audio._last_play.erase("ui_click")
	audio.history.clear()
	plain.button_down.emit()
	var plain_clicks: int = audio.history.count("ui_click")
	own.button_down.emit()
	var own_clicks: int = audio.history.count("ui_click") - plain_clicks
	plain.queue_free()
	own.queue_free()
	_check("щелчок: у кнопки Button.new() — есть (%d), у кнопки со своим звуком — нет (%d)" % [plain_clicks, own_clicks],
		plain_clicks == 1 and own_clicks == 0)
	bm.stop_battle()
	await _effects_pack()
	quit()

# 6. Пакет эффектов (EFFECTS_NEEDED.txt, листы tools/fx_fix.py): розыгрыш карт на расстановке и начало боя
# вызывают свои эффекты; ромб под перетаскиваемой картой — по клетке; вариант расы
func _has_fx(parent: Node, kind: String) -> bool:
	var V = load("res://scripts/battle/Vfx.gd")
	var frames: SpriteFrames = V._get_frames(kind)
	return parent.get_children().any(func(c): return c is AnimatedSprite2D and c.sprite_frames == frames)

# Уровень / появление отряда — свет на каждом бойце (LevelUpGlow: кольцо за спрайтом и свет перед ним)
func _has_level_glow(squad, kind: String = "level") -> bool:
	return squad != null and squad.soldiers.all(func(s): return s.get_children().filter(func(c):
		return c.get_script() != null and c.get_script().resource_path.ends_with("LevelUpGlow.gd") and c.kind == kind).size() == 2)

# Свечение клетки (TileGlow) вида look — в рендерере поля
func _has_tile_glow(renderer, look: String) -> bool:
	for c in renderer.get_children():
		if c.get_script() != null and c.get_script().resource_path.ends_with("TileGlow.gd") 				and c.verdict == look and not c.is_queued_for_deletion():
			return true
	return false

func _effects_pack() -> void:
	var bm = root.get_node("BattleManager")
	var V = load("res://scripts/battle/Vfx.gd")
	var wall = CardFactory.fortress_wall()
	var own = _squad_unit("tactical_marine", 9)
	# стена владений — вне клеток; на (0, 2) — здание (ромб «нельзя»)
	await _battle([own] as Array[UnitData], {wall: bm.WALL_TILE, CardFactory.plasma_generatorium(): Vector2i(0, 2)},
		{own: Vector2i(1, 1)})
	var s = current_scene
	var units: Node = s.units_container
	var tactical = CardFactory.create("tactical_squad")
	s._play_squad_card(tactical, Vector2i(2, 1))
	s._play_building_card(CardFactory.plasma_generatorium(), Vector2i(2, 2))
	# отряд Космодесанта — в десантной капсуле (DropPod, 12.11.2026): пока она падает — отряда не видно,
	# «В БОЙ» раньше конца — капсула снята, отряд проявляется
	var dropped = s._get_player_squad_at(Vector2i(2, 1))
	var pods: Array = units.get_children().filter(func(c): return c.get_script() != null 		and c.get_script().resource_path.ends_with("DropPod.gd"))
	var pod_ok: bool = pods.size() == 1 and dropped.modulate.a == 0.0
	for pod in s._drop_pods:
		pod.finish()
	pod_ok = pod_ok and s._spawn_tweens.any(func(t): return t.is_valid())
	var arrive_build: bool = pod_ok and _has_tile_glow(s.renderer, "build")
	s._merge_squad(tactical, s._get_player_squad_at(Vector2i(1, 1)))
	s._play_upgrade_card(CardFactory.create("battle_fury"), Vector2i(1, 1))
	s._play_event_card(CardFactory.create("orbital_strike"), Vector2i(0, 1))
	_check("расстановка: отряд — десантная капсула (снимается по «В БОЙ»), здание — волна по клетке, уровень — свет с шевронами, " +
		"улучшение — знак карты, орбитальный удар — метка на клетке", arrive_build
		and _has_level_glow(s._get_player_squad_at(Vector2i(1, 1))) and _has_fx(units, "upgrade_battle_fury")
		and _has_tile_glow(s.renderer, "strike"))
	var verdicts = [s._drop_verdict(tactical, Vector2i(1, 1)), s._drop_verdict(tactical, Vector2i(2, 0)),
		s._drop_verdict(tactical, Vector2i(0, 2)), s._drop_verdict(CardFactory.create("battle_fury"), Vector2i(2, 0))]
	s._update_drag_target(tactical, Vector2i(1, 1))
	var marker_ok: bool = is_instance_valid(s._drag_target) and s._drag_target.verdict == "compatible"
	s._update_drag_target(null, Vector2i.ZERO)
	_check("ромб под картой: свой отряд — compatible, пусто — playable, здание — invalid, улучшение на пустую — invalid (%s); " % [
		verdicts] + "отпустили — гаснет", verdicts == ["compatible", "playable", "invalid", "invalid"] and marker_ok
		and s._drag_target == null)
	# Карта не ляжет — ромб «нельзя»: отряд на максимуме и здоров, здание на максимуме
	var mine = s._get_player_squad_at(Vector2i(1, 1))
	while mine.data.can_merge_upgrade():
		s._merge_squad(tactical, mine)
	mine.heal_by_ratio(1.0)
	for i in 2:
		s._play_building_card(CardFactory.plasma_generatorium(), Vector2i(0, 2))
	var maxed := [s._drop_verdict(tactical, Vector2i(1, 1)), s._drop_verdict(CardFactory.plasma_generatorium(), Vector2i(0, 2))]
	_check("ромб «нельзя» там, где карта не ляжет: отряд ур.%d здоров, генератор ур.%d (%s)" % [mine.data.squad_level,
		s._get_player_building_at(Vector2i(0, 2)).card.building_level, maxed],
		maxed == ["invalid", "invalid"] and not s._merge_squad(tactical, mine))
	s._on_start_pressed(false)
	await _frames(1)   # метка снята queue_free — уходит из дерева в конце кадра
	var w = bm.kingdom_wall
	_check("начало боя: метка снята, щит стены — вспышкой по стене владений; вариант расы — _chaos, нет варианта — общий",
		not _has_tile_glow(s.renderer, "strike") and w != null and w.segments.all(func(x): return x.flash_left > 0.0)
		and V.race_kind("orbital_strike", "chaos") == "orbital_strike_chaos" and V.race_kind("squad_lost", "chaos") == "squad_lost")
	bm.stop_battle()
