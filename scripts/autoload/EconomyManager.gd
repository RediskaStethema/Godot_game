extends Node

# -------------------------------------------------------
# КОНСТАНТЫ (TDD, раздел 6 «Экономика»)
# -------------------------------------------------------
# Доход за победу в волне: 10 + волна × 2 + бонусы (бонусы не больше +8)
const INCOME_BASE: int = 10
const INCOME_PER_WAVE: int = 2
const INCOME_CAP_BONUS: int = 8       # interest cap — защита от snowball
const BONUS_FLAWLESS: int = 5         # полная победа без потерь
const BONUS_ELITE_KILL: int = 3       # за каждого убитого элитного врага
const LOSS_INCOME_MULT: float = 0.5   # за поражение — половина дохода
# Стартовый капитал: по таблице TDD в 1-й волне доступно 2–3 Common юнита
const STARTING_REQUISITION: int = 12
# Salvage — P1 по TDD: API есть, источников пока нет
const SALVAGE_CAP: int = 5
# Продажа карты из руки: 1/3 изначальной цены, округление вниз
# (решение по дизайну; в TDD было ×0.5)
const SELL_REFUND_DIVISOR: int = 3

# -------------------------------------------------------
# ДАННЫЕ
# -------------------------------------------------------
# Requisition — основная валюта: карты, здания, апгрейды.
# Salvage — редкий ресурс для Tier 3 и реликвий, излишек сверх капа сгорает.
var requisition: int = STARTING_REQUISITION
var salvage: int = 0
var wins: int = 0               # счётчик побед (статистика)
var round_number: int = 1       # текущая волна

signal requisition_changed(new_amount: int)
signal salvage_changed(new_amount: int)
signal income_received(amount: int)

# -------------------------------------------------------
# ДОХОД
# -------------------------------------------------------
func calculate_wave_income(wave: int, bonuses: int = 0) -> int:
	var base = INCOME_BASE + wave * INCOME_PER_WAVE
	return base + clampi(bonuses, 0, INCOME_CAP_BONUS)

# Бонусы TDD к доходу за победу (кап +8 применит calculate_wave_income):
# синергия фракции, «без потерь», +BONUS_ELITE_KILL за каждого элитного врага
func calculate_victory_bonuses(synergy_income: int, flawless: bool, elite_kills: int) -> int:
	return synergy_income + (BONUS_FLAWLESS if flawless else 0) + elite_kills * BONUS_ELITE_KILL

# Вызывается один раз в конце каждого боя — единственное место,
# где растёт round_number.
func give_round_income(won: bool, bonuses: int = 0) -> int:
	var income: int
	if won:
		wins += 1
		income = calculate_wave_income(round_number, bonuses)
	else:
		# За поражение бонусы не положены
		income = int(calculate_wave_income(round_number) * LOSS_INCOME_MULT)

	requisition += income
	print("EconomyManager: доход волна %d: %d Req, итого %d Req" % [round_number, income, requisition])
	round_number += 1

	emit_signal("income_received", income)
	emit_signal("requisition_changed", requisition)
	return income

# Разовая награда вне боя (события карты забега). round_number не трогает.
func add_requisition(amount: int) -> void:
	if amount <= 0:
		return
	requisition += amount
	print("EconomyManager: +%d Req, итого %d Req" % [amount, requisition])
	emit_signal("requisition_changed", requisition)

# -------------------------------------------------------
# SALVAGE
# -------------------------------------------------------
func add_salvage(amount: int) -> void:
	salvage = clampi(salvage + amount, 0, SALVAGE_CAP)
	emit_signal("salvage_changed", salvage)

# -------------------------------------------------------
# ТРАТЫ
# -------------------------------------------------------
func can_afford(req_cost: int, sal_cost: int = 0) -> bool:
	return requisition >= req_cost and salvage >= sal_cost

# Возвращает true если покупка прошла успешно,
# false если ресурсов не хватает — ничего не списывается.
func try_spend(req_cost: int, sal_cost: int = 0) -> bool:
	if not can_afford(req_cost, sal_cost):
		return false
	requisition -= req_cost
	emit_signal("requisition_changed", requisition)
	if sal_cost > 0:
		salvage -= sal_cost
		emit_signal("salvage_changed", salvage)
	return true

# -------------------------------------------------------
# ПРОДАЖА КАРТ
# -------------------------------------------------------
func get_sell_price(card: CardData) -> int:
	return card.cost / SELL_REFUND_DIVISOR

# Начисляет выручку и возвращает её. Убрать карту из руки — дело вызывающего.
func sell_card(card: CardData) -> int:
	var refund = get_sell_price(card)
	requisition += refund
	emit_signal("requisition_changed", requisition)
	return refund

# -------------------------------------------------------
# СОХРАНЕНИЕ (SaveManager) — своё состояние забега
# -------------------------------------------------------
func save_state() -> Dictionary:
	return {"requisition": requisition, "salvage": salvage, "wins": wins, "round_number": round_number}

func load_state(d: Dictionary) -> void:
	requisition = int(d["requisition"])
	salvage = int(d["salvage"])
	wins = int(d["wins"])
	round_number = int(d["round_number"])
	emit_signal("requisition_changed", requisition)
	emit_signal("salvage_changed", salvage)

# -------------------------------------------------------
# СБРОС
# -------------------------------------------------------
# Вызывается при старте новой игры (не нового раунда)
func reset() -> void:
	requisition = STARTING_REQUISITION
	salvage = 0
	wins = 0
	round_number = 1
	emit_signal("requisition_changed", requisition)
	emit_signal("salvage_changed", salvage)
