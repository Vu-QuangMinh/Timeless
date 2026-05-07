## PathPreview
## World-space Node2D that renders the current planned move path via _draw().
## Call set_path() to update; call clear() to hide.
## Draws each segment as a polyline (arcs are approximated with 16 steps).
## Does NOT compute paths, interact with game state, or handle input.

class_name PathPreview
extends Node2D

const ARC_STEPS   := 16
const LINE_WIDTH  := 1.5
const DEST_RADIUS := 5.0   # ring at destination
const DEST_WIDTH  := 1.5

var _path: MovePath = null
var _color: Color   = Color.WHITE

func set_path(path: MovePath, color: Color) -> void:
	_path  = path
	_color = color
	queue_redraw()

func clear() -> void:
	_path = null
	queue_redraw()

func _draw() -> void:
	if _path == null or _path.segments.is_empty():
		return

	for seg: MovePath.Segment in _path.segments:
		if seg.type == "line":
			draw_line(seg.from, seg.to, _color, LINE_WIDTH)
		else:
			_draw_arc_seg(seg)

	# Destination ring
	draw_arc(_path.end_pos, DEST_RADIUS, 0.0, TAU, 20, _color, DEST_WIDTH)

func _draw_arc_seg(seg: MovePath.Segment) -> void:
	var pts := PackedVector2Array()
	for i in ARC_STEPS + 1:
		var t := float(i) / ARC_STEPS
		var swept := seg.angular_change * t
		var angle  := seg.start_angle + (swept if seg.clockwise else -swept)
		pts.append(seg.center + Vector2(cos(angle), sin(angle)) * seg.radius)
	draw_polyline(pts, _color, LINE_WIDTH)
