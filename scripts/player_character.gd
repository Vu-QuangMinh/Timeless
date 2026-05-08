class_name PlayerCharacter
extends Node2D

const WALK_SPEED := 1.4  # m/s

var logical_pos: Vector2 = Vector2.ZERO
var _path_tween: Tween = null


func set_logical_pos(p: Vector2) -> void:
	logical_pos = p
	position = IsoMath.project(p)
	queue_redraw()


func move_along(path: MovePath) -> void:
	if _path_tween:
		_path_tween.kill()
	var duration: float = path.total_length() / maxf(WALK_SPEED, 0.01)
	_path_tween = create_tween()
	_path_tween.tween_method(
		func(t: float) -> void: set_logical_pos(path.position_at(t)),
		0.0, 1.0, duration
	)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 12.0, Color(0.25, 0.55, 1.0, 0.9))
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 24, Color.WHITE, 1.5)
