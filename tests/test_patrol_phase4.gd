extends SceneTree

# Phase 4 simulate-patrol: clicking the button snapshots each guard's
# pre-simulate position and spins up one looping Tween per guard with ≥2
# reachable patrol points. Stop restores positions and clears tween state.
# P is ignored during sim; F4 deactivate auto-stops.
# Run: godot --headless -s tests/test_patrol_phase4.gd


func _initialize() -> void:
	var fail := 0
	var pass_ := 0

	var level := Node2D.new()
	level.name = "Level1"
	# Obstacle-free level: every patrol segment is reachable.
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

	# Guard 1: 3 reachable patrol points → should be simulated.
	var enemy1 := Node2D.new()
	enemy1.name = "fake_enemy_1"
	enemy1.add_to_group("editable")
	enemy1.set_meta("recognition_priority", 50)
	var s1 := Sprite2D.new()
	s1.name = "Sprite"
	s1.centered = true
	s1.texture = load("res://assets/level1/CCTV.png")
	enemy1.add_child(s1)
	objects.add_child(enemy1)
	enemy1.global_position = Vector2(100.0, 200.0)  # known pre-sim position

	# Guard 2: 1 patrol point only → should be skipped.
	var enemy2 := Node2D.new()
	enemy2.name = "fake_enemy_2"
	enemy2.add_to_group("editable")
	enemy2.set_meta("recognition_priority", 50)
	var s2 := Sprite2D.new()
	s2.name = "Sprite"
	s2.centered = true
	s2.texture = load("res://assets/level1/CCTV.png")
	enemy2.add_child(s2)
	objects.add_child(enemy2)
	enemy2.global_position = Vector2(300.0, 400.0)

	var em_script := load("res://scripts/EditMode.gd")
	var em: Node = Node2D.new()
	em.set_script(em_script)
	em.name = "EditMode"
	level.add_child(em)
	await process_frame
	await process_frame
	em.call("_toggle")
	await process_frame

	# Populate patrol data directly: guard1 has 3 points, guard2 has 1.
	em.call("_on_object_button_pressed", enemy1)
	await process_frame
	em.call("_patrol_toggle_edit_mode")
	em.call("_patrol_add_point_at", Vector2(0.0, 0.0))
	em.call("_patrol_add_point_at", Vector2(2.0, 0.0))
	em.call("_patrol_add_point_at", Vector2(2.0, 2.0))
	em.call("_patrol_exit_edit_mode")

	em.call("_on_object_button_pressed", enemy2)
	await process_frame
	em.call("_patrol_toggle_edit_mode")
	em.call("_patrol_add_point_at", Vector2(5.0, 5.0))
	em.call("_patrol_exit_edit_mode")

	# 1. Initial state: not simulating, no tweens, no pre-positions.
	if not bool(em.get("_simulating")) \
			and (em.get("_sim_tweens") as Array).is_empty() \
			and (em.get("_sim_pre_positions") as Dictionary).is_empty():
		pass_ += 1
		print("PASS  initial state: not simulating, no tweens")
	else:
		fail += 1
		printerr("FAIL  unexpected initial sim state")

	# 2. Build paths for guard1 returns 4 ping-pong segments (3 pts: 2 forward + 2 backward).
	var paths1: Array = em.call("_build_patrol_movepaths_pingpong", "fake_enemy_1")
	if paths1.size() == 4:
		pass_ += 1
		print("PASS  ping-pong path count for 3 points = 4 (2 fwd + 2 bwd)")
	else:
		fail += 1
		printerr("FAIL  expected 4 ping-pong segments, got %d" % paths1.size())

	# 3. Guard 2 (only 1 point) yields no paths.
	var paths2: Array = em.call("_build_patrol_movepaths_pingpong", "fake_enemy_2")
	if paths2.is_empty():
		pass_ += 1
		print("PASS  guard with <2 points yields no paths")
	else:
		fail += 1
		printerr("FAIL  guard with 1 point should yield no paths, got %d" % paths2.size())

	# 4. Toggle simulate on. _simulating true; one tween (only guard1 qualifies);
	# pre-position captured for guard1; guard2 untouched.
	em.call("_toggle_simulate_patrol")
	if bool(em.get("_simulating")):
		pass_ += 1
		print("PASS  toggle ON → _simulating true")
	else:
		fail += 1
		printerr("FAIL  toggle did not start simulation")

	var tweens: Array = em.get("_sim_tweens")
	if tweens.size() == 1:
		pass_ += 1
		print("PASS  exactly 1 tween created (only guard1 has ≥2 points)")
	else:
		fail += 1
		printerr("FAIL  expected 1 tween, got %d" % tweens.size())

	var pre_pos: Dictionary = em.get("_sim_pre_positions")
	if pre_pos.has("fake_enemy_1") \
			and pre_pos["fake_enemy_1"] == Vector2(100.0, 200.0) \
			and not pre_pos.has("fake_enemy_2"):
		pass_ += 1
		print("PASS  pre-position captured for guard1 only")
	else:
		fail += 1
		printerr("FAIL  pre_pos = %s" % [pre_pos])

	# 5. Button label flipped to "Stop Simulation".
	var sim_btn: Button = em.get("_sim_button")
	if sim_btn.text == "Stop Simulation":
		pass_ += 1
		print("PASS  button text = 'Stop Simulation' while sim active")
	else:
		fail += 1
		printerr("FAIL  button text = '%s'" % sim_btn.text)

	# 6. Let tween run a couple frames — guard1 should have moved off its
	# pre-sim position. (At sim start the tween snaps guard to pts[0] = (0,0)
	# projected = (0,0), so even at t=0 the guard already left (100,200).)
	await process_frame
	await process_frame
	if enemy1.global_position != Vector2(100.0, 200.0):
		pass_ += 1
		print("PASS  guard1 moved during simulation (now %s)" % [enemy1.global_position])
	else:
		fail += 1
		printerr("FAIL  guard1 did not move (still at pre-sim pos)")

	# 7. P key is a no-op during simulation.
	em.call("_on_object_button_pressed", enemy1)
	await process_frame
	em.call("_patrol_toggle_edit_mode")
	if not bool(em.get("_patrol_edit_mode")):
		pass_ += 1
		print("PASS  P during sim is a no-op (patrol-edit stays off)")
	else:
		fail += 1
		printerr("FAIL  P entered patrol-edit during sim")

	# 8. Toggle simulate off. _simulating false; tweens cleared; pre-positions
	# restored; guard1 back at (100, 200); button label flipped back.
	em.call("_toggle_simulate_patrol")
	if not bool(em.get("_simulating")):
		pass_ += 1
		print("PASS  toggle OFF → _simulating false")
	else:
		fail += 1
		printerr("FAIL  toggle off did not stop simulation")

	tweens = em.get("_sim_tweens")
	pre_pos = em.get("_sim_pre_positions")
	if tweens.is_empty() and pre_pos.is_empty():
		pass_ += 1
		print("PASS  sim state cleared after stop")
	else:
		fail += 1
		printerr("FAIL  state not cleared (tweens=%d, pre=%s)" % [tweens.size(), pre_pos])

	if enemy1.global_position == Vector2(100.0, 200.0):
		pass_ += 1
		print("PASS  guard1 restored to pre-sim position (100,200)")
	else:
		fail += 1
		printerr("FAIL  guard1 not restored (at %s)" % [enemy1.global_position])

	if sim_btn.text == "Simulate Patrol":
		pass_ += 1
		print("PASS  button text back to 'Simulate Patrol' after stop")
	else:
		fail += 1
		printerr("FAIL  button text = '%s' after stop" % sim_btn.text)

	# 9. Re-start, then F4 deactivate auto-stops and restores positions.
	em.call("_toggle_simulate_patrol")
	await process_frame
	await process_frame
	if not (enemy1.global_position == Vector2(100.0, 200.0)):
		pass_ += 1
		print("PASS  after second start, guard1 again moves off pre-sim pos")
	else:
		fail += 1
		printerr("FAIL  guard1 did not move on second start")

	em.call("_force_deactivate")
	if not bool(em.get("_simulating")) \
			and (em.get("_sim_tweens") as Array).is_empty() \
			and enemy1.global_position == Vector2(100.0, 200.0):
		pass_ += 1
		print("PASS  F4 deactivate auto-stopped sim and restored position")
	else:
		fail += 1
		printerr("FAIL  deactivate did not clean up (sim=%s, tweens=%d, pos=%s)" \
				% [em.get("_simulating"), (em.get("_sim_tweens") as Array).size(),
				   enemy1.global_position])

	em.queue_free()
	level.queue_free()
	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
