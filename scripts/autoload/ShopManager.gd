extends Node

# -------------------------------------------------------
# МАГАЗИН — набор карт перед волной
# -------------------------------------------------------
# Каждый новый магазин (open_shop) — новый набор. Набор можно обновить за Req:
# первое обновление REROLL_BASE_COST, каждое следующее в этом магазине
# дороже на REROLL_COST_GROWTH (+13%); в новом магазине цена снова базовая.
# В магазине 1-й волны FIRST_WAVE_FREE_CARDS карт бесплатно (первые покупки).
# Случайность — от RunManager.rng (повторяемость по сиду забега).
# Подкрепление (BattleManager.catch_up_pending): выбор одной из CATCH_UP_CHOICES
# разных Common карт бесплатно, набор можно поменять CATCH_UP_REROLLS раз.
# Невзятый выбор не сгорает — ждёт в следующих магазинах.
const SHOP_SIZE: int = 4
const REROLL_BASE_COST: int = 5
const REROLL_COST_GROWTH: float = 1.13
const FIRST_WAVE_FREE_CARDS: int = 1
const CATCH_UP_CHOICES: int = 3
const CATCH_UP_REROLLS: int = 1

var current_offers: Array = []
var rerolls_done: int = 0          # обновлений в текущем магазине
var free_cards_left: int = 0       # бесплатных покупок в текущем магазине
var shop_node_id: int = -1         # шаг забега, для которого открыт текущий набор
var catch_up_offers: Array = []    # выбор подкрепления (пусто — выбора нет)
var catch_up_rerolls_left: int = 0
# Выбор выдан этим магазином: окно открывается само только тогда (дальше — по
# кнопке в шапке). Не сохраняется: после «Продолжить» окно само не всплывает
var catch_up_just_issued: bool = false

# Выбор карты между волнами (решение пользователя 16.11.2026): PICK_DEALT карт рубашкой вверх → игрок открывает
# PICK_OPEN из них → из открытых берёт одну (бесплатно), остальные сгорают. Пул — тот же, что у магазина,
# без повторов по id; набор — от RunManager.rng и сохраняется (выход и «Продолжить» не дают перебросить)
const PICK_DEALT: int = 4
const PICK_OPEN: int = 2
var pick_node_id: int = -1
var pick_offers: Array = []        # 4 карты рубашкой вверх
var pick_open: Array[int] = []     # индексы открытых игроком (до PICK_OPEN)
var pick_taken_index: int = -1     # взятая карта (-1 — ещё не выбрана): набор закрыт
# Стартовый выбор забега (решение пользователя 17.11.2026, вместо магазина волны 1): PICK_START_DEALT карт рубашкой вверх,
# игрок берёт вслепую PICK_START_TAKE (клик по рубашке — карта открывается и сразу в руку), остальные сгорают.
# Взятые индексы — в pick_open (карта открыта) и pick_start_taken (порядок взятия)
const PICK_START_DEALT: int = 6
const PICK_START_TAKE: int = 3
var pick_start_taken: Array[int] = []

signal shop_refreshed(offers: Array)
signal card_purchased(card_data: CardData)

# Магазин шага забега: свой набор уже есть (повторный вход, загрузка
# сохранения) — показываем его, иначе новый набор с базовой ценой обновления
func open_shop() -> void:
	if shop_node_id == RunManager.current_node_id and shop_node_id >= 0:
		emit_signal("shop_refreshed", current_offers)
		return
	shop_node_id = RunManager.current_node_id
	rerolls_done = 0
	free_cards_left = FIRST_WAVE_FREE_CARDS if EconomyManager.round_number == 1 else 0
	catch_up_just_issued = false
	if BattleManager.catch_up_pending:
		BattleManager.catch_up_pending = false
		if catch_up_offers.is_empty():
			catch_up_rerolls_left = CATCH_UP_REROLLS
			_roll_catch_up()
			catch_up_just_issued = true
	refresh_shop()

# Набор выбора карты для текущего шага PICK: есть свой (повторный вход, загрузка) — он же
func open_pick() -> void:
	if pick_node_id == RunManager.current_node_id and pick_node_id >= 0:
		return
	pick_node_id = RunManager.current_node_id
	pick_open.clear()
	pick_start_taken.clear()
	pick_taken_index = -1
	pick_offers.clear()
	var dealt: int = PICK_START_DEALT if pick_is_start() else PICK_DEALT
	var pool: Array = CardFactory.build_pool().filter(func(c): return MetaProgress.is_card_unlocked(c.id))
	var rng: RandomNumberGenerator = RunManager.rng
	for i in range(pool.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var seen: Dictionary = {}
	for c in pool:
		if pick_offers.size() >= dealt:
			break
		if not seen.has(c.id):
			seen[c.id] = true
			pick_offers.append(c)

# Идёт стартовый выбор забега (3 из 6 вслепую), а не обычный (открыть 2, взять 1)
func pick_is_start() -> bool:
	var node = RunManager.get_current_node()
	return node != null and node.type == RunMapNode.START_PICK

# Стартовый выбор: взять карту рубашки вслепую — открывается и уходит игроку. null — нельзя (набор закрыт / уже взята)
func pick_start_take(index: int) -> CardData:
	if pick_done() or index < 0 or index >= pick_offers.size() or pick_start_taken.has(index):
		return null
	pick_start_taken.append(index)
	pick_open.append(index)
	var card: CardData = pick_offers[index]
	print("ShopManager: стартовый выбор — '%s' (%d из %d)" % [card.title, pick_start_taken.size(), PICK_START_TAKE])
	return card

# Открыть карту рубашки: false — уже открыта, лимит открытых или карту уже взяли
func pick_reveal(index: int) -> bool:
	if pick_done() or index < 0 or index >= pick_offers.size() or pick_open.has(index) or pick_open.size() >= PICK_OPEN:
		return false
	pick_open.append(index)
	return true

# Взять одну из открытых: набор закрывается. null — нельзя (карта не открыта / уже взяли)
func pick_take(index: int) -> CardData:
	if pick_done() or not pick_open.has(index):
		return null
	pick_taken_index = index
	var card: CardData = pick_offers[index]
	print("ShopManager: выбор карты — '%s'" % card.title)
	return card

func pick_done() -> bool:
	if pick_is_start():
		return pick_start_taken.size() >= PICK_START_TAKE
	return pick_taken_index >= 0

func pick_ready() -> bool:
	return pick_open.size() >= PICK_OPEN

# Новый забег: номера шагов снова с нуля — старый набор не должен подхватиться
func reset() -> void:
	current_offers.clear()
	rerolls_done = 0
	free_cards_left = 0
	shop_node_id = -1
	catch_up_offers.clear()
	catch_up_rerolls_left = 0
	catch_up_just_issued = false
	pick_node_id = -1
	pick_offers.clear()
	pick_open.clear()
	pick_start_taken.clear()
	pick_taken_index = -1

func refresh_shop() -> void:
	current_offers.clear()
	var pool = CardFactory.build_pool().filter(func(c): return MetaProgress.is_card_unlocked(c.id))
	# Перемешивание Фишера–Йетса от RNG забега
	var rng: RandomNumberGenerator = RunManager.rng
	for i in range(pool.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for i in range(min(SHOP_SIZE, pool.size())):
		current_offers.append(pool[i])
	emit_signal("shop_refreshed", current_offers)
	print("ShopManager: магазин обновлён, %d предложений" % current_offers.size())

# -------------------------------------------------------
# СОХРАНЕНИЕ (SaveManager) — своё состояние забега
# -------------------------------------------------------
func save_state() -> Dictionary:
	return {
		"node_id": shop_node_id,
		"offers": CardFactory.ids_of(current_offers),
		"rerolls_done": rerolls_done,
		"free_cards_left": free_cards_left,
		"catch_up_offers": CardFactory.ids_of(catch_up_offers),
		"catch_up_rerolls_left": catch_up_rerolls_left,
		"pick_node_id": pick_node_id,
		"pick_offers": CardFactory.ids_of(pick_offers),
		"pick_open": pick_open.duplicate(),
		"pick_taken_index": pick_taken_index,
		"pick_start_taken": pick_start_taken.duplicate(),
	}

func load_state(d: Dictionary) -> void:
	shop_node_id = int(d["node_id"])
	current_offers = CardFactory.create_many(d["offers"])
	rerolls_done = int(d["rerolls_done"])
	free_cards_left = int(d["free_cards_left"])
	catch_up_offers = CardFactory.create_many(d.get("catch_up_offers", []))
	catch_up_rerolls_left = int(d.get("catch_up_rerolls_left", 0))
	pick_node_id = int(d.get("pick_node_id", -1))
	pick_offers = CardFactory.create_many(d.get("pick_offers", []))
	pick_open.clear()
	for i in d.get("pick_open", []):
		pick_open.append(int(i))
	pick_taken_index = int(d.get("pick_taken_index", -1))
	pick_start_taken.clear()
	for i in d.get("pick_start_taken", []):
		pick_start_taken.append(int(i))

# -------------------------------------------------------
# ОБНОВЛЕНИЕ НАБОРА
# -------------------------------------------------------
func get_reroll_cost() -> int:
	if rerolls_done == 0 and MetaProgress.passive_level("munitorum") > 0:
		return 0   # пассивка «Связи в Муниторуме»: первое обновление за волну бесплатно
	return roundi(REROLL_BASE_COST * pow(REROLL_COST_GROWTH, rerolls_done))

func try_reroll() -> bool:
	var cost = get_reroll_cost()
	if not EconomyManager.try_spend(cost):
		return false
	rerolls_done += 1
	print("ShopManager: обновление набора за %d Req (следующее — %d)" % [cost, get_reroll_cost()])
	refresh_shop()
	return true

# -------------------------------------------------------
# ПОКУПКА
# -------------------------------------------------------
# Цена к оплате: бесплатная карта 1-й волны, иначе цена со скидкой Epic.
# card.cost не меняется — от него считается цена продажи.
func get_price(card: CardData) -> int:
	if free_cards_left > 0:
		return 0
	return SynergyManager.get_discounted_cost(card)

# Сноска карты магазина (ShopSlot, при наведении): такой отряд / здание уже стоит на поле —
# какого уровня и пойдёт ли карта на улучшение. Пусто — на поле такого нет (или карта не отряд / здание)
func get_owned_note(card: CardData) -> String:
	var levels: Array[String] = []
	var can_level := false
	match card.card_type:
		"squad":
			for d in BattleManager.player_units:
				if d.factory_id == card.unit_factory_id:
					levels.append("ур. %d/%d" % [d.squad_level, UnitFactory.MAX_SQUAD_LEVEL])
					can_level = can_level or d.can_merge_upgrade()
		"building":
			for b in BattleManager.player_buildings:
				if b.id == card.id:
					levels.append("ур. %d/%d" % [b.building_level, CardData.MAX_BUILDING_LEVEL]
						if not b.building_level_bonuses.is_empty() else "стоит")
					can_level = can_level or b.can_level_up_building()
	if levels.is_empty():
		return ""
	var head := "На поле: " if levels.size() == 1 else "На поле ×%d: " % levels.size()
	var tail := "можно улучшить" if can_level else ("максимум — только лечение" if card.card_type == "squad" else "максимум")
	if card.card_type == "building" and card.building_level_bonuses.is_empty():
		tail = "можно поставить ещё"
	return "%s%s\n%s" % [head, ", ".join(levels), tail]

# Синергии с этой картой (новым отрядом): тег «было → станет» по армии на поле и отрядам в руке,
# какой уровень синергии откроется или сколько до следующего. Только подсказка магазина
func get_synergy_note(card: CardData) -> String:
	if card.card_type != "squad":
		return ""
	var unit := UnitFactory.create(card.unit_factory_id)
	var have := _owned_tag_weights()
	var lines: Array[String] = []
	for tag in SynergyManager.SYNERGY_DEFINITIONS:
		if not tag in unit.tags:
			continue
		var before := int(have.get(tag, 0.0) + 0.001)
		var after := int(have.get(tag, 0.0) + card.unit_count * unit.unit_weight + 0.001)
		var line := "%s %d → %d" % [SynergyManager.tag_label(tag), before, after]
		for level in SynergyManager.SYNERGY_DEFINITIONS[tag]:
			if before < level["threshold"] and after >= level["threshold"]:
				line += " — откроет «%s»" % Names.of(level["name"])
				break
			if after < level["threshold"]:
				line += " (до «%s» ещё %d)" % [Names.of(level["name"]), level["threshold"] - after]
				break
		lines.append(line)
	return "\n".join(lines)

# Теги армии в пересчёте на юниты (как SynergyManager): отряды на поле — по живым бойцам,
# отряды в руке — полным составом карты
func _owned_tag_weights() -> Dictionary:
	var w: Dictionary = {}
	for d in BattleManager.player_units:
		for tag in d.tags:
			w[tag] = w.get(tag, 0.0) + d.saved_hp.size() * d.unit_weight
	for c in BattleManager.pending_cards:
		if c.card_type == "squad":
			var u := UnitFactory.create(c.unit_factory_id)
			for tag in u.tags:
				w[tag] = w.get(tag, 0.0) + c.unit_count * u.unit_weight
	return w

func try_purchase(slot_index: int) -> CardData:
	if slot_index < 0 or slot_index >= current_offers.size():
		return null
	var card_data: CardData = current_offers[slot_index]
	var price = get_price(card_data)
	if not EconomyManager.try_spend(price):
		print("ShopManager: не хватает Requisition!")
		return null
	if free_cards_left > 0:
		free_cards_left -= 1
	else:
		SynergyManager.consume_discount(card_data)
	current_offers.remove_at(slot_index)
	emit_signal("card_purchased", card_data)
	print("ShopManager: куплена карта '%s' за %d Req" % [card_data.title, price])
	return card_data

# -------------------------------------------------------
# ПОДКРЕПЛЕНИЕ (catch-up)
# -------------------------------------------------------
func has_catch_up() -> bool:
	return not catch_up_offers.is_empty()

# CATCH_UP_CHOICES разных Common карт из пула (веса копий пула сохраняются).
# При смене набора сначала берутся карты, которых в прошлом наборе не было
func _roll_catch_up() -> void:
	var previous = CardFactory.ids_of(catch_up_offers)
	catch_up_offers.clear()
	var commons: Array = CardFactory.build_pool().filter(func(c): return c.rarity == "common" \
		and MetaProgress.is_card_unlocked(c.id))
	var fresh: Array = commons.filter(func(c): return not previous.has(c.id))
	var seen: Array = commons.filter(func(c): return previous.has(c.id))
	for group in [fresh, seen]:
		_take_distinct(group)

func _take_distinct(group: Array) -> void:
	var rng: RandomNumberGenerator = RunManager.rng
	while catch_up_offers.size() < CATCH_UP_CHOICES and not group.is_empty():
		var card: CardData = group[rng.randi_range(0, group.size() - 1)]
		group = group.filter(func(c): return c.id != card.id)   # без повторов
		catch_up_offers.append(card)

func try_reroll_catch_up() -> bool:
	if not has_catch_up() or catch_up_rerolls_left <= 0:
		return false
	catch_up_rerolls_left -= 1
	_roll_catch_up()
	return true

# Взять карту выбора: выбор закрывается целиком (лимит руки проверяет магазин)
func take_catch_up(index: int) -> CardData:
	if index < 0 or index >= catch_up_offers.size():
		return null
	var card: CardData = catch_up_offers[index]
	catch_up_offers.clear()
	catch_up_rerolls_left = 0
	catch_up_just_issued = false
	print("ShopManager: подкрепление — '%s' бесплатно" % card.title)
	return card
