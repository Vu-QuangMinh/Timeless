extends SceneTree

# Smoke test for Phase 3 save flow. Loads CCTV.png, creates an AssetEditor
# in-tree (so its _build_ui() runs), shoves test data into it, calls
# _save_asset(), then verifies the four expected files exist and look sane.
# Run: godot --headless -s tests/test_asset_save.gd

const TEST_NAME := "smoke_cctv"
const TEST_CATEGORY := "Camera"


func _initialize() -> void:
	var fail_count := 0
	var pass_count := 0

	var src_png := "res://assets/level1/CCTV.png"
	if not FileAccess.file_exists(src_png):
		printerr("FAIL: missing source %s" % src_png)
		quit(1)
		return

	var img := Image.new()
	if img.load(src_png) != OK:
		printerr("FAIL: could not load %s" % src_png)
		quit(1)
		return

	var script := load("res://scripts/asset_editor.gd")
	var editor: Node = script.new()
	root.add_child(editor)
	# _ready() ran inside add_child, so _build_ui has executed.

	editor.set("_image", img)
	editor.set("_texture", ImageTexture.create_from_image(img))
	editor.set("_texture_filename", "CCTV.png")

	# Two polygons: one collision (red), one recognition (yellow).
	var poly_collision := PackedVector2Array([Vector2(10, 10), Vector2(50, 10), Vector2(30, 50)])
	var poly_recognition := PackedVector2Array([Vector2(60, 60), Vector2(100, 60), Vector2(100, 100), Vector2(60, 100)])
	editor.set("_polygons", [
		{"type": "collision", "vertices": poly_collision},
		{"type": "recognition", "vertices": poly_recognition},
	])

	var err: String = editor.call("_save_asset", TEST_NAME, TEST_CATEGORY, true)
	if err != "":
		printerr("FAIL: _save_asset returned error: %s" % err)
		quit(1)
		return
	pass_count += 1
	print("PASS  _save_asset returned no error")

	var dir := "res://assets/palette/%s/%s" % [TEST_CATEGORY, TEST_NAME]
	var expected := [
		"%s/%s.png" % [dir, TEST_NAME],
		"%s/%s_normal.png" % [dir, TEST_NAME],
		"%s/%s.tres" % [dir, TEST_NAME],
		"%s/%s.borders.json" % [dir, TEST_NAME],
		"%s/%s.tscn" % [dir, TEST_NAME],
	]
	for path in expected:
		if FileAccess.file_exists(path):
			pass_count += 1
			print("PASS  %s exists" % path)
		else:
			fail_count += 1
			printerr("FAIL  %s missing" % path)

	# Verify borders.json round-trips.
	var json_path := "%s/%s.borders.json" % [dir, TEST_NAME]
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			var polys: Array = parsed.get("polygons", [])
			if polys.size() == 2:
				pass_count += 1
				print("PASS  borders.json has 2 polygons")
			else:
				fail_count += 1
				printerr("FAIL  borders.json polygon count = %d, expected 2" % polys.size())
			var img_size: Array = parsed.get("image_size", [])
			if img_size.size() == 2 and int(img_size[0]) == img.get_width() and int(img_size[1]) == img.get_height():
				pass_count += 1
				print("PASS  borders.json image_size matches source")
			else:
				fail_count += 1
				printerr("FAIL  borders.json image_size = %s, expected [%d, %d]" % [img_size, img.get_width(), img.get_height()])

	# Verify the .tscn loads back as a PackedScene and instances cleanly.
	var tscn_path := "%s/%s.tscn" % [dir, TEST_NAME]
	var packed: PackedScene = load(tscn_path)
	if packed != null:
		var inst := packed.instantiate()
		if inst != null:
			pass_count += 1
			print("PASS  .tscn instantiates: root=%s" % inst.get_class())
			# Camera category: root Area2D with collision_layer=2, child Sprite, child Body, recognition polys on root.
			if inst is Area2D:
				pass_count += 1
				print("PASS  Camera root is Area2D")
				if (inst as Area2D).collision_layer == 2:
					pass_count += 1
					print("PASS  Camera root collision_layer = 2")
				else:
					fail_count += 1
					printerr("FAIL  Camera root collision_layer = %d, expected 2" % (inst as Area2D).collision_layer)
				if inst.get_meta("recognition_priority", -999) == 40:
					pass_count += 1
					print("PASS  recognition_priority metadata = 40")
				else:
					fail_count += 1
					printerr("FAIL  recognition_priority = %s, expected 40" % inst.get_meta("recognition_priority", "MISSING"))
			else:
				fail_count += 1
				printerr("FAIL  Camera root is %s, expected Area2D" % inst.get_class())
			inst.queue_free()
		else:
			fail_count += 1
			printerr("FAIL  .tscn could not instantiate")
	else:
		fail_count += 1
		printerr("FAIL  could not load .tscn")

	editor.queue_free()

	# Clean up generated artifacts so the test doesn't litter the repo.
	var dir_to_remove := "res://assets/palette/%s/%s" % [TEST_CATEGORY, TEST_NAME]
	var d := DirAccess.open(dir_to_remove)
	if d != null:
		for f_name in d.get_files():
			d.remove(f_name)
		DirAccess.remove_absolute(dir_to_remove)

	print("---")
	print("Total: %d passed, %d failed" % [pass_count, fail_count])
	quit(0 if fail_count == 0 else 1)
