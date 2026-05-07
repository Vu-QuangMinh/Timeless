## PathSmoother
## Converts a raw waypoint list (from Pathfinder) into a MovePath with arc-and-line segments.
## Arc radius at each bend is 0.5m = 8px, clamped so tangent length never exceeds half the
## shorter adjacent segment. Bends shorter than MIN_TURN_RAD radians are skipped (near-collinear).
## Does NOT compute raw paths — use Pathfinder. Does NOT reference game state.

class_name PathSmoother

const ARC_RADIUS   := 8.0   # pixels; 0.5m × 16px/m
const MIN_TURN_RAD := 0.01  # radians; skip arc below ~0.57°

## Typed container for one bend's pre-computed arc parameters.
class _ArcData:
	var r: float = 0.0
	var center: Vector2
	var start_angle: float = 0.0
	var theta: float = 0.0
	var cw: bool = false
	var tp1: Vector2
	var tp2: Vector2

static func smooth(waypoints: Array[Vector2]) -> MovePath:
	var path := MovePath.new()
	if waypoints.size() == 0:
		return path
	path.start_pos = waypoints[0]
	path.end_pos   = waypoints[-1]

	if waypoints.size() == 1:
		return path

	if waypoints.size() == 2:
		path.segments.append(MovePath.make_line_seg(waypoints[0], waypoints[1]))
		return path

	# -----------------------------------------------------------------------
	# Pre-compute arc data for each interior waypoint.
	# arc_data[i] corresponds to waypoints[i+1]. null = skip (near-collinear).
	# -----------------------------------------------------------------------
	var n := waypoints.size()
	var arc_data: Array[_ArcData] = []  # typed; null entries are valid for RefCounted

	for i in range(1, n - 1):
		var prev := waypoints[i - 1]
		var cur  := waypoints[i]
		var nxt  := waypoints[i + 1]

		var d_in  := (cur - prev).normalized()
		var d_out := (nxt - cur).normalized()
		var dot   := clampf(d_in.dot(d_out), -1.0, 1.0)
		var theta := acos(dot)

		if theta < MIN_TURN_RAD:
			arc_data.append(null)
			continue

		var len_in  := prev.distance_to(cur)
		var len_out := cur.distance_to(nxt)
		var r := ARC_RADIUS
		var tl := r * tan(theta * 0.5)

		if tl > len_in * 0.5 or tl > len_out * 0.5:
			r  = minf(len_in, len_out) * 0.5 / tan(theta * 0.5)
			tl = r * tan(theta * 0.5)

		# cross > 0 → clockwise turn in Godot (y-down).
		var cross := d_in.x * d_out.y - d_in.y * d_out.x
		var cw    := cross > 0.0

		# Arc center: right-turn perpendicular of d_in = Vector2(-d_in.y, d_in.x).
		var perp   := Vector2(-d_in.y, d_in.x)
		var tp1    := cur - tl * d_in
		var center := tp1 + r * perp * (1.0 if cw else -1.0)
		var tp2    := cur + tl * d_out

		var ad        := _ArcData.new()
		ad.r          = r
		ad.center     = center
		ad.start_angle = atan2(tp1.y - center.y, tp1.x - center.x)
		ad.theta      = theta
		ad.cw         = cw
		ad.tp1        = tp1
		ad.tp2        = tp2
		arc_data.append(ad)

	# -----------------------------------------------------------------------
	# Build segment list: line → arc → line → arc → ... → line
	# -----------------------------------------------------------------------
	var line_start := waypoints[0]

	for i in arc_data.size():
		var ad: _ArcData = arc_data[i]
		if ad == null:
			continue  # near-collinear — line continues through this waypoint

		if line_start.distance_to(ad.tp1) > 0.1:
			path.segments.append(MovePath.make_line_seg(line_start, ad.tp1))

		path.segments.append(
			MovePath.make_arc_seg(ad.center, ad.r, ad.start_angle, ad.theta, ad.cw))

		line_start = ad.tp2

	if line_start.distance_to(waypoints[n - 1]) > 0.1:
		path.segments.append(MovePath.make_line_seg(line_start, waypoints[n - 1]))

	return path
