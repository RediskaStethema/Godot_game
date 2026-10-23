extends SceneTree

# Снимки экрана для сравнения вида «до / после» (стилизация): главное меню, окна выбора расы / ордена / бога, магазин
# (и обновление набора: рубашки, переворот, новый набор),
# расстановка и середина боя волны 10 за Космодесант и за Хаос, баннеры итога, экран расширения, пауза. Только в окне:
#   godot --path . -s tests/capture_style.gd -- <папка> [префикс]
# Сохранение, профиль и настройки игрока не трогает — свои файлы в user://
# Классы сцен по имени не упоминаются (скрипт компилируется до автолоадов).

const TEST_SAVE_PATH = "user://capture_style_save.json"
const TEST_PROFILE_PATH = "user://capture_style_profile.cfg"
const TEST_CONFIG_PATH = "user://capture_style_settings.cfg"
const BATTLE_SECONDS = 4.0   # сколько идёт бой до снимка «середина боя»: армии сошлись

var _dir := ""
var _prefix := "shot"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_prefix = args[1] if args.size() > 1 else "shot"
	DirAccess.make_dir_recursive_absolute(_dir)
	var sm = root.get_node("SaveManager")
	sm.save_path = TEST_SAVE_PATH
	sm.profile_path = TEST_PROFILE_PATH
	sm.enabled = false
	var gs = root.get_node("GameSettings")
	gs.config_path = TEST_CONFIG_PATH
	gs.battle_speed = 1.0
	_main()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name: String) -> void:
	await _frames(2)
	var path := _dir.path_join("%s_%s.png" % [_prefix, name])
	root.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)

# Отряд как из карты (BattleScene._play_squad_card): состав — unit_count карты, все с полным HP
func _squad(card_id: String) -> UnitData:
	var card = CardFactory.create(card_id)
	var d := UnitFactory.create(card.unit_factory_id)
	d.squad_size = card.unit_count
	d.squad_growth = UnitFactory.squad_growth_for(card)
	var hp: Array[float] = []
	for i in d.squad_size:
		hp.append(1.0)
	d.saved_hp = hp
	return d

# Забег расы faction на шаге нужного типа волны wave (магазин или бой)
func _setup_run(faction: String, wave: int, battle: bool) -> void:
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	rm.player_faction = faction
	bm.reset_run()
	rm.new_run(7)
	for n in rm.map.nodes:
		if n.wave == wave and n.is_battle() == battle:
			rm.current_node_id = n.id
			rm.current_completed = false
			break
	root.get_node("EconomyManager").round_number = wave
	root.get_node("EconomyManager").requisition = 34

func _army(faction: String) -> Array[UnitData]:
	var ids: Array = ["tactical_squad", "assault_squad", "devastator_squad", "terminator_squad", "dreadnought",
		"librarian"] if faction == "space_marines" else ["chaos_marines", "cultists", "havocs", "plague_marines",
		"hellbrute", "raptors"]
	var out: Array[UnitData] = []
	for i in ids.size():
		out.append(_squad(ids[i]))
	return out

func _battle(faction: String) -> void:
	_setup_run(faction, 10, true)
	var bm = root.get_node("BattleManager")
	bm.player_units = _army(faction)
	var chaos := faction == "chaos"   # здания расы — свои листы (Building: buildings/chaos/<тип>)
	bm.player_buildings[CardFactory.create("heretic_autocannon" if chaos else "bolter_turret")] = Vector2i(0, 0)
	bm.player_buildings[CardFactory.create("spiked_barricade" if chaos else "fortress_wall")] = bm.WALL_TILE   # стена владений
	bm.player_buildings[CardFactory.create("cult_shrine" if chaos else "barracks")] = Vector2i(1, 2)
	# Рука на расстановке — игральные карты внизу (Bench), одна под курсором поднята
	var hand: Array = ["cultists", "havocs", "hellbrute", "warp_ward", "dark_altar"] if chaos else 		["tactical_squad", "assault_squad", "librarian", "iron_halo", "plasma_generatorium", "orbital_strike"]
	bm.pending_cards.clear()
	for id in hand:
		bm.pending_cards.append(CardFactory.create(id))
	change_scene_to_file("res://scenes/battle/BattleScene.tscn")
	await _frames(20)
	await _shot(faction + "_placement")
	var cards: Array = current_scene.bench.cards_container.get_children()
	if cards.size() > 2:
		cards[2].mouse_entered.emit()
		await create_timer(0.3).timeout
		await _shot(faction + "_hand_hover")
		cards[2].mouse_exited.emit()
	current_scene._on_start_pressed()
	await create_timer(BATTLE_SECONDS).timeout
	await _shot(faction + "_battle")
	if faction == "space_marines":
		# Баннеры итога (подложки пакета интерфейса) и экран расширения — поверх боя
		for r in [["ПОБЕДА", true, "result_victory"], ["ПОРАЖЕНИЕ", false, "result_defeat"]]:
			current_scene.hud.show_result(r[0], "+24 Req · Лучший отряд: Tactical Squad", r[1])
			await create_timer(0.4, true, false, true).timeout
			await _shot(r[2])
		current_scene.hud.result_banner.queue_free()
		var banner = load("res://scenes/battle/ui/ExpansionBanner.gd").new()
		current_scene.get_node("UI").add_child(banner)
		banner.setup(6)
		await create_timer(0.5, true, false, true).timeout
		await _shot("expansion")
		banner.queue_free()
	if faction == "space_marines":
		await _effects_gallery()
	# Пауза поверх боя (Esc)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(10)
	if faction == "space_marines":
		await _shot("pause")
	paused = false
	root.get_node("BattleManager").stop_battle()

# Все эффекты рядами у центра экрана в масштабе бойца, снимок посреди анимации (бой на паузе —
# эффекты идут: Vfx не тикают с боем). Кровь — по цвету стороны
const GALLERY = ["fireball", "explosion", "impact", "muzzle_flash", "muzzle_smoke", "flame_burst",
	"hit_spark", "slash", "ground_slam", "lightning", "cast", "heal",
	"shield", "poof", "burning", "poisoned", "empowered",
	"slowed", "stun", "splatter", "river_splash"]
const GALLERY_COLS = 6
const GALLERY_STEP = Vector2(60, 55)
const EFFECT_SCALE = 0.5   # Soldier.EFFECT_SCALE (класс бойца здесь по имени не упоминать)

func _effects_gallery() -> void:
	var cam: Camera2D = current_scene.camera
	cam.zoom *= 3.0   # ближе — видно пиксели эффектов
	await _frames(2)
	var center: Vector2 = cam.get_screen_center_position()
	var parent: Node = current_scene.units_container
	var origin := center - Vector2(GALLERY_STEP.x * (GALLERY_COLS - 1) / 2.0, GALLERY_STEP.y * 2.0)
	for i in GALLERY.size():
		var at := origin + Vector2(i % GALLERY_COLS, i / GALLERY_COLS) * GALLERY_STEP
		Vfx.spawn(parent, GALLERY[i], at, EFFECT_SCALE)
		if i % 6 == 5:
			await process_frame   # лимит эффектов попаданий за кадр
	var blood_ids = ["tactical_marine", "chaos_cultist", "chaos_marine", "plague_marine", "dreadnought"]
	for i in blood_ids.size():
		Vfx.spawn_blood(parent, origin + Vector2(i, 4) * GALLERY_STEP, UnitFactory.create(blood_ids[i]), true, EFFECT_SCALE)
	await create_timer(0.25).timeout
	await _shot("effects")

func _main() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 2 and args[2] == "linear":
		Vfx.filter = CanvasItem.TEXTURE_FILTER_LINEAR
	await _frames(2)
	change_scene_to_file("res://scenes/menu/MainMenu.tscn")
	await _frames(20)
	await _shot("menu")
	# Окна нового забега: раса, орден, бог (эмблемы пакета интерфейса)
	for d in [["RaceSelectDialog", "", "race"], ["ChapterSelectDialog", "space_marines", "chapters"],
			["ChapterSelectDialog", "chaos", "gods"]]:
		var dialog = load("res://scenes/ui/%s.gd" % d[0]).new()
		current_scene.add_child(dialog)
		if d[1] == "":
			dialog.setup()
		else:
			dialog.setup(d[1])
		await _frames(5)
		await _shot(d[2])
		dialog.queue_free()
		await _frames(2)

	_setup_run("space_marines", 3, false)
	var hand: Array = ["tactical_squad", "devastator_squad", "fortress_wall", "iron_halo", "dreadnought_card"]
	for id in hand:
		var c = CardFactory.create(id)
		if c:
			root.get_node("BattleManager").pending_cards.append(c)
	change_scene_to_file("res://scenes/shop/ShopScene.tscn")
	await _frames(20)
	await _shot("shop")
	# Обновление набора: карты переворачиваются из рубашки (ShopSlot.reveal)
	current_scene._on_reroll_pressed()
	await create_timer(0.18).timeout
	await _shot("shop_backs")
	await create_timer(0.27).timeout
	await _shot("shop_flip")
	await create_timer(1.0).timeout
	await _shot("shop_reroll")

	await _battle("space_marines")
	await _battle("chaos")
	root.get_node("RunManager").player_faction = "space_marines"
	quit()
