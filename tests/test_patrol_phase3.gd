extends SceneTree

# Phase 3 patrol lines: per-guard pathfinder-routed polyline cache, segments
# classified reachable / unreachable, O toggles all-guards visibility, edits
# invalidate the cache.
# Run: godot --headless -s tests/test_patrol_phase3.gd


func _initialize() -> void:
	var fail := 0
	var pass_ := 0

	var level := Node2D.new()
	level.name = "Level1"
	# Attach an inline script so the level exposes get_wall_segments /
	# get_chest_obstacle, matching the contract EditMode's pathfinder builder
	# expects from level_1.gd. No walls, no chest → all reachable.
	var lvl_script := GDScript.new()
	lvl_script.source_code = """
extends Node2D
func get_wall_segments() -> Array:
	return []
func get_chest_obstacle() -> Dictionary:
	return {\"center\": Vector2.ZERO, \"radius\": 0.0}
"""
	lvl_script.reload()
	level.set_script(lvl_script)
	root.add_child(level)

	var objects := Node2D.new()
	objects.name = "Objects"
	level.add_child(objects)

	var enemy := Node2D.new()
	enemy.name = "fake_enemy_1"
	enemy.add_to_group("editable")
	enemy.set_meta("recognition_priority", 50)
	var enemy_sprite := Sprite2D.new()
	enemy_sprite.name = "Sprite"
	enemy_sprite.centered = true
	enemy_sprite.texture = load("res://assets/level1/CCTV.png")
	enemy.add_child(enemy_sprite)
	objects.add_child(enemy)

	# A second enemy for the "all patrols" test.
	var enemy2 := Node2D.new()
	enemy2.name = "fake_enemy_2"
	enemy2.add_to_group("editable")
	enemy2.set_meta("recognition_priority", 50)
	var enemy2_sprite := Sprite2D.new()
	enemy2_sprite.name = "Sprite"
	enemy2_sprite.centered = true
	enemy2_sprite.texture = load("res://assets/level1/CCTV.png")
	enemy2.add_child(enemy2_sprite)
	objects.add_child(enemy2)

	var em_script := load("res://scripts/EditMode.gd")
	var em: Node = Node2D.new()
	em.set_script(em_script)
	em.name = "EditMode"
	level.add_child(em)
	await process_frame
	await process_frame
	em.call("_toggle")
	await process_frame

	# Select enemy 1, enter patrol-edit, add 3 points (2 line segments).
	em.call("_on_object_button_pressed", enemy)
	await process_frame
	em.call("_patrol_toggle_edit_mode")
	em.call("_patrol_add_point_at", Vector2(0.0, 0.0))
	em.call("_patrol_add_point_at", Vector2(2.0, 0.0))
	em.call("_patrol_add_point_at", Vector2(2.0, 2.0))

	# 1. Cache starts empty / cleared by the _persist that fired on each add.
	# Force a rebuild and inspect the result.
	em.call("_rebuild_patrol_line", "fake_enemy_1")
	var cache: Dictionary = em.get("_patrol_line_cache")
	var segs: Array = cache.get("fake_enemy_1", [])
	if segs.size() == 2:
		pass_ += 1
		print("PASS  3 patrol points → 2 cached segments")
	else:
		fail += 1
		printerr("FAIL  expected 2 segments, got %d" % segs.size())

	# 2. With no walls / obstacles, both segments are reachable.
	var both_reachable: bool = true
	for s in segs:
		if not bool(s.get("reachable", false)):
			both_reachable = false
	if both_reachable:
		pass_ += 1
		print("PASS  both segments classified reachable (no obstacles)")
	else:
		fail += 1
		printerr("FAIL  some segment marked unreachable in obstacle-free level")

	# 3. Reachable segments carry a polyline of projected iso-pixel points; ≥2
	# vertices per segment so draw_line has something to render.
	var polylines_ok: bool = true
	for s in segs:
		var pl: Array = s.get("polyline", [])
		if pl.size() < 2:
			polylines_ok = false
	if polylines_ok:
		pass_ += 1
		print("PASS  every reachable segment has a polyline with ≥2 vertices")
	else:
		fail += 1
		printerr("FAIL  a reachable segment has < 2 polyline vertices")

	# 4. Polyline vertices are projected (iso-pixel space), not raw world meters.
	# Spot-check segment 0's first vertex: IsoMath.project((0,0)) == (0,0), and
	# its endpoint should be IsoMath.project((2,0)) ≈ (55.43, -32) (cos30*PPM*2,
	# -sin30*PPM*2). Inlined — autoloads aren't in scope from extends SceneTree.
	var first_v: Vector2 = (segs[0]["polyline"] as Array)[0]
	var last_v: Vector2 = (segs[0]["polyline"] as Array)[-1]
	var expected_last := Vector2(0.8660254 * 32.0 * 2.0, 0.5 * 32.0 * 2.0)  # (2,0) projected
	if first_v.distance_to(Vector2.ZERO) < 0.001 and last_v.distance_to(expected_last) < 0.01:
		pass_ += 1
		print("PASS  segment 0 polyline endpoints match IsoMath.project")
	else:
		fail += 1
		printerr("FAIL  endpoints first=%s last=%s expected_last=%s" \
				% [first_v, last_v, expected_last])

	# 5. Editing a point invalidates the cached line for that guard.
	em.call("_patrol_add_point_at", Vector2(0.0, 2.0))  # 4th point → 3 segments
	cache = em.get("_patrol_line_cache")
	if not cache.has("fake_enemy_1"):
		pass_ += 1
		print("PASS  adding a point invalidates the guard's cached line")
	else:
		fail += 1
		printerr("FAIL  cache not invalidated on add (still has fake_enemy_1)")

	em.call("_rebuild_patrol_line", "fake_enemy_1")
	segs = (em.get("_patrol_line_cache") as Dictionary)["fake_enemy_1"]
	if segs.size() == 3:
		pass_ += 1
		print("PASS  after adding point: 4 points → 3 segments")
	else:
		fail += 1
		printerr("FAIL  expected 3 segments, got %d" % segs.size())

	# 6. Drag-update invalidates the cache mid-drag (so the line follows the cursor).
	em.call("_patrol_drag_begin", Vector2(0.05, 0.05))
	em.call("_patrol_drag_update", Vector2(5.0, 5.0))
	cache = em.get("_patrol_line_cache")
	if not cache.has("fake_enemy_1"):
		pass_ += 1
		print("PASS  drag_update invalidates cache mid-drag")
	else:
		fail += 1
		printerr("FAIL  drag_update did not invalidate cache")
	em.call("_patrol_drag_end")

	# 7. Undo (which calls _persist) invalidates the cache.
	em.call("_rebuild_patrol_line", "fake_enemy_1")
	em.call("_undo")
	cache = em.get("_patrol_line_cache")
	if not cache.has("fake_enemy_1"):
		pass_ += 1
		print("PASS  undo invalidates cache via _persist")
	else:
		fail += 1
		printerr("FAIL  undo did not invalidate cache")

	# 8. O key toggles _show_all_patrols flag (starts false).
	if not bool(em.get("_show_all_patrols")):
		pass_ += 1
		print("PASS  _show_all_patrols defaults to false")
	else:
		fail += 1
		printerr("FAIL  _show_all_patrols defaulted true")

	# Simulate O press by sending the key event.
	var o_evt := InputEventKey.new()
	o_evt.keycode = KEY_O
	o_evt.pressed = true
	em.call("_unhandled_input", o_evt)
	if bool(em.get("_show_all_patrols")):
		pass_ += 1
		print("PASS  O press toggled _show_all_patrols on")
	else:
		fail += 1
		printerr("FAIL  O press did not toggle flag")

	em.call("_unhandled_input", o_evt)
	if not bool(em.get("_show_all_patrols")):
		pass_ += 1
		print("PASS  second O press toggled off")
	else:
		fail += 1
		printerr("FAIL  second O press did not toggle off")

	# 9. F4 deactivate resets _show_all_patrols and clears the cache.
	em.call("_unhandled_input", o_evt)  # turn back on
	em.call("_force_deactivate")
	cache = em.get("_patrol_line_cache")
	if not bool(em.get("_show_all_patrols")) and cache.is_empty():
		pass_ += 1
		print("PASS  _force_deactivate reset flag and cleared cache")
	else:
		fail += 1
		printerr("FAIL  deactivate did not reset (flag=%s, cache empty=%s)"
				% [em.get("_show_all_patrols"), cache.is_empty()])

	em.queue_free()
	level.queue_free()
	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
