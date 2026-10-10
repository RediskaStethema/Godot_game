# Архив: экран карты забега (RunMapScene) и события (RunEvents)

Удалены 2026-10-09 при переходе на линейный забег из 15 волн
(магазин → бой, мини-босс на 5/10, главный босс на 15). Файлы не были в git —
полный код сохранён здесь для восстановления.

## Что это было

### RunMapScene — экран карты забега
- Была **главной сценой** (`run/main_scene`). Между боями игрок возвращался на неё и сам выбирал следующий узел.
- Граф узлов слева направо: слои по 1 или 3 узла (`RunMapNode.layer / lane / lanes_in_layer`), рёбра рисовались в `_draw_edges()`, пройденный путь (`RunManager.visited`) подсвечивался.
- Состояния кнопки-узла: `available` / `current` / `visited` / `locked` — стиль из `UITheme.map_node_style()`, цвета `UITheme.NODE_COLORS`, подписи `NODE_NAMES`, подсказки при наведении `NODE_HINTS`.
- HUD сверху: волна X/Y, Requisition, HP цитадели, размер руки. Снизу — подсказка и легенда.
- Клик по доступному узлу → `RunManager.enter_node(id)`: магазин / бой меняли сцену, **событие** решалось прямо на карте оверлеем (`_show_event_overlay` → кнопки вариантов → `RunManager.resolve_event(i)`).

### Граф забега (старый RunMapData)
- `LAYOUT` — данные слоёв: `types`, `weights`, `lanes`. 5 волн:
  магазин → бой 1 → [магазин|событие]×3 → [бой|элита]×3 (волна 2) → … → [бой|элита] (волна 4) → магазин → босс (волна 5).
- Связи: слой из 1 узла ↔ все узлы соседнего; между слоями по 3 — только соседние строки (`|lane − lane'| ≤ 1`).
- `_roll_types` гарантировал, что в слое из 3 узлов выпадает каждый допустимый тип (всегда есть выбор).
- Узел «элита» (`RunMapNode.ELITE = "elite"`) — обычная волна, где передние отряды заменены `chaos_champion`; заменён мини-боссом.

### RunEvents — события узла «событие»
- `EVENTS` — данные: `id`, `title`, `text`, `options[]` (`label`, `effect`, параметры).
- Эффекты в `apply_option()`:
  - `requisition` — `EconomyManager.add_requisition(value)`;
  - `heal_citadel` — `BattleManager.heal_citadel(value)` (не выше максимума);
  - `free_card` — случайная карта пула (`CardFactory.build_pool()`, фильтры `rarity` / `card_type`) в руку; рука полна → цена продажи в Req.
- 3 события: «Тайник Муниторума» (+8 Req / обычная карта), «Техножрецы Марса» (+250 HP цитадели / +5 Req), «Экстренное подкрепление» (бесплатный обычный отряд).
- Выбор события: `RunEvents.pick(rng)` в `RunManager` при входе в узел типа `event`, хранилось в `RunManager.current_event`.

## Что осталось в коде (не удалялось)
- `EconomyManager.add_requisition()` и `BattleManager.heal_citadel()` — общие API, пригодятся событиям.
- `RunMapNode` / `RunMapData` / `RunManager` — теперь линейная цепочка шагов, `RunManager.advance()`.
- `UITheme.NODE_NAMES` — подпись типа боя в HUD.

## Как восстановить
1. Вернуть файлы ниже: `scenes/map/RunMapScene.gd`, `scenes/map/RunMapScene.tscn`, `scripts/data/RunEvents.gd`.
2. `RunMapNode`: вернуть `const EVENT = "event"` и поля `layer`, `lane`, `lanes_in_layer` (если убраны).
3. `UITheme`: вернуть `NODE_COLORS`, `MAP_NODE_FONT_SIZE`, `NODE_HINTS`, ключ `"event"` в `NODE_NAMES`, функцию `map_node_style()`.
4. `RunManager`: вернуть `visited`, `current_event`, `get_available_ids()` по слоям, выбор события в `enter_node`, `resolve_event()`, `goto_map()` (`MAP_SCENE`). Сцены вместо `advance()` зовут `goto_map()`.
5. Для графа с выбором — старый `RunMapData` (ниже); `RunMapNode.ELITE` заменить на `MINIBOSS` или вернуть элиту в `EnemyWaves`.
6. Если нужны только события в линейном забеге — проще вставить шаг `event` в `RunMapData.generate()` и показывать оверлей из `RunEvents` в `ShopScene` или отдельной сцене, без графа.
7. `project.godot`: `run/main_scene` → RunMapScene, если карта снова главная сцена.

## Исходный код

### RunMapScene.gd
`scenes/map/RunMapScene.gd`

```gdscript
extends Control

# Карта забега: граф узлов слева направо (RunManager.map), игрок выбирает
# следующий узел. Магазин и бой — отдельные сцены, событие решается здесь же
# (оверлей). UI собирается кодом, стили — из UITheme.

const NODE_SIZE = Vector2(86, 56)
const BOTTOM_BAR_HEIGHT: float = 70.0
const MAP_MARGIN: float = 16.0

var map_area: Control = null
var edges: Control = null
var node_buttons: Dictionary = {}    # id → Button
var hint_label: Label = null
var message_label: Label = null
var wave_label: Label = null
var requisition_label: Label = null
var citadel_label: Label = null
var hand_label: Label = null
var event_overlay: Control = null
var _leaving := false                 # уже ушли в магазин/бой — повторные клики игнорируем

func _ready() -> void:
	_build_layout()
	EconomyManager.requisition_changed.connect(_on_requisition_changed)
	BattleManager.citadel_hp_changed.connect(_on_citadel_changed)
	_refresh_hud()
	_build_nodes()
	_refresh_nodes()
	# Пришли на карту с незавершённым событием — показываем его
	var node = RunManager.get_current_node()
	if node and node.type == RunMapNode.EVENT and not RunManager.current_completed:
		_show_event_overlay()

# -------------------------------------------------------
# ВЁРСТКА
# -------------------------------------------------------
func _build_layout() -> void:
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UITheme.make_background())

	# --- HUD ---
	var hud = PanelContainer.new()
	hud.theme_type_variation = "HudPanel"
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.offset_bottom = UITheme.HUD_HEIGHT
	add_child(hud)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	hud.add_child(row)
	row.add_child(UITheme.make_label("КАРТА ЗАБЕГА", "TitleLabel"))
	message_label = UITheme.make_label("", "SmallLabel")
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.clip_text = true
	message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	message_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	row.add_child(message_label)
	wave_label = UITheme.make_label("", "HeaderLabel")
	row.add_child(wave_label)
	requisition_label = UITheme.make_label("", "ValueLabel")
	row.add_child(requisition_label)
	hand_label = UITheme.make_label("", "ValueLabel")
	row.add_child(hand_label)
	citadel_label = UITheme.make_label("", "ValueLabel")
	row.add_child(citadel_label)
	for l in [message_label, wave_label, requisition_label, hand_label, citadel_label]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# --- Поле карты ---
	map_area = Control.new()
	map_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_area.offset_top = UITheme.HUD_HEIGHT + 16
	map_area.offset_bottom = -(BOTTOM_BAR_HEIGHT + 16)
	map_area.offset_left = MAP_MARGIN
	map_area.offset_right = -MAP_MARGIN
	map_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map_area)
	edges = Control.new()
	edges.set_anchors_preset(Control.PRESET_FULL_RECT)
	edges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edges.draw.connect(_draw_edges)
	map_area.add_child(edges)
	map_area.resized.connect(_layout_nodes)

	# --- Подсказка снизу ---
	var bottom = PanelContainer.new()
	bottom.theme_type_variation = "HudPanel"
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -BOTTOM_BAR_HEIGHT
	add_child(bottom)
	var col = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(col)
	hint_label = UITheme.make_label("", "SmallLabel")
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint_label)
	var legend = UITheme.make_label(("Элита сильнее обычного боя, но даёт +%d Req за каждого элитного врага. "
		+ "Босс на волне %d завершает забег.") % [EconomyManager.BONUS_ELITE_KILL, RunManager.get_total_waves()], "DimLabel")
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(legend)

# -------------------------------------------------------
# HUD
# -------------------------------------------------------
func _refresh_hud() -> void:
	var total = RunManager.get_total_waves()
	wave_label.text = "Волна %d/%d" % [mini(EconomyManager.round_number, total), total]
	_on_requisition_changed(EconomyManager.requisition)
	_on_citadel_changed(BattleManager.citadel_hp)
	hand_label.text = "Рука %d/%d" % [BattleManager.pending_cards.size(), BattleManager.MAX_HAND_SIZE]

func _on_requisition_changed(amount: int) -> void:
	requisition_label.text = "%d Req" % amount

func _on_citadel_changed(hp: float) -> void:
	citadel_label.text = "Цитадель %d/%d" % [ceili(hp), int(BattleManager.CITADEL_MAX_HP)]
	citadel_label.add_theme_color_override("font_color",
		UITheme.RED_BRIGHT if hp <= BattleManager.CITADEL_MAX_HP / 4 else UITheme.GOLD_BRIGHT)

func _show_message(text: String) -> void:
	print("RunMapScene: ", text)
	message_label.text = text

# -------------------------------------------------------
# УЗЛЫ
# -------------------------------------------------------
func _build_nodes() -> void:
	for n in RunManager.map.nodes:
		var b = Button.new()
		b.custom_minimum_size = NODE_SIZE
		b.size = NODE_SIZE
		b.text = UITheme.NODE_NAMES.get(n.type, n.type)
		if n.is_battle():
			b.text += "\nволна %d" % n.wave
		b.tooltip_text = UITheme.NODE_HINTS.get(n.type, "")
		b.add_theme_font_size_override("font_size", UITheme.MAP_NODE_FONT_SIZE)
		b.pressed.connect(_on_node_pressed.bind(n.id))
		b.mouse_entered.connect(_on_node_hover.bind(n.id))
		b.mouse_exited.connect(_update_hint)
		map_area.add_child(b)
		node_buttons[n.id] = b
	_layout_nodes()

func _node_center(n: RunMapNode) -> Vector2:
	var w = map_area.size.x
	var h = map_area.size.y
	var layers = maxi(RunManager.map.layer_count, 1)
	return Vector2((n.layer + 0.5) * w / layers, (n.lane + 0.5) * h / n.lanes_in_layer)

func _layout_nodes() -> void:
	if RunManager.map == null:
		return
	for n in RunManager.map.nodes:
		var b: Button = node_buttons.get(n.id)
		if b:
			b.position = _node_center(n) - NODE_SIZE / 2.0
	edges.queue_redraw()

func _node_state(id: int, available: Array[int]) -> String:
	if available.has(id):
		return "available"
	if id == RunManager.current_node_id:
		return "current"
	if RunManager.visited.has(id):
		return "visited"
	return "locked"

func _refresh_nodes() -> void:
	var available = RunManager.get_available_ids()
	for n in RunManager.map.nodes:
		var b: Button = node_buttons[n.id]
		var state = _node_state(n.id, available)
		b.disabled = state != "available"
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not b.disabled else Control.CURSOR_ARROW
		b.add_theme_stylebox_override("normal", UITheme.map_node_style(n.type, state))
		b.add_theme_stylebox_override("hover", UITheme.map_node_style(n.type, state, true))
		b.add_theme_stylebox_override("pressed", UITheme.map_node_style(n.type, state, true))
		b.add_theme_stylebox_override("disabled", UITheme.map_node_style(n.type, state))
		b.add_theme_color_override("font_disabled_color",
			UITheme.TEXT if state in ["current", "visited"] else UITheme.TEXT_DIM.darkened(0.3))
	edges.queue_redraw()
	_update_hint()

func _update_hint() -> void:
	if RunManager.current_node_id < 0:
		hint_label.text = "Забег начинается: загляните в магазин и соберите армию"
	elif not RunManager.current_completed:
		hint_label.text = "Узел не пройден — вернитесь в него"
	else:
		hint_label.text = "Выберите следующий узел (подсвечены золотом)"

func _on_node_hover(id: int) -> void:
	var n = RunManager.map.get_node_by_id(id)
	if n:
		hint_label.text = "%s — %s" % [UITheme.NODE_NAMES.get(n.type, n.type), UITheme.NODE_HINTS.get(n.type, "")]

func _on_node_pressed(id: int) -> void:
	if event_overlay or _leaving:
		return
	if not RunManager.enter_node(id):
		return
	var node = RunManager.get_current_node()
	_leaving = node.type != RunMapNode.EVENT
	if node.type == RunMapNode.EVENT:
		_refresh_nodes()
		_show_event_overlay()

# Линии связей: пройденный путь — ярким золотом, доступные шаги — золотом, остальное тускло
func _draw_edges() -> void:
	if RunManager.map == null:
		return
	var path_edges = {}
	for i in range(RunManager.visited.size() - 1):
		path_edges[Vector2i(RunManager.visited[i], RunManager.visited[i + 1])] = true
	var available = RunManager.get_available_ids()
	var from_id = RunManager.current_node_id if RunManager.current_completed else -2
	for n in RunManager.map.nodes:
		for next_id in n.next:
			var m = RunManager.map.get_node_by_id(next_id)
			var color = Color(UITheme.GOLD_DIM, 0.45)
			var width = 2.0
			if path_edges.has(Vector2i(n.id, next_id)):
				color = UITheme.GOLD_BRIGHT
				width = 4.0
			elif n.id == from_id and available.has(next_id):
				color = UITheme.GOLD
				width = 3.0
			edges.draw_line(_node_center(n), _node_center(m), color, width, true)

# -------------------------------------------------------
# СОБЫТИЕ
# -------------------------------------------------------
func _show_event_overlay() -> void:
	_close_event_overlay()
	var ev: Dictionary = RunManager.current_event
	if ev.is_empty():
		return
	var col = _make_overlay()
	col.add_child(UITheme.make_label(ev.get("title", "Событие"), "TitleLabel"))
	var text = UITheme.make_label(ev.get("text", ""), "SmallLabel")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)
	var options: Array = ev.get("options", [])
	for i in range(options.size()):
		var b = Button.new()
		b.text = options[i].get("label", "?")
		b.pressed.connect(_on_event_option.bind(i))
		col.add_child(b)

func _on_event_option(index: int) -> void:
	var result = RunManager.resolve_event(index)
	_close_event_overlay()
	_show_message(result)
	_refresh_hud()
	_refresh_nodes()

# Затемнение + панель по центру; возвращает колонку для содержимого
func _make_overlay() -> VBoxContainer:
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	event_overlay = dim
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	return col

func _close_event_overlay() -> void:
	if event_overlay:
		event_overlay.queue_free()
		event_overlay = null
```

### RunMapScene.tscn
`scenes/map/RunMapScene.tscn`

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scenes/map/RunMapScene.gd" id="1_runmap"]

[node name="RunMapScene" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_runmap")
```

### RunEvents.gd
`scripts/data/RunEvents.gd`

```gdscript
class_name RunEvents
extends RefCounted

# События узла «событие» карты забега — данными.
# Точка расширения:
#   * новое событие — новая запись в EVENTS (title, text, options);
#   * новый эффект — ветка в apply_option() по полю "effect".
# Карты-события из CardFactory (TDD: Orbital Strike, Emergency Reinforcements)
# добавит content-cards; их можно подключить сюда эффектом нового типа.
#
# Эффекты:
#   "requisition"  — +value Req
#   "heal_citadel" — +value HP цитадели (не выше максимума)
#   "free_card"    — случайная карта из пула магазина в руку (фильтры rarity / card_type);
#                    рука полна → вместо карты её цена в Req
const EVENTS: Array = [
	{
		"id": "munitorum_cache",
		"title": "Тайник Муниторума",
		"text": "Разведчики нашли нетронутый склад Имперской Гвардии.",
		"options": [
			{"label": "Забрать припасы: +8 Req", "effect": "requisition", "value": 8},
			{"label": "Взять снаряжение: случайная обычная карта", "effect": "free_card", "rarity": "common"},
		],
	},
	{
		"id": "tech_priests",
		"title": "Техножрецы Марса",
		"text": "Адепты Механикус предлагают помощь в обмен на трофеи.",
		"options": [
			{"label": "Ремонт цитадели: +250 HP", "effect": "heal_citadel", "value": 250},
			{"label": "Продать трофеи: +5 Req", "effect": "requisition", "value": 5},
		],
	},
	{
		"id": "emergency_reinforcements",
		"title": "Экстренное подкрепление",
		"text": "Орбитальный транспорт сбросил отряд в зону высадки.",
		"options": [
			{"label": "Принять: бесплатный обычный отряд", "effect": "free_card", "rarity": "common", "card_type": "squad"},
		],
	},
]

static func pick(rng: RandomNumberGenerator) -> Dictionary:
	return EVENTS[rng.randi_range(0, EVENTS.size() - 1)]

# Применяет вариант события, возвращает текст результата для UI
static func apply_option(option: Dictionary, rng: RandomNumberGenerator) -> String:
	match option.get("effect", ""):
		"requisition":
			var amount: int = option.get("value", 0)
			EconomyManager.add_requisition(amount)
			return "+%d Req" % amount
		"heal_citadel":
			var healed = BattleManager.heal_citadel(float(option.get("value", 0)))
			return "Цитадель восстановлена: +%d HP" % roundi(healed)
		"free_card":
			var card = _random_card(rng, option.get("rarity", ""), option.get("card_type", ""))
			if card == null:
				return "Ничего не нашлось"
			if BattleManager.pending_cards.size() >= BattleManager.MAX_HAND_SIZE:
				var refund = EconomyManager.get_sell_price(card)
				EconomyManager.add_requisition(refund)
				return "Рука полна — %s обменяна на +%d Req" % [card.title, refund]
			BattleManager.pending_cards.append(card)
			return "В руку: %s" % card.title
	push_warning("RunEvents: неизвестный эффект '%s'" % option.get("effect", ""))
	return ""

static func _random_card(rng: RandomNumberGenerator, rarity: String, card_type: String) -> CardData:
	var options: Array = []
	for card in CardFactory.build_pool():
		if rarity != "" and card.rarity != rarity:
			continue
		if card_type != "" and card.card_type != card_type:
			continue
		options.append(card)
	if options.is_empty():
		return null
	return options[rng.randi_range(0, options.size() - 1)]
```

### RunMapData.gd — граф с выбором (до линейного забега)
`scripts/data/RunMapData.gd`

```gdscript
class_name RunMapData
extends Resource

# Граф забега: слои слева направо, в слое 1–3 узла (lanes).
# Боевой слой = одна волна: каждый путь проходит ровно один бой на слой,
# поэтому номер волны узла всегда совпадает с EconomyManager.round_number.
# Связи: из слоя в 1 узел — во все узлы следующего и наоборот,
# между слоями по 3 узла — в соседние строки (|lane - lane'| <= 1).
#
# Раскладка — данные: types (что может выпасть), weights (веса), lanes (ширина).
# Босс задаётся типом последнего слоя, а не проверкой номера волны.
const LAYOUT: Array = [
	{"types": [RunMapNode.SHOP], "lanes": 1},                                       # старт
	{"types": [RunMapNode.BATTLE], "lanes": 1},                                     # волна 1
	{"types": [RunMapNode.SHOP, RunMapNode.EVENT], "weights": [2, 1], "lanes": 3},
	{"types": [RunMapNode.BATTLE, RunMapNode.ELITE], "weights": [2, 1], "lanes": 3},  # волна 2
	{"types": [RunMapNode.SHOP, RunMapNode.EVENT], "weights": [2, 1], "lanes": 3},
	{"types": [RunMapNode.BATTLE, RunMapNode.ELITE], "weights": [2, 1], "lanes": 3},  # волна 3
	{"types": [RunMapNode.SHOP, RunMapNode.EVENT], "weights": [2, 1], "lanes": 3},
	{"types": [RunMapNode.BATTLE, RunMapNode.ELITE], "weights": [2, 1], "lanes": 3},  # волна 4
	{"types": [RunMapNode.SHOP], "lanes": 1},                                       # привал перед боссом
	{"types": [RunMapNode.BOSS], "lanes": 1},                                       # волна 5
]

@export var nodes: Array[RunMapNode] = []
@export var layer_count: int = 0
@export var total_waves: int = 0

func get_node_by_id(id: int) -> RunMapNode:
	if id < 0 or id >= nodes.size():
		return null
	return nodes[id]

func get_layer_ids(layer: int) -> Array[int]:
	var ids: Array[int] = []
	for n in nodes:
		if n.layer == layer:
			ids.append(n.id)
	return ids

# -------------------------------------------------------
# ГЕНЕРАЦИЯ
# -------------------------------------------------------
static func generate(rng: RandomNumberGenerator, layout: Array = LAYOUT) -> RunMapData:
	var map = RunMapData.new()
	var layers: Array = []
	var wave := 0
	for li in range(layout.size()):
		var spec: Dictionary = layout[li]
		var types: Array = spec["types"]
		var lanes: int = spec.get("lanes", 1)
		# Слой боевой, если его типы — бои (смешивать бой и не бой в слое нельзя)
		var battle_layer = RunMapNode.is_battle_type(types[0])
		if battle_layer:
			wave += 1
		var rolled = _roll_types(rng, types, spec.get("weights", []), lanes)
		var layer_nodes: Array[RunMapNode] = []
		for lane in range(lanes):
			var n = RunMapNode.new()
			n.id = map.nodes.size()
			n.layer = li
			n.lane = lane
			n.lanes_in_layer = lanes
			n.type = rolled[lane]
			n.wave = wave if battle_layer else 0
			map.nodes.append(n)
			layer_nodes.append(n)
		layers.append(layer_nodes)

	for li in range(layers.size() - 1):
		var a: Array[RunMapNode] = layers[li]
		var b: Array[RunMapNode] = layers[li + 1]
		for n in a:
			for m in b:
				if a.size() == 1 or b.size() == 1 or absi(n.lane - m.lane) <= 1:
					n.next.append(m.id)

	map.layer_count = layers.size()
	map.total_waves = wave
	return map

# Типы узлов слоя по весам; каждый допустимый тип выпадает хотя бы раз,
# если строк хватает — чтобы на карте всегда был выбор.
static func _roll_types(rng: RandomNumberGenerator, types: Array, weights: Array, lanes: int) -> Array:
	var result: Array = []
	var total := 0.0
	for i in range(types.size()):
		total += float(weights[i]) if i < weights.size() else 1.0
	for lane in range(lanes):
		var r = rng.randf() * total
		var picked = types[types.size() - 1]
		for i in range(types.size()):
			r -= float(weights[i]) if i < weights.size() else 1.0
			if r < 0.0:
				picked = types[i]
				break
		result.append(picked)
	if lanes >= types.size():
		for t in types:
			if result.has(t):
				continue
			# Заменяем строку, тип которой встречается больше одного раза
			var candidates: Array = []
			for lane in range(lanes):
				if result.count(result[lane]) > 1:
					candidates.append(lane)
			if not candidates.is_empty():
				result[candidates[rng.randi_range(0, candidates.size() - 1)]] = t
	return result
```

### RunManager.gd — версия с событиями и графом (переходная, уже с advance())
`scripts/autoload/RunManager.gd`

```gdscript
extends Node

# -------------------------------------------------------
# КАРТА ЗАБЕГА — состояние
# -------------------------------------------------------
# Отдельный autoload, а не поля BattleManager: BattleManager отвечает за бой
# и его тик, а цепочка шагов забега и текущий шаг — навигация между сценами.
# Сбрасывается из BattleManager.reset_run() (new_run()), генерирует RunMapData.
#
# Цикл линейный, игрок путь не выбирает: ShopScene → BattleScene → ShopScene → …
# Шаг завершён → advance() сам открывает следующий. round_number растёт только в
# EconomyManager.give_round_income (один бой = одна волна).

const SHOP_SCENE: String = "res://scenes/shop/ShopScene.tscn"
const BATTLE_SCENE: String = "res://scenes/battle/BattleScene.tscn"

signal run_started
signal node_entered(node: RunMapNode)
signal node_completed(node: RunMapNode)

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var map: RunMapData = null
var current_node_id: int = -1        # -1 — забег только начат, первый шаг не открыт
var current_completed: bool = true   # текущий узел пройден — можно идти дальше
var visited: Array[int] = []         # пройденный путь (id узлов по порядку)
var current_event: Dictionary = {}   # событие текущего узла «событие» (не перекидывается)
var run_won: bool = false            # босс повержен

func _ready() -> void:
	new_run()

func new_run(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	map = RunMapData.generate(rng)
	current_node_id = -1
	current_completed = true
	visited.clear()
	current_event = {}
	run_won = false
	print("RunManager: новый забег — %d узлов, %d волн" % [map.nodes.size(), map.total_waves])
	emit_signal("run_started")

# -------------------------------------------------------
# НАВИГАЦИЯ
# -------------------------------------------------------
func get_current_node() -> RunMapNode:
	return map.get_node_by_id(current_node_id) if map else null

# Куда можно пойти: старт → первый шаг; незавершённый шаг → только он;
# иначе — связи текущего шага
func get_available_ids() -> Array[int]:
	if map == null or run_won:
		return []
	if current_node_id < 0:
		return map.get_layer_ids(0)
	if not current_completed:
		return [current_node_id]
	return get_current_node().next.duplicate()

func can_enter(id: int) -> bool:
	return get_available_ids().has(id)

# Входит в шаг и меняет сцену (магазин / бой)
func enter_node(id: int) -> bool:
	if not _set_current(id):
		return false
	var node = map.get_node_by_id(id)
	match node.type:
		RunMapNode.SHOP:
			get_tree().change_scene_to_file(SHOP_SCENE)
		RunMapNode.BATTLE, RunMapNode.MINIBOSS, RunMapNode.BOSS:
			if node.wave != EconomyManager.round_number:
				push_warning("RunManager: волна шага %d ≠ round_number %d" % [node.wave, EconomyManager.round_number])
			get_tree().change_scene_to_file(BATTLE_SCENE)
	return true

# Делает шаг текущим без смены сцены
func _set_current(id: int) -> bool:
	if not can_enter(id):
		return false
	var node = map.get_node_by_id(id)
	if id != current_node_id:
		current_node_id = id
		current_completed = false
		visited.append(id)
		current_event = RunEvents.pick(rng) if node.type == RunMapNode.EVENT else {}
		print("RunManager: шаг %d (%s, волна %d)" % [id, node.type, node.wave])
		emit_signal("node_entered", node)
	return true

# Следующий шаг цепочки: старт → первый; незавершённый — он сам; иначе — next.
# Шагов нет (забег выигран) — -1.
func get_next_id() -> int:
	var ids = get_available_ids()
	return ids[0] if not ids.is_empty() else -1

# Переход к следующему шагу забега со сменой сцены (вызывают сцены по итогам шага)
func advance() -> void:
	var id = get_next_id()
	if id < 0 or not enter_node(id):
		push_warning("RunManager: следующего шага нет")

# Сцена открыта напрямую (главная сцена — магазин): забег ещё не начат —
# первый шаг становится текущим без смены сцены
func ensure_started() -> void:
	if current_node_id < 0 and not run_won:
		_set_current(get_next_id())

# Вызывают сцены шагов: магазин — при уходе, бой — по итогам
func complete_current_node(won: bool = true) -> void:
	var node = get_current_node()
	if node == null or current_completed:
		return
	current_completed = true
	current_event = {}
	if node.type == RunMapNode.BOSS and won:
		run_won = true
		print("RunManager: босс повержен — забег выигран")
	emit_signal("node_completed", node)

# Применяет вариант события текущего шага и завершает его (события сейчас в цепочку не входят)
func resolve_event(option_index: int) -> String:
	var node = get_current_node()
	if node == null or node.type != RunMapNode.EVENT or current_completed or current_event.is_empty():
		return ""
	var options: Array = current_event.get("options", [])
	if option_index < 0 or option_index >= options.size():
		return ""
	var result = RunEvents.apply_option(options[option_index], rng)
	print("RunManager: событие «%s» — %s" % [current_event.get("title", ""), result])
	complete_current_node()
	return result

# -------------------------------------------------------
# ДЛЯ БОЯ
# -------------------------------------------------------
# Тип текущего боя; если BattleScene запущена напрямую — обычный бой
func get_battle_type() -> String:
	var node = get_current_node()
	if node and node.is_battle() and not current_completed:
		return node.type
	return RunMapNode.BATTLE

func get_battle_wave() -> int:
	var node = get_current_node()
	if node and node.is_battle() and not current_completed:
		return node.wave
	return EconomyManager.round_number

func get_total_waves() -> int:
	return map.total_waves if map else 0

func is_shop_node_active() -> bool:
	var node = get_current_node()
	return node != null and node.type == RunMapNode.SHOP and not current_completed
```

### RunMapNode.gd — с EVENT и полями графа
`scripts/data/RunMapNode.gd`

```gdscript
class_name RunMapNode
extends Resource

# Шаг забега: магазин перед волной или бой волны. Связи — id следующего шага (RunMapData.nodes[id]).

const BATTLE: String = "battle"   # обычный бой волны
const MINIBOSS: String = "miniboss"  # каждая RunMapData.MINIBOSS_EVERY-я волна: мини-босс + элита
const BOSS: String = "boss"       # последняя волна (главный босс): победа = победа в забеге
const SHOP: String = "shop"       # магазин (ShopScene)
const EVENT: String = "event"     # событие (RunEvents) — сейчас в забег не входит

const BATTLE_TYPES: Array[String] = [BATTLE, MINIBOSS, BOSS]

@export var id: int = -1
@export var layer: int = 0          # столбец карты (слева направо)
@export var lane: int = 0           # строка внутри слоя
@export var lanes_in_layer: int = 1
@export var type: String = BATTLE
@export var wave: int = 0           # номер волны (только у боевых узлов)
@export var next: Array[int] = []   # id узлов, куда можно пойти дальше

static func is_battle_type(t: String) -> bool:
	return t in BATTLE_TYPES

func is_battle() -> bool:
	return is_battle_type(type)
```

### UITheme.gd — константы карты
`scripts/ui/UITheme.gd`

```gdscript
# Карта забега: цвет и подпись узла по типу (RunMapNode.*)
const NODE_COLORS = {
	"battle": Color("8e2620"),
	"miniboss": Color("c06a1e"),
	"boss":   Color("7a2f9e"),
	"shop":   Color("6e5a30"),
	"event":  Color("2f6e4a"),
}
const MAP_NODE_FONT_SIZE = 13
const NODE_NAMES = {
	"battle": "БОЙ",
	"miniboss": "МИНИ-БОСС",
	"boss":   "БОСС",
	"shop":   "МАГАЗИН",
	"event":  "СОБЫТИЕ",
}
const NODE_HINTS = {
	"battle": "Обычная волна Хаоса",
	"miniboss": "Hellbrute и элита Хаоса: +3 Req за каждого элитного врага",
	"boss":   "Главный босс Chaos Lord — победа завершает забег",
	"shop":   "Купить и продать карты",
	"event":  "Случайное событие с выбором награды",
}
```

### UITheme.gd — map_node_style()
`scripts/ui/UITheme.gd`

```gdscript
# Стиль кнопки-узла карты забега. state: "available", "current", "visited", "locked"
static func map_node_style(node_type: String, state: String, hover: bool = false) -> StyleBoxFlat:
	var base: Color = NODE_COLORS.get(node_type, BG_MID)
	var bg = base
	var border = GOLD_DIM
	var border_w = 2
	match state:
		"available":
			border = GOLD_BRIGHT if hover else GOLD
			border_w = 3
			if hover:
				bg = base.lightened(0.2)
		"current":
			border = GOLD_BRIGHT
			border_w = 4
		"visited":
			bg = base.darkened(0.45)
			border = GOLD
		_:
			bg = base.darkened(0.6)
			border = Color("3e362c")
	var s = panel_style(bg, border, border_w, 14, 6)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 4
	return s
```
