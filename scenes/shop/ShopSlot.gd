extends PanelContainer

@onready var card_title: Label = $VBoxContainer/UnitName
@onready var card_faction: Label = $VBoxContainer/UnitFaction
@onready var card_desc: Label = $VBoxContainer/UnitStats
@onready var buy_button: Button = $VBoxContainer/BuyButton

const CARD_SIZE = Vector2(220, 330)
# Портрет по силуэту бойца на грунте расы в рамке редкости (UITheme.make_portrait_frame): окно почти в
# пропорции рамки по ширине карты без полей (чуть ниже — место описанию)
const PORTRAIT_HEIGHT = 156.0
# Есть иллюстрация карты (assets/ui/card_art) — вместо портрета и заголовка лицо игральной карты
# (UITheme.make_card_face: название на плашке рамки, цена и масть в медальонах)
const CARD_FACE_WIDTH = 180.0
const DESC_FONT: int = 12          # кегль описания под карты (прежней разметки, через UITheme.text_px)
const DESC_LINE_SPACING: int = -3
# Сноски «на поле» и синергий — над кнопкой «Купить», не на портрете (решение пользователя)
const NOTE_GAP = 4.0
const NOTE_SIDE = 8.0

var slot_index: int = 0
var card_data: CardData = null
var hand_full: bool = false
var free: bool = false   # карта подкрепления — всегда бесплатно
var owned_note: PanelContainer = null   # сноска «на поле: ур. N» при наведении
var synergy_note: PanelContainer = null # под ней — синергии с этой картой (ShopManager.get_synergy_note)
var _synergy_label: Label
var _owned_label: Label = null
var _notes: VBoxContainer
var _notes_layer: Control
var _face: Control = null        # лицо игральной карты (есть арт) или null
var _face_cost: Label = null

signal purchase_requested(slot_index: int)

func setup(data: CardData, index: int, is_free: bool = false) -> void:
	card_data = data
	slot_index = index
	free = is_free
	custom_minimum_size = CARD_SIZE
	add_theme_stylebox_override("panel", UITheme.card_style(data.rarity))
	$VBoxContainer.add_theme_constant_override("separation", 6)
	_fill_header(data)
	_fill_body(data)
	buy_button.custom_minimum_size = Vector2(0, 42)
	buy_button.pressed.connect(_on_buy_pressed)
	# Неактивная кнопка (не хватает Req, рука полна) — клик всё равно отвечает: ShopScene скажет почему
	buy_button.gui_input.connect(func(e: InputEvent):
		if buy_button.disabled and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_on_buy_pressed())
	EconomyManager.requisition_changed.connect(_on_requisition_changed)
	_refresh_button()
	_build_owned_note()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	add_theme_stylebox_override("panel", UITheme.card_style(card_data.rarity, true))
	show_owned_note()

func _on_mouse_exited() -> void:
	# Курсор ушёл на кнопку «Купить» — он всё ещё над картой
	if Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
		return
	add_theme_stylebox_override("panel", UITheme.card_style(card_data.rarity))
	owned_note.hide()
	synergy_note.hide()
	card_desc.get_parent().modulate.a = 1.0

# Сноска поверх портрета: такой отряд / здание уже на поле — уровень (ShopManager.get_owned_note).
# Текст — в момент наведения: армия могла измениться, пока магазин открыт
func show_owned_note() -> void:
	var text := ShopManager.get_owned_note(card_data)
	_owned_label.text = text
	owned_note.visible = text != ""
	var syn := ShopManager.get_synergy_note(card_data)
	_synergy_label.text = syn
	synergy_note.visible = syn != ""
	# Сноски — вместо описания во вставке: текст под ними не проглядывает (прокрутка — его родитель)
	card_desc.get_parent().modulate.a = 0.0 if owned_note.visible or synergy_note.visible else 1.0
	_place_notes()
	_place_notes.call_deferred()   # показ в первый кадр слота — раскладка ещё не построена

# Низ сносок — над кнопкой «Купить» (растут вверх, на описание карты)
func _place_notes() -> void:
	_notes.offset_bottom = buy_button.global_position.y - _notes_layer.global_position.y - _notes_layer.size.y - NOTE_GAP
	_notes.offset_top = _notes.offset_bottom

func _build_owned_note() -> void:
	var layer := Control.new()   # слой поверх содержимого карты, клики не ловит
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	_notes_layer = layer
	var notes := VBoxContainer.new()   # «на поле» и синергии — друг под другом
	notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notes.add_theme_constant_override("separation", 2)
	notes.alignment = BoxContainer.ALIGNMENT_END
	layer.add_child(notes)
	notes.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	notes.offset_left = NOTE_SIDE
	notes.offset_right = -NOTE_SIDE
	notes.grow_vertical = Control.GROW_DIRECTION_BEGIN   # растёт вверх от кнопки
	_notes = notes
	# Сноски — во вставку описания, тем же мелким кеглем (25.10.2026: крупные и зелёные лезли на арт карты)
	owned_note = UITheme.make_panel("HudPanel", true)
	owned_note.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_DEEP, UITheme.GOLD, 1, 4, 3))
	owned_note.hide()
	notes.add_child(owned_note)
	synergy_note = UITheme.make_panel("HudPanel", true)
	synergy_note.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_DEEP, UITheme.GOLD_DIM, 1, 4, 3))
	synergy_note.hide()
	notes.add_child(synergy_note)
	_synergy_label = UITheme.make_label("", "SmallLabel")
	_synergy_label.add_theme_color_override("font_color", Palette.AMBER_LIGHT)
	_synergy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_synergy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_synergy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	synergy_note.add_child(_synergy_label)
	_owned_label = UITheme.make_label("", "SmallLabel")
	_owned_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	_owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_owned_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_owned_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owned_note.add_child(_owned_label)
	for l in [_synergy_label, _owned_label]:
		l.add_theme_font_size_override("font_size", UITheme.text_px(DESC_FONT))
		l.add_theme_constant_override("line_spacing", DESC_LINE_SPACING)

# Редкость · тип, портрет, название
func _fill_header(data: CardData) -> void:
	if UITheme.has_card_art(data):
		_face = UITheme.make_card_face(data, CARD_FACE_WIDTH, str(_cost()))
		_face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_face.tooltip_text = "%s · %s" % [UITheme.RARITY_NAMES.get(data.rarity, data.rarity),
			UITheme.TYPE_NAMES.get(data.card_type, data.card_type)]
		_face_cost = _face.get_node("Cost")
		$VBoxContainer.add_child(_face)
		$VBoxContainer.move_child(_face, 0)
		card_faction.hide()   # редкость и тип — рамка и масть
		card_title.text = data.title
		card_title.hide()     # название — на плашке рамки
		return
	card_faction.text = "%s · %s" % [
		UITheme.RARITY_NAMES.get(data.rarity, data.rarity),
		UITheme.TYPE_NAMES.get(data.card_type, data.card_type)]
	card_faction.theme_type_variation = "DimLabel"
	card_faction.add_theme_color_override("font_color", UITheme.rarity_color(data.rarity))
	# Портрет: кадр idle юнита, для зданий/улучшений — заглушка с названием типа
	var portrait = _make_portrait(data)
	$VBoxContainer.add_child(portrait)
	$VBoxContainer.move_child(portrait, 1)
	card_title.text = data.title
	card_title.theme_type_variation = "CardTitleLabel"
	card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

# Характеристики + описание + куда класть (CardData — общее для магазина и скамейки)
func _fill_body(data: CardData) -> void:
	var lines: Array[String] = []
	if data.get_stats_line() != "":
		lines.append(data.get_stats_line())
	lines.append(data.description)
	if data.get_play_hint() != "":
		lines.append("(в бою: %s)" % data.get_play_hint())
	card_desc.text = "\n".join(lines)
	card_desc.theme_type_variation = "SmallLabel"
	# Пиксельный RetroSans выше Play на строку — мельче и плотнее, чтобы во вставке было видно 3–4 строки
	card_desc.add_theme_font_size_override("font_size", UITheme.text_px(DESC_FONT))
	card_desc.add_theme_constant_override("line_spacing", DESC_LINE_SPACING)
	card_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Длинное описание прокручивается, а не растягивает карту — иначе она налезает на руку под магазином
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Описание — во вставке под иллюстрацией (ориентир пользователя — карты 9 Kings, 20.10.2026)
	var inset = PanelContainer.new()
	inset.name = "DescInset"
	inset.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_DEEP, UITheme.GOLD_DIM, 1, 4, 5))
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$VBoxContainer.add_child(inset)
	$VBoxContainer.move_child(inset, card_desc.get_index())
	inset.add_child(scroll)
	card_desc.reparent(scroll)
	card_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _make_portrait(data: CardData) -> Control:
	return UITheme.make_portrait_frame(data, PORTRAIT_HEIGHT, true)   # в рамке редкости

# Низ портрета / лица карты — сноски не должны на него залезать (tests/test_battle_ui.gd)
func portrait_bottom() -> float:
	if _face:
		return _face.get_global_rect().end.y
	return card_title.global_position.y

# Карта переворачивается из рубашки (обновление набора, решение пользователя 20.10.2026): сначала видна
# рубашка расы, через delay карта сжимается по ширине, рубашка прячется, лицо разворачивается. Только вид
const FLIP_TIME: float = 0.22
func reveal(delay: float) -> void:
	var back_tex := UITheme.card_back(card_data.faction)
	if _face == null or back_tex == null:
		return
	var back = TextureRect.new()
	back.name = "CardBack"
	back.texture = back_tex
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_callback(func(): _face.pivot_offset = _face.size / 2.0)
	t.tween_property(_face, "scale:x", 0.0, FLIP_TIME / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(back.queue_free)
	t.tween_property(_face, "scale:x", 1.0, FLIP_TIME / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _cost() -> int:
	return 0 if free else ShopManager.get_price(card_data)

func set_hand_full(full: bool) -> void:
	hand_full = full
	_refresh_button()

func _refresh_button() -> void:
	var cost = _cost()
	if _face_cost:
		_face_cost.text = str(cost)
	if hand_full:
		buy_button.text = "Рука полна"
		buy_button.disabled = true
		return
	buy_button.text = "Взять бесплатно" if cost == 0 else "Купить · %d Req" % cost
	buy_button.disabled = not EconomyManager.can_afford(cost)

func _on_buy_pressed() -> void:
	emit_signal("purchase_requested", slot_index)

# Не хватает Req — красная вспышка у цены (медальон лица карты, без арта — кнопка «Купить»)
const NO_MONEY_SIZE: float = 1.2
func flash_no_money() -> void:
	var at: Control = _face_cost if _face_cost else buy_button
	Vfx.spawn_over(self, "no_money", at.get_global_rect(), NO_MONEY_SIZE)

func _on_requisition_changed(_new_amount: int) -> void:
	if card_data:
		_refresh_button()
