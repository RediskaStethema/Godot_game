extends Control

# Карта руки на расстановке (решение пользователя 20.10.2026, ориентир — рука 9 Kings, Screenshot 2026-10-20 140249.png):
# игральная карта (UITheme.make_card_face) внизу поверх поля, видна верхняя часть (Bench.PEEK), под курсором
# поднимается целиком, над ней — описание. Положение в ряду задаёт Bench (set_rest)

const CARD_WIDTH: float = 150.0
const RAISE_LIFT: float = 10.0      # поднятая карта — выше нижнего края экрана на столько
const RAISE_TIME: float = 0.12
const DESC_WIDTH: float = 200.0
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
	_build_desc(data)
	mouse_entered.connect(func():
		_set_raised(true)
		hover_changed.emit(card_data, true))
	mouse_exited.connect(func():
		_set_raised(false)
		hover_changed.emit(card_data, false))

# Описание над поднятой картой: что делает и куда класть
func _build_desc(data: CardData) -> void:
	_desc = UITheme.make_panel("HudPanel", true)
	_desc.name = "Desc"
	var lines: Array[String] = []
	if data.get_stats_line() != "":
		lines.append(data.get_stats_line())
	lines.append(data.description)
	if data.get_play_hint() != "":
		lines.append("(в бою: %s)" % data.get_play_hint())
	var l := UITheme.make_label("\n".join(lines), "SmallLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(DESC_WIDTH - 20.0, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc.add_child(l)
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
	if on:
		_desc.reset_size()
		_desc.position = Vector2((size.x - _desc.size.x) / 2.0, -_desc.size.y - DESC_GAP)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position:y", _raised_y if on else _rest.y, RAISE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func set_dragged(on: bool) -> void:
	modulate.a = DRAG_ALPHA if on else 1.0

# -------------------------------------------------------
# DRAG & DROP
# -------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Начинаем тащить
				is_dragging = true
				drag_offset = event.position
				emit_signal("drag_started", card_data, global_position)
			else:
				is_dragging = false
