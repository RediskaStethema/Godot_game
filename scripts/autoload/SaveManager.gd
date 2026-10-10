extends Node

# -------------------------------------------------------
# СОХРАНЕНИЕ ЗАБЕГА
# -------------------------------------------------------
# Один слот: user://run_save.json. Каждая система из SYSTEMS сама отдаёт и
# принимает своё состояние (save_state() / load_state(d)) — новое поле забега
# добавляется в той же системе, здесь ничего менять не нужно. Новая система —
# строка в SYSTEMS (порядок = порядок загрузки).
#
# Пишется автоматически: вход в магазин и каждое действие в нём; вход в бой,
# каждое действие расстановки, «В БОЙ» и итог боя. Удаляется в конце забега и
# при новом забеге. Закрыли игру посреди боя — армия встаёт как была и бой
# сразу начинается заново; ход самой схватки не сохраняется.
const SAVE_PATH: String = "user://run_save.json"
# v2 — состояние по системам; сохранения v1 не читаются
const SAVE_VERSION: int = 2
const SYSTEMS: Array[String] = ["RunManager", "EconomyManager", "SynergyManager", "BattleManager", "ShopManager"]

# Путь файла; tests/test_save.gd подменяет его на свой, чтобы не трогать сохранение игрока
var save_path: String = SAVE_PATH
# Тесты и симуляции (tests/*.gd) выключают запись, чтобы не затереть
# настоящее сохранение игрока: root.get_node("SaveManager").enabled = false
var enabled: bool = true

func has_save() -> bool:
	return FileAccess.file_exists(save_path)

func delete_save() -> void:
	if enabled and has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
		print("SaveManager: сохранение удалено")

func save_run() -> bool:
	if not enabled or RunManager.map == null or RunManager.run_won:
		return false
	var data = {"version": SAVE_VERSION}
	for system in SYSTEMS:
		data[system] = _system(system).save_state()
	var f = FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: не удалось записать %s (%s)" % [save_path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

# Восстанавливает состояние систем. Сцену не меняет — дальше RunManager.resume().
func load_run() -> bool:
	if not has_save():
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("SaveManager: сохранение повреждено или старой версии — игнорирую")
		return false
	BattleManager.reset_run()   # чистое состояние всех систем
	for system in SYSTEMS:
		if data.has(system):
			_system(system).load_state(data[system])
	print("SaveManager: забег загружен — волна %d, шаг %d, %d Req, отрядов %d, карт в руке %d" % [
		EconomyManager.round_number, RunManager.current_node_id, EconomyManager.requisition,
		BattleManager.player_units.size(), BattleManager.pending_cards.size()])
	return true

func _system(system_name: String) -> Node:
	return get_node("/root/" + system_name)
