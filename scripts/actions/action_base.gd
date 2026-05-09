class_name ActionBase
extends RefCounted

var char_id: int = 0
var action_type: String = ""
var cost: float = 0.0


func execute_visual(_char) -> void:
	pass


func undo_visual(_char) -> void:
	pass


func to_dict() -> Dictionary:
	return {"type": action_type, "cost": cost}
