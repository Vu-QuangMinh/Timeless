extends SceneTree

# Verifies that the restored level_1.tscn nodes (Door/CCTV/Painting_3/Laser_sensor
# under Objects, plus Lighting subtree) load cleanly AND that the user's
# user://level_1_edits.json transforms apply over the .tscn baseline.
# Run: godot --headless -s tests/test_level_1_restore.gd


func _initialize() -> void:
	var fail := 0
	var pass_ := 0

	var packed: PackedScene = load("res://scenes/level_1/level_1.tscn")
	if packed == null:
		printerr("FAIL: could not load level_1.tscn")
		quit(1)
		return
	var level: Node = packed.instantiate()
	root.add_child(level)
	# _init_editor_state is call_deferred, then awaits process_frame.
	await process_frame
	await process_frame

	# Required structural nodes.
	var expected_paths := [
		"Background/Floor",
		"Background/Wall_X",
		"Background/Wall_Y",
		"Objects/Door",
		"Objects/CCTV",
		"Objects/Painting_3",
		"Objects/Laser_sensor",
		"Lighting/SunY",
		"Lighting/CCTV_Light",
		"Lighting/CCTV_Light/ConeBeam",
		"Lighting/Laser",
		"Lighting/Laser/LaserBeam",
		"EditMode",
		"LightMode",
		"AssetEditor",
	]
	for p in expected_paths:
		if level.has_node(p):
			pass_ += 1
			print("PASS  node exists: %s" % p)
		else:
			fail += 1
			printerr("FAIL  node missing: %s" % p)

	# Verify saved transforms applied. CCTV save says (196.67, -191.11);
	# baseline .tscn says (200, -200). After loader runs, position should
	# match the save (within float tolerance).
	var cctv := level.get_node_or_null("Objects/CCTV") as Sprite2D
	if cctv != null:
		var dx := absf(cctv.position.x - 196.666687011719)
		var dy := absf(cctv.position.y - (-191.111083984375))
		if dx < 0.5 and dy < 0.5:
			pass_ += 1
			print("PASS  CCTV position from save: (%.2f, %.2f)" % [cctv.position.x, cctv.position.y])
		else:
			fail += 1
			printerr("FAIL  CCTV position = (%.2f, %.2f), expected ~(196.67, -191.11)" % [cctv.position.x, cctv.position.y])

	var laser_sensor := level.get_node_or_null("Objects/Laser_sensor") as Sprite2D
	if laser_sensor != null:
		var dx := absf(laser_sensor.position.x - (-356.438323974609))
		var dy := absf(laser_sensor.position.y - (-10.2282867431641))
		if dx < 0.5 and dy < 0.5:
			pass_ += 1
			print("PASS  Laser_sensor position from save: (%.2f, %.2f)" % [laser_sensor.position.x, laser_sensor.position.y])
		else:
			fail += 1
			printerr("FAIL  Laser_sensor position = (%.2f, %.2f), expected ~(-356.44, -10.23)" % [laser_sensor.position.x, laser_sensor.position.y])

	# Verify Lighting nodes have the correct authored values from baseline.
	var sun := level.get_node_or_null("Lighting/SunY") as DirectionalLight2D
	if sun != null:
		if absf(sun.energy - 1.2) < 0.01:
			pass_ += 1
			print("PASS  SunY energy = %.2f" % sun.energy)
		else:
			fail += 1
			printerr("FAIL  SunY energy = %.2f, expected 1.2" % sun.energy)

	var cctv_light := level.get_node_or_null("Lighting/CCTV_Light") as PointLight2D
	if cctv_light != null:
		if cctv_light.color.is_equal_approx(Color(1, 0.18, 0.18, 1)):
			pass_ += 1
			print("PASS  CCTV_Light color matches baseline")
		else:
			fail += 1
			printerr("FAIL  CCTV_Light color = %s" % cctv_light.color)
		if cctv_light.get_script() != null:
			pass_ += 1
			print("PASS  CCTV_Light has cctv_pan.gd script attached")
		else:
			fail += 1
			printerr("FAIL  CCTV_Light has no script")
		# Save records position (221.11, -185.56); .tscn baseline says (200, -180).
		# Loader should have applied the save.
		var dx := absf(cctv_light.position.x - 221.111145019531)
		var dy := absf(cctv_light.position.y - (-185.555557250977))
		if dx < 0.5 and dy < 0.5:
			pass_ += 1
			print("PASS  CCTV_Light position from save: (%.2f, %.2f)" % [cctv_light.position.x, cctv_light.position.y])
		else:
			fail += 1
			printerr("FAIL  CCTV_Light position = (%.2f, %.2f), expected ~(221.11, -185.56) from save" % [cctv_light.position.x, cctv_light.position.y])

	# Phase 2: lights save layer round-trip. Mutate a light, call save_light_edits,
	# write to a scratch path, read it back, confirm the mutation persisted.
	var scratch_path := "user://__test_lights_roundtrip.json"
	if cctv_light != null:
		var original_energy: float = cctv_light.energy
		cctv_light.energy = 7.5
		var err: String = level.call("save_light_edits_to", scratch_path)
		if err == "":
			pass_ += 1
			print("PASS  save_light_edits_to returned no error")
		else:
			fail += 1
			printerr("FAIL  save_light_edits_to: %s" % err)
		var f := FileAccess.open(scratch_path, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY and (parsed.get("lights", []) as Array).size() == 3:
				pass_ += 1
				print("PASS  scratch file has 3 lights")
			else:
				fail += 1
				printerr("FAIL  scratch file lights count = %s" % (parsed.get("lights", []) as Array).size())
			# Find CCTV_Light entry and check the mutated energy persisted.
			for entry in (parsed.get("lights", []) as Array):
				if entry.get("name", "") == "CCTV_Light":
					if absf(float(entry.get("energy", 0.0)) - 7.5) < 0.01:
						pass_ += 1
						print("PASS  CCTV_Light energy persisted: %.2f" % float(entry["energy"]))
					else:
						fail += 1
						printerr("FAIL  CCTV_Light energy in save = %.2f, expected 7.5" % float(entry["energy"]))
		# Restore + clean up scratch file.
		cctv_light.energy = original_energy
		DirAccess.remove_absolute(scratch_path)

	level.queue_free()
	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
