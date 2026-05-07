## GameManager
## Owns mission-level state: global timer, win/lose conditions, current phase enum.
## Does NOT drive turn sequencing (that's TurnManager) or character logic.
## Does NOT handle input, rendering, or UI directly.

extends Node

signal global_timer_changed(seconds_remaining: float)
signal mission_failed()
signal mission_succeeded()

enum Phase { PLANNING, PREDICT, COMMIT }

const TURN_DURATION := 10.0  # seconds per turn committed
const ANIMATION_SPEED_MULTIPLIER: float = 5.0  # planning animations play 5× faster than real time

var global_timer: float = 60.0
var current_phase: Phase = Phase.PLANNING
var mission_active: bool = false

func start_mission(duration: float = 60.0) -> void:
	global_timer = duration
	current_phase = Phase.PLANNING
	mission_active = true
	emit_signal("global_timer_changed", global_timer)

## Called by TurnManager when a turn is committed.
## Advances timer by TURN_DURATION (or remaining time if < TURN_DURATION).
func advance_timer() -> void:
	if not mission_active:
		return
	var deduct := minf(TURN_DURATION, global_timer)
	global_timer -= deduct
	emit_signal("global_timer_changed", global_timer)
	if global_timer <= 0.0:
		_on_timer_expired()

func set_phase(phase: Phase) -> void:
	current_phase = phase

func _on_timer_expired() -> void:
	mission_active = false
	emit_signal("mission_failed")

func succeed_mission() -> void:
	if not mission_active:
		return
	mission_active = false
	emit_signal("mission_succeeded")
