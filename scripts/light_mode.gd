extends Node2D

@export var helper_color: Color = Color(1, 0.95, 0.4, 0.75)
@export var selection_color: Color = Color(0.4, 1, 0.7, 0.95)

var active: bool = false
var selected: Node2D = null
var dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

var _ui_layer: CanvasLayer = null
var _ui_panel: PanelContainer = null
var _ui_list: VBoxContainer = null
var _selected_label: Label = null
var _energy_slider: HSlider = null
var _height_slider: HSlider = null
var _rotation_slider: HSlider = null
var _texture_scale_slider: HSlider = null
var _color_r: HSlider = null
var _color_g: HSlider = null
var _color_b: HSlider = null
var _opacity_slider: HSlider = null
var _opacity_value_label: Label = null
var _opacity_row: VBoxContainer = null
var _rotation_row: VBoxContainer = null
var _rotation_value_label: Label = null
var _energy_value_label: Label = null
var _height_value_label: Label = null
var _texture_scale_row: VBoxContainer = null


func _ready() -> void:
	z_index = 4096
	set_process(false)
	_build_ui()
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			_toggle()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_F4:
			return

	if not active:
		return

	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_DELETE and selected:
				_delete_selected()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and selected:
				dragging = true
				drag_offset = selected.global_position - get_global_mouse_position()
			else:
				if dragging:
					_persist()
				dragging = false
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if dragging and selected:
			selected.global_position = get_global_mouse_position() + drag_offset
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	active = not active
	if active:
		_disable_other_modes()
		_refresh_light_list()
		_update_properties()
	else:
		selected = null
		dragging = false
	set_process(active)
	if _ui_panel:
		_ui_panel.visible = active
	queue_redraw()


func _disable_other_modes() -> void:
	var em := get_node_or_null("../EditMode")
	if em and em.get("active"):
		em.call("_toggle")


func _persist() -> void:
	var owner_node := get_owner()
	if owner_node and owner_node.has_method("save_light_edits"):
		owner_node.call_deferred("save_light_edits")


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 100
	add_child(_ui_layer)

	_ui_panel = PanelContainer.new()
	_ui_panel.anchor_left = 1.0
	_ui_panel.anchor_right = 1.0
	_ui_panel.offset_left = -228
	_ui_panel.offset_right = -8
	_ui_panel.offset_top = 8
	_ui_panel.visible = false
	_ui_layer.add_child(_ui_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_ui_panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)

	var title := Label.new()
	title.text = "Lights (F5)"
	title.add_theme_font_size_override("font_size", 12)
	v.add_child(title)

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	v.add_child(add_row)
	var add_dir := Button.new()
	add_dir.text = "+ Directional"
	add_dir.pressed.connect(_add_directional_light)
	add_row.add_child(add_dir)
	var add_pt := Button.new()
	add_pt.text = "+ Point"
	add_pt.pressed.connect(_add_point_light)
	add_row.add_child(add_pt)

	v.add_child(HSeparator.new())

	_ui_list = VBoxContainer.new()
	_ui_list.add_theme_constant_override("separation", 2)
	v.add_child(_ui_list)

	v.add_child(HSeparator.new())

	_selected_label = Label.new()
	_selected_label.text = "(none)"
	_selected_label.add_theme_font_size_override("font_size", 11)
	v.add_child(_selected_label)

	var energy_pair := _add_property_slider_with_value(v, "Energy", 0.0, 4.0, 0.05, _on_energy_changed, "%.2f")
	_energy_slider = energy_pair[0]
	_energy_value_label = energy_pair[1]
	var height_pair := _add_property_slider_with_value(v, "Height", 0.0, 2.0, 0.05, _on_height_changed, "%.2f")
	_height_slider = height_pair[0]
	_height_value_label = height_pair[1]

	_rotation_row = VBoxContainer.new()
	v.add_child(_rotation_row)
	var rot_header := HBoxContainer.new()
	rot_header.add_theme_constant_override("separation", 6)
	_rotation_row.add_child(rot_header)
	var rot_lbl := Label.new()
	rot_lbl.text = "Rotation (deg)"
	rot_lbl.add_theme_font_size_override("font_size", 11)
	rot_header.add_child(rot_lbl)
	_rotation_value_label = Label.new()
	_rotation_value_label.text = "0"
	_rotation_value_label.add_theme_font_size_override("font_size", 11)
	_rotation_value_label.add_theme_color_override("font_color", Color(1, 1, 0.4))
	rot_header.add_child(_rotation_value_label)
	_rotation_slider = HSlider.new()
	_rotation_slider.min_value = -180.0
	_rotation_slider.max_value = 180.0
	_rotation_slider.step = 1.0
	_rotation_slider.value_changed.connect(_on_rotation_changed)
	_rotation_row.add_child(_rotation_slider)

	_texture_scale_row = VBoxContainer.new()
	v.add_child(_texture_scale_row)
	_texture_scale_slider = _add_property_slider(_texture_scale_row, "Range (texture_scale)", 0.5, 5.0, 0.1, _on_texture_scale_changed)

	var color_label := Label.new()
	color_label.text = "Color (R / G / B)"
	v.add_child(color_label)
	_color_r = HSlider.new()
	_color_r.min_value = 0.0
	_color_r.max_value = 1.0
	_color_r.step = 0.01
	_color_r.value_changed.connect(_on_color_changed)
	v.add_child(_color_r)
	_color_g = HSlider.new()
	_color_g.min_value = 0.0
	_color_g.max_value = 1.0
	_color_g.step = 0.01
	_color_g.value_changed.connect(_on_color_changed)
	v.add_child(_color_g)
	_color_b = HSlider.new()
	_color_b.min_value = 0.0
	_color_b.max_value = 1.0
	_color_b.step = 0.01
	_color_b.value_changed.connect(_on_color_changed)
	v.add_child(_color_b)

	_opacity_row = VBoxContainer.new()
	v.add_child(_opacity_row)
	var op_pair := _add_property_slider_with_value(_opacity_row, "Opacity", 0.0, 1.0, 0.01, _on_opacity_changed, "%.2f")
	_opacity_slider = op_pair[0]
	_opacity_value_label = op_pair[1]

	v.add_child(HSeparator.new())

	var del_btn := Button.new()
	del_btn.text = "Delete Selected"
	del_btn.pressed.connect(_delete_selected)
	v.add_child(del_btn)


func _add_property_slider(parent: Node, label_text: String, lo: float, hi: float, step: float, cb: Callable) -> HSlider:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	parent.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value_changed.connect(cb)
	parent.add_child(sl)
	return sl


func _add_property_slider_with_value(parent: Node, label_text: String, lo: float, hi: float, step: float, cb: Callable, fmt: String) -> Array:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	parent.add_child(header)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	header.add_child(lbl)
	var val := Label.new()
	val.text = fmt % lo
	val.add_theme_font_size_override("font_size", 11)
	val.add_theme_color_override("font_color", Color(1, 1, 0.4))
	header.add_child(val)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value_changed.connect(cb)
	parent.add_child(sl)
	return [sl, val]


func _refresh_light_list() -> void:
	if _ui_list == null:
		return
	for c in _ui_list.get_children():
		c.queue_free()
	var lighting := get_node_or_null("../Lighting")
	if lighting == null:
		return
	for n in lighting.get_children():
		if n is Light2D:
			_add_light_row(n)
			for child in n.get_children():
				if child is CanvasItem and not (child is Light2D):
					_add_overlay_row(child)


func _add_light_row(light: Light2D) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_ui_list.add_child(row)

	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = light.enabled
	toggle.text = "●" if light.enabled else "○"
	toggle.custom_minimum_size = Vector2(24, 0)
	toggle.add_theme_font_size_override("font_size", 11)
	toggle.tooltip_text = "Bật/tắt nguồn sáng"
	toggle.toggled.connect(_on_light_toggled.bind(light))
	row.add_child(toggle)

	var btn := Button.new()
	var kind := "Dir" if light is DirectionalLight2D else ("Pt" if light is PointLight2D else "L2D")
	btn.text = "[%s] %s" % [kind, str(light.name)]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.toggle_mode = true
	btn.button_pressed = (light == selected)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(_on_light_button_pressed.bind(light))
	row.add_child(btn)


func _add_overlay_row(node: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_ui_list.add_child(row)

	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = node.visible
	toggle.text = "●" if node.visible else "○"
	toggle.custom_minimum_size = Vector2(24, 0)
	toggle.add_theme_font_size_override("font_size", 11)
	toggle.tooltip_text = "Bật/tắt overlay"
	toggle.toggled.connect(_on_overlay_toggled.bind(node))
	row.add_child(toggle)

	var btn := Button.new()
	btn.text = "  └ %s" % str(node.name)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.toggle_mode = true
	btn.button_pressed = (node == selected)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	btn.pressed.connect(_on_overlay_select.bind(node))
	row.add_child(btn)


func _on_overlay_select(node: Node) -> void:
	if not is_instance_valid(node):
		_refresh_light_list()
		return
	if node is Node2D:
		selected = node as Node2D
	_refresh_light_list()
	_update_properties()
	queue_redraw()


func _on_light_toggled(pressed: bool, light: Node) -> void:
	if is_instance_valid(light) and light is Light2D:
		(light as Light2D).enabled = pressed
		_persist()
		_refresh_light_list()


func _on_overlay_toggled(pressed: bool, node: Node) -> void:
	if is_instance_valid(node) and node is CanvasItem:
		(node as CanvasItem).visible = pressed
		_persist()
		_refresh_light_list()


func _on_light_button_pressed(light: Node) -> void:
	if not is_instance_valid(light):
		_refresh_light_list()
		return
	if light is Node2D:
		selected = light as Node2D
	_refresh_light_list()
	_update_properties()
	queue_redraw()


func _update_properties() -> void:
	var has_sel := selected != null and is_instance_valid(selected)
	if _selected_label:
		_selected_label.text = ("Selected: %s" % str(selected.name)) if has_sel else "(none)"
	if not has_sel:
		_rotation_row.visible = false
		_texture_scale_row.visible = false
		_opacity_row.visible = false
		return
	var is_light: bool = selected is Light2D
	if is_light:
		var l := selected as Light2D
		_energy_slider.set_value_no_signal(l.energy)
		if _energy_value_label:
			_energy_value_label.text = "%.2f" % l.energy
		var hgt: float = l.height if "height" in l else 0.0
		_height_slider.set_value_no_signal(hgt)
		if _height_value_label:
			_height_value_label.text = "%.2f" % hgt
		var col: Color = l.color
		_color_r.set_value_no_signal(col.r)
		_color_g.set_value_no_signal(col.g)
		_color_b.set_value_no_signal(col.b)
	else:
		if selected is CanvasItem and (selected as CanvasItem).material is ShaderMaterial:
			var mat := (selected as CanvasItem).material as ShaderMaterial
			var ovc = mat.get_shader_parameter("cone_color")
			if ovc is Color:
				var c: Color = ovc
				_color_r.set_value_no_signal(c.r)
				_color_g.set_value_no_signal(c.g)
				_color_b.set_value_no_signal(c.b)
	var has_base_rot: bool = "base_rotation_deg" in selected
	_rotation_row.visible = selected is Node2D
	if _rotation_row.visible:
		var deg_val: float
		if has_base_rot:
			deg_val = float(selected.get("base_rotation_deg"))
		elif selected is DirectionalLight2D:
			deg_val = rad_to_deg(selected.rotation) + 90.0
		else:
			deg_val = rad_to_deg(selected.rotation)
		_rotation_slider.set_value_no_signal(deg_val)
		if _rotation_value_label:
			_rotation_value_label.text = "%d°" % int(round(deg_val))
	_texture_scale_row.visible = selected is PointLight2D
	if selected is PointLight2D:
		_texture_scale_slider.set_value_no_signal((selected as PointLight2D).texture_scale)
	_opacity_row.visible = selected is CanvasItem
	if selected is CanvasItem:
		var alpha: float = (selected as CanvasItem).modulate.a
		_opacity_slider.set_value_no_signal(alpha)
		if _opacity_value_label:
			_opacity_value_label.text = "%.2f" % alpha


func _on_energy_changed(v: float) -> void:
	if selected and is_instance_valid(selected) and selected is Light2D:
		(selected as Light2D).energy = v
	if _energy_value_label:
		_energy_value_label.text = "%.2f" % v
	_persist()


func _on_height_changed(v: float) -> void:
	if selected and is_instance_valid(selected) and "height" in selected:
		selected.set("height", v)
	if _height_value_label:
		_height_value_label.text = "%.2f" % v
	_persist()


func _on_opacity_changed(v: float) -> void:
	if selected and is_instance_valid(selected) and selected is CanvasItem:
		var ci := selected as CanvasItem
		var m: Color = ci.modulate
		m.a = v
		ci.modulate = m
	if _opacity_value_label:
		_opacity_value_label.text = "%.2f" % v
	_persist()


func _on_rotation_changed(v: float) -> void:
	if selected and is_instance_valid(selected):
		if "base_rotation_deg" in selected:
			selected.set("base_rotation_deg", v)
		elif selected is DirectionalLight2D:
			selected.rotation = deg_to_rad(v - 90.0)
		elif selected is Node2D:
			selected.rotation = deg_to_rad(v)
	if _rotation_value_label:
		_rotation_value_label.text = "%d°" % int(round(v))
	_persist()


func _on_texture_scale_changed(v: float) -> void:
	if selected and is_instance_valid(selected) and selected is PointLight2D:
		(selected as PointLight2D).texture_scale = v
	_persist()


func _on_color_changed(_v: float) -> void:
	if selected and is_instance_valid(selected):
		var rgb := Color(_color_r.value, _color_g.value, _color_b.value)
		if selected is Light2D:
			var l := selected as Light2D
			l.color = Color(rgb.r, rgb.g, rgb.b, l.color.a)
		elif selected is CanvasItem:
			var ci := selected as CanvasItem
			if ci.material is ShaderMaterial:
				var mat := ci.material as ShaderMaterial
				var prev_a: float = 1.0
				var prev = mat.get_shader_parameter("cone_color")
				if prev is Color:
					prev_a = (prev as Color).a
				mat.set_shader_parameter("cone_color", Color(rgb.r, rgb.g, rgb.b, prev_a))
	_persist()


func _add_directional_light() -> void:
	var lighting := get_node_or_null("../Lighting")
	if lighting == null:
		return
	var dl := DirectionalLight2D.new()
	dl.name = "DirLight"
	dl.energy = 1.0
	dl.height = 1.0
	dl.color = Color.WHITE
	lighting.add_child(dl)
	selected = dl
	_refresh_light_list()
	_update_properties()
	queue_redraw()
	_persist()


func _add_point_light() -> void:
	var lighting := get_node_or_null("../Lighting")
	if lighting == null:
		return
	var pl := PointLight2D.new()
	pl.name = "PointLight"
	pl.texture = _make_radial_texture()
	pl.energy = 1.0
	pl.height = 1.0
	pl.color = Color.WHITE
	pl.texture_scale = 2.0
	var cam := get_viewport().get_camera_2d()
	pl.position = cam.get_screen_center_position() if cam else Vector2.ZERO
	lighting.add_child(pl)
	selected = pl
	_refresh_light_list()
	_update_properties()
	queue_redraw()
	_persist()


func _make_radial_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


func _delete_selected() -> void:
	if not (selected and is_instance_valid(selected)):
		return
	var n: Node = selected
	selected = null
	n.queue_free()
	await get_tree().process_frame
	_refresh_light_list()
	_update_properties()
	queue_redraw()
	_persist()


func _draw() -> void:
	if not active:
		return
	var lighting := get_node_or_null("../Lighting")
	if lighting == null:
		return
	var cam := get_viewport().get_camera_2d()
	var view_zoom: Vector2 = cam.zoom if cam else Vector2.ONE
	var line_w: float = 1.0 / view_zoom.x

	for n in lighting.get_children():
		if not (n is Light2D):
			continue
		var c: Color = selection_color if n == selected else helper_color
		if n is PointLight2D:
			var pl := n as PointLight2D
			draw_circle(pl.global_position, 8.0 / view_zoom.x, c)
			var range_r: float = 96.0 * pl.texture_scale
			draw_arc(pl.global_position, range_r, 0.0, TAU, 64, c, line_w)
		elif n is DirectionalLight2D:
			var dir := Vector2(cos(n.rotation), sin(n.rotation))
			var origin: Vector2 = n.global_position
			var arrow_len: float = 80.0 / view_zoom.x
			var tip: Vector2 = origin + dir * arrow_len
			draw_line(origin, tip, c, 2.0 * line_w)
			var perp := Vector2(-dir.y, dir.x) * (10.0 / view_zoom.x)
			var back: Vector2 = tip - dir * (16.0 / view_zoom.x)
			draw_line(tip, back + perp, c, line_w)
			draw_line(tip, back - perp, c, line_w)
			draw_circle(origin, 6.0 / view_zoom.x, c)
