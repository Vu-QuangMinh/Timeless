## ActionHack
## Hacks a target at range hack_range(INT) meters. Cost: hack_time(target_type, INT).
## target_type: "camera" | "tripwire" | "red_button" | "window" | "door"

class_name ActionHack
extends ActionBase

var target_type: String = "door"
var target_pos: Vector2 = Vector2.ZERO

func _init() -> void:
	action_type = "hack"

func execute_visual(character: PlayerCharacter, tween: Tween) -> void:
	# Double micro-pulse: typing / remote-interfacing rhythm.
	tween.tween_callback(func(): character.scale = Vector2.ONE)
	tween.tween_property(character, "scale", Vector2(1.08, 1.08), get_animation_duration() * 0.25)
	tween.tween_property(character, "scale", Vector2(0.97, 0.97), get_animation_duration() * 0.25)
	tween.tween_property(character, "scale", Vector2(1.08, 1.08), get_animation_duration() * 0.25)
	tween.tween_property(character, "scale", Vector2.ONE,         get_animation_duration() * 0.25)

func undo_visual(character: PlayerCharacter) -> void:
	character.scale = Vector2.ONE
