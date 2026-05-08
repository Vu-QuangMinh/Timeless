class_name MovePath

# Immutable. Segments are either lines or arcs.
# All coordinates in world meters.

class Segment:
	var is_arc: bool = false
	# Line: start, end
	var start: Vector2
	var end: Vector2
	# Arc: center, radius, from_angle, to_angle, arc_length
	var center: Vector2
	var radius: float
	var from_angle: float
	var to_angle: float
	var arc_length: float
	var length: float  # total segment length


var _segments: Array = []  # Array[Segment]
var _cumulative: Array[float] = []  # cumulative length at each segment end
var _total_length: float = 0.0


static func from_segments(segs: Array) -> MovePath:
	var mp := MovePath.new()
	mp._segments = segs
	var cum := 0.0
	for s in segs:
		cum += s.length
		mp._cumulative.append(cum)
	mp._total_length = cum
	return mp


func total_length() -> float:
	return _total_length


func position_at(frac: float) -> Vector2:
	if _segments.is_empty():
		return Vector2.ZERO
	frac = clamp(frac, 0.0, 1.0)
	var target := frac * _total_length
	for i in range(_cumulative.size()):
		if target <= _cumulative[i] + 1e-6:
			var seg: Segment = _segments[i]
			var seg_start := _cumulative[i] - seg.length if i > 0 else 0.0
			var local_t: float = clampf((target - seg_start) / maxf(seg.length, 1e-6), 0.0, 1.0)
			return _seg_position(seg, local_t)
	var last: Segment = _segments[-1]
	return _seg_position(last, 1.0)


static func _seg_position(seg: Segment, t: float) -> Vector2:
	if not seg.is_arc:
		return seg.start.lerp(seg.end, t)
	var angle := seg.from_angle + (seg.to_angle - seg.from_angle) * t
	return seg.center + Vector2(cos(angle), sin(angle)) * seg.radius
