extends Camera2D

const ZOOM_MIN := 0.3
const ZOOM_MAX := 3.0
const ZOOM_STEP := 0.1
const PAN_SPEED_PX_PER_SEC := 600.0  # screen-space speed at zoom 1.0

var _dragging: bool = false
var _drag_origin: Vector2 = Vector2.ZERO
var _drag_cam_start: Vector2 = Vector2.ZERO


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if dir == Vector2.ZERO:
		return
	# Divide by zoom so on-screen pan speed stays consistent across zoom levels.
	position += dir.normalized() * PAN_SPEED_PX_PER_SEC * delta / zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_zoom(1.0 + ZOOM_STEP, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_zoom(1.0 - ZOOM_STEP, event.position)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			if _dragging:
				_drag_origin = event.position
				_drag_cam_start = position
	elif event is InputEventMouseMotion and _dragging:
		var delta: Vector2 = (event.position - _drag_origin) / zoom.x
		position = _drag_cam_start - delta


func _adjust_zoom(factor: float, pivot: Vector2) -> void:
	var old_zoom := zoom.x
	var new_zoom := clampf(old_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var ratio := new_zoom / old_zoom
	var vp_center := get_viewport_rect().size * 0.5
	position = position + (pivot - vp_center) / old_zoom * (1.0 - 1.0 / ratio)
	zoom = Vector2(new_zoom, new_zoom)
