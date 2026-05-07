## Guard
## Visual enemy placeholder. Renders as an amber circle with a facing-direction line
## and a faint 120° FoV wedge. Stationary in the current build — AI / Predict-phase
## movement logic is out of scope until the Predict phase is implemented.

class_name Guard
extends CharacterBody2D

const GUARD_RADIUS   := 8.0          # pixels; 0.5 m at 16 px/m — same footprint as player
const FOV_HALF_RAD   := PI / 3.0     # 60° half-angle → 120° total FoV
const FOV_VISUAL_PX  := 48.0         # visual wedge length (3 m); game range is 20 m

const C_ACTIVE   := Color(1.0, 0.55, 0.10, 1.0)   # amber
const C_NEUTRAL  := Color(0.40, 0.40, 0.40, 1.0)  # grey when neutralised
const C_FOV_FILL := Color(1.0, 0.85, 0.20, 0.10)
const C_FOV_EDGE := Color(1.0, 0.85, 0.20, 0.28)

var guard_id: int        = 0
var facing_angle: float  = 0.0    # radians; Godot screen-space (0 = right, π/2 = down)
var is_neutralized: bool = false

# Predict-phase state — saved on enter, restored on Back to Planning.
var _predict_start_pos: Vector2
var _predict_start_facing: float = 0.0
var _predict_tween: Tween = null

func _ready() -> void:
	var col    := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = GUARD_RADIUS
	col.shape = circle
	add_child(col)

func _draw() -> void:
	draw_circle(Vector2.ZERO, GUARD_RADIUS, C_NEUTRAL if is_neutralized else C_ACTIVE)
	if is_neutralized:
		# Cross to signal downed state
		var r := GUARD_RADIUS * 0.55
		draw_line(Vector2(-r, -r), Vector2( r,  r), Color.WHITE, 1.5)
		draw_line(Vector2( r, -r), Vector2(-r,  r), Color.WHITE, 1.5)
		return

	_draw_fov()

	# Facing direction line
	var dir := Vector2(cos(facing_angle), sin(facing_angle))
	draw_line(Vector2.ZERO, dir * (GUARD_RADIUS + 5.0), Color.WHITE, 1.5)

func _draw_fov() -> void:
	const STEPS := 12
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	for i in range(STEPS + 1):
		var a := facing_angle - FOV_HALF_RAD + FOV_HALF_RAD * 2.0 * float(i) / STEPS
		pts.append(Vector2(cos(a), sin(a)) * FOV_VISUAL_PX)
	draw_colored_polygon(pts, C_FOV_FILL)

	var left  := Vector2(cos(facing_angle - FOV_HALF_RAD), sin(facing_angle - FOV_HALF_RAD))
	var right := Vector2(cos(facing_angle + FOV_HALF_RAD), sin(facing_angle + FOV_HALF_RAD))
	draw_line(Vector2.ZERO, left  * FOV_VISUAL_PX, C_FOV_EDGE, 1.0)
	draw_line(Vector2.ZERO, right * FOV_VISUAL_PX, C_FOV_EDGE, 1.0)
