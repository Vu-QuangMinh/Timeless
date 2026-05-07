## PlayerCharacter
## Extends Character with player-specific logic: turn time tracking, selection state,
## and registration with ActionQueue. Builds its own visuals via _draw() — no child nodes required.
## Does NOT handle input events (main.gd does click/Tab). Does NOT implement guard logic.

class_name PlayerCharacter
extends Character

signal time_remaining_changed(seconds: float)
signal time_bar_animate(to_seconds: float, over_real_seconds: float)
signal selected_changed(is_selected: bool)

const TURN_BUDGET   := 10.0
const CHAR_RADIUS   := 8.0   # pixels; 0.5m at 16px/m
# Fallen ellipse dimensions (2m × 0.7m at 16px/m)
const FALLEN_A      := 16.0  # semi-major axis (1m)
const FALLEN_B      := 5.6   # semi-minor axis (0.35m)

var is_selected:   bool = false
var is_taken_down: bool = false

## World position after all queued actions complete. Use this for range checks and
## pathfinding — not global_position, which is animated and lags during planning.
var logical_pos: Vector2

var _col_shape: CollisionShape2D
var _action_objects: Array[ActionBase] = []
var _move_tween: Tween = null
var _turn_start_pos: Vector2

func _ready() -> void:
	super._ready()
	ActionQueue.register_character(character_id)
	_turn_start_pos = position
	logical_pos     = position

	_col_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = CHAR_RADIUS
	_col_shape.shape = circle
	add_child(_col_shape)

func _draw() -> void:
	if is_taken_down:
		_draw_fallen()
		return

	var fill := Color.CYAN if is_selected else _class_color()
	draw_circle(Vector2.ZERO, CHAR_RADIUS, fill)
	if is_selected:
		draw_arc(Vector2.ZERO, CHAR_RADIUS + 2.0, 0.0, TAU, 24, Color.WHITE, 1.5)
	var font   := ThemeDB.fallback_font
	var fs     := 9
	var text   := display_name()
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(-text_w * 0.5, CHAR_RADIUS + 12.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func _draw_fallen() -> void:
	const STEPS := 24
	var pts := PackedVector2Array()
	for i in range(STEPS):
		var a := TAU * float(i) / STEPS
		pts.append(Vector2(cos(a) * FALLEN_A, sin(a) * FALLEN_B))
	draw_colored_polygon(pts, _class_color().darkened(0.45))
	# X marker
	var r := FALLEN_B * 0.75
	draw_line(Vector2(-r, -r), Vector2( r,  r), Color(0.9, 0.9, 0.9), 1.0)
	draw_line(Vector2( r, -r), Vector2(-r,  r), Color(0.9, 0.9, 0.9), 1.0)
	# Name label (greyed out)
	var font   := ThemeDB.fallback_font
	var fs     := 9
	var text   := display_name()
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(-text_w * 0.5, FALLEN_B + 12.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.5, 0.5, 0.5))

func select() -> void:
	is_selected = true
	queue_redraw()
	emit_signal("selected_changed", true)

func deselect() -> void:
	is_selected = false
	queue_redraw()
	emit_signal("selected_changed", false)

func get_turn_time_remaining() -> float:
	return TURN_BUDGET - ActionQueue.get_time_used(character_id)

func get_queued_actions() -> Array[ActionBase]:
	return _action_objects

## Mark this character as taken down: freezes visuals and blocks future actions.
## Does NOT clear _action_objects so restore_from_predict() can replay planning animations on Back.
func take_down() -> void:
	if is_taken_down:
		return
	is_taken_down = true
	if _move_tween:
		_move_tween.kill()
		_move_tween = null
	position = logical_pos
	scale    = Vector2.ONE
	queue_redraw()

## Queue an action: register cost, update logical_pos for moves, then replay the full
## action sequence visually from turn-start so planning animations stay correct.
func queue_action(action: ActionBase) -> void:
	if is_taken_down:
		return
	if _move_tween:
		_move_tween.kill()
		_move_tween = null

	ActionQueue.push_action(character_id, action.action_type, action.cost)
	emit_signal("time_bar_animate", get_turn_time_remaining(), action.get_animation_duration())

	var action_start_pos := logical_pos
	_action_objects.append(action)

	var as_move := action as ActionMove
	if as_move and as_move.path:
		logical_pos = as_move.path.end_pos

	position    = action_start_pos
	scale       = Vector2.ONE
	_move_tween = create_tween()
	action.execute_visual(self, _move_tween)

## Queue multiple actions as one atomic sequence (e.g. move + takedown).
## Runs all execute_visual calls on a single tween so the character slides
## to the target before performing the follow-up action.
func queue_actions(actions: Array[ActionBase]) -> void:
	if is_taken_down:
		return
	if _move_tween:
		_move_tween.kill()
		_move_tween = null

	var start_pos     := logical_pos
	var total_anim_dur := 0.0

	for action in actions:
		ActionQueue.push_action(character_id, action.action_type, action.cost)
		_action_objects.append(action)
		total_anim_dur += action.get_animation_duration()
		var as_move := action as ActionMove
		if as_move and as_move.path:
			logical_pos = as_move.path.end_pos

	emit_signal("time_bar_animate", get_turn_time_remaining(), total_anim_dur)

	position    = start_pos
	scale       = Vector2.ONE
	_move_tween = create_tween()
	for action in actions:
		action.execute_visual(self, _move_tween)

func undo_last_action() -> void:
	if _action_objects.is_empty():
		return
	if _move_tween:
		_move_tween.kill()
		_move_tween = null
	_action_objects.pop_back()
	ActionQueue.undo_last(character_id)

	logical_pos = _turn_start_pos
	for a in _action_objects:
		var as_move := a as ActionMove
		if as_move and as_move.path:
			logical_pos = as_move.path.end_pos

	_replay_visual()
	emit_signal("time_remaining_changed", get_turn_time_remaining())

func reset_turn_actions() -> void:
	if _move_tween:
		_move_tween.kill()
		_move_tween = null
	_action_objects.clear()
	ActionQueue.reset_character(character_id)
	logical_pos = _turn_start_pos
	position    = _turn_start_pos
	scale       = Vector2.ONE
	emit_signal("time_remaining_changed", get_turn_time_remaining())

func on_new_turn() -> void:
	if _move_tween:
		_move_tween.kill()
		_move_tween = null
	_action_objects.clear()
	scale           = Vector2.ONE
	_turn_start_pos = position
	logical_pos     = position
	emit_signal("time_remaining_changed", get_turn_time_remaining())

## Called when entering Predict: freeze the character at their logical (end-of-plan) position.
func finalize_for_predict() -> void:
	if _move_tween:
		_move_tween.kill()
		_move_tween = null
	position = logical_pos
	scale    = Vector2.ONE

## Called when returning to Planning from Predict: restart the planning animations.
func restore_from_predict() -> void:
	_replay_visual()

## Kill any running tween, reset to turn-start, replay every queued action in order.
func _replay_visual() -> void:
	position = _turn_start_pos
	scale    = Vector2.ONE
	if _action_objects.is_empty():
		return
	_move_tween = create_tween()
	for a in _action_objects:
		a.execute_visual(self, _move_tween)

func _class_color() -> Color:
	match character_class:
		Character.CharacterClass.BRAWLER:     return Color(0.9, 0.3, 0.3)
		Character.CharacterClass.CAT_BURGLAR: return Color(0.3, 0.9, 0.3)
		Character.CharacterClass.HACKER:      return Color(0.3, 0.5, 1.0)
		_: return Color.WHITE
