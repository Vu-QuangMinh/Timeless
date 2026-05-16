class_name HUD
extends CanvasLayer

signal commit_pressed()

const CHAR_COLORS: Array = [
	Color("#dc4444"),
	Color("#6688cc"),
	Color("#5acb5d"),
]

const CHAR_AVATARS: Array = [
	"res://assets/characters/brawler/avatar.png",
	"res://assets/characters/buglar/avatar.png",
	"res://assets/characters/hacker/avatar.png",
]

const DEFAULT_LAYOUT := {
	# Per-character group positions and sizes (fully independent)
	"char_0_x": 170.0, "char_0_y": 595.0, "char_0_w": 300.0, "char_0_h": 80.0,
	"char_1_x": 490.0, "char_1_y": 595.0, "char_1_w": 300.0, "char_1_h": 80.0,
	"char_2_x": 810.0, "char_2_y": 595.0, "char_2_w": 300.0, "char_2_h": 80.0,
	# Sub-elements — offset from each panel's origin (shared across all chars)
	"avatar_ox":    4.0, "avatar_oy":    4.0, "avatar_w":   72.0, "avatar_h":   72.0,
	"name_ox":     80.0, "name_oy":      4.0, "name_w":    212.0, "name_h":     24.0,
	"time_lbl_ox": 80.0, "time_lbl_oy": 28.0, "time_lbl_w": 212.0, "time_lbl_h": 20.0,
	"time_bar_ox":  0.0, "time_bar_oy": 84.0, "time_bar_w": 300.0, "time_bar_h": 20.0,
	"time_fill_ox": 0.0, "time_fill_oy": 84.0, "time_fill_w": 300.0, "time_fill_h": 20.0,
	"time_mark_ox": 0.0, "time_mark_oy": 82.0, "time_mark_w":  12.0, "time_mark_h": 24.0,
}

const LAYOUT_PATH := "user://hud_layout.json"

var layout: Dictionary = {}

var _timer_label: Label
var _phase_label: Label
var _char_containers: Array = []
var _predict_btn: Button
var _commit_btn: Button


func _ready() -> void:
	layer = 10
	layout = DEFAULT_LAYOUT.duplicate(true)
	_load_layout()
	_build_timer()
	_build_phase()
	_build_char_panel()
	_build_phase_buttons()


func _process(_delta: float) -> void:
	for c in _char_containers:
		var c_dict: Dictionary = c
		var fill_rect: TextureRect = c_dict["time_fill_rect"]
		var fill_px: float = c_dict["fill_base_x"] + fill_rect.size.x
		c_dict["time_mark_rect"].position.x = fill_px - c_dict["mark_w"] * 0.5
		c_dict["time_mark_rect"].position.y = c_dict["mark_base_y"]


func _load_layout() -> void:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary:
		for key in data:
			layout[key] = data[key]


func save_layout() -> void:
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(layout, "\t"))
	file.close()


static func _lf(d: Dictionary, key: String, def: float) -> float:
	return float(d.get(key, def))


func apply_layout(new_layout: Dictionary) -> void:
	layout = new_layout.duplicate(true)
	_reposition_all_with(layout)


func preview_layout(new_layout: Dictionary) -> void:
	_reposition_all_with(new_layout)


func _reposition_all_with(lay: Dictionary) -> void:
	if _char_containers.is_empty():
		return

	var av_ox: float = _lf(lay, "avatar_ox",     4.0)
	var av_oy: float = _lf(lay, "avatar_oy",     4.0)
	var av_w:  float = _lf(lay, "avatar_w",     72.0)
	var av_h:  float = _lf(lay, "avatar_h",     72.0)
	var nm_ox: float = _lf(lay, "name_ox",      80.0)
	var nm_oy: float = _lf(lay, "name_oy",       4.0)
	var nm_w:  float = _lf(lay, "name_w",      212.0)
	var nm_h:  float = _lf(lay, "name_h",       24.0)
	var tl_ox: float = _lf(lay, "time_lbl_ox",  80.0)
	var tl_oy: float = _lf(lay, "time_lbl_oy",  28.0)
	var tl_w:  float = _lf(lay, "time_lbl_w",  212.0)
	var tl_h:  float = _lf(lay, "time_lbl_h",   20.0)
	var tb_ox: float = _lf(lay, "time_bar_ox",   0.0)
	var tb_oy: float = _lf(lay, "time_bar_oy",  84.0)
	var tb_w:  float = _lf(lay, "time_bar_w",  300.0)
	var tb_h:  float = _lf(lay, "time_bar_h",   20.0)
	var tf_ox: float = _lf(lay, "time_fill_ox",  0.0)
	var tf_oy: float = _lf(lay, "time_fill_oy", 84.0)
	var tf_w:  float = _lf(lay, "time_fill_w", 300.0)
	var tf_h:  float = _lf(lay, "time_fill_h",  20.0)
	var tm_ox: float = _lf(lay, "time_mark_ox",  0.0)
	var tm_oy: float = _lf(lay, "time_mark_oy", 82.0)
	var tm_w:  float = _lf(lay, "time_mark_w",  12.0)
	var tm_h:  float = _lf(lay, "time_mark_h",  24.0)

	for i in 3:
		var px: float = _lf(lay, "char_%d_x" % i, 170.0 + float(i) * 320.0)
		var py: float = _lf(lay, "char_%d_y" % i, 595.0)
		var pw: float = _lf(lay, "char_%d_w" % i, 300.0)
		var ph: float = _lf(lay, "char_%d_h" % i,  80.0)
		var c: Dictionary = _char_containers[i]

		c["bg"].position             = Vector2(px, py)
		c["bg"].size                 = Vector2(pw, ph)
		c["avatar_rect"].position    = Vector2(px + av_ox, py + av_oy)
		c["avatar_rect"].size        = Vector2(av_w, av_h)
		c["name_lbl"].position       = Vector2(px + nm_ox, py + nm_oy)
		c["name_lbl"].size           = Vector2(nm_w, nm_h)
		c["sel_lbl"].position        = Vector2(px + pw - 28.0, py + 4.0)
		c["time_lbl"].position       = Vector2(px + tl_ox, py + tl_oy)
		c["time_lbl"].size           = Vector2(tl_w, tl_h)
		c["time_bar_rect"].position  = Vector2(px + tb_ox, py + tb_oy)
		c["time_bar_rect"].size      = Vector2(tb_w, tb_h)
		c["time_fill_rect"].position = Vector2(px + tf_ox, py + tf_oy)
		c["time_fill_rect"].size     = Vector2(tf_w * c.get("_fill_ratio", 1.0), tf_h)
		c["time_mark_rect"].size     = Vector2(tm_w, tm_h)
		c["fill_base_x"]  = px + tf_ox
		c["fill_max_w"]   = tf_w
		c["mark_base_y"]  = py + tm_oy
		c["mark_w"]       = tm_w
		c["time_mark_rect"].position = Vector2(px + tm_ox, py + tm_oy)


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
	var tb_tex: Texture2D = load("res://assets/hud/time_bar.png")
	var tf_tex: Texture2D = load("res://assets/hud/time_fill.png")
	var tm_tex: Texture2D = load("res://assets/hud/time_mark.png")

	for i in 3:
		var px: float = _lf(layout, "char_%d_x" % i, 170.0 + float(i) * 320.0)
		var py: float = _lf(layout, "char_%d_y" % i, 595.0)
		var pw: float = _lf(layout, "char_%d_w" % i, 300.0)
		var ph: float = _lf(layout, "char_%d_h" % i,  80.0)

		var av_ox: float = _lf(layout, "avatar_ox",     4.0)
		var av_oy: float = _lf(layout, "avatar_oy",     4.0)
		var av_w:  float = _lf(layout, "avatar_w",     72.0)
		var av_h:  float = _lf(layout, "avatar_h",     72.0)
		var nm_ox: float = _lf(layout, "name_ox",      80.0)
		var nm_oy: float = _lf(layout, "name_oy",       4.0)
		var nm_w:  float = _lf(layout, "name_w",      212.0)
		var nm_h:  float = _lf(layout, "name_h",       24.0)
		var tl_ox: float = _lf(layout, "time_lbl_ox",  80.0)
		var tl_oy: float = _lf(layout, "time_lbl_oy",  28.0)
		var tl_w:  float = _lf(layout, "time_lbl_w",  212.0)
		var tl_h:  float = _lf(layout, "time_lbl_h",   20.0)
		var tb_ox: float = _lf(layout, "time_bar_ox",   0.0)
		var tb_oy: float = _lf(layout, "time_bar_oy",  84.0)
		var tb_w:  float = _lf(layout, "time_bar_w",  300.0)
		var tb_h:  float = _lf(layout, "time_bar_h",   20.0)
		var tf_ox: float = _lf(layout, "time_fill_ox",  0.0)
		var tf_oy: float = _lf(layout, "time_fill_oy", 84.0)
		var tf_w:  float = _lf(layout, "time_fill_w",  300.0)
		var tf_h:  float = _lf(layout, "time_fill_h",   20.0)
		var tm_ox: float = _lf(layout, "time_mark_ox",  0.0)
		var tm_oy: float = _lf(layout, "time_mark_oy", 82.0)
		var tm_w:  float = _lf(layout, "time_mark_w",  12.0)
		var tm_h:  float = _lf(layout, "time_mark_h",  24.0)

		var bg := ColorRect.new()
		bg.position = Vector2(px, py)
		bg.size = Vector2(pw, ph)
		bg.color = Color(0.08, 0.08, 0.12, 0.88)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

		var avatar_rect := TextureRect.new()
		avatar_rect.position = Vector2(px + av_ox, py + av_oy)
		avatar_rect.size = Vector2(av_w, av_h)
		avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists(CHAR_AVATARS[i]):
			avatar_rect.texture = load(CHAR_AVATARS[i])
		add_child(avatar_rect)

		var name_lbl := Label.new()
		name_lbl.position = Vector2(px + nm_ox, py + nm_oy)
		name_lbl.size = Vector2(nm_w, nm_h)
		name_lbl.add_theme_font_size_override("font_size", 14)
		add_child(name_lbl)

		var sel_lbl := Label.new()
		sel_lbl.position = Vector2(px + pw - 28.0, py + 4.0)
		sel_lbl.size = Vector2(20.0, 20.0)
		sel_lbl.text = ""
		sel_lbl.add_theme_color_override("font_color", Color.YELLOW)
		add_child(sel_lbl)

		var time_lbl := Label.new()
		time_lbl.position = Vector2(px + tl_ox, py + tl_oy)
		time_lbl.size = Vector2(tl_w, tl_h)
		time_lbl.add_theme_font_size_override("font_size", 12)
		time_lbl.text = "10.0s remaining"
		add_child(time_lbl)

		var time_bar_rect := TextureRect.new()
		time_bar_rect.texture = tb_tex
		time_bar_rect.position = Vector2(px + tb_ox, py + tb_oy)
		time_bar_rect.size = Vector2(tb_w, tb_h)
		time_bar_rect.stretch_mode = TextureRect.STRETCH_SCALE
		time_bar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		time_bar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(time_bar_rect)

		var time_fill_rect := TextureRect.new()
		time_fill_rect.texture = tf_tex
		time_fill_rect.stretch_mode = TextureRect.STRETCH_SCALE
		time_fill_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		time_fill_rect.position = Vector2(px + tf_ox, py + tf_oy)
		time_fill_rect.size = Vector2(tf_w, tf_h)
		time_fill_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(time_fill_rect)

		var time_mark_rect := TextureRect.new()
		time_mark_rect.texture = tm_tex
		time_mark_rect.position = Vector2(px + tm_ox, py + tm_oy)
		time_mark_rect.size = Vector2(tm_w, tm_h)
		time_mark_rect.stretch_mode = TextureRect.STRETCH_SCALE
		time_mark_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		time_mark_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(time_mark_rect)

		_char_containers.append({
			"bg": bg,
			"avatar_rect": avatar_rect,
			"name_lbl": name_lbl,
			"sel_lbl": sel_lbl,
			"time_lbl": time_lbl,
			"time_bar_rect": time_bar_rect,
			"time_fill_rect": time_fill_rect,
			"time_mark_rect": time_mark_rect,
			"fill_base_x": px + tf_ox,
			"fill_max_w": tf_w,
			"mark_base_y": py + tm_oy,
			"mark_w": tm_w,
			"_fill_ratio": 1.0,
			"_fill_tween": null,
		})
	# Re-apply layout after all nodes are in the scene tree so TextureRect sizes
	# are set correctly (setting size before add_child can be overridden by Godot
	# when the texture's native size is very large).
	_reposition_all_with(layout)


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
	_commit_btn.pressed.connect(func(): commit_pressed.emit())
	add_child(_commit_btn)


func refresh(characters: Array, selected_idx: int) -> void:
	_timer_label.text = "%.1fs" % GameManager.global_time_remaining
	if GameManager.phase != GameManager.Phase.COMMIT:
		_phase_label.text = _phase_name(GameManager.phase)
	var any_queued := false
	for i in mini(characters.size(), _char_containers.size()):
		var pc: PlayerCharacter = characters[i]
		var c: Dictionary = _char_containers[i]
		c["name_lbl"].text = pc.char_data.display_name() if pc.char_data else "?"
		c["sel_lbl"].text = ">" if i == selected_idx else ""
		var used := pc.get_turn_time_used()
		var remaining := pc.get_turn_time_remaining()
		c["time_lbl"].text = "%.1fs remaining" % maxf(remaining, 0.0)
		var fill_ratio := clampf(remaining / GameManager.TURN_BUDGET_S, 0.0, 1.0)
		c["_fill_ratio"] = fill_ratio
		var target_w: float = c["fill_max_w"] * fill_ratio
		var prev: Tween = c["_fill_tween"]
		if prev != null and prev.is_valid():
			prev.kill()
		var tw := create_tween()
		tw.tween_property(c["time_fill_rect"], "size:x", target_w, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		c["_fill_tween"] = tw
		if used > 0.001:
			any_queued = true
	if GameManager.mission_active and GameManager.phase == GameManager.Phase.PLANNING:
		_commit_btn.disabled = not any_queued
	else:
		_commit_btn.disabled = true


func set_phase(p: String) -> void:
	_phase_label.text = p
	if p != "PLANNING":
		_commit_btn.disabled = true


func _phase_name(p: int) -> String:
	match p:
		0: return "PLANNING"
		1: return "PREDICT"
		2: return "COMMIT"
	return "PLANNING"
