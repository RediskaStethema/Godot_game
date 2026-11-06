class_name TestPanel
extends PanelContainer

# Панель тестового режима (решение пользователя 06.11.2026; RunManager.test_mode, только в сборке для
# разработки): слева на расстановке — все отряды, здания и прочие карты расы (CardFactory.test_cards), клик —
# карта в руку бесплатно; сколько улучшений у отрядов и зданий из панели (RunManager.test_level); волна и тип боя (сцена боя заново с
# этими врагами); очистить поле. Сама ничего не меняет — сигналы ловит BattleScene.

signal card_picked(card_id: String)
signal level_changed(level: int)
signal wave_changed(wave: int)
signal type_changed(battle_type: String)
signal clear_pressed

const WIDTH: float = 236.0
const MARGIN: float = 8.0
const TABS = [["squad", "Отряды"], ["building", "Здания"], ["other", "Прочее"]]
const TYPES = [RunMapNode.BATTLE, RunMapNode.MINIBOSS, RunMapNode.BOSS]
const TYPE_NAMES = {RunMapNode.BATTLE: "обычный", RunMapNode.MINIBOSS: "мини-босс", RunMapNode.BOSS: "босс"}

var _cards: Array[CardData] = []
var _list: VBoxContainer
var _tab_buttons := {}
var _level_buttons: Array[Button] = []
var _wave_label: Label
var _type_button: Button
var _tab: String = "squad"

func setup(faction: String) -> void:
	theme = UITheme.get_theme()
	theme_type_variation = "HudPanel"
	set_anchors_preset(Control.PRESET_LEFT_WIDE)
	offset_left = MARGIN
	offset_right = MARGIN + WIDTH
	offset_top = UITheme.HUD_HEIGHT + MARGIN
	offset_bottom = -(UITheme.BENCH_PEEK + MARGIN)
	_cards = CardFactory.test_cards(faction)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	col.add_child(UITheme.make_label("ТЕСТОВЫЙ РЕЖИМ", "HeaderLabel"))

	var tabs := HBoxContainer.new()
	col.add_child(tabs)
	for t in TABS:
		var b := UITheme.make_button(t[1], "", _show_tab.bind(t[0]))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tab_buttons[t[0]] = b
		tabs.add_child(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var level_row := HBoxContainer.new()
	col.add_child(level_row)
	level_row.add_child(UITheme.make_label("Улучш.", "SmallLabel"))
	level_row.tooltip_text = "Отряд из панели — ур.N (как N своих карт сверху), здание — ур. 1 + N (до 3)"
	level_row.mouse_filter = Control.MOUSE_FILTER_PASS
	for n in range(0, UnitFactory.MAX_SQUAD_LEVEL + 1):
		var b := UITheme.make_button(str(n), "", _set_level.bind(n))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_level_buttons.append(b)
		level_row.add_child(b)

	var wave_row := HBoxContainer.new()
	col.add_child(wave_row)
	wave_row.add_child(UITheme.make_button("−", "", _step_wave.bind(-1)))
	_wave_label = UITheme.make_label("", "SmallLabel")
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wave_row.add_child(_wave_label)
	wave_row.add_child(UITheme.make_button("+", "", _step_wave.bind(1)))
	_type_button = UITheme.make_button("", "", _cycle_type)
	col.add_child(_type_button)
	col.add_child(UITheme.make_button("Очистить поле", "", func(): clear_pressed.emit()))

	_refresh_controls()
	_show_tab("squad")

func _show_tab(tab: String) -> void:
	_tab = tab
	for key in _tab_buttons:
		_tab_buttons[key].set_pressed_no_signal(key == tab)
	for child in _list.get_children():
		child.queue_free()
	for card in _cards:
		if _tab_of(card) != tab:
			continue
		var b := UITheme.make_button(card.title, "", func(): card_picked.emit(card.id))
		b.name = "Card_" + card.id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.tooltip_text = "%s · %s\n%s" % [UITheme.RARITY_NAMES.get(card.rarity, card.rarity), card.title, card.description]
		b.add_theme_color_override("font_color", UITheme.rarity_color(card.rarity))
		_list.add_child(b)

static func _tab_of(card: CardData) -> String:
	return card.card_type if card.card_type in ["squad", "building"] else "other"

func _set_level(n: int) -> void:
	RunManager.test_level = n
	_refresh_controls()
	level_changed.emit(n)

func _step_wave(step: int) -> void:
	var wave := clampi(RunManager.test_wave + step, 1, RunManager.get_total_waves())
	if wave != RunManager.test_wave:
		wave_changed.emit(wave)

func _cycle_type() -> void:
	var i := TYPES.find(RunManager.test_battle_type)
	type_changed.emit(TYPES[(i + 1) % TYPES.size()])

func _refresh_controls() -> void:
	for i in _level_buttons.size():
		_level_buttons[i].set_pressed_no_signal(i == RunManager.test_level)
	_wave_label.text = "Волна %d" % RunManager.test_wave
	_type_button.text = "Тип: %s" % TYPE_NAMES.get(RunManager.test_battle_type, RunManager.test_battle_type)
