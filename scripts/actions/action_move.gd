## ActionMove
## Move action. Stores a MovePath and animates the character along it via Tween.
## execute_visual: adds a tween_method step that walks character.position along the path.
## undo_visual: snaps character.position back to path.start_pos instantly.
## Does NOT modify ActionQueue, stats, or game state.

class_name ActionMove
extends ActionBase

var path: MovePath  # set by main.gd before queuing

func _init() -> void:
	action_type = "move"

func execute_visual(character: PlayerCharacter, tween: Tween) -> void:
	if path == null:
		return
	var captured := path
	tween.tween_method(
		func(t: float) -> void: character.position = captured.position_at(t),
		0.0, 1.0, get_animation_duration())

func undo_visual(character: PlayerCharacter) -> void:
	if path != null:
		character.position = path.start_pos
