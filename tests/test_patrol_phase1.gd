extends SceneTree

# Phase 1 patrol UI: selecting an enemy (recognition_priority meta == 50) shows
# the "Patrols: 0 points" section in the right panel; selecting a wall hides it.
# Run: godot --headless -s tests/test_patrol_phase1.gd


func _initialize() -> void:
	var fail := 0
	var pass_ := 0

	# Build a minimal level with two editable nodes: a fake enemy (Node2D with
	# the recognition_priority meta set, like F6 saves) and a plain wall sprite.
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
	# Give it bounds so _world_bounds can pick it (not strictly needed for
	# Phase 1's selection-by-assignment test, but matches real spawned enemies).
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
	# No recognition_priority meta → not an enemy.
	objects.add_child(wall)

	# Mount EditMode under level so its sibling lookups work.
	var em_script := load("res://scripts/EditMode.gd")
	var em: Node = Node2D.new()
	em.set_script(em_script)
	em.name = "EditMode"
	level.add_child(em)
	await process_frame
	await process_frame  # let _build_ui finish

	# Activate F4 (turns on the right panel + patrol section is hidden by default).
	em.call("_toggle")
	await process_frame

	var patrol_section: Control = em.get("_patrol_section")
	var patrol_status_label: Label = em.get("_patrol_status_label")
	if patrol_section == null or patrol_status_label == null:
		printerr("FAIL: patrol UI fields not built — _patrol_section or _patrol_status_label is null")
		quit(1)
		return
	pass_ += 1
	print("PASS  _patrol_section + _patrol_status_label exist after _build_ui")

	# Initially no selection → section hidden.
	if not patrol_section.visible:
		pass_ += 1
		print("PASS  no selection → patrol section hidden")
	else:
		fail += 1
		printerr("FAIL  patrol section visible on F4 activate with no selection")

	# Select the wall via _on_object_button_pressed.
	em.call("_on_object_button_pressed", wall)
	await process_frame
	if not patrol_section.visible:
		pass_ += 1
		print("PASS  wall selected → patrol section still hidden")
	else:
		fail += 1
		printerr("FAIL  wall selected → patrol section visible (should be hidden)")

	# Select the enemy.
	em.call("_on_object_button_pressed", enemy)
	await process_frame
	if patrol_section.visible:
		pass_ += 1
		print("PASS  enemy selected → patrol section visible")
	else:
		fail += 1
		printerr("FAIL  enemy selected → patrol section still hidden")
	if patrol_status_label.text == "Patrols: 0 points":
		pass_ += 1
		print("PASS  status label shows 'Patrols: 0 points'")
	else:
		fail += 1
		printerr("FAIL  status label = '%s'" % patrol_status_label.text)

	# _patrol_data should have an auto-created entry for the enemy.
	var data: Dictionary = em.get("_patrol_data")
	if data.has("fake_enemy_1"):
		pass_ += 1
		print("PASS  _patrol_data has entry for 'fake_enemy_1'")
		var entry: Dictionary = data["fake_enemy_1"]
		if entry.get("loop_mode", "") == "ping_pong":
			pass_ += 1
			print("PASS  loop_mode defaults to 'ping_pong'")
		else:
			fail += 1
			printerr("FAIL  loop_mode = '%s'" % entry.get("loop_mode", ""))
		if (entry.get("points", []) as Array).is_empty():
			pass_ += 1
			print("PASS  points array starts empty")
		else:
			fail += 1
			printerr("FAIL  points array not empty: %s" % entry.get("points", []))
	else:
		fail += 1
		printerr("FAIL  _patrol_data missing entry for 'fake_enemy_1'")

	# Switch back to the wall — section hides again.
	em.call("_on_object_button_pressed", wall)
	await process_frame
	if not patrol_section.visible:
		pass_ += 1
		print("PASS  switching back to wall → patrol section hidden")
	else:
		fail += 1
		printerr("FAIL  switching to wall → patrol section still visible")

	# Mutate the points array directly (simulates Phase 2 adding a point) and
	# re-select the enemy — status label should reflect the new count.
	var entry2: Dictionary = (em.get("_patrol_data") as Dictionary)["fake_enemy_1"]
	(entry2["points"] as Array).append(Vector2(1.0, 2.0))
	(entry2["points"] as Array).append(Vector2(3.0, 4.0))
	em.call("_on_object_button_pressed", enemy)
	await process_frame
	if patrol_status_label.text == "Patrols: 2 points":
		pass_ += 1
		print("PASS  after adding 2 points: label shows 'Patrols: 2 points'")
	else:
		fail += 1
		printerr("FAIL  label = '%s' after adding 2 points" % patrol_status_label.text)

	em.queue_free()
	level.queue_free()
	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
