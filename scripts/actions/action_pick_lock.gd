class_name ActionPickLock
extends ActionBase

var lock_level: int = 1
var lock_type: String = "mechanical"
var target_pos: Vector2


func _init(pc, level: int, ltype: String, tpos: Vector2) -> void:
	action_type = "pick_lock"
	lock_level = level
	lock_type = ltype
	target_pos = tpos
	var int_stat: int = pc.char_data.char_int if pc.char_data else 1
	cost = TimeCalculator.pick_lock_time(level, int_stat)


func execute_visual(_char, _tween: Tween) -> void:
	var dur := get_animation_duration()
	_tween.tween_callback(func(): _char.scale = Vector2.ONE)
	_tween.tween_property(_char, "scale", Vector2(1.06, 1.06), dur * 0.2)
	_tween.tween_property(_char, "scale", Vector2(0.97, 0.97), dur * 0.2)
	_tween.tween_property(_char, "scale", Vector2(1.06, 1.06), dur * 0.2)
	_tween.tween_property(_char, "scale", Vector2(0.97, 0.97), dur * 0.2)
	_tween.tween_property(_char, "scale", Vector2.ONE,         dur * 0.2)
	_tween.tween_callback(func():
		if on_complete.is_valid():
			on_complete.call()
	)


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["lock_level"] = lock_level
	d["lock_type"] = lock_type
	d["target_pos"] = target_pos
	return d
