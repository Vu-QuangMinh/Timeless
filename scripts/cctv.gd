## CCTV
## Wall-mounted security camera. Pans ±pan_amplitude_deg around base_rotation_deg.
## Detection cone matches the ConeBeam polygon: local +Y axis, 320 px depth, ±20.6° half-angle.
## Call hack() to disable detection and hide the cone; restore() to re-enable.
##
## Planning note: the cone is frozen during Planning (atmosphere only, no panning).
## A full-sweep arc showing the danger zone would be a useful UX addition — future work.

class_name CCTV
extends PointLight2D

## Cone geometry — defaults match the ConeBeam polygon (0,0 / -120,320 / 120,320).
## fov_half_angle_deg = atan2(120, 320) * 180/PI ≈ 20.6°
@export var fov_half_angle_deg: float = 20.6
@export var view_distance_px:   float = 320.0

@export var pan_amplitude_deg: float = 30.0
@export var pan_period_sec:    float = 4.0
@export var pan_enabled:       bool  = true
@export var base_rotation_deg: float = 0.0:
	set(value):
		base_rotation_deg = value
		_base_rotation = deg_to_rad(value)

var _time: float = 0.0
var _base_rotation: float = 0.0
var cctv_id: int = -1
var is_hacked: bool = false

# Predict-phase snapshot — restored on Back to Planning.
var _predict_start_time: float = 0.0


func _ready() -> void:
	_base_rotation = deg_to_rad(base_rotation_deg)
	rotation = _base_rotation


func _process(delta: float) -> void:
	if not is_hacked and pan_enabled and GameManager.current_phase == GameManager.Phase.PREDICT:
		# Advance at game speed so the visual matches the discrete detection simulation
		# (10 game-seconds of panning compressed into 2 real seconds at 5× multiplier).
		_time += delta * GameManager.ANIMATION_SPEED_MULTIPLIER
		var phase: float = sin(_time * TAU / max(pan_period_sec, 0.01))
		rotation = _base_rotation + deg_to_rad(pan_amplitude_deg) * phase
	_sync_overlay()


func hack() -> void:
	is_hacked = true
	enabled = false
	var cone := get_node_or_null("ConeBeam")
	if cone:
		cone.visible = false


func restore() -> void:
	is_hacked = false
	enabled = true
	var cone := get_node_or_null("ConeBeam")
	if cone:
		cone.visible = true


func _sync_overlay() -> void:
	var cone := get_node_or_null("ConeBeam")
	if cone == null:
		return
	if cone is Node2D:
		(cone as Node2D).scale = Vector2.ONE * texture_scale
	if cone is CanvasItem and cone.material is ShaderMaterial:
		var mat: ShaderMaterial = cone.material
		mat.set_shader_parameter("intensity", min(energy * 0.6, 1.5))
