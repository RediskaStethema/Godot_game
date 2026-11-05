extends Control

@onready var round_label: Label = $TopBar/RoundLabel
@onready var requisition_label: Label = $TopBar/RequisitionLabel
@onready var shop_slots: HBoxContainer = $ShopPanel/ShopSlots
@onready var battle_button: Button = $BattleButton

const SHOP_SLOT_SCENE = preload("res://scenes/shop/ShopSlot.tscn")

# Высота панели руки внизу (с кнопкой «В БОЙ»). Подобрана под минимальную высоту окна 648:
# HUD + заголовок + карта (ShopSlot.CARD_SIZE) + рука
const HAND_PANEL_HEIGHT: float = 124.0
const HAND_CARD_SIZE = Vector2(118, 96)
# Карты руки сужаются, чтобы полная рука (MAX_HAND_SIZE) помещалась в панель без прокрутки:
# при 10 картах в окне 1152 px — ~90 px; уже этого — прокрутка
const HAND_CARD_MIN_WIDTH: float = 84.0
const HAND_CARD_GAP: int = 8
const HAND_TITLE_FONT: int = 13        # название карты руки (кегль прежней разметки, через UITheme.ui_px)
const HAND_TITLE_FONT_MIN: int = 8
const HAND_PORTRAIT_ALPHA: float = 0.22   # портрет фоном карты руки — под текстом, не мешает читать
const HAND_CARD_PAD: float = 5.0       # поля карты руки по бокам (у card_style — 10)
const HAND_BUTTON_PAD: float = 4.0     # поля кнопки «Продать» по бокам
const NO_MONEY_SIZE: float = 1.6       # вспышка «не хватает Req» (Vfx "no_money", кадр 64×32) у кнопки
const SELL_FADE_TIME: float = 0.25     # проданная карта гаснет под огнём

# «Рука» — карты, ещё не выложенные на поле: купленные сейчас +
# оставшиеся на скамейке с прошлого боя. Не больше BattleManager.MAX_HAND_SIZE.
var timeline: RunTimeline   # лента забега в шапке
var purchased_cards: Array[CardData] = []
# Выжившие юниты из прошлого боя
var surviving_units: Array[UnitData] = []
var hand_title: Label = null
var hand_row: HBoxContainer = null
var hand_scroll: ScrollContainer = null
var message_label: Label = null
var citadel_label: Label = null
var reroll_button: Button = null   # обновить набор карт (ShopManager.try_reroll)
var catch_up_button: Button = null   # снова открыть выбор подкрепления
var catch_up_picker: CatchUpPicker = null
var _empty_army_warned: bool = false   # уход без армии — со второго нажатия

func _ready() -> void:
	# Магазин — главная сцена: при запуске игры он же первый шаг забега
	RunManager.ensure_started()
	AudioManager.play_music("shop")
	_build_layout()
	add_child(PauseMenu.new())
	EconomyManager.requisition_changed.connect(_update_requisition_label)
	ShopManager.shop_refreshed.connect(_populate_shop)
	battle_button.pressed.connect(_on_battle_pressed)
	reroll_button.pressed.connect(_on_reroll_pressed)
	# Кнопка неактивна (не хватает Req) — клик всё равно отвечает: вспышка у кнопки и сообщение
	reroll_button.gui_input.connect(func(e: InputEvent):
		if reroll_button.disabled and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_on_reroll_pressed())

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
	_refresh_hand()
	round_label.text = "Волна %d/%d · %s" % [mini(EconomyManager.round_number, RunManager.get_total_waves()),
		RunManager.get_total_waves(), Difficulty.level_name(RunManager.difficulty)]
	# Каждый новый магазин — новый набор, цена обновления снова базовая
	ShopManager.open_shop()
	if ShopManager.free_cards_left > 0:
		_show_message("Первая волна: одна карта бесплатно")
	SaveManager.save_run()
	_refresh_catch_up_button()
	if ShopManager.catch_up_just_issued:
		_open_catch_up()

# Новый набор после обновления — карты переворачиваются из рубашки по очереди (ShopSlot.reveal)
const REVEAL_DELAY: float = 0.25
const REVEAL_STAGGER: float = 0.12
var _reveal_next: bool = false

func _populate_shop(offers: Array) -> void:
	for child in shop_slots.get_children():
		child.queue_free()
	for i in range(offers.size()):
		var slot = SHOP_SLOT_SCENE.instantiate()
		shop_slots.add_child(slot)
		slot.setup(offers[i], i)
		slot.set_hand_full(_is_hand_full())
		slot.purchase_requested.connect(_on_purchase_requested)
		if _reveal_next:
			slot.reveal(REVEAL_DELAY + REVEAL_STAGGER * i)
	_reveal_next = false
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
		AudioManager.play("no_money")
		_show_message("Не хватает Requisition: карта стоит %d" % ShopManager.get_price(ShopManager.current_offers[slot_index]))
		for slot in shop_slots.get_children():
			if slot.get("slot_index") == slot_index and slot.has_method("flash_no_money"):
				slot.flash_no_money()
		return
	AudioManager.play("buy")

	# Все типы карт идут в руку: отряды и здания выкладываются на тайл,
	# улучшения — бросаются на свой отряд в бою
	purchased_cards.append(card)
	_show_message("Куплено: %s" % card.title)

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
	AudioManager.play("sell")
	_show_message("Продано: %s (+%d Req)" % [card.title, refund])
	_refresh_catch_up_picker()
	# Карта сгорает на своём месте (лист card_sell) и гаснет; ряд руки сдвигается, когда догорела —
	# иначе под огнём сразу оказывалась соседняя карта
	var burning: Control = null
	for node in hand_row.get_children():
		if node.get_meta("card", null) == card:
			burning = node
	if burning:
		burning.propagate_call("set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])
		Vfx.spawn_over(self, "card_sell", burning.get_global_rect())
		var tw := burning.create_tween()
		tw.tween_property(burning, "modulate:a", 0.0, SELL_FADE_TIME)
		tw.tween_callback(_refresh_hand)
	else:
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
	_fit_hand_cards()

# Ширина карт руки — под ширину панели (окно и число карт), не уже HAND_CARD_MIN_WIDTH
func _fit_hand_cards() -> void:
	if hand_row == null or hand_scroll == null:
		return
	var cards = hand_row.get_children().filter(func(c): return c is PanelContainer and not c.is_queued_for_deletion())
	if cards.is_empty():
		return
	var n := cards.size()
	var w := clampf((hand_scroll.size.x - HAND_CARD_GAP * (n - 1)) / n, HAND_CARD_MIN_WIDTH, HAND_CARD_SIZE.x)
	for c in cards:
		c.custom_minimum_size.x = floorf(w)
		var title: Label = c.find_child("HandTitle", true, false)
		if title:
			title.add_theme_font_size_override("font_size", UITheme.fit_font_size(UITheme.ui_font(), title.text,
				floorf(w) - HAND_CARD_PAD * 2.0 - 2.0, UITheme.ui_px(HAND_TITLE_FONT), UITheme.ui_px(HAND_TITLE_FONT_MIN)))

func _make_hand_card(card: CardData) -> Control:
	var panel = PanelContainer.new()
	panel.set_meta("card", card)   # продажа — эффект на месте этой карты
	panel.custom_minimum_size = HAND_CARD_SIZE
	var style := UITheme.card_style(card.rarity)
	style.content_margin_left = HAND_CARD_PAD
	style.content_margin_right = HAND_CARD_PAD
	panel.add_theme_stylebox_override("panel", style)
	panel.tooltip_text = card.description
	panel.clip_contents = true   # иллюстрация по большей стороне — лишнее за краем карты
	# Иллюстрация карты (или портрет) — фоном карты, приглушена: высота карт та же, рука помещается в окно 648
	var art := UITheme.make_card_backdrop(card)
	var tex = null if art else UITheme.card_portrait(card)
	if art:
		panel.add_child(art)
	if tex:
		var bg = TextureRect.new()
		bg.texture = tex
		bg.modulate = UITheme.card_tint(card) * Color(1, 1, 1, HAND_PORTRAIT_ALPHA)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(bg)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	# Название — в одну строку шрифтом названий карт, кегль — под ширину карты (_fit_hand_cards; решение
	# пользователя 24.10.2026: «Devastator Squad» переносилось на две строки поверх арта)
	var title = UITheme.make_label(card.title, "SmallLabel")
	title.name = "HandTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_override("font", UITheme.ui_font())
	title.add_theme_font_size_override("font_size", UITheme.ui_px(HAND_TITLE_FONT))
	title.add_theme_constant_override("outline_size", 4)   # поверх иллюстрации
	col.add_child(title)

	var info = "×%d" % card.unit_count if card.card_type == "squad" else UITheme.TYPE_NAMES.get(card.card_type, "")
	var info_label = UITheme.make_label(info, "DimLabel")
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_constant_override("outline_size", 4)
	col.add_child(info_label)

	var sell = Button.new()
	sell.text = "Продать +%d" % EconomyManager.get_sell_price(card)
	sell.add_theme_font_size_override("font_size", UITheme.ui_px(12))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb = UITheme.get_theme().get_stylebox(state, "Button")   # карта ещё не в дереве — тема напрямую
		if sb:
			sb = sb.duplicate()
			sb.content_margin_left = HAND_BUTTON_PAD
			sb.content_margin_right = HAND_BUTTON_PAD
			sell.add_theme_stylebox_override(state, sb)
	sell.pressed.connect(_sell_card.bind(card))
	col.add_child(sell)
	return panel

func _show_message(text: String) -> void:
	print("ShopScene: ", text)
	if message_label:
		message_label.text = text

# Бойцов в армии: выжившие + карты отрядов в руке (уход без армии — со второго нажатия)
func _count_units() -> int:
	# Считаем юнитов: бойцы выживших отрядов + из карт отрядов в руке
	var count = 0
	for unit in surviving_units:
		count += unit.saved_hp.size()
	for card in purchased_cards:
		if card.card_type == "squad":
			count += card.unit_count
	return count

func _update_requisition_label(amount: int) -> void:
	requisition_label.text = "%d Req" % amount
	_refresh_reroll_button()

# -------------------------------------------------------
# ПОДКРЕПЛЕНИЕ (ShopManager.catch_up_offers)
# -------------------------------------------------------
func _open_catch_up() -> void:
	if catch_up_picker or not ShopManager.has_catch_up():
		return
	catch_up_picker = CatchUpPicker.new()
	add_child(catch_up_picker)
	catch_up_picker.setup()
	catch_up_picker.picked.connect(_on_catch_up_picked)
	catch_up_picker.reroll_requested.connect(_on_catch_up_reroll)
	catch_up_picker.tree_exited.connect(func(): catch_up_picker = null)
	_refresh_catch_up_picker()

func _refresh_catch_up_picker() -> void:
	if catch_up_picker:
		catch_up_picker.refresh(ShopManager.catch_up_offers, ShopManager.catch_up_rerolls_left, _is_hand_full())

func _refresh_catch_up_button() -> void:
	if catch_up_button:
		catch_up_button.visible = ShopManager.has_catch_up()

func _on_catch_up_picked(index: int) -> void:
	if _is_hand_full():
		_show_message("Рука полна (%d/%d) — продайте лишние карты" % [purchased_cards.size(), BattleManager.MAX_HAND_SIZE])
		return
	var card = ShopManager.take_catch_up(index)
	if card == null:
		return
	purchased_cards.append(card)
	_show_message("Подкрепление: %s" % card.title)
	if catch_up_picker:
		catch_up_picker.close()
	_refresh_catch_up_button()
	_refresh_hand()
	_populate_shop(ShopManager.current_offers)
	SaveManager.save_run()

func _on_catch_up_reroll() -> void:
	if ShopManager.try_reroll_catch_up():
		_refresh_catch_up_picker()
		SaveManager.save_run()

# -------------------------------------------------------
# ОБНОВЛЕНИЕ НАБОРА
# -------------------------------------------------------
func _on_reroll_pressed() -> void:
	var cost = ShopManager.get_reroll_cost()
	_reveal_next = true
	if not ShopManager.try_reroll():
		_reveal_next = false
		AudioManager.play("no_money")
		_show_message("Не хватает Requisition: обновление стоит %d" % cost)
		Vfx.spawn_over(self, "no_money", reroll_button.get_global_rect(), NO_MONEY_SIZE)
		return
	AudioManager.play("reroll")
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
	_build_hud()
	_build_shop_panel()
	_build_hand_panel()

# Шапка: название, сообщение, волна, Req, цитадель
func _build_hud() -> void:
	var hud = PanelContainer.new()
	hud.theme_type_variation = "HudPanel"
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.offset_bottom = UITheme.HUD_HEIGHT
	add_child(hud)
	var hud_row = HBoxContainer.new()
	hud_row.add_theme_constant_override("separation", 16)
	hud.add_child(hud_row)
	var badge := UITheme.make_chapter_badge()   # бог / орден забега — первым слева
	if badge:
		hud_row.add_child(badge)
	hud_row.add_child(UITheme.make_label("WH40KINGS", "TitleLabel"))
	message_label = UITheme.make_label("", "SmallLabel")
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	hud_row.add_child(message_label)
	hud_row.add_child(UITheme.icon_row("hud", "wave", round_label))
	round_label.theme_type_variation = "HeaderLabel"
	timeline = RunTimeline.new()   # 15 волн: мини-боссы, босс, события, ближайшая волна
	hud_row.add_child(timeline)
	hud_row.add_child(UITheme.icon_row("hud", "requisition", requisition_label))
	requisition_label.theme_type_variation = "ValueLabel"
	citadel_label = UITheme.make_label("%d/%d" % [ceili(BattleManager.citadel_hp), int(BattleManager.CITADEL_MAX_HP)], "ValueLabel")
	if BattleManager.citadel_hp <= BattleManager.CITADEL_MAX_HP / 4:
		citadel_label.add_theme_color_override("font_color", UITheme.RED_BRIGHT)
	var citadel_row := UITheme.icon_row("hud", "citadel_hp", citadel_label)   # «Цитадель» — значком
	citadel_row.tooltip_text = "Цитадель"
	citadel_row.mouse_filter = Control.MOUSE_FILTER_PASS
	hud_row.add_child(citadel_row)
	for l in [round_label, requisition_label, citadel_label]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	$TopBar.hide()

# Магазин по центру: заголовок + кнопка обновления набора, слоты карт
func _build_shop_panel() -> void:
	var shop_panel: VBoxContainer = $ShopPanel
	shop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_panel.offset_top = UITheme.HUD_HEIGHT + 10
	shop_panel.offset_bottom = -(HAND_PANEL_HEIGHT + 8)
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
	catch_up_button = UITheme.make_button("Подкрепление", "PrimaryButton", _open_catch_up)
	catch_up_button.custom_minimum_size = Vector2(200, 40)
	header.add_child(catch_up_button)
	reroll_button = Button.new()
	reroll_button.custom_minimum_size = Vector2(200, 40)
	header.add_child(reroll_button)
	shop_slots.add_theme_constant_override("separation", 18)
	shop_slots.size_flags_vertical = Control.SIZE_EXPAND_FILL

# Рука внизу: заголовок и кнопка «В БОЙ» слева, карты с кнопкой продажи
func _build_hand_panel() -> void:
	var hand_panel = PanelContainer.new()
	hand_panel.theme_type_variation = "HudPanel"
	hand_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hand_panel.offset_top = -HAND_PANEL_HEIGHT
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
	battle_button.reparent(hand_info)
	battle_button.theme_type_variation = "PrimaryButton"
	battle_button.text = "В БОЙ"
	battle_button.custom_minimum_size = Vector2(0, 52)
	hand_scroll = ScrollContainer.new()
	hand_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_scroll.resized.connect(_fit_hand_cards)
	hand_box.add_child(hand_scroll)
	hand_row = HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", HAND_CARD_GAP)
	hand_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hand_scroll.add_child(hand_row)

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
