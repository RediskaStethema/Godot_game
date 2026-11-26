extends Control

# Выбор карты после волны — шаг цепочки забега (RunMapNode.PICK, решение пользователя 16.11.2026: вместо магазина
# после каждой волны, магазин — только перед 1-й волной и после событий 4 / 8 / 12 / 14).
# 4 карты рубашкой вверх → игрок открывает 2 → из двух открытых берёт 1 (бесплатно); остальные сгорают.
# Набор, открытые и итог — в ShopManager (pick_*), сохраняются: выход и «Продолжить» не дают перебросить.
# Рука полна — взятая карта продаётся (EconomyManager.sell_card). UI собирается кодом, стили — UITheme.
# 17.11.2026 (решение пользователя): окно поверх поля следующего боя, как магазин (BattleScene открывает его на шаге PICK,
# `embedded`); карты — квадратом 2×2, выкладываются с анимацией и переворачиваются; невыбранные (в т.ч. неоткрытые) сгорают.
# 17.11.2026 (решение пользователя): перед волной 1 магазина нет — стартовый выбор (RunMapNode.START_PICK): 6 карт рубашкой вверх
# (3×2), клик по рубашке — карта открывается и сразу в руку, так 3 раза вслепую; остальные 3 сгорают.

signal finished   # «ДАЛЕЕ» в окне над полем: BattleScene переводит поле к расстановке

const CARD_WIDTH: float = 150.0
const COLUMN_WIDTH: float = 700.0          # колонка «подсказка · карты · ДАЛЕЕ» — постоянной ширины
const EDGE_HEIGHT: float = 48.0           # подсказка сверху и кнопка снизу — одной высоты
const INFO_WIDTH: float = 250.0           # окно описания у карты под курсором
const INFO_GAP: float = 14.0
const HOVER_BRIGHT: Color = Color(1.14, 1.12, 1.08, 1.0)
const FLIP_TIME: float = 0.55
const FLIP_LIFT: float = 0.12            # карта в перевороте приподнимается (рост)
const FLIP_TILT: float = 0.07            # и чуть кренится
const DIM: Color = Color(0.0, 0.0, 0.0, 0.78)   # поле под выбором сильно затемнено
const DEAL_TIME: float = 0.42             # выкладка одной карты
const DEAL_STAGGER: float = 0.13
const DEAL_FROM_SCALE: float = 0.45
const BURN_TIME: float = 0.55
const BURN_STAGGER: float = 0.09
const BURN_TINT: Color = Color(1.9, 0.75, 0.3, 1.0)

var embedded: bool = false
var hold_deal: bool = false   # обучение: карты не выкладывать до deal_now()

var _grid: GridContainer
var _hint: Label
var _next_button: Button
var _req_label: Label
var _slots: Array[Control] = []        # окно карты i (лицо + рубашка + слой клика)
var _holders: Array[Control] = []      # то же (имя прежнее)
var _hits: Array[Control] = []         # прозрачный слой поверх карты: клик (открыть / взять) и наведение
var _info: PanelContainer              # описание карты под курсором
var _info_title: Label
var _info_kind: Label
var _info_desc: Label
var _faces: Array[Control] = []
var _glared: Dictionary = {}   # слоты, где подсветка редкости уже навешена
var _face_ids: Array[String] = []   # id карты на лице каждой рубашки (см. _sync_faces)
var _backs: Array[TextureRect] = []    # рубашка поверх лица
var _flipping: Dictionary = {}         # рубашки, которые сейчас переворачиваются (_refresh их не прячет скачком)
var _dealing: bool = false             # идёт выкладка — клики по рубашкам не принимаются
var _burned: bool = false
var _start: bool = false               # стартовый выбор забега (3 из 6 вслепую), а не обычный (открыть 2, взять 1)

func _ready() -> void:
	if not embedded:
		AudioManager.play_music("shop")
	theme = UITheme.get_theme()
	UITheme.apply_cursors()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if embedded:
		mouse_filter = Control.MOUSE_FILTER_STOP   # клики до поля не доходят
	RunManager.ensure_started()
	ShopManager.open_pick()
	_build()
	if not embedded:
		add_child(PauseMenu.new())
	EconomyManager.requisition_changed.connect(_on_resources_changed)
	_refresh_hud()
	SaveManager.save_run()   # вылет на выборе — «Продолжить» вернёт сюда же с тем же набором
	_refresh()
	if hold_deal:   # обучение: пока наставники говорят о поле (цитадель), карты не показываем — deal_now() выложит их
		_dealing = true
		modulate.a = 0.0   # окно целиком (и затемнение поля под ним) — до deal_now()
		for c in _slots:
			c.modulate.a = 0.0
	else:
		_deal_in()

# Обучение: карты ещё не выложены (hold_deal) — выложить сейчас
func deal_now() -> void:
	if hold_deal:
		hold_deal = false
		create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
		_deal_in()

func _build() -> void:
	var back: Control
	if embedded:   # поле под окном чуть темнее — карты читаются
		var dim := ColorRect.new()
		dim.color = DIM
		back = dim
	else:
		back = UITheme.make_background()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hud := ShopFrame.hud_bar(self, false)   # без рамки (решение пользователя 17.11.2026): орден, сложность, монеты, лента волн
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	hud.add_child(row)
	var badge := UITheme.make_chapter_badge()   # бог / орден забега
	if badge:
		row.add_child(badge)
	row.add_child(UITheme.icon_row("difficulty", str(RunManager.difficulty),
		UITheme.make_label(Difficulty.level_name(RunManager.difficulty), "HeaderLabel")))
	_req_label = UITheme.make_label("", "ValueLabel")
	_req_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(UITheme.icon_row("hud", "requisition", _req_label))
	row.add_child(UITheme.make_spacer())
	row.add_child(RunTimeline.new())   # лента 15 волн, как в магазине
	row.add_child(UITheme.make_spacer())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)   # ширина колонки не зависит от длины подсказки — сетка не едет после переворота
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	_hint = UITheme.make_label("", "HeaderLabel")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(COLUMN_WIDTH, EDGE_HEIGHT)   # той же высоты, что «ДАЛЕЕ» внизу — сетка ровно по центру
	col.add_child(_hint)
	_grid = GridContainer.new()   # квадрат 2×2
	_start = ShopManager.pick_is_start()
	_grid.columns = 3 if _start else 2   # обычный — квадрат 2×2, стартовый — 3×2
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER   # по центру колонки, а не у левого края
	_grid.add_theme_constant_override("h_separation", 36)
	_grid.add_theme_constant_override("v_separation", 14)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_grid)
	for i in ShopManager.pick_offers.size():
		_grid.add_child(_make_slot(i, ShopManager.pick_offers[i]))
	_next_button = UITheme.make_button("ДАЛЕЕ", "PrimaryButton", _on_next_pressed)
	_next_button.custom_minimum_size = Vector2(320, EDGE_HEIGHT)
	_next_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_next_button.modulate.a = 0.0   # место занято сразу — сетка не прыгает, когда кнопка появится
	_next_button.disabled = true
	col.add_child(_next_button)
	ButtonVolume.attach(_next_button, 6.0)
	_build_info()

func _build_info() -> void:
	_info = UITheme.make_panel("HudPanel", true)
	_info.visible = false
	_info.z_index = 20
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(box)
	_info_title = UITheme.make_label("", "HeaderLabel")
	_info_title.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	_info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_title.custom_minimum_size = Vector2(INFO_WIDTH, 0)
	box.add_child(_info_title)
	_info_kind = UITheme.make_label("", "DimLabel")
	box.add_child(_info_kind)
	_info_desc = UITheme.make_label("", "SmallLabel")
	_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_desc.custom_minimum_size = Vector2(INFO_WIDTH, 0)
	box.add_child(_info_desc)
	add_child(_info)

# Окно карты: лицо под рубашкой; поверх — слой клика: закрытую открывает, открытую берёт; на открытой — описание при наведении
func _make_slot(i: int, card: CardData) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face: Control = _make_face(card)
	_face_ids.append(card.id)
	holder.custom_minimum_size = face.custom_minimum_size
	holder.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := TextureRect.new()
	back.texture = UITheme.card_back(card.faction if card.faction != "" else RunManager.player_faction)
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hit := Control.new()
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_on_card_clicked(i))
	hit.mouse_entered.connect(_on_card_hover.bind(i, true))
	hit.mouse_exited.connect(_on_card_hover.bind(i, false))
	holder.add_child(hit)
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slots.append(holder)
	_holders.append(holder)
	_faces.append(face)
	_backs.append(back)
	_hits.append(hit)
	return holder

func _make_face(card: CardData) -> Control:
	return UITheme.make_card_face(card, CARD_WIDTH) if UITheme.has_card_art(card) else _plain_face(card)

# Подсветка редкости (синяя — Rare, фиолетовая — Epic), как у карт магазина. Только у открытой карты: на закрытой рубашке
# она выдала бы редкость вслепую
func _glow_open_faces() -> void:
	for k in _faces.size():
		if _glared.has(k) or _flipping.has(k):
			continue
		if not (ShopManager.pick_open.has(k) or ShopManager.pick_start_taken.has(k)):
			continue
		var card: CardData = ShopManager.pick_offers[k]
		if not _faces[k] is PanelContainer:
			CardGlare.attach(_faces[k], card.rarity, true)
		_glared[k] = true

# Обучение подменяет карты местами уже после раздачи (ShopManager._tutorial_swap_start): лицо рубашки должно показывать ту карту,
# что ляжет в руку, — иначе игрок видит одно, а в руке другое
func _sync_faces() -> void:
	for k in mini(_faces.size(), ShopManager.pick_offers.size()):
		var card: CardData = ShopManager.pick_offers[k]
		if _face_ids[k] == card.id:
			continue
		var old: Control = _faces[k]
		var face := _make_face(card)
		var holder: Control = _holders[k]
		holder.add_child(face)
		holder.move_child(face, old.get_index())
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		old.queue_free()
		_glared.erase(k)
		_faces[k] = face
		_face_ids[k] = card.id

func _on_card_clicked(i: int) -> void:
	if _start:   # стартовый выбор: клик по рубашке — карта вслепую в руку; взятые не трогаем
		if not ShopManager.pick_open.has(i):
			_on_start_taken(i)
		return
	if ShopManager.pick_open.has(i):
		if ShopManager.pick_ready() and not ShopManager.pick_done() and not _flipping.has(i):
			_on_take_pressed(i)
	else:
		_on_back_clicked(i)

# Описание — у открытой карты (рубашку не выдаём); справа от карты, у правой колонки — слева
func _on_card_hover(i: int, entered: bool) -> void:
	var holder: Control = _holders[i]
	if not entered:
		_info.visible = false
		if not _flipping.has(i) and not _burned:
			holder.modulate = Color.WHITE
		return
	if _dealing or not ShopManager.pick_open.has(i) or _flipping.has(i):
		return
	if _burned and not _kept(i):
		return
	var card: CardData = ShopManager.pick_offers[i]
	_info_title.text = card.display_title()
	_info_kind.text = "%s · %s" % [UITheme.RARITY_NAMES.get(card.rarity, card.rarity), UITheme.TYPE_NAMES.get(card.card_type, card.card_type)]
	_info_desc.text = card.description
	_info.reset_size()
	_info.visible = true
	var r := holder.get_global_rect()
	var size := _info.get_combined_minimum_size()
	var g := _grid.get_global_rect()   # окно — сбоку от всей сетки, чтобы не закрывать соседнюю карту
	var left_col: bool = (i % 3 == 0) if _start else (i % 2 == 0)
	var x := g.position.x - INFO_GAP - size.x if left_col else g.end.x + INFO_GAP
	var y := clampf(r.position.y, 8.0, get_viewport_rect().size.y - size.y - 8.0)
	_info.position = Vector2(x, y)
	if not _start and ShopManager.pick_ready() and not ShopManager.pick_done():
		holder.modulate = HOVER_BRIGHT

# Карта оставлена игроку (не сгорает): взятая в обычном выборе или одна из взятых вслепую в стартовом
func _kept(i: int) -> bool:
	return i == ShopManager.pick_taken_index or ShopManager.pick_start_taken.has(i)

# Карта без иллюстрации — плашка редкости с названием
func _plain_face(card: CardData) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(CARD_WIDTH, CARD_WIDTH * 1.45)
	p.add_theme_stylebox_override("panel", UITheme.card_style(card.rarity))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.make_label(card.display_title(), "CardTitleLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	return p

# Выкладка: карты по очереди вылетают из центра (растут, проявляются, чуть довёртываются) рубашкой вверх
func _deal_in() -> void:
	_dealing = true
	for c in _slots:
		c.modulate.a = 0.0
	await get_tree().process_frame   # раскладка контейнеров — иначе размер ячеек нулевой
	if not is_inside_tree():
		return
	var tw := create_tween()
	tw.set_parallel(true)
	for i in _slots.size():
		var cell: Control = _slots[i]
		cell.pivot_offset = cell.size / 2.0   # положение держит контейнер — выкладка только масштабом и поворотом
		cell.scale = Vector2.ONE * DEAL_FROM_SCALE
		cell.rotation = (-0.12 if i % 2 == 0 else 0.12)
		var d := DEAL_STAGGER * i
		tw.tween_property(cell, "modulate:a", 1.0, DEAL_TIME * 0.6).set_delay(d)
		tw.tween_property(cell, "scale", Vector2.ONE, DEAL_TIME).set_delay(d) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(cell, "rotation", 0.0, DEAL_TIME).set_delay(d) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(AudioManager.play.bind("card_draw")).set_delay(d)
	tw.chain().tween_callback(func():
		_dealing = false
		_refresh())

func _on_back_clicked(i: int) -> void:
	if _dealing or _burned or not ShopManager.pick_reveal(i):
		return
	SaveManager.save_run()
	_sync_faces()   # обучение: открывается обязательная карта, её рубашка меняется местами с нажатой
	_flip(i)
	_refresh()
	if Tutorial.pick_target_card() != null:
		_hint.text = Tutorial.pick_hint()

# Переворот: карта приподнимается и кренится, рубашка сужается к ребру, с ребра раскрывается лицо; по краю — вспышка
func _flip(i: int) -> void:
	var back := _backs[i]
	var face := _faces[i]
	var holder := _holders[i]
	_flipping[i] = true
	for c in [back, face, holder]:
		c.pivot_offset = c.size / 2.0
	face.scale.x = 0.0
	var dir := -1.0 if i % 2 == 0 else 1.0
	var t := create_tween()
	t.tween_method(func(a: float):
		var k := sin(a)                          # 0 → 1 (ребро) → 0
		var w := cos(a)
		back.scale.x = maxf(w, 0.0)
		back.visible = w > 0.0
		face.scale.x = maxf(-w, 0.0)
		holder.scale = Vector2.ONE * (1.0 + FLIP_LIFT * k)
		holder.rotation = dir * FLIP_TILT * k
		holder.modulate = Color.WHITE.lerp(Color(1.5, 1.35, 1.1), k * k),
		0.0, PI, FLIP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func():
		back.visible = false
		holder.scale = Vector2.ONE
		holder.rotation = 0.0
		holder.modulate = Color.WHITE
		_flipping.erase(i)
		_refresh()
		if ShopManager.pick_ready() and not ShopManager.pick_done():
			_tutorial_notify("pick_ready"))
	AudioManager.play("card_draw")

# Обучение: наставник подсказывает / ругает (BattleScene — текущая сцена, окно выбора лежит поверх неё)
func _tutorial_notify(event: String) -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("_tutorial_notify"):
		main.call("_tutorial_notify", event, self)

# Рамки открытых карт, которые обучение разрешает взять (подсвечиваются пульсом)
func tutorial_holders() -> Array:
	var out: Array = []
	for i in ShopManager.pick_open:
		if i < _holders.size() and Tutorial.pick_accepts(ShopManager.pick_offers[i]):
			out.append(_holders[i])
	return out

func _on_take_pressed(i: int) -> void:
	var card := ShopManager.pick_take(i)
	if card == null:
		if Tutorial.pick_target_card() != null:   # обучение: взять надо обязательную карту
			_hint.text = Tutorial.pick_hint()
			_tutorial_notify("pick_wrong")
		return
	var msg := ""
	if BattleManager.pending_cards.size() >= BattleManager.MAX_HAND_SIZE:
		var refund := EconomyManager.sell_card(card)   # рука полна — карта сразу продаётся
		msg = "Рука полна — «%s» продана за %s" % [card.display_title(), GameConstants.coins(refund)]
	else:
		BattleManager.pending_cards.append(card)
		msg = "«%s» — в руке" % card.display_title()
	RunManager.complete_current_node()
	SaveManager.save_run()
	_hint.text = msg
	_burn_others([i])
	_refresh()

# Стартовый выбор: клик по рубашке — карта открывается и уходит в руку; третья взятая — остальные сгорают
func _on_start_taken(i: int) -> void:
	if _dealing or _burned or _flipping.has(i):
		return
	var card := ShopManager.pick_start_take(i)
	if card == null:
		return
	_sync_faces()
	if BattleManager.pending_cards.size() >= BattleManager.MAX_HAND_SIZE:
		EconomyManager.sell_card(card)   # рука полна (стартовая карта меты и др.) — карта сразу продаётся
	else:
		BattleManager.pending_cards.append(card)
	_flip(i)
	if ShopManager.pick_done():
		RunManager.complete_current_node()
		var names: Array[String] = []
		for k in ShopManager.pick_start_taken:
			names.append("«%s»" % ShopManager.pick_offers[k].display_title())
		_hint.text = "В руке: %s" % ", ".join(names)
		get_tree().create_timer(FLIP_TIME + 0.3, true, false, true).timeout.connect(
			func(): _burn_others(ShopManager.pick_start_taken.duplicate()))
	SaveManager.save_run()
	_refresh()

# Невыбранные карты сгорают — и вскрытые, и ещё рубашкой вверх (их не показываем)
func _burn_others(kept: Array) -> void:
	_burned = true
	if not is_inside_tree():
		return
	_info.visible = false
	var n := 0
	for i in _slots.size():
		_hits[i].mouse_filter = Control.MOUSE_FILTER_STOP if kept.has(i) else Control.MOUSE_FILTER_IGNORE
		if kept.has(i):
			continue
		var holder: Control = _holders[i]
		var d := BURN_STAGGER * n
		n += 1
		var tw := create_tween()
		tw.tween_interval(d)
		tw.tween_callback(func():
			if not is_instance_valid(holder):
				return
			Vfx.spawn_over(self, "card_burn", holder.get_global_rect()))
		tw.tween_property(holder, "modulate", BURN_TINT, BURN_TIME * 0.3)
		tw.tween_property(holder, "modulate:a", 0.0, BURN_TIME * 0.7).set_trans(Tween.TRANS_QUAD)

func _refresh() -> void:
	_glow_open_faces()
	var n := ShopManager.pick_open.size()
	var done := ShopManager.pick_done()
	for i in _slots.size():
		var is_open := ShopManager.pick_open.has(i)
		_backs[i].visible = not is_open and not _flipping.has(i)
		var can_take := is_open and ShopManager.pick_ready() and not done and not _flipping.has(i)
		if not _burned:
			var clickable := (not is_open and not done) if _start else (can_take or not is_open)
			_hits[i].mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW
	if done:
		_next_button.modulate.a = 1.0
		_next_button.disabled = false
		ModalOverlay.focus_later(_next_button)
	elif _start:
		_hint.text = "Выберите вслепую 3 карты — осталось %d" % (ShopManager.PICK_START_TAKE - ShopManager.pick_start_taken.size())
	elif n < ShopManager.PICK_OPEN:
		_hint.text = "Откройте %d из %d карт — осталось %d" % [ShopManager.PICK_OPEN, ShopManager.pick_offers.size(),
			ShopManager.PICK_OPEN - n]
	else:
		_hint.text = "Нажмите на карту, чтобы взять её"

func _on_resources_changed(_value) -> void:
	_refresh_hud()

func _refresh_hud() -> void:
	_req_label.text = str(EconomyManager.requisition)

func _on_next_pressed() -> void:
	if embedded:
		finished.emit()
	else:
		RunManager.advance()
