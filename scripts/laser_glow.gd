extends Node2D

@export var beam_length: float = 500.0
@export var core_thickness: float = 1.0
@export var inner_glow_thickness: float = 1.0
@export var outer_glow_thickness: float = 1.0
@export var core_color: Color = Color(0.745, 0.0, 0.0, 1.0)
@export var inner_glow_color: Color = Color(0.745, 0.0, 0.0, 0.55)
@export var outer_glow_color: Color = Color(0.745, 0.0, 0.0, 0.25)
@export var glitch_amount: float = 1.05
@export var glitch_rate: float = 4.2
@export var flicker_min: float = 0.7
@export var flicker_max: float = 1.0

var _time: float = 0.0
var _jitter: float = 0.0
var _flicker: float = 1.0
var _last_step: int = -1


func _process(delta: float) -> void:
	_time += delta
	var step: int = int(_time * glitch_rate)
	if step != _last_step:
		_last_step = step
		seed(step)
		_jitter = randf_range(-1.0, 1.0) * glitch_amount
		_flicker = randf_range(flicker_min, flicker_max)
	queue_redraw()


func _draw() -> void:
	var outer_y: float = -outer_glow_thickness * 0.5 + _jitter
	var outer_c: Color = Color(outer_glow_color.r, outer_glow_color.g, outer_glow_color.b, outer_glow_color.a * _flicker)
	draw_rect(Rect2(0.0, outer_y, beam_length, outer_glow_thickness), outer_c)

	var inner_y: float = -inner_glow_thickness * 0.5 + _jitter
	var inner_c: Color = Color(inner_glow_color.r, inner_glow_color.g, inner_glow_color.b, inner_glow_color.a * _flicker)
	draw_rect(Rect2(0.0, inner_y, beam_length, inner_glow_thickness), inner_c)

	var core_y: float = -core_thickness * 0.5 + _jitter
	var core_c: Color = Color(core_color.r, core_color.g, core_color.b, core_color.a * _flicker)
	draw_rect(Rect2(0.0, core_y, beam_length, core_thickness), core_c)
