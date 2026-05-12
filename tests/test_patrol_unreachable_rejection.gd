extends SceneTree

# Phase 3 follow-up: when a placement (add or drag-end) would create an
# unreachable segment, EditMode pops an error dialog and refuses the edit.
# Run: godot --headless -s tests/test_patrol_unreachable_rejection.gd


func _initialize() -> void:
	var fail := 0
	var pass_ := 0

	# A circular obstacle at (5, 0) radius 1.0. After Pathfinder's 0.5 m
	# CHAR_RADIUS inflation, the goal (5, 0) sits AT the obstacle center, so
	# every edge into it crosses the inflated circle — find_path returns
	# empty. Wall-box geometry routes through corners; circular is tighter.
	var level := Node2D.new()
	level.name = "Level1"
	var lvl_script := GDScript.new()
	lvl_script.source_code = """
extends Node2D
func get_wall_segments() -> Array:
	return []
func get_chest_obstacle() -> Dictionary:
	return {\"center\": Vector2(5.0, 0.0), \"radius\": 1.0}
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

	var em_script := load("res://scripts/EditMode.gd")
	var em: Node = Node2D.new()
	em.set_script(em_script)
	em.name = "EditMode"
	level.add_child(em)
	await process_frame
	await process_frame
	em.call("_toggle")
	await process_frame
	em.call("_on_object_button_pressed", enemy)
	await process_frame
	em.call("_patrol_toggle_edit_mode")

	# 1. Helper: (0,0) → (5,0) crosses into the walled box → unreachable.
	if not bool(em.call("_patrol_is_reachable", Vector2(0, 0), Vector2(5, 0))):
		pass_ += 1
		print("PASS  _patrol_is_reachable((0,0)→(5,0)) = false")
	else:
		fail += 1
		printerr("FAIL  expected (0,0)→(5,0) unreachable but pathfinder routed through")

	# 2. Helper: (0,0) → (0,5) clear path → reachable.
	if bool(em.call("_patrol_is_reachable", Vector2(0, 0), Vector2(0, 5))):
		pass_ += 1
		print("PASS  _patrol_is_reachable((0,0)→(0,5)) = true")
	else:
		fail += 1
		printerr("FAIL  expected (0,0)→(0,5) reachable")

	# 3. First add always succeeds (no prior point to validate against).
	var undo_baseline := (em.get("undo_stack") as Array).size()
	em.call("_patrol_add_point_at", Vector2(0, 0))
	var pts: Array = ((em.get("_patrol_data") as Dictionary)["fake_enemy_1"] as Dictionary)["points"]
	if pts.size() == 1 and pts[0] == Vector2(0, 0):
		pass_ += 1
		print("PASS  first add succeeds (no prior segment to check)")
	else:
		fail += 1
		printerr("FAIL  first add did not land (pts=%s)" % [pts])

	# 4. Second add into the unreachable zone is rejected: no append, no undo.
	em.call("_patrol_add_point_at", Vector2(5, 0))
	pts = ((em.get("_patrol_data") as Dictionary)["fake_enemy_1"] as Dictionary)["points"]
	var undo_now := (em.get("undo_stack") as Array).size()
	if pts.size() == 1 and undo_now == undo_baseline + 1:
		pass_ += 1
		print("PASS  unreachable add rejected; pts size unchanged; only the prior add on undo stack")
	else:
		fail += 1
		printerr("FAIL  rejection failed (pts=%s, undo_delta=%d)" \
				% [pts, undo_now - undo_baseline])

	# 5. Second add to a reachable target succeeds.
	em.call("_patrol_add_point_at", Vector2(0, 5))
	pts = ((em.get("_patrol_data") as Dictionary)["fake_enemy_1"] as Dictionary)["points"]
	if pts.size() == 2 and pts[1] == Vector2(0, 5):
		pass_ += 1
		print("PASS  reachable second add succeeds")
	else:
		fail += 1
		printerr("FAIL  reachable add did not land (pts=%s)" % [pts])

	# 6. Drag-update mutates live (rejection only fires on drag_end).
	em.call("_patrol_drag_begin", Vector2(0.05, 5.05))  # near pts[1]
	em.call("_patrol_drag_update", Vector2(5, 0))       # land in unreachable zone
	pts = ((em.get("_patrol_data") as Dictionary)["fake_enemy_1"] as Dictionary)["points"]
	if pts[1] == Vector2(5, 0):
		pass_ += 1
		print("PASS  drag_update mutates live (no in-flight reachability gate)")
	else:
		fail += 1
		printerr("FAIL  drag_update did not mutate (got %s)" % [pts[1]])

	# 7. drag_end with unreachable target reverts; no undo entry pushed.
	var undo_before_end := (em.get("undo_stack") as Array).size()
	em.call("_patrol_drag_end")
	pts = ((em.get("_patrol_data") as Dictionary)["fake_enemy_1"] as Dictionary)["points"]
	var undo_after_end := (em.get("undo_stack") as Array).size()
	if pts[1] == Vector2(0, 5) and undo_after_end == undo_before_end:
		pass_ += 1
		print("PASS  drag_end rejected; point reverted to origin; no undo pushed")
	else:
		fail += 1
		printerr("FAIL  drag_end did not revert (pts[1]=%s, undo_delta=%d)" \
				% [pts[1], undo_after_end - undo_before_end])

	# 8. Reachable drag commits and pushes one undo entry.
	em.call("_patrol_drag_begin", Vector2(0.05, 5.05))
	em.call("_patrol_drag_update", Vector2(0, 7))
	em.call("_patrol_drag_end")
	pts = ((em.get("_patrol_data") as Dictionary)["fake_enemy_1"] as Dictionary)["points"]
	var undo_after_good := (em.get("undo_stack") as Array).size()
	if pts[1] == Vector2(0, 7) and undo_after_good == undo_after_end + 1:
		pass_ += 1
		print("PASS  reachable drag commits + pushes one undo entry")
	else:
		fail += 1
		printerr("FAIL  reachable drag did not commit (pts[1]=%s, undo_delta=%d)" \
				% [pts[1], undo_after_good - undo_after_end])

	em.queue_free()
	level.queue_free()
	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
