extends Control

@onready var round_label: Label = $TopBar/RoundLabel
@onready var requisition_label: Label = $TopBar/RequisitionLabel
@onready var shop_slots: HBoxContainer = $ShopPanel/ShopSlots
@onready var battle_button: Button = $BattleButton

const SHOP_SLOT_SCENE = preload("res://scenes/shop/ShopSlot.tscn")

# Вид (решение пользователя 12.11.2026, образец download.png): магазин — окно поверх поля боя (BattleScene кладёт
# его на свой слой, embedded): панели — полупрозрачная тьма в ржавой латунной рамке (ShopFrame), сквозь них видно
# поле; слева карты набора, справа продавец под вывеской «Обновить»; рука — веером снизу (ShopHand), «В БОЙ» —
# справа внизу, на нём стоит продавец; в шапке справа значки «Армия» / «Настройки» (пауза). Без BattleScene (тесты, запуск
# сцены напрямую) — свой непрозрачный фон и своя пауза.
const BODY_GAP: float = 8.0            # между шапкой, панелями и рукой
const SIDE_MARGIN: float = 12.0
const VENDOR_WIDTH: float = 260.0
const BATTLE_BUTTON_SIZE = Vector2(200, 52)
const TOP_ICON_SIZE: float = 40.0
const VENDOR_FEET_SINK: float = 3.0   # подошвы — на латунной кромке «В БОЙ»: она на 3 px ниже прямоугольника кнопки (решение
									  # пользователя 12.11.2026: «не наезжать на ассет кнопки, а стоять на нём»; было 4 при росте 300)
const VENDOR_FEET_X: float = 7.0      # ноги в кадре листа правее центра холста (x 258 из 480, ×0.4 на экране)
# «В БОЙ» объёмная (решение пользователя 12.11.2026): ButtonVolume — основание BUTTON_DEPTH px, тень, блик, нажатие
const BUTTON_DEPTH: float = 11.0
const BUTTON_LIFT: float = 4.0        # кнопка выше прежнего — под основание и тень хватает места над краем экрана
const SELL_FADE_TIME: float = 0.25     # проданная карта гаснет под огнём
const NO_MONEY_SIZE: float = 1.6       # вспышка «не хватает Req» (Vfx "no_money", кадр 64×32) у кнопки

# Магазин внутри BattleScene (окно поверх поля): «В БОЙ» — сигнал finished, сцену не меняет; пауза — сцены боя
var embedded: bool = false
signal finished

# «Рука» — карты, ещё не выложенные на поле: купленные сейчас +
# оставшиеся на скамейке с прошлого боя. Не больше BattleManager.MAX_HAND_SIZE.
var timeline: RunTimeline   # лента забега в шапке
var purchased_cards: Array[CardData] = []
# Выжившие юниты из прошлого боя
var surviving_units: Array[UnitData] = []
var hand: ShopHand = null
var message_label: Label = null
var citadel_label: Label = null
var reroll_button: Button = null   # обновить набор карт (ShopManager.try_reroll)
var catch_up_button: Button = null   # снова открыть выбор подкрепления
var catch_up_picker: CatchUpPicker = null
var army_button: Button = null
var settings_button: Button = null
var pause_menu: PauseMenu = null   # своя — только вне BattleScene
# Продавец справа (решение пользователя 11.11.2026): техножрец / тёмный механикус, реплики и жесты, вывеска «Обновить»
var vendor: ShopVendor = null
# «Армия» (решение пользователя 12.11.2026): магазин сворачивается — видно поле с армией, камера мышью работает;
# шапка остаётся, «Армия» ещё раз или «Вернуться в магазин» — магазин обратно. Без поля под магазином (сцена
# магазина отдельно) — окно ShopArmyDialog
# Уход магазина (решение пользователя 12.11.2026: «анимация исчезания магазина — кнопка обновить подтягивается
# вверх, прилавок карт уезжает влево и т. д.»): вывеска «Обновить» на цепях уходит под шапку, панель карт — влево
# за край, рука — вниз, продавец с «В БОЙ» — вправо, затемнение тает; шапка остаётся и по «В БОЙ» растворяется
# поверх шапки боя (BattleScene._on_shop_finished; уезжая вверх, двоилась с ней). По очереди через SLIDE_STAGGER,
# каждая часть за SLIDE_TIME с разгоном; возврат из «Армии» — обратно с торможением. Только вид, время дерева
const SLIDE_TIME: float = 0.4
const SLIDE_STAGGER: float = 0.06
const HUD_TEXT_FADE: float = 0.18     # надписи шапки магазина гаснут по «В БОЙ» (BattleScene проявляет свои после)
const SLIDE_MARGIN: float = 40.0   # за край экрана с запасом (тени, основание кнопки)
var collapsed: bool = false
var return_button: Button = null
var _shop_parts: Array[Control] = []   # что прячется при сворачивании
var _home_offsets: Dictionary = {}       # часть → [left, top, right, bottom] на месте (для выезда и возврата)
var _hud_bar: Control = null
var _collapse_tween: Tween
var _empty_army_warned: bool = false   # уход без армии — со второго нажатия

func _ready() -> void:
	# Магазин — главная сцена: при запуске игры он же первый шаг забега
	RunManager.ensure_started()
	AudioManager.play_music("shop")
	UITheme.apply_cursors()
	_build_layout()
	if not embedded:
		pause_menu = PauseMenu.new()
		add_child(pause_menu)
	EconomyManager.requisition_changed.connect(_update_requisition_label)
	ShopManager.shop_refreshed.connect(_populate_shop)
	battle_button.pressed.connect(_on_battle_pressed)
	reroll_button.pressed.connect(_on_reroll_pressed)
	reroll_button.set_meta(AudioManager.NO_CLICK, true)   # свой звук — reroll / no_money
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
	# Номер волны — на ленте забега (RunTimeline), в шапке — только сложность (решение пользователя 10.11.2026)
	round_label.text = Difficulty.level_name(RunManager.difficulty)
	# Каждый новый магазин — новый набор, цена обновления снова базовая
	ShopManager.open_shop()
	# Бесплатная карта 1-й волны — видна на кнопках «Взять бесплатно», в шапке не пишется (решение пользователя 10.11.2026)
	SaveManager.save_run()
	_refresh_catch_up_button()
	if ShopManager.catch_up_just_issued:
		_open_catch_up()
	vendor.react("greet")

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
		AudioManager.play("no_money")
		_show_message("Рука полна (%d/%d) — продайте лишние карты" % [purchased_cards.size(), BattleManager.MAX_HAND_SIZE])
		vendor.react("hand_full")
		return

	# Цену (бесплатная карта 1-й волны, скидка Epic) считает ShopManager
	var from_rect := _slot_face_rect(slot_index)   # до покупки: слот потом пересоберётся
	var card = ShopManager.try_purchase(slot_index)
	if not card:
		AudioManager.play("no_money")
		_show_message("Не хватает монет: карта стоит %s" % GameConstants.coins(ShopManager.get_price(ShopManager.current_offers[slot_index])))
		vendor.react("no_money")
		for slot in shop_slots.get_children():
			if slot.get("slot_index") == slot_index and slot.has_method("flash_no_money"):
				slot.flash_no_money()
		return
	AudioManager.play("buy")

	# Все типы карт идут в руку: отряды и здания выкладываются на тайл,
	# улучшения — бросаются на свой отряд в бою
	purchased_cards.append(card)
	_show_message("Куплено: %s" % card.display_title())
	vendor.react("buy")

	_refresh_hand()
	_fly_to_hand(card, from_rect)
	_populate_shop(ShopManager.current_offers)
	SaveManager.save_run()

# Лицо карты слота на экране (нет лица — весь слот); не найден — пусто
func _slot_face_rect(slot_index: int) -> Rect2:
	for slot in shop_slots.get_children():
		if slot.get("slot_index") == slot_index:
			var face: Control = slot.get("_face")
			return face.get_global_rect() if face else slot.get_global_rect()
	return Rect2()

# Купленная карта летит из слота в своё место в руке (CardFlight)
func _fly_to_hand(card: CardData, from_rect: Rect2) -> void:
	if from_rect.size == Vector2.ZERO:
		return
	var node := hand.card_node(card)
	if node:
		CardFlight.fly(self, card, from_rect, node)

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
	_show_message("Продано: %s (+%s)" % [card.display_title(), GameConstants.coins(refund)])
	vendor.react("sell")
	_refresh_catch_up_picker()
	# Карта сгорает на своём месте (лист card_sell) и гаснет; ряд руки сдвигается, когда догорела —
	# иначе под огнём сразу оказывалась соседняя карта
	var burning: Control = hand.card_node(card)
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
	if hand == null:
		return
	hand.setup(purchased_cards)

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
	UITheme.roll_number(requisition_label, amount, func(v: int): return str(v))   # монета и число, отматывается
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
		AudioManager.play("no_money")   # кнопка карты без щелчка (свой звук) — отказ тоже слышен
		_show_message("Рука полна (%d/%d) — продайте лишние карты" % [purchased_cards.size(), BattleManager.MAX_HAND_SIZE])
		vendor.react("hand_full")
		return
	var card = ShopManager.take_catch_up(index)
	if card == null:
		return
	purchased_cards.append(card)
	AudioManager.play("buy")
	_show_message("Подкрепление: %s" % card.display_title())
	vendor.react("catch_up")
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
		_show_message("Не хватает монет: обновление стоит %s" % GameConstants.coins(cost))
		vendor.react("no_money")
		Vfx.spawn_over(self, "no_money", reroll_button.get_global_rect(), NO_MONEY_SIZE)
		return
	AudioManager.play("reroll")
	_show_message("Набор обновлён (−%s), следующее обновление — %s" % [GameConstants.coins(cost), GameConstants.coins(ShopManager.get_reroll_cost())])
	vendor.react("reroll")
	SaveManager.save_run()

func _refresh_reroll_button() -> void:
	if reroll_button == null:
		return
	var cost = ShopManager.get_reroll_cost()
	reroll_button.text = "Обновить · %d" % cost
	reroll_button.disabled = not EconomyManager.can_afford(cost)
	reroll_button.tooltip_text = ("Не хватает %s" % GameConstants.coins(cost - EconomyManager.requisition)) 		if reroll_button.disabled else "Новый набор карт"

# -------------------------------------------------------
# ВЁРСТКА (ноды из .tscn переставляем кодом, .tscn вручную не трогаем)
# -------------------------------------------------------
func _build_layout() -> void:
	theme = UITheme.get_theme()
	$Background.hide()
	$TopBar.hide()
	var back: Control
	if embedded:   # поле под магазином чуть темнее — панели читаются; клики до поля не доходят (корень ловит мышь)
		var dim := ColorRect.new()
		dim.color = Palette.SHOP_SCREEN_DIM
		back = dim
	else:
		back = UITheme.make_background()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	move_child(back, 0)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_hud()
	_build_shop_panel()
	_build_hand_panel()   # последней: поднятая карта руки и её описание — поверх панелей
	_shop_parts = [back, $ShopFrame, $VendorStand, hand, battle_button]
	return_button = UITheme.make_button("Вернуться в магазин", "PrimaryButton", _toggle_field.bind(false))
	return_button.name = "ReturnButton"
	return_button.custom_minimum_size = BATTLE_BUTTON_SIZE + Vector2(80, 0)
	add_child(return_button)
	return_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, int(SIDE_MARGIN * 2))
	return_button.hide()

# Шапка: значок ордена / бога, сообщение, сложность, лента забега, монеты (значок и число), цитадель; справа —
# армия и настройки («Колода» убрана — решение пользователя 12.11.2026: рука и так видна веером)
func _build_hud() -> void:
	var hud := ShopFrame.hud_bar(self)   # без рамки, тёмная подложка ступенями (17.11.2026; была латунная кромка снизу)
	_hud_bar = hud
	var hud_row = HBoxContainer.new()
	hud_row.add_theme_constant_override("separation", 12)
	hud.add_child(hud_row)
	hud_row.add_child(Control.new())   # отступ слева
	var badge := UITheme.make_chapter_badge()   # бог / орден забега — первым слева
	if badge:
		hud_row.add_child(badge)
	message_label = UITheme.make_label("", "SmallLabel")
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # длинное — в две строки, не за край
	message_label.max_lines_visible = 2
	message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	message_label.custom_minimum_size.x = 120.0
	message_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	hud_row.add_child(message_label)
	hud_row.add_child(UITheme.icon_row("difficulty", str(RunManager.difficulty), round_label))   # сложность забега
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
	# Значки справа (образец): армия — свернуть магазин и посмотреть поле, настройки — пауза
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 6)
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	hud_row.add_child(icons)
	army_button = _make_top_icon(icons, "army", "Армия: свернуть магазин и посмотреть поле", _open_army)
	army_button.toggle_mode = embedded   # нажата — магазин свёрнут
	settings_button = _make_top_icon(icons, "gear", "Настройки и пауза (Esc)", _open_pause)
	hud_row.add_child(Control.new())   # отступ справа

func _make_top_icon(parent: Control, kind: String, tip: String, on_pressed: Callable) -> Button:
	var b := TopIcon.new(kind, tip, TOP_ICON_SIZE)
	b.name = kind.capitalize() + "Button"
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b

# Значок шапки кодом (пока нет арта — UI_NEEDED.txt): латунная кнопка в рамке, глиф армии / шестерни
class TopIcon extends Button:
	var kind := ""
	func _init(k: String, tip: String, side: float) -> void:
		kind = k
		tooltip_text = tip
		custom_minimum_size = Vector2(side, side)
		focus_mode = Control.FOCUS_NONE
		var normal := ShopFrame.style(Palette.SHOP_BAR_VEIL, 0.0)
		var hover := ShopFrame.style(Palette.SHOP_VEIL, 0.0)
		hover.border_color = Palette.SHOP_FRAME_LIGHT
		for st in ["normal", "focus", "disabled"]:
			add_theme_stylebox_override(st, normal)
		for st in ["hover", "pressed", "hover_pressed"]:
			add_theme_stylebox_override(st, hover)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var c: Color = Palette.SHOP_ICON_HOVER if is_hovered() else Palette.SHOP_ICON
		var dark: Color = Palette.SHOP_FRAME_DARK
		var m := (size / 2.0).round()
		match kind:
			"army":   # три фигуры: средняя впереди и крупнее
				for f in [[-8.0, 0.85], [8.0, 0.85], [0.0, 1.0]]:
					var x: float = m.x + f[0]
					var k: float = f[1]
					var top := m.y - 9.0 * k + (1.0 - k) * 6.0
					draw_circle(Vector2(x, top), 4.0 * k + 1.0, dark)
					draw_circle(Vector2(x, top), 4.0 * k, c)
					var body := Rect2(x - 6.0 * k, top + 5.0 * k, 12.0 * k, 10.0 * k)
					draw_rect(body.grow(1.0), dark)
					draw_rect(body, c)
			"gear":   # шестерня
				for i in 8:
					draw_set_transform(m, TAU * i / 8.0)
					draw_rect(Rect2(-2.5, -12.0, 5.0, 6.0), c)
				draw_set_transform(Vector2.ZERO)
				draw_circle(m, 8.5, c)
				draw_circle(m, 3.5, dark)

# Карты набора — в панели слева (рамка с тьмой, сквозь неё поле); продавец — в своей панели справа,
# «Обновить» — вывеска на цепях над ним (решение пользователя 11.11.2026)
func _build_shop_panel() -> void:
	var frame := ShopFrame.new(Palette.SHOP_VEIL, 10.0)
	frame.name = "ShopFrame"
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_top = UITheme.HUD_HEIGHT + BODY_GAP
	frame.offset_bottom = -(UITheme.BENCH_PEEK + BODY_GAP)
	frame.offset_left = SIDE_MARGIN
	frame.offset_right = -(VENDOR_WIDTH + SIDE_MARGIN + BODY_GAP)
	var shop_panel: VBoxContainer = $ShopPanel
	var title: Label = $ShopPanel/ShopTitle
	shop_panel.reparent(frame, false)
	shop_panel.add_theme_constant_override("separation", 8)
	shop_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	title.text = "РЕКВИЗИЦИЯ"
	title.theme_type_variation = "HeaderLabel"
	title.add_theme_color_override("font_color", Palette.SHOP_FRAME_LIGHT)
	# Заголовок магазина + кнопка подкрепления справа
	var header = HBoxContainer.new()
	shop_panel.add_child(header)
	shop_panel.move_child(header, title.get_index())
	title.reparent(header)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catch_up_button = UITheme.make_button("Подкрепление", "PrimaryButton", _open_catch_up)
	catch_up_button.custom_minimum_size = Vector2(200, 40)
	UITheme.set_button_icon(catch_up_button, "hud", "catch_up")
	header.add_child(catch_up_button)
	shop_slots.add_theme_constant_override("separation", 12)
	shop_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	shop_slots.size_flags_vertical = Control.SIZE_EXPAND_FILL   # карты тянутся по высоте панели — место описанию
	# Продавец — справа, без рамки (решение пользователя 12.11.2026): стоит на кнопке «В БОЙ»
	# (`Screenshot 2026-11-12 114118.png`) — ноги по центру кнопки на её верхней кромке; тени — ShopVendor.VendorFigure.
	# Узел — после $BattleButton в дереве: сапоги рисуются поверх кромки кнопки
	var stand := Control.new()
	stand.name = "VendorStand"
	stand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stand)
	stand.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	var button_center := -(SIDE_MARGIN + BATTLE_BUTTON_SIZE.x / 2.0)
	stand.offset_left = button_center - VENDOR_FEET_X - VENDOR_WIDTH / 2.0
	stand.offset_right = stand.offset_left + VENDOR_WIDTH
	stand.offset_top = frame.offset_top
	stand.offset_bottom = -(BATTLE_BUTTON_SIZE.y + _battle_pad()) + VENDOR_FEET_SINK + ShopVendor.FIGURE_BOTTOM_PAD
	vendor = ShopVendor.new()
	stand.add_child(vendor)
	vendor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reroll_button = Button.new()
	UITheme.set_coin_icon(reroll_button)   # «Обновить · 5» и монета
	vendor.setup(RunManager.player_faction, reroll_button)
	# Цепи вывески — от верхнего края экрана (шапка без рамки, 17.11.2026; были от латунной кромки шапки): верх продавца
	# стоит на HUD_HEIGHT + BODY_GAP
	vendor.ceiling_gap = UITheme.HUD_HEIGHT + BODY_GAP + 1.0

# Рука внизу веером (ShopHand) на всю ширину до «В БОЙ» справа (плашка «РУКА n/10» убрана — решение
# пользователя 12.11.2026, `Screenshot 2026-11-12 114738.png`; цена продажи — на кнопке поднятой карты)
func _build_hand_panel() -> void:
	battle_button.theme_type_variation = "PrimaryButton"
	battle_button.text = "В БОЙ"
	battle_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	var pad := _battle_pad()
	battle_button.offset_left = -(BATTLE_BUTTON_SIZE.x + SIDE_MARGIN)
	battle_button.offset_right = -SIDE_MARGIN
	battle_button.offset_top = -(BATTLE_BUTTON_SIZE.y + pad)
	battle_button.offset_bottom = -pad
	_build_battle_volume()
	hand = ShopHand.new()
	hand.name = "Hand"
	add_child(hand)
	hand.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hand.offset_top = -UITheme.BENCH_PEEK
	hand.offset_bottom = 0
	hand.offset_left = SIDE_MARGIN
	hand.offset_right = -(BATTLE_BUTTON_SIZE.x + SIDE_MARGIN + BODY_GAP)
	hand.sell_requested.connect(_sell_card)

# Низ «В БОЙ» над краем экрана (по центру полосы руки и выше на BUTTON_LIFT — под основание)
func _battle_pad() -> float:
	return (UITheme.BENCH_PEEK - BATTLE_BUTTON_SIZE.y) / 2.0 + BUTTON_LIFT

func _build_battle_volume() -> void:
	# объём — общий для кнопок (ButtonVolume): основание, тень, блик, нажатие; без подъёма при наведении —
	# на кнопке стоит продавец
	ButtonVolume.attach(battle_button, BUTTON_DEPTH, 0.0)

# -------------------------------------------------------
# ЗНАЧКИ ШАПКИ
# -------------------------------------------------------
func _open_army() -> void:
	if embedded:
		_toggle_field(army_button.button_pressed)
		return
	var d := ShopArmyDialog.new()
	add_child(d)
	d.setup()

# Свернуть магазин (on) — панели тают, корень пропускает мышь: колесо и правая кнопка — камера поля
# (BattleScene.CameraInput, _unhandled_input); развернуть — обратно
func _toggle_field(on: bool) -> void:
	if on == collapsed:
		return
	collapsed = on
	army_button.set_pressed_no_signal(on)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP
	return_button.visible = on
	if _collapse_tween and _collapse_tween.is_valid():
		_collapse_tween.kill()
	if not on:
		for part in _shop_parts:
			part.show()
	_collapse_tween = _slide_parts(on)
	if on:
		_collapse_tween.chain().tween_callback(func():
			for part in _shop_parts:
				part.hide())
		_show_message("Армия на поле: колесо — зум, правая кнопка — двигать")
	else:
		_show_message("")

# Уход магазина по «В БОЙ» поверх поля (BattleScene._on_shop_finished): всё разъезжается, шапку растворяет сцена.
# Возвращает, сколько секунд идёт — потом узел можно удалять
func play_exit() -> float:
	if _collapse_tween and _collapse_tween.is_valid():
		_collapse_tween.kill()
	for part in _shop_parts:
		part.show()
	_collapse_tween = _slide_parts(true)
	if _hud_bar:   # надписи шапки гаснут первыми — под ней проявится шапка боя (та же планка), без двоения
		for c in _hud_bar.get_children():
			if c is CanvasItem:
				_collapse_tween.tween_property(c, "modulate:a", 0.0, HUD_TEXT_FADE)
	return SLIDE_TIME + SLIDE_STAGGER * 3.0

# Части магазина выезжают за края (out) или возвращаются. Сдвиг — смещением offset_* от места
# (_home_offsets): якоря те же, размер окна во время «Армии» может меняться
func _slide_parts(out: bool) -> Tween:
	var vp := get_viewport_rect().size
	var frame: Control = $ShopFrame
	var stand: Control = $VendorStand
	var right_x := vp.x - minf(stand.position.x, battle_button.position.x) + SLIDE_MARGIN
	var moves := [   # [часть, сдвиг, очередь]
		[frame, Vector2(-(frame.position.x + frame.size.x + SLIDE_MARGIN), 0.0), 1],
		[hand, Vector2(0.0, vp.y - hand.position.y + SLIDE_MARGIN), 2],
		[stand, Vector2(right_x, 0.0), 3],
		[battle_button, Vector2(right_x, 0.0), 3],
	]
	var tw := create_tween().set_parallel(true)
	var ez := Tween.EASE_IN if out else Tween.EASE_OUT
	var order := func(i: int) -> float: return SLIDE_STAGGER * (i if out else 3 - i)
	# Вывеска подтягивается первой (и опускается последней)
	tw.tween_property(vendor, "sign_lift", vendor.sign_lift_max() if out else 0.0, SLIDE_TIME) 		.set_trans(Tween.TRANS_CUBIC).set_ease(ez).set_delay(order.call(0))
	for mv in moves:
		var part: Control = mv[0]
		var from := _slide_k(part)
		if from <= 0.0:   # на месте — запоминаем место (размер окна мог смениться с прошлого раза)
			_home_offsets[part] = [part.offset_left, part.offset_top, part.offset_right, part.offset_bottom]
		tw.tween_method(_set_slide.bind(part, mv[1]), from, 1.0 if out else 0.0, SLIDE_TIME) 			.set_trans(Tween.TRANS_CUBIC).set_ease(ez).set_delay(order.call(mv[2]))
	var back: Control = _shop_parts[0]
	tw.tween_property(back, "modulate:a", 0.0 if out else 1.0, SLIDE_TIME).set_delay(order.call(2))
	return tw

func _slide_k(part: Control) -> float:
	return part.get_meta("slide_k", 0.0)

func _set_slide(k: float, part: Control, shift: Vector2) -> void:
	if part == $VendorStand:   # вывеска на продавце — остаётся над своим местом, уходит только вверх
		vendor.sign_hold_x = -shift.x * k
	var h: Array = _home_offsets[part]
	part.set_meta("slide_k", k)
	part.offset_left = h[0] + shift.x * k
	part.offset_right = h[2] + shift.x * k
	part.offset_top = h[1] + shift.y * k
	part.offset_bottom = h[3] + shift.y * k

# Пауза — своя (магазин без BattleScene) или сцены боя (окно над полем)
func _open_pause() -> void:
	var pm = pause_menu if pause_menu else get_tree().current_scene.get("pause_menu")
	if pm and not pm.is_open():
		pm.open()

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
	if embedded:   # окно над полем: расстановку открывает BattleScene, сцена не меняется
		finished.emit()
		return
	RunManager.advance()
