class_name PathSmoother

const ARC_RADIUS := 0.5   # meters; matches CHAR_RADIUS
const MIN_TURN_RAD := 0.01  # radians — below this we treat it as straight


func smooth(waypoints: Array, wall_segs: Array, obstacles: Array) -> MovePath:
	if waypoints.size() < 2:
		return null

	var segs: Array = []

	if waypoints.size() == 2:
		segs.append(_line_seg(waypoints[0], waypoints[1]))
		return MovePath.from_segments(segs)

	var i := 0
	var current: Vector2 = waypoints[0]
	while i < waypoints.size() - 1:
		var next: Vector2 = waypoints[i + 1]
		if i == waypoints.size() - 2:
			segs.append(_line_seg(current, next))
			break

		var after: Vector2 = waypoints[i + 2]
		var in_dir := (next - current).normalized()
		var out_dir := (after - next).normalized()
		var turn_angle := _signed_angle(in_dir, out_dir)

		if abs(turn_angle) < MIN_TURN_RAD:
			# Straight through
			segs.append(_line_seg(current, next))
			current = next
			i += 1
			continue

		# Inscribed arc tangent to corner
		var arc: Variant = _build_arc(current, next, after, in_dir, out_dir, turn_angle)
		if arc == null:
			segs.append(_line_seg(current, next))
			current = next
			i += 1
			continue

		var tan_pt_in: Vector2 = arc["tan_in"]
		var tan_pt_out: Vector2 = arc["tan_out"]
		var center: Vector2 = arc["center"]
		var radius: float = arc["radius"]
		var a0: float = arc["a0"]
		var a1: float = arc["a1"]

		if current.distance_to(tan_pt_in) > 1e-4:
			segs.append(_line_seg(current, tan_pt_in))

		var arc_seg := MovePath.Segment.new()
		arc_seg.is_arc = true
		arc_seg.center = center
		arc_seg.radius = radius
		arc_seg.from_angle = a0
		arc_seg.to_angle = a1
		var arc_len: float = absf(a1 - a0) * radius
		arc_seg.arc_length = arc_len
		arc_seg.length = arc_len
		segs.append(arc_seg)

		current = tan_pt_out
		i += 1

	return MovePath.from_segments(segs)


static func _line_seg(a: Vector2, b: Vector2) -> MovePath.Segment:
	var s := MovePath.Segment.new()
	s.is_arc = false
	s.start = a
	s.end = b
	s.length = a.distance_to(b)
	return s


static func _signed_angle(from_dir: Vector2, to_dir: Vector2) -> float:
	return atan2(from_dir.cross(to_dir), from_dir.dot(to_dir))


static func _build_arc(p0: Vector2, corner: Vector2, p2: Vector2,
		in_dir: Vector2, out_dir: Vector2, turn_angle: float) -> Variant:
	var half_angle: float = absf(turn_angle) * 0.5
	if half_angle < MIN_TURN_RAD:
		return null

	var tan_dist := ARC_RADIUS / tan(half_angle)
	var avail_in := p0.distance_to(corner)
	var avail_out := corner.distance_to(p2)
	if tan_dist > avail_in - 1e-3 or tan_dist > avail_out - 1e-3:
		# Not enough room for the arc; fall back to straight
		return null

	var tan_in := corner - in_dir * tan_dist
	var tan_out := corner + out_dir * tan_dist

	var sign_turn := signf(turn_angle)
	var perp_in := Vector2(-in_dir.y, in_dir.x) * sign_turn
	var center := tan_in + perp_in * ARC_RADIUS

	var a0 := (tan_in - center).angle()
	var a1 := (tan_out - center).angle()

	# Ensure arc sweeps in the correct direction
	var delta := a1 - a0
	if sign_turn > 0 and delta < 0:
		a1 += TAU
	elif sign_turn < 0 and delta > 0:
		a1 -= TAU

	return {
		"tan_in": tan_in,
		"tan_out": tan_out,
		"center": center,
		"radius": ARC_RADIUS,
		"a0": a0,
		"a1": a1,
	}
