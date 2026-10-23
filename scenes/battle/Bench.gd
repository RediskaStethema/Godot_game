extends CanvasLayer

# Рука на расстановке (решение пользователя 20.10.2026, ориентир — рука 9 Kings): игральные карты (BenchCard)
# в ряд внизу поверх поля без панели, видна верхняя часть PEEK, карта под курсором поднимается целиком.
# Много карт — ряд сжимается внахлёст (не шире места слева от панели синергий)
@onready var cards_container: Control = $Cards

const BENCH_CARD_SCENE = preload("res://scenes/battle/BenchCard.tscn")
const BenchCardScript = preload("res://scenes/battle/BenchCard.gd")

# Карты на скамейке
var bench_cards: Array[CardData] = []

# Карта которую сейчас тащим
var dragging_card: CardData = null
var drag_preview: Control = null
var empty_hint: Label = null
var _dragged_node: Control = null
var _grab: Vector2 = Vector2.ZERO        # точка карты под курсором (в px карты)
var _grab_hand: Vector2 = Vector2.ZERO   # за какую точку карту взяли в руке (над рукой — снова она)
var _drag_from: Vector2 = Vector2.ZERO   # где карта лежала на руке (экран) — сюда возвращается
var _last_mouse_x: float = 0.0           # курсор в прошлом кадре — наклон карты по ходу

# Тащим саму карту (решение пользователя 21.10.2026: игрок кладёт карту на поле, моделька появляется на клетке):
# лицо карты под курсором за ту же точку, за которую взяли; над полем — мельче и чуть наклонена по ходу
const DRAG_CARD_WIDTH: float = 96.0
const DRAG_FIELD_SCALE: float = 0.55   # над полем карта мельче — видна клетка под ней
const DRAG_TILT: float = 0.0012        # наклон (рад) на px/сек горизонтального хода
const DRAG_TILT_MAX: float = 0.22
const DROP_TIME: float = 0.16          # сыграна — сжимается в клетку
const RETURN_TIME: float = 0.2         # не сыграна — летит обратно в руку
const PEEK: float = UITheme.BENCH_PEEK   # видимая часть опущенной карты
const CARD_GAP: float = 10.0
const SIDE_MARGIN: float = 16.0

func _ready() -> void:
	# Кадровый апдейт нужен только пока тащим карту
	set_process(false)
	# Ряд карт — во всю ширину снизу, справа место под панель синергий; сам клики не ловит
	cards_container.theme = UITheme.get_theme()
	cards_container.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	cards_container.offset_top = -PEEK
	cards_container.offset_bottom = 0
	cards_container.offset_left = SIDE_MARGIN
	cards_container.offset_right = -BENCH_RIGHT_RESERVE - SIDE_MARGIN
	cards_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_container.resized.connect(_layout_cards)
	empty_hint = UITheme.make_label("Рука пуста — карты покупаются в магазине", "DimLabel")
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	empty_hint.add_theme_constant_override("outline_size", 4)
	empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _exit_tree() -> void:
	if dragging_card:   # ушли со сцены посреди перетаскивания — курсор вернуть
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Подсказка может быть вне дерева — освобождаем вручную
	if empty_hint and not empty_hint.is_inside_tree():
		empty_hint.free()

# Ширина справа, которую занимает панель синергий BattleScene
const BENCH_RIGHT_RESERVE: float = 380.0

signal card_dropped_on_tile(card: CardData, screen_pos: Vector2)
# Карта под курсором или в руке (тащим), null — ни одной: BattleScene подсвечивает её отряды на поле
signal card_hovered(card: CardData)
var hovered_card: CardData = null

func setup(cards: Array[CardData]) -> void:
	bench_cards = cards
	_populate()

func _populate() -> void:
	# Карта под курсором сейчас освободится — её mouse_exited уже не придёт
	_set_hovered_card(null)
	for child in cards_container.get_children():
		if child != empty_hint:
			child.queue_free()

	if empty_hint and empty_hint.get_parent():
		empty_hint.get_parent().remove_child(empty_hint)
	if bench_cards.is_empty() and empty_hint:
		cards_container.add_child(empty_hint)

	for i in bench_cards.size():
		var card := bench_cards[i]
		var bench_card = BENCH_CARD_SCENE.instantiate()
		bench_card.order = i
		cards_container.add_child(bench_card)
		bench_card.setup(card)
		bench_card.drag_started.connect(_on_drag_started)
		bench_card.hover_changed.connect(_on_card_hover_changed)
	_layout_cards()

# Ряд по центру; не помещается — шаг меньше ширины карты (внахлёст, правая поверх левой)
func _layout_cards() -> void:
	if empty_hint.get_parent() == cards_container:
		empty_hint.position = Vector2.ZERO
		empty_hint.size = Vector2(cards_container.size.x, PEEK - 12.0)
	var cards := cards_container.get_children().filter(func(c): return c != empty_hint and not c.is_queued_for_deletion())
	cards.sort_custom(func(a, b): return a.order < b.order)
	if cards.is_empty():
		return
	var cs: Vector2 = cards[0].size
	var avail := cards_container.size.x
	var n := cards.size()
	var step := cs.x + CARD_GAP
	if n > 1:
		step = minf(step, (avail - cs.x) / (n - 1))
	var total := cs.x + step * (n - 1)
	var x0 := (avail - total) / 2.0
	for i in n:
		cards[i].set_rest(Vector2(x0 + step * i, 0.0), PEEK - cs.y - cards[i].RAISE_LIFT)

# Пока карту тащат, подсветка держится, хотя курсор уже ушёл с карты на поле
func _on_card_hover_changed(card: CardData, hovered: bool) -> void:
	if hovered:
		_set_hovered_card(card)
	elif card == hovered_card and dragging_card != card:
		_set_hovered_card(null)

func _set_hovered_card(card: CardData) -> void:
	if card == hovered_card:
		return
	hovered_card = card
	card_hovered.emit(card)

# -------------------------------------------------------
# DRAG & DROP
# -------------------------------------------------------
func _on_drag_started(card: CardData, from_pos: Vector2) -> void:
	dragging_card = card
	for c in cards_container.get_children():
		if c.get("card_data") == card:
			_dragged_node = c
			c.set_dragged(true)

	# За мышью идёт сама карта, взятая за ту же точку (в масштабе карты руки)
	var mouse := get_viewport().get_mouse_position()
	var k := DRAG_CARD_WIDTH / BenchCardScript.CARD_WIDTH
	var face := UITheme.make_card_face(card, DRAG_CARD_WIDTH, str(card.unit_count) if card.card_type == "squad" else "")
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview = face
	add_child(drag_preview)
	_grab = (mouse - from_pos) * k
	_grab_hand = _grab
	drag_preview.pivot_offset = _grab
	drag_preview.global_position = mouse - _grab
	_drag_from = from_pos
	_last_mouse_x = mouse.x
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN   # вместо курсора — сама карта (решение пользователя 21.10.2026)
	set_process(true)

func _process(delta: float) -> void:
	if drag_preview == null or not is_instance_valid(drag_preview):
		return
	# Карта — точно под курсором (решение пользователя 21.10.2026: плавное догоняние отставало), наклон по ходу
	# мыши; над полем (не над рукой) — мельче
	var mouse := get_viewport().get_mouse_position()
	drag_preview.global_position = mouse - _grab
	var vx := (mouse.x - _last_mouse_x) / maxf(delta, 0.001)
	_last_mouse_x = mouse.x
	drag_preview.rotation = lerpf(drag_preview.rotation, clampf(vx * DRAG_TILT, -DRAG_TILT_MAX, DRAG_TILT_MAX),
		minf(1.0, 12.0 * delta))
	var over_field := mouse.y < get_viewport().get_visible_rect().size.y - PEEK
	var want := DRAG_FIELD_SCALE if over_field else 1.0
	drag_preview.scale = drag_preview.scale.lerp(Vector2(want, want), minf(1.0, 14.0 * delta))
	# Курсор скрыт — указатель сама карта: над полем она встаёт центром на курсор, и клетка под картой — та,
	# куда она ляжет (решение пользователя 22.10.2026: взятая за край карта висела над одной клеткой, а
	# подсвечивалась другая); над рукой — снова за ту точку, за которую взяли
	var grab_want: Vector2 = drag_preview.size / 2.0 if over_field else _grab_hand
	_grab = _grab.lerp(grab_want, minf(1.0, 14.0 * delta))
	drag_preview.pivot_offset = _grab
	drag_preview.global_position = mouse - _grab

func _input(event: InputEvent) -> void:
	if not dragging_card:
		return

	if event is InputEventMouseMotion and drag_preview and is_instance_valid(drag_preview):
		drag_preview.global_position = event.position - _grab   # сразу по движению, не ждём кадра
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			# Отпустили мышь — пытаемся положить на тайл
			_on_drop(get_viewport().get_mouse_position())

func _on_drop(screen_pos: Vector2) -> void:
	set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var card := dragging_card
	var hand_node := _dragged_node
	_dragged_node = null

	# Сообщаем BattleScene куда бросили карту — она сыграет её сразу
	emit_signal("card_dropped_on_tile", card, screen_pos)
	dragging_card = null
	_set_hovered_card(null)
	# Карта ушла с руки — сыграна: сжимается в клетку; осталась — летит обратно в руку
	var preview := drag_preview
	drag_preview = null
	if preview == null or not is_instance_valid(preview):
		_restore_hand_card(hand_node)
		return
	var tw := preview.create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if not bench_cards.has(card):
		tw.tween_property(preview, "global_position", screen_pos - _grab, DROP_TIME)
		tw.tween_property(preview, "scale", Vector2(0.15, 0.15), DROP_TIME)
		tw.tween_property(preview, "modulate:a", 0.0, DROP_TIME)
	else:
		# Назад на место в руке, в размер карты руки (масштаб — вокруг точки захвата)
		var back := BenchCardScript.CARD_WIDTH / DRAG_CARD_WIDTH
		tw.tween_property(preview, "global_position", _drag_from - _grab * (1.0 - back), RETURN_TIME)
		tw.tween_property(preview, "scale", Vector2(back, back), RETURN_TIME)
		tw.tween_property(preview, "rotation", 0.0, RETURN_TIME)
		tw.tween_property(preview, "modulate:a", 0.0, RETURN_TIME)
	tw.chain().tween_callback(preview.queue_free)
	tw.tween_callback(_restore_hand_card.bind(hand_node))   # карта на руке проявляется, когда долетела

# Без типа: карта сыграна — её узел в руке освобождается раньше колбэка твина, а освобождённый объект в
# типизированный аргумент не передать («Cannot convert argument 1 from Object to Object»)
func _restore_hand_card(node) -> void:
	if is_instance_valid(node):
		node.set_dragged(false)

# Пауза посреди перетаскивания (Esc) или окно потеряло фокус (alt-tab): отпускание кнопки не дойдёт —
# карта в руку, курсор виден
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_drag()

func _cancel_drag() -> void:
	if dragging_card == null:
		return
	set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if drag_preview and is_instance_valid(drag_preview):
		drag_preview.queue_free()
	drag_preview = null
	_restore_hand_card(_dragged_node)
	_dragged_node = null
	dragging_card = null
	_set_hovered_card(null)
