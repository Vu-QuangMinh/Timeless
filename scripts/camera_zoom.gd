extends Camera2D

@export var zoom_step: float = 1.1
@export var min_zoom: float = 0.2
@export var max_zoom: float = 5.0


func _unhandled_input(event: InputEvent) -> void:
	if not is_current():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(zoom_step)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / zoom_step)
			get_viewport().set_input_as_handled()


func _zoom_at(factor: float) -> void:
	var world_before := get_global_mouse_position()
	var new_zoom: Vector2 = (zoom * factor).clamp(
		Vector2(min_zoom, min_zoom),
		Vector2(max_zoom, max_zoom),
	)
	if new_zoom == zoom:
		return
	zoom = new_zoom
	var world_after := get_global_mouse_position()
	position += world_before - world_after
