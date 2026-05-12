extends SceneTree

# Phase 2 patrol editing: P toggles patrol-edit on a selected enemy. Inside that
# mode, left-click adds a point, right-click within 0.3 m deletes, drag moves.
# Each operation pushes an undo entry. Selection change or Esc exits the mode.
# Run: godot --headless -s tests/test_patrol_phase2.gd


func _initialize() -> void:
	var fail := 0
	var pass_ := 0

	var level := Node2D.new()
	level.name = "Level1"
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

	var wall := Sprite2D.new()
	wall.name = "Wall"
	wall.add_to_group("editable")
	wall.centered = true
	wall.texture = load("res://assets/level1/CCTV.png")
	objects.add_child(wall)

	var em_script := load("res://scripts/EditMode.gd")
	var em: Node = Node2D.new()
	em.set_script(em_script)
	em.name = "EditMode"
	level.add_child(em)
	await process_frame
	await process_frame
	em.call("_toggle")
	await process_frame

	# Select the enemy via the panel button path so _update_patrol_panel runs.
	em.call("_on_object_button_pressed", enemy)
	await process_frame

	# 1. P toggles patrol-edit on when an enemy is selected.
	em.call("_patrol_toggle_edit_mode")
	if bool(em.get("_patrol_edit_mode")):
		pass_ += 1
		print("PASS  toggle ON with enemy selected → _patrol_edit_mode true")
	else:
		fail += 1
		printerr("FAIL  toggle ON did not enter patrol-edit")

	# 2. Add 3 patrol points at distinct world positions.
	em.call("_patrol_add_point_at", Vector2(1.0, 1.0))
	em.call("_patrol_add_point_at", Vector2(2.0, 2.0))
	em.call("_patrol_add_point_at", Vector2(3.0, 3.0))
	var pts: Array = ((em.get("_patrol_data") as Dictionary)["fake_enemy_1"] as Dictionary)["points"]
	if pts.size() == 3 \
			and pts[0] == Vector2(1.0, 1.0) \
			and pts[1] == Vector2(2.0, 2.0) \
			and pts[2] == Vector2(3.0, 3.0):
		pass_ += 1
		print("PASS  3 points added at (1,1), (2,2), (3,3)")
	else:
		fail += 1
		printerr("FAIL  expected 3 points (1,1)/(2,2)/(3,3), got %s" % [pts])

	# 3. Editing marks F4 dirty.
	if bool(em.get("_dirty")):
		pass_ += 1
		print("PASS  _dirty set after adding points")
	else:
		fail += 1
		printerr("FAIL  _dirty not set after adding points")

	# 4. Patrol-panel status label reflects the live count.
	var status_label: Label = em.get("_patrol_status_label")
	if status_label.text == "Patrols: 3 points":
		pass_ += 1
		print("PASS  status label = 'Patrols: 3 points'")
	else:
		fail += 1
		printerr("FAIL  status label = '%s'" % status_label.text)

	# 5. Right-click within 0.3 m of point index 1 deletes it.
	var deleted: bool = em.call("_patrol_delete_at", Vector2(2.05, 2.05))
	pts = ((em.get("_patrol_data") as Dictionary)["fake_enemy_1"] as Dictionary)["points"]
	if deleted and pts.size() == 2 and pts[0] == Vector2(1, 1) and pts[1] == Vector2(3, 3):
		pass_ += 1
		print("PASS  right-click near (2,2) deleted index 1; remaining = (1,1)/(3,3)")
	else:
		fail += 1
		printerr("FAIL  delete result=%s, pts=%s" % [deleted, pts])

	# 6. Right-click far from any point is a no-op.
	var deleted2: bool = em.call("_patrol_delete_at", Vector2(20.0, 20.0))
	pts = ((em.get("_patrol_data") as Dictionary)["fake_enemy_1"] as Dictionary)["points"]
	if not deleted2 and pts.size() == 2:
		pass_ += 1
		print("PASS  delete far from any point is no-op")
	else:
		fail += 1
		printerr("FAIL  far-delete result=%s, pts=%s" % [deleted2, pts])

	# 7. Undo restores the deleted point at its original index.
	em.call("_undo")
	pts = ((em.get("_patrol_data") as Dictionary)["fake_enemy_1"] as Dictionary)["points"]
	if pts.size() == 3 and pts[1] == Vector2(2, 2):
		pass_ += 1
		print("PASS  undo restored deleted point at index 1")
	else:
		fail += 1
		printerr("FAIL  undo did not restore (pts=%s)" % [pts])

	# 8. Drag begin within 0.3 m of point 0 picks index 0.
	var began: bool = em.call("_patrol_drag_begin", Vector2(1.05, 1.05))
	if began and int(em.get("_patrol_drag_idx")) == 0:
		pass_ += 1
		print("PASS  drag begin on point 0")
	else:
		fail += 1
		printerr("FAIL  drag begin failed (began=%s, idx=%s)" % [began, em.get("_patrol_drag_idx")])

	# 9. Drag begin far from any point returns false.
	em.call("_patrol_drag_end")  # clean state for the next probe
	var began2: bool = em.call("_patrol_drag_begin", Vector2(50.0, 50.0))
	if not began2 and int(em.get("_patrol_drag_idx")) == -1:
		pass_ += 1
		print("PASS  drag begin far from any point is no-op")
	else:
		fail += 1
		printerr("FAIL  far drag begin should be no-op (began=%s)" % [began2])

	# 10. Begin again, update, end. Point 0 should move to release pos, and an
	# undo entry should be pushed.
	em.call("_patrol_drag_begin", Vector2(1.05, 1.05))
	em.call("_patrol_drag_update", Vector2(5.0, 5.0))
	pts = ((em.get("_patrol_data") as Dictionary)["fake_enemy_1"] as Dictionary)["points"]
	if pts[0] == Vector2(5, 5):
		pass_ += 1
		print("PASS  drag update moved point 0 to (5,5)")
	else:
		fail += 1
		printerr("FAIL  drag update did not move point 0 (got %s)" % [pts[0]])

	em.call("_patrol_drag_end")
	if int(em.get("_patrol_drag_idx")) == -1:
		pass_ += 1
		print("PASS  drag end cleared _patrol_drag_idx")
	else:
		fail += 1
		printerr("FAIL  drag end did not clear idx")

	# 11. Undo reverts the drag to the original position.
	em.call("_undo")
	pts = ((em.get("_patrol_data") as Dictionary)["fake_enemy_1"] as Dictionary)["points"]
	if pts[0] == Vector2(1, 1):
		pass_ += 1
		print("PASS  undo reverted dragged point 0 to (1,1)")
	else:
		fail += 1
		printerr("FAIL  undo did not revert drag (got %s)" % [pts[0]])

	# 12. Undo all 3 adds → empty points.
	em.call("_undo")
	em.call("_undo")
	em.call("_undo")
	pts = ((em.get("_patrol_data") as Dictionary)["fake_enemy_1"] as Dictionary)["points"]
	if pts.is_empty():
		pass_ += 1
		print("PASS  undo all 3 adds → 0 points")
	else:
		fail += 1
		printerr("FAIL  expected 0 points after 3 undos, got %d (%s)" % [pts.size(), pts])

	# 13. P again exits patrol-edit mode.
	em.call("_patrol_toggle_edit_mode")
	if not bool(em.get("_patrol_edit_mode")):
		pass_ += 1
		print("PASS  toggle OFF → _patrol_edit_mode false")
	else:
		fail += 1
		printerr("FAIL  toggle OFF did not exit patrol-edit")

	# 14. Toggle is a no-op when a non-enemy is selected.
	em.call("_on_object_button_pressed", wall)
	await process_frame
	em.call("_patrol_toggle_edit_mode")
	if not bool(em.get("_patrol_edit_mode")):
		pass_ += 1
		print("PASS  toggle with wall selected is no-op")
	else:
		fail += 1
		printerr("FAIL  patrol-edit entered with non-enemy selected")

	# 15. Selection change while in patrol-edit exits the mode automatically.
	em.call("_on_object_button_pressed", enemy)
	await process_frame
	em.call("_patrol_toggle_edit_mode")
	if not bool(em.get("_patrol_edit_mode")):
		fail += 1
		printerr("FAIL  could not re-enter patrol-edit for selection-exit test")
	em.call("_on_object_button_pressed", wall)
	await process_frame
	if not bool(em.get("_patrol_edit_mode")):
		pass_ += 1
		print("PASS  selecting a non-enemy exits patrol-edit")
	else:
		fail += 1
		printerr("FAIL  selection change did not exit patrol-edit")

	# 16. _patrol_exit_edit_mode (called by Esc in production) clears the flag.
	em.call("_on_object_button_pressed", enemy)
	await process_frame
	em.call("_patrol_toggle_edit_mode")
	em.call("_patrol_exit_edit_mode")
	if not bool(em.get("_patrol_edit_mode")):
		pass_ += 1
		print("PASS  _patrol_exit_edit_mode clears flag")
	else:
		fail += 1
		printerr("FAIL  _patrol_exit_edit_mode did not clear flag")

	em.queue_free()
	level.queue_free()
	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
