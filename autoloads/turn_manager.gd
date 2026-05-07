## TurnManager
## Drives turn phase transitions: Planning → Predict → Commit → Planning.
## Notifies listeners when the phase changes. Calls GameManager to advance the global timer on Commit.
## Does NOT implement guard AI, action resolution, or rendering.

extends Node

signal phase_changed(new_phase: GameManager.Phase)
signal turn_started(turn_number: int)

var turn_number: int = 0

func start_first_turn() -> void:
	turn_number = 1
	GameManager.set_phase(GameManager.Phase.PLANNING)
	emit_signal("phase_changed", GameManager.Phase.PLANNING)
	emit_signal("turn_started", turn_number)

## Player clicks "Predict" — freeze player actions, let guards act (stub for now).
func enter_predict() -> void:
	if GameManager.current_phase != GameManager.Phase.PLANNING:
		return
	GameManager.set_phase(GameManager.Phase.PREDICT)
	emit_signal("phase_changed", GameManager.Phase.PREDICT)

## Player clicks "Commit" — lock everything, advance timer, start next turn.
func commit_turn() -> void:
	if GameManager.current_phase != GameManager.Phase.PREDICT:
		return
	GameManager.advance_timer()
	ActionQueue.flush_committed_actions()
	turn_number += 1
	GameManager.set_phase(GameManager.Phase.PLANNING)
	emit_signal("phase_changed", GameManager.Phase.PLANNING)
	emit_signal("turn_started", turn_number)

## Player clicks "Back to Planning" from Predict screen.
func back_to_planning() -> void:
	if GameManager.current_phase != GameManager.Phase.PREDICT:
		return
	ActionQueue.cancel_predict()
	GameManager.set_phase(GameManager.Phase.PLANNING)
	emit_signal("phase_changed", GameManager.Phase.PLANNING)
