class_name ActionBase
extends RefCounted

var char_id: int = 0
var action_type: String = ""
var cost: float = 0.0
var on_complete: Callable = Callable()


func get_animation_duration() -> float:
	return cost / GameManager.ANIMATION_SPEED_MULTIPLIER


func execute_visual(_char, _tween: Tween) -> void:
	pass


func undo_visual(_char) -> void:
	pass


func to_dict() -> Dictionary:
	return {"type": action_type, "cost": cost}
