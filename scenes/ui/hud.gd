## HUD
## Builds and owns all in-game UI: global timer (top-right), phase buttons (top-centre),
## and selected character panel (bottom). Emits predict_pressed / commit_pressed /
## back_pressed for main.gd to act on. Does NOT read input or modify game state.

class_name HUD
extends CanvasLayer

signal predict_pressed
signal commit_pressed
signal back_pressed

# --- nodes built in _ready ---
var _timer_label: Label
var _panel_bg: ColorRect
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _time_label: Label
var _char_name_label: Label
var _char_dot: ColorRect
var _phase_label: Label
var _predict_btn: Button
var _commit_btn: Button
var _back_btn: Button
var _bar_tween: Tween = null

const BAR_W       := 480.0
const BAR_H       := 36.0
const PANEL_X     := 400.0
const PANEL_Y     := 662.0
const PANEL_W     := BAR_W + 80.0
const PANEL_H     := 52.0
const DOT_SIZE    := 28.0
const TURN_BUDGET := 10.0

func _ready() -> void:
	_build_timer()
	_build_char_panel()
	_build_phase_label()
	_build_phase_buttons()

	GameManager.global_timer_changed.connect(_on_timer_changed)
	TurnManager.phase_changed.connect(_on_phase_changed)

# ---------------------------------------------------------------------------
# Build helpers
# ---------------------------------------------------------------------------

func _build_timer() -> void:
	var bg := ColorRect.new()
	bg.color    = Color(0.0, 0.0, 0.0, 0.65)
	bg.position = Vector2(1070.0, 8.0)
	bg.size     = Vector2(202.0, 40.0)
	add_child(bg)

	_timer_label = Label.new()
	_timer_label.position = Vector2(1074.0, 10.0)
	_timer_label.size     = Vector2(194.0, 36.0)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 20)
	_timer_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	_timer_label.text = "TIME  60.0s"
	add_child(_timer_label)

func _build_char_panel() -> void:
	_panel_bg = ColorRect.new()
	_panel_bg.color    = Color(0.08, 0.08, 0.10, 0.85)
	_panel_bg.position = Vector2(PANEL_X, PANEL_Y)
	_panel_bg.size     = Vector2(PANEL_W, PANEL_H)
	add_child(_panel_bg)

	_char_dot = ColorRect.new()
	_char_dot.color    = Color.WHITE
	_char_dot.position = Vector2(PANEL_X + 8.0, PANEL_Y + (PANEL_H - DOT_SIZE) * 0.5)
	_char_dot.size     = Vector2(DOT_SIZE, DOT_SIZE)
	add_child(_char_dot)

	_char_name_label = Label.new()
	_char_name_label.position = Vector2(PANEL_X + 44.0, PANEL_Y + 2.0)
	_char_name_label.size     = Vector2(200.0, 18.0)
	_char_name_label.add_theme_font_size_override("font_size", 11)
	_char_name_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_char_name_label.text = "— no selection —"
	add_child(_char_name_label)

	_bar_bg = ColorRect.new()
	_bar_bg.color    = Color(0.25, 0.25, 0.28)
	_bar_bg.position = Vector2(PANEL_X + 44.0, PANEL_Y + 20.0)
	_bar_bg.size     = Vector2(BAR_W, BAR_H)
	add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.color    = Color(0.1, 0.95, 0.35)
	_bar_fill.position = _bar_bg.position
	_bar_fill.size     = Vector2(BAR_W, BAR_H)
	add_child(_bar_fill)

	_time_label = Label.new()
	_time_label.position = _bar_bg.position
	_time_label.size     = Vector2(BAR_W, BAR_H)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 17)
	_time_label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	_time_label.text = "10.0"
	add_child(_time_label)

func _build_phase_label() -> void:
	_phase_label = Label.new()
	_phase_label.position = Vector2(8.0, 10.0)
	_phase_label.size     = Vector2(400.0, 36.0)
	_phase_label.add_theme_font_size_override("font_size", 14)
	_phase_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.4))
	_phase_label.text = "PLANNING"
	add_child(_phase_label)

func _build_phase_buttons() -> void:
	# Predict button — shown during Planning.
	_predict_btn = _make_btn("PREDICT  →", Color(0.10, 0.70, 0.35))
	_predict_btn.position = Vector2(510.0, 8.0)
	_predict_btn.size     = Vector2(220.0, 36.0)
	_predict_btn.pressed.connect(func(): emit_signal("predict_pressed"))
	add_child(_predict_btn)

	# Back button — shown during Predict (left of Commit).
	_back_btn = _make_btn("←  BACK", Color(0.75, 0.40, 0.10))
	_back_btn.position = Vector2(510.0, 8.0)
	_back_btn.size     = Vector2(160.0, 36.0)
	_back_btn.pressed.connect(func(): emit_signal("back_pressed"))
	_back_btn.hide()
	add_child(_back_btn)

	# Commit button — shown during Predict (right of Back).
	_commit_btn = _make_btn("COMMIT  ✓", Color(0.15, 0.45, 0.90))
	_commit_btn.position = Vector2(682.0, 8.0)
	_commit_btn.size     = Vector2(160.0, 36.0)
	_commit_btn.pressed.connect(func(): emit_signal("commit_pressed"))
	_commit_btn.hide()
	add_child(_commit_btn)

func _make_btn(label_text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color",       Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_stylebox_override("normal",  _btn_style(color.darkened(0.25)))
	btn.add_theme_stylebox_override("hover",   _btn_style(color))
	btn.add_theme_stylebox_override("pressed", _btn_style(color.darkened(0.45)))
	btn.add_theme_stylebox_override("focus",   _btn_style(color.darkened(0.25)))
	return btn

func _btn_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color            = color
	s.border_color        = Color(1.0, 1.0, 1.0, 0.35)
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4
	s.corner_radius_bottom_right = 4
	s.content_margin_left  = 10.0
	s.content_margin_right = 10.0
	return s

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func update_selected_character(character: PlayerCharacter) -> void:
	if character == null:
		_char_name_label.text = "— no selection —"
		_char_dot.color = Color(0.4, 0.4, 0.4)
		_set_bar_fraction(1.0)
		_time_label.text = "–"
		return

	_char_name_label.text = character.display_name()
	_char_dot.color       = character._class_color()
	_refresh_time_bar(character)

	if not character.time_remaining_changed.is_connected(_on_time_changed):
		character.time_remaining_changed.connect(_on_time_changed)
	if not character.time_bar_animate.is_connected(_on_bar_animate):
		character.time_bar_animate.connect(_on_bar_animate)

func _refresh_time_bar(character: PlayerCharacter) -> void:
	var remaining := character.get_turn_time_remaining()
	_set_bar_fraction(remaining / TURN_BUDGET)
	_time_label.text = "%.1f" % remaining

# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_timer_changed(seconds: float) -> void:
	_timer_label.text = "TIME  %.1fs" % seconds

func _on_time_changed(seconds: float) -> void:
	if _bar_tween:
		_bar_tween.kill()
		_bar_tween = null
	_set_bar_fraction(seconds / TURN_BUDGET)
	_time_label.text = "%.1f" % seconds

func _on_bar_animate(to_seconds: float, over_real_seconds: float) -> void:
	if _bar_tween:
		_bar_tween.kill()
	_bar_tween = create_tween()
	var from_frac := _bar_fill.size.x / BAR_W
	var to_frac   := clampf(to_seconds / TURN_BUDGET, 0.0, 1.0)
	_bar_tween.tween_method(_set_bar_fraction, from_frac, to_frac, over_real_seconds)
	_time_label.text = "%.1f" % to_seconds

func _on_phase_changed(phase: GameManager.Phase) -> void:
	match phase:
		GameManager.Phase.PLANNING:
			_phase_label.text = "PLANNING  [` undo  |  R reset all  |  Tab next]"
			_predict_btn.show()
			_commit_btn.hide()
			_back_btn.hide()
		GameManager.Phase.PREDICT:
			_phase_label.text = "PREDICT — guards acting"
			_predict_btn.hide()
			_back_btn.show()
			_commit_btn.show()
		GameManager.Phase.COMMIT:
			_phase_label.text = "COMMIT"
			_predict_btn.hide()
			_commit_btn.hide()
			_back_btn.hide()

func _set_bar_fraction(t: float) -> void:
	_bar_fill.size.x = BAR_W * clampf(t, 0.0, 1.0)
