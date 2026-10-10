extends Node

# -------------------------------------------------------
# МАГАЗИН — набор карт перед волной
# -------------------------------------------------------
# Каждый новый магазин (open_shop) — новый набор. Набор можно обновить за Req:
# первое обновление REROLL_BASE_COST, каждое следующее в этом магазине
# дороже на REROLL_COST_GROWTH (+13%); в новом магазине цена снова базовая.
# В магазине 1-й волны FIRST_WAVE_FREE_CARDS карт бесплатно (первые покупки).
# Случайность — от RunManager.rng (повторяемость по сиду забега).
const SHOP_SIZE: int = 4
const REROLL_BASE_COST: int = 5
const REROLL_COST_GROWTH: float = 1.13
const FIRST_WAVE_FREE_CARDS: int = 1

var current_offers: Array = []
var rerolls_done: int = 0          # обновлений в текущем магазине
var free_cards_left: int = 0       # бесплатных покупок в текущем магазине
var shop_node_id: int = -1         # шаг забега, для которого открыт текущий набор

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
	refresh_shop()

# Новый забег: номера шагов снова с нуля — старый набор не должен подхватиться
func reset() -> void:
	current_offers.clear()
	rerolls_done = 0
	free_cards_left = 0
	shop_node_id = -1

func refresh_shop() -> void:
	current_offers.clear()
	var pool = CardFactory.build_pool()
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
	}

func load_state(d: Dictionary) -> void:
	shop_node_id = int(d["node_id"])
	current_offers = CardFactory.create_many(d["offers"])
	rerolls_done = int(d["rerolls_done"])
	free_cards_left = int(d["free_cards_left"])

# -------------------------------------------------------
# ОБНОВЛЕНИЕ НАБОРА
# -------------------------------------------------------
func get_reroll_cost() -> int:
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
