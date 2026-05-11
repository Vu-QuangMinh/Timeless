extends Node

# F6 Asset Editor — runtime tool for authoring collision (red) and recognition
# (yellow) polygons on PNG sprites. Personal use only, debug/editor-only.
# Phase 3: PNG load, drawing tools, save (Ctrl+S) and load (Ctrl+O) assets.

const PreviewScript := preload("res://scripts/asset_editor_preview.gd")
const SobelNormal := preload("res://scripts/util/sobel_normal.gd")

const PALETTE_ROOT := "res://assets/palette"
const TEMPLATES_ROOT := "res://scripts/templates"
const CATEGORIES := ["Camera", "Enemy", "Wall", "Door", "Lock", "Artifact"]
# Z-priority for hover-disambiguation; read by gameplay later via metadata.
const RECOGNITION_PRIORITY := {
	"Floor": 0,
	"Wall": 10,
	"Door": 20,
	"Lock": 20,
	"Artifact": 30,
	"Camera": 40,
	"Enemy": 50,
}

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
	{"category": "File",    "key": "Ctrl+S",       "desc": "Save asset"},
	{"category": "File",    "key": "Ctrl+O",       "desc": "Load asset"},
	{"category": "Mode",    "key": "F6",           "desc": "Toggle Asset Editor"},
]

const ShortcutPanelBuilder := preload("res://scripts/util/shortcut_panel.gd")

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
var _image: Image = null  # source pixels, kept for save (avoids texture→image round trip)
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

# Save Asset dialog
var _save_dialog: ConfirmationDialog = null
var _save_name_edit: LineEdit = null
var _save_category_btn: OptionButton = null
var _save_sobel_check: CheckBox = null
var _save_error_label: Label = null

# Load Asset dialog
var _asset_browser: ConfirmationDialog = null
var _asset_browser_list: ItemList = null
var _asset_browser_entries: Array = []  # [{category, name, json_path}]


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

	_build_save_dialog()
	_build_asset_browser()


func _build_save_dialog() -> void:
	_save_dialog = ConfirmationDialog.new()
	_save_dialog.title = "Save Asset"
	_save_dialog.ok_button_text = "Save"
	_save_dialog.min_size = Vector2i(360, 200)
	_save_dialog.confirmed.connect(_on_save_dialog_confirmed)
	_ui_layer.add_child(_save_dialog)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_save_dialog.add_child(v)

	var name_lbl := Label.new()
	name_lbl.text = "Asset name (lowercase + underscores)"
	v.add_child(name_lbl)
	_save_name_edit = LineEdit.new()
	_save_name_edit.placeholder_text = "e.g. standard_camera"
	_save_name_edit.text_changed.connect(_on_save_name_changed)
	v.add_child(_save_name_edit)

	var cat_lbl := Label.new()
	cat_lbl.text = "Category"
	v.add_child(cat_lbl)
	_save_category_btn = OptionButton.new()
	for cat in CATEGORIES:
		_save_category_btn.add_item(cat)
	v.add_child(_save_category_btn)

	_save_sobel_check = CheckBox.new()
	_save_sobel_check.text = "Generate normal map (Sobel)"
	_save_sobel_check.button_pressed = true
	v.add_child(_save_sobel_check)

	_save_error_label = Label.new()
	_save_error_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	_save_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_save_error_label)


func _build_asset_browser() -> void:
	_asset_browser = ConfirmationDialog.new()
	_asset_browser.title = "Load Asset"
	_asset_browser.ok_button_text = "Load"
	_asset_browser.min_size = Vector2i(420, 360)
	_asset_browser.confirmed.connect(_on_asset_browser_confirmed)
	_ui_layer.add_child(_asset_browser)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_asset_browser.add_child(v)

	var lbl := Label.new()
	lbl.text = "Assets under res://assets/palette/"
	v.add_child(lbl)

	_asset_browser_list = ItemList.new()
	_asset_browser_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_browser_list.custom_minimum_size = Vector2(380, 280)
	_asset_browser_list.item_activated.connect(_on_asset_browser_item_activated)
	v.add_child(_asset_browser_list)


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

	# Always-visible shortcut help, sits below the polygon list. (F6's UI fully
	# tiles the screen so a floating bottom-right corner conflicts with the
	# status bar; integrating into the right panel keeps it visible without
	# obscuring the preview.)
	v.add_child(HSeparator.new())
	var help := ShortcutPanelBuilder.build("F6 Shortcuts", SHORTCUTS)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(help)

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
	_try_restore_sibling_borders(path)


func _on_load_discard_confirmed() -> void:
	if _pending_load_path == "":
		return
	var p := _pending_load_path
	_pending_load_path = ""
	_polygons.clear()
	_in_progress = PackedVector2Array()
	_load_png(p)
	_try_restore_sibling_borders(p)


# If `png_path` has a sibling <basename>.borders.json (which is what F6 saves
# alongside the PNG), restore the polygons from it. No-op for fresh PNGs.
# Lets "Load PNG..." re-open a saved asset with its polygons intact, not just
# the bare image. Returns true if polygons were restored.
func _try_restore_sibling_borders(png_path: String) -> bool:
	var borders_path := "%s/%s.borders.json" % [png_path.get_base_dir(), png_path.get_file().get_basename()]
	if not FileAccess.file_exists(borders_path):
		return false
	var f := FileAccess.open(borders_path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var raw_polys: Variant = parsed.get("polygons", [])
	if typeof(raw_polys) != TYPE_ARRAY:
		return false
	var loaded: Array = []
	for p in raw_polys:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var verts := PackedVector2Array()
		var raw_verts: Variant = p.get("vertices", [])
		if typeof(raw_verts) == TYPE_ARRAY:
			for pair in raw_verts:
				if typeof(pair) == TYPE_ARRAY and (pair as Array).size() >= 2:
					verts.append(Vector2(float(pair[0]), float(pair[1])))
		loaded.append({"type": p.get("type", "collision"), "vertices": verts})
	if loaded.is_empty():
		return false
	_polygons = loaded
	_preview.set_polygons(_polygons)
	_refresh_polygon_list()
	_set_status_message("Loaded: %s + %d border%s" % [png_path.get_file(), loaded.size(), "" if loaded.size() == 1 else "s"], false)
	return true


func _load_png(path: String) -> void:
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		push_error("AssetEditor: failed to load %s (error %d)" % [path, err])
		return
	var tex := ImageTexture.create_from_image(img)
	_texture = tex
	_image = img
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
			KEY_S:
				if event.ctrl_pressed:
					_open_save_dialog()
					get_viewport().set_input_as_handled()
			KEY_O:
				if event.ctrl_pressed:
					_open_asset_browser()
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


# ── Save Asset ──────────────────────────────────────────────────────────────

func _open_save_dialog() -> void:
	if _image == null:
		_set_status_message("Load a PNG before saving", true)
		return
	if _save_error_label:
		_save_error_label.text = ""
	if _save_name_edit and _save_name_edit.text == "":
		# Suggest a default name based on the loaded filename.
		var stem := _texture_filename.get_basename().to_lower()
		_save_name_edit.text = _sanitize_name(stem)
	_save_dialog.popup_centered()


func _on_save_name_changed(_text: String) -> void:
	if _save_error_label:
		_save_error_label.text = ""


func _on_save_dialog_confirmed() -> void:
	# res:// is read-only in exported builds — F6 is debug/editor-only.
	var asset_name := _save_name_edit.text.strip_edges()
	if not _is_valid_name(asset_name):
		_save_error_label.text = "Name must be lowercase letters/digits/underscores, non-empty."
		_save_dialog.popup_centered()
		return
	var category: String = CATEGORIES[_save_category_btn.selected]
	var with_normal: bool = _save_sobel_check.button_pressed
	var err := _save_asset(asset_name, category, with_normal)
	if err != "":
		_save_error_label.text = err
		_save_dialog.popup_centered()
		return
	_dirty = false
	_set_status_message("Saved: %s/%s" % [category, asset_name], false)


func _save_asset(asset_name: String, category: String, with_normal: bool) -> String:
	if _image == null:
		return "No image loaded"
	var dir := "%s/%s/%s" % [PALETTE_ROOT, category, asset_name]
	var mk := DirAccess.make_dir_recursive_absolute(dir)
	if mk != OK and mk != ERR_ALREADY_EXISTS:
		return "Could not create %s (error %d)" % [dir, mk]
	# Ensure templates folder exists too (per spec).
	DirAccess.make_dir_recursive_absolute(TEMPLATES_ROOT)

	var png_path := "%s/%s.png" % [dir, asset_name]
	var save_err := _image.save_png(png_path)
	if save_err != OK:
		return "Failed to write %s (error %d)" % [png_path, save_err]

	var normal_tex: Texture2D = null
	if with_normal:
		var normal_img := SobelNormal.generate(_image)
		var normal_path := "%s/%s_normal.png" % [dir, asset_name]
		var n_err := normal_img.save_png(normal_path)
		if n_err != OK:
			return "Failed to write %s (error %d)" % [normal_path, n_err]
		normal_tex = ImageTexture.create_from_image(normal_img)

	var diffuse_tex := ImageTexture.create_from_image(_image)
	var ct := CanvasTexture.new()
	ct.diffuse_texture = diffuse_tex
	if normal_tex != null:
		ct.normal_texture = normal_tex
	var tres_path := "%s/%s.tres" % [dir, asset_name]
	var ct_err := ResourceSaver.save(ct, tres_path)
	if ct_err != OK:
		return "Failed to write %s (error %d)" % [tres_path, ct_err]

	var json_err := _write_borders_json(dir, asset_name)
	if json_err != "":
		return json_err

	# Reload the saved CanvasTexture so the scene references it as an external
	# resource (matters for ResourceSaver to write [ext_resource ...]).
	var loaded_ct: CanvasTexture = load(tres_path)
	var scene_err := _write_scene(dir, asset_name, category, loaded_ct)
	if scene_err != "":
		return scene_err
	return ""


func _write_borders_json(dir: String, asset_name: String) -> String:
	var poly_array := []
	for p in _polygons:
		var verts: PackedVector2Array = p.get("vertices", PackedVector2Array())
		var as_pairs := []
		for v in verts:
			as_pairs.append([v.x, v.y])
		poly_array.append({
			"type": p.get("type", "collision"),
			"vertices": as_pairs,
		})
	var data := {
		"version": 1,
		"image": "%s.png" % asset_name,
		"image_size": [int(_image.get_width()), int(_image.get_height())],
		"polygons": poly_array,
	}
	var path := "%s/%s.borders.json" % [dir, asset_name]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Failed to open %s for writing (error %d)" % [path, FileAccess.get_open_error()]
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return ""


func _write_scene(dir: String, asset_name: String, category: String, ct: CanvasTexture) -> String:
	var image_size := Vector2(_image.get_width(), _image.get_height())
	var collision_polys: Array = []  # Array[PackedVector2Array]
	var recognition_polys: Array = []
	for p in _polygons:
		var verts: PackedVector2Array = p.get("vertices", PackedVector2Array())
		# CollisionPolygon2D.polygon must be offset by -image_size/2 so it aligns
		# with a centered Sprite2D.
		var centered := PackedVector2Array()
		for v in verts:
			centered.append(v - image_size * 0.5)
		if p.get("type", "collision") == "recognition":
			recognition_polys.append(centered)
		else:
			collision_polys.append(centered)

	var pretty_name := asset_name.capitalize().replace(" ", "_")
	var root := _build_category_root(category, pretty_name, ct, image_size, collision_polys, recognition_polys)
	if root == null:
		return "Unknown category %s" % category

	root.set_meta("recognition_priority", RECOGNITION_PRIORITY.get(category, 0))

	var template_path := "%s/%s.gd" % [TEMPLATES_ROOT, category.to_lower()]
	if ResourceLoader.exists(template_path):
		root.set_script(load(template_path))

	# Assign owner so all children survive PackedScene.pack().
	_assign_owner_recursive(root, root)

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		root.queue_free()
		return "Failed to pack scene (error %d)" % pack_err
	var tscn_path := "%s/%s.tscn" % [dir, asset_name]
	var save_err := ResourceSaver.save(packed, tscn_path)
	root.queue_free()
	if save_err != OK:
		return "Failed to write %s (error %d)" % [tscn_path, save_err]
	return ""


func _build_category_root(
	category: String, pretty_name: String, ct: CanvasTexture, _image_size: Vector2,
	collision_polys: Array, recognition_polys: Array
) -> Node:
	match category:
		"Wall", "Door", "Lock":
			var sb := StaticBody2D.new()
			sb.name = pretty_name
			_add_centered_sprite(sb, ct)
			_add_named_polygons(sb, collision_polys, "Collision")
			if recognition_polys.size() > 0:
				_add_recognition_area(sb, recognition_polys)
			return sb
		"Camera":
			# Root Area2D IS the recognition area; yellow polys go on root.
			var area := Area2D.new()
			area.name = pretty_name
			area.collision_layer = 2
			area.collision_mask = 0
			_add_centered_sprite(area, ct)
			_add_named_polygons(area, recognition_polys, "Recognition")
			if collision_polys.size() > 0:
				var body := StaticBody2D.new()
				body.name = "Body"
				area.add_child(body)
				_add_named_polygons(body, collision_polys, "Collision")
			return area
		"Enemy":
			var root := Node2D.new()
			root.name = pretty_name
			_add_centered_sprite(root, ct)
			var body := CharacterBody2D.new()
			body.name = "Body"
			root.add_child(body)
			_add_named_polygons(body, collision_polys, "Collision")
			if recognition_polys.size() > 0:
				_add_recognition_area(root, recognition_polys)
			return root
		"Artifact":
			# Artifact was originally spec'd as pickup-only (no red), but if the
			# user explicitly drew collision polys, honor them — same shape as
			# Camera: a child `Body` StaticBody2D holds the red polys so spawned
			# artifacts can block movement.
			var root := Node2D.new()
			root.name = pretty_name
			_add_centered_sprite(root, ct)
			if collision_polys.size() > 0:
				var body := StaticBody2D.new()
				body.name = "Body"
				root.add_child(body)
				_add_named_polygons(body, collision_polys, "Collision")
			if recognition_polys.size() > 0:
				_add_recognition_area(root, recognition_polys)
			return root
		_:
			return null


func _add_centered_sprite(parent: Node, ct: CanvasTexture) -> void:
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.centered = true
	spr.texture = ct
	parent.add_child(spr)


func _add_named_polygons(parent: Node, polys: Array, name_prefix: String) -> void:
	for i in range(polys.size()):
		var cp := CollisionPolygon2D.new()
		cp.name = "%s_%d" % [name_prefix, i]
		cp.polygon = polys[i]
		parent.add_child(cp)


func _add_recognition_area(parent: Node, polys: Array) -> void:
	var area := Area2D.new()
	area.name = "Recognition"
	area.collision_layer = 2
	area.collision_mask = 0
	parent.add_child(area)
	_add_named_polygons(area, polys, "Recognition")


func _assign_owner_recursive(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_assign_owner_recursive(child, root)


func _is_valid_name(s: String) -> bool:
	if s == "":
		return false
	for ch in s:
		var c := ch.unicode_at(0)
		var is_lower := c >= "a".unicode_at(0) and c <= "z".unicode_at(0)
		var is_digit := c >= "0".unicode_at(0) and c <= "9".unicode_at(0)
		var is_underscore := ch == "_"
		if not (is_lower or is_digit or is_underscore):
			return false
	return true


func _sanitize_name(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		var c := ch.unicode_at(0)
		var is_lower := c >= "a".unicode_at(0) and c <= "z".unicode_at(0)
		var is_digit := c >= "0".unicode_at(0) and c <= "9".unicode_at(0)
		if is_lower or is_digit or ch == "_":
			out += ch
		elif ch == " " or ch == "-":
			out += "_"
	return out


func _set_status_message(msg: String, is_error: bool) -> void:
	if _status_tool:
		_status_tool.text = msg
		_status_tool.add_theme_color_override("font_color",
			Color(1, 0.5, 0.5) if is_error else Color(0.5, 1, 0.6))


# ── Load Asset ──────────────────────────────────────────────────────────────

func _open_asset_browser() -> void:
	_asset_browser_entries = _scan_palette()
	_asset_browser_list.clear()
	for entry in _asset_browser_entries:
		_asset_browser_list.add_item("[%s]  %s" % [entry["category"], entry["name"]])
	_asset_browser.popup_centered()


func _scan_palette() -> Array:
	var results: Array = []
	var root := DirAccess.open(PALETTE_ROOT)
	if root == null:
		return results
	for category in root.get_directories():
		var cat_dir := "%s/%s" % [PALETTE_ROOT, category]
		var cd := DirAccess.open(cat_dir)
		if cd == null:
			continue
		for asset_name in cd.get_directories():
			var json_path := "%s/%s/%s.borders.json" % [cat_dir, asset_name, asset_name]
			if FileAccess.file_exists(json_path):
				results.append({
					"category": category,
					"name": asset_name,
					"json_path": json_path,
				})
	results.sort_custom(func(a, b): return [a["category"], a["name"]] < [b["category"], b["name"]])
	return results


func _on_asset_browser_item_activated(_idx: int) -> void:
	# ConfirmationDialog auto-hides on `confirmed` (the OK button); double-click
	# fires `item_activated` instead, which doesn't auto-hide. Hide manually so
	# the loaded polygons aren't obscured by the still-open browser.
	_asset_browser.hide()
	_on_asset_browser_confirmed()


func _on_asset_browser_confirmed() -> void:
	var sel := _asset_browser_list.get_selected_items()
	if sel.is_empty():
		return
	var entry: Dictionary = _asset_browser_entries[sel[0]]
	_load_asset(entry["json_path"])


func _load_asset(json_path: String) -> void:
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		_set_status_message("Could not open %s" % json_path, true)
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_status_message("Invalid borders.json", true)
		return
	var dir := json_path.get_base_dir()
	var img_name: String = parsed.get("image", "")
	if img_name == "":
		_set_status_message("borders.json has no image field", true)
		return
	_load_png("%s/%s" % [dir, img_name])
	# _load_png clears polygons; now restore from the JSON.
	var loaded: Array = []
	var raw_polys: Variant = parsed.get("polygons", [])
	if typeof(raw_polys) == TYPE_ARRAY:
		for p in raw_polys:
			if typeof(p) != TYPE_DICTIONARY:
				continue
			var verts := PackedVector2Array()
			var raw_verts: Variant = p.get("vertices", [])
			if typeof(raw_verts) == TYPE_ARRAY:
				for pair in raw_verts:
					if typeof(pair) == TYPE_ARRAY and (pair as Array).size() >= 2:
						verts.append(Vector2(float(pair[0]), float(pair[1])))
			loaded.append({"type": p.get("type", "collision"), "vertices": verts})
	_polygons = loaded
	_preview.set_polygons(_polygons)
	_refresh_polygon_list()
	_dirty = false
	_set_status_message("Loaded: %s" % json_path.get_file(), false)
