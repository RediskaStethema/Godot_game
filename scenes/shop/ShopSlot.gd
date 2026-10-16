extends PanelContainer

@onready var card_title: Label = $VBoxContainer/UnitName
@onready var card_faction: Label = $VBoxContainer/UnitFaction
@onready var card_desc: Label = $VBoxContainer/UnitStats
@onready var buy_button: Button = $VBoxContainer/BuyButton

const CARD_SIZE = Vector2(220, 270)
const PORTRAIT_HEIGHT = 70.0
const OWNED_NOTE_TOP = 22.0   # сноска «на поле» — поверх портрета, под строкой редкости

var slot_index: int = 0
var card_data: CardData = null
var hand_full: bool = false
var free: bool = false   # карта подкрепления — всегда бесплатно
var owned_note: PanelContainer = null   # сноска «на поле: ур. N» при наведении
var synergy_note: PanelContainer = null # под ней — синергии с этой картой (ShopManager.get_synergy_note)
var _synergy_label: Label
var _owned_label: Label = null

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

# Сноска поверх портрета: такой отряд / здание уже на поле — уровень (ShopManager.get_owned_note).
# Текст — в момент наведения: армия могла измениться, пока магазин открыт
func show_owned_note() -> void:
	var text := ShopManager.get_owned_note(card_data)
	_owned_label.text = text
	owned_note.visible = text != ""
	var syn := ShopManager.get_synergy_note(card_data)
	_synergy_label.text = syn
	synergy_note.visible = syn != ""

func _build_owned_note() -> void:
	var layer := Control.new()   # слой поверх содержимого карты, клики не ловит
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	var notes := VBoxContainer.new()   # «на поле» и синергии — друг под другом
	notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notes.add_theme_constant_override("separation", 2)
	layer.add_child(notes)
	notes.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	notes.offset_top = OWNED_NOTE_TOP
	owned_note = UITheme.make_panel("HudPanel", true)
	owned_note.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_DEEP, UITheme.GOLD, 1, 4, 4))
	owned_note.hide()
	notes.add_child(owned_note)
	synergy_note = UITheme.make_panel("HudPanel", true)
	synergy_note.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_DEEP, UITheme.GREEN, 1, 4, 4))
	synergy_note.hide()
	notes.add_child(synergy_note)
	_synergy_label = UITheme.make_label("", "SmallLabel")
	_synergy_label.add_theme_color_override("font_color", UITheme.GREEN)
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

# Редкость · тип, портрет, название
func _fill_header(data: CardData) -> void:
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
	card_title.theme_type_variation = "HeaderLabel"
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
	card_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Длинное описание прокручивается, а не растягивает карту — иначе она налезает на руку под магазином
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	$VBoxContainer.add_child(scroll)
	$VBoxContainer.move_child(scroll, card_desc.get_index())
	card_desc.reparent(scroll)
	card_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _make_portrait(data: CardData) -> Control:
	var frame = PanelContainer.new()
	frame.custom_minimum_size = Vector2(0, PORTRAIT_HEIGHT)
	frame.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BG_DEEP, UITheme.GOLD_DIM, 1, 4, 4))
	var tex = UITheme.card_portrait(data)
	if tex:
		var img = TextureRect.new()
		img.texture = tex
		img.modulate = UITheme.card_tint(data)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		frame.add_child(img)
	else:
		var l = UITheme.make_label(UITheme.TYPE_NAMES.get(data.card_type, "").to_upper(), "HeaderLabel")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		frame.add_child(l)
	return frame

func _cost() -> int:
	return 0 if free else ShopManager.get_price(card_data)

func set_hand_full(full: bool) -> void:
	hand_full = full
	_refresh_button()

func _refresh_button() -> void:
	var cost = _cost()
	if hand_full:
		buy_button.text = "Рука полна"
		buy_button.disabled = true
		return
	buy_button.text = "Взять бесплатно" if cost == 0 else "Купить · %d Req" % cost
	buy_button.disabled = not EconomyManager.can_afford(cost)

func _on_buy_pressed() -> void:
	emit_signal("purchase_requested", slot_index)

func _on_requisition_changed(_new_amount: int) -> void:
	if card_data:
		_refresh_button()
