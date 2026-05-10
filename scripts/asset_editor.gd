extends Node

# F6 Asset Editor — runtime tool for authoring collision (red) and recognition
# (yellow) polygons on PNG sprites. Personal use only, debug/editor-only.
# Phase 2: full editor UI with PNG load, drawing tools, polygon list, zoom.

const PreviewScript := preload("res://scripts/asset_editor_preview.gd")

# Always-visible shortcut help table (panel rendered in Phase 4).
const SHORTCUTS := [
	{"category": "Tools",   "key": "1",            "desc": "Red Pen (collision)"},
	{"category": "Tools",   "key": "2",            "desc": "Yellow Pen (recognition)"},
	{"category": "Tools",   "key": "3",            "desc": "Eraser"},
	{"category": "Drawing", "key": "Left Click",   "desc": "Place vertex / erase polygon"},
	{"category": "Drawing", "key": "Double-click", "desc": "Close polygon"},
	{"category": "Drawing", "key": "Enter",        "desc": "Close polygon"},
	{"category": "Drawing", "key": "Esc",          "desc": "Cancel current polygon"},
	{"category": "View",    "key": "Mouse Wheel",  "desc": "Adjust zoom"},
	{"category": "Mode",    "key": "F6",           "desc": "Toggle Asset Editor"},
]

const TOOL_NONE := 0
const TOOL_RED := 1
const TOOL_YELLOW := 2
const TOOL_ERASER := 3

const ZOOM_MIN := 1.0
const ZOOM_MAX := 16.0
const ZOOM_STEP := 0.5
const ZOOM_DEFAULT := 4.0

var active: bool = false
var _dirty: bool = false

# Editor data
var _texture: Texture2D = null
var _texture_filename: String = ""
var _polygons: Array = []  # [{type: "collision"|"recognition", vertices: PackedVector2Array}]
var _in_progress: PackedVector2Array = PackedVector2Array()
var _current_tool: int = TOOL_NONE
var _highlighted_index: int = -1
var _zoom: float = ZOOM_DEFAULT

# UI references
var _ui_layer: CanvasLayer = null
var _root_panel: Control = null
var _preview: Control = null  # PreviewScript instance
var _filename_label: Label = null
var _polygon_list_box: VBoxContainer = null
var _status_cursor: Label = null
var _status_tool: Label = null
var _status_verts: Label = null
var _zoom_slider: HSlider = null
var _zoom_value_label: Label = null
var _tool_buttons: Dictionary = {}  # tool_id -> Button
var _exit_confirm: ConfirmationDialog = null
var _load_dialog: FileDialog = null
var _load_discard_confirm: ConfirmationDialog = null
var _pending_load_path: String = ""


func _ready() -> void:
	set_process(false)
	_build_ui()
	_apply_tool_button_state()


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 110
	add_child(_ui_layer)

	_root_panel = Control.new()
	_root_panel.anchor_right = 1.0
	_root_panel.anchor_bottom = 1.0
	_root_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root_panel.visible = false
	_ui_layer.add_child(_root_panel)

	# Dark backdrop covers everything underneath.
	var backdrop := ColorRect.new()
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.color = Color(0.05, 0.05, 0.07, 0.94)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_panel.add_child(backdrop)

	var root_v := VBoxContainer.new()
	root_v.anchor_right = 1.0
	root_v.anchor_bottom = 1.0
	root_v.add_theme_constant_override("separation", 0)
	_root_panel.add_child(root_v)

	root_v.add_child(_build_top_bar())
	root_v.add_child(_build_middle_row())
	root_v.add_child(_build_status_bar())

	_exit_confirm = ConfirmationDialog.new()
	_exit_confirm.title = "Unsaved borders"
	_exit_confirm.dialog_text = "Discard unsaved borders?"
	_exit_confirm.ok_button_text = "Discard"
	_exit_confirm.confirmed.connect(_on_exit_discard)
	_ui_layer.add_child(_exit_confirm)

	_load_dialog = FileDialog.new()
	_load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.filters = PackedStringArray(["*.png ; PNG image"])
	_load_dialog.size = Vector2i(700, 500)
	_load_dialog.file_selected.connect(_on_png_chosen)
	_ui_layer.add_child(_load_dialog)

	_load_discard_confirm = ConfirmationDialog.new()
	_load_discard_confirm.title = "Discard current borders?"
	_load_discard_confirm.dialog_text = "Loading a new PNG will discard the current polygons. Continue?"
	_load_discard_confirm.ok_button_text = "Discard"
	_load_discard_confirm.confirmed.connect(_on_load_discard_confirmed)
	_ui_layer.add_child(_load_discard_confirm)


func _build_top_bar() -> Control:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(0, 36)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	bar.add_child(margin)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	margin.add_child(h)

	var load_btn := Button.new()
	load_btn.text = "Load PNG..."
	load_btn.pressed.connect(_on_load_png_pressed)
	h.add_child(load_btn)

	_filename_label = Label.new()
	_filename_label.text = "(no file)"
	_filename_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filename_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	h.add_child(_filename_label)

	var title := Label.new()
	title.text = "Asset Editor (F6)"
	title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	h.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close_pressed)
	h.add_child(close_btn)

	return bar


func _build_middle_row() -> Control:
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 0)

	h.add_child(_build_left_toolbar())
	h.add_child(_build_preview())
	h.add_child(_build_right_panel())
	return h


func _build_left_toolbar() -> Control:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(80, 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	bar.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)

	_tool_buttons[TOOL_RED] = _add_tool_button(v, "Red Pen", "Collision (1)", TOOL_RED, PreviewScript.COLOR_COLLISION)
	_tool_buttons[TOOL_YELLOW] = _add_tool_button(v, "Yellow Pen", "Recognition (2)", TOOL_YELLOW, PreviewScript.COLOR_RECOGNITION)
	_tool_buttons[TOOL_ERASER] = _add_tool_button(v, "Eraser", "Erase polygon (3)", TOOL_ERASER, Color(0.85, 0.85, 0.9))

	v.add_child(HSeparator.new())

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.tooltip_text = "Cancel current polygon (Esc)"
	cancel_btn.pressed.connect(_cancel_in_progress)
	v.add_child(cancel_btn)

	return bar


func _add_tool_button(parent: Control, label: String, tooltip: String, tool_id: int, swatch: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.tooltip_text = tooltip
	btn.toggle_mode = true
	btn.add_theme_color_override("font_color", swatch)
	btn.pressed.connect(_on_tool_pressed.bind(tool_id))
	parent.add_child(btn)
	return btn


func _build_preview() -> Control:
	_preview = PreviewScript.new()
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.set_zoom(_zoom)
	_preview.vertex_placed.connect(_on_vertex_placed)
	_preview.polygon_close_requested.connect(_close_polygon)
	_preview.eraser_clicked.connect(_on_eraser_clicked)
	_preview.mouse_moved.connect(_on_preview_mouse_moved)
	_preview.zoom_step.connect(_on_zoom_step)
	return _preview


func _build_right_panel() -> Control:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(250, 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	bar.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)

	# Zoom row
	var zoom_header := HBoxContainer.new()
	zoom_header.add_theme_constant_override("separation", 6)
	v.add_child(zoom_header)
	var zoom_lbl := Label.new()
	zoom_lbl.text = "Zoom"
	zoom_header.add_child(zoom_lbl)
	_zoom_value_label = Label.new()
	_zoom_value_label.text = "%.1fx" % _zoom
	_zoom_value_label.add_theme_color_override("font_color", Color(1, 1, 0.4))
	zoom_header.add_child(_zoom_value_label)

	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = ZOOM_MIN
	_zoom_slider.max_value = ZOOM_MAX
	_zoom_slider.step = ZOOM_STEP
	_zoom_slider.value = _zoom
	_zoom_slider.value_changed.connect(_on_zoom_slider_changed)
	v.add_child(_zoom_slider)

	v.add_child(HSeparator.new())

	var poly_header := Label.new()
	poly_header.text = "Polygons"
	poly_header.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	v.add_child(poly_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_polygon_list_box = VBoxContainer.new()
	_polygon_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_polygon_list_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_polygon_list_box)

	return bar


func _build_status_bar() -> Control:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(0, 24)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	bar.add_child(margin)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	margin.add_child(h)

	_status_cursor = Label.new()
	_status_cursor.text = "(--, --)"
	h.add_child(_status_cursor)

	var sep := VSeparator.new()
	h.add_child(sep)

	_status_tool = Label.new()
	_status_tool.text = "Tool: none"
	_status_tool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_status_tool)

	_status_verts = Label.new()
	_status_verts.text = ""
	h.add_child(_status_verts)

	return bar


# ── Tool state ───────────────────────────────────────────────────────────────

func _on_tool_pressed(tool_id: int) -> void:
	if _current_tool == tool_id:
		_set_tool(TOOL_NONE)
	else:
		_set_tool(tool_id)


func _set_tool(tool_id: int) -> void:
	# Switching away from a pen tool while drawing discards the in-progress
	# polygon (matches the "tool change resets your draft" mental model).
	if (_current_tool == TOOL_RED or _current_tool == TOOL_YELLOW) and tool_id != _current_tool:
		_in_progress = PackedVector2Array()
		_preview.set_in_progress(_in_progress)
	_current_tool = tool_id
	_preview.set_current_tool(tool_id)
	_apply_tool_button_state()
	_update_status_bar()


func _apply_tool_button_state() -> void:
	for tid in _tool_buttons.keys():
		var btn: Button = _tool_buttons[tid]
		btn.set_pressed_no_signal(tid == _current_tool)


# ── Polygon operations ───────────────────────────────────────────────────────

func _on_vertex_placed(image_px: Vector2) -> void:
	_in_progress.append(image_px)
	_preview.set_in_progress(_in_progress)
	_update_status_bar()


func _close_polygon() -> void:
	if _in_progress.size() < 3:
		return
	var poly_type := _type_for_tool(_current_tool)
	if poly_type == "":
		return
	_polygons.append({"type": poly_type, "vertices": PackedVector2Array(_in_progress)})
	_in_progress = PackedVector2Array()
	_preview.set_in_progress(_in_progress)
	_preview.set_polygons(_polygons)
	_refresh_polygon_list()
	_mark_dirty()
	_update_status_bar()


func _cancel_in_progress() -> void:
	if _in_progress.is_empty():
		return
	_in_progress = PackedVector2Array()
	_preview.set_in_progress(_in_progress)
	_update_status_bar()


func _on_eraser_clicked(image_px: Vector2) -> void:
	# Topmost-first hit test (latest-drawn wins).
	for i in range(_polygons.size() - 1, -1, -1):
		var verts: PackedVector2Array = _polygons[i].get("vertices", PackedVector2Array())
		if verts.size() < 3:
			continue
		if Geometry2D.is_point_in_polygon(image_px, verts):
			_delete_polygon(i)
			return


func _delete_polygon(idx: int) -> void:
	if idx < 0 or idx >= _polygons.size():
		return
	_polygons.remove_at(idx)
	if _highlighted_index == idx:
		_highlighted_index = -1
	elif _highlighted_index > idx:
		_highlighted_index -= 1
	_preview.set_polygons(_polygons)
	_preview.set_highlighted(_highlighted_index)
	_refresh_polygon_list()
	_mark_dirty()


func _highlight_polygon(idx: int) -> void:
	_highlighted_index = (-1 if _highlighted_index == idx else idx)
	_preview.set_highlighted(_highlighted_index)
	_refresh_polygon_list()


func _type_for_tool(tool_id: int) -> String:
	match tool_id:
		TOOL_RED:
			return "collision"
		TOOL_YELLOW:
			return "recognition"
		_:
			return ""


# ── UI updates ──────────────────────────────────────────────────────────────

func _refresh_polygon_list() -> void:
	if _polygon_list_box == null:
		return
	for c in _polygon_list_box.get_children():
		c.queue_free()
	for i in range(_polygons.size()):
		var p: Dictionary = _polygons[i]
		var t: String = p.get("type", "collision")
		var vc: int = (p.get("vertices", PackedVector2Array()) as PackedVector2Array).size()
		var col := PreviewScript.COLOR_RECOGNITION if t == "recognition" else PreviewScript.COLOR_COLLISION
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_polygon_list_box.add_child(row)

		var swatch := ColorRect.new()
		swatch.color = col
		swatch.custom_minimum_size = Vector2(14, 14)
		row.add_child(swatch)

		var sel_btn := Button.new()
		sel_btn.text = "%d  (%dv)" % [i, vc]
		sel_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sel_btn.toggle_mode = true
		sel_btn.button_pressed = (i == _highlighted_index)
		sel_btn.add_theme_font_size_override("font_size", 11)
		sel_btn.pressed.connect(_highlight_polygon.bind(i))
		row.add_child(sel_btn)

		var del_btn := Button.new()
		del_btn.text = "X"
		del_btn.tooltip_text = "Delete polygon"
		del_btn.custom_minimum_size = Vector2(24, 0)
		del_btn.pressed.connect(_delete_polygon.bind(i))
		row.add_child(del_btn)


func _update_status_bar() -> void:
	if _status_tool:
		_status_tool.text = "Tool: %s" % _tool_name(_current_tool)
	if _status_verts:
		_status_verts.text = ("Vertices placed: %d" % _in_progress.size()) if _in_progress.size() > 0 else ""


func _on_preview_mouse_moved(image_px: Vector2, in_image: bool) -> void:
	if _status_cursor == null:
		return
	if in_image:
		_status_cursor.text = "(%d, %d)" % [int(image_px.x), int(image_px.y)]
	else:
		_status_cursor.text = "(--, --)"


func _tool_name(tool_id: int) -> String:
	match tool_id:
		TOOL_RED: return "Red Pen (collision)"
		TOOL_YELLOW: return "Yellow Pen (recognition)"
		TOOL_ERASER: return "Eraser"
		_: return "none"


# ── Zoom ────────────────────────────────────────────────────────────────────

func _on_zoom_slider_changed(v: float) -> void:
	_zoom = v
	_zoom_value_label.text = "%.1fx" % _zoom
	_preview.set_zoom(_zoom)


func _on_zoom_step(direction: int) -> void:
	# Mouse wheel: bump the slider; its value_changed handler updates everything.
	var new_val: float = clampf(_zoom + direction * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	if new_val != _zoom:
		_zoom_slider.value = new_val  # triggers _on_zoom_slider_changed


# ── Load PNG ────────────────────────────────────────────────────────────────

func _on_load_png_pressed() -> void:
	_load_dialog.popup_centered()


func _on_png_chosen(path: String) -> void:
	if _polygons.size() > 0 or _in_progress.size() > 0:
		_pending_load_path = path
		_load_discard_confirm.popup_centered()
		return
	_load_png(path)


func _on_load_discard_confirmed() -> void:
	if _pending_load_path == "":
		return
	var p := _pending_load_path
	_pending_load_path = ""
	_polygons.clear()
	_in_progress = PackedVector2Array()
	_load_png(p)


func _load_png(path: String) -> void:
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		push_error("AssetEditor: failed to load %s (error %d)" % [path, err])
		return
	var tex := ImageTexture.create_from_image(img)
	_texture = tex
	_texture_filename = path.get_file()
	_filename_label.text = _texture_filename
	_polygons.clear()
	_in_progress = PackedVector2Array()
	_highlighted_index = -1
	_preview.set_texture(tex)
	_preview.set_polygons(_polygons)
	_preview.set_in_progress(_in_progress)
	_preview.set_highlighted(_highlighted_index)
	_refresh_polygon_list()
	_update_status_bar()


# ── Mode lifecycle ──────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F6:
			_toggle()
			get_viewport().set_input_as_handled()
			return
		if not active:
			# F4 / F5 fall through; Esc is the game-quit (handled in EditMode).
			return
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_F4 or event.keycode == KEY_F5:
			# When active, swallow Esc/F4/F5 only after we react.
			if event.keycode == KEY_ESCAPE:
				_cancel_in_progress()
				get_viewport().set_input_as_handled()
				return
			# F4/F5 fall through so those modes can take over via their own handlers.
			return
		match event.keycode:
			KEY_1:
				_set_tool(TOOL_RED)
				get_viewport().set_input_as_handled()
			KEY_2:
				_set_tool(TOOL_YELLOW)
				get_viewport().set_input_as_handled()
			KEY_3:
				_set_tool(TOOL_ERASER)
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				if _in_progress.size() >= 3:
					_close_polygon()
				get_viewport().set_input_as_handled()


func _mark_dirty() -> void:
	if not _dirty:
		_dirty = true


func _toggle() -> void:
	if active:
		if _dirty:
			_exit_confirm.popup_centered()
			return
		_force_deactivate()
		return
	# Activating: turn off siblings first, then show panel.
	# Cross-mode activation skips the dirty prompt — switching modes silently
	# discards sibling unsaved work. The prompt only fires when the user
	# explicitly toggles this mode off (F6 again or Close button).
	active = true
	for sibling_name in ["EditMode", "LightMode"]:
		var s := get_node_or_null("../%s" % sibling_name)
		if s and s.get("active"):
			if s.has_method("_force_deactivate"):
				s.call("_force_deactivate")
			else:
				s.call("_toggle")
	set_process(true)
	if _root_panel:
		_root_panel.visible = true


func _force_deactivate() -> void:
	if not active:
		return
	active = false
	_dirty = false
	set_process(false)
	if _root_panel:
		_root_panel.visible = false


func _on_close_pressed() -> void:
	_toggle()


func _on_exit_discard() -> void:
	# Throw away unsaved polygons (and any in-progress draft). Keep the loaded
	# texture so re-opening F6 doesn't lose the file the user picked.
	_polygons.clear()
	_in_progress = PackedVector2Array()
	_highlighted_index = -1
	if _preview:
		_preview.set_polygons(_polygons)
		_preview.set_in_progress(_in_progress)
		_preview.set_highlighted(_highlighted_index)
	_refresh_polygon_list()
	_update_status_bar()
	_force_deactivate()
