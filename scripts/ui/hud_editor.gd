class_name HUDEditor
extends CanvasLayer

signal closed()

const GIZMO_BORDER     := Color(1.0, 0.78, 0.0, 0.85)
const GIZMO_FILL       := Color(1.0, 0.78, 0.0, 0.07)
const GIZMO_BORDER_SEL := Color(0.25, 0.85, 1.0, 1.0)
const GIZMO_FILL_SEL   := Color(0.25, 0.85, 1.0, 0.14)
const HANDLE_COLOR     := Color(1.0, 1.0, 1.0, 0.90)
const HANDLE_SZ        := 10.0
const MIN_SZ           := Vector2(20.0, 10.0)

var _hud: HUD
var _elements: Array = []   # [{node:Control, name:String, resizable:bool}]
var _gizmos:   Array = []   # Control, parallel to _elements

var _undo_stack: Array = [] # Array[Array[{pos,sz}]]
var _dirty := false

var _drag_mode   := 0   # 0=none  1=move  2=resize
var _drag_idx    := -1
var _drag_corner := -1  # 0=TL 1=TR 2=BL 3=BR
var _drag_start_mouse := Vector2.ZERO
var _drag_start_pos   := Vector2.ZERO
var _drag_start_size  := Vector2.ZERO

var _selected_idx := -1
var _list_buttons: Array = []
var _spinboxes: Dictionary = {}   # "x","y","w","h" -> SpinBox
var _inspector_title: Label
var _updating_inspector := false

var _undo_btn:   Button
var _dialog:     Control
var _left_panel: Control
var _inspector:  Control


func setup(hud: HUD) -> void:
	_hud  = hud
	layer = 11
	visible = false


func toggle() -> void:
	if visible:
		_try_close()
	else:
		_open()


# ── Open / close ──────────────────────────────────────────────────────────────

func _open() -> void:
	_elements = _hud.get_draggable_elements()
	_undo_stack.clear()
	_push_undo()
	_dirty = false
	_selected_idx = -1
	_build_overlay()
	_build_toolbar()
	_build_gizmos()
	_build_left_panel()
	_build_inspector()
	_build_dialog()
	visible = true


func _try_close() -> void:
	if _dirty:
		_dialog.visible = true
	else:
		_do_close()


func _do_close() -> void:
	_clear_children()
	_gizmos.clear()
	_list_buttons.clear()
	_spinboxes.clear()
	_undo_stack.clear()
	_dialog          = null
	_undo_btn        = null
	_left_panel      = null
	_inspector       = null
	_inspector_title = null
	visible          = false
	closed.emit()


func _clear_children() -> void:
	for ch in get_children():
		ch.queue_free()


# ── Overlay ───────────────────────────────────────────────────────────────────

func _build_overlay() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.22)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)


# ── Toolbar ───────────────────────────────────────────────────────────────────

func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.position = Vector2(10.0, 10.0)
	add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	bar.add_child(hbox)

	var title := Label.new()
	title.text = "  HUD Editor  —  F7 to exit  "
	title.add_theme_font_size_override("font_size", 13)
	hbox.add_child(title)

	_undo_btn = Button.new()
	_undo_btn.text = "Undo"
	_undo_btn.disabled = true
	_undo_btn.pressed.connect(_do_undo)
	hbox.add_child(_undo_btn)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_do_save)
	hbox.add_child(save_btn)

	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.pressed.connect(_try_close)
	hbox.add_child(exit_btn)


# ── Gizmos ────────────────────────────────────────────────────────────────────

func _build_gizmos() -> void:
	for i in _elements.size():
		var elem: Dictionary = _elements[i]
		var g := _make_gizmo(elem["name"], elem.get("resizable", false))
		_sync_gizmo(g, elem["node"] as Control)
		add_child(g)
		_gizmos.append(g)


func _make_gizmo(label_text: String, resizable: bool) -> Control:
	var g := Control.new()
	g.mouse_filter = Control.MOUSE_FILTER_PASS
	g.set_meta("resizable", resizable)

	var style := StyleBoxFlat.new()
	style.bg_color     = GIZMO_FILL
	style.border_color = GIZMO_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	g.set_meta("style", style)

	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", style)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(bg)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.position = Vector2(6.0, 2.0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", GIZMO_BORDER)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.set_meta("label", lbl)
	g.add_child(lbl)

	if resizable:
		for ci in 4:
			var h := ColorRect.new()
			h.size  = Vector2(HANDLE_SZ, HANDLE_SZ)
			h.color = HANDLE_COLOR
			h.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.set_meta("corner", ci)
			g.add_child(h)

	return g


func _sync_gizmo(g: Control, node: Control) -> void:
	g.position = node.position
	g.size     = node.size
	if g.get_meta("resizable", false):
		_place_corners(g)


func _place_corners(g: Control) -> void:
	var sz := g.size
	var offsets := [
		Vector2(0.0,              0.0),
		Vector2(sz.x - HANDLE_SZ, 0.0),
		Vector2(0.0,              sz.y - HANDLE_SZ),
		Vector2(sz.x - HANDLE_SZ, sz.y - HANDLE_SZ),
	]
	var ci := 0
	for ch in g.get_children():
		if ch.has_meta("corner"):
			ch.position = offsets[ci]
			ci += 1


# ── Left panel (object list) ──────────────────────────────────────────────────

func _build_left_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(10.0, 50.0)
	panel.custom_minimum_size = Vector2(155.0, 0.0)
	add_child(panel)
	_left_panel = panel

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "Objects"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 12)
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	_list_buttons.clear()
	for i in _elements.size():
		var elem: Dictionary = _elements[i]
		var btn := Button.new()
		btn.text = elem["name"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_select.bind(i))
		vbox.add_child(btn)
		_list_buttons.append(btn)


# ── Right panel (inspector) ───────────────────────────────────────────────────

func _build_inspector() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(155.0, 0.0)
	add_child(panel)
	_inspector = panel

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	_inspector_title = Label.new()
	_inspector_title.text = "—"
	_inspector_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inspector_title.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_inspector_title)

	vbox.add_child(HSeparator.new())

	var fields: Array[String] = ["X",      "Y",      "W",      "H",      "Font"]
	var keys:   Array[String] = ["x",      "y",      "w",      "h",      "f"]
	var mins:   Array[float]  = [-4000.0, -4000.0, -4000.0, -4000.0,    6.0]
	var maxs:   Array[float]  = [ 4000.0,  4000.0,  4000.0,  4000.0,   72.0]
	for fi in fields.size():
		var row := HBoxContainer.new()
		vbox.add_child(row)

		var lbl := Label.new()
		lbl.text = fields[fi]
		lbl.custom_minimum_size = Vector2(28.0, 0.0)
		lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(lbl)

		var sb := SpinBox.new()
		sb.min_value = mins[fi]
		sb.max_value = maxs[fi]
		sb.step = 1.0
		sb.custom_minimum_size = Vector2(108.0, 0.0)
		sb.editable = false
		row.add_child(sb)

		var key: String = keys[fi]
		_spinboxes[key] = sb
		sb.value_changed.connect(_on_spinbox_changed.bind(key))

	call_deferred("_reposition_inspector")


func _reposition_inspector() -> void:
	if _inspector == null or not is_instance_valid(_inspector):
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vp_w := vp.get_visible_rect().size.x
	_inspector.position = Vector2(vp_w - _inspector.size.x - 10.0, 50.0)


# ── Selection ─────────────────────────────────────────────────────────────────

func _select(idx: int) -> void:
	_selected_idx = idx
	_update_list_highlight()
	_update_inspector()
	_update_gizmo_highlight()


func _update_list_highlight() -> void:
	for i in _list_buttons.size():
		var btn := _list_buttons[i] as Button
		if i == _selected_idx:
			btn.add_theme_color_override("font_color", Color(0.25, 0.85, 1.0))
		else:
			btn.remove_theme_color_override("font_color")


func _update_inspector() -> void:
	if _selected_idx < 0 or _selected_idx >= _elements.size():
		_inspector_title.text = "—"
		for sb: SpinBox in _spinboxes.values():
			sb.editable = false
		return

	var elem: Dictionary = _elements[_selected_idx]
	var node: Control = elem["node"]
	_inspector_title.text = elem["name"]
	_spinboxes["x"].editable = true
	_spinboxes["y"].editable = true
	_spinboxes["w"].editable = true
	_spinboxes["h"].editable = true

	var has_font := elem.has("get_font_size") and elem["get_font_size"] is Callable
	_spinboxes["f"].editable = has_font
	if has_font:
		_updating_inspector = true
		_spinboxes["f"].value = float((elem["get_font_size"] as Callable).call())
		_updating_inspector = false

	_set_spinbox_values(node.position, node.size)


func _set_spinbox_values(pos: Vector2, sz: Vector2) -> void:
	_updating_inspector = true
	_spinboxes["x"].value = roundi(pos.x)
	_spinboxes["y"].value = roundi(pos.y)
	_spinboxes["w"].value = roundi(sz.x)
	_spinboxes["h"].value = roundi(sz.y)
	_updating_inspector = false


func _update_gizmo_highlight() -> void:
	for i in _gizmos.size():
		var g: Control = _gizmos[i]
		var style: StyleBoxFlat = g.get_meta("style")
		var lbl: Label = g.get_meta("label")
		if i == _selected_idx:
			style.bg_color     = GIZMO_FILL_SEL
			style.border_color = GIZMO_BORDER_SEL
			lbl.add_theme_color_override("font_color", GIZMO_BORDER_SEL)
		else:
			style.bg_color     = GIZMO_FILL
			style.border_color = GIZMO_BORDER
			lbl.add_theme_color_override("font_color", GIZMO_BORDER)


func _on_spinbox_changed(value: float, key: String) -> void:
	if _updating_inspector:
		return
	if _selected_idx < 0 or _selected_idx >= _elements.size():
		return

	if key == "f":
		var elem: Dictionary = _elements[_selected_idx]
		if elem.has("set_font_size") and elem["set_font_size"] is Callable:
			(elem["set_font_size"] as Callable).call(int(value))
			_dirty = true
		return

	_push_undo()
	var node: Control = _elements[_selected_idx]["node"]
	match key:
		"x": node.position.x = value
		"y": node.position.y = value
		"w": node.size.x = maxf(value, MIN_SZ.x)
		"h": node.size.y = maxf(value, MIN_SZ.y)
	_dirty = true
	_fire_on_change(_selected_idx)
	_resync_all_gizmos()
	_set_spinbox_values(node.position, node.size)


# ── Input ─────────────────────────────────────────────────────────────────────

func _point_in_ui_panels(mpos: Vector2) -> bool:
	if _left_panel != null and _left_panel.get_global_rect().has_point(mpos):
		return true
	if _inspector != null and _inspector.get_global_rect().has_point(mpos):
		return true
	# Also check the toolbar (any PanelContainer that isn't left/inspector)
	for ch in get_children():
		if ch is PanelContainer and ch != _left_panel and ch != _inspector:
			if (ch as Control).get_global_rect().has_point(mpos):
				return true
	return false


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F7:
			get_viewport().set_input_as_handled()
			if _dialog == null or not _dialog.visible:
				_try_close()
			return

	# While dialog is open let mouse events reach the Button nodes (GUI processes after _input)
	if _dialog != null and _dialog.visible:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _point_in_ui_panels(mb.global_position):
				return
			get_viewport().set_input_as_handled()
			if mb.pressed:
				_mouse_down(mb.global_position)
			else:
				_mouse_up()

	if event is InputEventMouseMotion and _drag_mode != 0:
		get_viewport().set_input_as_handled()
		_mouse_move((event as InputEventMouseMotion).global_position)


func _mouse_down(mpos: Vector2) -> void:
	# Top-most gizmo first (reverse order)
	for i in range(_gizmos.size() - 1, -1, -1):
		var g: Control = _gizmos[i]
		if not Rect2(g.position, g.size).has_point(mpos):
			continue

		# Resize corner?
		if g.get_meta("resizable", false):
			for ch in g.get_children():
				if not ch.has_meta("corner"):
					continue
				if Rect2(g.position + ch.position, ch.size).has_point(mpos):
					_select(i)
					_push_undo()
					_drag_mode   = 2
					_drag_idx    = i
					_drag_corner = ch.get_meta("corner")
					_drag_start_mouse = mpos
					_drag_start_pos   = g.position
					_drag_start_size  = g.size
					return

		# Move
		_select(i)
		_push_undo()
		_drag_mode = 1
		_drag_idx  = i
		_drag_start_mouse = mpos
		_drag_start_pos   = (_elements[i]["node"] as Control).position
		return

	# Clicked empty space — deselect
	_select(-1)


func _mouse_up() -> void:
	if _drag_mode != 0:
		_dirty = true
	_drag_mode = 0
	_drag_idx  = -1


func _mouse_move(mpos: Vector2) -> void:
	if _drag_idx < 0:
		return
	var node: Control = _elements[_drag_idx]["node"]
	var d := mpos - _drag_start_mouse

	if _drag_mode == 1:
		node.position = _drag_start_pos + d

	elif _drag_mode == 2:
		var npos := _drag_start_pos
		var nsz  := _drag_start_size
		match _drag_corner:
			0:  # TL
				npos = _drag_start_pos + d
				nsz  = _drag_start_size - d
			1:  # TR
				npos.y = _drag_start_pos.y + d.y
				nsz.x  = _drag_start_size.x + d.x
				nsz.y  = _drag_start_size.y - d.y
			2:  # BL
				npos.x = _drag_start_pos.x + d.x
				nsz.x  = _drag_start_size.x - d.x
				nsz.y  = _drag_start_size.y + d.y
			3:  # BR
				nsz = _drag_start_size + d
		nsz           = nsz.max(MIN_SZ)
		node.position = npos
		node.size     = nsz

	_fire_on_change(_drag_idx)
	_resync_all_gizmos()
	if _selected_idx == _drag_idx:
		_set_spinbox_values(node.position, node.size)


# ── Undo ──────────────────────────────────────────────────────────────────────

func _push_undo() -> void:
	var snap: Array = []
	for elem in _elements:
		var n: Control = elem["node"]
		snap.append({"pos": n.position, "sz": n.size})
	_undo_stack.append(snap)
	_refresh_undo_btn()


func _do_undo() -> void:
	if _undo_stack.size() <= 1:
		return
	_undo_stack.pop_back()
	var snap: Array = _undo_stack.back()
	for i in _elements.size():
		var n: Control = _elements[i]["node"]
		n.position = snap[i]["pos"]
		n.size     = snap[i]["sz"]
	_fire_all_on_change()
	_resync_all_gizmos()
	_dirty = _undo_stack.size() > 1
	_refresh_undo_btn()
	if _selected_idx >= 0 and _selected_idx < _elements.size():
		var node: Control = _elements[_selected_idx]["node"]
		_set_spinbox_values(node.position, node.size)


func _refresh_undo_btn() -> void:
	if _undo_btn:
		_undo_btn.disabled = _undo_stack.size() <= 1


func _fire_on_change(idx: int) -> void:
	if idx < 0 or idx >= _elements.size():
		return
	var elem: Dictionary = _elements[idx]
	if elem.has("on_change") and elem["on_change"] is Callable:
		elem["on_change"].call()


func _fire_all_on_change() -> void:
	for elem in _elements:
		if elem.has("on_change") and elem["on_change"] is Callable:
			elem["on_change"].call()


func _resync_all_gizmos() -> void:
	for i in _gizmos.size():
		_sync_gizmo(_gizmos[i], _elements[i]["node"] as Control)


func _do_save() -> void:
	_hud.save_layout()
	_dirty = false


# ── Exit dialog ───────────────────────────────────────────────────────────────

func _build_dialog() -> void:
	_dialog = Control.new()
	_dialog.visible = false
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dialog)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialog.add_child(dim)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300.0, 0.0)
	panel.position = Vector2(490.0, 290.0)
	_dialog.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Unsaved Changes"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var msg := Label.new()
	msg.text = "Save layout before exiting?"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(msg)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	vbox.add_child(hbox)

	var discard_btn := Button.new()
	discard_btn.text = "Discard"
	discard_btn.pressed.connect(_dialog_discard)
	hbox.add_child(discard_btn)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_dialog_save)
	hbox.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): _dialog.visible = false)
	hbox.add_child(cancel_btn)


func _dialog_discard() -> void:
	_dialog.visible = false
	if _undo_stack.size() > 0:
		var original: Array = _undo_stack[0]
		for i in _elements.size():
			var n: Control = _elements[i]["node"]
			n.position = original[i]["pos"]
			n.size     = original[i]["sz"]
	_do_close()


func _dialog_save() -> void:
	_dialog.visible = false
	_do_save()
	_do_close()
