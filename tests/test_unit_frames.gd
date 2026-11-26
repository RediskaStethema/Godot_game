extends SceneTree

# Кадры юнитов Космодесанта (16.11.2026: перерисовка Layer, конвейер tools/units_pipeline.py): ноги стоят на земле, стойка не
# «кипит», яркость в границах игры, у стрелков есть кадр выстрела и ствол внутри холста. Читает PNG напрямую (без импорта).
# Scout не проверяется (оригинальные кадры). Пороги — по замеру после конвейера (STATE.md юнитов):
#   стойка: зазор ног до низа холста ≤ IDLE_GAP (парящий Land Speeder — HOVER_GAP), соседние кадры отличаются меньше IDLE_DIFF;
#   бег: хотя бы один кадр касается земли (≤ RUN_TOUCH), ни один не выше RUN_MAX_GAP;
#   яркость: средняя в BRIGHT_MIN..BRIGHT_MAX, пикселей ярче 0.8 не больше BRIGHT_SHARE (было 12–20% — «пересвет»);
#   стрелки: shot_frame в пределах ряда attack, muzzle — внутри холста.
#   godot --headless --path . -s tests/test_unit_frames.gd

const DIR = "res://assets/units/space_marines/"
const UNITS = ["apothecary", "assault", "centurion", "chaplain", "chapter_master", "devastator", "dreadnought", "firedrakes",
	"honour_guard", "land_speeder", "librarian", "sanguinary_guard", "tactical", "terminator", "thunderwolf"]
const SHOOTERS = ["tactical", "devastator", "centurion", "chaplain", "land_speeder", "librarian", "firedrakes", "dreadnought"]
const HOVER = ["land_speeder"]
const IDLE_GAP: int = 2
const HOVER_GAP: int = 14
const IDLE_DIFF: float = 0.10
const RUN_TOUCH: int = 3
const RUN_MAX_GAP: int = 20
const BRIGHT_MIN: float = 0.24
const BRIGHT_MAX: float = 0.36
const BRIGHT_SHARE: float = 0.07
const SAMPLE: int = 3   # шаг выборки пикселей при сравнении кадров

func _initialize() -> void:
	_main()

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _frames(unit: String, anim: String) -> Array:
	var out: Array = []
	var i := 0
	while true:
		var path := ProjectSettings.globalize_path(DIR + "%s/%s/%d.png" % [unit, anim, i])
		if not FileAccess.file_exists(path):
			break
		var img := Image.load_from_file(path)
		img.convert(Image.FORMAT_RGBA8)
		out.append(img)
		i += 1
	return out

# Зазор между самым низким непрозрачным пикселем и низом холста
func _gap(img: Image) -> int:
	for y in range(img.get_height() - 1, -1, -1):
		for x in range(0, img.get_width(), 2):
			if img.get_pixel(x, y).a > 0.16:
				return img.get_height() - 1 - y
	return img.get_height()

# Средняя яркость (V по HSV) непрозрачных пикселей и доля ярче 0.8
func _bright(img: Image) -> Vector2:
	var sum := 0.0
	var hi := 0
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				sum += c.v
				n += 1
				if c.v > 0.8:
					hi += 1
	return Vector2(sum / maxf(n, 1), float(hi) / maxf(n, 1))

# Доля силуэта кадра a, пиксели которого заметно отличаются от кадра b
func _diff(a: Image, b: Image) -> float:
	var changed := 0
	var area := 0
	for y in range(0, a.get_height(), SAMPLE):
		for x in range(0, a.get_width(), SAMPLE):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if ca.a > 0.16:
				area += 1
			if (ca.a > 0.16 or cb.a > 0.16) and (absf(ca.a - cb.a) > 0.4 or maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))) > 0.17):
				changed += 1
	return float(changed) / maxf(area, 1)

func _main() -> void:
	await process_frame
	var bad_gap: Array = []
	var bad_diff: Array = []
	var bad_run: Array = []
	var bad_bright: Array = []
	var bad_meta: Array = []
	var worst_diff := 0.0
	for u in UNITS:
		var idle := _frames(u, "idle")
		var run := _frames(u, "run")
		if idle.size() < 3 or run.size() < 3:
			bad_gap.append("%s: кадров idle %d / run %d" % [u, idle.size(), run.size()])
			continue
		var gap := _gap(idle[0])
		if gap > (HOVER_GAP if u in HOVER else IDLE_GAP):
			bad_gap.append("%s idle зазор %d" % [u, gap])
		var d_sum := 0.0
		for i in range(1, idle.size()):
			d_sum += _diff(idle[i], idle[i - 1])
		var d_mean: float = d_sum / float(idle.size() - 1)
		worst_diff = maxf(worst_diff, d_mean)
		if d_mean > IDLE_DIFF:
			bad_diff.append("%s %.2f" % [u, d_mean])
		var touch := 999
		var top := 0
		for im in run:
			var g := _gap(im)
			touch = mini(touch, g)
			top = maxi(top, g)
		if u not in HOVER and (touch > RUN_TOUCH or top > RUN_MAX_GAP):
			bad_run.append("%s бег: касание %d, максимум %d" % [u, touch, top])
		var b := _bright(idle[0])
		if b.x < BRIGHT_MIN or b.x > BRIGHT_MAX or b.y > BRIGHT_SHARE:
			bad_bright.append("%s яркость %.2f, ярких %.1f%%" % [u, b.x, b.y * 100.0])
		if u in SHOOTERS:
			var fr: SpriteFrames = load(DIR + u + "/frames.tres")
			var shot: int = fr.get_meta("shot_frame", -1)
			var muzzle: Vector2 = fr.get_meta("muzzle", Vector2.INF)
			var atk := fr.get_frame_count("attack")
			var tex_w := fr.get_frame_texture("attack", 0).get_width()
			var tex_h := fr.get_frame_texture("attack", 0).get_height()
			if shot < 0 or shot >= atk or absf(muzzle.x) > tex_w * 0.5 or muzzle.y > 0.0 or muzzle.y < -tex_h:
				bad_meta.append("%s shot_frame %d (кадров %d), muzzle %s" % [u, shot, atk, muzzle])
	_check("ноги: стойка стоит на земле у всех %d юнитов %s" % [UNITS.size(), bad_gap], bad_gap.is_empty())
	_check("стойка не кипит: отличие соседних кадров ≤ %.2f (худшее %.2f) %s" % [IDLE_DIFF, worst_diff, bad_diff], bad_diff.is_empty())
	_check("бег: ноги касаются земли и не висят выше %d px %s" % [RUN_MAX_GAP, bad_run], bad_run.is_empty())
	_check("яркость %.2f–%.2f, пересвета ≤ %d%% %s" % [BRIGHT_MIN, BRIGHT_MAX, int(BRIGHT_SHARE * 100), bad_bright], bad_bright.is_empty())
	_check("стрелки: кадр выстрела и ствол на месте %s" % [bad_meta], bad_meta.is_empty())
	quit()
