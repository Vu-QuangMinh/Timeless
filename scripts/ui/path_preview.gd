class_name PathPreview
extends Node2D

# char_id -> Array[MovePath]
var _paths: Dictionary = {}

const COLORS: Array = [
	Color(0.85, 0.85, 0.2, 0.85),   # char 0 yellow
	Color(0.4, 0.7, 1.0, 0.85),     # char 1 blue
	Color(0.35, 0.9, 0.4, 0.85),    # char 2 green
]
const LINE_W := 2.0
const ARC_STEPS := 16


func set_paths(char_id: int, paths: Array) -> void:
	_paths[char_id] = paths
	queue_redraw()


func clear_char(char_id: int) -> void:
	_paths.erase(char_id)
	queue_redraw()


func clear_all() -> void:
	_paths.clear()
	queue_redraw()


func _draw() -> void:
	for char_id in _paths:
		var col: Color = COLORS[char_id % COLORS.size()]
		for path in _paths[char_id]:
			_draw_path(path, col)


func _draw_path(path: MovePath, col: Color) -> void:
	for i in path._segments.size():
		var seg: MovePath.Segment = path._segments[i]
		if seg.is_arc:
			_draw_arc_seg(seg, col)
		else:
			draw_line(IsoMath.project(seg.start), IsoMath.project(seg.end), col, LINE_W)


func _draw_arc_seg(seg: MovePath.Segment, col: Color) -> void:
	var prev := IsoMath.project(
		seg.center + Vector2(cos(seg.from_angle), sin(seg.from_angle)) * seg.radius)
	for i in range(1, ARC_STEPS + 1):
		var t := float(i) / float(ARC_STEPS)
		var angle := seg.from_angle + (seg.to_angle - seg.from_angle) * t
		var cur := IsoMath.project(seg.center + Vector2(cos(angle), sin(angle)) * seg.radius)
		draw_line(prev, cur, col, LINE_W)
		prev = cur
