## Main
## Entry point scene. Spawns test map, 3 player characters, 3 guards, camera, HUD, and UI overlays.
## Owns character selection (click / Tab), right-click context menu, path preview, and
## Predict-phase guard AI simulation.
## Handles planning-phase keyboard shortcuts: ` (undo), R (reset all), Tab (cycle).

extends Node2D

const PlayerCharScene  := preload("res://scenes/characters/player_character.tscn")
const TestMapScene     := preload("res://scenes/level_1/level_1.tscn")
const HUDScene         := preload("res://scenes/ui/hud.tscn")
const ContextMenuScene := preload("res://scenes/ui/context_menu.tscn")
const PathPreviewScene := preload("res://scenes/ui/path_preview.tscn")

const SPAWN_POSITIONS := [
	Vector2(-56.0, 272.0),
	Vector2(  0.0, 272.0),
	Vector2( 56.0, 272.0),
]
const SPAWN_CLASSES := [
	Character.CharacterClass.BRAWLER,
	Character.CharacterClass.CAT_BURGLAR,
	Character.CharacterClass.HACKER,
]

# Chest geometry (matches TestMap)
const CHEST_CENTER  := Vector2.ZERO
const CHEST_OBS_R   := 24.0
const CHEST_CLICK_R := 48.0

# Door centres — walls at ±320 px (TestMap.HALF, 10m at 32px/m)
const DOOR_CENTERS: Array = [
	Vector2(  0.0,  320.0),
	Vector2(  0.0, -320.0),
	Vector2(-320.0,   0.0),
	Vector2( 320.0,   0.0),
]
const DOOR_CLICK_R    := 48.0
const ACTION_REACH_PX := 16.0   # 0.5 m × 32 px/m
const GUARD_CLICK_R   := 32.0
const CCTV_CLICK_R    := 40.0

# Guard Predict constants
const GUARD_SPEED_PX  := 40.0   # 1.25 m/s × 32 px/m
const GUN_RANGE_PX    := 640.0  # 20 m × 32 px/m
const TASER_RANGE_PX  := 16.0   # 0.5 m × 32 px/m
const GUN_FIRE_S      := 3.0    # seconds to fire
const TASER_S         := 2.0    # seconds to tase

# CCTV Predict constants
const CCTV_DETECT_STEP_S := 0.1  # game-seconds per detection sample (100 steps / turn)

var _characters: Array[PlayerCharacter] = []
var _guards: Array[Guard] = []
var _selected_index: int = 0
var _hud: HUD
var _map: Node2D
var _context_menu: ContextMenu
var _path_preview: PathPreview
var _menu_layer: CanvasLayer

var _cctvs: Array = []
var _cctvs_hacked_baseline: Dictionary = {}

var _chest_locked: bool    = true
var _chest_picked_up: bool = false
var _predict_downed: Array[PlayerCharacter] = []
# guard_id → is_neutralized state at the start of the current planning phase (post-commit)
var _guards_neutralized_baseline: Dictionary = {}

func _ready() -> void:
	_setup_camera()
	_setup_map()
	_spawn_characters()
	_spawn_guards()
	_load_cctvs()
	_setup_hud()
	_setup_overlays()
	TurnManager.phase_changed.connect(_on_phase_changed_main)
	TurnManager.turn_started.connect(_on_turn_started)
	GameManager.start_mission(60.0)
	TurnManager.start_first_turn()
	_select(0)

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func _setup_camera() -> void:
	var cam := Camera2D.new()
	cam.set_script(preload("res://scripts/camera_zoom.gd"))
	cam.zoom = Vector2(0.9, 0.9)
	add_child(cam)

func _setup_map() -> void:
	_map = TestMapScene.instantiate()
	add_child(_map)

func _spawn_characters() -> void:
	var chars_node := Node2D.new()
	chars_node.name = "Characters"
	add_child(chars_node)
	for i in SPAWN_CLASSES.size():
		var ch: PlayerCharacter = PlayerCharScene.instantiate()
		ch.character_id    = i
		ch.character_class = SPAWN_CLASSES[i]
		if SPAWN_CLASSES[i] == Character.CharacterClass.HACKER:
			ch.position = _iso_project(Vector3(1, 141, 0))
		else:
			ch.position = SPAWN_POSITIONS[i]
		chars_node.add_child(ch)
		_characters.append(ch)


func _iso_project(p: Vector3) -> Vector2:
	const COS30 := 0.8660254
	const SIN30 := 0.5
	return Vector2((p.x + p.y) * COS30, (p.x - p.y) * SIN30 - p.z)

func _spawn_guards() -> void:
	var guards_node := Node2D.new()
	guards_node.name = "Guards"
	add_child(guards_node)
	var base_angle := randf() * TAU
	for i in 3:
		var jitter := (randf() - 0.5) * deg_to_rad(50.0)
		var angle  := base_angle + i * (TAU / 3.0) + jitter
		var pos    := Vector2(cos(angle), sin(angle)) * 160.0   # 5 m × 32 px/m
		var g              := Guard.new()
		g.guard_id          = i
		g.position          = pos
		g.facing_angle      = _angle_to_nearest_door(pos)
		g.patrol_turn_angle = PI / 2.0 if randf() < 0.5 else -PI / 2.0
		guards_node.add_child(g)
		_guards.append(g)

func _load_cctvs() -> void:
	_cctvs = _map.get_cctvs()

func _setup_hud() -> void:
	_hud = HUDScene.instantiate()
	add_child(_hud)
	_hud.predict_pressed.connect(_on_predict_pressed)
	_hud.commit_pressed.connect(_on_commit_pressed)
	_hud.back_pressed.connect(_on_back_pressed)

func _setup_overlays() -> void:
	_path_preview = PathPreviewScene.instantiate()
	add_child(_path_preview)

	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 10
	add_child(_menu_layer)

	_context_menu = ContextMenuScene.instantiate()
	_menu_layer.add_child(_context_menu)
	_context_menu.action_selected.connect(_on_action_selected)
	_context_menu.closed.connect(_on_menu_closed)

func _angle_to_nearest_door(pos: Vector2) -> float:
	var nearest := DOOR_CENTERS[0] as Vector2
	var best_sq := pos.distance_squared_to(nearest)
	for i in range(1, DOOR_CENTERS.size()):
		var dc := DOOR_CENTERS[i] as Vector2
		var sq := pos.distance_squared_to(dc)
		if sq < best_sq:
			best_sq = sq
			nearest = dc
	return (nearest - pos).angle()

# ---------------------------------------------------------------------------
# Phase / turn signal handlers
# ---------------------------------------------------------------------------

func _on_phase_changed_main(phase: GameManager.Phase) -> void:
	if phase == GameManager.Phase.PREDICT:
		_run_predict()

func _on_turn_started(_turn_number: int) -> void:
	# Snapshot guard/CCTV state so undo/reset can restore to this baseline.
	for g in _guards:
		_guards_neutralized_baseline[g.guard_id] = g.is_neutralized
	for cctv in _cctvs:
		_cctvs_hacked_baseline[cctv.cctv_id] = cctv.is_hacked
	for ch in _characters:
		ch.on_new_turn()
	_hud.update_selected_character(_selected_char())

# ---------------------------------------------------------------------------
# HUD button handlers
# ---------------------------------------------------------------------------

func _on_predict_pressed() -> void:
	TurnManager.enter_predict()
	# _run_predict() is triggered by the phase_changed signal above.

func _on_commit_pressed() -> void:
	_predict_downed.clear()  # taken-down state persists into next turns
	TurnManager.commit_turn()

func _on_back_pressed() -> void:
	# Kill guard predict animations and snap them back to pre-predict state.
	for g in _guards:
		if g._predict_tween:
			g._predict_tween.kill()
			g._predict_tween = null
		g.position     = g._predict_start_pos
		g.facing_angle = g._predict_start_facing
		g.modulate     = Color.WHITE
		g.queue_redraw()
	# Restore CCTV pan phase to pre-predict snapshot.
	for cctv in _cctvs:
		cctv._time = cctv._predict_start_time
		cctv.rotation = cctv._base_rotation + deg_to_rad(cctv.pan_amplitude_deg) * \
			sin(cctv._predict_start_time * TAU / max(cctv.pan_period_sec, 0.01))
	# Restore any characters taken down during this preview.
	for ch in _predict_downed:
		ch.is_taken_down = false
		ch.queue_redraw()
	_predict_downed.clear()
	# Restart player planning animations.
	for ch in _characters:
		ch.restore_from_predict()
	TurnManager.back_to_planning()

# ---------------------------------------------------------------------------
# Predict-phase guard AI
# ---------------------------------------------------------------------------

func _run_predict() -> void:
	_predict_downed.clear()
	# Snap every player to their logical (end-of-planning) position.
	for ch in _characters:
		ch.finalize_for_predict()

	var hostage_held := _anyone_holding_hostage()

	for g in _guards:
		if g.is_neutralized:
			continue
		g._predict_start_pos    = g.global_position
		g._predict_start_facing = g.facing_angle

		var target := _guard_fov_target(g)
		if target == null:
			_animate_guard_patrol(g)
			continue

		var dist := g.global_position.distance_to(target.logical_pos)
		if not hostage_held and dist <= GUN_RANGE_PX and dist > TASER_RANGE_PX:
			_animate_guard_shoot(g, target)
		else:
			_animate_guard_move(g, target)

	_predict_cctv_detections()

## Nearest non-downed player inside the guard's FOV cone, or null if none visible.
func _guard_fov_target(guard: Guard) -> PlayerCharacter:
	var nearest: PlayerCharacter = null
	var best_dist := INF
	for ch in _characters:
		if ch.is_taken_down:
			continue
		if not _is_in_guard_fov(guard, ch.logical_pos):
			continue
		var d := guard.global_position.distance_to(ch.logical_pos)
		if d < best_dist:
			best_dist = d
			nearest   = ch
	return nearest

func _is_in_guard_fov(guard: Guard, target_pos: Vector2) -> bool:
	var to_target := target_pos - guard.global_position
	var dist      := to_target.length()
	if dist > GUN_RANGE_PX:
		return false
	if dist < 0.5:
		return true
	var facing_dir := Vector2(cos(guard.facing_angle), sin(guard.facing_angle))
	return absf(facing_dir.angle_to(to_target.normalized())) <= Guard.FOV_HALF_RAD

## How far the guard can move in dir before the FOV front point (pos + dir*(d + FOV_VIS)) hits a wall.
func _fov_wall_dist(pos: Vector2, dir: Vector2) -> float:
	const ROOM_HALF := 320.0  # TestMap.HALF — 10m × 32px/m
	var fov_vis := Guard.FOV_VISUAL_PX
	var best    := INF
	if dir.x > 0.001:
		var d := (ROOM_HALF  - pos.x) / dir.x - fov_vis
		if d >= 0.0: best = minf(best, d)
	elif dir.x < -0.001:
		var d := (-ROOM_HALF - pos.x) / dir.x - fov_vis
		if d >= 0.0: best = minf(best, d)
	if dir.y > 0.001:
		var d := (ROOM_HALF  - pos.y) / dir.y - fov_vis
		if d >= 0.0: best = minf(best, d)
	elif dir.y < -0.001:
		var d := (-ROOM_HALF - pos.y) / dir.y - fov_vis
		if d >= 0.0: best = minf(best, d)
	return 0.0 if is_inf(best) else best

## Cardinal angle pointing directly toward the nearest wall from pos.
func _facing_toward_nearest_wall(pos: Vector2) -> float:
	const ROOM_HALF := 320.0
	var d_north := pos.y - (-ROOM_HALF)
	var d_south := ROOM_HALF - pos.y
	var d_west  := pos.x - (-ROOM_HALF)
	var d_east  := ROOM_HALF - pos.x
	var min_d   := minf(minf(d_north, d_south), minf(d_west, d_east))
	if   min_d == d_north: return -PI / 2.0   # face north (up)
	elif min_d == d_south: return  PI / 2.0   # face south (down)
	elif min_d == d_west:  return  PI         # face west  (left)
	else:                  return  0.0        # face east  (right)

## Patrol: face the nearest wall perpendicularly, move until FOV front hits it, then turn by
## patrol_turn_angle (set at spawn). Repeats for the full turn budget.
func _animate_guard_patrol(guard: Guard) -> void:
	guard._predict_tween = create_tween()
	var pos     := guard.global_position
	# Always start by facing directly toward the nearest wall, regardless of current heading.
	var facing  := _facing_toward_nearest_wall(pos)
	var cf0     := facing
	guard._predict_tween.tween_callback(func():
		guard.facing_angle = cf0
		guard.queue_redraw()
	)
	var elapsed := 0.0
	var budget  := GameManager.TURN_DURATION
	var safety  := 0

	while elapsed < budget - 0.001 and safety < 50:
		safety += 1
		var dir  := Vector2(cos(facing), sin(facing))
		var dist := _fov_wall_dist(pos, dir)

		if dist <= 0.5:
			# Already at wall stop — turn in place without moving.
			facing = wrapf(facing + guard.patrol_turn_angle, -PI, PI)
			var cf := facing
			guard._predict_tween.tween_callback(func():
				guard.facing_angle = cf
				guard.queue_redraw()
			)
			continue

		var secs_to_wall := dist / GUARD_SPEED_PX

		if elapsed + secs_to_wall >= budget:
			# Partial move fills the remaining budget.
			var remaining := budget - elapsed
			var end_pos   := pos + dir * (GUARD_SPEED_PX * remaining)
			guard._predict_tween.tween_property(
				guard, "position", end_pos,
				remaining / GameManager.ANIMATION_SPEED_MULTIPLIER)
			break

		# Full move to the wall stop, then turn.
		var stop_pos := pos + dir * dist
		guard._predict_tween.tween_property(
			guard, "position", stop_pos,
			secs_to_wall / GameManager.ANIMATION_SPEED_MULTIPLIER)
		elapsed += secs_to_wall
		pos      = stop_pos
		facing   = wrapf(facing + guard.patrol_turn_angle, -PI, PI)
		var cf   := facing
		guard._predict_tween.tween_callback(func():
			guard.facing_angle = cf
			guard.queue_redraw()
		)

## Recompute every guard's is_neutralized from scratch:
## start from the committed baseline, then re-apply any takedowns in the current planning queues.
## Call after any queue/undo/reset that involves a takedown action.
func _recompute_guard_neutralizations() -> void:
	for g in _guards:
		g.is_neutralized = _guards_neutralized_baseline.get(g.guard_id, false)
	for ch in _characters:
		if ch.is_taken_down:
			continue
		for action in ch.get_queued_actions():
			var td := action as ActionTakedown
			if td == null:
				continue
			for g in _guards:
				if g.guard_id == td.target_id:
					g.is_neutralized = true
					break
	for g in _guards:
		g.queue_redraw()

## Recompute every CCTV's is_hacked from the committed baseline, then re-apply
## any camera hack actions in the current planning queues.
func _recompute_cctv_hacks() -> void:
	for cctv in _cctvs:
		if _cctvs_hacked_baseline.get(cctv.cctv_id, false):
			cctv.hack()
		else:
			cctv.restore()
	for ch in _characters:
		if ch.is_taken_down:
			continue
		for action in ch.get_queued_actions():
			var ha := action as ActionHack
			if ha == null or ha.target_type != "cctv":
				continue
			for cctv in _cctvs:
				if cctv.global_position.distance_to(ha.target_pos) < 2.0:
					cctv.hack()
					break

## For each non-hacked CCTV, step through the 10 s turn budget in CCTV_DETECT_STEP_S increments
## and take down any player whose logical position falls inside the cone at any sample point.
## Uses the same _predict_downed list as guard-shoot so Back-to-Planning restores them.
func _predict_cctv_detections() -> void:
	var wall_segs: Array = _map.get_wall_segments()
	var step_count := int(GameManager.TURN_DURATION / CCTV_DETECT_STEP_S)
	for cctv in _cctvs:
		if cctv.is_hacked:
			continue
		cctv._predict_start_time = cctv._time
		for i in range(step_count + 1):
			var t := i * CCTV_DETECT_STEP_S
			var rot: float = cctv._base_rotation + deg_to_rad(cctv.pan_amplitude_deg) * \
				sin((cctv._predict_start_time + t) * TAU / max(cctv.pan_period_sec, 0.01))
			var facing := Vector2(-sin(rot), cos(rot))
			for ch in _characters:
				if ch.is_taken_down:
					continue
				if _cctv_sees(cctv, facing, ch.logical_pos, wall_segs):
					ch.take_down()
					_predict_downed.append(ch)

## Returns true if the CCTV's cone at the given facing direction covers target_pos with clear LOS.
## Facing direction is the world-space local +Y of the CCTV node: Vector2(-sin(rot), cos(rot)).
func _cctv_sees(cctv: CCTV, facing: Vector2, target_pos: Vector2, wall_segs: Array) -> bool:
	var to_target := target_pos - cctv.global_position
	var dist := to_target.length()
	if dist > cctv.view_distance_px:
		return false
	if dist < 0.5:
		return true
	if absf(facing.angle_to(to_target.normalized())) > deg_to_rad(cctv.fov_half_angle_deg):
		return false
	for ws in wall_segs:
		if Pathfinder._segs_intersect(cctv.global_position, target_pos, ws[0], ws[1]):
			return false
	return true

func _anyone_holding_hostage() -> bool:
	for ch in _characters:
		for entry in ActionQueue.get_queue(ch.character_id):
			if entry.get("type", "") == "hold_hostage":
				return true
	return false

## Guard stays in place, faces target, fires after GUN_FIRE_S seconds, and takes down the target.
func _animate_guard_shoot(guard: Guard, target: PlayerCharacter) -> void:
	guard.facing_angle = (target.logical_pos - guard.global_position).angle()
	guard.queue_redraw()
	var anim_s := GUN_FIRE_S / GameManager.ANIMATION_SPEED_MULTIPLIER
	guard._predict_tween = create_tween()
	guard._predict_tween.tween_interval(anim_s * 0.7)
	guard._predict_tween.tween_callback(func(): guard.modulate = Color(1.6, 0.4, 0.4))
	guard._predict_tween.tween_interval(anim_s * 0.15)
	guard._predict_tween.tween_callback(func(): guard.modulate = Color.WHITE)
	guard._predict_tween.tween_callback(func():
		if not target.is_taken_down:
			target.take_down()
			_predict_downed.append(target)
	)

## Guard moves toward target for up to 10 s worth of movement, stopping just within tase range.
func _animate_guard_move(guard: Guard, target: PlayerCharacter) -> void:
	var dir       := (target.logical_pos - guard.global_position).normalized()
	var dist      := guard.global_position.distance_to(target.logical_pos)
	var max_move  := GUARD_SPEED_PX * GameManager.TURN_DURATION
	var move_dist := minf(maxf(dist - TASER_RANGE_PX, 0.0), max_move)

	guard.facing_angle = dir.angle()
	guard.queue_redraw()

	if move_dist <= 0.0:
		return  # already within tase range

	var new_pos  := guard.global_position + dir * move_dist
	var anim_dur := (move_dist / GUARD_SPEED_PX) / GameManager.ANIMATION_SPEED_MULTIPLIER
	guard._predict_tween = create_tween()
	guard._predict_tween.tween_property(guard, "position", new_pos, anim_dur)
	# Flash on arrival if within tase range.
	if dist - move_dist <= TASER_RANGE_PX + 1.0:
		guard._predict_tween.tween_callback(func(): guard.modulate = Color(0.4, 0.4, 1.6))
		guard._predict_tween.tween_interval(0.15)
		guard._predict_tween.tween_callback(func(): guard.modulate = Color.WHITE)

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_phase != GameManager.Phase.PLANNING:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB:
				_cycle_selection()
			KEY_QUOTELEFT:
				_selected_char().undo_last_action()
				_recompute_guard_neutralizations()
				_recompute_cctv_hacks()
			KEY_R:
				for ch in _characters:
					ch.reset_turn_actions()
				_recompute_guard_neutralizations()
				_recompute_cctv_hacks()
				_hud.update_selected_character(_selected_char())

	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not _context_menu.visible:
				_try_select_at(get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_open_context_menu_at(get_global_mouse_position(), get_viewport().get_mouse_position())

func _try_select_at(world_pos: Vector2) -> void:
	var best_idx  := -1
	var best_dist := 12.0
	for i in _characters.size():
		var d := world_pos.distance_to(_characters[i].global_position)
		if d < best_dist:
			best_dist = d
			best_idx  = i
	if best_idx >= 0:
		_select(best_idx)

# ---------------------------------------------------------------------------
# Context menu
# ---------------------------------------------------------------------------

func _open_context_menu_at(world_pos: Vector2, screen_pos: Vector2) -> void:
	var sel := _selected_char()

	if world_pos.distance_to(sel.global_position) <= PlayerCharacter.CHAR_RADIUS + 2.0:
		return
	for ch in _characters:
		if ch != sel and world_pos.distance_to(ch.global_position) <= PlayerCharacter.CHAR_RADIUS + 2.0:
			return

	var items: Array = []

	if world_pos.distance_to(CHEST_CENTER) < CHEST_CLICK_R:
		items = _build_chest_items(sel)

	if items.is_empty():
		for g in _guards:
			if not g.is_neutralized and world_pos.distance_to(g.global_position) < GUARD_CLICK_R:
				items = _build_guard_items(g, sel)
				break

	if items.is_empty():
		for cctv in _cctvs:
			if not cctv.is_hacked and world_pos.distance_to(cctv.global_position) < CCTV_CLICK_R:
				items = _build_hack_items("cctv", cctv.global_position, sel, "Hack Camera")
				break

	if items.is_empty():
		for dc: Vector2 in DOOR_CENTERS:
			if world_pos.distance_to(dc) < DOOR_CLICK_R:
				items = _build_hack_items("door", dc, sel, "Hack Door")
				break

	if items.is_empty():
		items = _build_move_items(world_pos, sel)

	if items.is_empty():
		return

	_show_preview_for_items(items)
	_context_menu.show_at(screen_pos, items)

# ---------------------------------------------------------------------------
# Item builders
# ---------------------------------------------------------------------------

func _build_move_items(world_pos: Vector2, sel: PlayerCharacter) -> Array:
	var raw_path := Pathfinder.compute(
		sel.logical_pos, world_pos, _build_circles_for(sel), _map.get_wall_segments())
	var items: Array = []

	if raw_path.is_empty():
		items.append({
			label = "Move here", cost_str = "Unreachable",
			enabled = false, action_type = "move", data = {},
		})
		return items

	var path      := PathSmoother.smooth(raw_path)
	var cost      := path.time_cost(sel.stat_agi, sel.effective_weight())
	var remaining := sel.get_turn_time_remaining()

	if cost <= remaining + 0.001:
		items.append({
			label = "Move here", cost_str = "%.1f s" % cost,
			enabled = true, action_type = "move", data = {path = path, cost = cost},
		})
	else:
		items.append({
			label = "Move here — not enough time", cost_str = "%.1f s needed" % cost,
			enabled = false, action_type = "move", data = {},
		})
	return items

func _build_chest_items(sel: PlayerCharacter) -> Array:
	if _chest_picked_up:
		return []

	var in_range  := _in_action_range(sel.logical_pos, CHEST_CENTER, CHEST_OBS_R)
	var remaining := sel.get_turn_time_remaining()
	var items: Array = []

	if _chest_locked:
		var cost := TimeCalculator.lock_time(1, sel.stat_agi, sel.stat_str)
		if in_range:
			items.append(_action_item("Pick Lock", cost, "pick_lock", {cost = cost}, remaining))
		else:
			var move := _path_to(_approach_pos(CHEST_CENTER, CHEST_OBS_R, sel.logical_pos), sel)
			if not move.is_empty():
				items.append(_compound_item("Move + Pick Lock", move, cost, "move_pick_lock", {}, remaining))

	var item_kg     := 60.0 if _chest_locked else 10.0
	var pickup_cost := TimeCalculator.pickup_time(item_kg, sel.stat_str, sel.stat_int)
	var label       := "Pick Up" + (" (locked, +50 kg)" if _chest_locked else "")
	if in_range:
		items.append(_action_item(label, pickup_cost, "pickup",
			{cost = pickup_cost, item_kg = item_kg, item_value = 3.0}, remaining))
	else:
		var move := _path_to(_approach_pos(CHEST_CENTER, CHEST_OBS_R, sel.logical_pos), sel)
		if not move.is_empty():
			items.append(_compound_item("Move + " + label, move, pickup_cost, "move_pickup",
				{item_kg = item_kg, item_value = 3.0}, remaining))

	return items

func _build_guard_items(guard: Guard, sel: PlayerCharacter) -> Array:
	var in_range  := _in_action_range(sel.logical_pos, guard.global_position, Guard.GUARD_RADIUS)
	var remaining := sel.get_turn_time_remaining()
	var move_to_guard := {} if in_range else \
		_path_to(_approach_pos(guard.global_position, Guard.GUARD_RADIUS, sel.logical_pos),
			sel, guard.guard_id)
	var items: Array = []

	var td_cost := TimeCalculator.takedown_time("guard", sel.stat_str)
	if in_range:
		items.append(_action_item("Takedown", td_cost, "takedown",
			{cost = td_cost, guard_id = guard.guard_id, enemy_type = "guard"}, remaining))
	elif not move_to_guard.is_empty():
		items.append(_compound_item("Move + Takedown", move_to_guard, td_cost, "move_takedown",
			{guard_id = guard.guard_id, enemy_type = "guard"}, remaining))

	var hold_dur := TimeCalculator.clamp_hold_duration(5.0)
	if in_range:
		items.append(_action_item("Hold Hostage (5.0 s)", hold_dur, "hold_hostage",
			{cost = hold_dur, guard_id = guard.guard_id, hold_duration = hold_dur}, remaining))
	elif not move_to_guard.is_empty():
		items.append(_compound_item("Move + Hold Hostage (5.0 s)", move_to_guard, hold_dur,
			"move_hold_hostage", {guard_id = guard.guard_id, hold_duration = hold_dur}, remaining))

	return items

func _build_hack_items(target_type: String, target_center: Vector2, sel: PlayerCharacter, base_label: String = "Hack") -> Array:
	var hack_px   := TimeCalculator.hack_range(sel.stat_int) * 32.0
	var cost      := TimeCalculator.hack_time(target_type, sel.stat_int)
	var remaining := sel.get_turn_time_remaining()

	if sel.logical_pos.distance_to(target_center) <= hack_px:
		return [_action_item(base_label, cost, "hack",
			{cost = cost, target_type = target_type, target_pos = target_center}, remaining)]

	return [{
		label = base_label + " (out of range)", cost_str = "%.1f s" % cost,
		enabled = false, action_type = "hack", data = {},
	}]

# ---------------------------------------------------------------------------
# Item builder helpers
# ---------------------------------------------------------------------------

func _in_action_range(char_pos: Vector2, target: Vector2, obs_r: float) -> bool:
	return char_pos.distance_to(target) <= obs_r + Pathfinder.CHAR_RADIUS + ACTION_REACH_PX

func _approach_pos(target: Vector2, obs_r: float, char_pos: Vector2) -> Vector2:
	var dir := char_pos - target
	if dir.length_squared() < 0.01:
		dir = Vector2(0.0, 1.0)
	return target + dir.normalized() * (obs_r + Pathfinder.CHAR_RADIUS + 2.0)

func _path_to(pos: Vector2, sel: PlayerCharacter, exclude_guard_id: int = -1) -> Dictionary:
	var raw := Pathfinder.compute(
		sel.logical_pos, pos,
		_build_circles_for(sel, exclude_guard_id),
		_map.get_wall_segments())
	if raw.is_empty():
		return {}
	var path := PathSmoother.smooth(raw)
	return {path = path, cost = path.time_cost(sel.stat_agi, sel.effective_weight())}

func _action_item(
		label: String, cost: float, atype: String,
		data: Dictionary, remaining: float) -> Dictionary:
	return {
		label = label, cost_str = "%.1f s" % cost,
		enabled = cost <= remaining + 0.001,
		action_type = atype, data = data,
	}

func _compound_item(
		label: String, move_res: Dictionary, action_cost: float,
		atype: String, extra: Dictionary, remaining: float) -> Dictionary:
	var total: float = (move_res.cost as float) + action_cost
	var data := extra.duplicate()
	data["path"]        = move_res.path
	data["move_cost"]   = move_res.cost
	data["action_cost"] = action_cost
	data["cost"]        = total
	return {
		label = label, cost_str = "%.1f + %.1f s" % [move_res.cost, action_cost],
		enabled = total <= remaining + 0.001,
		action_type = atype, data = data,
	}

func _build_circles_for(exclude_player: PlayerCharacter, exclude_guard_id: int = -1) -> Array:
	var circles: Array = []
	circles.append(_map.get_chest_obstacle())
	for ch in _characters:
		if ch != exclude_player:
			circles.append({center = ch.logical_pos, radius = PlayerCharacter.CHAR_RADIUS})
	for g in _guards:
		if not g.is_neutralized and g.guard_id != exclude_guard_id:
			circles.append({center = g.global_position, radius = Guard.GUARD_RADIUS})
	return circles

func _show_preview_for_items(items: Array) -> void:
	for item in items:
		if not item.get("enabled", false):
			continue
		var atype: String = item.get("action_type", "")
		if atype in ["move", "move_pick_lock", "move_pickup", "move_takedown", "move_hold_hostage"]:
			var path: MovePath = item["data"].get("path")
			if path:
				_path_preview.set_path(path, _selected_char()._class_color())
				return
	_path_preview.clear()

# ---------------------------------------------------------------------------
# Action execution
# ---------------------------------------------------------------------------

func _on_action_selected(action_type: String, data: Dictionary) -> void:
	var sel := _selected_char()

	match action_type:
		"move":
			var path: MovePath = data.get("path")
			if path == null:
				return
			var action          := ActionMove.new()
			action.character_id  = sel.character_id
			action.cost          = data.get("cost", 0.0)
			action.path          = path
			sel.queue_action(action)

		"pick_lock":
			var action           := ActionPickLock.new()
			action.character_id   = sel.character_id
			action.cost           = data.get("cost", 0.0)
			action.lock_level     = 1
			action.lock_type      = "glass"
			sel.queue_action(action)

		"pickup":
			var action            := ActionPickUp.new()
			action.character_id    = sel.character_id
			action.cost            = data.get("cost", 0.0)
			action.item_kg         = data.get("item_kg", 0.0)
			action.item_value      = data.get("item_value", 0.0)
			sel.queue_action(action)

		"hack":
			var action             := ActionHack.new()
			action.character_id     = sel.character_id
			action.cost             = data.get("cost", 0.0)
			action.target_type      = data.get("target_type", "door")
			action.target_pos       = data.get("target_pos", Vector2.ZERO)
			sel.queue_action(action)
			if action.target_type == "cctv":
				_recompute_cctv_hacks()

		"takedown":
			var action           := ActionTakedown.new()
			action.character_id   = sel.character_id
			action.cost           = data.get("cost", 0.0)
			action.enemy_type     = data.get("enemy_type", "guard")
			action.target_id      = data.get("guard_id", -1)
			sel.queue_action(action)
			_recompute_guard_neutralizations()

		"hold_hostage":
			var action            := ActionHoldHostage.new()
			action.character_id    = sel.character_id
			action.cost            = data.get("cost", 0.0)
			action.hold_duration   = data.get("hold_duration", 5.0)
			action.target_id       = data.get("guard_id", -1)
			sel.queue_action(action)

		"move_pick_lock":
			var path: MovePath = data.get("path")
			if path == null:
				return
			var move             := ActionMove.new()
			move.character_id     = sel.character_id
			move.cost             = data.get("move_cost", 0.0)
			move.path             = path
			var lock             := ActionPickLock.new()
			lock.character_id     = sel.character_id
			lock.cost             = data.get("action_cost", 0.0)
			lock.lock_level       = 1
			lock.lock_type        = "glass"
			sel.queue_actions([move, lock])

		"move_pickup":
			var path: MovePath = data.get("path")
			if path == null:
				return
			var move             := ActionMove.new()
			move.character_id     = sel.character_id
			move.cost             = data.get("move_cost", 0.0)
			move.path             = path
			var pickup           := ActionPickUp.new()
			pickup.character_id   = sel.character_id
			pickup.cost           = data.get("action_cost", 0.0)
			pickup.item_kg        = data.get("item_kg", 0.0)
			pickup.item_value     = data.get("item_value", 0.0)
			sel.queue_actions([move, pickup])

		"move_takedown":
			var path: MovePath = data.get("path")
			if path == null:
				return
			var move             := ActionMove.new()
			move.character_id     = sel.character_id
			move.cost             = data.get("move_cost", 0.0)
			move.path             = path
			var action           := ActionTakedown.new()
			action.character_id   = sel.character_id
			action.cost           = data.get("action_cost", 0.0)
			action.enemy_type     = data.get("enemy_type", "guard")
			action.target_id      = data.get("guard_id", -1)
			sel.queue_actions([move, action])
			_recompute_guard_neutralizations()

		"move_hold_hostage":
			var path: MovePath = data.get("path")
			if path == null:
				return
			var move             := ActionMove.new()
			move.character_id     = sel.character_id
			move.cost             = data.get("move_cost", 0.0)
			move.path             = path
			var action           := ActionHoldHostage.new()
			action.character_id   = sel.character_id
			action.cost           = data.get("action_cost", 0.0)
			action.hold_duration  = data.get("hold_duration", 5.0)
			action.target_id      = data.get("guard_id", -1)
			sel.queue_actions([move, action])

	_hud.update_selected_character(sel)

func _on_menu_closed() -> void:
	_path_preview.clear()

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func _selected_char() -> PlayerCharacter:
	return _characters[_selected_index]

func _select(index: int) -> void:
	_characters[_selected_index].deselect()
	_selected_index = index
	_characters[_selected_index].select()
	_hud.update_selected_character(_characters[_selected_index])

func _cycle_selection() -> void:
	_select((_selected_index + 1) % _characters.size())
