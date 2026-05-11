extends SceneTree

# Phase 2 round-trip: build a synthetic palette asset, instantiate Level1 with
# a scratch save path, programmatically spawn the asset via EditMode, save,
# tear down, re-instantiate, verify the spawn re-appears at the same position.
# Run: godot --headless -s tests/test_palette_spawn.gd


const SCRATCH_PATH := "user://__test_palette_phase2.json"
const PALETTE_DIR := "res://assets/palette/Test/test_widget"
const TSCN_PATH := "res://assets/palette/Test/test_widget/test_widget.tscn"


func _initialize() -> void:
	var fail := 0
	var pass_ := 0

	# Build a minimal palette .tscn: Node2D root + Sprite2D child with the
	# CCTV.png texture (any valid texture works).
	DirAccess.make_dir_recursive_absolute(PALETTE_DIR)
	var widget_root := Node2D.new()
	widget_root.name = "TestWidget"
	var widget_sprite := Sprite2D.new()
	widget_sprite.name = "Sprite"
	widget_sprite.centered = true
	widget_sprite.texture = load("res://assets/level1/CCTV.png")
	widget_root.add_child(widget_sprite)
	widget_sprite.owner = widget_root
	var packed := PackedScene.new()
	packed.pack(widget_root)
	ResourceSaver.save(packed, TSCN_PATH)
	widget_root.queue_free()

	# Clean slate for the scratch save.
	DirAccess.remove_absolute(SCRATCH_PATH)

	# Phase A: spawn into a fresh level, save.
	var level_packed: PackedScene = load("res://scenes/level_1/level_1.tscn")
	var level: Node = level_packed.instantiate()
	level.set("current_edits_path", SCRATCH_PATH)  # before _init_editor_state's deferred call fires
	root.add_child(level)
	await process_frame
	await process_frame

	var em = level.get_node("EditMode")
	if em == null or not em.has_method("_spawn_palette_asset"):
		printerr("FAIL: EditMode missing _spawn_palette_asset")
		quit(1)
		return

	em.set("_drag_payload", {
		"type": "scene",
		"path": TSCN_PATH,
		"name": "test_widget",
	})
	em.call("_spawn_palette_asset", Vector2(123.0, 456.0))

	var objects: Node = level.get_node("Objects")
	var spawned: Node = objects.get_node_or_null("test_widget_1")
	if spawned != null:
		pass_ += 1
		print("PASS  spawn created Objects/test_widget_1")
	else:
		fail += 1
		printerr("FAIL  spawn did not create Objects/test_widget_1")

	if spawned and (spawned as Node2D).position.is_equal_approx(Vector2(123.0, 456.0)):
		pass_ += 1
		print("PASS  spawn position = (123, 456)")
	else:
		fail += 1
		printerr("FAIL  spawn position = %s" % ((spawned as Node2D).position if spawned else "<n/a>"))

	if spawned and spawned.has_meta("palette_source") and spawned.get_meta("palette_source") == TSCN_PATH:
		pass_ += 1
		print("PASS  palette_source metadata set")
	else:
		fail += 1
		printerr("FAIL  palette_source metadata wrong")

	if spawned and spawned.is_in_group("editable"):
		pass_ += 1
		print("PASS  spawned added to editable group")
	else:
		fail += 1
		printerr("FAIL  spawned not in editable group")

	# Regression: spawned scene root must produce non-null _world_bounds so that
	# selection / drag / scale handles work via the existing F4 paths.
	if spawned != null:
		var bounds = em.call("_world_bounds", spawned)
		if bounds != null:
			pass_ += 1
			print("PASS  _world_bounds(spawned) returned %s" % bounds)
		else:
			fail += 1
			printerr("FAIL  _world_bounds(spawned) was null — spawned scene roots can't be selected/dragged/scaled")
		# Hit-test at the sprite center should succeed.
		var sprite_center: Vector2 = (spawned as Node2D).global_position
		if em.call("_hit_test", spawned, sprite_center):
			pass_ += 1
			print("PASS  _hit_test(spawned, center) = true")
		else:
			fail += 1
			printerr("FAIL  _hit_test(spawned, center) = false — selection broken")

	# Clipboard test: Ctrl+C / Ctrl+V semantics + smart naming + stair offset.
	# Populate multi_selected by mutating the existing typed Array (set() with
	# an untyped literal would silently fail to assign).
	var sel_array: Array = em.get("multi_selected")
	sel_array.clear()
	sel_array.append(spawned)
	em.set("selected", spawned)
	em.call("_copy_to_clipboard")
	em.call("_paste_clipboard")
	var paste1: Node = objects.get_node_or_null("test_widget_2")
	if paste1 != null:
		pass_ += 1
		print("PASS  first paste named test_widget_2 (basename + next index)")
	else:
		fail += 1
		printerr("FAIL  first paste did not produce test_widget_2")
	if paste1 and (paste1 as Node2D).position.is_equal_approx(Vector2(123.0, 456.0) + Vector2(32.0, 32.0)):
		pass_ += 1
		print("PASS  first paste at source + copy_offset (155, 488)")
	else:
		fail += 1
		printerr("FAIL  first paste position = %s" % ((paste1 as Node2D).position if paste1 else "<n/a>"))

	em.call("_paste_clipboard")
	var paste2: Node = objects.get_node_or_null("test_widget_3")
	if paste2 != null:
		pass_ += 1
		print("PASS  second paste named test_widget_3")
	else:
		fail += 1
		printerr("FAIL  second paste did not produce test_widget_3")
	if paste2 and (paste2 as Node2D).position.is_equal_approx(Vector2(123.0, 456.0) + Vector2(64.0, 64.0)):
		pass_ += 1
		print("PASS  second paste stair-stepped to (187, 520)")
	else:
		fail += 1
		printerr("FAIL  second paste position = %s" % ((paste2 as Node2D).position if paste2 else "<n/a>"))

	# Smart-name helper: name without _<digits> suffix should append _1.
	var no_suffix_name: String = em.call("_smart_copy_name", objects, "Floor")
	if no_suffix_name == "Floor_1":
		pass_ += 1
		print("PASS  _smart_copy_name('Floor') = 'Floor_1'")
	else:
		fail += 1
		printerr("FAIL  _smart_copy_name('Floor') = '%s', expected 'Floor_1'" % no_suffix_name)

	# Re-Copy resets the offset so the next paste lands at copy_offset again.
	# (multi_selected may have been overwritten by _paste_clipboard pointing at
	# the new dups — re-pin to the original spawned widget.)
	sel_array = em.get("multi_selected")
	sel_array.clear()
	sel_array.append(spawned)
	em.call("_copy_to_clipboard")
	em.call("_paste_clipboard")
	# After re-Copy, source is still test_widget_1 (basename test_widget, start=2)
	# but test_widget_2 and test_widget_3 already exist, so next is test_widget_4.
	var paste3: Node = objects.get_node_or_null("test_widget_4")
	if paste3 != null:
		pass_ += 1
		print("PASS  re-Copy paste skipped existing names → test_widget_4")
	else:
		fail += 1
		printerr("FAIL  re-Copy paste did not produce test_widget_4")
	if paste3 and (paste3 as Node2D).position.is_equal_approx(Vector2(123.0, 456.0) + Vector2(32.0, 32.0)):
		pass_ += 1
		print("PASS  re-Copy reset paste offset (back to one copy_offset)")
	else:
		fail += 1
		printerr("FAIL  re-Copy paste position = %s, expected (155, 488)" % ((paste3 as Node2D).position if paste3 else "<n/a>"))

	# Clean up the extra paste nodes so the rest of the test sees a clean state.
	for n in [paste1, paste2, paste3]:
		if n != null and n.is_inside_tree():
			n.get_parent().remove_child(n)
			n.queue_free()
	sel_array = em.get("multi_selected")
	sel_array.clear()
	sel_array.append(spawned)
	em.set("selected", spawned)

	# Save and inspect the scratch JSON.
	var save_err: String = level.call("save_edits_to", SCRATCH_PATH)
	if save_err == "":
		pass_ += 1
		print("PASS  save_edits_to returned no error")
	else:
		fail += 1
		printerr("FAIL  save_edits_to: %s" % save_err)

	var f := FileAccess.open(SCRATCH_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		var spawned_arr: Variant = parsed.get("spawned_scenes", [])
		if typeof(spawned_arr) == TYPE_ARRAY and (spawned_arr as Array).size() == 1:
			pass_ += 1
			print("PASS  scratch JSON has 1 spawned_scenes entry")
		else:
			fail += 1
			printerr("FAIL  spawned_scenes count = %s" % (spawned_arr as Array).size())
		# Make sure the spawned widget is NOT in transforms (it has metadata).
		var transforms_arr: Array = parsed.get("transforms", [])
		var leaked := false
		for t in transforms_arr:
			if t.get("name", "") == "test_widget_1":
				leaked = true
				break
		if not leaked:
			pass_ += 1
			print("PASS  spawned widget not duplicated in transforms")
		else:
			fail += 1
			printerr("FAIL  spawned widget leaked into transforms")

	# Phase B: tear down, re-instantiate fresh level with same scratch save.
	level.queue_free()
	await process_frame

	var level2: Node = level_packed.instantiate()
	level2.set("current_edits_path", SCRATCH_PATH)
	root.add_child(level2)
	await process_frame
	await process_frame

	var spawned2: Node = level2.get_node_or_null("Objects/test_widget_1")
	if spawned2 != null:
		pass_ += 1
		print("PASS  reload re-instantiated Objects/test_widget_1")
	else:
		fail += 1
		printerr("FAIL  reload did not re-instantiate test_widget_1")

	if spawned2 and (spawned2 as Node2D).position.is_equal_approx(Vector2(123.0, 456.0)):
		pass_ += 1
		print("PASS  reload preserved position (123, 456)")
	else:
		fail += 1
		printerr("FAIL  reload position = %s" % ((spawned2 as Node2D).position if spawned2 else "<n/a>"))

	if spawned2 and spawned2.has_meta("palette_source"):
		pass_ += 1
		print("PASS  reload restored palette_source metadata")
	else:
		fail += 1
		printerr("FAIL  reload missing palette_source metadata")

	# Phase C: backward-compat — save without spawned_scenes key still loads.
	var legacy := {
		"version": 2,
		"transforms": [],
		"deleted": [],
		# no spawned_scenes
	}
	var lf := FileAccess.open(SCRATCH_PATH, FileAccess.WRITE)
	lf.store_string(JSON.stringify(legacy, "\t"))
	lf.close()
	level2.queue_free()
	await process_frame

	var level3: Node = level_packed.instantiate()
	level3.set("current_edits_path", SCRATCH_PATH)
	root.add_child(level3)
	await process_frame
	await process_frame

	# Should boot cleanly with no spawned_scenes; baseline objects still present.
	if level3.get_node_or_null("Objects") != null:
		pass_ += 1
		print("PASS  legacy save (no spawned_scenes key) loads cleanly")
	else:
		fail += 1
		printerr("FAIL  legacy save broke level load")

	level3.queue_free()

	# Cleanup
	DirAccess.remove_absolute(TSCN_PATH)
	DirAccess.remove_absolute(PALETTE_DIR)
	DirAccess.remove_absolute("res://assets/palette/Test")
	# Don't remove res://assets/palette in case other tests left things; safe to leave.
	DirAccess.remove_absolute(SCRATCH_PATH)

	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
