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


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["item_id"] = item_id
	d["item_kg"] = item_kg
	d["item_value"] = item_value
	return d
