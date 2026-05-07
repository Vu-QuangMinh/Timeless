## ActionTakedown
## Permanently neutralizes an enemy within 0.5 m. Cost: takedown_time(enemy_type, STR).
## target_id: character_id of the target guard (-1 until guards are spawned).

class_name ActionTakedown
extends ActionBase

var enemy_type: String = "guard"   # "guard" | "clerk"
var target_id: int     = -1

func _init() -> void:
	action_type = "takedown"

func execute_visual(character: PlayerCharacter, tween: Tween) -> void:
	tween.tween_callback(func(): character.scale = Vector2.ONE)
	tween.tween_property(character, "scale", Vector2(1.25, 1.25), get_animation_duration() * 0.2)
	tween.tween_property(character, "scale", Vector2.ONE,         get_animation_duration() * 0.8)

func undo_visual(character: PlayerCharacter) -> void:
	character.scale = Vector2.ONE
