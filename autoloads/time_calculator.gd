## TimeCalculator
## Pure static math functions for every time/stat formula in the design doc.
## Does NOT reference nodes, scenes, or game state. Import-free — call as TimeCalculator.fn().
## Does NOT handle pathing, angular cost integration, or partial-action logic (those live in action_queue / character).

extends Node

# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

## Returns meters-per-second after AGI bonus.
static func effective_movespeed(agi: int) -> float:
	return 1.25 * (1.0 + 0.1 * agi)

## Returns kg of carried weight after STR mitigation.
static func effective_weight(raw_kg: float, str: int) -> float:
	return raw_kg / (1.0 + 0.1 * str)

## Returns a multiplier (≥1.0) applied to any timed action due to carried weight.
static func weight_time_multiplier(effective_kg: float) -> float:
	return 1.0 + 0.01 * effective_kg

## Seconds to travel `distance` meters, accounting for AGI, weight, and angular cost.
## `angular_radians` is the total cumulative angular change along the path (in radians).
## Direction-change cost: 1 second per full 2π of cumulative turning.
static func move_time(
	distance: float,
	agi: int,
	effective_kg: float,
	angular_radians: float
) -> float:
	var speed := effective_movespeed(agi)
	var base_travel := distance / speed
	var weighted := base_travel * weight_time_multiplier(effective_kg)
	var turn_cost := angular_radians / (2.0 * PI)  # 1s per full 360°
	return weighted + turn_cost

# ---------------------------------------------------------------------------
# Pick Up
# ---------------------------------------------------------------------------

## Seconds to pick up an object of `item_kg` (after lock weight is already added if locked).
## Weight slows the action; INT speeds it.
static func pickup_time(item_kg: float, str: int, int_stat: int) -> float:
	var eff_weight := effective_weight(item_kg, str)
	return (1.0 * weight_time_multiplier(eff_weight)) / (1.0 + 0.1 * int_stat)

# ---------------------------------------------------------------------------
# Takedown
# ---------------------------------------------------------------------------

## Base times by enemy type (seconds).
const TAKEDOWN_BASE := {
	"guard": 5.0,
	"clerk": 3.0,
}

static func takedown_time(enemy_type: String, str: int) -> float:
	var base: float = TAKEDOWN_BASE.get(enemy_type, 5.0)
	return base / (1.0 + 0.1 * str)

# ---------------------------------------------------------------------------
# Hack
# ---------------------------------------------------------------------------

## Base times by target type (seconds).
const HACK_BASE := {
	"cctv":        4.0,
	"tripwire":    4.0,
	"red_button":  6.0,
	"window":      5.0,
	"door":        6.0,
}

static func hack_time(target_type: String, int_stat: int) -> float:
	var base: float = HACK_BASE.get(target_type, 4.0)
	return base / (1.0 + 0.1 * int_stat)

## Hack range in meters.
static func hack_range(int_stat: int) -> float:
	return 5.0 * (1.0 + 0.1 * int_stat)

# ---------------------------------------------------------------------------
# Pick Lock
# ---------------------------------------------------------------------------

## Level → base time in seconds.
const LOCK_BASE_TIME := { 1: 5.0, 2: 10.0, 3: 20.0 }

## stat1 and stat2 are the two stats for the lock type:
##   Glass (smash) → AGI + STR
##   Digital       → AGI + INT
##   Mechanical    → AGI + AGI (pass agi twice)
static func lock_time(level: int, stat1: int, stat2: int) -> float:
	var base: float = LOCK_BASE_TIME.get(level, 5.0)
	return base / (1.0 + 0.05 * stat1 + 0.05 * stat2)

# ---------------------------------------------------------------------------
# Body Weight (for downed allies)
# ---------------------------------------------------------------------------

## Random body weight for a character. Call once at spawn; seed externally if reproducibility needed.
## Range 60–70 kg base, +2 per STR point, −2 per AGI point.
static func body_weight(base_kg: float, str: int, agi: int) -> float:
	return base_kg + 2.0 * str - 2.0 * agi

# ---------------------------------------------------------------------------
# Hold Hostage
# ---------------------------------------------------------------------------

## Clamps a requested hold duration to the [0, 5] second range.
static func clamp_hold_duration(requested: float) -> float:
	return clamp(requested, 0.0, 5.0)
