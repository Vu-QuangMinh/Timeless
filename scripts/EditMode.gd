extends Node2D

const ShortcutPanelBuilder := preload("res://scripts/util/shortcut_panel.gd")
# Phase 3 patrol-line rendering needs the same wall-extraction as main.gd's
# pathfinder so what F4 previews matches what the game's runtime pathfinder
# would compute. No class_name to avoid the editor-scan registration cost.
const WorldObstaclesScript := preload("res://scripts/pathing/world_obstacles.gd")

# Always-visible shortcut help panel (rendered bottom-right while F4 is active).
const SHORTCUTS := [
	{"category": "Mode",   "key": "F4",          "desc": "Toggle Edit Mode"},
	{"category": "Mode",   "key": "Esc",         "desc": "Quit game"},
	{"category": "Edit",   "key": "LMB Drag",    "desc": "Move object"},
	{"category": "Edit",   "key": "Handle Drag", "desc": "Scale object"},
	{"category": "Edit",   "key": "Shift+Click", "desc": "Multi-select toggle"},
	{"category": "Edit",   "key": "Ctrl+C",      "desc": "Copy selection to clipboard"},
	{"category": "Edit",   "key": "Ctrl+V",      "desc": "Paste clipboard"},
	{"category": "Edit",   "key": "M",           "desc": "Mirror selected"},
	{"category": "Edit",   "key": "Delete",      "desc": "Delete selected"},
	{"category": "Edit",   "key": "Ctrl+Z",      "desc": "Undo"},
	{"category": "View",   "key": "Mouse Wheel", "desc": "Zoom camera"},
	{"category": "View",   "key": "Arrows",      "desc": "Pan camera"},
	{"category": "View",   "key": "Middle Drag", "desc": "Pan camera"},
	{"category": "Patrol", "key": "P",           "desc": "Toggle patrol edit (enemy selected)"},
	{"category": "Patrol", "key": "Esc",         "desc": "Exit patrol edit"},
	{"category": "Patrol", "key": "Left Click",  "desc": "Add patrol point"},
	{"category": "Patrol", "key": "Right Click", "desc": "Delete patrol point (near a point)"},
	{"category": "Patrol", "key": "Drag",        "desc": "Move patrol point"},
	{"category": "Patrol", "key": "O",           "desc": "Toggle all patrol lines visible"},
]

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

# Ctrl+C / Ctrl+V clipboard. Ctrl+C snapshots references to the current
# multi_selected and resets the per-clipboard paste offset; Ctrl+V duplicates
# each clipboard item with a smart name (<basename>_<n+1>) and stair-stepped
# position so repeated pastes don't pile up.
var _clipboard: Array[Node2D] = []
var _clipboard_paste_offset: Vector2 = Vector2.ZERO

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
var _help_panel: PanelContainer = null

# Asset palette — lists everything F6 has saved under res://assets/palette/.
# Phase 2 implements drag-to-spawn: mouse-down on an entry begins a drag with
# a translucent ghost; mouse-up over the viewport spawns; over a panel cancels.
const PALETTE_ROOT := "res://assets/palette"
const PALETTE_CATEGORY_ORDER := ["Camera", "Enemy", "Wall", "Door", "Lock", "Artifact"]
var _palette_panel: PanelContainer = null
var _palette_list: VBoxContainer = null

# Guard patrol routes. Keyed by enemy node name → {points: Array[Vector2] in
# world meters, loop_mode: String}. Phase 1 only declares the data and surfaces
# a selection-aware status label; Phases 2-6 add editing, rendering, simulation,
# persistence, and shortcuts.
const PATROL_RECOGNITION_PRIORITY := 50  # F6 writes this meta on Enemy roots
const PATROL_LOOP_MODE_PING_PONG := "ping_pong"
const PATROL_POINT_PICK_RADIUS_M := 0.3  # right-click / drag pickup radius
const PATROL_MARKER_RADIUS_PX := 10.0    # screen-px circle radius (pre-zoom)
var _patrol_data: Dictionary = {}
var _patrol_section: VBoxContainer = null
var _patrol_status_label: Label = null

# Phase 2 edit mode. `_patrol_edit_guard_name` pins the guard we're editing
# (in case selection changes; though selection-change auto-exits the mode).
# `_patrol_drag_idx` is -1 when not dragging a point.
var _patrol_edit_mode: bool = false
var _patrol_edit_guard_name: String = ""
var _patrol_drag_idx: int = -1
var _patrol_drag_origin: Vector2 = Vector2.ZERO

# Phase 3 patrol-line rendering. Cache keyed by guard name → Array of segment
# dicts. Reachable segments carry {reachable: true, polyline: Array[Vector2]
# in iso-pixel space (already projected via IsoMath.project)}. Unreachable
# segments carry {reachable: false, p0/p1: Vector2 iso-pixel} so the dashed
# fallback can draw a straight projected line. Cleared on any edit.
const PATROL_ARC_STEPS := 16            # matches PathPreview.ARC_STEPS
const PATROL_LINE_W := 2.0              # screen pixels
const PATROL_DASH_ON := 8.0             # screen pixels
const PATROL_DASH_OFF := 6.0            # screen pixels
const COLOR_PATROL_REACHABLE := Color(0.3, 0.9, 1.0, 0.8)
const COLOR_PATROL_UNREACHABLE := Color(1.0, 0.2, 0.2, 0.8)
var _patrol_line_cache: Dictionary = {}
var _show_all_patrols: bool = false     # O toggle, F4-only, resets on deactivate

# Lazy AcceptDialog instance for "can't place — unreachable" pops. Built on
# first error so we don't pay for a dialog that never shows.
var _patrol_error_dialog: AcceptDialog = null

# Phase 4 simulation. Tweens are created on the level root (one per guard with
# ≥2 reachable patrol points), looped, and set to TWEEN_PAUSE_PROCESS so they
# survive any game-pause F4 may trigger. Pre-positions snapshot global_position
# at start so we can restore on stop. Sim auto-stops on F4 deactivate.
const PATROL_BASE_SPEED_MPS := 1.25     # design.md guard speed
var _simulating: bool = false
var _sim_tweens: Array[Tween] = []
var _sim_pre_positions: Dictionary = {}  # guard_name → Vector2 (iso pixels)
var _sim_button: Button = null

# Drag state. While `_palette_dragging` is true, F4's existing left-click /
# motion handlers early-return so the palette owns the mouse. Drag start is
# triggered by the entry Button's `button_down` signal; release / cancel is
# polled in `_process` via `Input.is_mouse_button_pressed`.
var _palette_dragging: bool = false
var _drag_payload: Dictionary = {}  # {type, path, category, name, ghost_scale}
var _drag_ghost: Sprite2D = null

var _context_menu: PopupMenu = null
var _context_menu_node: Node2D = null  # node targeted by the last RMB
var _context_is_palette: bool = false
var _palette_context_entry: Dictionary = {}
var _palette_delete_confirm: ConfirmationDialog = null


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

	# Always-visible shortcut help, anchored bottom-right (the existing F4 panel
	# sits top-left so this corner is clear).
	_help_panel = ShortcutPanelBuilder.build("F4 Shortcuts", SHORTCUTS)
	_help_panel.anchor_left = 1.0
	_help_panel.anchor_right = 1.0
	_help_panel.anchor_top = 1.0
	_help_panel.anchor_bottom = 1.0
	_help_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_help_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help_panel.offset_left = -8
	_help_panel.offset_right = -8
	_help_panel.offset_top = -8
	_help_panel.offset_bottom = -8
	_help_panel.visible = false
	_ui_layer.add_child(_help_panel)

	_build_palette_panel()
	_build_context_menu()


func _build_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.add_item("Clone", 0)
	_context_menu.add_separator()
	_context_menu.add_item("Delete", 1)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	_ui_layer.add_child(_context_menu)

	_palette_delete_confirm = ConfirmationDialog.new()
	_palette_delete_confirm.title = "Delete Asset"
	_palette_delete_confirm.ok_button_text = "Delete"
	_palette_delete_confirm.confirmed.connect(_on_palette_delete_confirmed)
	_ui_layer.add_child(_palette_delete_confirm)


func _build_palette_panel() -> void:
	# Right-edge dock, ~220px wide. Stops short of the bottom so the
	# bottom-right help panel keeps its real estate.
	_palette_panel = PanelContainer.new()
	_palette_panel.anchor_left = 1.0
	_palette_panel.anchor_right = 1.0
	_palette_panel.anchor_top = 0.0
	_palette_panel.anchor_bottom = 1.0
	_palette_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_palette_panel.offset_left = -228
	_palette_panel.offset_right = -8
	_palette_panel.offset_top = 8
	_palette_panel.offset_bottom = -300  # leaves room for the help panel
	_palette_panel.visible = false
	_ui_layer.add_child(_palette_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_palette_panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	margin.add_child(v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	v.add_child(header)
	var title := Label.new()
	title.text = "Assets"
	title.add_theme_font_size_override("font_size", 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.tooltip_text = "Rescan res://assets/palette/"
	refresh_btn.add_theme_font_size_override("font_size", 10)
	refresh_btn.pressed.connect(_refresh_palette)
	header.add_child(refresh_btn)

	v.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	_palette_list = VBoxContainer.new()
	_palette_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_palette_list)

	# Simulate Patrol button — Phase 4. Always visible (independent of any
	# enemy selection) so the user can toggle while editing other things.
	v.add_child(HSeparator.new())
	_sim_button = Button.new()
	_sim_button.text = "Simulate Patrol"
	_sim_button.add_theme_font_size_override("font_size", 11)
	_sim_button.pressed.connect(_toggle_simulate_patrol)
	v.add_child(_sim_button)

	# Patrol section. Visible only when the user selects an enemy node
	# (recognition_priority == 50). Phase 1 just shows the point count; Phases
	# 2-6 add edit-mode toggles, line rendering, simulate button, etc.
	v.add_child(HSeparator.new())
	_patrol_section = VBoxContainer.new()
	_patrol_section.add_theme_constant_override("separation", 2)
	_patrol_section.visible = false
	v.add_child(_patrol_section)
	var patrol_title := Label.new()
	patrol_title.text = "Patrol"
	patrol_title.add_theme_font_size_override("font_size", 11)
	patrol_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_patrol_section.add_child(patrol_title)
	_patrol_status_label = Label.new()
	_patrol_status_label.text = "Patrols: 0 points"
	_patrol_status_label.add_theme_font_size_override("font_size", 10)
	_patrol_section.add_child(_patrol_status_label)
	var patrol_hint := Label.new()
	patrol_hint.text = "Press P to edit"
	patrol_hint.add_theme_font_size_override("font_size", 9)
	patrol_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_patrol_section.add_child(patrol_hint)


func _refresh_palette() -> void:
	if _palette_list == null:
		return
	for c in _palette_list.get_children():
		c.queue_free()

	var entries := _scan_palette()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No assets in res://assets/palette/.\nPress F6 to author one."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 10)
		empty.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
		_palette_list.add_child(empty)
		return

	# Group by category, emit canonical order first then any unknown categories.
	var by_cat := {}
	for e in entries:
		var cat: String = e["category"]
		if not by_cat.has(cat):
			by_cat[cat] = []
		(by_cat[cat] as Array).append(e)
	var ordered_cats: Array = []
	for c in PALETTE_CATEGORY_ORDER:
		if by_cat.has(c):
			ordered_cats.append(c)
	for c in by_cat.keys():
		if not ordered_cats.has(c):
			ordered_cats.append(c)

	for cat in ordered_cats:
		var cat_label := Label.new()
		cat_label.text = String(cat).to_upper()
		cat_label.add_theme_font_size_override("font_size", 10)
		cat_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
		_palette_list.add_child(cat_label)
		for entry in by_cat[cat]:
			_palette_list.add_child(_build_palette_entry(entry))


# Returns Array of {category, name, type ("scene"|"sprite"), path}.
func _scan_palette() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(PALETTE_ROOT):
		return out
	_scan_palette_dir(PALETTE_ROOT, out)
	return out


func _scan_palette_dir(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	# Collect .tscn basenames in this folder so we can skip the paired .tres
	# (F6 saves both per asset; the .tres is referenced by the .tscn's Sprite2D).
	var tscn_basenames := {}
	for f in d.get_files():
		if f.get_extension().to_lower() == "tscn":
			tscn_basenames[f.get_basename()] = true

	for f in d.get_files():
		var ext := f.get_extension().to_lower()
		var base := f.get_basename()
		var path := "%s/%s" % [dir_path, f]
		if ext == "tscn":
			out.append({
				"category": _palette_category_for(path),
				"name": base,
				"type": "scene",
				"path": path,
			})
		elif ext == "tres" and not tscn_basenames.has(base):
			# Only count standalone CanvasTextures.
			var res = load(path)
			if res is CanvasTexture:
				out.append({
					"category": _palette_category_for(path),
					"name": base,
					"type": "sprite",
					"path": path,
				})

	for sub in d.get_directories():
		_scan_palette_dir("%s/%s" % [dir_path, sub], out)


# Category = first folder under PALETTE_ROOT.
# e.g. res://assets/palette/Camera/foo/foo.tscn → "Camera"
func _palette_category_for(asset_path: String) -> String:
	var rel := asset_path.replace(PALETTE_ROOT + "/", "")
	var parts := rel.split("/")
	if parts.size() >= 1:
		return parts[0]
	return "(uncategorized)"


func _build_palette_entry(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var thumb := _build_palette_thumbnail(e)
	row.add_child(thumb)

	var btn := Button.new()
	btn.text = String(e.get("name", ""))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.clip_text = true
	btn.add_theme_font_size_override("font_size", 11)
	btn.tooltip_text = String(e.get("path", ""))
	# Drag begins on mouse-down (not click), so the user can press, drag, drop.
	btn.button_down.connect(_on_palette_entry_button_down.bind(e))
	btn.gui_input.connect(_on_palette_entry_btn_gui_input.bind(e))
	row.add_child(btn)
	return row


func _build_palette_thumbnail(e: Dictionary) -> Control:
	var size := Vector2(48, 48)
	var tex: Texture2D = null
	var t: String = e.get("type", "")
	if t == "scene":
		tex = _palette_thumb_from_scene(String(e.get("path", "")))
	elif t == "sprite":
		var ct = load(String(e.get("path", "")))
		if ct is CanvasTexture:
			tex = (ct as CanvasTexture).diffuse_texture

	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.custom_minimum_size = size
		rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return rect

	var placeholder := ColorRect.new()
	placeholder.color = Color(0.3, 0.3, 0.32)
	placeholder.custom_minimum_size = size
	return placeholder


func _palette_thumb_from_scene(tscn_path: String) -> Texture2D:
	var packed: PackedScene = load(tscn_path)
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	if inst == null:
		return null
	var tex := _find_first_sprite_texture(inst)
	inst.queue_free()
	return tex


func _find_first_sprite_texture(node: Node) -> Texture2D:
	if node is Sprite2D and (node as Sprite2D).texture != null:
		return (node as Sprite2D).texture
	for child in node.get_children():
		var t := _find_first_sprite_texture(child)
		if t != null:
			return t
	return null


# Drag start — fires on mouse-down on a palette entry button.
func _on_palette_entry_button_down(e: Dictionary) -> void:
	if not active:
		return
	_start_palette_drag(e)


func _start_palette_drag(e: Dictionary) -> void:
	# Cancel any in-progress F4 drag/scale on the existing tools so we don't
	# leave them in a half-state.
	mode = "idle"
	_drag_starts.clear()

	var ghost_tex: Texture2D = null
	var ghost_scale := Vector2.ONE
	var t: String = e.get("type", "")
	if t == "scene":
		var info := _palette_scene_visual(String(e.get("path", "")))
		ghost_tex = info.get("texture", null)
		ghost_scale = info.get("scale", Vector2.ONE)
	elif t == "sprite":
		var ct = load(String(e.get("path", "")))
		if ct is CanvasTexture:
			ghost_tex = (ct as CanvasTexture).diffuse_texture

	_drag_payload = {
		"type": t,
		"path": e.get("path", ""),
		"category": e.get("category", ""),
		"name": e.get("name", "asset"),
		"ghost_scale": ghost_scale,
	}
	_palette_dragging = true
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)

	if _drag_ghost == null:
		_drag_ghost = Sprite2D.new()
		_drag_ghost.centered = true
		_drag_ghost.modulate = Color(1, 1, 1, 0.5)
		_drag_ghost.z_index = 4097  # above EditMode's grid (z=4096)
		add_child(_drag_ghost)
	_drag_ghost.texture = ghost_tex
	_drag_ghost.scale = ghost_scale
	_drag_ghost.visible = ghost_tex != null
	_update_drag_ghost_position()


# Returns {texture: Texture2D, scale: Vector2} from a .tscn's first Sprite2D.
func _palette_scene_visual(tscn_path: String) -> Dictionary:
	var packed: PackedScene = load(tscn_path)
	if packed == null:
		return {"texture": null, "scale": Vector2.ONE}
	var inst: Node = packed.instantiate()
	if inst == null:
		return {"texture": null, "scale": Vector2.ONE}
	var spr := _find_first_sprite(inst)
	var result: Dictionary
	if spr:
		result = {"texture": spr.texture, "scale": spr.scale}
	else:
		result = {"texture": null, "scale": Vector2.ONE}
	inst.queue_free()
	return result


func _find_first_sprite(node: Node) -> Sprite2D:
	if node is Sprite2D and (node as Sprite2D).texture != null:
		return node as Sprite2D
	for child in node.get_children():
		var s := _find_first_sprite(child)
		if s != null:
			return s
	return null


func _update_drag_ghost_position() -> void:
	if _drag_ghost == null:
		return
	# Spec: position at IsoMath.project(IsoMath.unproject(mouse)) — round-trip
	# is identity for IsoMath but kept verbatim for clarity / future-proofing
	# (in case unproject ever gains snapping).
	var mouse_world := get_global_mouse_position()
	var snapped := IsoMath.project(IsoMath.unproject(mouse_world))
	# EditMode is a Node2D in world space; the ghost is its child, so position
	# in world coords renders correctly under the camera.
	_drag_ghost.global_position = snapped


func _mouse_over_any_panel() -> bool:
	var mp := get_viewport().get_mouse_position()
	if not get_viewport().get_visible_rect().has_point(mp):
		return true  # outside window counts as "not over viewport"
	for p in [_ui_panel, _help_panel, _palette_panel]:
		if p != null and p.visible and p.get_global_rect().has_point(mp):
			return true
	return false


func _process_palette_drag() -> void:
	# Hide ghost while cursor is over a panel; drag itself stays alive.
	_drag_ghost.visible = not _mouse_over_any_panel() and _drag_ghost.texture != null
	_update_drag_ghost_position()
	# Release detection — Button's button_up signal isn't reliable for off-button
	# release, so poll instead.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_resolve_palette_drag()


func _resolve_palette_drag() -> void:
	if _mouse_over_any_panel():
		_cancel_palette_drag()
		return
	var spawn_world := IsoMath.project(IsoMath.unproject(get_global_mouse_position()))
	_spawn_palette_asset(spawn_world)
	_finish_palette_drag()


func _cancel_palette_drag() -> void:
	_finish_palette_drag()


func _finish_palette_drag() -> void:
	_palette_dragging = false
	_drag_payload = {}
	if _drag_ghost != null:
		_drag_ghost.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _spawn_palette_asset(spawn_world_pos: Vector2) -> void:
	var objects := _objects_node()
	if objects == null:
		push_warning("EditMode: spawn skipped — /Level1/Objects not found")
		return
	var t: String = _drag_payload.get("type", "")
	var path: String = _drag_payload.get("path", "")
	var basename: String = _drag_payload.get("name", "asset")
	var unique := _unique_palette_name(objects, basename)

	var node: Node = null
	if t == "scene":
		var packed: PackedScene = load(path)
		if packed == null:
			push_warning("EditMode: could not load scene %s" % path)
			return
		node = packed.instantiate()
	elif t == "sprite":
		var ct = load(path)
		if not (ct is CanvasTexture):
			push_warning("EditMode: %s is not a CanvasTexture" % path)
			return
		var spr := Sprite2D.new()
		spr.centered = true
		spr.texture = ct
		node = spr
	else:
		return

	if node == null:
		return
	node.name = unique
	if node is Node2D:
		(node as Node2D).position = spawn_world_pos
	objects.add_child(node)
	if not node.is_in_group("editable"):
		node.add_to_group("editable")
	# Tag with provenance so save_edits_to can route to spawned_scenes.
	node.set_meta("palette_source", path)
	node.set_meta("palette_type", t)

	_push_undo({"action": "create", "node": node})
	_persist()
	_refresh_object_list()


func _objects_node() -> Node:
	var lvl := get_parent()
	if lvl == null:
		return null
	return lvl.get_node_or_null("Objects")


func _unique_palette_name(parent: Node, basename: String) -> String:
	var i := 1
	while i < 10000:
		var candidate := "%s_%d" % [basename, i]
		if not parent.has_node(candidate):
			return candidate
		i += 1
	return "%s_%d" % [basename, Time.get_ticks_msec()]


# ── Patrol routes (Phase 1) ────────────────────────────────────────────────

# Returns the currently-selected node iff it's a guard (recognition_priority
# meta == 50, written by F6's Enemy category builder). Otherwise null.
func _selected_enemy() -> Node:
	if selected == null or not is_instance_valid(selected):
		return null
	if int(selected.get_meta("recognition_priority", -1)) == PATROL_RECOGNITION_PRIORITY:
		return selected
	return null


# Looks up (or returns a fresh default for) the patrol entry for a guard name.
# Phase 2+ will mutate the returned dict directly when editing patrol points.
func _patrol_entry_for(guard_name: String) -> Dictionary:
	if not _patrol_data.has(guard_name):
		_patrol_data[guard_name] = {
			"points": [] as Array[Vector2],
			"loop_mode": PATROL_LOOP_MODE_PING_PONG,
		}
	return _patrol_data[guard_name]


# Shows/hides the patrol UI section based on whether an enemy is selected, and
# refreshes the point-count label. Called from every selection-changing path.
func _update_patrol_panel() -> void:
	if _patrol_section == null:
		return
	var enemy := _selected_enemy()
	if enemy == null:
		_patrol_section.visible = false
		return
	var entry := _patrol_entry_for(str(enemy.name))
	var pt_count := (entry.get("points", []) as Array).size()
	_patrol_status_label.text = "Patrols: %d points" % pt_count
	_patrol_section.visible = true


# ── Patrol routes (Phase 2) ────────────────────────────────────────────────

# P key entry point. No-op unless an enemy is currently selected. While
# patrol-edit is on, F4's normal viewport input is routed to patrol handlers.
func _patrol_toggle_edit_mode() -> void:
	# Phase 4: P is ignored during simulation. Spec requires patrol-edit be
	# force-exited at sim start (handled in _start_patrol_simulation) and the
	# key itself be a no-op while sim runs.
	if _simulating:
		return
	if _patrol_edit_mode:
		_patrol_exit_edit_mode()
		return
	var enemy := _selected_enemy()
	if enemy == null:
		return
	# Cancel any in-progress F4 drag/scale before taking input ownership.
	mode = "idle"
	_drag_starts.clear()
	_patrol_edit_mode = true
	_patrol_edit_guard_name = str(enemy.name)
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	_update_patrol_panel()
	queue_redraw()


func _patrol_exit_edit_mode() -> void:
	if not _patrol_edit_mode:
		return
	# Mid-drag exit: finalize the drag (pushes undo if it moved).
	if _patrol_drag_idx >= 0:
		_patrol_drag_end()
	_patrol_edit_mode = false
	_patrol_edit_guard_name = ""
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_update_patrol_panel()
	queue_redraw()


# Index of the closest patrol point to `world_pos` within
# PATROL_POINT_PICK_RADIUS_M, or -1. Operates on the currently-edited guard.
func _patrol_index_near(world_pos: Vector2) -> int:
	if _patrol_edit_guard_name == "":
		return -1
	if not _patrol_data.has(_patrol_edit_guard_name):
		return -1
	var pts: Array = (_patrol_data[_patrol_edit_guard_name] as Dictionary)["points"]
	var best := -1
	var best_d := PATROL_POINT_PICK_RADIUS_M
	for i in pts.size():
		var d := (pts[i] as Vector2).distance_to(world_pos)
		if d <= best_d:
			best_d = d
			best = i
	return best


func _patrol_add_point_at(world_pos: Vector2) -> void:
	if not _patrol_edit_mode:
		return
	var entry := _patrol_entry_for(_patrol_edit_guard_name)
	var pts: Array = entry["points"]
	# Any point past the first must be reachable from the prior point. If the
	# pathfinder returns empty, refuse the placement and pop an error — the
	# user can re-aim instead of leaving a dashed/broken segment in the route.
	if pts.size() >= 1 and not _patrol_is_reachable(pts[pts.size() - 1] as Vector2, world_pos):
		_show_patrol_unreachable_popup(
			"Can't place this patrol point — no path from the previous point.\nMove closer or place around obstacles.")
		return
	pts.append(world_pos)
	_push_undo({
		"action": "patrol_add",
		"guard": _patrol_edit_guard_name,
		"index": pts.size() - 1,
	})
	_persist()
	_update_patrol_panel()
	queue_redraw()


func _patrol_delete_at(world_pos: Vector2) -> bool:
	if not _patrol_edit_mode:
		return false
	var idx := _patrol_index_near(world_pos)
	if idx < 0:
		return false
	var entry := _patrol_entry_for(_patrol_edit_guard_name)
	var pts: Array = entry["points"]
	var pos: Vector2 = pts[idx]
	pts.remove_at(idx)
	_push_undo({
		"action": "patrol_delete",
		"guard": _patrol_edit_guard_name,
		"index": idx,
		"position": pos,
	})
	_persist()
	_update_patrol_panel()
	queue_redraw()
	return true


func _patrol_drag_begin(world_pos: Vector2) -> bool:
	if not _patrol_edit_mode:
		return false
	var idx := _patrol_index_near(world_pos)
	if idx < 0:
		return false
	var pts: Array = (_patrol_data[_patrol_edit_guard_name] as Dictionary)["points"]
	_patrol_drag_idx = idx
	_patrol_drag_origin = pts[idx]
	return true


func _patrol_drag_update(world_pos: Vector2) -> void:
	if _patrol_drag_idx < 0:
		return
	var pts: Array = (_patrol_data[_patrol_edit_guard_name] as Dictionary)["points"]
	pts[_patrol_drag_idx] = world_pos
	# Drag doesn't go through _persist (only drag_end does), so invalidate the
	# line cache directly so the rebuild picks up the moved point each frame.
	_invalidate_patrol_line(_patrol_edit_guard_name)
	queue_redraw()


func _patrol_drag_end() -> void:
	if _patrol_drag_idx < 0:
		return
	var pts: Array = (_patrol_data[_patrol_edit_guard_name] as Dictionary)["points"]
	var final_pos: Vector2 = pts[_patrol_drag_idx]
	if final_pos != _patrol_drag_origin:
		# Both touching segments must still be reachable — incoming from the
		# prior point and outgoing to the next one. If either fails, snap back
		# to the drag origin (no undo entry pushed).
		var idx := _patrol_drag_idx
		var rejected := false
		if idx > 0 and not _patrol_is_reachable(pts[idx - 1] as Vector2, final_pos):
			rejected = true
		if not rejected and idx + 1 < pts.size() \
				and not _patrol_is_reachable(final_pos, pts[idx + 1] as Vector2):
			rejected = true
		if rejected:
			pts[idx] = _patrol_drag_origin
			_invalidate_patrol_line(_patrol_edit_guard_name)
			_show_patrol_unreachable_popup(
				"Can't move this patrol point there — no path to or from an adjacent point.")
			queue_redraw()
		else:
			_push_undo({
				"action": "patrol_move",
				"guard": _patrol_edit_guard_name,
				"index": _patrol_drag_idx,
				"position": _patrol_drag_origin,
			})
			_persist()
	_patrol_drag_idx = -1
	_patrol_drag_origin = Vector2.ZERO


# ── Patrol lines (Phase 3) ─────────────────────────────────────────────────

func _invalidate_patrol_line(guard_name: String) -> void:
	_patrol_line_cache.erase(guard_name)


# Pulls wall geometry + obstacles in the same shape main.gd's _build_path
# does, so the F4 preview matches what the runtime guard pathfinder would see.
func _build_patrol_path_inputs() -> Dictionary:
	var lvl := get_parent()
	var wall_segs: Array = []
	var obstacles: Array = []
	if lvl != null:
		if lvl.has_method("get_wall_segments"):
			wall_segs = lvl.get_wall_segments()
		wall_segs.append_array(WorldObstaclesScript.collect_wall_segments(lvl))
		if lvl.has_method("get_chest_obstacle"):
			var chest: Dictionary = lvl.get_chest_obstacle()
			if chest.get("radius", 0.0) > 0.0:
				obstacles.append(chest)
	return {"walls": wall_segs, "obstacles": obstacles}


# Lazily rebuilds the polyline cache for a single guard. Called by the
# renderer on demand; idempotent.
func _rebuild_patrol_line(guard_name: String) -> void:
	if not _patrol_data.has(guard_name):
		_patrol_line_cache.erase(guard_name)
		return
	var pts: Array = (_patrol_data[guard_name] as Dictionary)["points"]
	if pts.size() < 2:
		_patrol_line_cache[guard_name] = []
		return
	var inputs := _build_patrol_path_inputs()
	var pf := Pathfinder.new()
	pf.setup(inputs["walls"], inputs["obstacles"])
	var smoother := PathSmoother.new()
	var segs: Array = []
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var waypoints: Array = pf.find_path(a, b)
		if waypoints.is_empty():
			segs.append({
				"reachable": false,
				"p0": IsoMath.project(a),
				"p1": IsoMath.project(b),
			})
			continue
		var mp: MovePath = smoother.smooth(waypoints, inputs["walls"], inputs["obstacles"])
		if mp == null:
			segs.append({
				"reachable": false,
				"p0": IsoMath.project(a),
				"p1": IsoMath.project(b),
			})
			continue
		segs.append({"reachable": true, "polyline": _movepath_to_polyline(mp)})
	_patrol_line_cache[guard_name] = segs


# Samples a MovePath at the same fidelity PathPreview uses (16 steps per arc,
# line segments use their endpoints) and projects each vertex to iso pixels.
func _movepath_to_polyline(mp: MovePath) -> Array:
	var out: Array = []
	for i in mp._segments.size():
		var seg: MovePath.Segment = mp._segments[i]
		if not seg.is_arc:
			if out.is_empty():
				out.append(IsoMath.project(seg.start))
			out.append(IsoMath.project(seg.end))
		else:
			var p0 := seg.center + Vector2(cos(seg.from_angle), sin(seg.from_angle)) * seg.radius
			if out.is_empty():
				out.append(IsoMath.project(p0))
			for k in range(1, PATROL_ARC_STEPS + 1):
				var t := float(k) / float(PATROL_ARC_STEPS)
				var angle := seg.from_angle + (seg.to_angle - seg.from_angle) * t
				var p := seg.center + Vector2(cos(angle), sin(angle)) * seg.radius
				out.append(IsoMath.project(p))
	return out


# Draws the cached patrol line for one guard. Lazily rebuilds on cache miss.
func _draw_patrol_lines(guard_name: String, view_zoom: Vector2) -> void:
	if not _patrol_line_cache.has(guard_name):
		_rebuild_patrol_line(guard_name)
	var segs: Array = _patrol_line_cache.get(guard_name, [])
	if segs.is_empty():
		return
	var z := maxf(view_zoom.x, 0.0001)
	var line_w := PATROL_LINE_W / z
	for seg in segs:
		if bool(seg.get("reachable", false)):
			var polyline: Array = seg["polyline"]
			for i in range(polyline.size() - 1):
				draw_line(polyline[i], polyline[i + 1], COLOR_PATROL_REACHABLE, line_w)
		else:
			_draw_dashed_line(seg["p0"], seg["p1"], COLOR_PATROL_UNREACHABLE, line_w, z)


# Single-pair reachability check using the same wall + obstacle inputs the
# patrol-line renderer uses. Returns false iff Pathfinder.find_path is empty.
func _patrol_is_reachable(from: Vector2, to: Vector2) -> bool:
	var inputs := _build_patrol_path_inputs()
	var pf := Pathfinder.new()
	pf.setup(inputs["walls"], inputs["obstacles"])
	return not pf.find_path(from, to).is_empty()


func _show_patrol_unreachable_popup(msg: String) -> void:
	if _patrol_error_dialog == null:
		_patrol_error_dialog = AcceptDialog.new()
		_patrol_error_dialog.title = "Patrol Point Unreachable"
		# Mount on the existing F4 UI layer so it sits above the world.
		if _ui_layer != null:
			_ui_layer.add_child(_patrol_error_dialog)
		else:
			add_child(_patrol_error_dialog)
	_patrol_error_dialog.dialog_text = msg
	_patrol_error_dialog.popup_centered()


# ── Patrol simulation (Phase 4) ────────────────────────────────────────────

func _toggle_simulate_patrol() -> void:
	if _simulating:
		_stop_patrol_simulation()
	else:
		_start_patrol_simulation()


# Builds forward + backward MovePaths for one guard (ping-pong). Returns an
# empty array if any segment is unreachable or if the guard has < 2 points —
# we refuse to simulate broken patrols rather than animate through walls.
func _build_patrol_movepaths_pingpong(guard_name: String) -> Array:
	if not _patrol_data.has(guard_name):
		return []
	var pts: Array = (_patrol_data[guard_name] as Dictionary)["points"]
	if pts.size() < 2:
		return []
	var inputs := _build_patrol_path_inputs()
	var pf := Pathfinder.new()
	pf.setup(inputs["walls"], inputs["obstacles"])
	var smoother := PathSmoother.new()
	var paths: Array = []
	# Forward: 0 → 1 → ... → N-1
	for i in range(pts.size() - 1):
		var wpts: Array = pf.find_path(pts[i], pts[i + 1])
		if wpts.is_empty():
			return []
		var mp: MovePath = smoother.smooth(wpts, inputs["walls"], inputs["obstacles"])
		if mp == null:
			return []
		paths.append(mp)
	# Backward: N-1 → N-2 → ... → 0. Recomputed (not just reversed) because
	# smoothing's arc choices differ by direction.
	for i in range(pts.size() - 1, 0, -1):
		var wpts2: Array = pf.find_path(pts[i], pts[i - 1])
		if wpts2.is_empty():
			return []
		var mp2: MovePath = smoother.smooth(wpts2, inputs["walls"], inputs["obstacles"])
		if mp2 == null:
			return []
		paths.append(mp2)
	return paths


func _find_guard_node(guard_name: String) -> Node2D:
	var lvl := get_parent()
	if lvl == null:
		return null
	var objects := lvl.get_node_or_null("Objects")
	if objects == null:
		return null
	var node := objects.get_node_or_null(guard_name)
	if node == null or not (node is Node2D):
		return null
	return node as Node2D


# Tween setter. Frac is the eased 0..1 progress along `path`. position_at
# returns world meters; project to iso pixels for the scene's coordinate
# space. Stale guard refs (deleted mid-sim) silently no-op.
func _set_guard_at_path_frac(guard: Node2D, path: MovePath, frac: float) -> void:
	if not is_instance_valid(guard):
		return
	guard.global_position = IsoMath.project(path.position_at(frac))


func _start_patrol_simulation() -> void:
	# Spec: simulation is F4-only.
	if not active:
		return
	# Force-exit patrol-edit before starting (spec: "patrol-edit is force-exited if active").
	if _patrol_edit_mode:
		_patrol_exit_edit_mode()
	var lvl := get_parent()
	if lvl == null:
		return
	_sim_pre_positions.clear()
	_sim_tweens.clear()
	var any_started := false
	for guard_name in _patrol_data.keys():
		var paths := _build_patrol_movepaths_pingpong(guard_name)
		if paths.is_empty():
			continue
		var guard_node := _find_guard_node(guard_name)
		if guard_node == null:
			continue
		_sim_pre_positions[guard_name] = guard_node.global_position
		var base_speed := PATROL_BASE_SPEED_MPS
		if guard_node.has_meta("effective_movespeed"):
			base_speed = float(guard_node.get_meta("effective_movespeed"))
		var effective_speed := base_speed * GameManager.ANIMATION_SPEED_MULTIPLIER
		var t := lvl.create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.set_loops()
		for path in paths:
			var dur: float = (path as MovePath).total_length() / maxf(effective_speed, 0.001)
			var path_ref: MovePath = path
			var node_ref: Node2D = guard_node
			t.tween_method(
				func(frac: float) -> void: _set_guard_at_path_frac(node_ref, path_ref, frac),
				0.0, 1.0, dur,
			)
		_sim_tweens.append(t)
		any_started = true
	if not any_started:
		# Nothing to simulate — toggle stays off so the button label is honest.
		return
	_simulating = true
	_update_sim_button_label()


func _stop_patrol_simulation() -> void:
	for t in _sim_tweens:
		if t != null and is_instance_valid(t):
			t.kill()
	_sim_tweens.clear()
	for guard_name in _sim_pre_positions.keys():
		var node := _find_guard_node(guard_name)
		if node != null:
			node.global_position = _sim_pre_positions[guard_name]
	_sim_pre_positions.clear()
	_simulating = false
	_update_sim_button_label()


func _update_sim_button_label() -> void:
	if _sim_button != null:
		_sim_button.text = "Stop Simulation" if _simulating else "Simulate Patrol"


# Dashes are sized in screen pixels; iso-pixel local lengths divide by zoom so
# the pattern doesn't grow / shrink with camera zoom.
func _draw_dashed_line(p0: Vector2, p1: Vector2, col: Color, line_w: float, z: float) -> void:
	var dash_on := PATROL_DASH_ON / z
	var dash_off := PATROL_DASH_OFF / z
	var period := dash_on + dash_off
	var total := p0.distance_to(p1)
	if total < 0.0001:
		return
	var dir := (p1 - p0) / total
	var t := 0.0
	while t < total:
		var a := p0 + dir * t
		var b := p0 + dir * minf(t + dash_on, total)
		draw_line(a, b, col, line_w)
		t += period


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
		btn.gui_input.connect(_on_object_list_btn_gui_input.bind(n))
		_ui_list.add_child(btn)
	# Selection-changing paths all flow through _refresh_object_list, so this
	# is the single chokepoint that keeps the patrol panel in sync with
	# `selected`. (See _selected_enemy / _update_patrol_panel.)
	_update_patrol_panel()


func _on_object_button_pressed(node: Node2D) -> void:
	if not is_instance_valid(node):
		_refresh_object_list()
		return
	# Panel selection changes auto-exit patrol-edit; user can press P to re-enter
	# on the new selection if it's an enemy.
	if _patrol_edit_mode:
		_patrol_exit_edit_mode()
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


func _on_object_list_btn_gui_input(event: InputEvent, node: Node2D) -> void:
	if not (event is InputEventMouseButton):
		return
	var me := event as InputEventMouseButton
	if me.button_index != MOUSE_BUTTON_RIGHT or not me.pressed:
		return
	if not is_instance_valid(node):
		return
	if node not in multi_selected:
		multi_selected = [node]
		selected = node
		_refresh_object_list()
	_context_is_palette = false
	_context_menu_node = selected
	var mp := Vector2i(get_viewport().get_mouse_position())
	_context_menu.popup(Rect2i(mp, Vector2i.ZERO))


func _on_palette_entry_btn_gui_input(event: InputEvent, e: Dictionary) -> void:
	if not (event is InputEventMouseButton):
		return
	var me := event as InputEventMouseButton
	if not me.pressed:
		return
	if me.button_index == MOUSE_BUTTON_LEFT and me.double_click:
		_open_asset_in_f6(e)
		return
	if me.button_index == MOUSE_BUTTON_RIGHT:
		_context_is_palette = true
		_palette_context_entry = e
		var mp := Vector2i(get_viewport().get_mouse_position())
		_context_menu.popup(Rect2i(mp, Vector2i.ZERO))


func _on_context_menu_id_pressed(id: int) -> void:
	if _context_is_palette:
		match id:
			0:
				_spawn_palette_entry_at_center(_palette_context_entry)
			1:
				_confirm_delete_palette_asset(_palette_context_entry)
	else:
		match id:
			0:
				_clone_selected()
			1:
				_delete_selected()


func _clone_selected() -> void:
	if multi_selected.is_empty():
		return
	var new_nodes: Array[Node2D] = []
	for source in multi_selected:
		if not is_instance_valid(source):
			continue
		var dup: Node = source.duplicate()
		source.get_parent().add_child(dup)
		if not dup.is_in_group("editable"):
			dup.add_to_group("editable")
		if dup is Node2D:
			var d2 := dup as Node2D
			d2.global_position = source.global_position + copy_offset
			d2.name = _smart_copy_name(d2.get_parent(), str(source.name))
			new_nodes.append(d2)
		_push_undo({"action": "create", "node": dup})
	if not new_nodes.is_empty():
		multi_selected = new_nodes
		selected = new_nodes[new_nodes.size() - 1]
	_persist()
	_refresh_object_list()


func _open_asset_in_f6(e: Dictionary) -> void:
	var path: String = String(e.get("path", ""))
	if path == "":
		return
	var dir_path: String = path.get_base_dir()
	var asset_name: String = path.get_basename().get_file()
	var json_path: String = dir_path + "/" + asset_name + ".borders.json"
	if not FileAccess.file_exists(json_path):
		push_warning("EditMode: no borders.json found for %s" % asset_name)
		return
	var asset_editor := get_node_or_null("../AssetEditor")
	if asset_editor == null:
		push_warning("EditMode: AssetEditor node not found")
		return
	if not bool(asset_editor.get("active")):
		asset_editor.call("_toggle")
	asset_editor.call("_load_asset", json_path)


func _spawn_palette_entry_at_center(e: Dictionary) -> void:
	var cam := get_viewport().get_camera_2d()
	var spawn_iso: Vector2
	if cam:
		spawn_iso = cam.get_screen_center_position()
	else:
		spawn_iso = get_viewport_rect().size * 0.5
	_drag_payload = {
		"type": String(e.get("type", "")),
		"path": String(e.get("path", "")),
		"category": String(e.get("category", "")),
		"name": String(e.get("name", "asset")),
		"ghost_scale": Vector2.ONE,
	}
	_spawn_palette_asset(IsoMath.project(IsoMath.unproject(spawn_iso)))
	_drag_payload = {}


func _confirm_delete_palette_asset(e: Dictionary) -> void:
	if _palette_delete_confirm == null:
		return
	var name: String = String(e.get("name", "this asset"))
	_palette_delete_confirm.dialog_text = "Delete \"%s\" and all its files from the palette?" % name
	_palette_context_entry = e
	_palette_delete_confirm.popup_centered()


func _on_palette_delete_confirmed() -> void:
	var path: String = String(_palette_context_entry.get("path", ""))
	if path == "":
		return
	var dir_path: String = path.get_base_dir()
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(dir_path + "/" + f)
	DirAccess.remove_absolute(dir_path)
	_refresh_palette()


func _process(_delta: float) -> void:
	if _palette_dragging:
		_process_palette_drag()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			# Esc cancels a palette drag without quitting the game.
			if _palette_dragging:
				_cancel_palette_drag()
				get_viewport().set_input_as_handled()
				return
			# Esc exits patrol-edit mode without quitting.
			if _patrol_edit_mode:
				_patrol_exit_edit_mode()
				get_viewport().set_input_as_handled()
				return
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

	# Right-click during a palette drag cancels (matches Esc).
	if _palette_dragging and event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT \
			and (event as InputEventMouseButton).pressed:
		_cancel_palette_drag()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_Z and event.ctrl_pressed:
				_undo()
			elif event.keycode == KEY_C and event.ctrl_pressed:
				_copy_to_clipboard()
			elif event.keycode == KEY_V and event.ctrl_pressed:
				_paste_clipboard()
			elif event.keycode == KEY_DELETE and selected:
				_delete_selected()
			elif event.keycode == KEY_M and selected and not event.ctrl_pressed:
				_mirror_selected()
			elif event.keycode == KEY_P and not event.ctrl_pressed:
				_patrol_toggle_edit_mode()
			elif event.keycode == KEY_O and not event.ctrl_pressed:
				_show_all_patrols = not _show_all_patrols
				queue_redraw()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return
		# Palette owns the mouse during drag — suppress F4's selection /
		# scene-drag / scale-handle handlers without rewriting them.
		if _palette_dragging:
			get_viewport().set_input_as_handled()
			return
		# Patrol-edit owns the mouse: left-click adds (or drags a nearby point),
		# right-click deletes a nearby point. Other F4 left-click handlers
		# (selection, drag-to-move, scale handles) are suppressed.
		if _patrol_edit_mode:
			var wp := IsoMath.unproject(get_global_mouse_position())
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					if not _patrol_drag_begin(wp):
						_patrol_add_point_at(wp)
				else:
					_patrol_drag_end()
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_patrol_delete_at(wp)
			get_viewport().set_input_as_handled()
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
		# Palette drag updates ghost via _process polling — don't let F4's
		# drag/scale tools react to mouse motion while a drag is active.
		if _palette_dragging:
			get_viewport().set_input_as_handled()
			return
		# Patrol-edit: only react to motion while actively dragging a point.
		if _patrol_edit_mode:
			if _patrol_drag_idx >= 0:
				_patrol_drag_update(IsoMath.unproject(get_global_mouse_position()))
			get_viewport().set_input_as_handled()
			return
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
	if _help_panel:
		_help_panel.visible = true
	if _palette_panel:
		_palette_panel.visible = true
	_refresh_object_list()
	_refresh_palette()
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
	# Spawned scene roots (StaticBody2D, Area2D, Node2D, etc.) carry their visual
	# in a child Sprite2D. Use that sprite's bounds — it inherits the root's
	# transform via global_position/global_scale, so dragging/scaling the root
	# moves the bounds correctly.
	var child := _find_first_sprite(node)
	if child and child.texture:
		var size: Vector2 = child.texture.get_size() * child.global_scale.abs()
		var origin: Vector2
		if child.centered:
			origin = child.global_position - size * 0.5
		else:
			origin = child.global_position
		origin += child.offset * child.global_scale
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
	# Re-anchor: shift selected so the corner opposite the grabbed handle
	# (scale_grabbed_dir tells us which corner was grabbed) stays fixed at
	# scale_anchor_world. Works for Sprite2D roots and for spawned scene roots
	# whose bounds come from a child Sprite2D.
	var b = _world_bounds(selected)
	if b != null:
		var rect := b as Rect2
		var anchor_corner: Vector2
		if scale_grabbed_dir.x >= 0.0 and scale_grabbed_dir.y >= 0.0:
			anchor_corner = rect.position
		elif scale_grabbed_dir.x < 0.0 and scale_grabbed_dir.y >= 0.0:
			anchor_corner = Vector2(rect.end.x, rect.position.y)
		elif scale_grabbed_dir.x < 0.0 and scale_grabbed_dir.y < 0.0:
			anchor_corner = rect.end
		else:
			anchor_corner = Vector2(rect.position.x, rect.end.y)
		selected.global_position += scale_anchor_world - anchor_corner
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
		"patrol_add":
			var g: String = e["guard"]
			var i: int = e["index"]
			if _patrol_data.has(g):
				var pts: Array = (_patrol_data[g] as Dictionary)["points"]
				if i >= 0 and i < pts.size():
					pts.remove_at(i)
			_update_patrol_panel()
		"patrol_delete":
			var g2: String = e["guard"]
			var i2: int = e["index"]
			var p2: Vector2 = e["position"]
			var entry := _patrol_entry_for(g2)
			var pts2: Array = entry["points"]
			var insert_at: int = clampi(i2, 0, pts2.size())
			pts2.insert(insert_at, p2)
			_update_patrol_panel()
		"patrol_move":
			var g3: String = e["guard"]
			var i3: int = e["index"]
			var p3: Vector2 = e["position"]
			if _patrol_data.has(g3):
				var pts3: Array = (_patrol_data[g3] as Dictionary)["points"]
				if i3 >= 0 and i3 < pts3.size():
					pts3[i3] = p3
			_update_patrol_panel()
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


func _copy_to_clipboard() -> void:
	# Snapshot references; resets per-clipboard offset so the next paste lands
	# exactly one copy_offset from the source.
	_clipboard.clear()
	for n in multi_selected:
		if is_instance_valid(n):
			_clipboard.append(n)
	_clipboard_paste_offset = Vector2.ZERO


func _paste_clipboard() -> void:
	if _clipboard.is_empty():
		return
	_clipboard_paste_offset += copy_offset
	var new_dups: Array[Node2D] = []
	for source in _clipboard:
		if not is_instance_valid(source):
			continue
		var dup: Node = source.duplicate()
		source.get_parent().add_child(dup)
		if not dup.is_in_group("editable"):
			dup.add_to_group("editable")
		if dup is Node2D:
			var d2 := dup as Node2D
			d2.global_position = source.global_position + _clipboard_paste_offset
			d2.name = _smart_copy_name(d2.get_parent(), str(source.name))
			new_dups.append(d2)
		_push_undo({"action": "create", "node": dup})
	if new_dups.size() > 0:
		multi_selected = new_dups
		selected = new_dups[new_dups.size() - 1]
	_persist()
	_refresh_object_list()


# If `source_name` ends in `_<digits>` (e.g. test_widget_3, Painting_1), the
# new name keeps the same basename and finds the next unused index after that.
# Otherwise (e.g. CCTV, Door), append `_1` (or higher if already taken).
func _smart_copy_name(parent: Node, source_name: String) -> String:
	var basename := source_name
	var start := 1
	var re := RegEx.new()
	re.compile("^(.+)_(\\d+)$")
	var m := re.search(source_name)
	if m:
		basename = m.get_string(1)
		start = int(m.get_string(2)) + 1
	var i := start
	while i < 100000:
		var candidate := "%s_%d" % [basename, i]
		if not parent.has_node(candidate):
			return candidate
		i += 1
	return "%s_%d" % [basename, Time.get_ticks_msec()]


func _persist() -> void:
	# Edits are now batched: mark dirty, write only on explicit Save / Save As.
	# Any edit may change wall geometry under F4-spawned StaticBody2Ds, so blow
	# the patrol-line cache so the next draw rebuilds against current walls.
	_patrol_line_cache.clear()
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
	if _palette_dragging:
		_cancel_palette_drag()
	if _patrol_edit_mode:
		_patrol_exit_edit_mode()
	# Phase 4: simulation is F4-only — auto-stop and restore positions when
	# leaving the mode (covers F4-off, switch to F5/F6, and discard exits).
	if _simulating:
		_stop_patrol_simulation()
	# Phase 3: O state is F4-scoped per spec — reset on deactivate.
	_show_all_patrols = false
	_patrol_line_cache.clear()
	active = false
	selected = null
	multi_selected.clear()
	mode = "idle"
	set_process(false)
	if _ui_panel:
		_ui_panel.visible = false
	if _help_panel:
		_help_panel.visible = false
	if _palette_panel:
		_palette_panel.visible = false
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

	# Patrol lines: if O is on, every guard's line; else only the selected
	# guard's. Drawn before markers so the numbered circles render on top.
	var selected_enemy := _selected_enemy()
	if _show_all_patrols:
		for guard_name in _patrol_data.keys():
			_draw_patrol_lines(guard_name, view_zoom)
	elif selected_enemy != null:
		_draw_patrol_lines(str(selected_enemy.name), view_zoom)

	# Patrol markers render for the currently-selected enemy regardless of
	# edit-mode state — selecting a guard shows its route at a glance.
	if selected_enemy != null:
		_draw_patrol_markers(selected_enemy, view_zoom)


# Numbered red circles at IsoMath.project(point_world_meters). EditMode is a
# Node2D at world origin (0, 0) so global iso pixels == _draw local coords.
func _draw_patrol_markers(guard: Node, view_zoom: Vector2) -> void:
	if not _patrol_data.has(str(guard.name)):
		return
	var pts: Array = (_patrol_data[str(guard.name)] as Dictionary)["points"]
	if pts.is_empty():
		return
	var z := maxf(view_zoom.x, 0.0001)
	var radius_px := PATROL_MARKER_RADIUS_PX / z
	var line_w := 1.5 / z
	var marker_font := ThemeDB.fallback_font
	var marker_font_size: int = max(9, int(11.0 / z))
	var fill := Color(0.95, 0.2, 0.2, 0.92)
	var border := Color(0.55, 0.05, 0.05, 0.95)
	for i in pts.size():
		var screen := IsoMath.project(pts[i] as Vector2)
		draw_circle(screen, radius_px, fill)
		draw_arc(screen, radius_px, 0.0, TAU, 24, border, line_w, true)
		var label := str(i + 1)
		var ts: Vector2 = marker_font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, marker_font_size)
		var label_pos := screen + Vector2(-ts.x * 0.5, marker_font_size * 0.35)
		draw_string(
			marker_font, label_pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, marker_font_size, Color.WHITE)
