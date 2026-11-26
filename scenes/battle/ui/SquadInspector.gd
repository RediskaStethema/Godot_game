class_name SquadInspector
extends Control

signal squad_info_opened(squad: Squad)   # справка своего отряда открыта кликом (обучение)

# Подсказки по отрядам на поле боя (UI поверх камеры, в CanvasLayer):
#   * наведение на бойца дольше HOVER_NAME_DELAY — подпись «имя ×бойцов · ур.N»
#     (свои золотом, враги красным; скрытые до боя враги не подписываются);
#   * клик по своему отряду на расстановке — справка-карточка InfoCard (решение пользователя 23.10.2026, образец
#     9 Kings): портрет, имя, бойцы, описание карты, статы бойца, способность, бонусы, улучшения, ряд; синергий
#     в ней нет — они в справке цитадели (клик по цитадели); в бою справки нет (только подпись при наведении);
#     повторный клик или клик мимо — закрыть;
#   * клик по своему зданию на расстановке — такая же карточка (решение пользователя 24.10.2026): иллюстрация
#     карты, название, ур. N/3 ромбиками, что делает с текущими цифрами, можно ли улучшить; пока открыта —
#     здание не гаснет и его зона действия подсвечена (BattleScene._update_building_hover). Здание — только
#     по его клетке, как подсказка при наведении (building_finder).
# Карточка — между top_limit (низ плашки сообщения) и bottom_limit (рука на расстановке), не выше этого места
# (InfoCard.fit); подписи при наведении не ложатся на открытую карточку (_place_clear: сбоку от неё или скрыть),
# подсказки здания при открытой справке здания нет — всё уже в карточке (25.10.2026: налезали друг на друга).
# Опрос мыши и обновление текста — REFRESH_INTERVAL раз в секунду, не каждый кадр.

const HOVER_NAME_DELAY: float = 0.5
const HOVER_HALF_WIDTH: float = 20.0   # полуширина бойца для попадания курсором, px мира
const REFRESH_INTERVAL: float = 0.1
const INFO_WIDTH: float = 220.0
const CELL_PX: float = 78.25   # шаг клетки вдоль оси наступления, px (√(70² + 35²)) — скорость и дальность в клетках
const PORTRAIT_CROP = Rect2(50, 40, 260, 260)   # лицо иллюстрации карты (арт 360×504) — портрет справки
# Подсказки к бафам справки при наведении (решение пользователя 10.11.2026): откуда бонус и что делает
const BONUS_HINTS = {
	"hp": "Больше здоровья каждому бойцу. Даёт уровень отряда (карта того же отряда на него) и карты-улучшения",
	"damage": "Сильнее каждый удар и выстрел. Даёт уровень отряда и карты-улучшения",
	"attack_speed": "Бьёт и стреляет чаще. Даёт уровень отряда и карты-улучшения",
	"move_speed": "Быстрее добегает до врага. Даёт карта-улучшение скорости",
	"shield": "В начале каждого боя бойцы получают щит: он принимает урон первым, пока не кончится",
	"banner": "Аура знамени: союзники рядом с отрядом бьют сильнее. С другими аурами урона не складывается",
}
const POSITION_HINT = "Бонус ряда королевства: зависит от того, в каком ряду стоит отряд — переставьте, чтобы сменить"

# Выключается в конце забега (shutdown)
var enabled: bool = true
# true — клик забран другим (залп орудия игрока): справку не открывать и не закрывать.
# Справка получает клик раньше сцены, поэтому спрашивает её заранее
var click_blocker: Callable
# Здание игрока на клетке под точкой мира или null (задаёт BattleScene — знает сетку)
var building_finder: Callable
# Верх и низ места для справки на экране (задаёт BattleScene: плашка сообщения, рука); не заданы — шапка и низ экрана
var top_limit: Callable
var bottom_limit: Callable
var info_squad: Squad = null
var info_citadel: bool = false   # открыта справка цитадели
var info_building: Building = null

var _hover_panel: PanelContainer
var _hover_text: Label
var _card: InfoCard
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
	_card = InfoCard.new()
	_card.hide()
	add_child(_card)

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
	if BattleManager.is_battle_running():   # справка — только на расстановке
		close_info()
		return
	var world := _screen_to_world(event.position)
	var squad = squad_at(world)
	if squad != null and squad.team == GameConstants.TEAM_PLAYER:
		var same: bool = squad == info_squad
		close_info()
		if not same:
			info_squad = squad
			_update_info()
			squad_info_opened.emit(squad)
		return
	if citadel_at(world):
		var was := info_citadel
		close_info()
		info_citadel = not was
		_update_info()
		return
	var building: Building = building_finder.call(world) if building_finder.is_valid() else null
	if building != null:
		var same_building := building == info_building
		close_info()
		if not same_building:
			info_building = building
			_update_info()
		return
	close_info()

# -------------------------------------------------------
# API
# -------------------------------------------------------
func squad_at(world_pos: Vector2) -> Squad:
	return SquadRegistry.find_squad_at(world_pos, HOVER_HALF_WIDTH)

# Цитадель игрока под точкой мира (её спрайт или блоки — get_occlusion_rect)
func citadel_at(world_pos: Vector2) -> bool:
	return BattleManager.has_citadel() and BattleManager.citadel.get_occlusion_rect().has_point(world_pos)

func close_info() -> void:
	info_squad = null
	info_citadel = false
	info_building = null
	_card.hide()

func is_info_visible() -> bool:
	return _card.visible

# Подсказка по зданию (Building.describe) у точки экрана; пустой текст — скрыть
func show_building_hover(text: String, screen_pos: Vector2) -> void:
	if text == "" or not enabled or info_building != null:
		_building_panel.hide()
		return
	_building_text.text = text
	_building_panel.reset_size()
	_place_clear(_building_panel, screen_pos + Vector2(16, 12))

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
	var text = "%s ×%d" % [squad.data.display_name(), squad.soldiers.size()]
	if squad.team == GameConstants.TEAM_PLAYER and squad.data.squad_level > 0:
		text += " · ур.%d" % squad.data.squad_level
	_hover_text.text = text
	var col: Color = UITheme.GOLD_BRIGHT if squad.team == GameConstants.TEAM_PLAYER else UITheme.RED_BRIGHT
	var boss_col := EnemyWaves.boss_color(squad.data.factory_id)   # примарх — цветом бога / легиона
	if boss_col.a > 0.0:
		col = boss_col
	_hover_text.add_theme_color_override("font_color", col)
	_hover_panel.reset_size()
	var was_visible := _hover_panel.visible
	_place_clear(_hover_panel, screen_pos + Vector2(14, -_hover_panel.size.y - 6))
	if _hover_panel.visible and not was_visible:   # плавное появление подписи (18.11.2026)
		_hover_panel.modulate.a = 0.0
		var tw := _hover_panel.create_tween().set_ignore_time_scale(true)
		tw.tween_property(_hover_panel, "modulate:a", 1.0, 0.12)

const CLEAR_GAP: float = 6.0   # подпись сбоку от открытой карточки — с зазором

# Подпись у точки в пределах экрана; на открытую карточку не ложится — сбоку от неё, не влезла — скрыта
func _place_clear(panel: Control, pos: Vector2) -> void:
	var limit := get_viewport_rect().size - panel.size
	panel.position = pos.clamp(Vector2.ZERO, limit)
	panel.show()
	if not _card.visible:
		return
	var card := Rect2(_card.position, _card.size).grow(CLEAR_GAP)
	if not card.intersects(Rect2(panel.position, panel.size)):
		return
	for x in [card.position.x - panel.size.x, card.end.x]:
		var p := Vector2(x, panel.position.y).clamp(Vector2.ZERO, limit)
		if not card.intersects(Rect2(p, panel.size)):
			panel.position = p
			return
	panel.hide()

# -------------------------------------------------------
# СПРАВКА
# -------------------------------------------------------
func _update_info() -> void:
	if info_squad == null and not info_citadel and info_building == null:
		return
	if BattleManager.is_battle_running():
		close_info()
		return
	var anchor: Vector2
	if info_citadel:
		if not BattleManager.has_citadel():
			close_info()
			return
		_show_citadel_card()
		anchor = _world_to_screen(BattleManager.citadel.global_position)
	elif info_building != null:
		if not is_instance_valid(info_building):
			close_info()
			return
		_show_building_card(info_building)
		anchor = _world_to_screen(info_building.global_position)
	else:
		if not is_instance_valid(info_squad) or not info_squad.is_alive() or info_squad.soldiers.is_empty():
			close_info()
			return
		_show_squad_card(info_squad)
		anchor = _world_to_screen(info_squad.soldiers[0].global_position)
	var screen := get_viewport_rect().size
	var top: float = top_limit.call() + CLEAR_GAP if top_limit.is_valid() else UITheme.HUD_HEIGHT
	var bottom: float = bottom_limit.call() - CLEAR_GAP if bottom_limit.is_valid() else screen.y
	_card.fit(bottom - top)
	_card.reset_size()
	_card.show()
	# Справа от отряда / цитадели / здания, между top и bottom; выше места — от top
	var pos = anchor + Vector2(30, -_card.size.y / 2.0)
	pos.x = clampf(pos.x, 0.0, maxf(screen.x - _card.size.x, 0.0))
	pos.y = maxf(minf(pos.y, bottom - _card.size.y), top)
	_card.position = pos
	# Подписи, открытые раньше карточки, — с неё
	for panel in [_hover_panel, _building_panel]:
		if panel.visible:
			_place_clear(panel, panel.position)
	if info_building != null:
		_building_panel.hide()

func _show_squad_card(squad: Squad) -> void:
	var d = squad.data
	var card := CardFactory.squad_card_for(d.factory_id)
	var alive := squad.soldiers.size()
	var full := maxi(d.squad_size, alive)
	_card.setup(squad_portrait(card), d.display_name(), "×%d" % alive if alive >= full else "×%d/%d" % [alive, full],
		describe(squad), d.squad_level, UnitFactory.MAX_SQUAD_LEVEL,
		UITheme.rarity_color(card.rarity) if card else Palette.GOLD)

func _show_citadel_card() -> void:
	var tex: Texture2D = BattleManager.citadel.get_portrait()
	if tex == null:
		tex = UITheme.ui_icon("hud", "citadel_hp")
	_card.setup(tex, "Цитадель", "%d/%d" % [ceili(BattleManager.citadel_hp), roundi(BattleManager.CITADEL_MAX_HP)],
		describe_citadel(), 0, 0, Palette.GOLD)

func _show_building_card(b: Building) -> void:
	var tex := squad_portrait(b.card)
	if tex == null and b.sprite:
		tex = b.sprite.sprite_frames.get_frame_texture("idle", 0)
	_card.setup(tex, b.card.display_title(), "", describe_building(b), b.card.building_level, CardData.MAX_BUILDING_LEVEL,
		UITheme.rarity_color(b.card.rarity))

# Текст справки здания (BBCode): что делает с текущими цифрами, можно ли улучшить
static func describe_building(b: Building) -> String:
	return "%s

%s" % [InfoCard.color_numbers(b.effect_text(), Palette.AMBER_LIGHT), b.upgrade_text()]

# Портрет справки: лицо иллюстрации карты; арта нет — кадр бойца по силуэту
static func squad_portrait(card: CardData) -> Texture2D:
	if card == null:
		return null
	var art: Texture2D = UITheme.card_art(card)
	if art:
		var a := AtlasTexture.new()
		a.atlas = art
		a.region = PORTRAIT_CROP
		return a
	return UITheme.card_portrait(card)

# Текст справки цитадели (BBCode): прочность, щит стен, синергии армии
static func describe_citadel() -> String:
	var lines: Array[String] = []
	lines.append(InfoCard.stat("Прочность", "%d/%d" % [ceili(BattleManager.citadel_hp), roundi(BattleManager.CITADEL_MAX_HP)]))
	if BattleManager.has_kingdom_wall():
		lines.append(InfoCard.stat("Щит стен в начале боя", "+%d" % roundi(BattleManager.kingdom_wall.get_citadel_shield())))
	lines.append("")
	lines.append("[color=#%s]Синергии армии[/color]" % Palette.GOLD.to_html(false))
	for l in BattleHud.synergy_lines():
		lines.append(InfoCard.color_numbers(l, Palette.AMBER_LIGHT))
	return "\n".join(lines)

# Способность отряда из данных UnitData ("" — нет)
static func ability_text(d: UnitData) -> String:
	if d.special_kind != "":
		return "%s (раз в %d с); ярость на %d%% HP — приём в 1,5 раза чаще%s" % [d.special_name,
			roundi(d.special_cooldown), roundi(Soldier.ENRAGE_AT * 100.0), "; не отбрасывается" if d.knockback_immune else ""]
	if d.jump_range > 0.0:
		return "прыжок на стрелка (раз за бой), удар ×%.1f и оглушение %.1f с" % [d.jump_damage_mult, d.jump_stun]
	if d.entrench_time > 0.0:
		return "окапывание: стоя на месте, до +%d%% урона за %d с" % [roundi(d.entrench_bonus * 100.0), roundi(d.entrench_time)]
	if d.deep_strike_delay > 0.0:
		return "Deep Strike: через %d с боя — к ближайшему врагу" % roundi(d.deep_strike_delay)
	if d.mobile_fire:
		return "стрельба на ходу"
	return ""

# Строка бога отряда Хаоса: «Бог: Дедушка Тысячи» цветом бога (решение пользователя 09.11.2026), дальше — благословения
static func god_line(d: UnitData) -> String:
	var god: String = d.get_god()
	var text := ChaosGods.describe(god, d.blessings, d.tags)
	var head := "Бог: %s" % ChaosGods.god_name(god)
	if not text.begins_with(head):
		return InfoCard.color_numbers(text, Palette.AMBER_LIGHT)
	return "[color=#%s]%s[/color]%s" % [ChaosGods.god_color(god).to_html(false), InfoCard.hint(head, ChaosGods.blessing_hint(god)),
		InfoCard.color_numbers(text.substr(head.length()), Palette.AMBER_LIGHT)]

# Бонус справки: числа цветом, подсказка — откуда бонус и что делает
static func _bonus(text: String, tip: String) -> String:
	return InfoCard.hint(InfoCard.color_numbers(text, Palette.AMBER_LIGHT), tip)

# Число для справки: целое — без дробной части, иначе одна цифра после запятой
static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return str(roundi(v))
	return ("%.1f" % v).replace(".", ",")

# Текст справки (BBCode): описание карты, статы бойца, HP отряда, бонусы множителей UnitData, способность,
# улучшения, ряд. Синергий нет — они в справке цитадели
static func describe(squad: Squad) -> String:
	var d = squad.data
	var lines: Array[String] = []
	var card := CardFactory.squad_card_for(d.factory_id)
	if card and card.description != "":
		lines.append(InfoCard.color_numbers(card.description, Palette.AMBER_LIGHT))
		lines.append("")
	if not squad.soldiers.is_empty():
		var s = squad.soldiers[0]
		lines.append(InfoCard.stat("Здоровье", _num(s.max_hp)))
		lines.append(InfoCard.stat("Урон", _num(s.current_damage)))
		lines.append(InfoCard.stat("Атаки/с", _num(s.current_attack_speed)))
		lines.append(InfoCard.stat("Движение", _num(s.current_move_speed / CELL_PX) + " кл/с"))
		lines.append(InfoCard.stat("Дальность", "вплотную" if s.current_attack_range <= UnitFactory.MELEE_RANGE * 1.5
			else _num(s.current_attack_range / CELL_PX) + " кл"))
	var hp := 0.0
	var max_hp := 0.0
	for soldier in squad.soldiers:
		hp += soldier.current_hp
		max_hp += soldier.max_hp
	lines.append(InfoCard.stat("HP отряда", "%d/%d" % [ceili(hp), ceili(max_hp)]))
	# Бонусы — каждый с подсказкой, откуда он и что делает (числа красятся до [hint] — в подсказку теги не попадают)
	var bonuses: Array[String] = []
	for b in [[d.hp_multiplier, "HP", BONUS_HINTS["hp"]], [d.damage_multiplier, "урона", BONUS_HINTS["damage"]],
			[d.attack_speed_multiplier, "скорострельности", BONUS_HINTS["attack_speed"]],
			[d.move_speed_multiplier, "скорости бега", BONUS_HINTS["move_speed"]]]:
		if b[0] > 1.001:
			bonuses.append(_bonus("+%d%% %s" % [roundi((b[0] - 1.0) * 100.0), b[1]], b[2]))
	if d.shield_ratio > 0.0:
		bonuses.append(_bonus("щит %d%% HP" % roundi(d.shield_ratio * 100.0), BONUS_HINTS["shield"]))
	if d.banner_aura_bonus > 0.0:
		bonuses.append(_bonus("знамя: +%d%% урона рядом" % roundi(d.banner_aura_bonus * 100.0), BONUS_HINTS["banner"]))
	if not bonuses.is_empty():
		lines.append("Бонусы: " + ", ".join(bonuses))
	var ability := ability_text(d)
	if ability != "":
		lines.append("Способность: " + InfoCard.color_numbers(ability, Palette.AMBER_LIGHT))
	if squad.team == GameConstants.TEAM_PLAYER and "chaos" in d.tags and d.get_god() != "":   # бог отряда (ChaosGods)
		lines.append(god_line(d))
	if not d.applied_upgrades.is_empty():
		var ups: Array[String] = []
		for title in d.applied_upgrades:
			ups.append(InfoCard.hint(title, CardFactory.description_by_title(title)))
		lines.append("Улучшения: " + ", ".join(ups))
	# Казармы по соседству (решение пользователя 23.11.2026, обучение): что они сделают с этим отрядом после победы
	if squad.team == GameConstants.TEAM_PLAYER:
		for bcard in BattleManager.player_buildings:
			if bcard.building_type == "barracks" \
					and BattleManager.NEIGHBOUR_TILES.has(squad.tile - BattleManager.player_buildings[bcard]):
				var stats: Dictionary = bcard.get_building_stats()
				var heal := roundi(float(stats.get("heal", 0.0)) * 100.0) if bcard.faction != "chaos" else 0
				var back := floori(float(stats.get("refill", 0.0)))
				var text := "после победы " + ("лечат живых на %d%% и " % heal if heal > 0 else "") \
					+ "возвращают до %d павших бойцов" % back
				lines.append("Казармы рядом: " + InfoCard.color_numbers(text, Palette.AMBER_LIGHT))
	var pos = SynergyManager.get_squad_position_bonus(squad)
	if pos != "":
		var p: Dictionary = SynergyManager.POSITION_BONUSES[pos]
		lines.append("%s: %s" % [InfoCard.hint(p["name"], POSITION_HINT), InfoCard.color_numbers(p["desc"], Palette.AMBER_LIGHT)])
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
