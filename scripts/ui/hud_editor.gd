class_name HUDEditor
extends Node

# Each entry: name, x_key, y_key, w_key, h_key
# Groups (is_group:true) — absolute position per character
# Elements (is_group:false) — offset from the character panel origin, shared
const OBJECTS: Array[Dictionary] = [
	# ── Character groups ──────────────────────────────────────────────────────
	{"name": "Brawler",    "is_group": true,  "char_idx": 0,
	 "x_key": "char_0_x", "y_key": "char_0_y", "w_key": "char_0_w", "h_key": "char_0_h"},
	{"name": "Burglar",    "is_group": true,  "char_idx": 1,
	 "x_key": "char_1_x", "y_key": "char_1_y", "w_key": "char_1_w", "h_key": "char_1_h"},
	{"name": "Hacker",     "is_group": true,  "char_idx": 2,
	 "x_key": "char_2_x", "y_key": "char_2_y", "w_key": "char_2_w", "h_key": "char_2_h"},
	# ── Sub-elements (offset relative to panel origin) ────────────────────────
	{"name": "Avatar",     "is_group": false,
	 "x_key": "avatar_ox",    "y_key": "avatar_oy",    "w_key": "avatar_w",    "h_key": "avatar_h"},
	{"name": "Name Label", "is_group": false,
	 "x_key": "name_ox",      "y_key": "name_oy",      "w_key": "name_w",      "h_key": "name_h"},
	{"name": "Time Label", "is_group": false,
	 "x_key": "time_lbl_ox",  "y_key": "time_lbl_oy",  "w_key": "time_lbl_w",  "h_key": "time_lbl_h"},
	{"name": "Time Bar",   "is_group": false,
	 "x_key": "time_bar_ox",  "y_key": "time_bar_oy",  "w_key": "time_bar_w",  "h_key": "time_bar_h"},
	{"name": "Time Fill",  "is_group": false,
	 "x_key": "time_fill_ox", "y_key": "time_fill_oy", "w_key": "time_fill_w", "h_key": "time_fill_h"},
	{"name": "Time Mark",  "is_group": false,
	 "x_key": "time_mark_ox", "y_key": "time_mark_oy", "w_key": "time_mark_w", "h_key": "time_mark_h"},
]

static func _lf(d: Dictionary, key: String, def: float) -> float:
	return float(d.get(key, def))


var active: bool = false

var _hud: HUD = null
var _working: Dictionary = {}
var _undo_stack: Array = []
var _sel: int = 0
var _updating: bool = false

var _ui: CanvasLayer = null
var _overlay: Control = null
var _obj_btns: Array = []
var _x_edit: LineEdit = null
var _y_edit: LineEdit = null
var _w_edit: LineEdit = null
var _h_edit: LineEdit = null
var _exit_dlg: ConfirmationDialog = null

# Drag state
var _drag_active: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_x: float = 0.0
var _drag_start_y: float = 0.0


func init(hud: HUD) -> void:
	_hud = hud


func toggle() -> void:
	if active:
		_show_exit_dlg()
	else:
		_enter()


func _enter() -> void:
	active = true
	_working = _hud.layout.duplicate(true)
	_undo_stack.clear()
	_sel = 0
	_drag_active = false
	_build_ui()
	_highlight_sel()
	_fill_inputs()


func _do_save() -> void:
	_hud.apply_layout(_working)
	_hud.save_layout()
	active = false
	_teardown_ui()


func _do_discard() -> void:
	_hud.preview_layout(_hud.layout)
	active = false
	_teardown_ui()


# ── UI construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 100
	add_child(_ui)

	# Full-screen overlay — draws selection outlines and handles drag
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	_overlay.draw.connect(_draw_overlay)
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_ui.add_child(_overlay)

	# ── Left panel ──────────────────────────────────────────────────────────
	var lp := PanelContainer.new()
	lp.position = Vector2(0, 0)
	lp.size = Vector2(200, 720)
	_ui.add_child(lp)

	var lv := VBoxContainer.new()
	lv.set_anchors_preset(Control.PRESET_FULL_RECT)
	lv.add_theme_constant_override("separation", 4)
	lp.add_child(lv)

	var title := Label.new()
	title.text = "HUD Editor  [F7]"
	title.add_theme_font_size_override("font_size", 13)
	lv.add_child(title)
	lv.add_child(HSeparator.new())

	_obj_btns.clear()

	# Groups section
	var grp_lbl := Label.new()
	grp_lbl.text = "Character Groups"
	grp_lbl.add_theme_font_size_override("font_size", 11)
	grp_lbl.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	lv.add_child(grp_lbl)

	for i in OBJECTS.size():
		var o: Dictionary = OBJECTS[i]
		if i == 3:
			lv.add_child(HSeparator.new())
			var el_lbl := Label.new()
			el_lbl.text = "Elements (offset)"
			el_lbl.add_theme_font_size_override("font_size", 11)
			el_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
			lv.add_child(el_lbl)
		var btn := Button.new()
		btn.text = o["name"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func(idx = i): _select(idx))
		lv.add_child(btn)
		_obj_btns.append(btn)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(sp)
	lv.add_child(HSeparator.new())

	var ubtn := Button.new()
	ubtn.text = "Undo  (Ctrl+Z)"
	ubtn.pressed.connect(_undo)
	lv.add_child(ubtn)

	var sbtn := Button.new()
	sbtn.text = "Save"
	sbtn.pressed.connect(_do_save)
	lv.add_child(sbtn)

	var xbtn := Button.new()
	xbtn.text = "Exit  (F7)"
	xbtn.pressed.connect(_show_exit_dlg)
	lv.add_child(xbtn)

	# ── Right panel ─────────────────────────────────────────────────────────
	var rp := PanelContainer.new()
	rp.position = Vector2(1280 - 215, 0)
	rp.size = Vector2(215, 240)
	_ui.add_child(rp)

	var rv := VBoxContainer.new()
	rv.set_anchors_preset(Control.PRESET_FULL_RECT)
	rv.add_theme_constant_override("separation", 4)
	rp.add_child(rv)

	var ptitle := Label.new()
	ptitle.text = "Properties"
	ptitle.add_theme_font_size_override("font_size", 13)
	rv.add_child(ptitle)
	rv.add_child(HSeparator.new())

	_x_edit = _make_row(rv, "X", "x")
	_y_edit = _make_row(rv, "Y", "y")
	_w_edit = _make_row(rv, "W", "w")
	_h_edit = _make_row(rv, "H", "h")

	_x_edit.text_submitted.connect(func(t): _submit("x", t))
	_y_edit.text_submitted.connect(func(t): _submit("y", t))
	_w_edit.text_submitted.connect(func(t): _submit("w", t))
	_h_edit.text_submitted.connect(func(t): _submit("h", t))
	_x_edit.focus_exited.connect(func(): _submit("x", _x_edit.text))
	_y_edit.focus_exited.connect(func(): _submit("y", _y_edit.text))
	_w_edit.focus_exited.connect(func(): _submit("w", _w_edit.text))
	_h_edit.focus_exited.connect(func(): _submit("h", _h_edit.text))

	var hint := Label.new()
	hint.text = "Drag group/element\nto move"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	rv.add_child(hint)

	# ── Exit dialog ─────────────────────────────────────────────────────────
	_exit_dlg = ConfirmationDialog.new()
	_exit_dlg.title = "Exit HUD Editor"
	_exit_dlg.dialog_text = "Save changes before exiting?"
	_exit_dlg.ok_button_text = "Save"
	_exit_dlg.cancel_button_text = "Cancel"
	_exit_dlg.confirmed.connect(_do_save)
	_exit_dlg.add_button("Discard", true, "discard")
	_exit_dlg.custom_action.connect(func(action: StringName):
		if action == "discard":
			_exit_dlg.hide()
			_do_discard()
	)
	_ui.add_child(_exit_dlg)


func _make_row(parent: VBoxContainer, label: String, field: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label + " :"
	lbl.custom_minimum_size = Vector2(30, 0)
	row.add_child(lbl)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var up_btn := Button.new()
	up_btn.text = "▲"
	up_btn.custom_minimum_size = Vector2(22, 14)
	up_btn.add_theme_font_size_override("font_size", 9)
	col.add_child(up_btn)
	var dn_btn := Button.new()
	dn_btn.text = "▼"
	dn_btn.custom_minimum_size = Vector2(22, 14)
	dn_btn.add_theme_font_size_override("font_size", 9)
	col.add_child(dn_btn)
	up_btn.pressed.connect(func(): _step(field, 1.0))
	dn_btn.pressed.connect(func(): _step(field, -1.0))
	return edit


func _step(field: String, delta: float) -> void:
	var o: Dictionary = OBJECTS[_sel]
	var key := _field_key(o, field)
	if key.is_empty():
		return
	_push_undo()
	_working[key] = _lf(_working, key, 0.0) + delta
	_hud.preview_layout(_working)
	_fill_inputs()
	if _overlay:
		_overlay.queue_redraw()


func _teardown_ui() -> void:
	if _ui:
		_ui.queue_free()
		_ui = null
	_overlay = null
	_obj_btns.clear()
	_x_edit = null; _y_edit = null; _w_edit = null; _h_edit = null
	_exit_dlg = null


# ── Selection & input ──────────────────────────────────────────────────────────

func _select(idx: int) -> void:
	_sel = idx
	_drag_active = false
	_highlight_sel()
	_fill_inputs()
	if _overlay:
		_overlay.queue_redraw()


func _highlight_sel() -> void:
	for i in _obj_btns.size():
		_obj_btns[i].modulate = Color(1.0, 1.0, 0.25) if i == _sel else Color.WHITE


func _fill_inputs() -> void:
	if _updating or _x_edit == null:
		return
	_updating = true
	var o: Dictionary = OBJECTS[_sel]
	_x_edit.text = "%.1f" % _lf(_working, str(o.get("x_key", "")), 0.0)
	_y_edit.text = "%.1f" % _lf(_working, str(o.get("y_key", "")), 0.0)
	_w_edit.text = "%.1f" % _lf(_working, str(o.get("w_key", "")), 0.0)
	_h_edit.text = "%.1f" % _lf(_working, str(o.get("h_key", "")), 0.0)
	_updating = false


func _submit(field: String, text: String) -> void:
	if _updating:
		return
	var val := text.to_float()
	var o: Dictionary = OBJECTS[_sel]
	var key := _field_key(o, field)
	if key.is_empty():
		return
	if absf(val - _lf(_working, key, 0.0)) < 0.01:
		return
	_push_undo()
	_working[key] = val
	_hud.preview_layout(_working)
	if _overlay:
		_overlay.queue_redraw()


func _field_key(o: Dictionary, field: String) -> String:
	match field:
		"x": return str(o.get("x_key", ""))
		"y": return str(o.get("y_key", ""))
		"w": return str(o.get("w_key", ""))
		"h": return str(o.get("h_key", ""))
	return ""


func _push_undo() -> void:
	_undo_stack.append(_working.duplicate(true))
	if _undo_stack.size() > 64:
		_undo_stack.pop_front()


func _undo() -> void:
	if _undo_stack.is_empty():
		return
	_working = _undo_stack.pop_back()
	_hud.preview_layout(_working)
	_fill_inputs()
	if _overlay:
		_overlay.queue_redraw()


func _show_exit_dlg() -> void:
	if _exit_dlg:
		_exit_dlg.popup_centered()


# ── Drag ──────────────────────────────────────────────────────────────────────

func _on_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_start_drag(event.position)
		else:
			_drag_active = false
	elif event is InputEventMouseMotion and _drag_active:
		_update_drag(event.position)


func _try_start_drag(mouse_pos: Vector2) -> void:
	var o_sel: Dictionary = OBJECTS[_sel]
	var rects := _get_object_rects(o_sel)
	for r in rects:
		if r.has_point(mouse_pos):
			_push_undo()
			_drag_active = true
			_drag_start_mouse = mouse_pos
			_drag_start_x = _lf(_working, str(o_sel.get("x_key", "")), 0.0)
			_drag_start_y = _lf(_working, str(o_sel.get("y_key", "")), 0.0)
			return


func _update_drag(mouse_pos: Vector2) -> void:
	var delta: Vector2 = mouse_pos - _drag_start_mouse
	var o: Dictionary = OBJECTS[_sel]
	_working[str(o.get("x_key", ""))] = _drag_start_x + delta.x
	_working[str(o.get("y_key", ""))] = _drag_start_y + delta.y
	_hud.preview_layout(_working)
	_fill_inputs()
	if _overlay:
		_overlay.queue_redraw()


func _get_object_rects(o: Dictionary) -> Array:
	var rects: Array = []
	var lay: Dictionary = _working
	if o.get("is_group", false):
		var i: int = int(o.get("char_idx", 0))
		var px: float = _lf(lay, "char_%d_x" % i, 170.0 + float(i) * 320.0)
		var py: float = _lf(lay, "char_%d_y" % i, 595.0)
		var pw: float = _lf(lay, "char_%d_w" % i, 300.0)
		var ph: float = _lf(lay, "char_%d_h" % i,  80.0)
		rects.append(Rect2(px, py, pw, ph))
	else:
		var xk: String = str(o.get("x_key", ""))
		var yk: String = str(o.get("y_key", ""))
		var wk: String = str(o.get("w_key", ""))
		var hk: String = str(o.get("h_key", ""))
		var ox: float = _lf(lay, xk, 0.0)
		var oy: float = _lf(lay, yk, 0.0)
		var ow: float = _lf(lay, wk, 100.0)
		var oh: float = _lf(lay, hk,  20.0)
		for j in 3:
			var px: float = _lf(lay, "char_%d_x" % j, 170.0 + float(j) * 320.0)
			var py: float = _lf(lay, "char_%d_y" % j, 595.0)
			rects.append(Rect2(px + ox, py + oy, ow, oh))
	return rects


# ── Overlay drawing ────────────────────────────────────────────────────────────

func _draw_overlay() -> void:
	var o: Dictionary = OBJECTS[_sel]
	var rects := _get_object_rects(o)
	var col_sel  := Color(0.2, 0.95, 1.0, 0.9)
	var col_dim  := Color(1.0, 1.0, 1.0, 0.15)

	# Draw all non-selected group rects as dim outlines for reference
	for i in OBJECTS.size():
		if i == _sel:
			continue
		var other: Dictionary = OBJECTS[i]
		if not other.get("is_group", false):
			continue
		for r in _get_object_rects(other):
			_overlay.draw_rect(r, col_dim, false, 1.0)

	# Draw selected object
	for r in rects:
		_overlay.draw_rect(r, col_sel, false, 2.0)
		# Corner handles
		for corner in [r.position,
				r.position + Vector2(r.size.x, 0),
				r.position + Vector2(0, r.size.y),
				r.position + r.size]:
			_overlay.draw_rect(Rect2(corner - Vector2(4, 4), Vector2(8, 8)), col_sel, true)


# ── Input ──────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F7:
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	if event.keycode == KEY_Z and event.ctrl_pressed:
		_undo()
		get_viewport().set_input_as_handled()
