class_name TokenCarousel
extends VBoxContainer

# Карусель жетонов (решение пользователя 13.11.2026, образец `Screenshot 2026-11-13 203111.png`: «выбор расы и ордена
# подобным колесом, но не карт, а жетонов»): выбранный жетон в центре крупно, соседи по дуге мельче и тусклее,
# стрелки по бокам; под каруселью — имя и описание выбранного, кнопка «ВЫБРАТЬ».
# Поворот: стрелки, колесо мыши, ←/→ (жетон в фокусе), клик по боковому жетону; выбор — клик по центральному,
# Enter / пробел или «ВЫБРАТЬ». Закрытый (open = false) можно повернуть в центр и прочитать, выбрать нельзя.
# Жетон — Button (имя name_prefix + id, disabled у закрытых — как карточки прежних окон), медальон рисуется кодом
# (_TokenFace): латунный обод с заклёпками, поле в цвет accent, эмблема icon. Только интерфейс.
#
# items: [{id, name, icon: Texture2D | null, accent: Color, open: bool, lines: [[текст, вариация, цвет | null], …]}]

signal chosen(id: String)

const TOKEN_RADIUS: float = 66.0
const SLOT_X: Array[float] = [0.0, 168.0, 290.0]     # центр жетона по смещению от центра (0, ±1, ±2)
const SLOT_Y: Array[float] = [0.0, -14.0, -24.0]     # дуга: дальние выше — уходят назад
const SLOT_SCALE: Array[float] = [1.0, 0.66, 0.46]
const SLOT_ALPHA: Array[float] = [1.0, 0.8, 0.45]
const SLOT_DIM: Array[float] = [1.0, 0.62, 0.42]     # яркость дальних
const TURN_TIME: float = 0.22
const STAGE_SIZE = Vector2(760, 200)
const INFO_HEIGHT: float = 118.0
const ARROW_SIZE = Vector2(44, 64)
const ARROW_GAP: float = 18.0

var name_prefix: String = "Token_"
var _items: Array = []
var _tokens: Array[Button] = []
var _center: int = 0
var _stage: Control
var _title: Label
var _lines: VBoxContainer
var _choose_btn: Button
var _done: bool = false

func setup(items: Array, prefix: String, start: int = 0) -> void:
	_items = items
	name_prefix = prefix
	add_theme_constant_override("separation", 8)
	_stage = Control.new()
	_stage.custom_minimum_size = STAGE_SIZE
	_stage.mouse_filter = Control.MOUSE_FILTER_PASS
	_stage.gui_input.connect(_on_stage_input)
	_stage.resized.connect(func(): _layout(false))
	add_child(_stage)
	for i in items.size():
		var t := _make_token(items[i], i)
		_stage.add_child(t)
		_tokens.append(t)
	for dir in [-1, 1]:
		var a := Button.new()
		a.name = "ArrowLeft" if dir < 0 else "ArrowRight"
		a.text = "◀" if dir < 0 else "▶"
		a.flat = true
		a.focus_mode = Control.FOCUS_NONE
		a.custom_minimum_size = ARROW_SIZE
		a.size = ARROW_SIZE
		a.add_theme_font_size_override("font_size", 40)
		a.add_theme_color_override("font_color", UITheme.GOLD)
		a.add_theme_color_override("font_hover_color", UITheme.GOLD_BRIGHT)
		a.pressed.connect(turn.bind(dir))
		a.visible = items.size() > 1
		_stage.add_child(a)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(STAGE_SIZE.x, INFO_HEIGHT)   # высота не прыгает от длины описания
	info.add_theme_constant_override("separation", 4)
	add_child(info)
	_title = UITheme.make_label("", "HeaderLabel")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_title)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 2)
	info.add_child(_lines)
	_choose_btn = UITheme.make_button("ВЫБРАТЬ", "", func(): choose_center())
	_choose_btn.name = "ChooseButton"
	_choose_btn.focus_mode = Control.FOCUS_NONE   # Enter — на жетоне в фокусе
	_choose_btn.custom_minimum_size = Vector2(220, 46)
	_choose_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_choose_btn)
	ButtonVolume.attach(_choose_btn, 6.0)
	_center = clampi(start, 0, maxi(items.size() - 1, 0))
	_layout(false)
	_show_info()

func token(id: String) -> Button:
	for t in _tokens:
		if t.get_meta("id") == id:
			return t
	return null

# Смещение жетона от центра по кругу: −n/2 … n/2
func _offset(i: int) -> int:
	var n := _items.size()
	return wrapi(i - _center + n / 2, 0, n) - n / 2

func turn(dir: int) -> void:
	if _items.size() < 2 or _done:
		return
	_center = wrapi(_center + dir, 0, _items.size())
	_layout(true)
	_show_info()
	ModalOverlay.focus_later(_tokens[_center])
	AudioManager.play("ui_click")

func turn_to(i: int) -> void:
	var off := _offset(i)
	if off != 0:
		turn(off)

func choose_center() -> void:
	if _done or _items.is_empty() or not _items[_center]["open"]:
		return
	_done = true
	emit_signal("chosen", _items[_center]["id"])

func _make_token(item: Dictionary, i: int) -> Button:
	var b := Button.new()
	b.name = name_prefix + item["id"]
	b.set_meta("id", item["id"])
	b.disabled = not item["open"]
	b.flat = true
	for s in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	var d := TOKEN_RADIUS * 2.0 + 16.0
	b.custom_minimum_size = Vector2(d, d)
	b.size = Vector2(d, d)
	b.pivot_offset = b.size / 2.0
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var face := _TokenFace.new()
	face.radius = TOKEN_RADIUS
	face.accent = item.get("accent", UITheme.GOLD_DIM)
	face.fire = item.get("fire", false)
	face.icon = item.get("icon")
	face.locked = not item["open"]
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(face)
	if face.locked:
		var lock := UITheme.make_icon("hud", "lock", 30.0)
		if lock:
			lock.name = "Lock"
			lock.position = Vector2(d / 2.0 + TOKEN_RADIUS * 0.38, d / 2.0 + TOKEN_RADIUS * 0.38)
			b.add_child(lock)
	b.gui_input.connect(_on_token_input.bind(i))
	b.mouse_entered.connect(func(): face.hover = true; face.queue_redraw())
	b.mouse_exited.connect(func(): face.hover = false; face.queue_redraw())
	b.focus_entered.connect(func():   # Tab / фокус из окна — жетон едет в центр
		if _offset(i) != 0:
			turn_to(i))
	return b

func _on_token_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if _offset(i) != 0:
			turn_to(i)
		else:
			choose_center()
	elif event.is_action_pressed("ui_left"):
		accept_event()
		turn(-1)
	elif event.is_action_pressed("ui_right"):
		accept_event()
		turn(1)
	elif event.is_action_pressed("ui_accept") and _offset(i) == 0:
		accept_event()
		choose_center()
	else:
		_on_stage_input(event)

func _on_stage_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			accept_event()
			turn(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			accept_event()
			turn(1)

# Жетоны по местам: центр сцены + слот по смещению; дальше ±2 — скрыт. Перескок через край круга — без полёта
func _layout(animate: bool) -> void:
	if _stage == null:
		return
	var mid := Vector2(_stage.size.x / 2.0, _stage.size.y / 2.0 + 6.0)
	for i in _tokens.size():
		var t := _tokens[i]
		var off := _offset(i)
		var k := mini(absi(off), SLOT_X.size() - 1)
		# чётное число жетонов: тот, что напротив центра (−n/2), скрыт — по бокам поровну (у богов было 2 слева, 1 справа)
		var n := _tokens.size()
		var far := absi(off) >= SLOT_X.size() or (n % 2 == 0 and n > 2 and off == -n / 2)
		var target_pos := mid + Vector2(SLOT_X[k] * signf(off), SLOT_Y[k]) - t.size / 2.0
		var target_scale := Vector2.ONE * SLOT_SCALE[k]
		var dim := SLOT_DIM[k]
		var target_mod := Color(dim, dim, dim, 0.0 if far else SLOT_ALPHA[k])
		t.z_index = 10 - absi(off)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE if far else Control.MOUSE_FILTER_STOP
		var face: _TokenFace = t.get_child(0)
		face.selected = off == 0
		face.queue_redraw()
		var jump := animate and t.has_meta("off") and absi(int(t.get_meta("off")) - off) > 2
		t.set_meta("off", off)
		if not animate or jump:
			t.position = target_pos
			t.scale = target_scale
			t.modulate = target_mod
			continue
		var tw := t.create_tween().set_parallel().set_ignore_time_scale(true)
		tw.tween_property(t, "position", target_pos, TURN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(t, "scale", target_scale, TURN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(t, "modulate", target_mod, TURN_TIME)
	# стрелки — вплотную за крайними видимыми жетонами (на фоне меню справа башня: у края сцены стрелка ложилась на неё)
	var reach := mini((_tokens.size() - 1) / 2, SLOT_X.size() - 1)
	var edge := SLOT_X[reach] + TOKEN_RADIUS * SLOT_SCALE[reach] + ARROW_GAP
	for a in _stage.get_children():
		if a.name == "ArrowLeft":
			a.position = Vector2(mid.x - edge - ARROW_SIZE.x, mid.y - ARROW_SIZE.y / 2.0)
		elif a.name == "ArrowRight":
			a.position = Vector2(mid.x + edge, mid.y - ARROW_SIZE.y / 2.0)

func _show_info() -> void:
	if _items.is_empty():
		return
	var item: Dictionary = _items[_center]
	_title.text = item["name"]
	_title.add_theme_color_override("font_color", item.get("title_color", UITheme.GOLD_BRIGHT)
		if item["open"] else UITheme.TEXT_DIM)
	for c in _lines.get_children():
		c.queue_free()
	for line in item.get("lines", []):
		var l := UITheme.make_label(line[0], line[1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(STAGE_SIZE.x - 120.0, 0)
		l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if line.size() > 2 and line[2] != null:
			l.add_theme_color_override("font_color", line[2])
		_lines.add_child(l)
	_choose_btn.disabled = not item["open"]




# Жетон на экране: пиксель-арт TokenArt крупным пикселем без сглаживания, тень ступенями, у выбранного — свечение
# кольцами (пульс), под курсором светлее
class _TokenFace extends Control:
	const EMBLEM_SHARE: float = 0.9   # эмблема — доля диаметра поля
	var radius: float = 66.0
	var accent: Color = Color.WHITE
	var icon: Texture2D = null
	var locked: bool = false
	var fire: bool = false   # «огненно-чёрное» поле (TokenArt.build)
	var selected: bool = false
	var hover: bool = false
	var _t: float = 0.0
	var _tex: Texture2D = null

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_tex = TokenArt.build(accent, locked, fire)
		if icon:   # эмблема — отдельным слоем с мип-уровнями: резкая при любом масштабе окна
			var e := _Emblem.new()
			e.icon = icon
			e.locked = locked
			e.box = TokenArt.FIELD_R * 2.0 * EMBLEM_SHARE * radius / TokenArt.RADIUS
			e.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			e.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(e)

	func _process(delta: float) -> void:
		if selected:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var k := radius / TokenArt.RADIUS   # px экрана на пиксель арта
		for i in 3:   # тень под жетоном — ступенями
			draw_set_transform(c + Vector2(0, radius * 0.95), 0.0, Vector2(1.0, 0.26))
			draw_circle(Vector2.ZERO, radius * (0.95 - 0.12 * i), Color(0, 0, 0, 0.2), true, -1.0, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if selected and not locked:
			var p := 0.5 + 0.5 * sin(_t * 2.6)
			var glow := accent.lightened(0.35)
			for i in 3:
				draw_arc(c, radius + k * (2.0 + i * 2.0 + p * 1.5), 0.0, TAU, 72,
					Color(Palette.TOKEN_RIM[5] if i == 0 else glow, (0.34 - 0.1 * i) * (0.7 + 0.3 * p)), k * 1.6, false)
		var side := TokenArt.ART * k
		draw_texture_rect(_tex, Rect2(c - Vector2(side, side) / 2.0, Vector2(side, side)), false,
			Color(1.12, 1.1, 1.05) if hover and not locked else Color.WHITE)


# Эмблема жетона: исходная текстура (180–256 px) с мип-уровнями, вписана в квадрат box; под ней — тёмный контур
# (та же текстура тёмным цветом со сдвигом на 1.5 px в 8 сторон) и тень вдавливания вправо-вниз; закрытый — тусклый
class _Emblem extends Control:
	const OUTLINE = Color(0.02, 0.015, 0.02, 0.85)
	const SHADOW = Color(0, 0, 0, 0.6)
	var icon: Texture2D
	var locked: bool = false
	var box: float = 80.0

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		var w := float(icon.get_width())
		var h := float(icon.get_height())
		var k := box / maxf(w, h)
		var sz := Vector2(w, h) * k
		var r := Rect2(size / 2.0 - sz / 2.0, sz)
		draw_texture_rect(icon, Rect2(r.position + Vector2(2.5, 3.0), sz), false, SHADOW)
		for a in 8:
			var o := Vector2.from_angle(TAU * a / 8.0) * 1.5
			draw_texture_rect(icon, Rect2(r.position + o, sz), false, OUTLINE)
		draw_texture_rect(icon, r, false, Color(0.4, 0.4, 0.45) if locked else Color.WHITE)
