## ActionHoldHostage
## Character stays stationary holding an enemy for hold_duration seconds (0–5 s).
## Suppresses guard shooting while any character is holding a hostage.
## target_id: character_id of the hostage (-1 until guards are spawned).

class_name ActionHoldHostage
extends ActionBase

var hold_duration: float = 5.0   # already clamped via TimeCalculator.clamp_hold_duration
var target_id: int       = -1

func _init() -> void:
	action_type = "hold_hostage"

func execute_visual(character: PlayerCharacter, tween: Tween) -> void:
	# Slight squat to show character is pinned in place restraining someone.
	tween.tween_callback(func(): character.scale = Vector2.ONE)
	tween.tween_property(character, "scale", Vector2(0.85, 0.85), get_animation_duration() * 0.1)
	tween.tween_property(character, "scale", Vector2(0.85, 0.85), get_animation_duration() * 0.8)
	tween.tween_property(character, "scale", Vector2.ONE,         get_animation_duration() * 0.1)

func undo_visual(character: PlayerCharacter) -> void:
	character.scale = Vector2.ONE
