extends SceneTree

# Тема расы игрока (FactionTheme): раса в сохранении, поле из темы, цитадель —
# лист кадров (стоит / стреляет / ранена / рушится), плитка-картинка ромба.
# Лист и плитку тест рисует сам (чистых спрайтов рас пока нет).
#   godot --headless --path . -s tests/test_faction_theme.gd
const SHEET_PATH = "user://test_citadel_sheet.png"
const TILE_PATH = "user://test_theme_tile.png"
const FRAME = 32

func _initialize() -> void:
	root.get_node("SaveManager").enabled = false
	root.get_node("GameSettings").battle_speed = 1.0
	_main()

func _frames(n: int) -> void:
	for i in range(n): await process_frame

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

# Лист 4 ряда × 6 кадров, у каждого ряда свой цвет
func _make_sheet() -> void:
	var img = Image.create(FRAME * 6, FRAME * 4, false, Image.FORMAT_RGBA8)
	var colors = [Color.GRAY, Color.ORANGE, Color.RED, Color.BLACK]
	for row in 4:
		img.fill_rect(Rect2i(0, row * FRAME, FRAME * 6, FRAME), colors[row])
	img.save_png(ProjectSettings.globalize_path(SHEET_PATH))
	var tile = Image.create(280, 200, false, Image.FORMAT_RGBA8)   # вдвое шире клетки
	tile.fill(Color(0.3, 0.6, 0.3))
	tile.save_png(ProjectSettings.globalize_path(TILE_PATH))

# Все пути "texture" в теме (вложенные плиты, кадры, группы местности)
func _collect_textures(value, out: Array) -> void:
	if value is Dictionary:
		if value.has("texture"):
			out.append(value["texture"])
		for v in value.values():
			_collect_textures(v, out)
	elif value is Array:
		for v in value:
			_collect_textures(v, out)

func _main() -> void:
	await process_frame
	_make_sheet()
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")

	# 1. Раса забега: по умолчанию десант, сохраняется, старое сохранение — десант
	_check("раса по умолчанию — space_marines", rm.player_faction == "space_marines")
	rm.player_faction = "chaos"
	var saved = rm.save_state()
	rm.player_faction = "space_marines"
	rm.load_state(saved)
	var faction_loaded = rm.player_faction
	saved.erase("player_faction")
	rm.load_state(saved)
	_check("раса в сохранении; без поля — десант", faction_loaded == "chaos" and rm.player_faction == "space_marines")
	rm.player_faction = "tyranids"   # темы нет — берётся тема по умолчанию

	# 2. Бой: поле и цитадель из темы (неизвестная раса → тема по умолчанию, цитадель — спрайт)
	bm.reset_run()
	rm.new_run(5)
	for n in rm.map.nodes:
		if n.is_battle() and n.wave == 1:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = 1
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(3)
	var battle = current_scene
	var theme: Dictionary = battle.renderer.theme
	var citadel = bm.citadel
	_check("тема по умолчанию: плитки и декор есть, цитадель — спрайт темы (готика)", theme.has("floor") \
		and not theme["floor"].is_empty() and not theme["decorations"].is_empty() and citadel.has_sprite())
	var cit_theme: Dictionary = theme.get("citadel", {})
	# готика — с тоном; анимированный декор (костёр) — без: холодный огонь выглядел бы мёртвым
	var props_tinted = theme["decorations"].filter(func(d): return not d.has("frames")).all(func(d): return d.has("tint"))
	# цитадель — цветокор запечён в лист (tools/sm_grade.py): оттенка поверх нет — белое ядро вспышки не синеет
	_check("готика темнее, ближе к грунту: декор с тоном, цитадель — цветокор в листе, без оттенка",
		props_tinted and not cit_theme.has("tint") and citadel._sprite.modulate == Color.WHITE)
	var marks: Dictionary = battle.renderer._layout.get("landmarks", {})
	var fires = marks.keys().filter(func(c): return marks[c] == theme["landmarks"]["campfire"])
	var flags = marks.keys().filter(func(c): return marks[c] in theme["landmarks"]["banners"])
	var war = marks.keys().filter(func(c): return marks[c] in theme["landmarks"]["war_banners"])
	var war_ok: bool = war.size() == theme["landmarks"]["war_banner_count"]
	for c in war:   # большие знамёна — на стороне игрока, вне боевой полосы, порознь с другими ориентирами
		if not battle.renderer._is_player_side(c) or battle.renderer._is_battle_strip(c):
			war_ok = false
		for o in marks.keys():
			if o != c and maxi(absi(o.x - c.x), absi(o.y - c.y)) < battle.renderer.WAR_BANNER_GAP:
				war_ok = false
	var rivers: Dictionary = battle.renderer._layout.get("rivers", {})
	var river_row: int = rivers.keys()[0].y if not rivers.is_empty() else 0
	var near_base = fires.filter(func(c): return maxi(absi(c.x - battle.iso_grid.citadel_tile.x),
		absi(c.y - battle.iso_grid.citadel_tile.y)) == battle.renderer.CITADEL_CLEAR + 1)
	var beyond_river = fires.filter(func(c): return c.y == (river_row - 1 if river_row < 0 else river_row + 1))
	var flag_by_fire = near_base.size() == 1 and flags.any(func(c): return maxi(absi(c.x - near_base[0].x), absi(c.y - near_base[0].y)) == 1)
	_check("ориентиры: 2 костра (у базы, за рекой), 3 знамени (одно у костра), %d больших знамён — порознь на стороне игрока, пол анимирован" % war.size(),
		fires.size() == 2 and near_base.size() == 1 and beyond_river.size() == 1 and flags.size() == 3
		and flag_by_fire and war_ok and battle.renderer._animated)
	citadel.apply_theme({})
	await _frames(1)
	_check("пустая тема цитадели — башня из блоков", not citadel.has_sprite())

	# 3. Плитки-картинки: пол из PNG ромба рисуется без ошибок
	battle.renderer.theme = {"floor": [TILE_PATH], "kingdom": [TILE_PATH], "enemy": [TILE_PATH], "decorations": []}
	battle.renderer.refresh_floor()
	await _frames(2)
	_check("пол из картинок-ромбов перерисован", true)

	# 3б. Тема Хаоса: все плиты на месте, поле (анимированное — обелиски) рисуется; кристаллов, знамён-плит, окопов
	#     и извержений нет (решение пользователя 23.10.2026): на местах извержений — красные глаза (10 кадров), на местах
	#     кристаллов — туман; взрыва клетки при ударе нет
	var chaos: Dictionary = load("res://scripts/data/FactionTheme.gd").THEMES["chaos"]
	var paths: Array = []
	_collect_textures(chaos, paths)
	var unique: Array = []
	for p in paths:
		if not unique.has(p):
			unique.append(p)
	var missing = unique.filter(func(p): return not ResourceLoader.exists(p))
	battle.renderer.theme = chaos
	battle.renderer.refresh_floor()
	await _frames(2)
	var removed = unique.filter(func(p): return "blast_" in p or "trench_" in p or "flag_" in p or "/terrain_" in p)
	var eyes = unique.filter(func(p): return "red_eyes_" in p)
	var mist_cells: int = battle.renderer._layout.get("mist", []).size()
	var no_blast_vfx = not load("res://scripts/battle/Vfx.gd").EFFECTS.has("tile_blast")
	var chaos_citadel: Dictionary = chaos.get("citadel", {})
	_check("Хаос: %d плит на месте, цитадель — крепость из листа, пол анимирован, кристаллов / знамён-плит / окопов / извержений нет, глаза — %d кадров, туман на %d клетках, взрыва клетки при ударе нет, реки нет" % [unique.size(), eyes.size(), mist_cells],
		unique.size() == 45 and eyes.size() == 10 and mist_cells > 0 and ResourceLoader.exists(chaos_citadel.get("sheet", "")) and missing.is_empty() and battle.renderer._animated \
		and not chaos.has("river") and battle.renderer._layout["rivers"].is_empty() \
		and removed.is_empty() and no_blast_vfx)

	# 3б. Цитадель Космодесанта — лист citadel_spacemarine_spritesheet: все ряды, снаряд — на кадре вспышки из ствола
	var sm_cit: Dictionary = theme["citadel"]   # раса без темы → тема Космодесанта
	citadel.apply_theme(sm_cit)   # выше проверялась пустая тема — башня из блоков
	await _frames(2)
	var sm_frames: SpriteFrames = citadel._sprite.sprite_frames
	var counts_ok = sm_frames.get_frame_count("idle") == 1 and sm_frames.get_frame_count("attack") == 9 \
		and sm_frames.get_frame_count("hit") == 3 and sm_frames.get_frame_count("fall") == 12 \
		and is_equal_approx(sm_frames.get_animation_speed("attack"), 12.0)
	var shots_before = bm.projectiles.size()
	citadel._fire_at(citadel.global_position + Vector2(200, 0))
	var none_yet = bm.projectiles.size() == shots_before and citadel.get_sprite_animation() == "attack"
	for i in range(int(ceil(float(sm_cit["shot_frame"]) / 12.0 / 0.1))):
		citadel.tick(0.1)
	var shot = bm.projectiles.back() if bm.projectiles.size() > shots_before else null
	var muzzle = citadel.to_global(citadel._sprite.position + sm_cit["muzzle"] * citadel._sprite.scale)
	_check("цитадель Космодесанта: 1/9/3/12 кадров (стоит неподвижно), снаряд — на кадре вспышки, из ствола",
		counts_ok and none_yet and shot != null and shot.global_position.distance_to(muzzle) < 1.0)
	bm.clear_projectiles()

	# 3в. Попадание по цитадели — белая вспышка на спрайте (как у бойца), гаснет сама
	citadel.take_hit(0.0)
	var flash_peak: float = citadel.get_hit_flash()
	var on_sprite = citadel._sprite.material != null and citadel._sprite.material == citadel.material
	for i in range(600):   # твин гаснет по времени кадров: ждём, пока погаснет (не дольше 600 кадров)
		if citadel.get_hit_flash() < 0.01:
			break
		await _frames(1)
	_check("попадание по цитадели: белеет %.2f и гаснет до %.2f" % [flash_peak, citadel.get_hit_flash()],
		flash_peak > 0.5 and on_sprite and citadel.get_hit_flash() < 0.01)

	# 4. Цитадель: лист кадров → анимации, состояния, область перекрытия
	citadel.apply_theme({"sheet": SHEET_PATH, "frame_size": Vector2i(FRAME, FRAME),
		"anchor": Vector2(16, 30), "scale": 2.0, "fps": 30.0,
		"rows": {"idle": [0, 6], "attack": [1, 6], "hit": [2, 6], "fall": [3, 6]}})
	await _frames(2)
	_check("лист кадров: спрайт, стоит (idle)", citadel.has_sprite() and citadel.get_sprite_animation() == "idle")
	var occ: Rect2 = citadel.get_occlusion_rect()
	_check("область перекрытия = кадр × масштаб", is_equal_approx(occ.size.x, FRAME * 2.0) \
		and is_equal_approx(occ.size.y, FRAME * 2.0))
	citadel._fire_at(citadel.global_position + Vector2(100, 0))
	var after_fire = citadel.get_sprite_animation()
	citadel.take_hit(10.0)
	var after_hit = citadel.get_sprite_animation()
	citadel._fire_at(citadel.global_position + Vector2(100, 0))
	var fire_during_hit = citadel.get_sprite_animation()
	_check("выстрел → attack, попадание → hit, выстрел не перебивает hit", after_fire == "attack" \
		and after_hit == "hit" and fire_during_hit == "hit")
	await create_timer(0.5).timeout
	_check("после попадания — снова idle", citadel.get_sprite_animation() == "idle")
	citadel.self_modulate.a = 0.35
	await _frames(2)
	_check("прозрачность цитадели переходит на спрайт", is_equal_approx(citadel._sprite.self_modulate.a, 0.35))
	citadel.take_hit(bm.citadel_hp + 100.0)
	var fallen = citadel.get_sprite_animation()
	citadel.play_state("hit")
	_check("0 HP → fall, дальше не меняется", fallen == "fall" and citadel.get_sprite_animation() == "fall")

	# Существа по краям поля (SideCritters, тема "critters"): сколько в теме, все за контуром стены владений и вне
	# боевой полосы, ходят
	var critters: Array = battle.units_container.get_children().filter(func(n): return n.get("area") != null)
	var wall_rect: Rect2 = load("res://scripts/battle/KingdomWall.gd").contour(battle.iso_grid)
	var outside := critters.all(func(c): return c.area.all(func(cell): return not wall_rect.has_point(Vector2(cell)) \
		and not battle.renderer._is_battle_strip(cell)))
	var start_pos: Array = critters.map(func(c): return c.position)
	var t_walk := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_walk < 6000:
		await process_frame
	var walked := 0
	for i in critters.size():
		if critters[i].position != start_pos[i]:
			walked += 1
	_check("существа по краям поля: %d, за стеной владений и вне боевой полосы, ходят %d" % [critters.size(), walked],
		critters.size() == battle.renderer.theme.get("critters", {}).get("count", -1) and outside and walked > 0)

	bm.stop_battle()
	rm.player_faction = "space_marines"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SHEET_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TILE_PATH))
	quit()
