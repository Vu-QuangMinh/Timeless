## MovePath
## Immutable record of a smoothed arc-and-line path in world-pixel coordinates.
## Provides total distance (meters), total angular change (radians), time cost,
## and arc-length position interpolation for tweening.
## Does NOT compute paths (use PathSmoother). Does NOT touch nodes or signals.

class_name MovePath

const PPM := 16.0  # pixels per meter — must match TestMap

## A single segment: either a straight line or a circular arc.
class Segment:
	var type: String         # "line" or "arc"
	# line
	var from: Vector2
	var to: Vector2
	# arc
	var center: Vector2
	var radius: float
	var start_angle: float   # radians, measured from center
	var clockwise: bool      # true = angle increases (Godot y-down convention)
	var angular_change: float  # always positive, in radians
	# shared
	var length: float        # arc-length in pixels

var segments: Array[Segment] = []
var start_pos: Vector2
var end_pos: Vector2

# ---------------------------------------------------------------------------
# Factory helpers (called by PathSmoother)
# ---------------------------------------------------------------------------

static func make_line_seg(a: Vector2, b: Vector2) -> Segment:
	var s := Segment.new()
	s.type = "line"
	s.from = a
	s.to = b
	s.length = a.distance_to(b)
	return s

## start_a: angle (radians) of the arc's first point, measured from center.
## angular: the sweep magnitude in radians (always positive).
## cw: true = clockwise in Godot screen space (angle increases).
static func make_arc_seg(
		cen: Vector2, rad: float,
		start_a: float, angular: float, cw: bool) -> Segment:
	var s := Segment.new()
	s.type = "arc"
	s.center = cen
	s.radius = rad
	s.start_angle = start_a
	s.clockwise = cw
	s.angular_change = absf(angular)
	s.length = rad * s.angular_change
	return s

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func total_length_px() -> float:
	var t := 0.0
	for s: Segment in segments:
		t += s.length
	return t

func total_distance_meters() -> float:
	return total_length_px() / PPM

func total_angular_change() -> float:
	var t := 0.0
	for s: Segment in segments:
		if s.type == "arc":
			t += s.angular_change
	return t

func time_cost(agi: int, eff_kg: float) -> float:
	return TimeCalculator.move_time(
		total_distance_meters(), agi, eff_kg, total_angular_change())

## Arc-length interpolation. t=0 → start_pos, t=1 → end_pos.
func position_at(t: float) -> Vector2:
	var total := total_length_px()
	if total <= 0.0:
		return start_pos
	var target_px := clampf(t, 0.0, 1.0) * total
	var walked := 0.0
	for s: Segment in segments:
		if s.length <= 0.0:
			continue
		if walked + s.length >= target_px - 0.001:
			var local_t := (target_px - walked) / s.length
			return _seg_pos(s, clampf(local_t, 0.0, 1.0))
		walked += s.length
	return end_pos

func _seg_pos(s: Segment, t: float) -> Vector2:
	if s.type == "line":
		return s.from.lerp(s.to, t)
	# Arc: clockwise = angle increases in Godot (y-down).
	var swept := s.angular_change * t
	var angle  := s.start_angle + (swept if s.clockwise else -swept)
	return s.center + Vector2(cos(angle), sin(angle)) * s.radius
