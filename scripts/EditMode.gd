extends Node2D

@export var iso_angle_deg: float = 30.0
@export var grid_size: int = 64
@export var grid_label_step: int = 4
@export var grid_color: Color = Color(1, 1, 1, 0.16)
@export var grid_label_color: Color = Color(1, 1, 1, 0.7)
@export var cursor_coord_color: Color = Color(1, 1, 0.3, 0.95)
@export var x_axis_color: Color = Color(1, 0.35, 0.35, 0.9)
@export var y_axis_color: Color = Color(0.35, 1, 0.45, 0.9)
@export var z_axis_color: Color = Color(0.45, 0.7, 1.0, 0.9)
@export var z_axis_height: float = 1024.0
@export var selection_color: Color = Color(0.2, 1, 0.4, 0.95)
@export var handle_fill_color: Color = Color(1, 1, 1, 1)
@export var handle_size_px: float = 6.0
@export var handle_hit_size_px: float = 9.0
@export var copy_offset: Vector2 = Vector2(32, 32)
@export var max_undo: int = 256

var active: bool = false
var selected: Node2D = null
var multi_selected: Array[Node2D] = []

var mode: String = "idle"  # "idle" | "drag" | "scale"

# Drag state
var drag_offset: Vector2 = Vector2.ZERO
var drag_started_pos: Vector2 = Vector2.ZERO
var _drag_starts: Dictionary = {}
var _drag_mouse_start: Vector2 = Vector2.ZERO

# Scale state
var scale_anchor_world: Vector2 = Vector2.ZERO
var scale_grabbed_dir: Vector2 = Vector2.ONE
var scale_initial_distance: float = 1.0
var scale_initial_node_scale: Vector2 = Vector2.ONE
var scale_initial_node_position: Vector2 = Vector2.ZERO
var _scale_starts: Dictionary = {}

var undo_stack: Array = []

# Dirty tracking. _clean_undo_size is the size of undo_stack at the last save
# (or at F4 enter). Anything pushed beyond that is unsaved work.
var _dirty: bool = false
var _clean_undo_size: int = 0
var _suppress_dirty: bool = false  # set during Discard so undo doesn't re-mark dirty

var _ui_layer: CanvasLayer = null
var _ui_panel: PanelContainer = null
var _ui_list: VBoxContainer = null
var _save_path_label: Label = null
var _title_label: Label = null
var _save_dialog: FileDialog = null
var _exit_confirm: ConfirmationDialog = null


func _ready() -> void:
	z_index = 4096
	set_process(false)
	_build_ui()
	queue_redraw()


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 100
	add_child(_ui_layer)

	_ui_panel = PanelContainer.new()
	_ui_panel.position = Vector2(8, 8)
	_ui_panel.custom_minimum_size = Vector2(180, 0)
	_ui_panel.visible = false
	_ui_layer.add_child(_ui_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_ui_panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	margin.add_child(v)

	_title_label = Label.new()
	_title_label.text = "Objects (F4)"
	_title_label.add_theme_font_size_override("font_size", 12)
	v.add_child(_title_label)

	var sep := HSeparator.new()
	v.add_child(sep)

	_ui_list = VBoxContainer.new()
	_ui_list.add_theme_constant_override("separation", 2)
	v.add_child(_ui_list)

	v.add_child(HSeparator.new())

	var mirror_btn := Button.new()
	mirror_btn.text = "Mirror (flip horizontal)"
	mirror_btn.add_theme_font_size_override("font_size", 11)
	mirror_btn.tooltip_text = "Flip selected object horizontally (M)"
	mirror_btn.pressed.connect(_mirror_selected)
	v.add_child(mirror_btn)

	v.add_child(HSeparator.new())

	_save_path_label = Label.new()
	_save_path_label.add_theme_font_size_override("font_size", 10)
	_save_path_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_save_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_save_path_label)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 4)
	v.add_child(save_row)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.tooltip_text = "Save to current path"
	save_btn.add_theme_font_size_override("font_size", 11)
	save_btn.pressed.connect(_on_save_pressed)
	save_row.add_child(save_btn)
	var save_as_btn := Button.new()
	save_as_btn.text = "Save As..."
	save_as_btn.tooltip_text = "Pick a new path and save"
	save_as_btn.add_theme_font_size_override("font_size", 11)
	save_as_btn.pressed.connect(_on_save_as_pressed)
	save_row.add_child(save_as_btn)

	_save_dialog = FileDialog.new()
	_save_dialog.access = FileDialog.ACCESS_USERDATA
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.filters = PackedStringArray(["*.json ; JSON edits"])
	_save_dialog.size = Vector2i(600, 420)
	_save_dialog.file_selected.connect(_on_save_path_chosen)
	_ui_layer.add_child(_save_dialog)

	_exit_confirm = ConfirmationDialog.new()
	_exit_confirm.title = "Unsaved map changes"
	_exit_confirm.dialog_text = "Discard unsaved map changes?"
	_exit_confirm.ok_button_text = "Discard"
	_exit_confirm.add_button("Save", true, "save_and_close")
	_exit_confirm.confirmed.connect(_on_exit_discard)
	_exit_confirm.custom_action.connect(_on_exit_custom_action)
	_ui_layer.add_child(_exit_confirm)

	_update_save_path_label()
	_update_dirty_indicator()


func _mirror_selected() -> void:
	if multi_selected.size() == 0:
		return
	for n in multi_selected:
		if is_instance_valid(n):
			_push_undo({
				"action": "transform",
				"node": n,
				"position": n.global_position,
				"scale": n.scale,
			})
			n.scale.x = -n.scale.x
	_persist()
	queue_redraw()


func _refresh_object_list() -> void:
	if _ui_list == null:
		return
	for c in _ui_list.get_children():
		c.queue_free()
	for n in get_tree().get_nodes_in_group("editable"):
		if not (n is Node2D):
			continue
		var btn := Button.new()
		btn.text = str(n.name)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.toggle_mode = true
		btn.button_pressed = (n in multi_selected)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_object_button_pressed.bind(n))
		_ui_list.add_child(btn)


func _on_object_button_pressed(node: Node2D) -> void:
	if not is_instance_valid(node):
		_refresh_object_list()
		return
	if Input.is_key_pressed(KEY_SHIFT):
		if node in multi_selected:
			multi_selected.erase(node)
			if selected == node:
				selected = multi_selected[multi_selected.size() - 1] if multi_selected.size() > 0 else null
		else:
			multi_selected.append(node)
			selected = node
	else:
		multi_selected = [node]
		selected = node
	mode = "idle"
	_refresh_object_list()
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F4:
			_toggle()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F5 or event.keycode == KEY_F6:
			return

	if not active:
		return

	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_Z and event.ctrl_pressed:
				_undo()
			elif event.keycode == KEY_DELETE and selected:
				_delete_selected()
			elif event.keycode == KEY_C and selected and not event.ctrl_pressed:
				_copy_selected()
			elif event.keycode == KEY_M and selected and not event.ctrl_pressed:
				_mirror_selected()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var pos := get_global_mouse_position()
				var handle_idx := _handle_at(pos)
				if handle_idx >= 0 and selected:
					_start_scale(handle_idx)
				elif selected and _hit_test(selected, pos):
					_start_drag(pos)
				else:
					_select_at(pos)
					_refresh_object_list()
					if selected:
						_start_drag(pos)
			else:
				_end_action()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if mode == "drag" and selected:
			var delta := get_global_mouse_position() - _drag_mouse_start
			for n in _drag_starts:
				if is_instance_valid(n):
					(n as Node2D).global_position = _drag_starts[n] + delta
		elif mode == "scale" and selected:
			_apply_scale_drag(get_global_mouse_position())
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	if active:
		# Trying to deactivate. If dirty, intercept and prompt; otherwise close.
		if _dirty:
			_exit_confirm.popup_centered()
			return
		_force_deactivate()
		return
	# Activating: turn off siblings, snapshot clean state, show panel.
	# Cross-mode activation skips the dirty prompt — switching modes silently
	# discards sibling unsaved work. The prompt only fires when the user
	# explicitly toggles a mode off (own-key press or Close button).
	active = true
	for sibling_name in ["LightMode", "AssetEditor"]:
		var s := get_node_or_null("../%s" % sibling_name)
		if s and s.get("active"):
			if s.has_method("_force_deactivate"):
				s.call("_force_deactivate")
			else:
				s.call("_toggle")
	_clean_undo_size = undo_stack.size()
	_dirty = false
	set_process(true)
	if _ui_panel:
		_ui_panel.visible = true
	_refresh_object_list()
	_update_dirty_indicator()
	_update_save_path_label()
	queue_redraw()


func _select_at(pos: Vector2) -> void:
	var best: Node2D = null
	var best_score: float = -INF
	for n in get_tree().get_nodes_in_group("editable"):
		if n is Node2D and _hit_test(n, pos):
			var score := float(n.z_index) + float(n.get_index()) * 0.001
			if score >= best_score:
				best_score = score
				best = n
	if best:
		if Input.is_key_pressed(KEY_SHIFT):
			if best in multi_selected:
				multi_selected.erase(best)
				if selected == best:
					selected = multi_selected[multi_selected.size() - 1] if multi_selected.size() > 0 else null
			else:
				multi_selected.append(best)
				selected = best
		else:
			multi_selected = [best]
			selected = best
	else:
		if not Input.is_key_pressed(KEY_SHIFT):
			multi_selected.clear()
			selected = null


func _hit_test(node: Node2D, pos: Vector2) -> bool:
	var bounds = _world_bounds(node)
	if bounds == null:
		return false
	return (bounds as Rect2).has_point(pos)


func _world_bounds(node: Node2D):
	if node is Sprite2D and node.texture:
		var spr := node as Sprite2D
		var size: Vector2 = spr.texture.get_size() * spr.global_scale.abs()
		var origin: Vector2
		if spr.centered:
			origin = spr.global_position - size * 0.5
		else:
			origin = spr.global_position
		origin += spr.offset * spr.global_scale
		return Rect2(origin, size)
	return null


func _bounds_corners(b: Rect2) -> Array:
	return [
		b.position,
		Vector2(b.end.x, b.position.y),
		b.end,
		Vector2(b.position.x, b.end.y),
	]


func _current_zoom() -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam:
		return cam.zoom
	return Vector2.ONE


func _handle_at(pos: Vector2) -> int:
	if selected == null:
		return -1
	var bounds = _world_bounds(selected)
	if bounds == null:
		return -1
	var zx := maxf(_current_zoom().x, 0.0001)
	var hsize := handle_hit_size_px / zx
	var corners := _bounds_corners(bounds as Rect2)
	for i in range(4):
		var r := Rect2(corners[i] - Vector2(hsize, hsize), Vector2(hsize * 2.0, hsize * 2.0))
		if r.has_point(pos):
			return i
	return -1


func _start_drag(pos: Vector2) -> void:
	mode = "drag"
	drag_offset = selected.global_position - pos
	drag_started_pos = selected.global_position
	_drag_mouse_start = pos
	_drag_starts.clear()
	for n in multi_selected:
		if is_instance_valid(n):
			_drag_starts[n] = n.global_position


func _start_scale(handle_idx: int) -> void:
	mode = "scale"
	var bounds := _world_bounds(selected) as Rect2
	var corners := _bounds_corners(bounds)
	var grabbed: Vector2 = corners[handle_idx]
	var anchor: Vector2 = corners[(handle_idx + 2) % 4]
	scale_anchor_world = anchor
	var dir := grabbed - anchor
	scale_grabbed_dir = Vector2(signf(dir.x), signf(dir.y))
	if scale_grabbed_dir.x == 0.0:
		scale_grabbed_dir.x = 1.0
	if scale_grabbed_dir.y == 0.0:
		scale_grabbed_dir.y = 1.0
	scale_initial_distance = maxf(dir.length(), 0.0001)
	scale_initial_node_scale = selected.scale
	scale_initial_node_position = selected.global_position
	_scale_starts.clear()
	for n in multi_selected:
		if is_instance_valid(n):
			_scale_starts[n] = n.scale
			_push_undo({
				"action": "transform",
				"node": n,
				"position": n.global_position,
				"scale": n.scale,
			})


func _apply_scale_drag(mouse_world: Vector2) -> void:
	var delta := mouse_world - scale_anchor_world
	var factor := delta.length() / scale_initial_distance
	factor = maxf(factor, 0.01)
	var new_scale := scale_initial_node_scale * factor
	selected.scale = new_scale
	if selected is Sprite2D and (selected as Sprite2D).texture:
		var spr := selected as Sprite2D
		var sz: Vector2 = spr.texture.get_size() * Vector2(absf(new_scale.x), absf(new_scale.y))
		if spr.centered:
			selected.global_position = scale_anchor_world + scale_grabbed_dir * sz * 0.5
	for n in multi_selected:
		if n != selected and is_instance_valid(n) and _scale_starts.has(n):
			n.scale = (_scale_starts[n] as Vector2) * factor


func _end_action() -> void:
	if mode == "drag":
		var any_moved: bool = false
		for n in _drag_starts:
			if is_instance_valid(n) and (n as Node2D).global_position != _drag_starts[n]:
				_push_undo({
					"action": "transform",
					"node": n,
					"position": _drag_starts[n],
					"scale": (n as Node2D).scale,
				})
				any_moved = true
		if any_moved:
			_persist()
	elif mode == "scale":
		if selected:
			_persist()
	mode = "idle"
	_drag_starts.clear()


func _push_undo(entry: Dictionary) -> void:
	undo_stack.push_back(entry)
	while undo_stack.size() > max_undo:
		undo_stack.pop_front()


func _undo() -> void:
	if undo_stack.is_empty():
		return
	var e: Dictionary = undo_stack.pop_back()
	match e.get("action"):
		"transform":
			var n: Node2D = e["node"]
			if is_instance_valid(n):
				n.global_position = e["position"]
				n.scale = e["scale"]
				selected = n
		"delete":
			var n: Node2D = e["node"]
			var parent: Node = e["parent"]
			if is_instance_valid(parent) and is_instance_valid(n):
				parent.add_child(n)
				if not n.is_in_group("editable"):
					n.add_to_group("editable")
				selected = n
		"create":
			var n: Node2D = e["node"]
			if is_instance_valid(n):
				if n.get_parent():
					n.get_parent().remove_child(n)
				n.queue_free()
				selected = null
	_persist()
	_refresh_object_list()


func _delete_selected() -> void:
	if multi_selected.size() == 0:
		return
	for n in multi_selected:
		if is_instance_valid(n):
			var parent := n.get_parent()
			if parent != null:
				parent.remove_child(n)
				_push_undo({"action": "delete", "node": n, "parent": parent})
	multi_selected.clear()
	selected = null
	_persist()
	_refresh_object_list()


func _copy_selected() -> void:
	if multi_selected.size() == 0:
		return
	var new_dups: Array[Node2D] = []
	for n in multi_selected:
		if is_instance_valid(n):
			var dup: Node = n.duplicate()
			n.get_parent().add_child(dup)
			if not dup.is_in_group("editable"):
				dup.add_to_group("editable")
			if dup is Node2D:
				(dup as Node2D).global_position = n.global_position + copy_offset
				new_dups.append(dup as Node2D)
			_push_undo({"action": "create", "node": dup})
	if new_dups.size() > 0:
		multi_selected = new_dups
		selected = new_dups[new_dups.size() - 1]
	_persist()
	_refresh_object_list()


func _persist() -> void:
	# Edits are now batched: mark dirty, write only on explicit Save / Save As.
	_mark_dirty()


func _mark_dirty() -> void:
	if _suppress_dirty:
		return
	if not _dirty:
		_dirty = true
		_update_dirty_indicator()


func _update_dirty_indicator() -> void:
	if _title_label:
		_title_label.text = "Objects (F4)%s" % ("  *" if _dirty else "")


func _update_save_path_label() -> void:
	if _save_path_label == null:
		return
	var owner_node := get_owner()
	var path := ""
	if owner_node and "current_edits_path" in owner_node:
		path = str(owner_node.get("current_edits_path"))
	_save_path_label.text = "Saving to: %s" % (path if path != "" else "(none)")


func _on_save_pressed() -> void:
	_save_to_current_path()


func _save_to_current_path() -> bool:
	var owner_node := get_owner()
	if owner_node == null or not owner_node.has_method("save_edits"):
		push_warning("EditMode: owner has no save_edits() — cannot persist")
		return false
	var err: String = owner_node.call("save_edits")
	if err != "":
		push_error("EditMode save failed: %s" % err)
		return false
	_clean_undo_size = undo_stack.size()
	_dirty = false
	_update_dirty_indicator()
	_update_save_path_label()
	return true


func _on_save_as_pressed() -> void:
	var owner_node := get_owner()
	if owner_node and "current_edits_path" in owner_node:
		var current := str(owner_node.get("current_edits_path"))
		if current.begins_with("user://"):
			_save_dialog.current_file = current.substr("user://".length())
	_save_dialog.popup_centered()


func _on_save_path_chosen(path: String) -> void:
	var owner_node := get_owner()
	if owner_node == null or not owner_node.has_method("save_edits_to"):
		return
	var err: String = owner_node.call("save_edits_to", path)
	if err != "":
		push_error("EditMode Save As failed: %s" % err)
		return
	_clean_undo_size = undo_stack.size()
	_dirty = false
	_update_dirty_indicator()
	_update_save_path_label()


func _discard_changes() -> void:
	_suppress_dirty = true
	while undo_stack.size() > _clean_undo_size:
		_undo()
	_suppress_dirty = false
	_dirty = false
	_update_dirty_indicator()
	_refresh_object_list()
	queue_redraw()


func _on_exit_discard() -> void:
	# ConfirmationDialog's "OK" button = Discard
	_discard_changes()
	_force_deactivate()


func _on_exit_custom_action(action: StringName) -> void:
	if action == &"save_and_close":
		if _save_to_current_path():
			_exit_confirm.hide()
			_force_deactivate()


func _force_deactivate() -> void:
	# Bypass the dirty check that _toggle() would re-trigger.
	if not active:
		return
	active = false
	selected = null
	multi_selected.clear()
	mode = "idle"
	set_process(false)
	if _ui_panel:
		_ui_panel.visible = false
	queue_redraw()


func _iso_basis() -> Vector2:
	return Vector2(cos(deg_to_rad(iso_angle_deg)), sin(deg_to_rad(iso_angle_deg)))


func iso_project(p: Vector3) -> Vector2:
	var b := _iso_basis()
	return Vector2((p.x + p.y) * b.x, (p.x - p.y) * b.y - p.z)


func iso_unproject_ground(screen: Vector2) -> Vector2:
	var b := _iso_basis()
	var u := screen.x / b.x
	var v := screen.y / b.y
	return Vector2((u + v) * 0.5, (u - v) * 0.5)


func _draw() -> void:
	if not active:
		return
	var rect := get_viewport_rect()
	var cam := get_viewport().get_camera_2d()
	var view_size: Vector2 = rect.size
	var view_zoom: Vector2 = Vector2.ONE
	var view_center: Vector2 = view_size * 0.5
	if cam:
		view_zoom = cam.zoom
		view_center = cam.get_screen_center_position()
	var half: Vector2 = view_size * 0.5 / view_zoom
	var top_left: Vector2 = view_center - half
	var bottom_right: Vector2 = view_center + half

	var line_w: float = 1.0 / view_zoom.x

	var corners := [
		top_left,
		Vector2(bottom_right.x, top_left.y),
		bottom_right,
		Vector2(top_left.x, bottom_right.y),
	]
	var x_min: float = INF
	var x_max: float = -INF
	var y_min: float = INF
	var y_max: float = -INF
	for cnr in corners:
		var w := iso_unproject_ground(cnr)
		x_min = minf(x_min, w.x)
		x_max = maxf(x_max, w.x)
		y_min = minf(y_min, w.y)
		y_max = maxf(y_max, w.y)
	x_min -= float(grid_size)
	x_max += float(grid_size)
	y_min -= float(grid_size)
	y_max += float(grid_size)

	var y: float = floor(y_min / float(grid_size)) * float(grid_size)
	while y <= y_max:
		var is_axis: bool = absf(y) < 0.5
		var col: Color = x_axis_color if is_axis else grid_color
		var w: float = (2.0 if is_axis else 1.0) * line_w
		var p1 := iso_project(Vector3(x_min, y, 0))
		var p2 := iso_project(Vector3(x_max, y, 0))
		draw_line(p1, p2, col, w)
		y += float(grid_size)

	var x: float = floor(x_min / float(grid_size)) * float(grid_size)
	while x <= x_max:
		var is_axis: bool = absf(x) < 0.5
		var col: Color = y_axis_color if is_axis else grid_color
		var w: float = (2.0 if is_axis else 1.0) * line_w
		var p1 := iso_project(Vector3(x, y_min, 0))
		var p2 := iso_project(Vector3(x, y_max, 0))
		draw_line(p1, p2, col, w)
		x += float(grid_size)

	var z_top := iso_project(Vector3(0, 0, z_axis_height))
	var z_bot := iso_project(Vector3(0, 0, -z_axis_height * 0.05))
	draw_line(z_bot, z_top, z_axis_color, 2.0 * line_w)

	var font := ThemeDB.fallback_font
	var font_size: int = max(8, int(12.0 / view_zoom.x))
	var pad: float = 3.0 / view_zoom.x

	var label_step: float = float(grid_size * max(1, grid_label_step))
	var lx: float = ceil(x_min / label_step) * label_step
	while lx <= x_max:
		var ly: float = ceil(y_min / label_step) * label_step
		while ly <= y_max:
			var sp := iso_project(Vector3(lx, ly, 0))
			draw_string(
				font,
				sp + Vector2(pad, font_size),
				"%d, %d" % [int(lx), int(ly)],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				grid_label_color,
			)
			ly += label_step
		lx += label_step

	draw_string(font, iso_project(Vector3(x_max - float(grid_size), 0, 0)) + Vector2(pad, font_size), "X+", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, x_axis_color)
	draw_string(font, iso_project(Vector3(0, y_max - float(grid_size), 0)) + Vector2(pad, font_size), "Y+", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, y_axis_color)
	draw_string(font, z_top + Vector2(pad, -pad), "Z+", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, z_axis_color)

	for n in multi_selected:
		if is_instance_valid(n) and n != selected:
			var b2 = _world_bounds(n)
			if b2 != null:
				draw_rect(b2 as Rect2, selection_color, false, 2.0 * line_w)

	if selected and is_instance_valid(selected):
		var bounds = _world_bounds(selected)
		if bounds != null:
			var b: Rect2 = bounds
			draw_rect(b, selection_color, false, 2.0 * line_w)
			var hsize := handle_size_px / view_zoom.x
			for c in _bounds_corners(b):
				var hr := Rect2(c - Vector2(hsize, hsize), Vector2(hsize * 2.0, hsize * 2.0))
				draw_rect(hr, handle_fill_color, true)
				draw_rect(hr, selection_color, false, 1.5 * line_w)

	var mouse_pos := get_global_mouse_position()
	var ground := iso_unproject_ground(mouse_pos)
	var coord_text := "(%d, %d, 0)" % [int(ground.x), int(ground.y)]
	var coord_offset := Vector2(14.0, -6.0) / view_zoom.x
	var text_pos := mouse_pos + coord_offset
	var text_size: Vector2 = font.get_string_size(coord_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var bg_rect := Rect2(text_pos + Vector2(-pad, -text_size.y), text_size + Vector2(pad * 2.0, pad))
	draw_rect(bg_rect, Color(0, 0, 0, 0.55), true)
	draw_string(font, text_pos, coord_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, cursor_coord_color)
