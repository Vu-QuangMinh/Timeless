extends Node2D

const _Character := preload("res://scripts/character.gd")

signal _commit_done()

var _level: Node2D
var _characters: Array = []   # Array[PlayerCharacter]
var _selected_idx: int = 0

var _path_preview: PathPreview
var _context_menu: ContextMenu
var _hud: HUD

var _input_locked: bool = false

# Callables matched to the labels shown in the last context menu
var _pending_actions: Array = []


func _ready() -> void:
	_level = preload("res://scenes/level_1/level_1.tscn").instantiate()
	add_child(_level)

	_path_preview = preload("res://scenes/ui/path_preview.tscn").instantiate()
	add_child(_path_preview)

	var pc_scene := preload("res://scenes/characters/player_character.tscn")
	var classes := [
		_Character.CharacterClass.BRAWLER,
		_Character.CharacterClass.CAT_BURGLAR,
		_Character.CharacterClass.HACKER,
	]
	var spawn_x := [0.6, 1.44, 2.3]
	for i in 3:
		var pc := pc_scene.instantiate() as PlayerCharacter
		pc.setup(i, _Character.new(classes[i]))
		add_child(pc)
		pc.set_logical_pos(Vector2(spawn_x[i], 3.0))
		_characters.append(pc)

	_context_menu = preload("res://scenes/ui/context_menu.tscn").instantiate()
	add_child(_context_menu)
	_context_menu.item_selected.connect(_on_action_selected)

	_hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	_hud.commit_pressed.connect(_on_commit_pressed)

	GameManager.start_mission(60.0)
	GameManager.mission_ended.connect(_on_mission_ended)

	_select(0)


func _unhandled_input(event: InputEvent) -> void:
	if _input_locked:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:
				_context_menu.close()
				_select((_selected_idx + 1) % _characters.size())
			KEY_QUOTELEFT:
				_context_menu.close()
				_undo()
			KEY_R:
				_context_menu.close()
				_reset()
		return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_on_left_click()
			MOUSE_BUTTON_RIGHT:
				_on_right_click()


func _select(idx: int) -> void:
	for i in _characters.size():
		if i == idx:
			_characters[i].select()
		else:
			_characters[i].deselect()
	_selected_idx = idx
	_update_hud()


func _undo() -> void:
	var pc: PlayerCharacter = _characters[_selected_idx]
	pc.undo_last_action()
	_path_preview.set_paths(pc.char_id, pc.get_move_paths())
	_update_hud()


func _reset() -> void:
	var pc: PlayerCharacter = _characters[_selected_idx]
	pc.reset_actions()
	_path_preview.clear_char(pc.char_id)
	_update_hud()


func _on_left_click() -> void:
	var world_pos := IsoMath.unproject(get_global_mouse_position())
	if _context_menu.is_open():
		return
	for i in _characters.size():
		if world_pos.distance_to(_characters[i].logical_pos) < 0.5:
			_select(i)
			return


func _make_item(label: String, enabled: bool) -> Dictionary:
	return {"label": label, "enabled": enabled}


func _on_right_click() -> void:
	if not GameManager.mission_active:
		return
	_context_menu.close()
	_pending_actions.clear()
	var items: Array = []

	var world_pos := IsoMath.unproject(get_global_mouse_position())
	var screen_pos := get_viewport().get_mouse_position()
	var pc: PlayerCharacter = _characters[_selected_idx]

	# 1. Other character nearby (0.4 m)?
	for i in _characters.size():
		if i == _selected_idx:
			continue
		if world_pos.distance_to(_characters[i].logical_pos) < 0.4:
			return

	# 2. Chest nearby (1.5 m)?
	var chest_center: Vector2 = _level.get_chest_obstacle()["center"]
	if not _level.chest_picked_up and world_pos.distance_to(chest_center) < 1.5:
		_build_chest_items(items, chest_center, pc)
		if not items.is_empty():
			_context_menu.show_at(screen_pos, items)
			return

	# 3. Floor (within room bounds)?
	if _level.get_room_bounds().has_point(world_pos):
		_build_move_items(items, world_pos, pc)

	if items.is_empty():
		return
	_context_menu.show_at(screen_pos, items)


func _on_action_selected(idx: int) -> void:
	if idx >= 0 and idx < _pending_actions.size():
		_pending_actions[idx].call()
	_pending_actions.clear()


# ── Commit phase ──────────────────────────────────────────────────────────────

func _on_commit_pressed() -> void:
	if GameManager.phase != GameManager.Phase.PLANNING or _input_locked:
		return
	_context_menu.close()
	_path_preview.clear_all()
	_input_locked = true
	_hud.set_phase("COMMITTING...")
	_run_commit()


func _run_commit() -> void:
	var tweens: Array[Tween] = []
	for ch in _characters:
		var t := (ch as PlayerCharacter).commit_actions(self)
		if t != null:
			tweens.append(t)

	if tweens.is_empty():
		_after_commit()
		return

	var counter: Array = [tweens.size()]
	for t in tweens:
		t.finished.connect(func() -> void:
			counter[0] -= 1
			if counter[0] == 0:
				_commit_done.emit()
		)

	await _commit_done
	_after_commit()


func _after_commit() -> void:
	for ch in _characters:
		var pc := ch as PlayerCharacter
		pc.clear_queue_after_commit()
	GameManager.advance_timer(GameManager.TURN_BUDGET_S)
	TurnManager.start_next_turn()
	_input_locked = false
	_update_hud()
	_hud.set_phase("PLANNING")


func _on_mission_ended() -> void:
	_input_locked = true
	_hud.set_phase("TIME UP")


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_planned_end_pos(pc: PlayerCharacter) -> Vector2:
	var pos := pc.logical_pos
	for entry in ActionQueue.get_queue(pc.char_id):
		if entry["type"] == "move":
			pos = entry["end_pos"]
	return pos


func _approach_pos(target: Vector2, from: Vector2, dist: float) -> Vector2:
	var d := target - from
	if d.length() <= dist:
		return from
	return target - d.normalized() * dist


func _build_path(from: Vector2, to: Vector2, pc: PlayerCharacter) -> MovePath:
	var wall_segs: Array = _level.get_wall_segments()
	var obstacles: Array = []
	var chest_obs: Dictionary = _level.get_chest_obstacle()
	if chest_obs["radius"] > 0.0:
		obstacles.append(chest_obs)
	var pf := Pathfinder.new()
	pf.setup(wall_segs, obstacles)
	var waypoints := pf.find_path(from, to)
	if waypoints.is_empty():
		return null
	var smoother := PathSmoother.new()
	return smoother.smooth(waypoints, wall_segs, obstacles)


func _build_move_items(items: Array, target: Vector2, pc: PlayerCharacter) -> void:
	var start := _get_planned_end_pos(pc)
	var path := _build_path(start, target, pc)
	if path == null:
		items.append(_make_item("Move here — Unreachable", false))
		_pending_actions.append(func() -> void: pass)
		return
	var cost := TimeCalculator.move_time(
		path.total_length(), pc.char_data.char_agi, pc.char_data.effective_weight())
	var enabled := cost <= pc.get_turn_time_remaining() + 0.001
	var label: String
	if enabled:
		label = "Move here  (%.1fs)" % cost
	else:
		label = "Move here — not enough time  (%.1fs needed)" % cost
	items.append(_make_item(label, enabled))
	_pending_actions.append(func() -> void:
		var action := ActionMove.new(pc, path)
		pc.queue_action(action)
		_path_preview.set_paths(pc.char_id, pc.get_move_paths())
		_update_hud()
	)


func _build_chest_items(items: Array, chest_center: Vector2, pc: PlayerCharacter) -> void:
	var start := _get_planned_end_pos(pc)
	# 1.4 m approach: safely outside the pathfinder's inflated obstacle
	# (chest radius 0.75 + char radius 0.5 = 1.25 m effective).
	var approach := _approach_pos(chest_center, start, 1.4)
	var needs_move := start.distance_to(chest_center) > 1.5

	var move_path: MovePath = null
	var move_cost := 0.0
	var unreachable := false
	if needs_move:
		move_path = _build_path(start, approach, pc)
		if move_path != null:
			move_cost = TimeCalculator.move_time(
				move_path.total_length(), pc.char_data.char_agi, pc.char_data.effective_weight())
		else:
			unreachable = true

	var remaining := pc.get_turn_time_remaining()

	if _level.chest_locked:
		var complexity := 1
		var lock_cost := TimeCalculator.pick_lock_time(complexity, pc.char_data.char_int)
		var total_cost := move_cost + lock_cost
		var label: String
		var enabled: bool
		if unreachable:
			label = "Pick Lock — Unreachable"
			enabled = false
		elif needs_move:
			enabled = total_cost <= remaining + 0.001
			if enabled:
				label = "Move + Pick Lock  (%.1fs + %.1fs)" % [move_cost, lock_cost]
			else:
				label = "Move + Pick Lock — not enough time  (%.1fs + %.1fs needed)" % [move_cost, lock_cost]
		else:
			enabled = lock_cost <= remaining + 0.001
			if enabled:
				label = "Pick Lock  (%.1fs)" % lock_cost
			else:
				label = "Pick Lock — not enough time  (%.1fs needed)" % lock_cost
		items.append(_make_item(label, enabled))
		var captured_move := move_path
		var captured_level := _level
		_pending_actions.append(func() -> void:
			if captured_move != null:
				pc.queue_action(ActionMove.new(pc, captured_move))
				_path_preview.set_paths(pc.char_id, pc.get_move_paths())
			var pick_lock := ActionPickLock.new(pc, complexity, "mechanical", chest_center)
			pick_lock.on_complete = func(): captured_level.unlock_chest()
			pc.queue_action(pick_lock)
			_update_hud()
		)
	else:
		var chest_kg := 5.0
		var pickup_cost := TimeCalculator.pickup_time(chest_kg, pc.char_data.char_str)
		var total_cost := move_cost + pickup_cost
		var label: String
		var enabled: bool
		if unreachable:
			label = "Pick Up Chest — Unreachable"
			enabled = false
		elif needs_move:
			enabled = total_cost <= remaining + 0.001
			if enabled:
				label = "Move + Pick Up Chest  (%.1fs + %.1fs)" % [move_cost, pickup_cost]
			else:
				label = "Move + Pick Up Chest — not enough time  (%.1fs + %.1fs needed)" % [move_cost, pickup_cost]
		else:
			enabled = pickup_cost <= remaining + 0.001
			if enabled:
				label = "Pick Up Chest  (%.1fs)" % pickup_cost
			else:
				label = "Pick Up Chest — not enough time  (%.1fs needed)" % pickup_cost
		items.append(_make_item(label, enabled))
		var captured_move := move_path
		var captured_level := _level
		_pending_actions.append(func() -> void:
			if captured_move != null:
				pc.queue_action(ActionMove.new(pc, captured_move))
				_path_preview.set_paths(pc.char_id, pc.get_move_paths())
			var pickup := ActionPickUp.new(pc, "chest", chest_kg, 1000.0)
			pickup.on_complete = func(): captured_level.pickup_chest()
			pc.queue_action(pickup)
			_update_hud()
		)


func _update_hud() -> void:
	if _hud:
		_hud.refresh(_characters, _selected_idx)
