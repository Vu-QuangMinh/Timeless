extends Node

const TURN_BUDGET_S := 10.0
const TOTAL_TURNS := 4
const TOTAL_BUDGET_S := 45.0
const ANIMATION_SPEED_MULTIPLIER := 5.0

signal mission_ended()

enum Phase { PLANNING, PREDICT, COMMIT }

var phase: Phase = Phase.PLANNING
var global_time_remaining: float = TOTAL_BUDGET_S
var mission_active: bool = false


func start_mission(duration: float) -> void:
	global_time_remaining = duration
	mission_active = true
	phase = Phase.PLANNING


func advance_timer(seconds: float) -> void:
	if not mission_active:
		return
	global_time_remaining = maxf(0.0, global_time_remaining - seconds)
	if global_time_remaining <= 0.0:
		mission_active = false
		mission_ended.emit()
