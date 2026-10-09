extends Node

# -------------------------------------------------------
# СОХРАНЕНИЕ ЗАБЕГА
# -------------------------------------------------------
# Один слот: user://run_save.json. Пишется автоматически:
#   * вход в магазин и каждое действие в нём (покупка, продажа, обновление);
#   * вход в бой (состояние до расстановки) и итог боя;
# удаляется в конце забега (победа / цитадель пала) и при новом забеге.
# Закрыли игру посреди боя — бой начнётся заново с расстановки.
#
# Отряды и карты хранятся по id фабрик (UnitFactory / CardFactory) + состояние
# отряда; при загрузке собираются заново — правки баланса применяются и к
# старому сохранению. Граф забега не хранится: RunMapData.generate() детерминирован.
const SAVE_PATH: String = "user://run_save.json"
# Путь файла; tests/test_save.gd подменяет его на свой, чтобы не трогать сохранение игрока
var save_path: String = SAVE_PATH
const SAVE_VERSION: int = 1

# Тесты и симуляции (tests/*.gd) выключают запись, чтобы не затереть
# настоящее сохранение игрока: root.get_node("SaveManager").enabled = false
var enabled: bool = true

func has_save() -> bool:
	return FileAccess.file_exists(save_path)

func delete_save() -> void:
	if enabled and has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
		print("SaveManager: сохранение удалено")

# -------------------------------------------------------
# ЗАПИСЬ
# -------------------------------------------------------
func save_run() -> bool:
	if not enabled or RunManager.map == null or RunManager.run_won:
		return false
	var units: Array = []
	for d in BattleManager.player_units:
		var u = _unit_to_dict(d)
		if BattleManager.player_placements.has(d):
			u["tile"] = _v2i_to_arr(BattleManager.player_placements[d])
		units.append(u)
	var buildings: Array = []
	for card in BattleManager.player_buildings:
		buildings.append({"card": card.id, "tile": _v2i_to_arr(BattleManager.player_buildings[card])})
	var kingdom: Array = []
	for t in BattleManager.kingdom_tiles:
		kingdom.append(_v2i_to_arr(t))
	var data = {
		"version": SAVE_VERSION,
		"run": {
			"rng_seed": str(RunManager.rng.seed),
			"rng_state": str(RunManager.rng.state),
			"current_node_id": RunManager.current_node_id,
			"current_completed": RunManager.current_completed,
		},
		"economy": {
			"requisition": EconomyManager.requisition,
			"salvage": EconomyManager.salvage,
			"wins": EconomyManager.wins,
			"round_number": EconomyManager.round_number,
		},
		"synergy": {"epic_discount_pending": SynergyManager.epic_discount_pending},
		"battle": {
			"citadel_hp": BattleManager.citadel_hp,
			"kingdom_tiles": kingdom,
			"tiles_bought": BattleManager.tiles_bought,
			"units": units,
			"buildings": buildings,
			"hand": _card_ids(BattleManager.pending_cards),
		},
		"shop": {
			"node_id": ShopManager.shop_node_id,
			"offers": _card_ids(ShopManager.current_offers),
			"rerolls_done": ShopManager.rerolls_done,
			"free_cards_left": ShopManager.free_cards_left,
		},
	}
	var f = FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: не удалось записать %s (%s)" % [save_path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

# -------------------------------------------------------
# ЧТЕНИЕ
# -------------------------------------------------------
# Восстанавливает состояние автолоадов. Сцену не меняет — дальше RunManager.resume().
func load_run() -> bool:
	if not has_save():
		return false
	var text = FileAccess.get_file_as_string(save_path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("SaveManager: сохранение повреждено или старой версии — игнорирую")
		return false

	BattleManager.reset_run()   # чистое состояние (зовёт RunManager.new_run)

	var run: Dictionary = data["run"]
	# seed/state — 64-битные, в JSON строками (число потеряло бы точность); state — после seed
	RunManager.rng.seed = str(run["rng_seed"]).to_int()
	RunManager.rng.state = str(run["rng_state"]).to_int()
	RunManager.current_node_id = int(run["current_node_id"])
	RunManager.current_completed = bool(run["current_completed"])

	var eco: Dictionary = data["economy"]
	EconomyManager.requisition = int(eco["requisition"])
	EconomyManager.salvage = int(eco["salvage"])
	EconomyManager.wins = int(eco["wins"])
	EconomyManager.round_number = int(eco["round_number"])
	SynergyManager.epic_discount_pending = int(data["synergy"]["epic_discount_pending"])

	var b: Dictionary = data["battle"]
	BattleManager.citadel_hp = float(b["citadel_hp"])
	BattleManager.kingdom_tiles.clear()
	for t in b["kingdom_tiles"]:
		BattleManager.kingdom_tiles.append(_arr_to_v2i(t))
	BattleManager.tiles_bought = int(b["tiles_bought"])
	for u in b["units"]:
		var d = _unit_from_dict(u)
		BattleManager.player_units.append(d)
		if u.has("tile"):
			BattleManager.player_placements[d] = _arr_to_v2i(u["tile"])
	for entry in b["buildings"]:
		var card = CardFactory.create(entry["card"])
		if card:
			BattleManager.player_buildings[card] = _arr_to_v2i(entry["tile"])
	BattleManager.pending_cards = _cards_from_ids(b["hand"])

	var shop: Dictionary = data["shop"]
	ShopManager.shop_node_id = int(shop["node_id"])
	ShopManager.current_offers = _cards_from_ids(shop["offers"])
	ShopManager.rerolls_done = int(shop["rerolls_done"])
	ShopManager.free_cards_left = int(shop["free_cards_left"])

	EconomyManager.emit_signal("requisition_changed", EconomyManager.requisition)
	BattleManager.emit_signal("citadel_hp_changed", BattleManager.citadel_hp)
	print("SaveManager: забег загружен — волна %d, шаг %d, %d Req, отрядов %d, карт в руке %d" % [
		EconomyManager.round_number, RunManager.current_node_id, EconomyManager.requisition,
		BattleManager.player_units.size(), BattleManager.pending_cards.size()])
	return true

# -------------------------------------------------------
# СЕРИАЛИЗАЦИЯ
# -------------------------------------------------------
func _unit_to_dict(d: UnitData) -> Dictionary:
	return {
		"id": d.factory_id,
		"saved_hp": Array(d.saved_hp),
		"hp_mult": d.hp_multiplier,
		"dmg_mult": d.damage_multiplier,
		"as_mult": d.attack_speed_multiplier,
		"upgrades": Array(d.applied_upgrades),
		"squad_size": d.squad_size,
		"level": d.squad_level,
	}

func _unit_from_dict(u: Dictionary) -> UnitData:
	var d = UnitFactory.create(u["id"])
	var hp: Array[float] = []
	for v in u["saved_hp"]:
		hp.append(float(v))
	d.saved_hp = hp
	d.hp_multiplier = float(u["hp_mult"])
	d.damage_multiplier = float(u["dmg_mult"])
	d.attack_speed_multiplier = float(u["as_mult"])
	var ups: Array[String] = []
	for s in u["upgrades"]:
		ups.append(str(s))
	d.applied_upgrades = ups
	d.squad_size = int(u["squad_size"])
	d.squad_level = int(u["level"])
	return d

func _card_ids(cards: Array) -> Array:
	var ids: Array = []
	for c in cards:
		ids.append(c.id)
	return ids

func _cards_from_ids(ids: Array) -> Array[CardData]:
	var cards: Array[CardData] = []
	for id in ids:
		var c = CardFactory.create(str(id))
		if c:
			cards.append(c)
	return cards

func _v2i_to_arr(v: Vector2i) -> Array:
	return [v.x, v.y]

func _arr_to_v2i(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))
