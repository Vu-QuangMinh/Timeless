extends SceneTree

# Duck-typed stubs — action _init accepts untyped `pc`, so these satisfy all field reads.
class MockData:
	var char_agi := 2
	var char_str := 2
	var char_int := 2
	func effective_weight() -> float: return 70.0

class MockPC:
	var char_id := 0
	var char_data: MockData
	func _init() -> void:
		char_data = MockData.new()


func _init() -> void:
	var ok := true

	# Instantiate ActionQueue script directly (it extends Node, not a singleton here).
	var aq: Node = preload("res://autoloads/action_queue.gd").new()
	# Read TURN_BUDGET_S from game_manager constants without instantiating a node.
	const BUDGET := 10.0  # GameManager.TURN_BUDGET_S

	var pc := MockPC.new()

	# ── Build two 3 m straight paths ────────────────────────────────────────────
	var seg1 := MovePath.Segment.new()
	seg1.is_arc = false; seg1.start = Vector2(0, 0); seg1.end = Vector2(3, 0); seg1.length = 3.0
	var path1 := MovePath.from_segments([seg1])

	var seg2 := MovePath.Segment.new()
	seg2.is_arc = false; seg2.start = Vector2(3, 0); seg2.end = Vector2(6, 0); seg2.length = 3.0
	var path2 := MovePath.from_segments([seg2])

	var action1 := ActionMove.new(pc, path1)
	var action2 := ActionMove.new(pc, path2)

	# ── Test 1: queue 1 action → size == 1, used == cost ────────────────────────
	aq.reset(0)
	var d1 := action1.to_dict()
	d1["start_time"] = 0.0
	aq.add_action(0, d1)
	ok = _check("queue 1: size == 1", aq.get_queue(0).size() == 1, ok)
	ok = _check("queue 1: used == cost", absf(_sum(aq, 0) - action1.cost) < 0.001, ok)

	# ── Test 2: queue 2 actions → size == 2, used == sum ────────────────────────
	var d2 := action2.to_dict()
	d2["start_time"] = action1.cost
	aq.add_action(0, d2)
	ok = _check("queue 2: size == 2", aq.get_queue(0).size() == 2, ok)
	ok = _check("queue 2: used == sum", absf(_sum(aq, 0) - (action1.cost + action2.cost)) < 0.001, ok)

	# ── Test 3: undo → size == 1 ────────────────────────────────────────────────
	aq.undo_last(0)
	ok = _check("undo: size == 1", aq.get_queue(0).size() == 1, ok)

	# ── Test 4: reset → size == 0 ────────────────────────────────────────────────
	aq.reset(0)
	ok = _check("reset: size == 0", aq.get_queue(0).size() == 0, ok)

	# ── Test 5: remaining == TURN_BUDGET_S after reset ──────────────────────────
	var remaining := BUDGET - _sum(aq, 0)
	ok = _check("remaining after reset == TURN_BUDGET_S", absf(remaining - BUDGET) < 0.001, ok)

	aq.free()
	quit(0 if ok else 1)


func _sum(aq: Node, char_id: int) -> float:
	var total := 0.0
	for entry in aq.get_queue(char_id):
		total += entry["cost"]
	return total


func _check(label: String, condition: bool, ok: bool) -> bool:
	if condition:
		print("  PASS  %s" % label)
	else:
		print("  FAIL  %s" % label)
	return ok and condition
