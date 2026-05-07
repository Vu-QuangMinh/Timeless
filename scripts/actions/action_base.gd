## ActionBase
## Abstract base for all plannable actions. Stores character_id, action_type, and cost.
## Subclasses override execute_visual and undo_visual, and set action_type in _init().
## Does NOT push to ActionQueue (PlayerCharacter.queue_action does that).
## Does NOT handle guard actions or commit-phase resolution.

class_name ActionBase

var character_id: int   = -1
var action_type: String = ""
var cost: float         = 0.0

func get_animation_duration() -> float:
	return cost / GameManager.ANIMATION_SPEED_MULTIPLIER

## Play the action's visual on `character`, chaining onto `tween`.
## Subclasses should add tween steps to the provided Tween rather than creating a new one.
func execute_visual(_character: PlayerCharacter, _tween: Tween) -> void:
	pass

## Instantly revert the character to its pre-action visual state.
func undo_visual(_character: PlayerCharacter) -> void:
	pass
