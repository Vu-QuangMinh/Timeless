class_name PlayerCharacter
extends Node2D

signal time_remaining_changed(char_id: int, remaining: float)

# Class colors used for selection ring
const COLOR_BY_CLASS: Array = [
	Color("#dc4444"),
	Color("#6688cc"),
	Color("#5acb5d"),
]

# Animation GIF filenames per character class
const _BRAWLER_ANIMS: Dictionary = {
	"idle_se":      "Idle-SE-128.gif",
	"walk_se":      "Walk-SE-128.gif",
	"walk_ne":      "Walk-NE-128.gif",
	"hide_se":      "Hide-SE-128.gif",
	"lockpick_se":  "Lockpick-SE-128.gif",
	"lockpick_nw":  "Lockpick-NW-128.gif",
	"punch_jab_se": "Punch-Jab-SE-128.gif",
	"tie_se":       "Tie-SE-128.gif",
}

const _BUGLAR_ANIMS: Dictionary = {
	"idle_sw":     "Idle SW.gif",
	"hide_se":     "Hide-SE-128.gif",
	"lockpick_ne": "Lock-Pick-NE-128.gif",
	"lockpick_se": "Lock-Pick-SE-128.gif",
	"walk_ne":     "Walk-NE.gif",
	"walk_se":     "Walk-SE.gif",
}

const _HACKER_ANIMS: Dictionary = {
	"hide_se":     "Hide-SE-128.gif",
	"lockpick_ne": "Lock-pick-NE-128.gif",
	"lockpick_se": "Lock-pick-SE-128.gif",
}

const _ANIM_BASE_PATH: Array = [
	"res://assets/characters/brawler/",
	"res://assets/characters/buglar/",
	"res://assets/characters/hacker/",
]

var char_id: int = 0
var char_data = null        # Character instance
var logical_pos: Vector2 = Vector2.ZERO
var is_selected: bool = false
var is_taken_down: bool = false

var _action_objects: Array = []
var _anim_sprite: AnimatedSprite2D = null


func setup(id: int, char: Object) -> void:
	char_id = id
	char_data = char
	_build_anim_sprite()


func _build_anim_sprite() -> void:
	_anim_sprite = AnimatedSprite2D.new()
	_anim_sprite.scale = Vector2(0.5, 0.5)
	_anim_sprite.offset = Vector2(0, -32)
	add_child(_anim_sprite)

	var sf := SpriteFrames.new()
	sf.remove_animation("default")

	var base: String = _ANIM_BASE_PATH[int(char_data.char_class)]
	var gif_map: Dictionary

	match char_data.char_class:
		Character.CharacterClass.BRAWLER:
			gif_map = _BRAWLER_ANIMS
		Character.CharacterClass.CAT_BURGLAR:
			gif_map = _BUGLAR_ANIMS
		Character.CharacterClass.HACKER:
			gif_map = _HACKER_ANIMS

	for anim_name in gif_map:
		_add_gif_anim(sf, anim_name, base + gif_map[anim_name])

	if char_data.char_class == Character.CharacterClass.HACKER:
		_add_frame_seq(sf, "idle_sw", base + "Idle_SW/")
		_add_frame_seq(sf, "walk_se", base + "Walk_SE/")

	_anim_sprite.sprite_frames = sf

	var default_anim := _pick_default_anim(sf)
	if default_anim != "":
		_anim_sprite.play(default_anim)


func _pick_default_anim(sf: SpriteFrames) -> String:
	for name in ["idle_se", "idle_sw", "idle_ne", "walk_se"]:
		if sf.has_animation(name) and sf.get_frame_count(name) > 0:
			return name
	var names := sf.get_animation_names()
	return names[0] if names.size() > 0 else ""


func _add_gif_anim(sf: SpriteFrames, anim_name: String, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var tex = load(path)
	if tex == null:
		return
	sf.add_animation(anim_name)
	sf.set_animation_loop(anim_name, true)
	sf.set_animation_speed(anim_name, 8.0)
	if tex is AnimatedTexture:
		for i in tex.get_frame_count():
			sf.add_frame(anim_name, tex.get_frame_texture(i))
	elif tex is Texture2D:
		sf.add_frame(anim_name, tex)


func _add_frame_seq(sf: SpriteFrames, anim_name: String, folder: String) -> void:
	var frames: Array = []
	var i := 0
	while ResourceLoader.exists(folder + str(i) + ".png"):
		frames.append(load(folder + str(i) + ".png"))
		i += 1
	if frames.is_empty():
		return
	if sf.has_animation(anim_name):
		sf.remove_animation(anim_name)
	sf.add_animation(anim_name)
	sf.set_animation_loop(anim_name, true)
	sf.set_animation_speed(anim_name, 8.0)
	for frame in frames:
		sf.add_frame(anim_name, frame)


func play_anim(anim_name: String) -> void:
	if _anim_sprite == null or _anim_sprite.sprite_frames == null:
		return
	if _anim_sprite.sprite_frames.has_animation(anim_name):
		_anim_sprite.play(anim_name)


func set_logical_pos(p: Vector2) -> void:
	logical_pos = p
	position = IsoMath.project(p)
	queue_redraw()


func select() -> void:
	is_selected = true
	queue_redraw()


func deselect() -> void:
	is_selected = false
	queue_redraw()


func queue_action(action) -> void:
	action.char_id = char_id
	var start_t := ActionQueue.get_next_available_time(char_id)
	var d: Dictionary = action.to_dict()
	d["start_time"] = start_t
	ActionQueue.add_action(char_id, d)
	_action_objects.append(action)
	emit_signal("time_remaining_changed", char_id, get_turn_time_remaining())


func undo_last_action() -> void:
	if _action_objects.is_empty():
		return
	_action_objects.pop_back()
	ActionQueue.undo_last(char_id)
	emit_signal("time_remaining_changed", char_id, get_turn_time_remaining())


func reset_actions() -> void:
	_action_objects.clear()
	ActionQueue.reset(char_id)
	emit_signal("time_remaining_changed", char_id, get_turn_time_remaining())


func get_turn_time_used() -> float:
	var total := 0.0
	for entry in ActionQueue.get_queue(char_id):
		total += entry["cost"]
	return total


func get_turn_time_remaining() -> float:
	return GameManager.TURN_BUDGET_S - get_turn_time_used()


func commit_actions(scene_root: Node) -> Tween:
	if _action_objects.is_empty():
		return null
	var t: Tween = scene_root.create_tween()
	for action in _action_objects:
		action.execute_visual(self, t)
	return t


func clear_queue_after_commit() -> void:
	_action_objects.clear()
	ActionQueue.reset(char_id)
	scale = Vector2.ONE
	emit_signal("time_remaining_changed", char_id, get_turn_time_remaining())


func get_move_paths() -> Array:
	var paths := []
	for a in _action_objects:
		if a is ActionMove:
			paths.append(a.path)
	return paths


func _draw() -> void:
	if is_taken_down:
		draw_circle(Vector2.ZERO, 10.0, Color(0.4, 0.4, 0.4, 0.7))
		return
	if is_selected:
		var col: Color = COLOR_BY_CLASS[int(char_data.char_class)] if char_data else Color.GRAY
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 32, col, 2.5)
	var font := ThemeDB.fallback_font
	var fs := ThemeDB.fallback_font_size
	draw_string(font, Vector2(-14.0, -20.0), char_data.display_name() if char_data else "",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 4, Color.WHITE)
