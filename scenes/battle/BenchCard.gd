extends Control

# Карта руки на расстановке (решение пользователя 20.10.2026, ориентир — рука 9 Kings, Screenshot 2026-10-20 140249.png):
# игральная карта (UITheme.make_card_face) внизу поверх поля, видна верхняя часть (Bench.PEEK), под курсором
# поднимается целиком, над ней — описание. Положение в ряду задаёт Bench (set_rest)

const CARD_WIDTH: float = 112.0   # решение пользователя 22.10.2026: было 150 — велики, неудобно ставить на клетку
const RAISE_LIFT: float = 10.0      # поднятая карта — выше нижнего края экрана на столько
const RAISE_TIME: float = 0.12
const DESC_WIDTH: float = 236.0   # шире (12.11.2026): плашки характеристик — в одну строку
const DESC_GAP: float = 6.0
const DRAG_ALPHA: float = 0.35      # карта, которую тащат, на скамейке бледнеет

var card_data: CardData = null
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var raised: bool = false
var order: int = 0               # место в ряду (Bench): поднятая карта — последней в дереве, опущенная — на место
var _rest := Vector2.ZERO
var _raised_y: float = 0.0
var _tween: Tween = null
var _desc: PanelContainer
# Описание сбоку от поднятой карты, низом по её низу (рука магазина, ShopHand: над картой оно закрывало
# описания карт набора — решение пользователя 12.11.2026); false — над картой (расстановка)
var desc_side: bool = false
var _glare: CardGlare = null
# Рука магазина (ShopHand, 12.11.2026): карту не тащат, на поднятой — «Продать +N» по нижней кромке
var draggable: bool = true
var sell_button: Button = null
const SELL_HEIGHT: float = 24.0
const SELL_PAD: float = 6.0
signal sell_pressed(card: CardData)

# Сигнал — когда начали тащить карту
signal drag_started(card: CardData, screen_pos: Vector2)
# Курсор на карте / ушёл с неё — BattleScene подсвечивает клетки этого отряда на поле
signal hover_changed(card: CardData, hovered: bool)

static func card_size() -> Vector2:
	return UITheme.CARD_ART_SIZE * CARD_WIDTH / UITheme.CARD_ART_SIZE.x

func setup(data: CardData) -> void:
	card_data = data
	size = card_size()
	custom_minimum_size = size
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	# Медальон: у отряда — число бойцов, у остальных пусто (цены на руке нет)
	var face := UITheme.make_card_face(data, CARD_WIDTH, str(data.unit_count) if data.card_type == "squad" else "")
	add_child(face)
	_glare = CardGlare.attach(face, data.rarity)   # наклон, блик, подсветка редкости — под курсором (только вид)
	_build_desc(data)
	if not draggable:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	mouse_entered.connect(func():
		_set_raised(true)
		hover_changed.emit(card_data, true))
	mouse_exited.connect(func():
		_set_raised(false)
		hover_changed.emit(card_data, false))

# «Продать +N» — внизу карты, видна только у поднятой (рука магазина). Звать после setup
func add_sell_button(price: int) -> void:
	sell_button = Button.new()
	sell_button.name = "Sell"
	sell_button.text = "Продать +%d" % price
	UITheme.set_coin_icon(sell_button, true, 14)   # монета справа от числа
	sell_button.add_theme_font_size_override("font_size", UITheme.ui_px(11))
	sell_button.set_meta(AudioManager.NO_CLICK, true)   # свой звук — sell
	sell_button.clip_text = true   # узкая карта: кнопка не шире её
	sell_button.pressed.connect(func(): sell_pressed.emit(card_data))
	sell_button.hide()
	add_child(sell_button)
	# Размер — после входа в дерево: до него минимальный размер кнопки считался по монете в полный рост (96 px),
	# и кнопка вырастала на полкарты
	sell_button.position = Vector2(SELL_PAD, size.y - SELL_HEIGHT - SELL_PAD)
	sell_button.size = Vector2(size.x - SELL_PAD * 2.0, SELL_HEIGHT)

# Описание над поднятой картой: что делает и куда класть
# Подсказка карты (решение пользователя 12.11.2026, «подсказки карт»): рамка подсказок (TooltipPanel), сверху
# плашки характеристик (UITheme.make_stat_chips — не рвутся по строкам), описание по левому краю, «куда класть» —
# приглушённо
func _build_desc(data: CardData) -> void:
	_desc = UITheme.make_panel("TooltipPanel", true)
	_desc.name = "Desc"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc.add_child(box)
	var chips := UITheme.make_stat_chips(data)
	if chips:
		box.add_child(chips)
	var l := UITheme.make_label(data.description, "SmallLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(DESC_WIDTH - 20.0, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	if data.get_play_hint() != "":
		var hint := UITheme.make_label("В бою: %s" % data.get_play_hint(), "DimLabel")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(DESC_WIDTH - 20.0, 0)
		hint.add_theme_font_size_override("font_size", UITheme.text_px(11))
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(hint)
	_desc.hide()
	add_child(_desc)

# Место в ряду (Bench): rest — опущенная карта, raised_y — поднятая
func set_rest(rest: Vector2, raised_y: float) -> void:
	_rest = rest
	_raised_y = raised_y
	position = Vector2(rest.x, raised_y if raised else rest.y)

func _set_raised(on: bool) -> void:
	raised = on
	# Внахлёст курсор ловит карта, что позже в дереве (z_index на это не влияет) — поднятая уходит в конец
	if is_inside_tree():
		get_parent().move_child(self, -1 if on else mini(order, get_parent().get_child_count() - 1))
	_desc.visible = on
	if sell_button:
		sell_button.visible = on
	if on:
		_desc.reset_size()
		if desc_side:   # справа от карты, у правого края экрана — слева
			var right := get_global_rect().end.x + DESC_GAP + _desc.size.x <= get_viewport_rect().size.x
			# низом по низу карты; за край экрана не уходит — _keep_desc_on_screen, пока карта поднимается
			_desc.position = Vector2(size.x + DESC_GAP if right else -_desc.size.x - DESC_GAP, size.y - _desc.size.y)
		else:
			_desc.position = Vector2((size.x - _desc.size.x) / 2.0, -_desc.size.y - DESC_GAP)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position:y", _raised_y if on else _rest.y, RAISE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# Описание сбоку — низом не ниже края экрана (веер руки магазина сдвигает и наклоняет карту — считаем по факту)
func _process(_delta: float) -> void:
	if not (desc_side and raised and _desc and _desc.visible):
		return
	_desc.position.y = size.y - _desc.size.y   # каждый кадр от исходного — поправки не копятся, пока карта поднимается
	var over := _desc.get_global_rect().end.y - (get_viewport_rect().size.y - DESC_GAP)
	if over > 0.0:
		_desc.position.y -= over

func set_dragged(on: bool) -> void:
	modulate.a = DRAG_ALPHA if on else 1.0
	if _glare:
		_glare.enabled = not on

# -------------------------------------------------------
# DRAG & DROP
# -------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and draggable:
			if event.pressed:
				# Начинаем тащить
				is_dragging = true
				drag_offset = event.position
				emit_signal("drag_started", card_data, global_position)
			else:
				is_dragging = false
