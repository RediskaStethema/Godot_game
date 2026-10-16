extends SceneTree

# Код под ассеты (решение пользователя 16.10.2026): графика и звук подключаются, как только
# появятся файлы. Листы и звуки здесь — сгенерированные в памяти (своих ассетов ещё нет):
# 1) здание со своим листом (Building: idle / attack / refill, уровни idle_2…): спрайт вместо блоков,
#    размер под клетку, рамка для прозрачности, выстрел из ствола листа, вид уровня, портрет карты;
#    без листа — блоки, как раньше;
# 2) Казармы вернули бойцов — анимация refill;
# 3) Apothecary с рядом heal — лечит → heal, некого лечить → стойка;
# 4) броня в цвет ордена: свои — шейдер с тоном ордена, враги и Ultramarines — как нарисовано,
#    вспышка попадания не снимает перекраску;
# 5) звук: шины, событие без файла — тихо, с потоком — играет, предел частоты, выстрел снаряда и
#    музыка магазина вызывают свои события.
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
	B._frames_cache["tower"] = tower_frames
	B._frames_cache["wall"] = null
	var turret = CardFactory.bolter_turret()
	var wall = CardFactory.fortress_wall()
	await _battle([_squad_unit("tactical_marine", 3)] as Array[UnitData], {turret: Vector2i(0, 0), wall: Vector2i(0, 2)})
	var t = bm.buildings.filter(func(b): return b.card == turret)[0]
	var w = bm.buildings.filter(func(b): return b.card == wall)[0]
	var occ: Rect2 = t.get_occlusion_rect()
	var width_ok := absf(occ.size.x - 140.0 * B.SPRITE_WIDTH) < 1.0
	_check("здание со своим листом: спрайт вместо блоков (ширина %.0f ≈ %.0f), рамка прозрачности по нему; без листа — блоки" % [
		occ.size.x, 140.0 * B.SPRITE_WIDTH], t.sprite != null and width_ok and t.sprite.animation == "idle" and w.sprite == null)
	turret.level_up_building()
	t.refresh_stats()
	var portrait = load(UI_THEME).card_portrait(turret)
	_check("уровень 2 — вид idle_2; портрет карты — кадр листа", t.sprite.animation == "idle_2"
		and portrait == tower_frames.get_frame_texture("idle", 0))
	current_scene._on_start_pressed()
	bm.set_process(false)
	var enemy = reg.get_alive_soldiers_of_team(1)[0]
	t.attack_timer = 0.0
	t.tick(0.1)
	var shot = bm.projectiles[-1] if not bm.projectiles.is_empty() else null
	var expect_muzzle: Vector2 = t._sprite_muzzle()
	_check("выстрел турели: анимация attack, снаряд из ствола листа на кадре вспышки",
		t.sprite.animation == "attack" and shot != null and shot._origin.distance_to(expect_muzzle) < 0.5 and shot._delay > 0.0)
	bm.stop_battle()

	# 2. Казармы вернули бойцов — анимация refill
	B._frames_cache["barracks"] = _sheet({"idle": 2, "refill": 3})
	var barracks = CardFactory.barracks()
	var wounded = _squad_unit("tactical_marine", 9)
	wounded.saved_hp = [1.0, 1.0, 1.0] as Array[float]
	await _battle([wounded] as Array[UnitData], {barracks: Vector2i(1, 1)}, {wounded: Vector2i(1, 0)})
	var bb = bm.buildings.filter(func(b): return b.card == barracks)[0]
	var added: int = bm.refill_from_barracks()
	_check("Казармы вернули бойцов (%d) — анимация refill" % added, added > 0 and bb.sprite.animation == "refill")
	for k in ["tower", "wall", "barracks"]:
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
	_check("Blood Angels: броня красная, враг как нарисован; вспышка — с перекраской, после — снова цвет ордена",
		red_ok and foe.sprite.material == null and flashing and marine.sprite.material == mat)
	rm.player_chapter = "ultramarines"
	await _battle([_squad_unit("tactical_marine", 3)] as Array[UnitData])
	_check("Ultramarines — синие как нарисовано (без шейдера)", reg.get_alive_soldiers_of_team(0)[0].sprite.material == null)
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
	P.launch(current_scene, "bolt", Vector2.ZERO, null, Vector2(100, 0))
	_check("события звука: музыка боя, выстрел снаряда (%s)" % ", ".join(audio.history.slice(0, 4)),
		audio.current_music() == "battle" and audio.history.any(func(h): return h.begins_with("shot_bolt")))
	quit()
