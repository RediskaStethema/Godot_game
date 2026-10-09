extends Control

@onready var round_label: Label = $TopBar/RoundLabel
@onready var requisition_label: Label = $TopBar/RequisitionLabel
@onready var shop_slots: HBoxContainer = $ShopPanel/ShopSlots
@onready var battle_button: Button = $BattleButton
@onready var army_label: Label = $ArmyPanel/ArmyLabel

const SHOP_SLOT_SCENE = preload("res://scenes/shop/ShopSlot.tscn")

# Высоты нижних панелей магазина. Подобраны под минимальную высоту окна 648:
# HUD + заголовок + карта (ShopSlot.CARD_SIZE) + рука + нижняя панель
const BOTTOM_BAR_HEIGHT: float = 80.0
const HAND_PANEL_HEIGHT: float = 124.0
const HAND_CARD_SIZE = Vector2(118, 96)

# «Рука» — карты, ещё не выложенные на поле: купленные сейчас +
# оставшиеся на скамейке с прошлого боя. Не больше BattleManager.MAX_HAND_SIZE.
var purchased_cards: Array[CardData] = []
# Выжившие юниты из прошлого боя
var surviving_units: Array[UnitData] = []
var army_details: Label = null   # список отрядов-ветеранов под счётчиком армии
var hand_title: Label = null
var hand_row: HBoxContainer = null
var message_label: Label = null
var citadel_label: Label = null
var reroll_button: Button = null   # обновить набор карт (ShopManager.try_reroll)
var _empty_army_warned: bool = false   # уход без армии — со второго нажатия

func _ready() -> void:
	# Магазин — главная сцена: при запуске игры он же первый шаг забега
	RunManager.ensure_started()
	_build_layout()
	EconomyManager.requisition_changed.connect(_update_requisition_label)
	ShopManager.shop_refreshed.connect(_populate_shop)
	battle_button.pressed.connect(_on_battle_pressed)
	reroll_button.pressed.connect(_on_reroll_pressed)

	# Загружаем выживших
	for unit in BattleManager.player_units:
		surviving_units.append(unit)
	# Карты, не выложенные в прошлом бою, остаются в руке. Рука магазина — тот же
	# массив, что BattleManager.pending_cards: сохранение видит покупки сразу
	for card in BattleManager.pending_cards:
		purchased_cards.append(card)
	BattleManager.pending_cards = purchased_cards
	print("ShopScene: загружено выживших: %d, карт в руке: %d" % [surviving_units.size(), purchased_cards.size()])

	_update_requisition_label(EconomyManager.requisition)
	_update_army_label()
	_refresh_hand()
	round_label.text = "Волна %d/%d" % [mini(EconomyManager.round_number, RunManager.get_total_waves()),
		RunManager.get_total_waves()]
	# Каждый новый магазин — новый набор, цена обновления снова базовая
	ShopManager.open_shop()
	if ShopManager.free_cards_left > 0:
		_show_message("Первая волна: одна карта бесплатно")
	SaveManager.save_run()

func _populate_shop(offers: Array) -> void:
	for child in shop_slots.get_children():
		child.queue_free()
	for i in range(offers.size()):
		var slot = SHOP_SLOT_SCENE.instantiate()
		shop_slots.add_child(slot)
		slot.setup(offers[i], i)
		slot.set_hand_full(_is_hand_full())
		slot.purchase_requested.connect(_on_purchase_requested)
	_refresh_reroll_button()

func _on_purchase_requested(slot_index: int) -> void:
	if slot_index >= ShopManager.current_offers.size():
		return

	# Проверяем лимит руки ДО покупки — деньги не списываем вообще
	if _is_hand_full():
		_show_message("Рука полна (%d/%d) — продайте лишние карты" % [purchased_cards.size(), BattleManager.MAX_HAND_SIZE])
		return

	# Цену (бесплатная карта 1-й волны, скидка Epic) считает ShopManager
	var card = ShopManager.try_purchase(slot_index)
	if not card:
		return

	# Все типы карт идут в руку: отряды и здания выкладываются на тайл,
	# улучшения — бросаются на свой отряд в бою
	purchased_cards.append(card)
	_show_message("Куплено: %s" % card.title)

	_update_army_label()
	_refresh_hand()
	_populate_shop(ShopManager.current_offers)
	SaveManager.save_run()

# -------------------------------------------------------
# РУКА И ПРОДАЖА
# -------------------------------------------------------
func _is_hand_full() -> bool:
	return purchased_cards.size() >= BattleManager.MAX_HAND_SIZE

func _sell_card(card: CardData) -> void:
	if not purchased_cards.has(card):
		return
	purchased_cards.erase(card)
	var refund = EconomyManager.sell_card(card)
	_show_message("Продано: %s (+%d Req)" % [card.title, refund])
	_update_army_label()
	_refresh_hand()
	_populate_shop(ShopManager.current_offers)
	SaveManager.save_run()

func _refresh_hand() -> void:
	if hand_row == null:
		return
	for child in hand_row.get_children():
		child.queue_free()
	var n = purchased_cards.size()
	hand_title.text = "РУКА %d/%d" % [n, BattleManager.MAX_HAND_SIZE]
	hand_title.add_theme_color_override("font_color",
		UITheme.RED_BRIGHT if _is_hand_full() else UITheme.GOLD)
	if n == 0:
		var hint = UITheme.make_label("Пусто — купленные карты появятся здесь", "DimLabel")
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hand_row.add_child(hint)
		return
	for card in purchased_cards:
		hand_row.add_child(_make_hand_card(card))

func _make_hand_card(card: CardData) -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = HAND_CARD_SIZE
	panel.add_theme_stylebox_override("panel", UITheme.card_style(card.rarity))
	panel.tooltip_text = card.description
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	var title = UITheme.make_label(card.title, "SmallLabel")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(title)

	var info = "×%d" % card.unit_count if card.card_type == "squad" else UITheme.TYPE_NAMES.get(card.card_type, "")
	var info_label = UITheme.make_label(info, "DimLabel")
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(info_label)

	var sell = Button.new()
	sell.text = "Продать +%d" % EconomyManager.get_sell_price(card)
	sell.add_theme_font_size_override("font_size", 13)
	sell.pressed.connect(_sell_card.bind(card))
	col.add_child(sell)
	return panel

func _show_message(text: String) -> void:
	print("ShopScene: ", text)
	if message_label:
		message_label.text = text

# -------------------------------------------------------
# АРМИЯ
# -------------------------------------------------------
func _count_units() -> int:
	# Считаем юнитов: бойцы выживших отрядов + из карт отрядов в руке
	var count = 0
	for unit in surviving_units:
		count += unit.saved_hp.size()
	for card in purchased_cards:
		if card.card_type == "squad":
			count += card.unit_count
	return count

func _update_army_label() -> void:
	var count = _count_units()
	# Лимита армии нет — ограничена только рука (MAX_HAND_SIZE)
	army_label.text = "Армия: %d бойцов" % count
	army_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	if army_details:
		var parts: Array[String] = []
		for unit in surviving_units:
			var ups = " [%s]" % ", ".join(unit.applied_upgrades) if not unit.applied_upgrades.is_empty() else ""
			var lvl = " ур.%d" % unit.squad_level if unit.squad_level > 0 else ""
			parts.append("%s ×%d%s%s" % [unit.unit_name, unit.saved_hp.size(), lvl, ups])
		army_details.text = ("Ветераны: " + "   ·   ".join(parts)) if not parts.is_empty() \
			else "Ветеранов нет — купите отряды и выложите их в бою"

func _update_requisition_label(amount: int) -> void:
	requisition_label.text = "%d Req" % amount
	_refresh_reroll_button()

# -------------------------------------------------------
# ОБНОВЛЕНИЕ НАБОРА
# -------------------------------------------------------
func _on_reroll_pressed() -> void:
	var cost = ShopManager.get_reroll_cost()
	if not ShopManager.try_reroll():
		_show_message("Не хватает Requisition: обновление стоит %d" % cost)
		return
	_show_message("Набор обновлён (−%d Req), следующее обновление — %d Req" % [cost, ShopManager.get_reroll_cost()])
	SaveManager.save_run()

func _refresh_reroll_button() -> void:
	if reroll_button == null:
		return
	var cost = ShopManager.get_reroll_cost()
	reroll_button.text = "Обновить · %d Req" % cost
	reroll_button.disabled = not EconomyManager.can_afford(cost)

# -------------------------------------------------------
# ВЁРСТКА (ноды из .tscn переставляем кодом, .tscn вручную не трогаем)
# -------------------------------------------------------
func _build_layout() -> void:
	theme = UITheme.get_theme()
	$Background.hide()
	var bg = UITheme.make_background()
	add_child(bg)
	move_child(bg, 0)

	# --- HUD сверху ---
	var hud = PanelContainer.new()
	hud.theme_type_variation = "HudPanel"
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.offset_bottom = UITheme.HUD_HEIGHT
	add_child(hud)
	var hud_row = HBoxContainer.new()
	hud_row.add_theme_constant_override("separation", 24)
	hud.add_child(hud_row)
	hud_row.add_child(UITheme.make_label("WH40KINGS", "TitleLabel"))
	message_label = UITheme.make_label("", "SmallLabel")
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	hud_row.add_child(message_label)
	round_label.reparent(hud_row)
	round_label.theme_type_variation = "HeaderLabel"
	requisition_label.reparent(hud_row)
	requisition_label.theme_type_variation = "ValueLabel"
	citadel_label = UITheme.make_label("Цитадель %d/%d" % [ceili(BattleManager.citadel_hp), int(BattleManager.CITADEL_MAX_HP)], "ValueLabel")
	if BattleManager.citadel_hp <= BattleManager.CITADEL_MAX_HP / 4:
		citadel_label.add_theme_color_override("font_color", UITheme.RED_BRIGHT)
	hud_row.add_child(citadel_label)
	for l in [round_label, requisition_label, citadel_label]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	$TopBar.hide()

	# --- Магазин по центру ---
	var shop_panel: VBoxContainer = $ShopPanel
	shop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_panel.offset_top = UITheme.HUD_HEIGHT + 10
	shop_panel.offset_bottom = -(BOTTOM_BAR_HEIGHT + HAND_PANEL_HEIGHT + 8)
	shop_panel.offset_left = 24
	shop_panel.offset_right = -24
	shop_panel.add_theme_constant_override("separation", 8)
	var title: Label = $ShopPanel/ShopTitle
	title.text = "РЕКВИЗИЦИЯ"
	title.theme_type_variation = "HeaderLabel"
	# Заголовок магазина + кнопка обновления набора справа
	var header = HBoxContainer.new()
	shop_panel.add_child(header)
	shop_panel.move_child(header, title.get_index())
	title.reparent(header)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll_button = Button.new()
	reroll_button.custom_minimum_size = Vector2(200, 40)
	header.add_child(reroll_button)
	shop_slots.add_theme_constant_override("separation", 18)
	shop_slots.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# --- Рука: карты с кнопкой продажи ---
	var hand_panel = PanelContainer.new()
	hand_panel.theme_type_variation = "HudPanel"
	hand_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hand_panel.offset_top = -(BOTTOM_BAR_HEIGHT + HAND_PANEL_HEIGHT)
	hand_panel.offset_bottom = -BOTTOM_BAR_HEIGHT
	add_child(hand_panel)
	var hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 14)
	hand_panel.add_child(hand_box)
	var hand_info = VBoxContainer.new()
	hand_info.custom_minimum_size = Vector2(130, 0)
	hand_info.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_box.add_child(hand_info)
	hand_title = UITheme.make_label("РУКА", "HeaderLabel")
	hand_info.add_child(hand_title)
	var sell_hint = UITheme.make_label("Продажа: 1/3 цены", "DimLabel")
	hand_info.add_child(sell_hint)
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_box.add_child(scroll)
	hand_row = HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", 8)
	hand_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(hand_row)

	# --- Нижняя панель: армия + кнопка боя ---
	var bottom = PanelContainer.new()
	bottom.theme_type_variation = "HudPanel"
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -BOTTOM_BAR_HEIGHT
	add_child(bottom)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	bottom.add_child(row)
	var army_col = VBoxContainer.new()
	army_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	army_col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(army_col)
	army_label.reparent(army_col)
	army_label.theme_type_variation = "ValueLabel"
	army_details = UITheme.make_label("", "DimLabel")
	army_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	army_col.add_child(army_details)
	$ArmyPanel.hide()
	battle_button.reparent(row)
	battle_button.theme_type_variation = "PrimaryButton"
	battle_button.text = "В БОЙ"
	battle_button.custom_minimum_size = Vector2(220, 60)

# Уход из магазина — сразу в бой волны: шаг магазина пройден, следующий шаг
# цепочки — бой. Без армии — предупреждение, со второго нажатия уходим всё
# равно (иначе без денег и карт можно застрять в магазине).
func _on_battle_pressed() -> void:
	if _count_units() == 0 and surviving_units.is_empty() and not _empty_army_warned:
		_empty_army_warned = true
		_show_message("Армии нет — купите отряд или нажмите ещё раз, чтобы уйти без неё")
		return
	# Передаём всё в BattleManager: рука → скамейка следующего боя
	BattleManager.pending_cards = purchased_cards
	BattleManager.player_units.clear()
	for unit in surviving_units:
		BattleManager.player_units.append(unit)
	if RunManager.is_shop_node_active():
		RunManager.complete_current_node()
	RunManager.advance()
