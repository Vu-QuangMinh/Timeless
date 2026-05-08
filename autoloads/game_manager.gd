extends Node

const TURN_BUDGET_S := 10.0
const TOTAL_TURNS := 4
const TOTAL_BUDGET_S := 45.0
const ANIMATION_SPEED_MULTIPLIER := 5.0

enum Phase { PLANNING, PREDICT, COMMIT }

var phase: Phase = Phase.PLANNING
var global_time_remaining: float = TOTAL_BUDGET_S
var mission_active: bool = false
