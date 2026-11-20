extends SceneTree

# Проверка стиля по ассетам без рендера (17.11.2026, скилл game-stylization): новый или перерисованный ассет, который
# «выбивается» (пересвет, дым на статичном кадре), ловится тестом, а не жалобой.
#   1. Здания (кадр 0 каждого ряда idle / idle_2 / idle_3 в assets/sprites/buildings, обе расы): средняя яркость не выше
#      MAX_BUILDING_MEAN (самые яркие сейчас — Апотекарион 0.40, Кодекс-бастион 0.34), доля пикселей ярче 0.8 — не больше
#      MAX_BRIGHT_SHARE (как у кадров юнитов, tests/test_unit_frames.gd).
#   2. Статичный кадр здания (кадр 0 — его показывает расстановка, Building.hold_idle_outside_battle) без отдельных
#      пятен дыма: суммарно не больше MAX_STATIC_SPECKS пикселей вне главной связной части (decision 17.11.2026: дым
#      только в анимации работы, tools/building_smoke_fade.py).
#   3. Палитра интерфейса: фон темнее панели, панель темнее текста, текст светлее приглушённого (иерархия яркости).
#   4. Цвета брони братств различимы: у каждого братства своя пара «тон тела + тон отделки», без двух одинаковых.
# Запуск: godot --headless --path . -s tests/test_style_lint.gd

const MAX_BUILDING_MEAN: float = 0.42
const MAX_BRIGHT_SHARE: float = 0.07
const MAX_STATIC_SPECKS: int = 300
# Здания, у которых отдельные части — часть рисунка, а не дым (парящие кристаллы Шпиля, языки пламени алтаря, капли чаши)
const DETACHED_BY_DESIGN: Array[String] = ["warp_spire", "skull_altar", "blood_chalice"]
const ALPHA_MIN: float = 0.5
const BUILDINGS_DIR := "res://assets/sprites/buildings"

var _fails := 0

func _check(name: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok:
		_fails += 1

func _initialize() -> void:
	_main()

func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

# Главная связная часть кадра и «остальное» (отдельные пятна): кадр — альфа > ALPHA_MIN, 8-связность
func _specks(img: Image) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			mask[y * w + x] = 1 if img.get_pixel(x, y).a > ALPHA_MIN else 0
	var seen := PackedByteArray()
	seen.resize(w * h)
	var sizes: Array[int] = []
	for start in w * h:
		if mask[start] == 0 or seen[start] == 1:
			continue
		var stack: Array[int] = [start]
		seen[start] = 1
		var n := 0
		while not stack.is_empty():
			var p: int = stack.pop_back()
			n += 1
			var px := p % w
			var py := p / w
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := px + dx
					var ny := py + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var q := ny * w + nx
					if mask[q] == 1 and seen[q] == 0:
						seen[q] = 1
						stack.append(q)
		sizes.append(n)
	if sizes.size() <= 1:
		return 0
	var total := 0
	var biggest := 0
	for s in sizes:
		total += s
		biggest = maxi(biggest, s)
	return total - biggest

func _building_rows() -> Array:
	var out: Array = []
	var dirs := ["", "chaos/"]
	var da := DirAccess.open(BUILDINGS_DIR)
	for sub in dirs:
		var root_path: String = BUILDINGS_DIR + ("/" + sub.trim_suffix("/") if sub != "" else "")
		var d := DirAccess.open(root_path)
		if d == null:
			continue
		for name in d.get_directories():
			if name == "chaos" or name.ends_with("wall"):
				continue
			for row in ["idle", "idle_2", "idle_3"]:
				var path := "%s/%s/%s/0.png" % [root_path, name, row]
				if FileAccess.file_exists(path):
					out.append([("chaos/" if sub != "" else "") + name + "/" + row, path])
	return out

func _main() -> void:
	await process_frame
	var worst_mean := 0.0
	var worst_mean_name := ""
	var worst_bright := 0.0
	var worst_bright_name := ""
	var specks_bad: Array[String] = []
	var rows := _building_rows()
	for r in rows:
		var img := Image.load_from_file(ProjectSettings.globalize_path(r[1]))   # файл PNG напрямую, без импорта
		if img == null:
			continue
		var w := img.get_width()
		var h := img.get_height()
		var sum := 0.0
		var n := 0
		var bright := 0
		for y in h:
			for x in w:
				var c := img.get_pixel(x, y)
				if c.a <= ALPHA_MIN:
					continue
				var l := _luma(c)
				sum += l
				n += 1
				if l > 0.8:
					bright += 1
		if n == 0:
			continue
		var mean := sum / n
		var share := float(bright) / n
		if mean > worst_mean:
			worst_mean = mean
			worst_mean_name = r[0]
		if share > worst_bright:
			worst_bright = share
			worst_bright_name = r[0]
		var building_name: String = String(r[0]).split("/")[-2] if String(r[0]).count("/") > 1 else String(r[0]).split("/")[0]
		var specks := 0 if DETACHED_BY_DESIGN.has(building_name) else _specks(img)
		if specks > MAX_STATIC_SPECKS:
			specks_bad.append("%s (%d px)" % [r[0], specks])
	_check("здания: %d статичных кадров, самый яркий %s — средняя %.3f ≤ %.2f" % [rows.size(), worst_mean_name, worst_mean, MAX_BUILDING_MEAN],
		not rows.is_empty() and worst_mean <= MAX_BUILDING_MEAN)
	_check("здания: засвет (> 0.8) не больше %.0f%% — максимум %.1f%% у %s" % [MAX_BRIGHT_SHARE * 100.0, worst_bright * 100.0, worst_bright_name],
		worst_bright <= MAX_BRIGHT_SHARE)
	_check("статичный кадр зданий без отдельных пятен дыма (≤ %d px, парящие части по замыслу — исключения): %s" % [MAX_STATIC_SPECKS, ", ".join(specks_bad) if not specks_bad.is_empty() else "чисто"],
		specks_bad.is_empty())

	# Иерархия яркости палитры интерфейса
	var bg := _luma(Palette.BG_DEEP)
	var mid := _luma(Palette.BG_MID)
	var panel := _luma(Palette.PANEL)
	var text := _luma(Palette.TEXT)
	var dim := _luma(Palette.TEXT_DIM)
	_check("палитра: фон (%.2f) < средний фон (%.2f), панель (%.2f) тёмная, текст (%.2f) светлее приглушённого (%.2f) и панели" % [bg, mid, panel, text, dim],
		bg < mid and panel < 0.15 and text > dim and dim > panel * 2.0)

	# Цвета брони братств различимы (тон тела / отделки не совпадают у двух братств)
	var seen: Dictionary = {}
	var dup := ""
	for c in Chapters.for_faction("space_marines"):
		var armor: Dictionary = c.get("armor", {})
		if armor.is_empty():
			dup = c["id"] + " без armor"
			break
		var key := "%.2f/%.2f|%.2f/%.2f" % [armor.get("body", {}).get("hue", -1.0), armor.get("body", {}).get("val", 0.0),
			armor.get("trim", {}).get("hue", -1.0), armor.get("trim", {}).get("sat", 0.0)]
		if seen.has(key):
			dup = "%s = %s" % [c["id"], seen[key]]
			break
		seen[key] = c["id"]
	_check("братства: у каждого своя пара цветов брони (%s)" % ("различимы" if dup == "" else dup), dup == "")

	print("test_style_lint: %s" % ("OK" if _fails == 0 else "%d провалов" % _fails))
	quit(1 if _fails > 0 else 0)
