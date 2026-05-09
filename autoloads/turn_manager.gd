extends Node

signal phase_changed(new_phase: int)
signal turn_started(turn_index: int)
signal turn_ended(turn_index: int)

var turn_index: int = 0


func start_predict() -> void:
	GameManager.phase = GameManager.Phase.PREDICT
	phase_changed.emit(GameManager.phase)


func back_to_planning() -> void:
	GameManager.phase = GameManager.Phase.PLANNING
	phase_changed.emit(GameManager.phase)


func commit() -> void:
	turn_ended.emit(turn_index)
	turn_index += 1
	GameManager.phase = GameManager.Phase.PLANNING
	turn_started.emit(turn_index)
	phase_changed.emit(GameManager.phase)


func start_next_turn() -> void:
	turn_index += 1
	GameManager.phase = GameManager.Phase.PLANNING
	phase_changed.emit(GameManager.phase)
	turn_started.emit(turn_index)
