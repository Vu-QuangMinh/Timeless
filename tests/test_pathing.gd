extends SceneTree


func _init() -> void:
	var ok := true

	# --- Pathfinder ---

	# Straight line, no obstacles
	var pf := Pathfinder.new()
	pf.setup([], [])
	var path := pf.find_path(Vector2(0, 0), Vector2(5, 0))
	ok = _check("straight path found", not path.is_empty(), ok)
	ok = _check("straight path starts at origin", path[0].distance_to(Vector2.ZERO) < 0.01, ok)
	ok = _check("straight path ends at target", path[-1].distance_to(Vector2(5, 0)) < 0.01, ok)

	# Wall blocking straight path; character must go around
	var wall := [{"a": Vector2(2, -3), "b": Vector2(2, 3)}]
	var pf2 := Pathfinder.new()
	pf2.setup(wall, [])
	var path2 := pf2.find_path(Vector2(0, 0), Vector2(5, 0))
	ok = _check("wall: path found", not path2.is_empty(), ok)
	ok = _check("wall: path has >2 points", path2.size() > 2, ok)

	# Obstacle blocking straight path
	var obs := [{"center": Vector2(2.5, 0), "radius": 1.0}]
	var pf3 := Pathfinder.new()
	pf3.setup([], obs)
	var path3 := pf3.find_path(Vector2(0, 0), Vector2(5, 0))
	ok = _check("obstacle: path found", not path3.is_empty(), ok)
	ok = _check("obstacle: path has >2 points", path3.size() > 2, ok)

	# LOS helper: no wall → clear
	var pf4 := Pathfinder.new()
	pf4.setup([], [])
	ok = _check("LOS clear", pf4._los_clear(Vector2(0, 0), Vector2(10, 0)), ok)

	# LOS helper: wall blocks → not clear
	var pf5 := Pathfinder.new()
	pf5.setup([{"a": Vector2(5, -1), "b": Vector2(5, 1)}], [])
	ok = _check("LOS blocked by wall", not pf5._los_clear(Vector2(0, 0), Vector2(10, 0)), ok)

	# segs_intersect static
	ok = _check("segs cross → true",
		Pathfinder._segs_intersect(Vector2(0, 0), Vector2(4, 4), Vector2(0, 4), Vector2(4, 0)), ok)
	ok = _check("segs parallel → false",
		not Pathfinder._segs_intersect(Vector2(0, 0), Vector2(4, 0), Vector2(0, 1), Vector2(4, 1)), ok)
	# Wall endpoint (u=1) must be treated as a hit — path from (-1,6) to (1,4) would graze
	# the top endpoint of wall (0,-5)→(0,5) if the u<1 strict check were used.
	ok = _check("segs endpoint hit → true",
		Pathfinder._segs_intersect(Vector2(-1, 6), Vector2(1, 4), Vector2(0, -5), Vector2(0, 5)), ok)

	# Corner-cutting: path around a wall endpoint must not cross through it.
	var cwall := [{"a": Vector2(0, -5), "b": Vector2(0, 5)}]
	var pf_c := Pathfinder.new()
	pf_c.setup(cwall, [])
	var cpath := pf_c.find_path(Vector2(-1, 6), Vector2(1, 4))
	ok = _check("corner-cut: path found", not cpath.is_empty(), ok)
	var no_cross := true
	for i in range(cpath.size() - 1):
		if Pathfinder._segs_intersect(cpath[i], cpath[i + 1], Vector2(0, -5), Vector2(0, 5)):
			no_cross = false
	ok = _check("corner-cut: no segment crosses wall", no_cross, ok)

	# --- Sprite-derived wall geometry ---
	# Wall_Y world coords from analyze_walls.py: roughly constant x ≈ −5 m,
	# spanning y −11.94 → 3.55.  Points on opposite sides must route around it.
	var wy_wall := [{"a": Vector2(-5.81, -11.94), "b": Vector2(-4.54, 3.55)}]
	var pf_wy := Pathfinder.new()
	pf_wy.setup(wy_wall, [])
	var path_wy := pf_wy.find_path(Vector2(0.0, -4.0), Vector2(-8.0, -4.0))
	ok = _check("sprite wall: path found across Wall_Y", not path_wy.is_empty(), ok)
	var no_wy_cross := true
	for i in range(path_wy.size() - 1):
		if Pathfinder._segs_intersect(path_wy[i], path_wy[i + 1],
				Vector2(-5.81, -11.94), Vector2(-4.54, 3.55)):
			no_wy_cross = false
	ok = _check("sprite wall: path does not cross Wall_Y", no_wy_cross, ok)

	# Snap pass: two segments sharing a corner within 0.05 m must get identical endpoints.
	var seg_a := {"a": Vector2(-4.55, 3.57), "b": Vector2(0.28, 4.45)}
	var seg_b := {"a": Vector2(-5.81, -11.94), "b": Vector2(-4.54, 3.55)}
	var pf_snap := Pathfinder.new()
	pf_snap.setup([seg_a, seg_b], [])
	var snapped_corner_a: Vector2 = pf_snap._wall_segs[0]["a"]
	var snapped_corner_b: Vector2 = pf_snap._wall_segs[1]["b"]
	ok = _check("snap: shared corner endpoints are identical after setup",
		snapped_corner_a == snapped_corner_b, ok)

	# --- MovePath ---

	var seg := MovePath.Segment.new()
	seg.is_arc = false
	seg.start = Vector2(0, 0)
	seg.end = Vector2(10, 0)
	seg.length = 10.0
	var mp := MovePath.from_segments([seg])
	ok = _check("MovePath total_length", absf(mp.total_length() - 10.0) < 0.001, ok)
	ok = _check("MovePath position_at(0)", mp.position_at(0.0).distance_to(Vector2.ZERO) < 0.001, ok)
	ok = _check("MovePath position_at(0.5)", mp.position_at(0.5).distance_to(Vector2(5, 0)) < 0.001, ok)
	ok = _check("MovePath position_at(1)", mp.position_at(1.0).distance_to(Vector2(10, 0)) < 0.001, ok)

	# --- PathSmoother ---

	var smoother := PathSmoother.new()
	# Straight line → one segment
	var straight_path := smoother.smooth([Vector2(0, 0), Vector2(5, 0)], [], [])
	ok = _check("smoother: straight path not null", straight_path != null, ok)
	ok = _check("smoother: straight total_length ≈ 5", absf(straight_path.total_length() - 5.0) < 0.01, ok)

	# 90-degree corner → arced path slightly shorter than L-shape
	var corner_path := smoother.smooth([Vector2(0, 0), Vector2(5, 0), Vector2(5, 5)], [], [])
	ok = _check("smoother: corner path not null", corner_path != null, ok)
	ok = _check("smoother: corner path length < 10", corner_path.total_length() < 10.0, ok)

	quit(0 if ok else 1)


func _check(label: String, condition: bool, ok: bool) -> bool:
	if condition:
		print("  PASS  %s" % label)
	else:
		print("  FAIL  %s" % label)
	return ok and condition
