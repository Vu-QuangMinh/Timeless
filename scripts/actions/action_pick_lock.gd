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


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["lock_level"] = lock_level
	d["lock_type"] = lock_type
	d["target_pos"] = target_pos
	return d
