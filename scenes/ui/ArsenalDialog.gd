class_name ArsenalDialog
extends ModalOverlay

# «Арсенал» главного меню — мета-прогрессия (MetaProgress): Слава, пассивки на все забеги (уровни
# за Славу), стартовые карты (открываются за Славу, выбираются при новом забеге), достижения —
# ордены и карты магазина с условием и прогрессом. После покупки окно перестраивается.

const ROW_GAP: float = 6.0
const LIST_HEIGHT: float = 420.0
const BUTTON_WIDTH: float = 190.0

var glory_label: Label = null

func setup() -> void:
	close_on_cancel = true
	build_frame(820.0)
	_rebuild()

func _rebuild() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	_focus_taken = false
	add_title("АРСЕНАЛ")
	glory_label = add_title("Слава: %d — за каждый забег, даже проигранный" % MetaProgress.get_glory(), "HeaderLabel")
	glory_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", ROW_GAP)
	scroll.add_child(list)

	_section(list, "ПАССИВКИ НА ВСЕ ЗАБЕГИ")
	for p in MetaProgress.PASSIVES:
		var lvl := int(MetaProgress.passive_levels.get(p["id"], 0))
		var max_lvl: int = p["costs"].size()
		var shown: float = maxi(lvl, 1) * float(p["value"])
		var text := "%s · ур. %d/%d\n%s" % [p["name"], lvl, max_lvl, p["desc"] % shown if "%" in p["desc"] else p["desc"]]
		var cost := MetaProgress.next_passive_cost(p["id"])
		_row(list, text, "Максимум" if cost < 0 else "Улучшить · %d" % cost,
			cost >= 0 and MetaProgress.get_glory() >= cost, _buy_passive.bind(p["id"]), "Passive_" + p["id"])

	_section(list, "СТАРТОВЫЕ КАРТЫ — одна в руку в начале забега")
	for s in MetaProgress.START_CARDS:
		var card := CardFactory.create(s["card"])
		var owned := MetaProgress.owned_start_cards.has(s["card"])
		_row(list, "%s\n%s" % [card.title, card.description], "Открыта" if owned else "Открыть · %d" % s["cost"],
			not owned and MetaProgress.get_glory() >= s["cost"], _buy_start_card.bind(s["card"]), "Start_" + s["card"])

	_section(list, "ДОСТИЖЕНИЯ — ордены")
	for id in MetaProgress.CHAPTER_UNLOCKS:
		var rule: Dictionary = MetaProgress.CHAPTER_UNLOCKS[id]
		_achievement(list, "Орден %s" % Chapters.get_chapter(id)["name"], rule, MetaProgress.is_chapter_unlocked(id))
	_section(list, "ДОСТИЖЕНИЯ — карты в магазине")
	for id in MetaProgress.CARD_UNLOCKS:
		var rule: Dictionary = MetaProgress.CARD_UNLOCKS[id]
		_achievement(list, CardFactory.create(id).title, rule, MetaProgress.is_card_unlocked(id))
	add_button("Закрыть", close)

func _section(list: VBoxContainer, text: String) -> void:
	var l := UITheme.make_label(text, "HeaderLabel")
	list.add_child(l)

func _row(list: VBoxContainer, text: String, button_text: String, enabled: bool, action: Callable, row_name: String) -> void:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 12)
	list.add_child(row)
	var l := UITheme.make_label(text, "SmallLabel")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var b := UITheme.make_button(button_text, "PrimaryButton" if enabled else "", action)
	b.name = "Buy"
	b.custom_minimum_size = Vector2(BUTTON_WIDTH, 40)
	b.disabled = not enabled
	row.add_child(b)

func _achievement(list: VBoxContainer, title: String, rule: Dictionary, done: bool) -> void:
	var l := UITheme.make_label(("✓ %s — открыто" % title) if done else ("%s — %s" % [title, MetaProgress.unlock_text(rule)]),
		"SmallLabel" if done else "DimLabel")
	if done:
		l.add_theme_color_override("font_color", UITheme.GREEN)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(l)

func _buy_passive(id: String) -> void:
	if MetaProgress.buy_passive(id):
		_rebuild()

func _buy_start_card(card_id: String) -> void:
	if MetaProgress.buy_start_card(card_id):
		_rebuild()
