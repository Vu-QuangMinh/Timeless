class_name PlayerCharacter
extends Node2D

signal time_remaining_changed(char_id: int, remaining: float)

# Class colors: Brawler=red, Cat Burglar=slate-blue, Hacker=green
const COLOR_BY_CLASS: Array = [
	Color("#dc4444"),
	Color("#2c2c34"),
	Color("#5acb5d"),
]

var char_id: int = 0
var char_data = null        # Character instance (untyped to avoid parse-order dep)
var logical_pos: Vector2 = Vector2.ZERO
var is_selected: bool = false
var is_taken_down: bool = false

var _action_objects: Array = []  # Array[ActionBase]


func setup(id: int, char: Object) -> void:
	char_id = id
	char_data = char


func set_logical_pos(p: Vector2) -> void:
	logical_pos = p
	position = IsoMath.project(p)
	queue_redraw()


func select() -> void:
	is_selected = true
	queue_redraw()


func deselect() -> void:
	is_selected = false
	queue_redraw()


func queue_action(action) -> void:
	action.char_id = char_id
	var start_t := ActionQueue.get_next_available_time(char_id)
	var d: Dictionary = action.to_dict()
	d["start_time"] = start_t
	ActionQueue.add_action(char_id, d)
	_action_objects.append(action)
	emit_signal("time_remaining_changed", char_id, get_turn_time_remaining())


func undo_last_action() -> void:
	if _action_objects.is_empty():
		return
	_action_objects.pop_back()
	ActionQueue.undo_last(char_id)
	emit_signal("time_remaining_changed", char_id, get_turn_time_remaining())


func reset_actions() -> void:
	_action_objects.clear()
	ActionQueue.reset(char_id)
	emit_signal("time_remaining_changed", char_id, get_turn_time_remaining())


func get_turn_time_used() -> float:
	var total := 0.0
	for entry in ActionQueue.get_queue(char_id):
		total += entry["cost"]
	return total


func get_turn_time_remaining() -> float:
	return GameManager.TURN_BUDGET_S - get_turn_time_used()


func get_move_paths() -> Array:
	var paths := []
	for a in _action_objects:
		if a is ActionMove:
			paths.append(a.path)
	return paths


func _draw() -> void:
	if is_taken_down:
		draw_circle(Vector2.ZERO, 10.0, Color(0.4, 0.4, 0.4, 0.7))
		return
	var col: Color = COLOR_BY_CLASS[int(char_data.char_class)] if char_data else Color.GRAY
	draw_circle(Vector2.ZERO, 12.0, col)
	if is_selected:
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 32, Color.WHITE, 2.5)
	var font := ThemeDB.fallback_font
	var fs := ThemeDB.fallback_font_size
	draw_string(font, Vector2(-14.0, -20.0), char_data.display_name() if char_data else "",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 4, Color.WHITE)
