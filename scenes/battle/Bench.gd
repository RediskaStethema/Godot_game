extends CanvasLayer

@onready var cards_container: HBoxContainer = $BenchPanel/HBoxContainer

const BENCH_CARD_SCENE = preload("res://scenes/battle/BenchCard.tscn")

# Карты на скамейке
var bench_cards: Array[CardData] = []

# Карта которую сейчас тащим
var dragging_card: CardData = null
var drag_preview: Control = null
var empty_hint: Label = null

const PREVIEW_SIZE = Vector2(72, 72)

func _ready() -> void:
	# Кадровый апдейт нужен только пока тащим карту
	set_process(false)
	# Панель скамейки — во всю ширину снизу, справа место под панель синергий
	var panel: PanelContainer = $BenchPanel
	panel.theme = UITheme.get_theme()
	panel.theme_type_variation = "HudPanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -UITheme.BENCH_HEIGHT
	panel.offset_bottom = 0
	panel.offset_left = 0
	panel.offset_right = -BENCH_RIGHT_RESERVE
	# До 10 карт (лимит руки) не влезают в ширину — горизонтальная прокрутка
	var scroll = ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	cards_container.reparent(scroll)
	cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_container.add_theme_constant_override("separation", 10)
	empty_hint = UITheme.make_label("Скамейка пуста — карты покупаются в магазине", "DimLabel")
	empty_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _exit_tree() -> void:
	# Подсказка может быть вне дерева — освобождаем вручную
	if empty_hint and not empty_hint.is_inside_tree():
		empty_hint.free()

# Ширина справа, которую занимает панель синергий BattleScene
const BENCH_RIGHT_RESERVE: float = 380.0

signal card_dropped_on_tile(card: CardData, tile: Vector2i)

func setup(cards: Array[CardData]) -> void:
	bench_cards = cards
	_populate()

func _populate() -> void:
	for child in cards_container.get_children():
		if child != empty_hint:
			child.queue_free()

	if empty_hint and empty_hint.get_parent():
		empty_hint.get_parent().remove_child(empty_hint)
	if bench_cards.is_empty() and empty_hint:
		cards_container.add_child(empty_hint)

	for card in bench_cards:
		var bench_card = BENCH_CARD_SCENE.instantiate()
		cards_container.add_child(bench_card)
		bench_card.setup(card)
		bench_card.drag_started.connect(_on_drag_started)

# -------------------------------------------------------
# DRAG & DROP
# -------------------------------------------------------
func _on_drag_started(card: CardData, from_pos: Vector2) -> void:
	dragging_card = card

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

	# Сообщаем BattleScene куда бросили карту
	# BattleScene сама разберётся попали ли мы на тайл
	emit_signal("card_dropped_on_tile", dragging_card, screen_pos)
	dragging_card = null
