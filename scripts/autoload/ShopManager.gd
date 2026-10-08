extends Node

const SHOP_SIZE: int = 4
var current_offers: Array = []

signal shop_refreshed(offers: Array)
signal card_purchased(card_data: CardData)

func refresh_shop() -> void:
	current_offers.clear()
	var pool = CardFactory.build_pool()
	pool.shuffle()
	for i in range(min(SHOP_SIZE, pool.size())):
		current_offers.append(pool[i])
	emit_signal("shop_refreshed", current_offers)
	print("ShopManager: магазин обновлён, %d предложений" % current_offers.size())

func try_purchase(slot_index: int) -> CardData:
	if slot_index >= current_offers.size():
		return null
	var card_data = current_offers[slot_index]
	if not EconomyManager.try_spend(card_data.cost):
		print("ShopManager: не хватает Requisition!")
		return null
	current_offers.remove_at(slot_index)
	emit_signal("card_purchased", card_data)
	print("ShopManager: куплена карта '%s' за %d Req" % [card_data.title, card_data.cost])
	return card_data
