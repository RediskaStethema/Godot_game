extends SceneTree

# Все листы кадров (frames.tres в assets/sprites): каждый кадр каждой анимации загружается и не пустой.
# Решение пользователя 19.10.2026: Апотекарион «на 1 кадр исчезал» — кадр не импортировался (valid=false
# в .import), а SpriteFrames молча показывал пустоту.
#   godot --headless --path . -s tests/test_sprite_sheets.gd

const ROOT = "res://assets/sprites"

var _fails := 0

func _initialize() -> void:
	var sheets: Array[String] = []
	_collect(ROOT, sheets)
	var broken: Array[String] = []
	var frames_total := 0
	for path in sheets:
		var sf = load(path) as SpriteFrames
		if sf == null:
			broken.append(path)
			continue
		for anim in sf.get_animation_names():
			for i in sf.get_frame_count(anim):
				frames_total += 1
				var tex := sf.get_frame_texture(anim, i)
				if tex == null or tex.get_width() == 0:
					broken.append("%s %s/%d" % [path, anim, i])
	_check("листов %d, кадров %d — все загружаются%s" % [sheets.size(), frames_total,
		"" if broken.is_empty() else ": " + ", ".join(broken.slice(0, 10))], broken.is_empty() and sheets.size() > 30)
	quit(1 if _fails > 0 else 0)

func _collect(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f == "frames.tres":
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)

func _check(name: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok:
		_fails += 1
