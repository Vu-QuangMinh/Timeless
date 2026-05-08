extends Node

# keyed by char_id -> Array[Dictionary{start_time, cost, type, ...}]
var _queues: Dictionary = {}


func get_queue(char_id: int) -> Array:
	return _queues.get(char_id, [])


func add_action(char_id: int, action: Dictionary) -> void:
	if not _queues.has(char_id):
		_queues[char_id] = []
	_queues[char_id].append(action)


func get_next_available_time(char_id: int) -> float:
	var q := get_queue(char_id)
	if q.is_empty():
		return 0.0
	var last: Dictionary = q[-1]
	return last["start_time"] + last["cost"]


func undo_last(char_id: int) -> void:
	var q := get_queue(char_id)
	if not q.is_empty():
		q.pop_back()


func reset(char_id: int) -> void:
	_queues[char_id] = []


func erase_from_time(char_id: int, t: float) -> void:
	var q := get_queue(char_id)
	var i := q.size() - 1
	while i >= 0:
		if q[i]["start_time"] >= t:
			q.remove_at(i)
		i -= 1


func clear_all() -> void:
	_queues.clear()
