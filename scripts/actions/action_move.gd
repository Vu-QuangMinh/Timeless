class_name ActionMove
extends ActionBase

var path: MovePath
var end_pos: Vector2


func _init(pc, p: MovePath) -> void:
	action_type = "move"
	path = p
	end_pos = p.position_at(1.0)
	var agi: int = pc.char_data.char_agi if pc.char_data else 1
	var weight: float = pc.char_data.effective_weight() if pc.char_data else 70.0
	cost = TimeCalculator.move_time(p.total_length(), agi, weight)


func execute_visual(_char, _tween: Tween) -> void:
	var captured := path
	_tween.tween_method(
		func(t: float) -> void: _char.set_logical_pos(captured.position_at(t)),
		0.0, 1.0, get_animation_duration()
	)


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["end_pos"] = end_pos
	return d
