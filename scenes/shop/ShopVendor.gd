class_name ShopVendor
extends Control

# Продавец магазина (решение пользователя 11.11.2026): справа от карт стоит техножрец Адептус Механикус, у Хаоса —
# тёмный механикус. Отвечает на действия игрока репликами в комиксном облаке и жестами (react), над ним на цепях
# висит вывеска «Обновить» — кнопка обновления набора ShopScene (attach_reroll), от обновления раскачивается.
# Арт — лист художника assets/ui/shop/vendor/<раса>/frames.tres (ТЗ — ART_TZ_SHOP_VENDOR_2026-11-11.txt): ряды
# idle (цикл), greet / buy / reroll / no_money / sell / hand_full / catch_up (разовые, нет ряда — idle с жестом
# кодом; жесту без ряда — похожий, ANIM_FALLBACK), metadata/figure_height — рост фигуры в кадре, metadata/lens — линза
# в кадре (к ней хвост облака). Обе расы — пакет v2 12.11.2026 (исходник assets/source_sheets/shop_vendor_v2_2026-11-12). Листа нет — заглушка кодом (VendorFigure._draw_placeholder).
# Только вид: на магазин не влияет; реплики — своя случайность (не RunManager.rng — seed забега не сдвигается).

const FRAMES_DIR := "res://assets/ui/shop/vendor/"
const FIGURE_HEIGHT := 240.0        # рост фигуры на экране, px (решение пользователя 12.11.2026: на 20% меньше, было 300)
const FIGURE_BOTTOM_PAD := 6.0
const CHAIN_LEN := 30.0             # цепи вывески от верха узла до вывески
# Цепи крепятся к латунной кромке шапки (решение пользователя 12.11.2026, `Screenshot 2026-11-12 143846.png`:
# «цепи подвешены за воздух» — верх цепей висел в зазоре под шапкой): ceiling_gap — сколько px от верха узла
# вверх до кромки (задаёт ShopScene), там латунная скоба на двух заклёпках и крюк
const MOUNT_SIZE := Vector2(16, 7)
const SIGN_SWAY_IDLE := 0.012       # рад: вывеска чуть качается всегда
const SIGN_SWING := 0.09            # рад: толчок от обновления
const SIGN_DAMP := 1.6              # затухание толчка, 1/с
const BUBBLE_MAX_WIDTH := 230.0
const BUBBLE_TIME := 2.4            # сек на экране + BUBBLE_PER_CHAR за букву
const BUBBLE_PER_CHAR := 0.03
const BUBBLE_FADE := 0.3
const TYPE_SPEED := 45.0            # букв в секунду — текст печатается
const REACT_TIME := 0.9             # жест заглушки, сек
const EVENTS := ["greet", "buy", "reroll", "no_money", "sell", "hand_full", "catch_up"]
# Жест без своего ряда в листе — похожий ряд (пакет 12.11.2026: только idle / buy / no_money)
const ANIM_FALLBACK := {"greet": "buy", "sell": "buy", "reroll": "buy", "catch_up": "buy", "hand_full": "no_money"}

# Реплики по расе игрока: техножрец (Космодесант) и тёмный механикус (Хаос)
const LINES := {
	"space_marines": {
		"greet": ["Приветствую, латник Криспина. Гомункул в колбе благословляет обмен.",
			"Склады Ретортариев открыты. Выбирай — колба ждёт.",
			"Монеты принимаются. Без торга."],
		"buy": ["Сделка скреплена печатью. Гомункул доволен.", "Колба светится — доволен.",
			"Принято. Внесено в реестр Ретортариев."],
		"no_money": ["Недостаточно монет. Обмен отклонён.", "Твой счёт пуст, как пустая колба.",
			"Ошибка 0-0-1: средств нет."],
		"hand_full": ["Твои руки полны. Освободи место.", "Перегрузка инвентаря. Продай лишнее."],
		"reroll": ["Перебираю запасы... новые реликвии.", "Обновляю манифест склада.", "Колба показывает иное."],
		"sell": ["Принимаю на переработку.", "Лом тоже пойдёт в тигель.", "Металл вернётся в тигель."],
		"catch_up": ["Помощь Ретортариев. Безвозмездно — на этот раз.", "Подкрепление выдано. Не потеряй."],
	},
	"chaos": {
		"greet": ["А, подписавший договор. Мои кузни открыты.", "Добро пожаловать. Цена — кровь... и монеты.",
			"Демон в машине шепчет: покупай."],
		"buy": ["Договор скреплён. Варп доволен.", "Заражённое железо служит тебе.", "Бери. Оно уже голодно."],
		"no_money": ["Нечем платить? Варп не терпит долгов.", "Пустой кошель. Нет платы — нет товара.",
			"Нет. Даже демоны не работают даром."],
		"hand_full": ["Тебе больше не унести. Продай лишнее.", "Руки полны — освободи их сделкой."],
		"reroll": ["Смотри, что принёс Варп.", "Перековываю товар... иное, тёмное.", "Демоны шепчут новые цены."],
		"sell": ["Сгодится на переплавку в демонов.", "Отдай. Кузня проглотит.", "Принято. Варп заберёт остаток."],
		"catch_up": ["Дар Внешних. Не благодари.", "Вот тебе мясо для войны."],
	},
}

var faction := "space_marines"
var last_event := ""          # для тестов
var last_line := ""
var sign_node: HangingSign
var ceiling_gap := 0.0:              # от верха узла до кромки шапки, к которой крепятся цепи
	set(v):
		ceiling_gap = v
		_layout()
# Вывеска подтягивается вверх (уход магазина, ShopScene._slide_parts): 0 — висит, sign_lift_max() — под шапкой
var sign_lift := 0.0:
	set(v):
		sign_lift = v
		_layout_sign()
# Вывеска поднимается строго вертикально (решение пользователя 12.11.2026): продавец при уходе магазина уезжает
# вправо — вывеска (его ребёнок) сдвигается на sign_hold_x обратно и остаётся над своим местом
var sign_hold_x := 0.0:
	set(v):
		sign_hold_x = v
		_layout_sign()
var figure: VendorFigure
var bubble: PanelContainer
var _bubble_label: Label
var _tail: BubbleTail
var _bubble_tween: Tween
var _rng := RandomNumberGenerator.new()

func setup(race: String, reroll_button: Button) -> void:
	faction = race if LINES.has(race) else "space_marines"
	_rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	figure = VendorFigure.new()
	figure.vendor_faction = faction
	add_child(figure)
	sign_node = HangingSign.new()
	add_child(sign_node)
	if reroll_button:
		if reroll_button.get_parent():
			reroll_button.reparent(sign_node, false)
		else:
			sign_node.add_child(reroll_button)
		sign_node.button = reroll_button   # нажатие обрабатывает ShopScene (_on_reroll_pressed)
	_tail = BubbleTail.new()
	add_child(_tail)
	_build_bubble()
	resized.connect(_layout)
	_layout()

func _build_bubble() -> void:
	bubble = PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.BUBBLE_PAPER
	sb.border_color = Palette.BUBBLE_EDGE
	# пергамент пиксельный (решение пользователя 12.11.2026, «облако и плашки пикселем»): срез углов ступенькой
	# без сглаживания, контур чернилами толще, тень — жёсткая со сдвигом, без размытия
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.corner_detail = 1
	sb.anti_aliasing = false
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(4, 4)
	bubble.add_theme_stylebox_override("panel", sb)
	_bubble_label = Label.new()
	_bubble_label.theme = UITheme.get_theme()
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Печать по буквам не меняет размер облака: раскладка — по всему тексту (иначе при visible_ratio 0 облако
	# сжималось в точку и ставилось за правый край)
	_bubble_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_bubble_label.add_theme_color_override("font_color", Palette.BUBBLE_INK)
	_bubble_label.add_theme_font_size_override("font_size", UITheme.text_px(13))
	_bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(_bubble_label)
	bubble.hide()
	_tail.hide()
	add_child(bubble)

func _layout() -> void:
	if figure == null:
		return
	var h := minf(FIGURE_HEIGHT, size.y - CHAIN_LEN - HangingSign.HEIGHT - 10.0)
	figure.position = Vector2(0, size.y - h - FIGURE_BOTTOM_PAD)
	figure.size = Vector2(size.x, h)
	_layout_sign()
	if bubble.visible:
		_place_bubble()

# Голова фигуры в координатах продавца (облако — над ней и левее, хвост — к ней)
# Вывеска: цепи от кромки шапки (ceiling_gap над узлом); подтянута на sign_lift — цепи короче, под шапкой тает
func _layout_sign() -> void:
	if sign_node == null:
		return
	sign_node.size = Vector2(minf(size.x - 20.0, HangingSign.WIDTH), HangingSign.HEIGHT)
	sign_node.position = Vector2((size.x - sign_node.size.x) / 2.0 + sign_hold_x, CHAIN_LEN - sign_lift)
	sign_node.lifting = sign_lift > 0.0
	sign_node.pivot_offset = Vector2(sign_node.size.x / 2.0, -(CHAIN_LEN + ceiling_gap) + sign_lift)
	var over := sign_lift - (CHAIN_LEN + ceiling_gap)   # насколько вывеска зашла под шапку
	sign_node.modulate.a = clampf(1.0 - over / HangingSign.HEIGHT, 0.0, 1.0)
	queue_redraw()

# Цепи вывески: скоба на кромке шапки (неподвижна) → звенья к углу вывески (качается); вывеска зашла под шапку —
# цепей нет. Звенья — овал и ребро по очереди
const LINK := 7.0
func _draw() -> void:
	if sign_node == null or not sign_node.visible:
		return
	var a := sign_node.modulate.a
	for x in sign_node.corners():
		var corner: Vector2 = sign_node.get_transform() * Vector2(x, 0)
		var top := Vector2(sign_node.position.x + x, -ceiling_gap)
		var d := corner - top
		if d.y <= 4.0:
			continue
		_draw_mount(top, a)
		var dir := d.normalized()
		var n := int((d.length() - 4.0) / LINK)
		for i in n:
			var p := top + dir * (4.0 + i * LINK + LINK * 0.5)
			if i % 2 == 0:
				draw_arc(p, 3.0, 0.0, TAU, 10, Color(Palette.VENDOR_CHAIN, a), 2.0)
				draw_arc(p + Vector2(-0.5, -0.5), 3.0, PI, PI * 1.6, 5, Color(Palette.VENDOR_CHAIN_LIGHT, a), 1.0)
			else:
				draw_line(p - dir * 3.0, p + dir * 3.0, Color(Palette.VENDOR_CHAIN, a), 2.0)

# Скоба на кромке шапки: латунная пластина на двух заклёпках, снизу крюк — на нём верхнее звено
func _draw_mount(top: Vector2, a: float) -> void:
	var m := MOUNT_SIZE
	var r := Rect2(top + Vector2(-m.x / 2.0, -m.y + 2.0), m)
	draw_rect(r.grow(1.0), Color(Palette.SHOP_FRAME_DARK, a))
	draw_rect(r, Color(Palette.VENDOR_BRASS, a))
	draw_rect(Rect2(r.position, Vector2(m.x, 1.0)), Color(Palette.SHOP_FRAME_LIGHT, a))
	for dx in [-m.x / 2.0 + 3.0, m.x / 2.0 - 4.0]:
		draw_rect(Rect2(Vector2(top.x + dx, r.position.y + 2.0), Vector2(2, 2)), Color(Palette.SHOP_FRAME_DARK, a))
	draw_arc(top + Vector2(0, 3.0), 2.5, 0.0, PI, 6, Color(Palette.VENDOR_CHAIN_LIGHT, a), 2.0)   # крюк

func sign_lift_max() -> float:
	return CHAIN_LEN + ceiling_gap + HangingSign.HEIGHT

func head_point() -> Vector2:
	return figure.position + figure.head_point()

func _place_bubble() -> void:
	bubble.reset_size()
	if _bubble_label.autowrap_mode != TextServer.AUTOWRAP_OFF:   # с переносом — ширина по пределу, высота по строкам
		_bubble_label.size = Vector2(BUBBLE_MAX_WIDTH, 0)
		bubble.reset_size()
		bubble.size.x = BUBBLE_MAX_WIDTH + 24.0
	var head := head_point()
	var pos := Vector2(head.x - bubble.size.x + 40.0, head.y - bubble.size.y - 34.0)
	pos.x = minf(pos.x, size.x - bubble.size.x)   # не за правый край экрана
	pos.y = maxf(pos.y, sign_node.position.y + HangingSign.HEIGHT + 6.0)
	bubble.position = pos
	_tail.from_rect = Rect2(bubble.position, bubble.size)
	_tail.to_point = head + Vector2(-8.0, -18.0)
	_tail.queue_redraw()

# Реакция на действие игрока: реплика в облаке и жест (ряд листа или жест заглушки)
func react(event: String) -> void:
	if not LINES[faction].has(event):
		return
	last_event = event
	var lines: Array = LINES[faction][event]
	var line: String = lines[_rng.randi() % lines.size()]
	if lines.size() > 1 and line == last_line:   # подряд одна и та же — следующая
		line = lines[(lines.find(line) + 1) % lines.size()]
	say(line)
	figure.react(event)
	if event == "reroll":
		sign_node.swing()

func say(text: String) -> void:
	last_line = text
	_bubble_label.text = text
	_bubble_label.custom_minimum_size = Vector2.ZERO
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if _bubble_label.get_minimum_size().x > BUBBLE_MAX_WIDTH:
		_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bubble_label.custom_minimum_size = Vector2(BUBBLE_MAX_WIDTH, 0)
	_bubble_label.visible_ratio = 0.0
	bubble.modulate.a = 1.0
	bubble.scale = Vector2(0.85, 0.85)
	bubble.show()
	_tail.show()
	_tail.modulate.a = 1.0
	_place_bubble()
	_place_bubble.call_deferred()   # перенос считается после раскладки — плашка не раздувается
	bubble.pivot_offset = Vector2(bubble.size.x - 40.0, bubble.size.y)
	if _bubble_tween:
		_bubble_tween.kill()
	_bubble_tween = create_tween()
	_bubble_tween.tween_property(bubble, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bubble_tween.parallel().tween_property(_bubble_label, "visible_ratio", 1.0, text.length() / TYPE_SPEED)
	_bubble_tween.tween_interval(BUBBLE_TIME + text.length() * BUBBLE_PER_CHAR)
	_bubble_tween.tween_property(bubble, "modulate:a", 0.0, BUBBLE_FADE)
	_bubble_tween.parallel().tween_property(_tail, "modulate:a", 0.0, BUBBLE_FADE)
	_bubble_tween.tween_callback(func():
		bubble.hide()
		_tail.hide())

func bubble_text() -> String:
	return _bubble_label.text if bubble.visible else ""

# -------------------------------------------------------
# Вывеска на цепях — кнопка обновления набора
# -------------------------------------------------------
class HangingSign extends Control:
	const WIDTH := 210.0
	const HEIGHT := 44.0
	var button: Button:
		set(b):
			button = b
			b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			b.custom_minimum_size = Vector2.ZERO
	var _t := 0.0
	var _swing := 0.0
	var lifting := false   # подтягивается вверх — не качается: идёт ровно по вертикали

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func swing() -> void:
		_swing = ShopVendor.SIGN_SWING

	func _process(delta: float) -> void:
		_t += delta
		_swing = move_toward(_swing, 0.0, _swing * ShopVendor.SIGN_DAMP * delta + 0.0001)
		var target := 0.0 if lifting else sin(_t * 1.3) * ShopVendor.SIGN_SWAY_IDLE + sin(_t * 6.0) * _swing
		rotation = move_toward(rotation, target, delta * 0.6) if lifting else target
		get_parent().queue_redraw()   # цепи — у продавца: от неподвижных скоб к углам качающейся вывески

	func _draw() -> void:
		for x in corners():
			draw_circle(Vector2(x, 0), 3.0, Palette.VENDOR_BRASS)   # кольцо на углу вывески; цепи — ShopVendor._draw

	func corners() -> Array:
		return [18.0, size.x - 18.0]

# -------------------------------------------------------
# Хвост облака реплики — треугольник от края облака к голове
# -------------------------------------------------------
class BubbleTail extends Control:
	var from_rect := Rect2()
	var to_point := Vector2.ZERO

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if from_rect.size == Vector2.ZERO:
			return
		# хвост в пиксель: точки по целым, контур той же толщины, что у облака (3)
		var base := Vector2(from_rect.end.x - 48.0, from_rect.end.y - 4.0).round()
		var tip := to_point.round()
		var pts := PackedVector2Array([base + Vector2(-10, 0), base + Vector2(10, 0), tip])
		draw_colored_polygon(pts, Palette.BUBBLE_PAPER)
		draw_polyline(PackedVector2Array([pts[0], pts[2], pts[1]]), Palette.BUBBLE_EDGE, 3.0)

# -------------------------------------------------------
# Фигура продавца: лист художника или заглушка кодом
# -------------------------------------------------------
class VendorFigure extends Control:
	var vendor_faction := "space_marines"
	var sprite: AnimatedSprite2D = null
	var _t := 0.0
	var _react := ""
	var _react_left := 0.0
	var _eye := Vector2.ZERO          # куда смотрит линза заглушки (за курсором), −1..1
	var _shadows: Array[AnimatedSprite2D] = []   # падающая тень силуэтом на интерфейс (свет сверху-слева)
	var _k := 1.0                     # масштаб кадра листа на экране
	var _frame_size := Vector2.ZERO

	# Стилизация (решение пользователя 12.11.2026: «добавь тени, убери рамку — пусть стоит на интерфейсе»):
	# под ногами — пятно тени, за фигурой — её силуэт вправо-вниз двумя слоями (мягкий край). Стойка — один
	# кадр, без «дыхания» (решение пользователя 12.11.2026: «пусть просто стоит, анимации — только при действии»)
	const SHADOW_LAYERS := [[Vector2(7, 5), 0.42], [Vector2(13, 10), 0.2]]   # сдвиг на экране, прозрачность
	# В стиль поля (решение пользователя 12.11.2026, стилизация «продавец в стиль»): шейдер бойцов — тёмный контур
	# OUTLINE_SCREEN_PX px экрана (Palette.OUTLINE), свет местности темы "unit_env" (оттенок, насыщенность,
	# приглушение светов) — как у бойцов на поле под магазином
	const OUTLINE_SCREEN_PX := 1.2
	const FOOT_SHADOW_ALPHA := 0.55
	const FOOT_SHADOW_SIZE := Vector2(0.62, 0.075)   # доля ширины / высоты фигуры

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var path: String = ShopVendor.FRAMES_DIR + vendor_faction + "/frames.tres"
		if ResourceLoader.exists(path):
			sprite = AnimatedSprite2D.new()
			sprite.sprite_frames = load(path)
			sprite.centered = false
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # кадры ×2 — на экране вдвое мельче
			sprite.animation_finished.connect(func():
				if sprite.animation != "idle":
					sprite.play("idle"))
			for layer in SHADOW_LAYERS:
				var sh := AnimatedSprite2D.new()
				sh.sprite_frames = sprite.sprite_frames
				sh.centered = false
				sh.texture_filter = sprite.texture_filter
				sh.modulate = Color(0, 0, 0, layer[1])
				add_child(sh)
				_shadows.append(sh)
			sprite.material = ShaderMaterial.new()
			sprite.material.shader = Soldier.unit_shader()
			var env: Dictionary = FactionTheme.current().get("unit_env", {})
			sprite.material.set_shader_parameter("outline_color", Palette.OUTLINE)
			sprite.material.set_shader_parameter("env_sat", env.get("sat", 1.0))
			sprite.material.set_shader_parameter("env_knee", env.get("knee", 0.0))
			sprite.self_modulate = env.get("tint", Color.WHITE)
			Soldier.apply_style(sprite.material, "unit")   # светотень ступенями, как у бойцов
			add_child(sprite)
			# Перетекание кадров: 7–8 кадров на ряд — без него поза меняется рывком (решение пользователя 12.11.2026,
			# «слишком дёрганый»). Фигура неподвижна по холсту — наложение не мелькает, как у мелких бойцов
			FrameBlend.attach(sprite)
			sprite.play("idle")
		resized.connect(_fit_sprite)
		_fit_sprite()

	func has_art() -> bool:
		return sprite != null

	func _fit_sprite() -> void:
		if sprite == null or sprite.sprite_frames.get_frame_count("idle") == 0:
			return
		var tex := sprite.sprite_frames.get_frame_texture("idle", 0)
		var fig_h := float(sprite.sprite_frames.get_meta("figure_height", tex.get_height()))
		_k = size.y / fig_h
		_frame_size = Vector2(tex.get_size())
		if sprite.material is ShaderMaterial:   # контур — в пикселях листа: на экране OUTLINE_SCREEN_PX при любом росте
			sprite.material.set_shader_parameter("outline_px", float(maxi(1, roundi(OUTLINE_SCREEN_PX / maxf(_k, 0.01)))))
		_place_sprites()
		queue_redraw()

	# Кадр стоит ногами на низ фигуры, тени — тем же кадром со сдвигом
	func _place_sprites() -> void:
		sprite.scale = Vector2(_k, _k)
		sprite.position = Vector2((size.x - _frame_size.x * _k) / 2.0, size.y - _frame_size.y * _k)
		for i in _shadows.size():
			var sh := _shadows[i]
			sh.scale = sprite.scale
			sh.position = sprite.position + SHADOW_LAYERS[i][0]
			if sh.animation != sprite.animation:
				sh.animation = sprite.animation
			sh.frame = sprite.frame

	# Голова в координатах фигуры (облако реплики — к ней)
	func head_point() -> Vector2:
		if sprite and sprite.sprite_frames.has_meta("lens"):   # линза в кадре листа (metadata/lens)
			return sprite.position + Vector2(sprite.sprite_frames.get_meta("lens")) * sprite.scale
		return Vector2(size.x * 0.5, size.y * 0.16)

	func react(event: String) -> void:
		_react = event
		_react_left = ShopVendor.REACT_TIME
		if sprite == null:
			return
		var anim: String = event if sprite.sprite_frames.has_animation(event) else ANIM_FALLBACK.get(event, "")
		if anim != "" and sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)

	func _process(delta: float) -> void:
		_t += delta
		_react_left = maxf(_react_left - delta, 0.0)
		if sprite:
			_place_sprites()
		else:
			var m := get_local_mouse_position() - head_point()
			var target := Vector2(clampf(m.x / 300.0, -1.0, 1.0), clampf(m.y / 300.0, -1.0, 1.0))
			_eye = _eye.lerp(target, minf(1.0, delta * 6.0))
			queue_redraw()

	func _draw() -> void:
		if sprite == null:
			_draw_placeholder()
			return
		# Пятно тени под ногами: стопка сплюснутых эллипсов — к краю прозрачнее (за спрайтом: _draw родителя — под детьми)
		var c := Vector2(size.x / 2.0 + 4.0, size.y - 2.0)
		var half := Vector2(size.y * FOOT_SHADOW_SIZE.x, size.y * FOOT_SHADOW_SIZE.y) / 2.0
		for i in 5:
			var f := 1.0 - i * 0.16
			draw_set_transform(c, 0.0, Vector2(half.x * f, half.y * f))
			draw_circle(Vector2.ZERO, 1.0, Color(0, 0, 0, FOOT_SHADOW_ALPHA / 5.0))
		draw_set_transform(Vector2.ZERO)

	# Заглушка до листа художника: силуэт в рясе с капюшоном, линза-глаз за курсором, механодендриты,
	# шестерня Механикус на груди; жесты — подскок (buy), дрожь и красная линза (no_money), дендриты к вывеске
	# (reroll), поклон (sell / greet / catch_up)
	func _draw_placeholder() -> void:
		var chaos := vendor_faction == "chaos"
		var robe: Color = Palette.VENDOR_ROBE_CHAOS if chaos else Palette.VENDOR_ROBE
		var robe_dark: Color = Palette.VENDOR_ROBE_CHAOS_DARK if chaos else Palette.VENDOR_ROBE_DARK
		var lens: Color = Palette.VENDOR_LENS_CHAOS if chaos else Palette.VENDOR_LENS
		var w := size.x
		var h := size.y
		var r := _react_left / ShopVendor.REACT_TIME   # 1 → 0 за время жеста
		var bob := sin(_t * 1.6) * 2.0
		var shake := 0.0
		var bow := 0.0
		match _react:
			"buy":
				bob -= sin(r * PI) * 10.0
			"no_money", "hand_full":
				shake = sin(_t * 40.0) * 4.0 * r
				lens = Palette.VENDOR_LENS_ANGRY if r > 0.0 else lens
			"sell", "greet", "catch_up":
				bow = sin(r * PI) * 10.0
		var cx := w * 0.5 + shake
		var hem := h
		var shoulder_y := h * 0.30 + bob + bow * 0.5
		var head := Vector2(cx + bow * 0.3, h * 0.16 + bob + bow)
		# Механодендриты — из-за спины, покачиваются; на обновлении тянутся вверх к вывеске
		var reach := r if _react == "reroll" else 0.0
		for i in 3:
			var side := -1.0 if i % 2 == 0 else 1.0
			var root := Vector2(cx + side * 26.0, shoulder_y + 10.0)
			var pts := PackedVector2Array()
			for k in 9:
				var u := k / 8.0
				var sway := sin(_t * 1.4 + i * 1.7 + u * 3.0) * 8.0 * u
				var up := lerpf(-40.0 - i * 18.0, -150.0, reach) * u
				pts.append(root + Vector2(side * (40.0 + i * 12.0) * u + sway, up - 30.0 * sin(u * PI)))
			draw_polyline(pts, Palette.VENDOR_METAL_DARK, 6.0)
			draw_polyline(pts, Palette.VENDOR_METAL, 3.0)
			var tip := pts[pts.size() - 1]
			draw_line(tip, tip + Vector2(side * 8.0, -6.0), Palette.VENDOR_BRASS, 2.0)
			draw_line(tip, tip + Vector2(side * 2.0, -10.0), Palette.VENDOR_BRASS, 2.0)
		# Ряса — трапеция с тёмной складкой по центру
		var robe_pts := PackedVector2Array([Vector2(cx - 46.0, shoulder_y), Vector2(cx + 46.0, shoulder_y),
			Vector2(cx + 74.0, hem), Vector2(cx - 74.0, hem)])
		draw_colored_polygon(robe_pts, robe)
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 6.0, shoulder_y + 30.0), Vector2(cx + 6.0, shoulder_y + 30.0),
			Vector2(cx + 16.0, hem), Vector2(cx - 16.0, hem)]), robe_dark)
		draw_polyline(robe_pts + PackedVector2Array([robe_pts[0]]), Palette.OUTLINE, 2.0)
		# Наплечники-аугметика и шестерня на груди
		for side in [-1.0, 1.0]:
			draw_circle(Vector2(cx + side * 44.0, shoulder_y + 6.0), 14.0, Palette.VENDOR_METAL_DARK)
			draw_circle(Vector2(cx + side * 44.0, shoulder_y + 6.0), 10.0, Palette.VENDOR_METAL)
		var cog := Vector2(cx, shoulder_y + 46.0)
		for k in 8:
			var a := k * TAU / 8.0 + _t * 0.3
			draw_line(cog + Vector2.from_angle(a) * 10.0, cog + Vector2.from_angle(a) * 15.0, Palette.VENDOR_BRASS, 4.0)
		draw_circle(cog, 11.0, Palette.VENDOR_BRASS)
		draw_circle(cog, 5.0, robe_dark)
		# Капюшон, тень лица, у Хаоса — шипы
		draw_circle(head, 30.0, robe)
		draw_colored_polygon(PackedVector2Array([head + Vector2(-30, 0), head + Vector2(0, -38), head + Vector2(30, 0)]), robe)
		if chaos:
			for side in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([head + Vector2(side * 18, -22), head + Vector2(side * 34, -52),
					head + Vector2(side * 26, -16)]), Palette.VENDOR_METAL_DARK)
		draw_circle(head + Vector2(0, 6), 19.0, Color(0, 0, 0, 0.85))
		# Линза-глаз за курсором, со свечением; второй глаз — тусклая точка
		var eye := head + Vector2(6.0, 4.0) + _eye * Vector2(5.0, 3.0)
		for k in 3:
			draw_circle(eye, 9.0 - k * 2.5, Color(lens, 0.18 + k * 0.25))
		draw_circle(eye, 2.5, Color(1, 1, 1, 0.9))
		draw_circle(head + Vector2(-8.0, 6.0) + _eye * Vector2(4.0, 2.0), 2.0, Color(lens, 0.5))
