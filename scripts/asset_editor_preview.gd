extends Control

# Center preview Control for the F6 Asset Editor.
# Renders: dark/checker background, the loaded PNG (centered, scaled by zoom),
# completed polygons (translucent fill + outline + vertex dots), and an
# in-progress polygon (lines + dots + rubber-band line to the cursor).
# Forwards mouse and zoom intent to the parent editor via signals; the parent
# owns the polygon array and tool state.

signal vertex_placed(image_px: Vector2)
signal polygon_close_requested
signal eraser_clicked(image_px: Vector2)
signal mouse_moved(image_px: Vector2, in_image: bool)
signal zoom_step(delta: int)  # +1 wheel up, -1 wheel down

const TOOL_NONE := 0
const TOOL_RED := 1
const TOOL_YELLOW := 2
const TOOL_ERASER := 3

const COLOR_COLLISION := Color(1.0, 0.2, 0.2)
const COLOR_RECOGNITION := Color(1.0, 0.9, 0.2)
const FILL_ALPHA := 0.25
const VERTEX_RADIUS_PX := 3.0
const OUTLINE_WIDTH_PX := 1.0
const RUBBER_BAND_DASH := 8.0  # pixels per dash segment
const CHECKER_SIZE_PX := 16.0
const CHECKER_A := Color(0.18, 0.18, 0.20)
const CHECKER_B := Color(0.26, 0.26, 0.28)

var texture: Texture2D = null
var image_size: Vector2 = Vector2.ZERO  # px
var zoom: float = 4.0

# Polygon list owned by the parent editor; we just render it.
# Each entry: {"type": "collision"|"recognition", "vertices": PackedVector2Array (image px)}
var polygons: Array = []
var in_progress: PackedVector2Array = PackedVector2Array()
var current_tool: int = TOOL_NONE
var highlighted_index: int = -1

var _local_mouse: Vector2 = Vector2(-1, -1)
var _mouse_inside: bool = false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func set_texture(tex: Texture2D) -> void:
	texture = tex
	image_size = tex.get_size() if tex else Vector2.ZERO
	queue_redraw()


func set_zoom(z: float) -> void:
	zoom = max(0.1, z)
	queue_redraw()


func set_polygons(arr: Array) -> void:
	polygons = arr
	queue_redraw()


func set_in_progress(arr: PackedVector2Array) -> void:
	in_progress = arr
	queue_redraw()


func set_current_tool(tool_id: int) -> void:
	current_tool = tool_id
	match tool_id:
		TOOL_ERASER:
			mouse_default_cursor_shape = Control.CURSOR_CROSS
		TOOL_RED, TOOL_YELLOW:
			mouse_default_cursor_shape = Control.CURSOR_CROSS
		_:
			mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()


func set_highlighted(idx: int) -> void:
	highlighted_index = idx
	queue_redraw()


# Image-px (top-left origin, +X right, +Y down) ↔ Control-local screen px.
# The image is centered in the Control rect and scaled by `zoom`.
# image_px = (local - centering_offset) / zoom
# centering_offset = (control_size - image_size * zoom) / 2
func control_to_image_px(local: Vector2) -> Vector2:
	var img_screen := image_size * zoom
	var top_left := (size - img_screen) * 0.5
	if zoom <= 0.0:
		return Vector2.ZERO
	return (local - top_left) / zoom


func image_px_to_control(img_px: Vector2) -> Vector2:
	var img_screen := image_size * zoom
	var top_left := (size - img_screen) * 0.5
	return top_left + img_px * zoom


func is_image_px_inside(img_px: Vector2) -> bool:
	return img_px.x >= 0.0 and img_px.y >= 0.0 \
		and img_px.x <= image_size.x and img_px.y <= image_size.y


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_local_mouse = (event as InputEventMouseMotion).position
		_mouse_inside = true
		var img_px := control_to_image_px(_local_mouse)
		mouse_moved.emit(img_px, is_image_px_inside(img_px))
		queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom_step.emit(1)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_step.emit(-1)
				accept_event()
			MOUSE_BUTTON_LEFT:
				var img_px := control_to_image_px(mb.position)
				if not is_image_px_inside(img_px):
					return
				if current_tool == TOOL_ERASER:
					eraser_clicked.emit(img_px)
				elif current_tool == TOOL_RED or current_tool == TOOL_YELLOW:
					if mb.double_click and in_progress.size() >= 3:
						polygon_close_requested.emit()
					else:
						vertex_placed.emit(img_px)
				accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_mouse_inside = false
		queue_redraw()


func _draw() -> void:
	_draw_checker_background()
	if texture and image_size.x > 0 and image_size.y > 0:
		var top_left := (size - image_size * zoom) * 0.5
		draw_texture_rect(texture, Rect2(top_left, image_size * zoom), false)
	_draw_polygons()
	_draw_in_progress()
	if texture == null:
		_draw_empty_hint()


func _draw_checker_background() -> void:
	# Dark fill first, then checker overlay (cheap; preview area is small).
	draw_rect(Rect2(Vector2.ZERO, size), CHECKER_A, true)
	var cs := CHECKER_SIZE_PX
	var cols := int(ceil(size.x / cs))
	var rows := int(ceil(size.y / cs))
	for row in range(rows):
		for col in range(cols):
			if (row + col) % 2 == 1:
				var r := Rect2(Vector2(col, row) * cs, Vector2(cs, cs))
				draw_rect(r, CHECKER_B, true)


func _draw_polygons() -> void:
	for i in range(polygons.size()):
		var p: Dictionary = polygons[i]
		var verts: PackedVector2Array = p.get("vertices", PackedVector2Array())
		if verts.size() < 3:
			continue
		var col := _color_for_type(p.get("type", "collision"))
		var screen_verts := PackedVector2Array()
		for v in verts:
			screen_verts.append(image_px_to_control(v))
		var fill := col
		fill.a = FILL_ALPHA
		draw_colored_polygon(screen_verts, fill)
		var outline_w := OUTLINE_WIDTH_PX * (2.0 if i == highlighted_index else 1.0)
		# draw_polyline doesn't auto-close — append first point.
		var closed := PackedVector2Array(screen_verts)
		closed.append(screen_verts[0])
		draw_polyline(closed, col, outline_w, true)
		for v in screen_verts:
			draw_circle(v, VERTEX_RADIUS_PX, col)


func _draw_in_progress() -> void:
	if in_progress.is_empty():
		return
	var col := _color_for_tool(current_tool)
	if col.a == 0.0:
		return
	var screen_verts := PackedVector2Array()
	for v in in_progress:
		screen_verts.append(image_px_to_control(v))
	if screen_verts.size() >= 2:
		draw_polyline(screen_verts, col, OUTLINE_WIDTH_PX, true)
	for v in screen_verts:
		draw_circle(v, VERTEX_RADIUS_PX, col)
	# Rubber-band line from last placed vertex to current cursor (dashed-ish).
	if _mouse_inside and screen_verts.size() > 0:
		var last := screen_verts[screen_verts.size() - 1]
		var ghost := col
		ghost.a = 0.55
		draw_dashed_line(last, _local_mouse, ghost, OUTLINE_WIDTH_PX, RUBBER_BAND_DASH, true)


func _draw_empty_hint() -> void:
	var font := ThemeDB.fallback_font
	var text := "Load a PNG to begin..."
	var fs := 14
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	var pos := (size - ts) * 0.5
	draw_string(font, pos + Vector2(0, fs), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.85, 0.9, 0.85))


func _color_for_type(t: String) -> Color:
	if t == "recognition":
		return COLOR_RECOGNITION
	return COLOR_COLLISION


func _color_for_tool(tool_id: int) -> Color:
	match tool_id:
		TOOL_RED:
			return COLOR_COLLISION
		TOOL_YELLOW:
			return COLOR_RECOGNITION
		_:
			return Color(0, 0, 0, 0)
