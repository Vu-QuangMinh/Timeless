extends Node2D

var _level: Node2D
var _character: PlayerCharacter
var _move_preview: Array = []  # projected waypoints for debug


func _ready() -> void:
	_level = preload("res://scenes/level_1/level_1.tscn").instantiate()
	add_child(_level)

	var pc_scene := preload("res://scenes/characters/player_character.tscn")
	_character = pc_scene.instantiate() as PlayerCharacter
	add_child(_character)
	_character.set_logical_pos(Vector2(0.0, -8.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos := IsoMath.unproject(get_global_mouse_position())
		_move_character_to(world_pos)


func _move_character_to(target: Vector2) -> void:
	var wall_segs: Array = _level.get_wall_segments()
	var obstacles: Array = []
	var chest: Dictionary = _level.get_chest_obstacle()
	if chest["radius"] > 0.0:
		obstacles.append(chest)

	var pf := Pathfinder.new()
	pf.setup(wall_segs, obstacles)
	var waypoints := pf.find_path(_character.logical_pos, target)
	print("click world=", target, " path=", waypoints)
	if waypoints.is_empty():
		return

	var smoother := PathSmoother.new()
	var path := smoother.smooth(waypoints, wall_segs, obstacles)
	if path == null:
		return

	_character.move_along(path)
