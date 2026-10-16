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
	var props_tinted = theme["decorations"].all(func(d): return d.has("tint"))
	_check("готика темнее, ближе к грунту: декор с тоном, цитадель — тон темы",
		props_tinted and cit_theme.has("tint") and citadel._sprite.modulate == cit_theme["tint"])
	citadel.apply_theme({})
	await _frames(1)
	_check("пустая тема цитадели — башня из блоков", not citadel.has_sprite())

	# 3. Плитки-картинки: пол из PNG ромба рисуется без ошибок
	battle.renderer.theme = {"floor": [TILE_PATH], "kingdom": [TILE_PATH], "enemy": [TILE_PATH], "decorations": []}
	battle.renderer.refresh_floor()
	await _frames(2)
	_check("пол из картинок-ромбов перерисован", true)

	# 3б. Тема Хаоса: все плиты на месте, поле (анимированное) рисуется, взрыв клетки — на полу
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
	var blast = load("res://scripts/battle/Vfx.gd").spawn(battle.units_container, "tile_blast", Vector2.ZERO)
	_check("Хаос: %d плит на месте, пол анимирован, взрыв клетки — на слое пола" % unique.size(),
		unique.size() == 49 and missing.is_empty() and battle.renderer._animated 		and blast != null and blast.get_parent() == battle.renderer)

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

	bm.stop_battle()
	rm.player_faction = "space_marines"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SHEET_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TILE_PATH))
	quit()
