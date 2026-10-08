extends PanelContainer

@onready var card_image: TextureRect = $VBoxContainer/CardImage
@onready var info_label: Label = $VBoxContainer/InfoLabel

const CARD_SIZE = Vector2(108, 140)

var card_data: CardData = null
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

# Сигнал — когда начали тащить карту
signal drag_started(card: CardData, screen_pos: Vector2)

func setup(data: CardData) -> void:
	card_data = data
	custom_minimum_size = CARD_SIZE
	add_theme_stylebox_override("panel", UITheme.card_style(data.rarity))
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	tooltip_text = data.description

	# Портрет юнита вместо огромной картинки 1029×309
	card_image.texture = UITheme.card_portrait(data)
	card_image.modulate = UITheme.card_tint(data)
	card_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Без портрета (здания, улучшения) картинка не занимает место
	card_image.custom_minimum_size = Vector2(0, 72 if card_image.texture else 8)
	card_image.mouse_filter = Control.MOUSE_FILTER_IGNORE

	info_label.theme_type_variation = "SmallLabel"
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Текст зависит от типа карты
	match data.card_type:
		"squad":
			info_label.text = "%s\n×%d" % [data.title, data.unit_count]
		"building":
			info_label.text = "%s\n\nЗдание:\nна пустой тайл" % data.title
		"upgrade":
			info_label.text = "%s\n\n%s\nна свой отряд" % [data.title, data.description]

	mouse_entered.connect(func(): add_theme_stylebox_override("panel", UITheme.card_style(data.rarity, true)))
	mouse_exited.connect(func(): add_theme_stylebox_override("panel", UITheme.card_style(data.rarity)))

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
