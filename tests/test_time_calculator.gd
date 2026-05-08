## Test runner for TC.
## Run headless: godot --headless -s tests/test_time_calculator.gd
## No external framework required. Exits with code 0 on pass, 1 on failure.
## Does NOT test pathing, angular integration, or scene-dependent logic.

extends SceneTree

# Load directly so the test works headless without relying on autoload init order.
const TC := preload("res://autoloads/time_calculator.gd")

const EPSILON := 0.0001

var _pass := 0
var _fail := 0

func _init() -> void:
	_run_all()
	print("\n--- Results: %d passed, %d failed ---" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _run_all() -> void:
	_test_effective_movespeed()
	_test_effective_weight()
	_test_weight_time_multiplier()
	_test_move_time()
	_test_pickup_time()
	_test_takedown_time()
	_test_hack_time()
	_test_hack_range()
	_test_lock_time()
	_test_body_weight()
	_test_clamp_hold()

# ---------------------------------------------------------------------------

func _assert_near(label: String, got: float, expected: float) -> void:
	if abs(got - expected) < EPSILON:
		print("  PASS  %s" % label)
		_pass += 1
	else:
		print("  FAIL  %s  got=%.6f  expected=%.6f" % [label, got, expected])
		_fail += 1

func _assert_eq(label: String, got: Variant, expected: Variant) -> void:
	if got == expected:
		print("  PASS  %s" % label)
		_pass += 1
	else:
		print("  FAIL  %s  got=%s  expected=%s" % [label, str(got), str(expected)])
		_fail += 1

# ---------------------------------------------------------------------------

func _test_effective_movespeed() -> void:
	print("effective_movespeed")
	# AGI 0 → 5 m/s base
	_assert_near("agi=0",  TC.effective_movespeed(0),  5.0)
	# AGI 10 → 5*(1+1.0) = 10 m/s
	_assert_near("agi=10", TC.effective_movespeed(10), 10.0)
	# AGI 3 → 5*1.3 = 6.5
	_assert_near("agi=3",  TC.effective_movespeed(3),  6.5)

func _test_effective_weight() -> void:
	print("effective_weight")
	# STR 0 → no mitigation
	_assert_near("str=0 100kg",  TC.effective_weight(100.0, 0),  100.0)
	# STR 10 → weight/(1+1.0) = 50
	_assert_near("str=10 100kg", TC.effective_weight(100.0, 10), 50.0)
	# STR 1 → 100/1.1 ≈ 90.909
	_assert_near("str=1 100kg",  TC.effective_weight(100.0, 1),  100.0 / 1.1)

func _test_weight_time_multiplier() -> void:
	print("weight_time_multiplier")
	_assert_near("0kg",   TC.weight_time_multiplier(0.0),   1.0)
	_assert_near("100kg", TC.weight_time_multiplier(100.0), 2.0)
	_assert_near("50kg",  TC.weight_time_multiplier(50.0),  1.5)

func _test_move_time() -> void:
	print("move_time")
	# 10m, agi=0, 0kg, 0 angular → 10/5 = 2.0s
	_assert_near("10m agi=0 no weight no turn",
		TC.move_time(10.0, 0, 0.0, 0.0), 2.0)
	# 10m, agi=10 → speed=10, time=1.0s
	_assert_near("10m agi=10 no weight no turn",
		TC.move_time(10.0, 10, 0.0, 0.0), 1.0)
	# 0m, any agi, full circle turn (2π) → 0 travel + 1s turn cost
	_assert_near("0m agi=0 full circle",
		TC.move_time(0.0, 0, 0.0, 2.0 * PI), 1.0)
	# weight: 100kg eff, agi=0, 10m → travel=2.0 * multiplier(100)=2.0*2.0=4.0
	_assert_near("10m agi=0 100kg eff",
		TC.move_time(10.0, 0, 100.0, 0.0), 4.0)

func _test_pickup_time() -> void:
	print("pickup_time")
	# 0kg item, str=0, int=0 → base=1.0 * 1.0 / 1.0 = 1.0
	_assert_near("0kg str=0 int=0", TC.pickup_time(0.0, 0, 0), 1.0)
	# 0kg, int=10 → 1.0/2.0 = 0.5
	_assert_near("0kg int=10",      TC.pickup_time(0.0, 0, 10), 0.5)
	# 100kg raw, str=0 eff=100, multiplier=2.0, int=0 → 1.0*2.0/1.0 = 2.0
	_assert_near("100kg str=0 int=0", TC.pickup_time(100.0, 0, 0), 2.0)

func _test_takedown_time() -> void:
	print("takedown_time")
	# Guard, str=0 → 5/1.0 = 5.0
	_assert_near("guard str=0",  TC.takedown_time("guard", 0),  5.0)
	# Guard, str=10 → 5/2.0 = 2.5
	_assert_near("guard str=10", TC.takedown_time("guard", 10), 2.5)
	# Clerk, str=0 → 3.0
	_assert_near("clerk str=0",  TC.takedown_time("clerk", 0),  3.0)
	# Clerk, str=1 → 3/1.1 ≈ 2.727
	_assert_near("clerk str=1",  TC.takedown_time("clerk", 1),  3.0 / 1.1)

func _test_hack_time() -> void:
	print("hack_time")
	# CCTV, int=0 → 4/1.0 = 4.0
	_assert_near("cctv int=0",  TC.hack_time("cctv", 0),  4.0)
	# CCTV, int=10 → 4/2.0 = 2.0
	_assert_near("cctv int=10", TC.hack_time("cctv", 10), 2.0)
	# Door, int=0 → 6.0
	_assert_near("door int=0",    TC.hack_time("door", 0),    6.0)
	# Door, int=3 → 6/1.3 ≈ 4.615
	_assert_near("door int=3",    TC.hack_time("door", 3),    6.0 / 1.3)

func _test_hack_range() -> void:
	print("hack_range")
	# int=0 → 5*(1+0) = 5.0
	_assert_near("int=0",  TC.hack_range(0),  5.0)
	# int=10 → 5*(1+1.0) = 10.0
	_assert_near("int=10", TC.hack_range(10), 10.0)
	# int=3 → 5*1.3 = 6.5
	_assert_near("int=3",  TC.hack_range(3),  6.5)

func _test_lock_time() -> void:
	print("lock_time")
	# Level 1, stats 0+0 → 5/1.0 = 5.0
	_assert_near("L1 s0+s0",  TC.lock_time(1, 0, 0),  5.0)
	# Level 2, stats 0+0 → 10.0
	_assert_near("L2 s0+s0",  TC.lock_time(2, 0, 0),  10.0)
	# Level 3, stats 0+0 → 20.0
	_assert_near("L3 s0+s0",  TC.lock_time(3, 0, 0),  20.0)
	# Level 1, stat1=10 stat2=0 → 5/(1+0.5+0) = 5/1.5 ≈ 3.333
	_assert_near("L1 s10+s0", TC.lock_time(1, 10, 0), 5.0 / 1.5)
	# Level 1, stat1=10 stat2=10 → 5/(1+0.5+0.5) = 5/2.0 = 2.5
	_assert_near("L1 s10+s10",TC.lock_time(1, 10, 10),2.5)
	# Mechanical (AGI twice): agi=3 → 5/(1+0.05*3+0.05*3) = 5/(1+0.3) ≈ 3.846
	_assert_near("L1 mechanical agi=3", TC.lock_time(1, 3, 3), 5.0 / 1.3)

func _test_body_weight() -> void:
	print("body_weight")
	# base 65, str=0, agi=0 → 65
	_assert_near("65 str=0 agi=0", TC.body_weight(65.0, 0, 0), 65.0)
	# str=3 → +6; agi=1 → -2; net = 65+6-2 = 69
	_assert_near("65 str=3 agi=1", TC.body_weight(65.0, 3, 1), 69.0)
	# Cat Burglar profile: str=0 agi=3 → 65+0-6 = 59
	_assert_near("cat burglar profile", TC.body_weight(65.0, 0, 3), 59.0)
	# Brawler profile: str=3 agi=1 → 65+6-2 = 69
	_assert_near("brawler profile", TC.body_weight(65.0, 3, 1), 69.0)

func _test_clamp_hold() -> void:
	print("clamp_hold_duration")
	_assert_near("5.0",  TC.clamp_hold_duration(5.0),  5.0)
	_assert_near("0.0",  TC.clamp_hold_duration(0.0),  0.0)
	_assert_near("8.0 → 5.0", TC.clamp_hold_duration(8.0),  5.0)
	_assert_near("-1 → 0.0",  TC.clamp_hold_duration(-1.0), 0.0)
	_assert_near("3.2",  TC.clamp_hold_duration(3.2),  3.2)
