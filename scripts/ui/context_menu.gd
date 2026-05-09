class_name ContextMenu
extends CanvasLayer

signal item_selected(index: int)

var _panel: PanelContainer
var _vbox: VBoxContainer
var _buttons: Array = []
var _pending_count: int = 0


func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	add_child(_panel)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 0)
	_panel.add_child(_vbox)
	_panel.visible = false


func show_at(screen_pos: Vector2, items: Array) -> void:
	_clear_buttons()
	_pending_count = items.size()
	for i in items.size():
		var item: Dictionary = items[i]
		var btn := Button.new()
		btn.text = item["label"]
		btn.disabled = not item["enabled"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(160.0, 28.0)
		var idx := i
		btn.pressed.connect(func() -> void: _on_btn(idx))
		_vbox.add_child(btn)
		_buttons.append(btn)
	_panel.position = screen_pos
	_panel.visible = true


func close() -> void:
	_panel.visible = false
	_clear_buttons()


func is_open() -> bool:
	return _panel.visible


func _clear_buttons() -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()


func _on_btn(index: int) -> void:
	close()
	emit_signal("item_selected", index)


func _unhandled_input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		var mp: Vector2 = (event as InputEventMouseButton).position
		var r := Rect2(_panel.position, _panel.size)
		if not r.has_point(mp):
			close()
			get_viewport().set_input_as_handled()
