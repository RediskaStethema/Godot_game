extends SceneTree

# Компиляция всех шейдеров проекта без окна (навык godot-shaders, Pattern 4): файлы .gdshader и шейдеры строкой
# в скриптах (кровь, снаряды) — load() ленивый, компиляцию вызывает get_shader_uniform_list().
#   godot --headless --path . -s tests/compile_shaders.gd > shaders.log 2>&1
#   grep -nE "SHADER ERROR|Shader compilation failed" shaders.log   — пусто = всё компилируется
# Классы сцен по имени не упоминаются (скрипт -s компилируется до автолоадов) — строки шейдеров берутся из
# констант скриптов через load().

const INLINE := [
	["res://scripts/battle/Vfx.gd", "BLOOD_SHADER"],
	["res://scripts/battle/Projectile.gd", "TINT_SHADER"],
	["res://scripts/battle/Projectile.gd", "WARM_SHADER"],
]

func _initialize() -> void:
	var paths := _find("res://", "gdshader")
	for path in paths:
		print("compiling ", path)   # SHADER ERROR печатается сразу после
		var shader := load(path) as Shader
		print("  uniforms: ", shader.get_shader_uniform_list().size())
	for it in INLINE:
		var code = load(it[0]).get_script_constant_map().get(it[1], "")
		print("compiling ", it[0], " ", it[1])
		var s := Shader.new()
		s.code = code
		print("  uniforms: ", s.get_shader_uniform_list().size())
	print("Compiled %d shaders" % (paths.size() + INLINE.size()))
	quit(0)

func _find(dir: String, ext: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == ext:
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with(".") and sub != "addons" and not sub.begins_with("godot_agent"):
			found.append_array(_find(dir.path_join(sub), ext))
	return found
