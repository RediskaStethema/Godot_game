class_name RunEvents
extends RefCounted

# События — стадия цепочки забега (решение пользователя: после волн RunMapData.EVENT_AFTER_WAVES,
# отдельная сцена EventScene, выбор с риском). Данными:
#   событие — {id, title, text, options[]}; вариант — {label, cost_req?, cost_hp?, gain[], chance?, fail[]}
#   cost_req / cost_hp — цена (Req / HP цитадели); не хватает — вариант недоступен
#   chance — шанс удачи: удалось — gain, нет — fail (бросок от seed забега, «Продолжить» не перебросит)
# Эффекты (gain / fail) — словари с одним ключом:
#   {"req": n}            +n Req
#   {"heal": n}           +n HP цитадели (не выше максимума)
#   {"damage": n}         −n HP цитадели (событие не убивает: остаётся хотя бы 1)
#   {"card": {rarity, card_type}}  случайная карта пула в руку; рука полна — её цена продажи в Req
#   {"level_squad": 1}    случайный отряд армии +1 уровень (как карта того же отряда: бойцы и статы)
#   {"heal_army": 1}      все отряды армии — полный состав с полным HP
#   {"building_level": 1} случайное здание ниже максимального уровня +1 уровень
#   {"enemy_hp": k, "note": текст}  враги следующей волны с HP ×k (BattleManager.next_battle_enemy_hp)
# Новое событие — запись в EVENTS; новый эффект — ветка в _apply_effect и проверка в _effect_blocker
# Подпись карты-награды по редкости: [карта, отряд]
const CARD_NAMES = {
	"common": ["обычная карта", "обычный отряд"],
	"rare": ["редкая карта", "редкий отряд"],
	"epic": ["эпическая карта", "эпический отряд"],
}

const EVENTS: Array = [
	{
		"id": "munitorum_cache",
		"title": "Тайник Муниторума",
		"text": "Разведчики нашли нетронутый склад Имперской Гвардии. Унести всё не выйдет.",
		"options": [
			{"label": "Забрать припасы", "gain": [{"req": 10}]},
			{"label": "Взять снаряжение", "gain": [{"card": {"rarity": "common"}}]},
		],
	},
	{
		"id": "tech_priests",
		"title": "Техножрецы Марса",
		"text": "Адепты Механикус предлагают помощь. Дух машины требует подношений.",
		"options": [
			{"label": "Ремонт цитадели", "gain": [{"heal": 250}]},
			{"label": "Освятить орудия", "cost_req": 8, "gain": [{"building_level": 1}]},
			{"label": "Отказаться", "gain": []},
		],
	},
	{
		"id": "distress_signal",
		"title": "Сигнал бедствия",
		"text": "Слабый сигнал с подбитого «Громового ястреба». Это может быть ловушкой.",
		"options": [
			{"label": "Выслать отряд", "chance": 0.6, "gain": [{"card": {"rarity": "rare"}}],
				"fail": [{"damage": 150}]},
			{"label": "Пройти мимо", "gain": []},
		],
	},
	{
		"id": "chapter_relic",
		"title": "Реликвия ордена",
		"text": "В руинах капеллы найден реликварий павшего брата-капитана.",
		"options": [
			{"label": "Вручить достойным", "gain": [{"level_squad": 1}]},
			{"label": "Продать вольному торговцу", "gain": [{"req": 15}]},
		],
	},
	{
		"id": "field_hospital",
		"title": "Полевой госпиталь",
		"text": "Апотекарии развернули госпиталь у линии фронта. Медикаментов мало.",
		"options": [
			{"label": "Вылечить армию", "cost_req": 6, "gain": [{"heal_army": 1}]},
			{"label": "Отправить медикаменты в цитадель", "gain": [{"heal": 120}]},
		],
	},
	{
		"id": "warp_storm",
		"title": "Варп-шторм",
		"text": "Над полем разразился варп-шторм. Он терзает всех — и своих, и чужих.",
		"options": [
			{"label": "Идти сквозь шторм", "cost_hp": 100,
				"gain": [{"enemy_hp": 0.8, "note": "Варп-шторм измотал врага: −20% HP"}]},
			{"label": "Укрыться", "gain": []},
		],
	},
	{
		"id": "cultists",
		"title": "Культисты в тылу",
		"text": "В тылу объявились еретики. Если их не выжечь, они придут на помощь врагу.",
		"options": [
			{"label": "Выжечь ересь", "cost_req": 8, "gain": []},
			{"label": "Не отвлекаться", "gain": [{"enemy_hp": 1.2, "note": "Культисты усилили врага: +20% HP"}]},
		],
	},
	{
		"id": "reinforcements",
		"title": "Экстренное подкрепление",
		"text": "Орбитальный транспорт сбросил подкрепление в зону высадки.",
		"options": [
			{"label": "Принять отряд", "gain": [{"card": {"rarity": "common", "card_type": "squad"}}]},
			{"label": "Перенаправить в цитадель", "gain": [{"heal": 150}]},
		],
	},
	{
		"id": "battlefield_spoils",
		"title": "Трофеи с поля боя",
		"text": "После боя поле усеяно телами и оружием. Обыск займёт время.",
		"options": [
			{"label": "Обыскать павших", "chance": 0.5, "gain": [{"req": 18}], "fail": []},
			{"label": "Сжечь тела", "gain": [{"req": 6}]},
		],
	},
]

# Порядок событий забега: перемешанный от seed список — i-й шаг «событие» берёт i-е (без повторов)
static func for_run(seed_value: int, index: int) -> Dictionary:
	var order: Array = range(EVENTS.size())
	var rng = RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "events"])
	for i in range(order.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	return EVENTS[order[index % order.size()]]

# Почему вариант недоступен ("" — доступен)
static func blocker(option: Dictionary) -> String:
	var req: int = option.get("cost_req", 0)
	if req > EconomyManager.requisition:
		return "нужно %d Req" % req
	var hp: float = option.get("cost_hp", 0.0)
	if hp > 0.0 and BattleManager.citadel_hp <= hp:
		return "цитадель слишком слаба"
	for e in option.get("gain", []):
		var b = _effect_blocker(e)
		if b != "":
			return b
	return ""

# Подпись варианта: название, цена, что даёт
static func describe(option: Dictionary) -> String:
	var parts: Array[String] = []
	if option.get("cost_req", 0) > 0:
		parts.append("−%d Req" % option["cost_req"])
	if option.get("cost_hp", 0.0) > 0.0:
		parts.append("−%d HP цитадели" % int(option["cost_hp"]))
	var gain: Array[String] = []
	for e in option.get("gain", []):
		gain.append(_effect_text(e))
	if option.has("chance"):
		var fail: Array[String] = []
		for e in option.get("fail", []):
			fail.append(_effect_text(e))
		parts.append("%d%%: %s, иначе %s" % [roundi(option["chance"] * 100), ", ".join(gain),
			", ".join(fail) if not fail.is_empty() else "ничего"])
	elif not gain.is_empty():
		parts.append(", ".join(gain))
	return option["label"] + (" (" + "; ".join(parts) + ")" if not parts.is_empty() else "")

# Применяет вариант: цена, бросок, эффекты. Возвращает текст итога для экрана
static func apply(option: Dictionary, rng: RandomNumberGenerator) -> String:
	if option.get("cost_req", 0) > 0:
		EconomyManager.try_spend(option["cost_req"])
	if option.get("cost_hp", 0.0) > 0.0:
		_damage_citadel(option["cost_hp"])
	var effects: Array = option.get("gain", [])
	var lines: Array[String] = []
	if option.has("chance"):
		var lucky = rng.randf() < option["chance"]
		lines.append("Удача!" if lucky else "Не повезло.")
		if not lucky:
			effects = option.get("fail", [])
	for e in effects:
		lines.append(_apply_effect(e, rng))
	if lines.is_empty() or (lines.size() == 1 and option.has("chance") and effects.is_empty()):
		lines.append("Ничего не изменилось.")
	return "\n".join(lines)

static func _effect_blocker(e: Dictionary) -> String:
	if e.has("level_squad") and not BattleManager.player_units.any(func(d): return d.can_merge_upgrade()):
		return "нет отряда для улучшения"
	if e.has("building_level") and _upgradable_buildings().is_empty():
		return "нет здания для улучшения"
	return ""

static func _effect_text(e: Dictionary) -> String:
	if e.has("req"): return "+%d Req" % e["req"]
	if e.has("heal"): return "+%d HP цитадели" % e["heal"]
	if e.has("damage"): return "−%d HP цитадели" % e["damage"]
	if e.has("card"):
		var squad: bool = e["card"].get("card_type", "") == "squad"
		return CARD_NAMES.get(e["card"].get("rarity", ""), ["случайная карта", "случайный отряд"])[1 if squad else 0]
	if e.has("level_squad"): return "отряд +1 уровень"
	if e.has("heal_army"): return "армия здорова"
	if e.has("building_level"): return "здание +1 уровень"
	if e.has("enemy_hp"): return "враги след. волны %+d%% HP" % roundi((e["enemy_hp"] - 1.0) * 100)
	return ""

static func _apply_effect(e: Dictionary, rng: RandomNumberGenerator) -> String:
	if e.has("req"):
		EconomyManager.add_requisition(e["req"])
		return "+%d Req" % e["req"]
	if e.has("heal"):
		return "Цитадель восстановлена: +%d HP" % roundi(BattleManager.heal_citadel(float(e["heal"])))
	if e.has("damage"):
		return "Засада! Цитадель −%d HP" % roundi(_damage_citadel(e["damage"]))
	if e.has("card"):
		return _give_card(rng, e["card"].get("rarity", ""), e["card"].get("card_type", ""))
	if e.has("level_squad"):
		var options = BattleManager.player_units.filter(func(d): return d.can_merge_upgrade())
		if options.is_empty():
			return "Достойных не нашлось"
		var d: UnitData = options[rng.randi() % options.size()]
		d.apply_merge_upgrade()
		for i in range(d.squad_growth):   # новые бойцы уровня — с полным HP, как Squad.merge_upgrade
			d.saved_hp.append(1.0)
		return "%s — уровень %d/%d" % [d.unit_name, d.squad_level, UnitFactory.MAX_SQUAD_LEVEL]
	if e.has("heal_army"):
		for d in BattleManager.player_units:
			var hp: Array[float] = []
			for i in range(maxi(d.squad_size, 1)):
				hp.append(1.0)
			d.saved_hp = hp
		return "Армия в строю: полный состав, полное здоровье"
	if e.has("building_level"):
		var options = _upgradable_buildings()
		if options.is_empty():
			return "Нечего освящать"
		var card: CardData = options[rng.randi() % options.size()]
		card.level_up_building()
		return "%s — уровень %d" % [card.title, card.building_level]
	if e.has("enemy_hp"):
		BattleManager.next_battle_enemy_hp *= e["enemy_hp"]
		BattleManager.next_battle_note = e.get("note", "")
		return e.get("note", "")
	push_warning("RunEvents: неизвестный эффект %s" % e)
	return ""

# Урон цитадели вне боя: событие не заканчивает забег — остаётся хотя бы 1 HP
static func _damage_citadel(amount: float) -> float:
	var dealt = minf(amount, BattleManager.citadel_hp - 1.0)
	BattleManager.citadel_hp -= dealt
	BattleManager.citadel_hp_changed.emit(BattleManager.citadel_hp)
	return dealt

static func _upgradable_buildings() -> Array:
	return BattleManager.player_buildings.keys().filter(func(c): return c.building_level < CardData.MAX_BUILDING_LEVEL)

static func _give_card(rng: RandomNumberGenerator, rarity: String, card_type: String) -> String:
	var options: Array = []
	for card in CardFactory.build_pool():
		if (rarity == "" or card.rarity == rarity) and (card_type == "" or card.card_type == card_type):
			options.append(card)
	if options.is_empty():
		return "Ничего не нашлось"
	var card: CardData = options[rng.randi() % options.size()]
	if BattleManager.pending_cards.size() >= BattleManager.MAX_HAND_SIZE:
		var refund = EconomyManager.get_sell_price(card)
		EconomyManager.add_requisition(refund)
		return "Рука полна — %s обменяна на +%d Req" % [card.title, refund]
	BattleManager.pending_cards.append(card)
	return "В руку: %s" % card.title
