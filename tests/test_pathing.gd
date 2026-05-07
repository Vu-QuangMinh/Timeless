## Test runner for Pathfinder, PathSmoother, and MovePath.
## Run headless: godot --headless -s tests/test_pathing.gd
## Exits 0 on all pass, 1 on any failure.

extends SceneTree

const PF  := preload("res://scripts/pathing/pathfinder.gd")
const PS  := preload("res://scripts/pathing/path_smoother.gd")
const MP  := preload("res://scripts/pathing/move_path.gd")
const TC  := preload("res://autoloads/time_calculator.gd")

const EPS := 0.5   # pixel tolerance for position checks
const EPS_F := 0.01  # float tolerance

var _pass := 0
var _fail := 0

func _init() -> void:
	_run_all()
	print("\n--- Results: %d passed, %d failed ---" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _run_all() -> void:
	_test_pathfinder()
	_test_smoother()
	_test_movepath()

# ---------------------------------------------------------------------------
# Pathfinder tests
# ---------------------------------------------------------------------------

func _test_pathfinder() -> void:
	print("Pathfinder")

	# 1 — Straight line, no obstacles
	var raw := PF.compute(Vector2(0, 0), Vector2(100, 0), [], [])
	_assert("straight no obstacles: has path", not raw.is_empty())
	_assert("straight no obstacles: starts at origin", raw[0].distance_to(Vector2(0, 0)) < EPS)
	_assert("straight no obstacles: ends at goal", raw[-1].distance_to(Vector2(100, 0)) < EPS)

	# 2 — Path around a single circle at (50, 0), radius 20 (inflated internally)
	var circle := [{center = Vector2(50, 0), radius = 20.0}]
	var raw2 := PF.compute(Vector2(0, 0), Vector2(100, 0), circle, [])
	_assert("around circle: has path", not raw2.is_empty())
	_assert("around circle: starts at origin", raw2[0].distance_to(Vector2(0, 0)) < EPS)
	_assert("around circle: ends at goal",    raw2[-1].distance_to(Vector2(100, 0)) < EPS)
	# No waypoint should be closer than (radius+CHAR_RADIUS) to the circle center
	var min_dist := INF
	for p: Vector2 in raw2:
		min_dist = minf(min_dist, p.distance_to(Vector2(50, 0)))
	_assert("around circle: path clears inflated obstacle",
		min_dist >= 20.0 + PF.CHAR_RADIUS - EPS)

	# 3 — Path through a doorway (wall at y=320, gap from x=-24 to x=24)
	var wall_left  := PackedVector2Array([Vector2(-320, 320), Vector2(-24, 320)])
	var wall_right := PackedVector2Array([Vector2(24, 320), Vector2(320, 320)])
	var raw3 := PF.compute(Vector2(0, 100), Vector2(0, 400), [], [wall_left, wall_right])
	_assert("through doorway: has path", not raw3.is_empty())
	_assert("through doorway: goal reached", raw3[-1].distance_to(Vector2(0, 400)) < EPS)

	# 4 — No path: start sits inside a massive inflated obstacle → all edges blocked
	var huge := [{center = Vector2(50, 0), radius = 2000.0}]
	var raw4 := PF.compute(Vector2(0, 0), Vector2(100, 0), huge, [])
	_assert("no path: unreachable", raw4.is_empty())

# ---------------------------------------------------------------------------
# PathSmoother tests
# ---------------------------------------------------------------------------

func _test_smoother() -> void:
	print("PathSmoother")

	# 1 — Single line: two waypoints → one line segment, no arcs
	var pts1: Array[Vector2] = [Vector2(0, 0), Vector2(100, 0)]
	var path1 := PS.smooth(pts1)
	_assert("2 waypoints: one line segment", path1.segments.size() == 1)
	_assert("2 waypoints: segment is line", path1.segments[0].type == "line")
	_assert_near("2 waypoints: no angular change", path1.total_angular_change(), 0.0)

	# 2 — 90° bend: three waypoints [A, B, C] with a right-angle turn at B
	# A=(0,0), B=(100,0), C=(100,100) — turn right by 90°
	var pts2: Array[Vector2] = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)]
	var path2 := PS.smooth(pts2)
	_assert("90° bend: has arc", path2.total_angular_change() > 0.01)
	_assert_near("90° bend: angular change = PI/2", path2.total_angular_change(), PI * 0.5)
	# Endpoints preserved
	_assert("90° bend: starts at A",
		path2.position_at(0.0).distance_to(Vector2(0, 0)) < EPS)
	_assert("90° bend: ends at C",
		path2.position_at(1.0).distance_to(Vector2(100, 100)) < EPS)

	# 3 — Zigzag: [A, B, C, D] with two 90° bends
	var pts3: Array[Vector2] = [
		Vector2(0, 0), Vector2(50, 0), Vector2(50, 50), Vector2(100, 50)
	]
	var path3 := PS.smooth(pts3)
	var arc_count := 0
	for s in path3.segments:
		if s.type == "arc":
			arc_count += 1
	_assert("zigzag: has 2 arcs", arc_count == 2)
	_assert_near("zigzag: total angular = PI", path3.total_angular_change(), PI)

# ---------------------------------------------------------------------------
# MovePath tests
# ---------------------------------------------------------------------------

func _test_movepath() -> void:
	print("MovePath")

	# Straight line: 160px = 10m, AGI=0, no weight, no turns
	var pts: Array[Vector2] = [Vector2(0, 0), Vector2(160, 0)]
	var path := PS.smooth(pts)

	_assert_near("160px straight: distance_meters",  path.total_distance_meters(), 10.0)
	_assert_near("160px straight: angular_change",   path.total_angular_change(),  0.0)

	# time_cost should match TimeCalculator.move_time(10m, agi=0, eff_kg=0, angular=0)
	var expected_time := TC.move_time(10.0, 0, 0.0, 0.0)
	_assert_near("160px straight: time_cost matches TC", path.time_cost(0, 0.0), expected_time)

	# position_at endpoints
	_assert("pos_at(0) = start", path.position_at(0.0).distance_to(Vector2(0, 0)) < EPS)
	_assert("pos_at(1) = end",   path.position_at(1.0).distance_to(Vector2(160, 0)) < EPS)
	_assert("pos_at(0.5) = mid", path.position_at(0.5).distance_to(Vector2(80, 0)) < EPS)

	# With weight: 100kg, str=0 → eff_weight=100, multiplier=2.0 → travel time doubles
	var expected_weighted := TC.move_time(10.0, 0, 100.0, 0.0)
	_assert_near("weighted time_cost", path.time_cost(0, 100.0), expected_weighted)

# ---------------------------------------------------------------------------
# Assert helpers
# ---------------------------------------------------------------------------

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  PASS  %s" % label)
		_pass += 1
	else:
		print("  FAIL  %s" % label)
		_fail += 1

func _assert_near(label: String, got: float, expected: float) -> void:
	if absf(got - expected) < EPS_F:
		print("  PASS  %s" % label)
		_pass += 1
	else:
		print("  FAIL  %s  got=%.4f  expected=%.4f" % [label, got, expected])
		_fail += 1
