extends Node2D

@export var show_debug_walls: bool = true


func _draw() -> void:
	if not show_debug_walls:
		return
	for seg in get_wall_segments():
		draw_line(IsoMath.project(seg["a"]), IsoMath.project(seg["b"]), Color.RED, 2.0)
	var chest := get_chest_obstacle()
	if chest["radius"] > 0.0:
		draw_circle(IsoMath.project(chest["center"]), chest["radius"] * IsoMath.PPM * 0.6, Color(1.0, 0.9, 0.1, 0.5))


func get_wall_segments() -> Array:
	# Walkable boundary is the INNER face of the wall — approximately 1m inside the sprite's
	# outer diamond edge, where the decorative ledge ends and the floor begins.
	# ±9m is a first estimate. Calibrate: left-click wall inner edges in-game, read console.
	#
	# Door is on the NORTH wall (y=9), near the NE corner (upper-right of room).
	# Gap from x=6 to x=9 — calibrate by clicking door-frame edges in-game.
	return [
		{"a": Vector2(-9.0,  9.0), "b": Vector2( 6.0,  9.0)},  # north-left  (left of door)
		# door gap: x = 6 → 9 on north wall (upper-right of room)
		{"a": Vector2(-9.0, -9.0), "b": Vector2(-9.0,  9.0)},  # west  (complete)
		{"a": Vector2(-9.0, -9.0), "b": Vector2( 9.0, -9.0)},  # south (complete)
		{"a": Vector2( 9.0,  9.0), "b": Vector2( 9.0, -9.0)},  # east  (complete)
	]


func get_door_centers() -> Array:
	return [Vector2(7.5, 9.0)]  # midpoint of door gap; calibrate in-game


func get_chest_obstacle() -> Dictionary:
	return {"center": Vector2.ZERO, "radius": 0.75}
