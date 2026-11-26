extends SceneTree

# Перетекание кадров FrameBlend (решение пользователя 19.10.2026: плавность бойцов, зданий, эффектов):
# поверх текущего кадра — следующий с прозрачностью = доле времени кадра; конец разовой анимации — без
# перетекания; ADD-эффект — родитель гаснет на ту же долю; выключено «Атмосферой» — нет; подключено к
# эффектам и снарядам, не к моделям; стойка зданий вне схватки — один кадр.
#   godot --headless --path . -s tests/test_frame_blend.gd
# Классы по имени не упоминаются (скрипт компилируется до автолоадов) — load()

const FRAME_BLEND = "res://scripts/battle/FrameBlend.gd"

var _fails := 0

func _initialize() -> void:
	_main()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _tex(c: Color) -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

func _sheet(loop: bool) -> SpriteFrames:
	var f := SpriteFrames.new()
	f.add_animation("a")
	f.set_animation_loop("a", loop)
	f.set_animation_speed("a", 4.0)
	for c in [Color.RED, Color.GREEN, Color.BLUE]:
		f.add_frame("a", _tex(c))
	return f

func _main() -> void:
	var FB = load(FRAME_BLEND)
	var gs = root.get_node("GameSettings")
	gs.config_path = "user://test_frame_blend_settings.cfg"
	gs.atmosphere = true
	var s := AnimatedSprite2D.new()
	s.sprite_frames = _sheet(true)
	root.add_child(s)
	var b = FB.attach(s)
	s.play("a")
	s.speed_scale = 0.0   # кадр не уходит между проверками (в headless кадр движка бывает длинным)
	s.set_frame_and_progress(0, 0.6)
	await _frames(2)
	var t0 = s.frame_progress
	_check("следующий кадр поверх текущего, прозрачность = доле кадра (%.2f ≈ %.2f)" % [b.self_modulate.a, t0],
		b.visible and b.texture == s.sprite_frames.get_frame_texture("a", s.frame + 1) and absf(b.self_modulate.a - t0) < 0.05)
	_check("повторное подключение — тот же узел", FB.attach(s) == b)
	s.set_frame_and_progress(2, 0.5)
	await _frames(2)
	_check("цикл: после последнего кадра перетекает в первый", b.visible and b.texture == s.sprite_frames.get_frame_texture("a", 0))
	s.sprite_frames = _sheet(false)
	s.play("a")
	s.speed_scale = 0.0
	s.set_frame_and_progress(2, 0.5)
	await _frames(2)
	_check("разовая анимация: на последнем кадре перетекания нет", not b.visible)

	var add := AnimatedSprite2D.new()
	add.sprite_frames = _sheet(true)
	root.add_child(add)
	var ba = FB.attach(add, true, FB.MAX_FPS)
	add.play("a")
	add.speed_scale = 0.0
	add.set_frame_and_progress(0, 0.5)
	await _frames(2)
	_check("ADD: родитель гаснет на ту же долю (%.2f + %.2f ≈ 1)" % [add.self_modulate.a, ba.self_modulate.a],
		absf(add.self_modulate.a + ba.self_modulate.a - 1.0) < 0.05)
	gs.atmosphere = false
	await _frames(2)
	add.sprite_frames.set_animation_speed("a", 20.0)
	await _frames(2)
	_check("быстрая анимация (20 к/с > %.0f) — без перетекания" % FB.MAX_FPS, not ba.visible and add.self_modulate.a == 1.0)
	add.sprite_frames.set_animation_speed("a", 4.0)
	await _frames(2)
	_check("«Атмосфера» выключена — без перетекания, родитель как был", not ba.visible and add.self_modulate.a == 1.0)
	gs.atmosphere = true

	# Подключено в игре: эффект, снаряд; у моделей (боец, здание, цитадель) — нет (решение пользователя
	# 20.10.2026: наложение следующего кадра мелькало, особенно у полупрозрачных построек на расстановке)
	var on := {"Vfx": "FrameBlend.attach(v,", "Projectile": "FrameBlend.attach(p)"}
	var bad: Array = []
	for cls in ["Soldier", "Building", "Citadel", "Vfx", "Projectile"]:
		var code: String = FileAccess.get_file_as_string("res://scripts/battle/%s.gd" % cls)
		var ok: bool = code.contains(on[cls]) if on.has(cls) else not code.contains("FrameBlend.attach(")
		if not ok:
			bad.append(cls)
	_check("перетекание у эффектов и снарядов, у моделей — нет%s" % ("" if bad.is_empty() else ": не так у " + str(bad)),
		bad.is_empty())

	# Стойка здания вне схватки — один кадр, в бою — анимация (уровни idle_2 / idle_3); бойцы — всегда
	var bm = root.get_node("BattleManager")
	var hold = load("res://scripts/battle/Building.gd").hold_idle_outside_battle
	var idle := AnimatedSprite2D.new()
	var f := _sheet(true)
	f.rename_animation("a", "idle_2")
	idle.sprite_frames = f
	root.add_child(idle)
	idle.play("idle_2")
	idle.frame = 2
	hold.call(idle)
	var plays_planning: bool = idle.is_playing() and idle.animation == &"idle_2"   # расстановка — стойка играет (21.11.2026)
	bm.start_battle()
	hold.call(idle)
	var plays: bool = idle.is_playing() and idle.animation == &"idle_2"
	bm.stop_battle()
	hold.call(idle)
	_check("стойка здания: на расстановке играет (%s), в бою играет (%s), после боя — снова играет" % [plays_planning, plays],
		plays_planning and plays and idle.is_playing())

	# Ускорение боя не ускоряет кадры зданий, кроме выстрела (решение пользователя 12.11.2026)
	var rate = load("res://scripts/battle/Building.gd").hold_frame_rate
	bm.battle_speed_now = 3.0
	rate.call(idle)
	var idle_k: float = idle.speed_scale
	var f2 := _sheet(true)
	f2.rename_animation("a", "attack_2")
	var shot := AnimatedSprite2D.new()
	shot.sprite_frames = f2
	root.add_child(shot)
	shot.play("attack_2")
	shot.speed_scale = 0.5
	rate.call(shot)
	bm.battle_speed_now = 1.0
	rate.call(idle)
	_check("ускорение ×3: стойка здания ×%.2f (1/3), выстрел ×%.2f (как бой), без ускорения — ×%.2f" % [idle_k, shot.speed_scale, idle.speed_scale],
		absf(idle_k - 1.0 / 3.0) < 0.001 and shot.speed_scale == 1.0 and idle.speed_scale == 1.0)
	quit(1 if _fails > 0 else 0)

func _check(name: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok:
		_fails += 1
