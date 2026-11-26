extends SceneTree

# Появление цитадели (25.11.2026): _citadel_appear прячет цитадель, запускает листы эффекта (back под ней, front поверх), потом
# она проявляется и встаёт на место. Запуск: godot --headless --path . -s tests/test_citadel_spawn.gd
var _fails := 0

func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		_fails += 1

func _initialize() -> void:
	root.get_node("GameSettings").battle_speed = 1.0
	root.get_node("SaveManager").enabled = false
	_main()

func _of_kind(kind_prefix: String) -> Array:
	var out: Array = []
	for c in root.find_children("*", "", true, false):
		if "kind" in c and str(c.kind).begins_with(kind_prefix):
			out.append(c)
	return out

func _main() -> void:
	var bm = root.get_node("BattleManager")
	var rm = root.get_node("RunManager")
	bm.reset_run()
	rm.new_run(7)
	for faction in ["space_marines", "chaos"]:
		rm.player_faction = faction
		var scene = load("res://scenes/battle/BattleScene.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
		await process_frame
		await process_frame
		var cit = bm.citadel
		var home: Vector2 = cit.position
		scene._citadel_appear(0.0)
		await process_frame
		await process_frame
		var backs := _of_kind("citadel_spawn_back")
		var fronts := _of_kind("citadel_spawn_front")
		var want_chaos: bool = faction == "chaos"
		_check("%s: эффект запущен (back %d, front %d), вид расы" % [faction, backs.size(), fronts.size()],
			backs.size() == 1 and fronts.size() == 1 and str(backs[0].kind).ends_with("_chaos") == want_chaos
			and backs[0].z_index == 0 and fronts[0].z_index > 0)
		_check("%s: цитадель скрыта и опущена в начале" % faction, cit.modulate.a < 0.5 and cit.position.y > home.y)
		await create_timer(scene.CITADEL_REVEAL_AT + scene.CITADEL_REVEAL_TIME + 0.4).timeout
		_check("%s: цитадель проявилась и встала на место" % faction, is_equal_approx(cit.modulate.a, 1.0) and cit.position.is_equal_approx(home))
		scene.queue_free()
		await process_frame
		await process_frame
	print("citadel spawn: %d fail" % _fails)
	quit()
