class_name ActionPickUp
extends ActionBase

var item_id: String = ""
var item_kg: float = 0.0
var item_value: float = 0.0


func _init(pc, id: String, weight_kg: float, value: float) -> void:
	action_type = "pickup"
	item_id = id
	item_kg = weight_kg
	item_value = value
	var str_stat: int = pc.char_data.char_str if pc.char_data else 1
	cost = TimeCalculator.pickup_time(weight_kg, str_stat)


func execute_visual(_char, _tween: Tween) -> void:
	var dur := get_animation_duration()
	_tween.tween_callback(func(): _char.scale = Vector2.ONE)
	_tween.tween_property(_char, "scale", Vector2(1.15, 1.15), dur * 0.3)
	_tween.tween_property(_char, "scale", Vector2.ONE,         dur * 0.7)
	_tween.tween_callback(func():
		if on_complete.is_valid():
			on_complete.call()
	)


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["item_id"] = item_id
	d["item_kg"] = item_kg
	d["item_value"] = item_value
	return d
