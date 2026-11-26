class_name Tutorial
extends Node

# Обучение (решение пользователя 23.11.2026, второй вариант — сценарий вместо россыпи подсказок).
# Два наставника в углах поля: слева алхимик Космодесанта («Вагнер»), справа козлоногий торговец Хаоса; они спорят и
# тянут нового короля каждый на свою сторону, и по очереди учат. Сценарий волн 1–2 (Stage):
#   INTRO         — приветствие и лор (клик — следующая реплика), стартовый выбор;
#   PICK          — три рубашки, всегда пехота, Казармы и лекарь (ShopManager.open_pick → start_cards);
#   PLACE_UNIT    — карта пехоты и клетка подсвечены, ставить можно только их; после — как идёт бой;
#   TRAIN_BATTLE  — учебный бой, враг слабый (training_specs) — игрок выигрывает всегда;
#   PLACE_BARRACKS— наставник Космодесанта: Казармы рядом с отрядом (карта и клетка подсвечены);
#   CLICK_SQUAD   — «пауза» (бой не начнётся, holds_start): нажми на отряд — в справке видно действие Казарм;
#   WAVES         — волны 2–4: обычные подсказки по событиям (STEPS), каждая один раз; выбор карты после боя (открыть 2, взять 1),
#                   зачем нужны монеты, событие (EventScene — `show_event_intro`);
#   SHOP_BUY      — первый магазин (после события волны 4): наставники объясняют монеты, в первом слоте — орудие (Thunderfire /
#                   Phlegethon Mortar), оно подсвечено, «В БОЙ» держится, пока оно не куплено (`apply_scripted_shop`, `shop_holds`);
#   PLACE_CANNON  — расстановка волны 5: как работает орудие, карта и клетка подсвечены; потом объявление босса и предупреждение;
#   BOSS          — бой с боссом волны 5: подсказка «кликни по полю — залп»; победа → DONE;
#   DONE          — обучение окончено.
# Слова и картинка совпадают (решение пользователя 25.11.2026): реплика про цитадель — наезд камеры и кольцо, про монеты — пульсирует
# счётчик, про обновление — кнопка «Обновить» (LINE_FOCUS, по началу текста реплики); Казармы — подсвечена их зона; выбор перед
# волной 2 — обязательная карта пехоты; волна 4 — урок о прокачке: карта пехоты на отряд, карта Казарм на Казармы (нет карты — выдаётся).
# Не Autoload: создаёт BattleScene и удаляет вместе с собой. Прогресс — GameSettings.tutorial_stage / tutorial_seen,
# выключатель — «Обучение» в настройках, «Пропустить обучение» на экране. Не идёт в тестовом режиме и headless.
# Новая подсказка — строка в STEPS, новая реплика сценария — в *_LINES.

enum Stage { INTRO, PICK, PLACE_UNIT, TRAIN_BATTLE, PLACE_BARRACKS, CLICK_SQUAD, WAVES, SHOP_BUY, PLACE_CANNON, BOSS, DONE }

const LAYER: int = 6                 # над окнами магазина / выбора карты (BattleScene.SHOP_LAYER 5), под паузой
const AREA_SIZE := Vector2(270, 470) # окно наставника: фигура и облако над ней
const AREA_MARGIN: float = 8.0
const FADE: float = 0.25
const READ_TIME: float = 5.0         # минимум сек, пока реплика-подсказка висит на экране (решение пользователя 25.11.2026)
const HOLD_EXTRA: float = 0.9        # сек после облака подсказки до ухода наставника
const DIALOGUE_HOLD: float = 3600.0  # реплика диалога висит, пока игрок не кликнет
const DIM := Palette.TUTORIAL_DIM
const SKIP_TEXT := "Пропустить обучение"
const CLICK_TEXT := "Нажмите, чтобы продолжить"
const TRAINING_COUNT_MAX: int = 3    # бойцов в учебном отряде врага
const TRAINING_MULT: float = 0.5     # их множитель HP и урона
const TRIAL_WAVE: int = 5            # волна 5 — простые враги: игрок пробует орудие
const TRIAL_MULT: float = 0.6        # их множитель HP и урона
const BOSS_WAVE: int = 6             # волна 6 — ослабленный примарх
const BOSS_MULT: float = 0.2         # его множитель HP и урона (обычный на волне 15 — ×2.4)

const UNIT_CARD := "tactical_squad"
const BARRACKS_CARD := "barracks"
const LEAD_CARD := "apothecary"
const CANNON_CARD := "thunderfire_cannon"   # у Хаоса — Phlegethon Mortar (CardFactory.equivalent)
const EVENT_CARD := "emergency_reinforcements"   # у Хаоса — Masquerade Rising: карта-событие, выбор после 2-го боя
const RARE_CARD := "devastator_squad"             # у Хаоса — Havocs: редкая карта, выбор после 3-го боя
const UNIT_PICK_WAVE: int = 2    # выбор перед волной 2 — вторая карта пехоты (на ней урок о прокачке)
const EVENT_PICK_WAVE: int = 3   # выбор перед волной 3 — после 2-го боя
const RARE_PICK_WAVE: int = 4    # перед волной 4 — после 3-го
const START_DEALT: int = 6           # рубашек в учебном стартовом выборе; выпадают всегда стандартные три

# Реплики сценария: [кто ("chaos" / "marine"), текст]
const INTRO_LINES: Array = [
	["chaos", "Еще один царек пришел! Быстрей проходи, правда трон шаткий смотри не упади ха-ха-ха-ха."],
	["marine", "Не слушай его, государь. Я — Вагнер, алхимик Ретортариев. Мы давно ждали достойного правителя, сильного и дальновидного."],
	["chaos", "Да. Только кто сказал, что он такой? Это королевство давно стало тюрьмой, впрочем, как и весь мир."],
	["marine", "Иди к чёрту, козёл. А ты его не слушай. В мире всегда есть место свету и надежде. Сейчас светом и надеждой этого мира избрали тебя."],
	["marine", "Видишь цитадель внизу слева? Это сердце твоего королевства, ты не должен дать ему пасть. Для этого ты можешь строить здания и нанимать войска. Сейчас я покажу тебе, как это делать."],
	["chaos", "Вся твоя власть — куча камней, милый король, умри поскорей. ХА-ХА-ХА-ХА."],
	["marine", "Чёртов козёл. Не слушай его. Начнём с азов."],
]
const PLACE_UNIT_LINES: Array = [
	["marine", "Видишь светящуюся карту в руке? Это отряд Криспинов — стандартная стрелковая пехота. Возьми её и выставь на поле брани."],
]
const AFTER_UNIT_LINES: Array = [
	["chaos", "Солдат первый стал на бой. Споем ему за упокой, ха-ха-ха!"],
	["marine", "Впереди небольшой отряд, наши Криспины легко с ним справятся."],
]
const BARRACKS_LINES: Array = [
	["marine", "У тебя в руке есть карта Казарм. Казармы лечат бойцов в отряде и воскрешают некоторых."],
	["marine", "Поставь Казармы рядом с Криспинами. Обрати внимание на радиус их действия."],
]
const PICK_START_HINT := "Шесть карт пред тобой — ты три поверни. Они в руку все лягут, смотри, не проспи!"
const PICK_START_LINES: Array = [
	["chaos", PICK_START_HINT],
	["marine", "В начале пути тебе на выбор даётся 6 карт: вскрываешь 3 и забираешь их. Дальше, почти после каждого боя, на выбор будут давать 4 карты."],
]
# Урок про прокачку (волна 4, расстановка): отряды — картой того же отряда на отряд, здания — картой того же здания на здание
const UPGRADE_WAVE: int = 4
const UPGRADE_LINES: Array = [
	["marine", "Вот тебе карта Криспинов. Одинаковые карты складываются: брось карту отряда на такой же отряд на поле."],
	["marine", "Уровень отряда вырастет, а часть жизней восстановится. Если отряды не лечить, они погибнут, а на их место придут менее опытные солдаты."],
	["chaos", "Опытный боец — скоро новенький мертвец."],
	["marine", "Держи ещё карту Казарм. Со зданиями так же. Предел у всего — третий уровень."],
	["chaos", "Король отстроить город обещал, жаль лишь, что он в гроб сыграл! Ха-ха-ха!"],
]
# Что показать игроку, пока наставник говорит реплику (решение пользователя 25.11.2026: слова и картинка совпадают).
# Ключ — начало текста реплики (сами реплики не трогаем), значение — цель показа: citadel (наезд камеры и кольцо),
# coins (пульсирует счётчик монет), reroll (пульсирует «Обновить»)
const LINE_FOCUS: Array = [
	["Видишь цитадель", "citadel"],
	["Вся твоя власть", "citadel"],
	["Береги цитадель", "citadel"],
	["После каждого боя ты получаешь определённое", "coins"],
	["Монеты нужны", "coins"],
	["Звон монет", "coins"],
	["Если вдруг карты кончились", "reroll"],
]
const FOCUS_ZOOM: float = 1.7
const FOCUS_TIME: float = 0.7
const PULSE_COLOR := Palette.TUTORIAL_PULSE
const UPGRADE_UNIT_DONE := "Так и расти отряды и здания: улучшенный отряд лучше по характеристикам, улучшенные здания дают больше бонусов."
const UPGRADE_BUILDING_DONE := "Здание улучшено: эффект сильнее, радиус и урон растут. Третий уровень — предел."
const PICK_LINES: Array = [
	["marine", "После каждого боя тебе даётся 4 карты на выбор. Вскрываешь ты 2, но забираешь 1."],
	["chaos", "Наш король и глуп, и смел — карточку стащить сумел. Хе-хе-хе."],
	["marine", "После каждого боя ты получаешь определённое количество монет: чем сложнее бой, тем больше награда."],
	["marine", "Монеты нужны, чтобы покупать новые владения королевства, а также карты в магазине. Но об этом позже."],
	["chaos", "Звон монет тебя заманит и на кладбище утянет!"],
]
const EVENT_LINES: Array = [
	["marine", "Иногда между боями происходят катаклизмы или другие события мира. У тебя есть выбор, как поступить."],
	["chaos", "На перепутье наш король! Он в гробу одной ногой!"],
	["marine", "Читай внимательно. Событие не переиграть: выбрал — и последствия твои, на ближайший бой или на весь забег."],
]
const SHOP_LINES: Array = [
	["marine", "А вот и важнейшая часть! Магазин! Тут я предлагаю тебе карты на выбор, покупать можно до 10 штук."],
	["marine", "Если вдруг карты кончились, ты можешь обновить ассортимент! Первый раз бесплатно, потом мне придётся повысить цены."],
	["marine", "Купи сейчас {cannon}, оно тебе пригодится."],
]
const CANNON_LINES: Array = [
	["marine", "Это {cannon}. Здание, но не простое: стреляешь из него ты сам."],
	["marine", "Поставь на подсвеченную клетку. В бою клик по полю — залп: снаряд упадёт туда и накроет всех в радиусе прицела."],
	["marine", "Перезарядка — четыре секунды. Бей в самую густую толпу."],
]
const BOSS_LINES: Array = [
	["chaos", "А теперь новость, король: следующий бой — с боссом. Не толпа, а один большой, злой и очень крепкий."],
	["marine", "Береги цитадель: дойдёт до неё и пробьёт — забег кончен. Бей по боссу из орудия и по тем, кто идёт рядом."],
	["chaos", "Ну, ни пуха. Жми «В БОЙ»."],
]
const PICK_EVENT_LINES: Array = [
	["marine", "Не все карты ставят солдат или здания. Некоторые улучшают других или воздействуют на врага."],
]
const EVENT_CARD_LINES: Array = [
	["marine", "Это карта подмоги, она присылает случайный обычный отряд тебе на выручку."],
]
const EVENT_CARD_DONE := "Подмога пришла: случайный обычный отряд встал на клетку, карта сгорела. Бывают карты и посильнее — они сработают в начале боя."
const EVENT_CARD_BUY := "Сейчас у тебя есть монеты. Можешь купить себе новые клетки, чтобы в будущем ставить на них свои здания и войска."
const PICK_RARE_LINES: Array = [
	["marine", "Взгляни на рамки карт: у каждой своя редкость. Обычные — самые частые и дешёвые, редкие — сильнее и дороже, эпические — самые мощные и самые редкие."],
	["marine", "Цвет рамки и значок в углу подскажут редкость. Дорогая карта не всегда лучше — но редкая и редко подводит."],
]
const CANNON_HINT := "Клик по полю — залп из орудия. Бей туда, где врагов больше всего."
const CLICK_NOTE := "Кликни на свой отряд и посмотри, как на него действуют Казармы."
const AFTER_INFO_LINES: Array = [
	["chaos", "Камень к камню, вот и дом. Мертвецам уютно в нём."],
]

# Подсказки по событиям (после сценария и на волнах 2–4); who — кто говорит (по умолчанию Хаос)
const STEPS: Array = [
	{"id": "w2_pick", "event": "pick", "wave_min": 2, "wave_max": 2, "lines": PICK_LINES,
		"text": "Четыре рубашки. Открой две, возьми одну, остальные сгорят. Жадность — дело честное, но выбирать надо."},
	{"id": "w3_pick_event", "event": "pick", "wave_min": 3, "wave_max": 3, "lines": PICK_EVENT_LINES, "text": ""},
	{"id": "w4_pick_rare", "event": "pick", "wave_min": 4, "wave_max": 4, "lines": PICK_RARE_LINES, "text": ""},
	{"id": "w3_place", "event": "placement", "wave_min": 3, "wave_max": 3,
		"text": "Одинаковые теги — синергия: чем больше своих рядом в армии, тем сильнее бонус. Клик по цитадели покажет список."},
	{"id": "w3_expansion", "event": "expansion", "wave_min": 2, "wave_max": 3,
		"text": "Пришло время расширяться. Клетки у края твоих владений продаются, цена на плашке. Монеты зря не лежат."},
	{"id": "merge", "event": "merge", "wave_min": 1, "wave_max": 15, "who": "marine",
		"text": UPGRADE_UNIT_DONE},
	{"id": "building_level", "event": "building_level", "wave_min": 1, "wave_max": 15, "who": "marine",
			"text": UPGRADE_BUILDING_DONE},
	{"id": "shop", "event": "shop", "wave_min": 1, "wave_max": 15,
		"text": "Мой прилавок. Монеты сюда, карты туда. «Обновить» дёргает цепь, но стоит монет. Лишнее продай — мешок проглотит. Потом «В БОЙ»."},
]

var wave: int = 1                    # волна ближайшего боя (BattleScene.battle_wave)
var scene: Node                      # BattleScene: bench, renderer, iso_grid, _show_message, tutorial_release
var vendors: Dictionary = {}         # "chaos" / "marine" → ShopVendor
var target_id: String = ""           # карта, которую игрок должен сыграть (подсвечена)
var target_tile: Vector2i = Vector2i(-99, -99)

var _holders: Dictionary = {}
var _catcher: ColorRect
var _skip: Button
var _tweens: Dictionary = {}
var _lines: Array = []
var _line_i: int = 0
var _on_done: Callable = Callable()
var _dialogue_active: bool = false
var _pulse_nodes: Array = []         # элементы, которые пульсируют, пока наставник на них показывает
var _ring: Node2D = null             # кольцо вокруг цитадели
var _camera_moved: bool = false
var _speaker: ShopVendor = null          # диалог ведёт торговец магазина (не наставники в углах)
var _glows: Array = []               # рамки подсветки поверх затемнения
var _upgrade_step: int = 0           # урок о прокачке: 0 — не идёт, 1 — отряд, 2 — здание

# ---------- Состояние (статические — ими пользуются ShopManager, ShopScene и тесты) ----------
# Сценарий идёт: не тестовый режим, не headless (тесты), включён игроком, до конца сценария
static var force_for_tests: bool = false   # тесты в headless включают сценарий сами

# Забег идёт, а сценарий в нём так и не начинался (сохранение из прошлой версии; обучение включили посреди забега):
# обучение молчит до нового забега (решение пользователя 26.11.2026 — иначе у такого забега пропадал автостарт боя и
# орудие не выпадало). Новый забег узнаётся по стартовому выбору, дальше него сценарий всегда уже не на INTRO
static func dormant() -> bool:
	return GameSettings.tutorial_stage == Stage.INTRO and not RunManager.is_start_pick_active()

static func scripted_active() -> bool:
	if RunManager.test_mode or (DisplayServer.get_name() == "headless" and not force_for_tests) or dormant():
		return false
	return GameSettings.tutorial_enabled and GameSettings.tutorial_stage < Stage.DONE

static func scripted_pick_active() -> bool:
	return scripted_active() and GameSettings.tutorial_stage <= Stage.PICK

# Обучение вообще нужно (сценарий или непоказанные подсказки)
static func is_active() -> bool:
	if RunManager.test_mode or DisplayServer.get_name() == "headless" or not GameSettings.tutorial_enabled or dormant():
		return false
	return GameSettings.tutorial_stage < Stage.DONE or not _unseen().is_empty()

# Три карты первого выбора по расе игрока: пехота, Казармы, лекарь
static func start_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	for id in [UNIT_CARD, BARRACKS_CARD, LEAD_CARD]:
		var c: CardData = CardFactory.equivalent(id, RunManager.player_faction)
		if c != null:
			out.append(c)
	return out

static func _unseen() -> Array:
	var out: Array = []
	for s in STEPS:
		if not GameSettings.tutorial_seen.has(s["id"]):
			out.append(s)
	return out

# Карты, которых игрок получить не должен до своего времени: орудие (Thunderfire / Mortar) — только покупкой в первом магазине
static func hidden_card_ids() -> Array:
	if RunManager.test_mode or (DisplayServer.get_name() == "headless" and not force_for_tests) or not GameSettings.tutorial_enabled 			or dormant():
		return []
	if GameSettings.tutorial_stage >= Stage.PLACE_CANNON:
		return []
	var out: Array = []
	for faction in ["space_marines", "chaos"]:
		var c := CardFactory.equivalent(CANNON_CARD, faction)
		if c != null:
			out.append(c.id)
	return out

# Учебный выбор карты (после 2-го боя — событие, после 3-го — редкая): карта, которая обязана выпасть и которую надо взять
static func pick_target_card() -> CardData:
	if not scripted_active() or not RunManager.is_pick_node_active() or RunManager.is_start_pick_active():
		return null
	var w: int = RunManager.get_battle_wave()
	var stage: int = GameSettings.tutorial_stage
	# выбор перед волной 2 открывается сразу после учебного боя — стадия ещё «поставь Казармы»
	if stage != Stage.WAVES and not (stage == Stage.PLACE_BARRACKS and w == UNIT_PICK_WAVE):
		return null
	if w == UNIT_PICK_WAVE and not GameSettings.tutorial_seen.has("pick_unit_done"):
		return CardFactory.equivalent(UNIT_CARD, RunManager.player_faction)
	if w == EVENT_PICK_WAVE and not GameSettings.tutorial_seen.has("pick_event_done"):
		return CardFactory.equivalent(EVENT_CARD, RunManager.player_faction)
	if w == RARE_PICK_WAVE and not GameSettings.tutorial_seen.has("pick_rare_done"):
		return CardFactory.equivalent(RARE_CARD, RunManager.player_faction)
	return null

# Урок о редкости (выбор перед волной 4): игроку выпадают две редкие карты, берёт любую из них
static func is_rare_lesson() -> bool:
	var t := pick_target_card()
	return t != null and RunManager.get_battle_wave() == RARE_PICK_WAVE

# Эту карту обучение разрешает взять? (обязательная; на уроке редкости — любая редкая)
static func pick_accepts(card: CardData) -> bool:
	var t := pick_target_card()
	if t == null:
		return true
	if card.id == t.id:
		return true
	return is_rare_lesson() and card.rarity == "rare"

static func pick_hint() -> String:
	var t := pick_target_card()
	if t == null:
		return ""
	if is_rare_lesson():
		return "Наставник: возьми любую из двух редких карт"
	return "Наставник: возьми «%s»" % t.display_title()

# Вторая редкая карта урока: другая редкая отряда из пула (не орудие и не обязательная)
static func second_rare_card(target: CardData, offered: Array = []) -> CardData:
	var hidden := hidden_card_ids()
	var pool: Array = CardFactory.build_pool().filter(func(c): return c.rarity == "rare" and c.card_type == "squad" 		and c.id != target.id and not hidden.has(c.id) and not offered.any(func(o): return o.id == c.id) and MetaProgress.is_card_unlocked(c.id))
	if pool.is_empty():
		return null
	return pool[RunManager.rng.randi_range(0, pool.size() - 1)]

static func mark_pick_taken(card: CardData) -> void:
	if card == null:
		return
	var unit := CardFactory.equivalent(UNIT_CARD, RunManager.player_faction)
	if unit != null and card.id == unit.id and RunManager.get_battle_wave() == UNIT_PICK_WAVE:
		GameSettings.mark_tutorial_seen("pick_unit_done")
	elif card.card_type == "event":
		GameSettings.mark_tutorial_seen("pick_event_done")
	elif card.rarity == "rare":
		GameSettings.mark_tutorial_seen("pick_rare_done")

# Первый магазин обучения: после события волны 4, сценарий дошёл до волн (WAVES) или уже в магазине (SHOP_BUY)
static func scripted_shop_stage() -> bool:
	if not scripted_active() or not RunManager.is_shop_node_active():
		return false
	var s: int = GameSettings.tutorial_stage
	return s == Stage.WAVES or s == Stage.SHOP_BUY

# Первый магазин обучения: купить можно только орудие, обновлять нельзя (решение пользователя 25.11.2026)
static func shop_blocks(card: CardData) -> bool:
	if not scripted_shop_stage():
		return false
	var cannon := cannon_card()
	return cannon != null and card.id != cannon.id

static func shop_reroll_blocked() -> bool:
	return scripted_shop_stage()

# Орудие куплено — магазин уходит сам, обучение идёт дальше
static func shop_auto_leave(hand: Array) -> bool:
	if not scripted_active() or not RunManager.is_shop_node_active():
		return false
	var s: int = GameSettings.tutorial_stage
	var cannon := cannon_card()
	return s >= Stage.WAVES and s <= Stage.PLACE_CANNON and cannon != null and hand.any(func(c): return c.id == cannon.id)

# Что говорит наставник, когда игрок вскрыл две карты и среди них нужная
static func pick_say() -> String:
	var t := pick_target_card()
	if t == null:
		return ""
	if is_rare_lesson():
		return "Обе карты редкие, видишь, как они светятся? Бери любую — они подсвечены."
	if t.card_type == "event":
		return "Вот она — карта подмоги! Бери именно её, она подсвечена."
	return "Бери «%s» — она подсвечена." % t.display_title()

static func pick_scold() -> String:
	var t := pick_target_card()
	if t == null:
		return ""
	if is_rare_lesson():
		return "Не туда! Мне нужна одна из редких, подсвеченных карт."
	return "Эй, не туда! Тебе нужна подсвеченная карта — «%s». Остальные не трогай!" % t.display_title()

static func cannon_card() -> CardData:
	return CardFactory.equivalent(CANNON_CARD, RunManager.player_faction)

# Учебный магазин: в первом слоте — орудие (ShopManager.open_shop), денег нет — оно бесплатно
static func apply_scripted_shop() -> void:
	if not scripted_shop_stage():
		return
	var cannon := cannon_card()
	if cannon == null or ShopManager.current_offers.is_empty():
		return
	ShopManager.current_offers[0] = cannon
	if EconomyManager.requisition < cannon.cost:
		ShopManager.free_cards_left = maxi(ShopManager.free_cards_left, 1)

# «В БОЙ» магазина держится, пока орудие не куплено (hand — рука магазина, ShopScene.purchased_cards)
static func shop_holds(hand: Array) -> bool:
	if not scripted_active() or GameSettings.tutorial_stage != Stage.SHOP_BUY:
		return false
	var cannon := cannon_card()
	return cannon != null and not hand.any(func(c): return c.id == cannon.id)

# Реплика наставников в сцене события (EventScene — отдельная сцена, не BattleScene): один раз за забег обучения
static func show_event_intro(parent: Node) -> void:
	if RunManager.test_mode or DisplayServer.get_name() == "headless" or not GameSettings.tutorial_enabled or dormant():
		return
	if GameSettings.tutorial_seen.has("event_intro") or GameSettings.tutorial_stage >= Stage.DONE:
		return
	GameSettings.mark_tutorial_seen("event_intro")
	var t := Tutorial.new()
	t.setup(parent, RunManager.get_battle_wave())
	t._dialogue(EVENT_LINES)

# Первый непоказанный шаг события для волны; null — нечего показывать
static func find_step(event: String, at_wave: int) -> Variant:
	for s in STEPS:
		if s["event"] == event and at_wave >= int(s["wave_min"]) and at_wave <= int(s["wave_max"]) \
				and not GameSettings.tutorial_seen.has(s["id"]):
			return s
	return null

# Реплика для вендора, который уже стоит в сцене (магазин): текст шага или "" — и шаг помечается показанным
static func take_line(event: String, at_wave: int) -> String:
	if RunManager.test_mode or DisplayServer.get_name() == "headless" or not GameSettings.tutorial_enabled or dormant():
		return ""
	if event == "shop" and scripted_shop_stage():   # первый магазин ведёт Tutorial (shop_open), не реплика продавца
		return ""
	var step: Variant = find_step(event, at_wave)
	if step == null:
		return ""
	GameSettings.mark_tutorial_seen(step["id"])
	return step["text"]

# ---------- Сборка ----------
func setup(parent: Node, start_wave: int) -> void:
	wave = start_wave
	scene = parent
	name = "Tutorial"
	parent.add_child(self)
	if RunManager.is_start_pick_active() and GameSettings.tutorial_stage < Stage.DONE:
		GameSettings.tutorial_seen.clear()   # брошенное на середине обучение не должно прятать уроки
		GameSettings.set_tutorial_stage(Stage.INTRO)   # забег начался — сценарий с начала
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	add_child(layer)
	_catcher = ColorRect.new()
	_catcher.color = DIM
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(_catcher)
	_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catcher.gui_input.connect(_on_catcher_input)
	_catcher.visible = false
	var click := Label.new()
	click.text = CLICK_TEXT
	click.theme = UITheme.get_theme()
	click.add_theme_font_size_override("font_size", UITheme.text_px(14))
	click.add_theme_color_override("font_color", Palette.AMBER_LIGHT)
	click.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catcher.add_child(click)
	click.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	click.grow_horizontal = Control.GROW_DIRECTION_BOTH
	click.offset_top = -UITheme.BENCH_PEEK - 20.0   # было −36: на выборе 3 карт надпись налезала на нижний край карт
	click.add_theme_color_override("font_outline_color", Palette.OUTLINE)
	click.add_theme_constant_override("outline_size", 4)
	click.offset_bottom = click.offset_top + 24.0
	_make_holder("marine", "space_marines", true, layer)
	_make_holder("chaos", "chaos", false, layer)
	_skip = UITheme.make_button(SKIP_TEXT, "", _on_skip)
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.theme = UITheme.get_theme()   # слой не наследует тему: без неё кнопка — системным шрифтом и плоской серой плашкой
	layer.add_child(_skip)
	_skip.custom_minimum_size = Vector2(190, 30)
	_skip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_skip.offset_left = -200.0
	_skip.offset_right = -10.0
	_skip.offset_top = UITheme.HUD_HEIGHT + 8.0
	_skip.offset_bottom = _skip.offset_top + 30.0
	_skip.visible = false

# Наставник в углу: left — слева, иначе справа; фигура — продавец расы, вывеска «Обновить» скрыта
func _make_holder(who: String, faction: String, left: bool, layer: CanvasLayer) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.anchor_left = 0.0 if left else 1.0
	holder.anchor_right = holder.anchor_left
	var off := AREA_MARGIN if left else -AREA_MARGIN - AREA_SIZE.x
	holder.offset_left = off
	holder.offset_right = off + AREA_SIZE.x
	holder.offset_bottom = -UITheme.BENCH_PEEK - AREA_MARGIN
	holder.offset_top = holder.offset_bottom - AREA_SIZE.y
	var v := ShopVendor.new()
	holder.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.setup(faction, null)
	v.sign_node.visible = false
	v.figure.set_flipped(left)   # наставник слева смотрит вправо — на карты (лист нарисован лицом влево)
	holder.modulate.a = 0.0
	holder.visible = false
	vendors[who] = v
	_holders[who] = holder

# ---------- События ----------
# Событие игры → сценарий или подсказка. ctx — карта (card_played)
func notify(event: String, ctx: Variant = null) -> void:
	if not GameSettings.tutorial_enabled or _dialogue_active or (event != "pick_start" and dormant()):
		return
	if _upgrade_step > 0 and (event == "merge" or event == "building_level"):   # урок о прокачке говорит об этом сам
		return
	var stage: int = GameSettings.tutorial_stage
	match event:
		"pick_start":
			if stage <= Stage.PICK:
				_on_pick_start(stage)
				return
		"placement":
			if _on_placement(stage):
				return
		"card_played":
			if _on_card_played(stage, ctx):
				return
		"squad_info":
			if stage == Stage.CLICK_SQUAD:
				_dialogue(AFTER_INFO_LINES, func():
					_set_stage(Stage.WAVES)
					_release())
				return
		"pick_ready":
			if pick_target_card() != null:
				for h in ctx.call("tutorial_holders"):
					_pulse_add(h)
					_glow_add(h)
				hint("marine", pick_say())
				return
		"pick_wrong":
			if pick_target_card() != null:
				hint("marine", pick_scold())
				return
		"battle_won":
			if stage == Stage.TRAIN_BATTLE:
				_set_stage(Stage.PLACE_BARRACKS)
				hint("marine", "Первая победа. Да здравствует Король! Давай теперь поставим здания.")
				return
			if stage == Stage.PLACE_CANNON and GameSettings.tutorial_seen.has("cannon_placed"):
				if wave >= BOSS_WAVE:   # победа с орудием пришла позже волны учебного босса — объявлять уже некого
					_set_stage(Stage.DONE)
					return
				_set_stage(Stage.BOSS)
				hint("marine", "Орудие в деле! Дальше — самое трудное.")
				return
			if stage == Stage.BOSS and wave >= BOSS_WAVE:
				_set_stage(Stage.DONE)
				hint("chaos", "Босс повержен! Дальше сам, король. Ещё десять волн — и примарх. Не жалей монет.", 6.0)
				return
		"battle_start":
			if (stage == Stage.BOSS and wave >= BOSS_WAVE) or stage == Stage.PLACE_CANNON:
				hint("marine", CANNON_HINT, 7.0)
				return
		"shop_open":
			if stage == Stage.WAVES or stage == Stage.SHOP_BUY:
				_set_stage(Stage.SHOP_BUY)
				GameSettings.mark_tutorial_seen("shop")
				_dialogue(_fmt(SHOP_LINES), Callable(), _shop_vendor())
				return
	var step: Variant = find_step(event, wave)
	if step != null:
		GameSettings.mark_tutorial_seen(step["id"])
		if step.has("lines"):
			_dialogue(step["lines"])
		else:
			hint(str(step.get("who", "chaos")), step["text"])

func _on_pick_start(stage: int) -> void:
	if stage == Stage.INTRO:
		_dialogue(INTRO_LINES, func():
			_set_stage(Stage.PICK)
			_deal_cards()   # шесть карт появляются на реплике про них — до этого видно только поле
			_dialogue(PICK_START_LINES))
	else:
		hint("chaos", PICK_START_HINT)

# true — расстановка обработана сценарием
func _on_placement(stage: int) -> bool:
	if wave == 1 and (stage == Stage.PICK or stage == Stage.PLACE_UNIT):
		if _hand_card(UNIT_CARD) == null:   # карты нет (сохранение, чужая игра) — сценарий не нужен
			_set_stage(Stage.WAVES)
			return false
		_set_stage(Stage.PLACE_UNIT)
		_dialogue(PLACE_UNIT_LINES, func(): _set_target(_hand_card(UNIT_CARD), _free_tile_for_unit()))
		return true
	if stage == Stage.PLACE_BARRACKS and wave >= 2:
		var tile := _free_tile_beside_squad()
		if _hand_card(BARRACKS_CARD) == null or tile == IsoGridRenderer.NO_TILE:
			_set_stage(Stage.WAVES)
			return false
		_dialogue(BARRACKS_LINES, func(): _set_target(_hand_card(BARRACKS_CARD), tile))
		return true
	if stage == Stage.CLICK_SQUAD:   # «Продолжить»: бой держится до клика по отряду — напомнить о нём
		if SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER).is_empty():
			_set_stage(Stage.WAVES)
			return false
		hint("marine", CLICK_NOTE, DIALOGUE_HOLD)
		return true
	if stage == Stage.WAVES and wave >= UPGRADE_WAVE and not GameSettings.tutorial_seen.has("upgrade_done"):
		return _start_upgrade_lesson()
	if stage == Stage.WAVES and not GameSettings.tutorial_seen.has("event_card_played"):
		var ev := CardFactory.equivalent(EVENT_CARD, RunManager.player_faction)
		var ev_in_hand: CardData = null
		for c in BattleManager.pending_cards:
			if ev != null and c.id == ev.id:
				ev_in_hand = c
		var ev_tile := _free_tile_beside_squad()
		if ev_tile == IsoGridRenderer.NO_TILE:
			ev_tile = _free_tile_for_unit()
		if ev_in_hand != null and ev_tile != IsoGridRenderer.NO_TILE:
			_dialogue(EVENT_CARD_LINES, func(): _set_target(ev_in_hand, ev_tile))
			return true
	if stage == Stage.PLACE_CANNON:
		var cannon := cannon_card()
		var cannon_in_hand: CardData = null
		for c in BattleManager.pending_cards:
			if cannon != null and c.id == cannon.id:
				cannon_in_hand = c
		var cannon_tile := _free_tile_beside_squad()
		if cannon_tile == IsoGridRenderer.NO_TILE:
			cannon_tile = _free_tile_for_unit()
		if GameSettings.tutorial_seen.has("cannon_placed"):
			return false
		if cannon_in_hand == null or cannon_tile == IsoGridRenderer.NO_TILE:   # орудия нет или ставить некуда — дальше без него
			GameSettings.mark_tutorial_seen("cannon_placed")
			_set_stage(Stage.BOSS)
			return false
		_dialogue(_fmt(CANNON_LINES), func(): _set_target(cannon_in_hand, cannon_tile))
		return true
	if stage == Stage.BOSS and wave >= BOSS_WAVE and not GameSettings.tutorial_seen.has("boss_intro"):
		GameSettings.mark_tutorial_seen("boss_intro")
		_dialogue(BOSS_LINES, func(): _release())
		return true
	return false

func _on_card_played(stage: int, card: Variant) -> bool:
	if card == null or target_id == "" or card.id != target_id:
		return false
	_clear_target()
	if stage == Stage.PLACE_UNIT:
		_dialogue(AFTER_UNIT_LINES, func():
			_set_stage(Stage.TRAIN_BATTLE)
			_release())
		return true
	if stage == Stage.PLACE_BARRACKS:
		_set_stage(Stage.CLICK_SQUAD)
		hint("marine", CLICK_NOTE, DIALOGUE_HOLD)
		return true
	if stage == Stage.WAVES and _upgrade_step > 0:
		return _on_upgrade_played()
	if stage == Stage.WAVES and card.card_type == "event":
		GameSettings.mark_tutorial_seen("event_card_played")
		hint("marine", EVENT_CARD_DONE, 7.0)
		get_tree().create_timer(7.9, false).timeout.connect(func():   # вторая реплика — про покупку клеток, когда первая ушла
			if is_instance_valid(self) and GameSettings.tutorial_enabled and GameSettings.tutorial_stage == Stage.WAVES:
				hint("marine", EVENT_CARD_BUY, READ_TIME))
		return true
	if stage == Stage.PLACE_CANNON:
		GameSettings.mark_tutorial_seen("cannon_placed")
		hint("marine", "Орудие стоит. Теперь «В БОЙ» — и клик по полю: залп!")
		_release()
		return true
	return false

# ---------- Урок о прокачке (волна 4) ----------
# Шаг 1: карта пехоты — на свой отряд (уровень +1), шаг 2: карта Казарм — на Казармы. Карты, которых нет в руке, наставник выдаёт
func _start_upgrade_lesson() -> bool:
	var squad_tile := _tile_of_squad(UNIT_CARD)
	var unit: CardData = _ensure_in_hand(UNIT_CARD) if squad_tile != IsoGridRenderer.NO_TILE else null
	if unit == null:   # отряда, который можно улучшить или вылечить, нет, или рука полна — урок не нужен
		GameSettings.mark_tutorial_seen("upgrade_done")
		return false
	_upgrade_step = 1
	_dialogue(UPGRADE_LINES.slice(0, 3), func(): _set_target(unit, squad_tile))
	return true

func _on_upgrade_played() -> bool:
	_clear_target()
	if _upgrade_step == 1:
		GameSettings.mark_tutorial_seen("merge")
		var bar_tile := _tile_of_building(BARRACKS_CARD)
		var bar: CardData = _ensure_in_hand(BARRACKS_CARD) if bar_tile != IsoGridRenderer.NO_TILE else null
		if bar == null:   # Казарм, которые можно улучшить, нет (или рука полна) — урок про здания только словами
			_upgrade_step = 0
			GameSettings.mark_tutorial_seen("upgrade_done")
			_dialogue(UPGRADE_LINES.slice(3), func(): _release())
			return true
		_upgrade_step = 2
		_dialogue(UPGRADE_LINES.slice(3), func(): _set_target(bar, bar_tile))
		return true
	_upgrade_step = 0
	GameSettings.mark_tutorial_seen("building_level")
	GameSettings.mark_tutorial_seen("upgrade_done")
	hint("marine", UPGRADE_BUILDING_DONE, 6.0)
	_release()
	return true

# Карта расы игрока по id шаблона: есть в руке — она, нет — наставник выдаёт копию
func _ensure_in_hand(id: String) -> CardData:
	var have := _hand_card(id)
	if have != null:
		return have
	var card: CardData = CardFactory.equivalent(id, RunManager.player_faction)
	if card == null or BattleManager.pending_cards.size() >= BattleManager.MAX_HAND_SIZE:
		return null
	BattleManager.pending_cards.append(card)
	var bench: Variant = scene.get("bench")
	if bench != null and not bench.bench_cards.has(card):
		bench.bench_cards.append(card)
	if bench != null:
		bench._populate()
	return card

func _tile_of_squad(id: String) -> Vector2i:
	var want: CardData = CardFactory.equivalent(id, RunManager.player_faction)
	for squad in SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER):
		if want != null and squad.data.factory_id == want.unit_factory_id \
				and (squad.data.can_merge_upgrade() or squad.is_wounded()):
			return squad.tile
	return IsoGridRenderer.NO_TILE

func _tile_of_building(id: String) -> Vector2i:
	var want: CardData = CardFactory.equivalent(id, RunManager.player_faction)
	for card in BattleManager.player_buildings:
		if want != null and card.id == want.id and card.can_level_up_building():
			return BattleManager.player_buildings[card]
	return IsoGridRenderer.NO_TILE

# ---------- Ограничения сценария (зовёт BattleScene) ----------
# Бой не начинается: идёт диалог или игрок должен выполнить шаг сценария
func holds_start() -> bool:
	if not GameSettings.tutorial_enabled or (dormant() and not _dialogue_active):
		return false
	if _dialogue_active or is_talking():   # пока наставники на экране — бой не начинается (решение пользователя 25.11.2026)
		return true
	if target_id != "":   # наставник ведёт карту на клетку
		return true
	var s: int = GameSettings.tutorial_stage
	return s == Stage.PLACE_UNIT or s == Stage.PLACE_BARRACKS or s == Stage.CLICK_SQUAD \
		or (s == Stage.PLACE_CANNON and not GameSettings.tutorial_seen.has("cannon_placed"))

# Бой в обучении начинается только кнопкой «В БОЙ» (решение пользователя 25.11.2026), сам — никогда
func no_auto_start() -> bool:
	return GameSettings.tutorial_enabled and GameSettings.tutorial_stage < Stage.DONE and not dormant()

# Правило «в руке остаются 2 карты» не действует, пока наставник ведёт карту на клетку (орудие — предпоследняя карта)
func exempts_hand_floor() -> bool:
	return GameSettings.tutorial_enabled and not dormant() and (target_id != "" or GameSettings.tutorial_stage == Stage.PLACE_CANNON)

# «{cannon}» в репликах — название орудия расы игрока
func _fmt(lines: Array) -> Array:
	var title := "орудие"
	var cannon := cannon_card()
	if cannon != null:
		title = cannon.display_title()
	return lines.map(func(l): return [l[0], str(l[1]).replace("{cannon}", title)])

# Карту можно бросить сюда? Пока есть цель — только цель на свою клетку
func allow_drop(card: CardData, tile: Vector2i) -> bool:
	if not GameSettings.tutorial_enabled or target_id == "" or dormant():
		return true
	if card.id == target_id and tile == target_tile:
		return true
	if scene.has_method("_show_message"):
		scene.call("_show_message", "Козёл: сюда нельзя — перетащи светящуюся карту на подсвеченную клетку")
	return false

# Учебный бой: один слабый отряд врага — игрок выигрывает всегда
func is_training_battle() -> bool:
	return GameSettings.tutorial_enabled and wave == 1 and GameSettings.tutorial_stage <= Stage.TRAIN_BATTLE and not dormant()

func training_specs(specs: Array) -> Array:
	if specs.is_empty():
		return specs
	var first: Dictionary = specs[0]
	return [{"unit": first["unit"], "count": mini(int(first["count"]), TRAINING_COUNT_MAX), "mult": TRAINING_MULT}]

# Волна 5 — простые враги (пробуем орудие), волна 6 — ослабленный примарх: подменяют состав врага (BattleScene._place_enemy_squads).
# Поле волны 5 строится ещё под магазином (стадия WAVES), а орудие покупают позже — поэтому любая стадия от волн до орудия
func is_trial_battle() -> bool:
	var stage: int = GameSettings.tutorial_stage
	return GameSettings.tutorial_enabled and wave == TRIAL_WAVE and stage >= Stage.WAVES and stage <= Stage.PLACE_CANNON

func is_boss_battle() -> bool:
	return GameSettings.tutorial_enabled and wave == BOSS_WAVE and GameSettings.tutorial_stage == Stage.BOSS

func scripted_specs(max_squads: int) -> Array:
	var enemy := FactionTheme.enemy_of(RunManager.player_faction)
	if is_boss_battle():
		var boss: Array = EnemyWaves.build(15, RunMapNode.BOSS, max_squads, RunManager.rng.seed, RunManager.difficulty, enemy)
		return [{"unit": boss[0]["unit"], "count": boss[0]["count"], "mult": BOSS_MULT}]
	var out: Array = []
	for spec in EnemyWaves.build(4, RunMapNode.BATTLE, max_squads, RunManager.rng.seed, RunManager.difficulty, enemy):
		out.append({"unit": spec["unit"], "count": spec["count"], "mult": TRIAL_MULT})
	return out

# ---------- Диалог ----------
func _dialogue(lines: Array, on_done: Callable = Callable(), speaker: ShopVendor = null) -> void:
	_speaker = speaker
	_lines = lines
	_line_i = 0
	_on_done = on_done
	_dialogue_active = true
	_catcher.visible = true
	_skip.visible = true
	if _speaker == null:
		for who in _holders:
			_show_holder(who, true)
	_next_line()

func _next_line() -> void:
	if _line_i >= _lines.size():
		_end_dialogue(true)
		return
	var l: Array = _lines[_line_i]
	_line_i += 1
	_focus_line(str(l[1]))
	if _speaker != null and is_instance_valid(_speaker):   # учебный магазин: говорит торговец магазина, он и наставник
		_speaker.say(l[1], DIALOGUE_HOLD)
		_speaker.figure.react("greet")
		return
	for who in vendors:
		if who != l[0]:
			vendors[who].hide_bubble()
	vendors[l[0]].say(l[1], DIALOGUE_HOLD)
	vendors[l[0]].figure.react("greet")

func _end_dialogue(call_done: bool) -> void:
	_clear_focus()
	_dialogue_active = false
	_catcher.visible = false
	if _speaker != null and is_instance_valid(_speaker):
		_speaker.hide_bubble()
	_speaker = null
	for who in vendors:
		vendors[who].hide_bubble()
		_show_holder(who, false)
	_skip.visible = target_id != "" or GameSettings.tutorial_stage == Stage.SHOP_BUY
	var done := _on_done
	_on_done = Callable()
	if call_done and done.is_valid():
		done.call()

func _on_catcher_input(event: InputEvent) -> void:
	if _dialogue_active and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_next_line()

# ---------- Показ того, о чём говорит наставник ----------
func _deal_cards() -> void:
	var shop: Variant = scene.get("shop")
	if shop != null and is_instance_valid(shop) and shop.has_method("deal_now"):
		shop.call("deal_now")

func _focus_line(text: String) -> void:
	var key := ""
	for f in LINE_FOCUS:
		if text.begins_with(f[0]):
			key = f[1]
			break
	_clear_focus()
	match key:
		"citadel":
			_focus_citadel()
		"coins":
			_pulse_add(_coins_node())
			_glow_add(_coins_node())
		"reroll":
			var shop: Variant = scene.get("shop")
			if shop != null and is_instance_valid(shop):
				_pulse_add(shop.get("reroll_button"))
				_glow_add(shop.get("reroll_button"))

func _focus_citadel() -> void:
	var cit: Variant = BattleManager.citadel
	var cam: Variant = scene.get("camera")
	if cit == null or not is_instance_valid(cit) or cam == null or not is_instance_valid(cam):
		return
	_catcher.color = Color(0, 0, 0, 0)   # пока показываем цитадель — поле без затемнения
	cam.focus(cit.global_position, FOCUS_ZOOM, FOCUS_TIME, true)
	_camera_moved = true
	_ring = FocusRing.new()
	_ring.position = cit.global_position
	cit.get_parent().add_child(_ring)

func _coins_node() -> Variant:
	var shop: Variant = scene.get("shop")
	if shop != null and is_instance_valid(shop) and shop.get("_req_label") != null:
		return shop.get("_req_label")
	var hud: Variant = scene.get("hud")
	return hud.requisition_label() if hud != null else null

func _shop_vendor() -> ShopVendor:
	var shop: Variant = scene.get("shop")
	if shop != null and is_instance_valid(shop) and shop.get("vendor") != null:
		return shop.get("vendor")
	return null

# Рамка поверх затемнения вокруг элемента, о котором говорит наставник
func _glow_add(node: Variant) -> void:
	if node == null or not is_instance_valid(node) or _catcher == null:
		return
	var g := RectGlow.new()
	g.target = node
	_catcher.get_parent().add_child(g)
	_glows.append(g)

func _pulse_add(node: Variant) -> void:
	if node != null and is_instance_valid(node):
		_pulse_nodes.append(node)

func _clear_focus() -> void:
	if _catcher != null:
		_catcher.color = DIM
	for n in _pulse_nodes:
		if is_instance_valid(n):
			n.modulate = Color.WHITE
	_pulse_nodes.clear()
	for g in _glows:
		if is_instance_valid(g):
			g.queue_free()
	_glows.clear()
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null
	if _camera_moved:
		_camera_moved = false
		if scene != null and is_instance_valid(scene) and scene.has_method("_fit_camera"):
			scene.call("_fit_camera", true)

# Пульсирующая янтарная рамка вокруг элемента интерфейса — рисуется над затемнением, мышь не ловит
class RectGlow extends Control:
	var target: Control = null
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(_delta: float) -> void:
		if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
			visible = false
			return
		visible = true
		var r := target.get_global_rect().grow(6.0)
		position = r.position
		size = r.size
		queue_redraw()
	func _draw() -> void:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.AMBER_LIGHT, 0.10 + 0.14 * pulse), true)
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.AMBER_LIGHT, 0.6 + 0.4 * pulse), false, 3.0)

# Пульсирующее кольцо вокруг цитадели на время реплики
class FocusRing extends Node2D:
	const RADIUS := 150.0
	func _init() -> void:
		z_index = 100
	func _process(_delta: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
		var c := Color(Palette.AMBER_LIGHT, 0.55 + 0.4 * pulse)
		draw_arc(Vector2.ZERO, RADIUS * (0.95 + 0.08 * pulse), 0.0, TAU, 64, c, 4.0, true)
		draw_arc(Vector2.ZERO, RADIUS * 0.8, 0.0, TAU, 64, Color(c, 0.35), 2.0, true)

# ---------- Одна реплика (без блокировки) ----------
func hint(who: String, text: String, hold: float = -1.0) -> void:
	if not vendors.has(who):
		return
	_skip.visible = true
	for other in vendors:
		if other != who:
			vendors[other].hide_bubble()
			_show_holder(other, false)
	_show_holder(who, true)
	var shown: float = maxf(hold if hold >= 0.0 else ShopVendor.BUBBLE_TIME + text.length() * ShopVendor.BUBBLE_PER_CHAR, READ_TIME)
	vendors[who].say(text, shown)
	var talk: float = text.length() / ShopVendor.TYPE_SPEED + shown + ShopVendor.BUBBLE_FADE + HOLD_EXTRA
	var h: Control = _holders[who]
	if _tweens.has(who) and _tweens[who]:
		_tweens[who].kill()
	var tw := create_tween().set_ignore_time_scale(true)
	_tweens[who] = tw
	tw.tween_property(h, "modulate:a", 1.0, FADE)
	tw.tween_interval(talk)
	tw.tween_callback(func():
		_show_holder(who, false)
		_skip.visible = target_id != "" or GameSettings.tutorial_stage == Stage.CLICK_SQUAD)

func _show_holder(who: String, on: bool) -> void:
	var h: Control = _holders[who]
	# Прежний твин этого наставника гасим всегда: иначе конец «ухода» предыдущего диалога прятал его посреди следующего
	if _tweens.has(who) and _tweens[who]:
		_tweens[who].kill()
	var tw := create_tween().set_ignore_time_scale(true)
	_tweens[who] = tw
	if on:
		h.visible = true
		tw.tween_property(h, "modulate:a", 1.0, FADE)
	else:
		tw.tween_property(h, "modulate:a", 0.0, FADE)
		tw.tween_callback(func(): h.visible = false)

# ---------- Цель: карта и клетка ----------
func _set_target(card: CardData, tile: Vector2i) -> void:
	if card == null:
		return
	target_id = card.id
	target_tile = tile
	_skip.visible = true

func _clear_target() -> void:
	target_id = ""
	target_tile = Vector2i(-99, -99)
	var r: Variant = scene.get("renderer")
	if r != null:
		r.tutorial_tile = IsoGridRenderer.NO_TILE
		r.set_effect_tiles([] as Array[Vector2i])
		r.queue_redraw()
	for node in _hand_nodes():
		node.modulate = Color.WHITE

func _process(_delta: float) -> void:
	_poll_shop()
	if not _pulse_nodes.is_empty():
		var pl := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
		for n in _pulse_nodes:
			if is_instance_valid(n):
				n.modulate = Color.WHITE.lerp(PULSE_COLOR, pl)
	if target_id == "":
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	for node in _hand_nodes():
		var data: CardData = node.get("card_data")
		node.modulate = Color.WHITE.lerp(PULSE_COLOR, pulse) if data != null and data.id == target_id else Color.WHITE
	var r: Variant = scene.get("renderer")
	if r != null:
		r.tutorial_tile = target_tile
		if target_id == _barracks_id():   # Казармы: показываем, на кого они действуют
			r.set_effect_tiles(Building.get_effect_tiles("barracks", target_tile))
		r.queue_redraw()

# Первый магазин: орудие в слоте пульсирует, куплено (карта в руке магазина) — следующая стадия
func _poll_shop() -> void:
	if GameSettings.tutorial_stage != Stage.SHOP_BUY or not GameSettings.tutorial_enabled:
		return
	var shop: Variant = scene.get("shop")
	if shop == null or not is_instance_valid(shop) or shop.get("shop_slots") == null:
		return
	var cannon := cannon_card()
	if cannon == null:
		return
	var bought: bool = (shop.get("purchased_cards") as Array).any(func(c): return c.id == cannon.id)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	for slot in shop.shop_slots.get_children():
		var data: Variant = slot.get("card_data")
		slot.modulate = Color.WHITE.lerp(PULSE_COLOR, pulse) if not bought and data != null and data.id == cannon.id else Color.WHITE
	if bought and not _dialogue_active:
		_set_stage(Stage.PLACE_CANNON)
		var v := _shop_vendor()
		if v != null:
			v.say("Отлично. Теперь «В БОЙ» — поставим его на поле.", READ_TIME)

func _barracks_id() -> String:
	var c: CardData = CardFactory.equivalent(BARRACKS_CARD, RunManager.player_faction)
	return c.id if c != null else ""

func _hand_nodes() -> Array:
	var bench: Variant = scene.get("bench")
	if bench == null or bench.get("cards_container") == null:
		return []
	return bench.cards_container.get_children().filter(func(c): return c.get("card_data") != null)

func _hand_card(id: String) -> CardData:
	# id карты расы: у Хаоса свои id — сравниваем с эквивалентом
	var want: CardData = CardFactory.equivalent(id, RunManager.player_faction)
	for c in BattleManager.pending_cards:
		if want != null and c.id == want.id:
			return c
	return null

func _free_tile_for_unit() -> Vector2i:
	var grid: Variant = scene.get("iso_grid")
	var r: Variant = scene.get("renderer")
	var middle := Vector2i(1, 1)
	if grid.is_valid_tile(middle) and not r.occupied_tiles_player.has(middle):
		return middle
	for t in grid.get_all_tiles():
		if grid.is_valid_tile(t) and not r.occupied_tiles_player.has(t):
			return t
	return IsoGridRenderer.NO_TILE

# Свободная клетка по стороне от первого отряда игрока (там Казармы действуют); NO_TILE — нет
func _free_tile_beside_squad() -> Vector2i:
	var grid: Variant = scene.get("iso_grid")
	var r: Variant = scene.get("renderer")
	for squad in SquadRegistry.get_alive_squads_of_team(GameConstants.TEAM_PLAYER):
		for n in BattleManager.NEIGHBOUR_TILES:
			var t: Vector2i = squad.tile + n
			if grid.is_valid_tile(t) and not r.occupied_tiles_player.has(t):
				return t
	return IsoGridRenderer.NO_TILE

# ---------- Служебное ----------
func _set_stage(stage: int) -> void:
	GameSettings.set_tutorial_stage(stage)

# Шаг сценария завершён — бой снова можно запускать (если в руке осталось мало карт, он начнётся сам)
func _release() -> void:
	if scene != null and is_instance_valid(scene) and scene.has_method("tutorial_release"):
		scene.call("tutorial_release")

func _on_skip() -> void:
	_deal_cards()
	GameSettings.set_tutorial_enabled(false)
	_clear_target()
	_upgrade_step = 0
	_clear_focus()
	if _dialogue_active:
		_end_dialogue(false)
	for who in vendors:
		vendors[who].hide_bubble()
		_show_holder(who, false)
	_skip.visible = false
	_release()

func is_talking() -> bool:
	return _dialogue_active or _holders.values().any(func(h): return h.visible)
