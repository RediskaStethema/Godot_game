extends SceneTree

# Сочность боя (18.11.2026, только вид): слабая тряска камеры не перебивает сильную, ещё не угасшую.
# Запуск: godot --headless --path . -s tests/test_juice.gd
# (IsoGridRenderer / Soldier здесь не грузятся — они зовут автолоады, скрипты `-s` компилируются до них)

var _fails := 0

func _check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1

func _init() -> void:
	var cam = load("res://scripts/battle/BattleCamera.gd").new()
	root.add_child(cam)
	cam.shake(6.0)
	cam.shake(1.0)   # шаг босса сразу после удара приёма
	_check(is_equal_approx(cam.get("_shake_peak"), 6.0), "слабая тряска не перебила сильную (пик %.1f)" % cam.get("_shake_peak"))
	cam.shake(9.0)
	_check(is_equal_approx(cam.get("_shake_peak"), 9.0), "более сильная заменила (пик %.1f)" % cam.get("_shake_peak"))
	cam.queue_free()
	print("test_juice: %s" % ("OK" if _fails == 0 else "%d провалов" % _fails))
	quit(1 if _fails > 0 else 0)
