class_name HUD
extends CanvasLayer

const CHAR_COLORS: Array = [
	Color("#dc4444"),
	Color("#6688cc"),
	Color("#5acb5d"),
]

var _timer_label: Label
var _phase_label: Label
var _char_containers: Array = []  # Array of {dot, name_lbl, bar, sel_lbl}
var _predict_btn: Button
var _commit_btn: Button


func _ready() -> void:
	layer = 10
	_build_timer()
	_build_phase()
	_build_char_panel()
	_build_phase_buttons()


func _build_timer() -> void:
	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-130.0, 10.0)
	_timer_label.size = Vector2(120.0, 30.0)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.add_theme_font_size_override("font_size", 20)
	_timer_label.text = "45.0s"
	add_child(_timer_label)


func _build_phase() -> void:
	_phase_label = Label.new()
	_phase_label.position = Vector2(10.0, 10.0)
	_phase_label.size = Vector2(180.0, 30.0)
	_phase_label.add_theme_font_size_override("font_size", 18)
	_phase_label.text = "PLANNING"
	add_child(_phase_label)


func _build_char_panel() -> void:
	var vp_size := Vector2(1280.0, 720.0)
	var panel_h := 80.0
	var panel_w := 300.0
	var spacing := 20.0
	var total_w := panel_w * 3.0 + spacing * 2.0
	var start_x := (vp_size.x - total_w) * 0.5
	var y := vp_size.y - panel_h - 10.0

	for i in 3:
		var x := start_x + float(i) * (panel_w + spacing)
		var bg := ColorRect.new()
		bg.position = Vector2(x, y)
		bg.size = Vector2(panel_w, panel_h)
		bg.color = Color(0.08, 0.08, 0.12, 0.88)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

		var dot := ColorRect.new()
		dot.position = Vector2(x + 8.0, y + 8.0)
		dot.size = Vector2(14.0, 14.0)
		dot.color = CHAR_COLORS[i]
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dot)

		var name_lbl := Label.new()
		name_lbl.position = Vector2(x + 28.0, y + 4.0)
		name_lbl.size = Vector2(panel_w - 36.0, 24.0)
		name_lbl.add_theme_font_size_override("font_size", 14)
		add_child(name_lbl)

		var sel_lbl := Label.new()
		sel_lbl.position = Vector2(x + panel_w - 28.0, y + 4.0)
		sel_lbl.size = Vector2(20.0, 20.0)
		sel_lbl.text = ""
		sel_lbl.add_theme_color_override("font_color", Color.YELLOW)
		add_child(sel_lbl)

		var time_lbl := Label.new()
		time_lbl.position = Vector2(x + 8.0, y + 28.0)
		time_lbl.size = Vector2(panel_w - 16.0, 20.0)
		time_lbl.add_theme_font_size_override("font_size", 12)
		time_lbl.text = "10.0s remaining"
		add_child(time_lbl)

		var bar := ProgressBar.new()
		bar.position = Vector2(x + 8.0, y + 50.0)
		bar.size = Vector2(panel_w - 16.0, 14.0)
		bar.max_value = GameManager.TURN_BUDGET_S
		bar.value = 0.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)

		_char_containers.append({
			"name_lbl": name_lbl,
			"sel_lbl": sel_lbl,
			"time_lbl": time_lbl,
			"bar": bar,
		})


func _build_phase_buttons() -> void:
	var vp_size := Vector2(1280.0, 720.0)
	var btn_y := vp_size.y - 100.0

	_predict_btn = Button.new()
	_predict_btn.text = "Predict"
	_predict_btn.position = Vector2(vp_size.x - 220.0, btn_y)
	_predict_btn.size = Vector2(90.0, 30.0)
	_predict_btn.disabled = true
	add_child(_predict_btn)

	_commit_btn = Button.new()
	_commit_btn.text = "Commit"
	_commit_btn.position = Vector2(vp_size.x - 120.0, btn_y)
	_commit_btn.size = Vector2(90.0, 30.0)
	_commit_btn.disabled = true
	add_child(_commit_btn)


func refresh(characters: Array, selected_idx: int) -> void:
	_timer_label.text = "%.1fs" % GameManager.global_time_remaining
	_phase_label.text = _phase_name(GameManager.phase)
	for i in minf(characters.size(), _char_containers.size()):
		var pc: PlayerCharacter = characters[i]
		var c: Dictionary = _char_containers[i]
		c["name_lbl"].text = pc.char_data.display_name() if pc.char_data else "?"
		c["sel_lbl"].text = ">" if i == selected_idx else ""
		var used := pc.get_turn_time_used()
		var remaining := pc.get_turn_time_remaining()
		c["time_lbl"].text = "%.1fs remaining" % maxf(remaining, 0.0)
		c["bar"].value = used


func _phase_name(p: int) -> String:
	match p:
		0: return "PLANNING"
		1: return "PREDICT"
		2: return "COMMIT"
	return "PLANNING"
