class_name ShopHand
extends Control

# Рука магазина (решение пользователя 12.11.2026, образец download.png): карты веером внизу экрана, как рука
# расстановки (Bench) — видна верхняя часть PEEK, карта под курсором поднимается целиком, над ней описание,
# на ней — «Продать +N» (BenchCard.add_sell_button). Карты не тащат. Много карт — внахлёст.
# Узел — полоса по низу экрана высотой PEEK; продажу обрабатывает ShopScene (sell_requested).

const BENCH_CARD_SCENE = preload("res://scenes/battle/BenchCard.tscn")
const PEEK: float = UITheme.BENCH_PEEK
const CARD_GAP: float = 10.0
const FAN_TILT: float = 0.035      # рад: крайние карты веера чуть повёрнуты (образец — карты веером)
const FAN_DROP: float = 6.0        # px: крайние карты ниже середины

signal sell_requested(card: CardData)

var cards: Array[CardData] = []
var empty_hint: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.get_theme()
	empty_hint = UITheme.make_label("Пусто — купленные карты появятся здесь", "DimLabel")
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_hint.add_theme_constant_override("outline_size", 4)
	empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(empty_hint)
	empty_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)

func setup(hand: Array[CardData]) -> void:
	cards = hand
	refresh()

func refresh() -> void:
	for c in get_children():
		if c != empty_hint:
			c.queue_free()
	empty_hint.visible = cards.is_empty()
	for i in cards.size():
		var node = BENCH_CARD_SCENE.instantiate()
		node.order = i
		node.draggable = false
		node.desc_side = true   # описание сбоку — не закрывает карты набора
		add_child(node)
		node.setup(cards[i])
		node.set_meta("card", cards[i])   # ShopScene: полёт покупки и огонь продажи — по этому узлу
		node.add_sell_button(EconomyManager.get_sell_price(cards[i]))
		node.sell_pressed.connect(func(card): sell_requested.emit(card))
	_layout()

# Узел карты в руке (не освобождается); нет — null
func card_node(card: CardData) -> Control:
	for c in get_children():
		if c != empty_hint and not c.is_queued_for_deletion() and c.get_meta("card", null) == card:
			return c
	return null

func _layout() -> void:
	var nodes := get_children().filter(func(c): return c != empty_hint and not c.is_queued_for_deletion())
	nodes.sort_custom(func(a, b): return a.order < b.order)
	if nodes.is_empty():
		return
	var cs: Vector2 = nodes[0].size
	var n := nodes.size()
	var step := cs.x + CARD_GAP
	if n > 1:
		step = minf(step, (size.x - cs.x) / (n - 1))
	var total := cs.x + step * (n - 1)
	var x0 := (size.x - total) / 2.0
	for i in n:
		var k := 0.0 if n == 1 else (float(i) / (n - 1)) * 2.0 - 1.0   # −1 … 1 от левого края веера к правому
		var node: Control = nodes[i]
		node.pivot_offset = Vector2(cs.x / 2.0, cs.y)
		node.rotation = k * FAN_TILT
		node.set_rest(Vector2(x0 + step * i, absf(k) * FAN_DROP), PEEK - cs.y - node.RAISE_LIFT)
