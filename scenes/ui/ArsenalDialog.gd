class_name ArsenalDialog
extends ModalOverlay

# «Арсенал» главного меню — древо мета-прогрессии (MetaProgress.TREE, решение пользователя 10.11.2026):
# слева 4 ветки колонками (MetaProgress.BRANCHES), узлы — значки, связи с родителем — линиями
# (куплен — янтарь, можно купить — сталь, закрыт — тёмная сталь); справа карточка выбранного узла:
# Слава, название, что даёт, родитель, кнопка «Открыть · N». Наведение и клик выбирают узел.
# После покупки окно перестраивается (выбор остаётся).

const WINDOW_WIDTH: float = 1060.0
const COLUMN_WIDTH: float = 165.0       # ширина колонки ветки
const NODE_SIZE: float = 56.0           # значок узла
const LANE_STEP: float = 46.0           # сдвиг узла lane ±1 от середины колонки
const BRANCH_HEADER: float = 48.0       # название ветки над узлами
const ROW_STEP_MAX: float = 88.0        # шаг рядов; в низком окне — меньше, не ниже ROW_STEP_MIN
const ROW_STEP_MIN: float = 70.0
const WINDOW_CHROME: float = 250.0      # рамка, заголовок и «Закрыть» вокруг древа — древо вписано в экран
const COST_LABEL_WIDTH: float = 80.0
const COST_LABEL_HEIGHT: float = 20.0   # связь к потомку начинается под подписью цены родителя
const LOCK_SIZE: float = 22.0
const DETAIL_WIDTH: float = 300.0
const GLORY_ICON_SIZE: float = 30.0
const NODE_ICON_PAD: float = 5.0
const EDGE_WIDTH: float = 3.0
const SELECTED_BORDER: int = 3
const LOCKED_ICON_TINT = Color(0.45, 0.45, 0.5)
const POOR_ICON_TINT = Color(0.75, 0.75, 0.8)
const KIND_NAMES = {"passive": "Пассивка на все забеги", "start_card": "Стартовая карта",
	"chapter": "Братство", "card": "Карта магазина"}

var glory_label: Label = null
var selected: String = ""
var _row_step: float = ROW_STEP_MAX
var _node_buttons: Dictionary = {}      # id узла → Button
var _detail: VBoxContainer = null

func setup() -> void:
	close_on_cancel = true
	build_frame(WINDOW_WIDTH)
	selected = _default_selection()
	_rebuild()

# Первый узел, который можно купить сейчас, иначе первый доступный, иначе корень первой ветки
func _default_selection() -> String:
	for n in MetaProgress.TREE:
		if MetaProgress.can_buy(n["id"]):
			return n["id"]
	for n in MetaProgress.TREE:
		if MetaProgress.is_available(n["id"]):
			return n["id"]
	return MetaProgress.TREE[0]["id"]

func _rebuild() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	_focus_taken = false
	_node_buttons.clear()
	add_title("АРСЕНАЛ")
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	content.add_child(body)
	body.add_child(_make_tree())
	_detail = VBoxContainer.new()
	_detail.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	_detail.add_theme_constant_override("separation", 10)
	body.add_child(_detail)
	_show_detail(selected)
	add_button("Закрыть", close)

# -------------------------------------------------------
# ДРЕВО
# -------------------------------------------------------
func _rows() -> int:
	var rows := 0
	for n in MetaProgress.TREE:
		rows = maxi(rows, int(n["row"]) + 1)
	return rows

func _node_center(n: Dictionary) -> Vector2:
	var col := 0
	for i in MetaProgress.BRANCHES.size():
		if MetaProgress.BRANCHES[i]["id"] == n["branch"]:
			col = i
	return Vector2(COLUMN_WIDTH * (col + 0.5) + LANE_STEP * float(n["lane"]),
		BRANCH_HEADER + _row_step * (float(n["row"]) + 0.5))

func _make_tree() -> Control:
	var rows := _rows()
	_row_step = clampf((get_viewport_rect().size.y - WINDOW_CHROME - BRANCH_HEADER) / rows, ROW_STEP_MIN, ROW_STEP_MAX)
	var tree := Control.new()
	tree.name = "Tree"
	tree.custom_minimum_size = Vector2(COLUMN_WIDTH * MetaProgress.BRANCHES.size(), BRANCH_HEADER + _row_step * rows)
	tree.draw.connect(_draw_tree.bind(tree))
	for i in MetaProgress.BRANCHES.size():
		var b: Dictionary = MetaProgress.BRANCHES[i]
		var nodes := MetaProgress.branch_nodes(b["id"])
		var owned := nodes.filter(func(n): return MetaProgress.owns(n["id"])).size()
		var head := UITheme.make_label(b["name"].to_upper(), "HeaderLabel")
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.position = Vector2(COLUMN_WIDTH * i, 0)
		head.size = Vector2(COLUMN_WIDTH, BRANCH_HEADER * 0.55)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tree.add_child(head)
		var sub := UITheme.make_label("открыто %d/%d" % [owned, nodes.size()], "DimLabel")
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.position = Vector2(COLUMN_WIDTH * i, BRANCH_HEADER * 0.5)
		sub.size = Vector2(COLUMN_WIDTH, BRANCH_HEADER * 0.4)
		tree.add_child(sub)
	for n in MetaProgress.TREE:
		_add_node(tree, n)
	return tree

# Разделители колонок и связи «родитель → узел»; цвет — по состоянию узла-потомка
func _draw_tree(tree: Control) -> void:
	for i in range(1, MetaProgress.BRANCHES.size()):
		var x := COLUMN_WIDTH * i
		tree.draw_line(Vector2(x, BRANCH_HEADER * 0.2), Vector2(x, tree.size.y), Color(UITheme.GOLD_DIM, 0.6), 1.0)
	for n in MetaProgress.TREE:
		if n["requires"] == "":
			continue
		var parent := MetaProgress.get_node_data(n["requires"])
		var color: Color = UITheme.GOLD if MetaProgress.owns(n["id"]) \
			else (UITheme.TEXT_DIM if MetaProgress.is_available(n["id"]) else UITheme.GOLD_DIM)
		var from := _node_center(parent) + Vector2(0, NODE_SIZE / 2.0 + COST_LABEL_HEIGHT)
		tree.draw_line(from, _node_center(n) - Vector2(0, NODE_SIZE / 2.0), color, EDGE_WIDTH, true)

func _add_node(tree: Control, n: Dictionary) -> void:
	var id: String = n["id"]
	var owned := MetaProgress.owns(id)
	var available := MetaProgress.is_available(id)
	var affordable := MetaProgress.can_buy(id)
	var center := _node_center(n)
	var b := Button.new()
	b.name = "Node_" + id
	b.custom_minimum_size = Vector2(NODE_SIZE, NODE_SIZE)
	b.size = b.custom_minimum_size
	b.position = center - b.size / 2.0
	b.clip_contents = true
	b.tooltip_text = MetaProgress.node_title(n)
	var border: Color = UITheme.GOLD_BRIGHT if owned else (UITheme.GOLD if affordable
		else (UITheme.TEXT_DIM if available else UITheme.GOLD_DIM))
	var width := SELECTED_BORDER if id == selected else 2
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var hl: bool = state == "hover" or state == "focus" or id == selected
		b.add_theme_stylebox_override(state, _node_style(UITheme.AMBER_LIGHT if hl and id == selected else border,
			width + (1 if state == "hover" else 0), owned))
	b.pressed.connect(_select.bind(id))
	b.mouse_entered.connect(_show_detail.bind(id))
	b.mouse_exited.connect(func(): _show_detail(selected))
	tree.add_child(b)
	_node_buttons[id] = b
	var icon := _node_icon(n)
	if icon:
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = NODE_ICON_PAD
		icon.offset_top = NODE_ICON_PAD
		icon.offset_right = -NODE_ICON_PAD
		icon.offset_bottom = -NODE_ICON_PAD
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not available and not owned:
			icon.self_modulate = LOCKED_ICON_TINT
		elif not owned and not affordable:
			icon.self_modulate = POOR_ICON_TINT
		b.add_child(icon)
	if not available and not owned:   # замок hud/lock в правом нижнем углу закрытого узла
		var lock := UITheme.make_icon("hud", "lock", LOCK_SIZE)
		if lock:
			lock.name = "Lock"
			lock.position = b.size - lock.custom_minimum_size - Vector2(2, 2)
			b.add_child(lock)
	# Под узлом — цена (не хватает Славы — тусклая) или «открыто»
	var cost := UITheme.make_label("открыто" if owned else str(n["cost"]), "SmallLabel")
	cost.name = "Cost_" + id
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_color_override("font_color", UITheme.GREEN if owned
		else (UITheme.GOLD_BRIGHT if affordable else UITheme.TEXT_DIM))
	cost.position = Vector2(center.x - COST_LABEL_WIDTH / 2.0, center.y + NODE_SIZE / 2.0)
	cost.size = Vector2(COST_LABEL_WIDTH, 0)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree.add_child(cost)

func _node_style(border: Color, width: int, owned: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(UITheme.BG_MID, 1.0) if owned else Palette.PANEL_DARK
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(6)
	s.corner_detail = 1   # срезанные углы, как у панелей UITheme
	return s

# Значок узла: пассивка — passives/<id>, орден — emblems/<id>, карта — значок карты или её иллюстрация
func _node_icon(n: Dictionary) -> TextureRect:
	var tex: Texture2D = null
	var cover := false
	match n["kind"]:
		"passive":
			tex = UITheme.ui_icon("passives", n["target"])
		"chapter":
			tex = UITheme.ui_icon("emblems", n["target"])
		_:
			tex = UITheme.ui_icon("cards", n["target"])
			if tex == null:
				var card := CardFactory.create(n["target"])
				tex = UITheme.card_art(card) if card else null
				cover = true
	if tex == null:
		return null
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return r

# -------------------------------------------------------
# КАРТОЧКА УЗЛА
# -------------------------------------------------------
func _select(id: String) -> void:
	if id == selected:
		return
	selected = id
	_rebuild()

func _show_detail(id: String) -> void:
	if _detail == null or not is_instance_valid(_detail):
		return
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	glory_label = UITheme.make_label("Слава: %d" % MetaProgress.get_glory(), "HeaderLabel")
	glory_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	glory_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_detail.add_child(UITheme.icon_row("hud", "glory", glory_label, GLORY_ICON_SIZE))
	_detail.add_child(_wrapped("За каждый забег, даже проигранный: бои, мини-боссы, босс × сложность", "DimLabel"))
	_detail.add_child(HSeparator.new())
	var n := MetaProgress.get_node_data(id)
	if n.is_empty():
		return
	var title := UITheme.make_label(MetaProgress.node_title(n), "HeaderLabel")
	title.name = "NodeTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(title)
	_detail.add_child(_wrapped("%s · %s" % [KIND_NAMES.get(n["kind"], ""),
		MetaProgress.get_branch(n["branch"]).get("name", "")], "DimLabel"))
	_detail.add_child(_wrapped(MetaProgress.node_desc(n), "SmallLabel"))
	var owned := MetaProgress.owns(id)
	var available := MetaProgress.is_available(id)
	if not owned and not available:
		var need := _wrapped("Сначала откройте: %s" % MetaProgress.node_title(MetaProgress.get_node_data(n["requires"])), "SmallLabel")
		need.add_theme_color_override("font_color", UITheme.RED_BRIGHT)
		_detail.add_child(need)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(spacer)
	var cost := int(n["cost"])
	var text := "Открыто" if owned else ("Открыть · %d Славы" % cost if MetaProgress.get_glory() >= cost or not available
		else "Не хватает %d Славы" % (cost - MetaProgress.get_glory()))
	var enabled := MetaProgress.can_buy(id)
	var b := UITheme.make_button(text, "PrimaryButton" if enabled else "", _buy.bind(id))
	b.name = "Buy"
	b.custom_minimum_size = Vector2(0, 44)
	b.disabled = not enabled
	_detail.add_child(b)

func _wrapped(text: String, variation: String) -> Label:
	var l := UITheme.make_label(text, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	return l

func _buy(id: String) -> void:
	if MetaProgress.buy_node(id):
		selected = id
		_rebuild()
