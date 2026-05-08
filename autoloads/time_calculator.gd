class_name TimeCalculator

# All formulas in seconds. Pure math — no scene or autoload dependencies.

const WALK_SPEED_BASE: float = 1.4  # m/s at AGI 1, 70 kg
const HACK_BASE := {
	"cctv": 4.0,
	"terminal": 8.0,
	"safe": 12.0,
}
const PICK_BASE := 6.0
const TAKEDOWN_BASE := 3.0
const HOLD_BASE := 5.0
const PICKUP_BASE := 1.5


static func move_time(distance_m: float, agi: int, weight_kg: float) -> float:
	var speed: float = WALK_SPEED_BASE * (0.7 + 0.3 * float(agi)) * (70.0 / maxf(weight_kg, 1.0))
	return distance_m / max(speed, 0.01)


static func hack_time(target_type: String, int_stat: int) -> float:
	var base: float = HACK_BASE.get(target_type, 6.0)
	return base / max(float(int_stat), 1.0)


static func pick_lock_time(complexity: int, int_stat: int) -> float:
	return PICK_BASE * float(complexity) / max(float(int_stat), 1.0)


static func takedown_time(str_stat: int) -> float:
	return TAKEDOWN_BASE / max(float(str_stat), 1.0)


static func hold_hostage_time(str_stat: int) -> float:
	return HOLD_BASE / max(float(str_stat), 1.0)


static func pickup_time(item_weight_kg: float, str_stat: int) -> float:
	return PICKUP_BASE * max(item_weight_kg / (10.0 * float(str_stat)), 1.0)


static func struggle_duration(str_stat: int, n_guards: int) -> float:
	return (3.0 + 0.5 * float(str_stat)) / max(float(n_guards), 1.0)
