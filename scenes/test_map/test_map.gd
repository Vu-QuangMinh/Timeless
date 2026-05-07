## TestMap
## Draws the 20m×20m test room (walls, doors, windows, chest) using _draw().
## All geometry is visual only in this build — collision walls come in a later phase.
## Does NOT spawn characters, manage guards, or handle game logic.
## Coordinate system: 1 world unit = 1 pixel, 32px = 1 meter. Origin at room center.

class_name TestMap
extends Node2D

# --- Scale constants (pixels) ---
const PPM    := 32.0   # pixels per meter
const HALF   := 320.0  # 10m half-extent of room interior (20m×20m room)
const WALL_T := 32.0   # 1m wall thickness
const DOOR_H := 48.0   # half of 3m door opening
const WIN_W  := 32.0   # 1m window width (half = 16px)

# Derived: length from wall edge to door gap on one side
const _HALF_WALL := HALF - DOOR_H  # 272px

## World-space position of each door center (used by main.gd for spawn).
const DOOR_SOUTH := Vector2(0.0,   HALF)
const DOOR_NORTH := Vector2(0.0,  -HALF)
const DOOR_WEST  := Vector2(-HALF, 0.0)
const DOOR_EAST  := Vector2( HALF, 0.0)

## Spawn point: just inside the south (bottom) door, 3 character-widths of space.
const SPAWN_ORIGIN := Vector2(0.0, HALF - 24.0)

# --- Colors ---
const C_FLOOR   := Color(0.18, 0.18, 0.20)
const C_WALL    := Color(0.55, 0.55, 0.60)
const C_DOOR    := Color(0.45, 0.30, 0.15)
const C_WINDOW  := Color(0.50, 0.75, 0.90)
const C_CHEST   := Color(0.75, 0.60, 0.20)
const C_LOCK    := Color(0.85, 0.15, 0.15)

func _draw() -> void:
	_draw_floor()
	_draw_walls()
	_draw_doors()
	_draw_windows()
	_draw_chest()

func _draw_floor() -> void:
	draw_rect(Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0), C_FLOOR)

func _draw_walls() -> void:
	# Each side: two wall segments flanking the door gap.
	# Walls sit OUTSIDE the interior (between HALF and HALF+WALL_T).
	var w := WALL_T

	# South wall — two horizontal bars
	draw_rect(Rect2(-HALF,   HALF, _HALF_WALL, w), C_WALL)  # left of door
	draw_rect(Rect2( DOOR_H, HALF,  _HALF_WALL, w), C_WALL)  # right of door

	# North wall
	draw_rect(Rect2(-HALF,  -HALF - w, _HALF_WALL, w), C_WALL)
	draw_rect(Rect2( DOOR_H,-HALF - w,  _HALF_WALL, w), C_WALL)

	# West wall — two vertical bars
	draw_rect(Rect2(-HALF - w, -HALF,   w, _HALF_WALL), C_WALL)  # top of door
	draw_rect(Rect2(-HALF - w,  DOOR_H, w, _HALF_WALL), C_WALL)  # bottom of door

	# East wall
	draw_rect(Rect2(HALF, -HALF,   w, _HALF_WALL), C_WALL)
	draw_rect(Rect2(HALF,  DOOR_H, w, _HALF_WALL), C_WALL)

	# Corner fills
	draw_rect(Rect2(-HALF - w,  HALF,      w, w), C_WALL)  # SW
	draw_rect(Rect2( HALF,      HALF,      w, w), C_WALL)  # SE
	draw_rect(Rect2(-HALF - w, -HALF - w,  w, w), C_WALL)  # NW
	draw_rect(Rect2( HALF,     -HALF - w,  w, w), C_WALL)  # NE

func _draw_doors() -> void:
	var w := WALL_T
	# South
	draw_rect(Rect2(-DOOR_H, HALF, DOOR_H * 2.0, w), C_DOOR)
	# North
	draw_rect(Rect2(-DOOR_H, -HALF - w, DOOR_H * 2.0, w), C_DOOR)
	# West
	draw_rect(Rect2(-HALF - w, -DOOR_H, w, DOOR_H * 2.0), C_DOOR)
	# East
	draw_rect(Rect2(HALF, -DOOR_H, w, DOOR_H * 2.0), C_DOOR)

func _draw_windows() -> void:
	# Two windows per half-wall, per wall (8 total).
	# Divide each half-wall (296px) into 3 equal sections; windows at 1/3 and 2/3.
	var seg := _HALF_WALL / 3.0
	var ww  := WIN_W
	var wh  := WALL_T

	# Helper: draw a window rect centered at `cx, cy` with given width/height
	# South wall (horizontal): windows in y=[HALF, HALF+WALL_T]
	_draw_h_windows( HALF,  1.0, ww, wh, seg)
	# North wall
	_draw_h_windows(-HALF - WALL_T, 1.0, ww, wh, seg)
	# West wall (vertical)
	_draw_v_windows(-HALF - WALL_T, 1.0, WALL_T, ww, seg)
	# East wall
	_draw_v_windows( HALF, 1.0, WALL_T, ww, seg)

func _draw_h_windows(wall_y: float, _side: float, ww: float, wh: float, seg: float) -> void:
	# Left half: from -HALF to -DOOR_H
	var lx := -HALF + seg - ww * 0.5
	draw_rect(Rect2(lx,        wall_y, ww, wh), C_WINDOW)
	draw_rect(Rect2(lx + seg,  wall_y, ww, wh), C_WINDOW)
	# Right half: from DOOR_H to HALF
	var rx := DOOR_H + seg - ww * 0.5
	draw_rect(Rect2(rx,        wall_y, ww, wh), C_WINDOW)
	draw_rect(Rect2(rx + seg,  wall_y, ww, wh), C_WINDOW)

func _draw_v_windows(wall_x: float, _side: float, ww: float, wh: float, seg: float) -> void:
	# Top half: from -HALF to -DOOR_H
	var ty := -HALF + seg - wh * 0.5
	draw_rect(Rect2(wall_x, ty,        ww, wh), C_WINDOW)
	draw_rect(Rect2(wall_x, ty + seg,  ww, wh), C_WINDOW)
	# Bottom half: from DOOR_H to HALF
	var by := DOOR_H + seg - wh * 0.5
	draw_rect(Rect2(wall_x, by,        ww, wh), C_WINDOW)
	draw_rect(Rect2(wall_x, by + seg,  ww, wh), C_WINDOW)

func _draw_chest() -> void:
	# Chest at center: 48×48px box (3m×3m), gold. Red lock indicator on top.
	var size := Vector2(48.0, 48.0)
	var origin := -size * 0.5
	draw_rect(Rect2(origin, size), C_CHEST)
	# Lock indicator: small red square upper half
	draw_rect(Rect2(origin.x + 4.0, origin.y + 4.0, size.x - 8.0, size.y * 0.5 - 2.0), C_LOCK)
	# Label
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-18.0, size.y * 0.5 + 14.0), "CHEST (locked)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)

# ---------------------------------------------------------------------------
# Navigation geometry (used by Pathfinder)
# ---------------------------------------------------------------------------

## Returns the 8 wall segments as the inner-face boundaries of the room.
## Each entry is a PackedVector2Array of [p1, p2].
func get_wall_segments() -> Array[PackedVector2Array]:
	var segs: Array[PackedVector2Array] = []
	# South wall (y = HALF): left and right of door gap
	segs.append(PackedVector2Array([Vector2(-HALF, HALF), Vector2(-DOOR_H, HALF)]))
	segs.append(PackedVector2Array([Vector2( DOOR_H, HALF), Vector2( HALF,  HALF)]))
	# North wall (y = -HALF)
	segs.append(PackedVector2Array([Vector2(-HALF, -HALF), Vector2(-DOOR_H, -HALF)]))
	segs.append(PackedVector2Array([Vector2( DOOR_H, -HALF), Vector2( HALF,  -HALF)]))
	# West wall (x = -HALF)
	segs.append(PackedVector2Array([Vector2(-HALF, -HALF), Vector2(-HALF, -DOOR_H)]))
	segs.append(PackedVector2Array([Vector2(-HALF,  DOOR_H), Vector2(-HALF,  HALF)]))
	# East wall (x = HALF)
	segs.append(PackedVector2Array([Vector2(HALF, -HALF), Vector2(HALF, -DOOR_H)]))
	segs.append(PackedVector2Array([Vector2(HALF,  DOOR_H), Vector2(HALF,  HALF)]))
	return segs

## Returns the chest as a circular obstacle for the pathfinder.
## Radius = half the chest's visual width (12px). Pathfinder inflates by CHAR_RADIUS itself.
func get_chest_obstacle() -> Dictionary:
	return {center = Vector2.ZERO, radius = 24.0}
