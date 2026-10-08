extends PanelContainer

@onready var card_title: Label = $VBoxContainer/UnitName
@onready var card_faction: Label = $VBoxContainer/UnitFaction
@onready var card_desc: Label = $VBoxContainer/UnitStats
@onready var buy_button: Button = $VBoxContainer/BuyButton

const CARD_SIZE = Vector2(230, 290)
const PORTRAIT_HEIGHT = 84.0

var slot_index: int = 0
var card_data: CardData = null
var hand_full: bool = false

signal purchase_requested(slot_index: int)

func setup(data: CardData, index: int) -> void:
	card_data = data
	slot_index = index

	custom_minimum_size = CARD_SIZE
	add_theme_stylebox_override("panel", UITheme.card_style(data.rarity))
	var box: VBoxContainer = $VBoxContainer
	box.add_theme_constant_override("separation", 6)

	# Строка редкости и типа
	card_faction.text = "%s · %s" % [
		UITheme.RARITY_NAMES.get(data.rarity, data.rarity),
		UITheme.TYPE_NAMES.get(data.card_type, data.card_type)]
	card_faction.theme_type_variation = "DimLabel"
	card_faction.add_theme_color_override("font_color", UITheme.rarity_color(data.rarity))

	# Портрет: кадр idle юнита, для зданий/улучшений — заглушка с названием типа
	var portrait = _make_portrait(data)
	box.add_child(portrait)
	box.move_child(portrait, 1)

	card_title.text = data.title
	card_title.theme_type_variation = "HeaderLabel"
	card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Характеристики + описание
	var text = data.description
	match data.card_type:
		"squad":
			var u = UnitFactory.create(data.unit_factory_id)
			text = "×%d   HP %d   УРН %d   ДАЛ %d\n%s" % [data.unit_count, u.hp, u.damage, u.attack_range, data.description]
		"upgrade":
			text = "%s\n(перетащите на свой отряд в бою)" % data.description
	card_desc.text = text
	card_desc.theme_type_variation = "SmallLabel"
	card_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL

	buy_button.custom_minimum_size = Vector2(0, 42)
	buy_button.pressed.connect(_on_buy_pressed)
	EconomyManager.requisition_changed.connect(_on_requisition_changed)
	_refresh_button()

	mouse_entered.connect(func(): add_theme_stylebox_override("panel", UITheme.card_style(data.rarity, true)))
	mouse_exited.connect(func(): add_theme_stylebox_override("panel", UITheme.card_style(data.rarity)))

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
		l.add_theme_color_override("font_color", UITheme.GOLD_DIM)
		frame.add_child(l)
	return frame

func _cost() -> int:
	return SynergyManager.get_discounted_cost(card_data)

func set_hand_full(full: bool) -> void:
	hand_full = full
	_refresh_button()

func _refresh_button() -> void:
	var cost = _cost()
	if hand_full:
		buy_button.text = "Рука полна"
		buy_button.disabled = true
		return
	buy_button.text = "Купить · %d Req" % cost
	buy_button.disabled = not EconomyManager.can_afford(cost)

func _on_buy_pressed() -> void:
	emit_signal("purchase_requested", slot_index)

func _on_requisition_changed(_new_amount: int) -> void:
	if card_data:
		_refresh_button()
