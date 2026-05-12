extends SceneTree

# Phase 5 patrol persistence: save_edits_to writes a `patrols` array to the
# JSON; _apply_saved_edits (via _apply_patrols) restores it after spawned
# scenes. Round-trips through a palette-spawned guard so the guard re-appears
# on reload. Also exercises backward-compat (no `patrols` key) and the drift
# case where a patrol references a guard not in the scene.
# Run: godot --headless -s tests/test_patrol_phase5.gd


func _initialize() -> void:
	var fail := 0
	var pass_ := 0
	var scratch := "user://test_patrol_phase5.json"

	# Wipe any leftover from a prior run.
	if FileAccess.file_exists(scratch):
		DirAccess.remove_absolute(scratch)

	# ── Part A: save side ─────────────────────────────────────────────────
	var lvl: Node = load("res://scenes/level_1/level_1.tscn").instantiate()
	lvl.current_edits_path = scratch
	root.add_child(lvl)
	await process_frame
	await process_frame  # let _init_editor_state finish (it call_deferreds)
	await process_frame

	var em: Node = lvl.get_node("EditMode")
	em.call("_toggle")  # activate F4
	await process_frame

	# Spawn fake_enemy via the palette path so it carries palette_source
	# metadata — that's what makes it survive the spawned_scenes reload step.
	var palette_path := "res://assets/palette/Enemy/fake_enemy/fake_enemy.tscn"
	em.set("_drag_payload", {
		"type": "scene",
		"path": palette_path,
		"category": "Enemy",
		"name": "fake_enemy",
		"ghost_scale": Vector2.ONE,
	})
	em.call("_spawn_palette_asset", Vector2(50.0, 50.0))
	await process_frame

	var objects: Node = lvl.get_node("Objects")
	var guard_name := "fake_enemy_1"
	var enemy: Node2D = objects.get_node_or_null(guard_name)
	if enemy == null:
		printerr("FAIL  spawn did not create Objects/%s" % guard_name)
		quit(1)
		return
	pass_ += 1
	print("PASS  palette spawn created %s" % guard_name)

	# Drive Phase 2 actions to populate patrol data.
	em.call("_on_object_button_pressed", enemy)
	await process_frame
	em.call("_patrol_toggle_edit_mode")
	em.call("_patrol_add_point_at", Vector2(-2.0, 0.0))
	em.call("_patrol_add_point_at", Vector2(-2.0, 1.0))
	em.call("_patrol_add_point_at", Vector2(-3.0, 1.0))
	em.call("_patrol_exit_edit_mode")

	# 1. Save → no error.
	var err: String = lvl.save_edits_to(scratch)
	if err == "":
		pass_ += 1
		print("PASS  save_edits_to returned no error")
	else:
		fail += 1
		printerr("FAIL  save_edits_to error: %s" % err)

	# 2. JSON contains a `patrols` array with our entry, points in [[x,y]] form.
	var f := FileAccess.open(scratch, FileAccess.READ)
	if f == null:
		printerr("FAIL  could not read scratch JSON")
		quit(1)
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	var patrols_arr: Array = parsed.get("patrols", [])
	if patrols_arr.size() == 1 and patrols_arr[0]["guard_name"] == guard_name:
		pass_ += 1
		print("PASS  JSON has 1 patrol entry for guard '%s'" % guard_name)
	else:
		fail += 1
		printerr("FAIL  expected 1 patrol for %s, got %s" % [guard_name, patrols_arr])

	var saved_pts: Array = patrols_arr[0]["points"]
	if saved_pts.size() == 3 \
			and saved_pts[0] == [-2.0, 0.0] \
			and saved_pts[1] == [-2.0, 1.0] \
			and saved_pts[2] == [-3.0, 1.0]:
		pass_ += 1
		print("PASS  points serialized as [[x,y], ...] in world meters")
	else:
		fail += 1
		printerr("FAIL  points = %s" % [saved_pts])

	if patrols_arr[0]["loop_mode"] == "ping_pong":
		pass_ += 1
		print("PASS  loop_mode = 'ping_pong' persisted")
	else:
		fail += 1
		printerr("FAIL  loop_mode = '%s'" % patrols_arr[0]["loop_mode"])

	# 3. Empty-points guards are NOT persisted. Auto-select another node to
	# trigger Phase 1's _patrol_entry_for which creates an empty entry; that
	# entry should be filtered out of the save.
	em.call("_patrol_toggle_edit_mode")  # exit (no-op if already out)
	# Force-add a guard with no points via _patrol_data direct write — closer
	# to the auto-init path Phase 1 takes on selection.
	(em.get("_patrol_data") as Dictionary)["fake_enemy_ghost"] = {
		"points": [] as Array[Vector2],
		"loop_mode": "ping_pong",
	}
	lvl.save_edits_to(scratch)
	f = FileAccess.open(scratch, FileAccess.READ)
	parsed = JSON.parse_string(f.get_as_text())
	f.close()
	patrols_arr = parsed.get("patrols", [])
	var names := []
	for p in patrols_arr:
		names.append(p["guard_name"])
	if not ("fake_enemy_ghost" in names) and (guard_name in names):
		pass_ += 1
		print("PASS  empty-points guard excluded from save (saved: %s)" % [names])
	else:
		fail += 1
		printerr("FAIL  empty-points filter broken (saved: %s)" % [names])

	# Tear down the first level.
	lvl.queue_free()
	await process_frame
	await process_frame

	# ── Part B: load side (round-trip) ───────────────────────────────────
	var lvl2: Node = load("res://scenes/level_1/level_1.tscn").instantiate()
	lvl2.current_edits_path = scratch
	root.add_child(lvl2)
	await process_frame
	await process_frame
	await process_frame  # _init_editor_state is call_deferred

	var em2: Node = lvl2.get_node("EditMode")
	var pdata2: Dictionary = em2.get("_patrol_data")
	if pdata2.has(guard_name):
		pass_ += 1
		print("PASS  after reload, _patrol_data has '%s'" % guard_name)
	else:
		fail += 1
		printerr("FAIL  reload did not restore patrol data (keys=%s)" % [pdata2.keys()])

	var restored_pts: Array = (pdata2[guard_name] as Dictionary)["points"]
	if restored_pts.size() == 3 \
			and restored_pts[0] == Vector2(-2.0, 0.0) \
			and restored_pts[1] == Vector2(-2.0, 1.0) \
			and restored_pts[2] == Vector2(-3.0, 1.0):
		pass_ += 1
		print("PASS  restored points equal saved points (as Vector2)")
	else:
		fail += 1
		printerr("FAIL  restored pts = %s" % [restored_pts])

	# Guard re-appeared via spawned_scenes (it has palette_source metadata).
	var objects2: Node = lvl2.get_node("Objects")
	if objects2.get_node_or_null(guard_name) != null:
		pass_ += 1
		print("PASS  guard '%s' re-instantiated via spawned_scenes" % guard_name)
	else:
		fail += 1
		printerr("FAIL  guard not re-instantiated")

	lvl2.queue_free()
	await process_frame
	await process_frame

	# ── Part C: backward compatibility ───────────────────────────────────
	# Hand-write a save with no `patrols` key — _apply_saved_edits should
	# treat it as empty and not error out.
	var legacy := {
		"version": 2,
		"transforms": [],
		"deleted": [],
		"spawned_scenes": [],
		# no `patrols`
	}
	var legacy_path := "user://test_patrol_phase5_legacy.json"
	var lf := FileAccess.open(legacy_path, FileAccess.WRITE)
	lf.store_string(JSON.stringify(legacy, "\t"))
	lf.close()

	var lvl3: Node = load("res://scenes/level_1/level_1.tscn").instantiate()
	lvl3.current_edits_path = legacy_path
	root.add_child(lvl3)
	await process_frame
	await process_frame
	await process_frame
	var em3: Node = lvl3.get_node("EditMode")
	var pdata3: Dictionary = em3.get("_patrol_data")
	if pdata3.is_empty():
		pass_ += 1
		print("PASS  legacy save (no patrols key) loads cleanly with empty _patrol_data")
	else:
		fail += 1
		printerr("FAIL  legacy load populated _patrol_data: %s" % [pdata3.keys()])
	lvl3.queue_free()
	await process_frame
	DirAccess.remove_absolute(legacy_path)

	# ── Part D: drift — patrols reference a guard not in the scene ───────
	var drift := {
		"version": 2,
		"transforms": [],
		"deleted": [],
		"spawned_scenes": [],
		"patrols": [
			{
				"guard_name": "phantom_enemy",
				"points": [[1.0, 2.0], [3.0, 4.0]],
				"loop_mode": "ping_pong",
			},
		],
	}
	var drift_path := "user://test_patrol_phase5_drift.json"
	var df := FileAccess.open(drift_path, FileAccess.WRITE)
	df.store_string(JSON.stringify(drift, "\t"))
	df.close()

	var lvl4: Node = load("res://scenes/level_1/level_1.tscn").instantiate()
	lvl4.current_edits_path = drift_path
	root.add_child(lvl4)
	await process_frame
	await process_frame
	await process_frame
	var em4: Node = lvl4.get_node("EditMode")
	var pdata4: Dictionary = em4.get("_patrol_data")
	# Spec: keep the data in memory even if the guard is missing.
	if pdata4.has("phantom_enemy") \
			and (pdata4["phantom_enemy"] as Dictionary)["points"].size() == 2:
		pass_ += 1
		print("PASS  drift case: patrol data preserved even though guard missing")
	else:
		fail += 1
		printerr("FAIL  drift data not preserved (pdata=%s)" % [pdata4])
	lvl4.queue_free()
	await process_frame
	DirAccess.remove_absolute(drift_path)
	DirAccess.remove_absolute(scratch)

	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
