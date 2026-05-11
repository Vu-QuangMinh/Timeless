extends SceneTree

# Loads Level1 + user's save, computes a path A→B that should be blocked by a
# spawned Camera laser_sensor (which has collision). If the pathfinder returns
# direct [A, B], the segments are reaching it but LOS isn't being blocked.
# If it returns multi-waypoint, blocking works.
# Run: godot --headless -s tests/test_path_blocked.gd

const WorldObstaclesScript := preload("res://scripts/pathing/world_obstacles.gd")


func _initialize() -> void:
	var level_packed: PackedScene = load("res://scenes/level_1/level_1.tscn")
	var level: Node = level_packed.instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	await process_frame

	# Find the first Camera-spawned laser_sensor and report its world meter pos.
	var objects := level.get_node_or_null("Objects")
	var camera_spawn: Node2D = null
	for child in objects.get_children():
		var src: String = child.get_meta("palette_source", "")
		if src.find("/Camera/") >= 0:
			camera_spawn = child as Node2D
			break

	if camera_spawn == null:
		printerr("FAIL: no Camera spawn under Objects")
		quit(1)
		return

	var pixel_pos := camera_spawn.global_position
	# Inline iso unproject (autoload not visible at parse time).
	var u := pixel_pos.x / (0.8660254 * 32.0)
	var v := pixel_pos.y / (0.5 * 32.0)
	var center_m := Vector2((u + v) * 0.5, (u - v) * 0.5)
	print("Camera spawn '%s' at iso-pixel %s → meters %s" % [camera_spawn.name, pixel_pos, center_m])

	# Plan A→B that crosses the spawn's center along the X axis in meters.
	var a := center_m + Vector2(-2.0, 0.0)
	var b := center_m + Vector2(2.0, 0.0)
	print("Querying path %s → %s (line crosses spawn)" % [a, b])

	# Replicate main.gd's _build_path setup.
	var wall_segs: Array = level.get_wall_segments()
	print("Baseline wall_segs from level: %d" % wall_segs.size())
	var spawned_segs: Array = WorldObstaclesScript.collect_wall_segments(level)
	print("WorldObstacles segments from scene: %d" % spawned_segs.size())
	wall_segs.append_array(spawned_segs)
	print("Combined wall_segs: %d" % wall_segs.size())

	var pf := Pathfinder.new()
	pf.setup(wall_segs, [])
	var path: Array = pf.find_path(a, b)
	print("Path: %d waypoints: %s" % [path.size(), path])

	var pass_ := 0
	var fail := 0
	if path.size() > 2:
		pass_ += 1
		print("PASS  pathfinder routed around the spawn (%d waypoints)" % path.size())
	elif path.size() == 2:
		fail += 1
		printerr("FAIL  pathfinder returned direct LOS [A, B] — collision NOT blocking despite %d segments in graph" % spawned_segs.size())
		# Debug: try a much closer A→B that's definitely inside the box.
		var a2 := center_m + Vector2(-0.5, 0.0)
		var b2 := center_m + Vector2(0.5, 0.0)
		var path2: Array = pf.find_path(a2, b2)
		printerr("  Closer query %s → %s: %d waypoints" % [a2, b2, path2.size()])
	else:
		fail += 1
		printerr("FAIL  pathfinder returned %d waypoints (unexpected)" % path.size())

	# Diagnostic: print the first few extracted segments to verify they're sensible.
	print("First 5 extracted segments (in meters):")
	for i in range(min(5, spawned_segs.size())):
		var s: Dictionary = spawned_segs[i]
		var seg_len: float = (s["b"] - s["a"]).length()
		print("  %s → %s  (len=%.3f m)" % [s["a"], s["b"], seg_len])

	level.queue_free()
	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
