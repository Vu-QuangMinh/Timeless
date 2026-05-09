extends SceneTree

func _init() -> void:
	var gm_script := preload("res://autoloads/game_manager.gd")
	var aq_script := preload("res://autoloads/action_queue.gd")

	var gm: Node = gm_script.new()
	var aq: Node = aq_script.new()

	var pass_count := 0
	var fail_count := 0

	# 1. advance_timer reduces timer by the given amount
	gm.start_mission(60.0)
	gm.advance_timer(10.0)
	if absf(gm.global_time_remaining - 50.0) < 0.001:
		pass_count += 1
	else:
		printerr("FAIL advance_timer_reduces: expected 50.0, got ", gm.global_time_remaining)
		fail_count += 1

	# 2. advance_timer clamps at 0 — never goes negative
	gm.start_mission(5.0)
	gm.advance_timer(10.0)
	if gm.global_time_remaining == 0.0:
		pass_count += 1
	else:
		printerr("FAIL advance_timer_clamps: expected 0.0, got ", gm.global_time_remaining)
		fail_count += 1

	# 3. mission_ended emitted and mission_active cleared when timer hits 0
	var tracker := {"ended": false}
	gm.mission_ended.connect(func(): tracker["ended"] = true)
	gm.start_mission(5.0)
	gm.advance_timer(10.0)
	if tracker["ended"] and not gm.mission_active:
		pass_count += 1
	else:
		printerr("FAIL mission_ended_signal: ended=", tracker["ended"], " active=", gm.mission_active)
		fail_count += 1

	# 4. advance_timer is a no-op when mission_active is false
	gm.start_mission(60.0)
	gm.mission_active = false
	var before: float = gm.global_time_remaining
	gm.advance_timer(10.0)
	if gm.global_time_remaining == before:
		pass_count += 1
	else:
		printerr("FAIL advance_noop_inactive: expected ", before, " got ", gm.global_time_remaining)
		fail_count += 1

	# 5. ActionQueue.reset clears the queue (simulates clear_queue_after_commit)
	aq.add_action(0, {"type": "move", "cost": 3.0, "start_time": 0.0})
	aq.add_action(0, {"type": "pick_lock", "cost": 6.0, "start_time": 3.0})
	aq.reset(0)
	if aq.get_queue(0).size() == 0:
		pass_count += 1
	else:
		printerr("FAIL queue_reset: expected 0, got ", aq.get_queue(0).size())
		fail_count += 1

	print("test_commit: %d passed, %d failed" % [pass_count, fail_count])
	gm.free()
	aq.free()
	quit(1 if fail_count > 0 else 0)
