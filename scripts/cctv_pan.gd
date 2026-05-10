extends PointLight2D

@export var pan_amplitude_deg: float = 30.0
@export var pan_period_sec: float = 4.0
@export var pan_enabled: bool = true
@export var base_rotation_deg: float = 0.0:
	set(value):
		base_rotation_deg = value
		_base_rotation = deg_to_rad(value)

var _time: float = 0.0
var _base_rotation: float = 0.0


func _ready() -> void:
	_base_rotation = deg_to_rad(base_rotation_deg)


func _process(delta: float) -> void:
	if pan_enabled:
		_time += delta
		var phase: float = sin(_time * TAU / max(pan_period_sec, 0.01))
		rotation = _base_rotation + deg_to_rad(pan_amplitude_deg) * phase
	_sync_overlay()


func _sync_overlay() -> void:
	var cone := get_node_or_null("ConeBeam")
	if cone == null:
		return
	if cone is Node2D:
		(cone as Node2D).scale = Vector2.ONE * texture_scale
	if cone is CanvasItem and cone.material is ShaderMaterial:
		var mat: ShaderMaterial = cone.material
		mat.set_shader_parameter("intensity", min(energy * 0.6, 1.5))
