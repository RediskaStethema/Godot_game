extends CanvasLayer

# Рука на расстановке (решение пользователя 20.10.2026, ориентир — рука 9 Kings): игральные карты (BenchCard)
# в ряд внизу поверх поля без панели, видна верхняя часть PEEK, карта под курсором поднимается целиком.
# Много карт — ряд сжимается внахлёст (не шире места слева от панели синергий)
@onready var cards_container: Control = $Cards

const BENCH_CARD_SCENE = preload("res://scenes/battle/BenchCard.tscn")

# Карты на скамейке
var bench_cards: Array[CardData] = []

# Карта которую сейчас тащим
var dragging_card: CardData = null
var drag_preview: Control = null
var empty_hint: Label = null
var _dragged_node: Control = null

const PREVIEW_SIZE = Vector2(72, 72)
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
	# Подсказка может быть вне дерева — освобождаем вручную
	if empty_hint and not empty_hint.is_inside_tree():
		empty_hint.free()

# Ширина справа, которую занимает панель синергий BattleScene
const BENCH_RIGHT_RESERVE: float = 380.0

signal card_dropped_on_tile(card: CardData, tile: Vector2i)
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

	# Компактный превью (портрет юнита) следует за мышью
	var preview = TextureRect.new()
	preview.texture = UITheme.card_portrait(card)
	if preview.texture == null:
		preview.texture = preload("res://assets/cards/card_preview_default.png")
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	preview.size = PREVIEW_SIZE
	preview.modulate = UITheme.card_tint(card) * Color(1, 1, 1, 0.75)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview = preview
	add_child(drag_preview)
	drag_preview.global_position = from_pos
	set_process(true)

func _process(_delta: float) -> void:
	# Превью следует за мышью
	if drag_preview and is_instance_valid(drag_preview):
		drag_preview.global_position = get_viewport().get_mouse_position() - PREVIEW_SIZE / 2.0

func _input(event: InputEvent) -> void:
	if not dragging_card:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			# Отпустили мышь — пытаемся положить на тайл
			_on_drop(get_viewport().get_mouse_position())

func _on_drop(screen_pos: Vector2) -> void:
	set_process(false)
	# Убираем превью
	if drag_preview:
		drag_preview.queue_free()
		drag_preview = null
	if is_instance_valid(_dragged_node):
		_dragged_node.set_dragged(false)
	_dragged_node = null

	# Сообщаем BattleScene куда бросили карту
	# BattleScene сама разберётся попали ли мы на тайл
	emit_signal("card_dropped_on_tile", dragging_card, screen_pos)
	dragging_card = null
	_set_hovered_card(null)
