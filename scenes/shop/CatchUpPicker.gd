class_name CatchUpPicker
extends ModalOverlay

# Окно подкрепления в магазине: выбор одной Common карты бесплатно
# (ShopManager.catch_up_offers), один раз можно поменять набор. Только вид:
# выбор, смену и лимит руки обрабатывает ShopScene.

const SHOP_SLOT_SCENE = preload("res://scenes/shop/ShopSlot.tscn")

signal picked(index: int)
signal reroll_requested

var _slots: HBoxContainer
var _reroll_button: Button

func setup() -> void:
	build_frame(760.0)
	add_title("ПОДКРЕПЛЕНИЕ")
	add_title("Цитадель в опасности — выберите одну карту бесплатно", "DimLabel")
	_slots = HBoxContainer.new()
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots.add_theme_constant_override("separation", 18)
	content.add_child(_slots)
	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	content.add_child(buttons)
	_reroll_button = UITheme.make_button("", "", func(): emit_signal("reroll_requested"))
	_reroll_button.custom_minimum_size = Vector2(220, 46)
	buttons.add_child(_reroll_button)
	var later = UITheme.make_button("Позже", "", close)
	later.custom_minimum_size = Vector2(160, 46)
	ModalOverlay.focus_later(later)   # фокус в окне, не на кнопке магазина под ним
	buttons.add_child(later)

# Карты выбора и кнопка смены; hand_full — карты нельзя взять (рука полна)
func refresh(offers: Array, rerolls_left: int, hand_full: bool) -> void:
	for child in _slots.get_children():
		child.queue_free()
	for i in range(offers.size()):
		var slot = SHOP_SLOT_SCENE.instantiate()
		_slots.add_child(slot)
		slot.setup(offers[i], i, true)
		slot.set_hand_full(hand_full)
		slot.purchase_requested.connect(func(index): emit_signal("picked", index))
	_reroll_button.text = "Поменять набор · %d" % rerolls_left
	_reroll_button.disabled = rerolls_left <= 0
