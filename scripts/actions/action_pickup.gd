## ActionPickUp
## Picks up a nearby item (≤ 0.5 m). Cost: pickup_time(item_kg, STR, INT).
## execute_visual: scale pulse to show reaching down and grasping.
## State change (carried_kg / carried_value) resolves at commit, not during planning.

class_name ActionPickUp
extends ActionBase

var item_kg: float    = 0.0
var item_value: float = 0.0

func _init() -> void:
	action_type = "pickup"

func execute_visual(character: PlayerCharacter, tween: Tween) -> void:
	tween.tween_callback(func(): character.scale = Vector2.ONE)
	tween.tween_property(character, "scale", Vector2(1.15, 1.15), get_animation_duration() * 0.3)
	tween.tween_property(character, "scale", Vector2.ONE,         get_animation_duration() * 0.7)

func undo_visual(character: PlayerCharacter) -> void:
	character.scale = Vector2.ONE
