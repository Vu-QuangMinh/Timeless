## ContextMenu
## Right-click popup drawn via _draw() on a CanvasLayer in screen space.
## Caller populates items via show_at(), then listens to action_selected.
## Each item: {label: String, cost_str: String, enabled: bool, action_type: String, data: Dictionary}
## Does NOT build paths or compute costs — caller provides those. Does NOT modify game state.

class_name ContextMenu
extends Node2D

signal action_selected(action_type: String, data: Dictionary)
signal closed()

const ROW_H   := 28.0
const MENU_W  := 270.0
const PAD_X   := 10.0
const PAD_TOP := 6.0

const C_BG       := Color(0.10, 0.10, 0.13, 0.95)
const C_BORDER   := Color(0.45, 0.45, 0.50, 1.0)
const C_HOVER    := Color(0.25, 0.25, 0.30, 1.0)
const C_TEXT     := Color(0.90, 0.90, 0.90)
const C_DISABLED := Color(0.45, 0.45, 0.45)
const C_COST     := Color(0.40, 0.90, 0.55)
const C_COST_DIS := Color(0.35, 0.45, 0.38)

var _items: Array = []  # Array of item Dictionaries
var _hovered: int = -1
var _visible_menu: bool = false

func _ready() -> void:
	set_process_input(true)
	hide()

func show_at(screen_pos: Vector2, items: Array) -> void:
	_items = items
	_hovered = -1
	_visible_menu = true
	position = _clamp_to_viewport(screen_pos)
	show()
	queue_redraw()

func close() -> void:
	_visible_menu = false
	_items.clear()
	hide()
	emit_signal("closed")

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not _visible_menu:
		return
	var total_h := PAD_TOP * 2.0 + ROW_H * _items.size()
	var bg := Rect2(0.0, 0.0, MENU_W, total_h)

	draw_rect(bg, C_BG)
	draw_rect(bg, C_BORDER, false, 1.0)

	for i in _items.size():
		var item: Dictionary = _items[i]
		var row_y := PAD_TOP + i * ROW_H
		var row   := Rect2(1.0, row_y, MENU_W - 2.0, ROW_H)

		if i == _hovered and item.get("enabled", false):
			draw_rect(row, C_HOVER)

		var font   := ThemeDB.fallback_font
		var fs     := 13
		var text_c := C_TEXT if item.get("enabled", false) else C_DISABLED
		var cost_c := C_COST if item.get("enabled", false) else C_COST_DIS

		var label: String    = item.get("label", "")
		var cost_str: String = item.get("cost_str", "")

		draw_string(font, Vector2(PAD_X, row_y + ROW_H * 0.72),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_c)

		if cost_str != "":
			var cw := font.get_string_size(cost_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(MENU_W - PAD_X - cw, row_y + ROW_H * 0.72),
				cost_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cost_c)

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _visible_menu:
		return

	if event is InputEventMouseMotion:
		_update_hover(event.position)

	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var clicked := _item_at(event.position)
			if clicked >= 0:
				var item: Dictionary = _items[clicked]
				if item.get("enabled", false):
					get_viewport().set_input_as_handled()
					var atype: String     = item.get("action_type", "")
					var data: Dictionary  = item.get("data", {})
					close()
					emit_signal("action_selected", atype, data)
					return
			# Click outside menu
			if not _in_bounds(event.position):
				get_viewport().set_input_as_handled()
				close()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			close()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func _update_hover(screen_pos: Vector2) -> void:
	var prev := _hovered
	_hovered = _item_at(screen_pos)
	if _hovered != prev:
		queue_redraw()

func _item_at(screen_pos: Vector2) -> int:
	var local := screen_pos - position
	if local.x < 0.0 or local.x > MENU_W:
		return -1
	var total_h := PAD_TOP * 2.0 + ROW_H * _items.size()
	if local.y < PAD_TOP or local.y > total_h - PAD_TOP:
		return -1
	var idx := int((local.y - PAD_TOP) / ROW_H)
	return idx if idx < _items.size() else -1

func _in_bounds(screen_pos: Vector2) -> bool:
	var local := screen_pos - position
	var total_h := PAD_TOP * 2.0 + ROW_H * _items.size()
	return local.x >= 0.0 and local.x <= MENU_W and local.y >= 0.0 and local.y <= total_h

func _clamp_to_viewport(pos: Vector2) -> Vector2:
	var vp  := get_viewport().get_visible_rect().size
	var total_h := PAD_TOP * 2.0 + ROW_H * _items.size()
	return Vector2(
		clampf(pos.x, 0.0, vp.x - MENU_W),
		clampf(pos.y, 0.0, vp.y - total_h))
