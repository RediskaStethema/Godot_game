class_name SquadInspector
extends Control

# Подсказки по отрядам на поле боя (UI поверх камеры, в CanvasLayer):
#   * наведение на бойца дольше HOVER_NAME_DELAY — подпись «имя ×бойцов · ур.N»
#     (свои золотом, враги красным; скрытые до боя враги не подписываются);
#   * клик по своему отряду — справка: уровень, бойцы, HP, бонусы, улучшения,
#     синергии; обновляется на лету, повторный клик или клик мимо — закрыть.
# Опрос мыши и обновление текста — REFRESH_INTERVAL раз в секунду, не каждый кадр.

const HOVER_NAME_DELAY: float = 0.5
const HOVER_HALF_WIDTH: float = 20.0   # полуширина бойца для попадания курсором, px мира
const REFRESH_INTERVAL: float = 0.1
const INFO_WIDTH: float = 220.0

# Выключается, пока открыто меню слияния (BattleScene)
var enabled: bool = true
# true — клик забран другим (залп орудия игрока): справку не открывать и не закрывать.
# Справка получает клик раньше сцены, поэтому спрашивает её заранее
var click_blocker: Callable
var info_squad: Squad = null

var _hover_panel: PanelContainer
var _hover_text: Label
var _info_panel: PanelContainer
var _info_title: Label
var _info_text: Label
var _building_panel: PanelContainer   # подсказка по зданию под курсором (BattleScene)
var _building_text: Label
var _hover_squad: Squad = null
var _hover_time: float = 0.0
var _refresh_left: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func _build() -> void:
	_info_panel = UITheme.make_panel("HudPanel", true)
	_info_panel.custom_minimum_size = Vector2(INFO_WIDTH, 0)
	_info_panel.hide()
	add_child(_info_panel)
	var col = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.add_child(col)
	_info_title = UITheme.make_label("", "HeaderLabel")
	col.add_child(_info_title)
	_info_text = UITheme.make_label("", "SmallLabel")
	_info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_text.custom_minimum_size = Vector2(INFO_WIDTH, 0)
	col.add_child(_info_text)

	_hover_panel = UITheme.make_panel("HudPanel", true)
	_hover_panel.hide()
	add_child(_hover_panel)
	_hover_text = UITheme.make_label("", "SmallLabel")
	_hover_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.add_child(_hover_text)

	_building_panel = UITheme.make_panel("HudPanel", true)
	_building_panel.hide()
	add_child(_building_panel)
	_building_text = UITheme.make_label("", "SmallLabel")
	_building_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_building_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_building_text.custom_minimum_size = Vector2(INFO_WIDTH, 0)
	_building_panel.add_child(_building_text)

# -------------------------------------------------------
# ОПРОС
# -------------------------------------------------------
func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_INTERVAL
	_update_info()
	_update_hover(REFRESH_INTERVAL)

func _update_hover(elapsed: float) -> void:
	var squad = squad_at(_mouse_world()) if enabled else null
	# Справка уже открыта на этом отряде — подпись не нужна
	if squad != null and squad == info_squad:
		squad = null
	if squad != _hover_squad:
		_hover_squad = squad
		_hover_time = 0.0
		_hover_panel.hide()
	if squad == null:
		return
	_hover_time += elapsed
	if _hover_time >= HOVER_NAME_DELAY:
		show_hover(squad, get_viewport().get_mouse_position())

# _unhandled_input: клики по UI (скамейка, HUD, меню) сюда не доходят
func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if click_blocker.is_valid() and click_blocker.call():
		return
	var squad = squad_at(_screen_to_world(event.position))
	if squad == null or squad.team != GameConstants.TEAM_PLAYER or squad == info_squad:
		close_info()
		return
	info_squad = squad
	_update_info()

# -------------------------------------------------------
# API
# -------------------------------------------------------
func squad_at(world_pos: Vector2) -> Squad:
	return SquadRegistry.find_squad_at(world_pos, HOVER_HALF_WIDTH)

func close_info() -> void:
	info_squad = null
	_info_panel.hide()

# Подсказка по зданию (Building.describe) у точки экрана; пустой текст — скрыть
func show_building_hover(text: String, screen_pos: Vector2) -> void:
	if text == "" or not enabled:
		_building_panel.hide()
		return
	_building_text.text = text
	_building_panel.reset_size()
	var pos = screen_pos + Vector2(16, 12)
	_building_panel.position = pos.clamp(Vector2.ZERO, get_viewport_rect().size - _building_panel.size)
	_building_panel.show()

func is_building_hover_visible() -> bool:
	return _building_panel.visible

# Всё скрыть и больше не реагировать (конец забега)
func shutdown() -> void:
	close_info()
	_hover_panel.hide()
	_building_panel.hide()
	enabled = false
	set_process(false)

# Подпись над точкой экрана, в пределах экрана
func show_hover(squad: Squad, screen_pos: Vector2) -> void:
	var text = "%s ×%d" % [squad.data.unit_name, squad.soldiers.size()]
	if squad.team == GameConstants.TEAM_PLAYER and squad.data.squad_level > 0:
		text += " · ур.%d" % squad.data.squad_level
	_hover_text.text = text
	_hover_text.add_theme_color_override("font_color",
		UITheme.GOLD_BRIGHT if squad.team == GameConstants.TEAM_PLAYER else UITheme.RED_BRIGHT)
	_hover_panel.reset_size()
	var pos = screen_pos + Vector2(14, -_hover_panel.size.y - 6)
	_hover_panel.position = pos.clamp(Vector2.ZERO, get_viewport_rect().size - _hover_panel.size)
	_hover_panel.show()

# -------------------------------------------------------
# СПРАВКА
# -------------------------------------------------------
func _update_info() -> void:
	if info_squad == null:
		return
	if not is_instance_valid(info_squad) or not info_squad.is_alive():
		close_info()
		return
	_info_title.text = info_squad.data.unit_name
	_info_text.text = describe(info_squad)
	_info_panel.reset_size()
	_info_panel.show()
	# Рядом с первым живым бойцом (в бою отряд движется), в пределах экрана
	var anchor = _world_to_screen(info_squad.soldiers[0].global_position)
	var pos = anchor + Vector2(24, -_info_panel.size.y / 2.0)
	_info_panel.position = pos.clamp(Vector2(0, UITheme.HUD_HEIGHT), get_viewport_rect().size - _info_panel.size)

# Текст справки: уровень, бойцы, HP, бонусы множителей UnitData, улучшения, синергии
static func describe(squad: Squad) -> String:
	var d = squad.data
	var lines: Array[String] = []
	lines.append("Уровень %d/%d" % [d.squad_level, UnitFactory.MAX_SQUAD_LEVEL])
	var alive = squad.soldiers.size()
	lines.append("Бойцы: %d/%d" % [alive, maxi(d.squad_size, alive)])
	var hp := 0.0
	var max_hp := 0.0
	for soldier in squad.soldiers:
		hp += soldier.current_hp
		max_hp += soldier.max_hp
	lines.append("HP: %d/%d" % [ceili(hp), ceili(max_hp)])
	var bonuses: Array[String] = []
	for b in [[d.hp_multiplier, "HP"], [d.damage_multiplier, "урона"], [d.attack_speed_multiplier, "скорострельности"]]:
		if b[0] > 1.001:
			bonuses.append("+%d%% %s" % [roundi((b[0] - 1.0) * 100.0), b[1]])
	lines.append("Бонусы: " + (", ".join(bonuses) if not bonuses.is_empty() else "нет"))
	if not d.applied_upgrades.is_empty():
		lines.append("Улучшения: " + ", ".join(d.applied_upgrades))
	var syn = SynergyManager.get_soldier_synergy_names(d.tags)
	if not syn.is_empty():
		lines.append("Синергии: " + ", ".join(syn))
	var pos = SynergyManager.get_squad_position_bonus(squad)
	if pos != "":
		var p: Dictionary = SynergyManager.POSITION_BONUSES[pos]
		lines.append("%s: %s" % [p["name"], p["desc"]])
	return "\n".join(lines)

# -------------------------------------------------------
# ЭКРАН ↔ МИР (камера боя задаёт canvas_transform вьюпорта)
# -------------------------------------------------------
func _mouse_world() -> Vector2:
	return _screen_to_world(get_viewport().get_mouse_position())

func _screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p

func _world_to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p
