extends Node2D

@export var show_debug_walls: bool = true

var chest_locked: bool = true
var chest_picked_up: bool = false

# ── Wall pixel constants (texture space) ──────────────────────────────────────
# Extracted by scripts/tools/analyze_walls.py from Wall_X.png and Wall_Y.png
# alpha edges. Texture size 2412×1760, sprite scale 0.5307, position (0,0).
#
# Wall_X runs at roughly constant world_y ≈ 4 m (the back wall, with door).
# Wall_Y runs at roughly constant world_x ≈ −5 m (the left wall, solid).
# The two walls share a corner at approximately world (−4.55, 3.56).

const _WX_SEG1_A := Vector2(1155.0,  635.0)   # Wall_X seg-1 start — shared wall corner
const _WX_SEG1_B := Vector2(1453.0,  754.0)   # Wall_X seg-1 end   — left door edge
const _WX_SEG2_A := Vector2(1546.0,  841.0)   # Wall_X seg-2 start — right door edge
const _WX_SEG2_B := Vector2(2033.0, 1064.0)   # Wall_X seg-2 end   — far-right corner

const _WY_SEG_A  := Vector2( 279.0, 1065.0)   # Wall_Y start — far end (bottom)
const _WY_SEG_B  := Vector2(1154.0,  636.0)   # Wall_Y end   — shared wall corner


func unlock_chest() -> void:
	chest_locked = false
	queue_redraw()


func lock_chest() -> void:
	chest_locked = true
	queue_redraw()


func pickup_chest() -> void:
	chest_picked_up = true
	queue_redraw()


func _draw() -> void:
	if not show_debug_walls:
		return
	for seg in get_wall_segments():
		draw_line(IsoMath.project(seg["a"]), IsoMath.project(seg["b"]), Color.RED, 2.0)
	var chest := get_chest_obstacle()
	if chest_picked_up:
		return
	var screen_center: Vector2 = IsoMath.project(chest["center"])
	var r: float = chest["radius"] * IsoMath.PPM * 0.6
	if chest_locked:
		draw_circle(screen_center, r, Color(1.0, 0.85, 0.1, 0.7))   # gold = locked
		draw_arc(screen_center, r, 0.0, TAU, 24, Color(0.8, 0.6, 0.0), 2.0)
	else:
		draw_circle(screen_center, r, Color(0.65, 0.65, 0.65, 0.7)) # grey = unlocked


# Convert a texture-space pixel coordinate to world meters, accounting for the
# sprite's scale and centered-origin placement in the scene.
func _texture_pixel_to_world(tex_px: Vector2, sprite: Sprite2D) -> Vector2:
	var tex_size: Vector2 = sprite.texture.get_size()
	var screen_offset: Vector2 = (tex_px - tex_size * 0.5) * sprite.scale
	var screen_pos: Vector2 = sprite.position + screen_offset
	return IsoMath.unproject(screen_pos)


func get_wall_segments() -> Array:
	# Lines are flush with the floor diamond edges, not the alpha-detected wall base
	# (which tilts due to 3D wall thickness in the art).
	# Door gap on the back wall: world x ∈ [0.28, 2.61] from alpha analysis.
	return [
		{"a": Vector2(-4.54,  3.56), "b": Vector2( 0.28,  3.56)},  # back wall, left of door
		{"a": Vector2( 2.61,  3.56), "b": Vector2(10.97,  3.56)},  # back wall, right of door
		{"a": Vector2(-4.54, -11.94), "b": Vector2(-4.54,  3.56)}, # left wall
	]


# Axis-aligned bounding rectangle of the room floor in world meters.
# Derived from wall endpoints — not from Floor.png alpha (which has debris).
func get_room_bounds() -> Rect2:
	var wx: Sprite2D = $Background/Wall_X
	var wy: Sprite2D = $Background/Wall_Y
	var junction := _texture_pixel_to_world(_WX_SEG1_A, wx)  # shared corner = (x_min, y_max)
	var x_max    := _texture_pixel_to_world(_WX_SEG2_B, wx).x
	var y_min    := _texture_pixel_to_world(_WY_SEG_A,  wy).y
	return Rect2(Vector2(junction.x, y_min), Vector2(x_max - junction.x, junction.y - y_min))


func get_door_centers() -> Array:
	return [Vector2(1.44, 3.56)]  # midpoint of door gap at the back wall's y


func get_chest_obstacle() -> Dictionary:
	# Chest at floor centroid so it stays centered if the sprite ever moves.
	return {"center": get_room_bounds().get_center(), "radius": 0.75}
