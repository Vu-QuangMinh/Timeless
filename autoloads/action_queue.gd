## ActionQueue
## Stores and manages the ordered list of queued actions for each player character per turn.
## Supports undo (pop last), reset (clear all), and commit/cancel lifecycle hooks.
## Does NOT execute actions visually, resolve physics, or know about guard actions.

extends Node

signal queue_changed(character_id: int, actions: Array)

## Each entry: { "character_id": int, "type": String, "cost": float, "data": Dictionary }
var _queues: Dictionary = {}  # character_id (int) -> Array of action dicts

func register_character(character_id: int) -> void:
	_queues[character_id] = []

func get_queue(character_id: int) -> Array:
	return _queues.get(character_id, [])

func get_time_used(character_id: int) -> float:
	var total := 0.0
	for action in get_queue(character_id):
		total += action["cost"]
	return total

func get_time_remaining(character_id: int, turn_budget: float) -> float:
	return turn_budget - get_time_used(character_id)

func push_action(character_id: int, action_type: String, cost: float, data: Dictionary = {}) -> bool:
	if not _queues.has(character_id):
		return false
	var entry := { "character_id": character_id, "type": action_type, "cost": cost, "data": data }
	_queues[character_id].append(entry)
	emit_signal("queue_changed", character_id, _queues[character_id])
	return true

## Undo the last queued action for a character.
func undo_last(character_id: int) -> void:
	if not _queues.has(character_id):
		return
	if _queues[character_id].is_empty():
		return
	_queues[character_id].pop_back()
	emit_signal("queue_changed", character_id, _queues[character_id])

## Reset all queued actions for a character.
func reset_character(character_id: int) -> void:
	if not _queues.has(character_id):
		return
	_queues[character_id].clear()
	emit_signal("queue_changed", character_id, _queues[character_id])

## Called on Commit — clears all queues after actions are locked in.
func flush_committed_actions() -> void:
	for id in _queues:
		_queues[id].clear()
		emit_signal("queue_changed", id, [])

## Called on Back to Planning — same as flush for now (guard actions aren't stored here).
func cancel_predict() -> void:
	pass  # Guard actions are not stored in ActionQueue; nothing to undo here yet.
