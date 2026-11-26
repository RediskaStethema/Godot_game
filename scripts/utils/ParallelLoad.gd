extends RefCounted

# Несколько тяжёлых ресурсов (листы кадров, листы эффектов) читаются одновременно потоками загрузчика, а не по одному
# (оптимизация 26.11.2026: 14 наборов кадров юнитов — 1.3 с по очереди, 0.2 с разом). Вызывающий получает словарь
# путь → ресурс и держит его, пока не разберёт: после этого обычный load() того же пути берёт из кэша.
# Нет файла, уже в кэше или поток не принял запрос — пути в словаре нет, его прочтёт обычный load().
# Без class_name: подключать preload.

static func load_all(paths: Array) -> Dictionary:
	# Без окна (тесты) — по очереди обычным load(): заглушечный рендер Godot не рассчитан на создание текстур из потоков
	# («Parameter "t" is null», проверка 26.11.2026); в окне 6504 загрузки потоками — без ошибок
	if DisplayServer.get_name() == "headless":
		return {}
	var pending: Array[String] = []
	for path: String in paths:
		if path in pending or ResourceLoader.has_cached(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			pending.append(path)
	var loaded := {}
	for path in pending:
		var res: Resource = ResourceLoader.load_threaded_get(path)
		if res != null:
			loaded[path] = res
	return loaded
