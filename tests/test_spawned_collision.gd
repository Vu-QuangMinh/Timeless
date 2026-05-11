extends SceneTree

# Verifies the WorldObstacles → Pathfinder integration: a freshly spawned wall
# asset (StaticBody2D + CollisionPolygon2D, in iso-pixel world space) shows up
# as wall segments in world meters and blocks line-of-sight through its body.
# Run: godot --headless -s tests/test_spawned_collision.gd

const WorldObstaclesScript := preload("res://scripts/pathing/world_obstacles.gd")


func _initialize() -> void:
	var fail := 0
	var pass_ := 0

	# Build a fake palette wall: StaticBody2D root + CollisionPolygon2D child
	# whose vertices form a 64×64 px box centered on the body.
	var body := StaticBody2D.new()
	body.name = "FakeWall"
	# collision_layer defaults to 1 — that's what WorldObstacles filters for.
	var cp := CollisionPolygon2D.new()
	cp.name = "Collision_0"
	cp.polygon = PackedVector2Array([
		Vector2(-32, -32), Vector2(32, -32), Vector2(32, 32), Vector2(-32, 32),
	])
	body.add_child(cp)

	# Drop the body at iso-pixel world coord (200, 0). This corresponds to
	# world meters somewhere around (3.6, 3.6) per IsoMath:
	#   unproject((200, 0)) → (200/(cos30*32) + 0)/2, (200/(cos30*32) - 0)/2
	#   ≈ (3.6, 3.6)
	body.position = Vector2(200.0, 0.0)
	root.add_child(body)
	await process_frame

	var segs: Array = WorldObstaclesScript.collect_wall_segments(root)
	if segs.size() == 4:
		pass_ += 1
		print("PASS  WorldObstacles extracted 4 edges from the box CollisionPolygon2D")
	else:
		fail += 1
		printerr("FAIL  expected 4 edges, got %d" % segs.size())
		for s in segs:
			printerr("       %s → %s" % [s["a"], s["b"]])

	# Sanity: the segments are in meters, not pixels. A 64-px box at 32 px/m =
	# 2-meter sides. Edges should be ~2 m long after iso unprojection (slightly
	# different per edge because of the iso skew, but length is approximately
	# 2/sqrt(2) ≈ 1.41 m on the X-axis projection).
	if segs.size() > 0:
		var first_edge_len: float = (segs[0]["b"] - segs[0]["a"]).length()
		# Loose bound — just confirm we're not in pixel-space (which would be ~64).
		if first_edge_len > 0.5 and first_edge_len < 5.0:
			pass_ += 1
			print("PASS  edge length %.2f is in meters (not pixels)" % first_edge_len)
		else:
			fail += 1
			printerr("FAIL  edge length %.2f is suspicious (expected ~1-3 m)" % first_edge_len)

	# Now test that a Pathfinder seeded with these segments blocks LOS through
	# the wall and routes around it.
	var pf := Pathfinder.new()
	pf.setup(segs, [])

	# Pick endpoints in meters that bracket the wall's X coordinate. The body is
	# at iso-pixel (200, 0), unproject ≈ (3.61, 3.61) — pick two points so the
	# straight line A→B passes through the box.
	# Inline IsoMath.unproject (autoload not parse-time visible from test scripts).
	var u := 200.0 / (0.8660254 * 32.0)
	var v := 0.0 / (0.5 * 32.0)
	var box_center_m := Vector2((u + v) * 0.5, (u - v) * 0.5)
	var a := box_center_m + Vector2(-2.0, 0.0)
	var b := box_center_m + Vector2(2.0, 0.0)

	var direct: Array = pf.find_path(a, b)
	# If LOS were clear, direct = [a, b] (size 2). If blocked, A* routes around,
	# returning more waypoints.
	if direct.size() > 2:
		pass_ += 1
		print("PASS  pathfinder routed around the wall (%d waypoints)" % direct.size())
	else:
		fail += 1
		printerr("FAIL  pathfinder did not route around the wall (got %d waypoints)" % direct.size())

	# Negative test: when the wall is on collision_layer 2 (e.g. a recognition-
	# only Area2D), it should be skipped.
	var area := Area2D.new()
	area.collision_layer = 2  # not bit 0
	var cp2 := CollisionPolygon2D.new()
	cp2.polygon = PackedVector2Array([
		Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10),
	])
	area.add_child(cp2)
	root.add_child(area)
	await process_frame

	var segs2: Array = WorldObstaclesScript.collect_wall_segments(root)
	# Should still be 4 (only the StaticBody2D contributed; the Area2D was skipped).
	if segs2.size() == 4:
		pass_ += 1
		print("PASS  Area2D on layer 2 was skipped (still 4 segments)")
	else:
		fail += 1
		printerr("FAIL  expected 4 segments after adding layer-2 area, got %d" % segs2.size())

	body.queue_free()
	area.queue_free()

	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
