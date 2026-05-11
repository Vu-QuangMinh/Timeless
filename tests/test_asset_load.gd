extends SceneTree

# Verifies the F6 Ctrl+O load path: save an asset with two polygons, wipe
# editor state, call _load_asset on the saved borders.json, and check that
# _polygons is repopulated end-to-end (count, types, vertices).
# Run: godot --headless -s tests/test_asset_load.gd

const TEST_NAME := "smoke_load_roundtrip"
const TEST_CATEGORY := "Wall"


func _initialize() -> void:
	var fail := 0
	var pass_ := 0

	var src_png := "res://assets/level1/CCTV.png"
	var img := Image.new()
	if img.load(src_png) != OK:
		printerr("FAIL: missing %s" % src_png)
		quit(1)
		return

	var script := load("res://scripts/asset_editor.gd")
	var editor: Node = script.new()
	root.add_child(editor)
	# Wait for _ready / _build_ui to finish so _preview, _filename_label etc.
	# are non-null. Without this the in-process UI calls in _load_png error.
	await process_frame
	await process_frame

	editor.set("_image", img)
	editor.set("_texture", ImageTexture.create_from_image(img))
	editor.set("_texture_filename", "CCTV.png")

	var poly_collision := PackedVector2Array([
		Vector2(10, 10), Vector2(50, 10), Vector2(30, 50)
	])
	var poly_recognition := PackedVector2Array([
		Vector2(60, 60), Vector2(100, 60), Vector2(100, 100), Vector2(60, 100)
	])
	editor.set("_polygons", [
		{"type": "collision", "vertices": poly_collision},
		{"type": "recognition", "vertices": poly_recognition},
	])

	var err: String = editor.call("_save_asset", TEST_NAME, TEST_CATEGORY, false)
	if err != "":
		printerr("FAIL: _save_asset returned %s" % err)
		quit(1)
		return
	pass_ += 1
	print("PASS  _save_asset wrote files")

	var json_path := "res://assets/palette/%s/%s/%s.borders.json" % [TEST_CATEGORY, TEST_NAME, TEST_NAME]

	# Wipe editor state to simulate a fresh session.
	editor.set("_image", null)
	editor.set("_texture", null)
	editor.set("_texture_filename", "")
	editor.set("_polygons", [])

	# Load the saved asset.
	editor.call("_load_asset", json_path)

	var loaded_polys: Array = editor.get("_polygons")
	if loaded_polys.size() == 2:
		pass_ += 1
		print("PASS  _polygons repopulated with 2 entries")
	else:
		fail += 1
		printerr("FAIL  _polygons.size() = %d, expected 2" % loaded_polys.size())
		for p in loaded_polys:
			printerr("       %s" % p)

	if loaded_polys.size() >= 1:
		var p0: Dictionary = loaded_polys[0]
		if p0.get("type", "") == "collision":
			pass_ += 1
			print("PASS  polygon[0].type = collision")
		else:
			fail += 1
			printerr("FAIL  polygon[0].type = %s, expected collision" % p0.get("type", ""))
		var v0: PackedVector2Array = p0.get("vertices", PackedVector2Array())
		if v0.size() == 3 and v0[0] == Vector2(10, 10):
			pass_ += 1
			print("PASS  polygon[0].vertices restored (3 verts, [0]=(10,10))")
		else:
			fail += 1
			printerr("FAIL  polygon[0].vertices wrong: size=%d first=%s" % [v0.size(), v0[0] if v0.size() > 0 else "<empty>"])

	if loaded_polys.size() >= 2:
		var p1: Dictionary = loaded_polys[1]
		if p1.get("type", "") == "recognition":
			pass_ += 1
			print("PASS  polygon[1].type = recognition")
		else:
			fail += 1
			printerr("FAIL  polygon[1].type = %s, expected recognition" % p1.get("type", ""))
		var v1: PackedVector2Array = p1.get("vertices", PackedVector2Array())
		if v1.size() == 4:
			pass_ += 1
			print("PASS  polygon[1].vertices restored (4 verts)")
		else:
			fail += 1
			printerr("FAIL  polygon[1].vertices.size() = %d, expected 4" % v1.size())

	# Verify the texture got loaded too.
	var loaded_image: Image = editor.get("_image")
	if loaded_image != null and loaded_image.get_width() > 0:
		pass_ += 1
		print("PASS  _image repopulated (%dx%d)" % [loaded_image.get_width(), loaded_image.get_height()])
	else:
		fail += 1
		printerr("FAIL  _image not repopulated")

	# CRITICAL: verify the preview Control received the polygons too. This is
	# what determines whether the user actually sees them rendered.
	var preview = editor.get("_preview")
	if preview == null:
		fail += 1
		printerr("FAIL  _preview is null (UI not built)")
	else:
		var preview_polys: Array = preview.get("polygons")
		if preview_polys.size() == 2:
			pass_ += 1
			print("PASS  _preview.polygons has 2 entries (will render)")
		else:
			fail += 1
			printerr("FAIL  _preview.polygons.size() = %d" % preview_polys.size())
		var preview_image_size: Vector2 = preview.get("image_size")
		if preview_image_size.x > 0 and preview_image_size.y > 0:
			pass_ += 1
			print("PASS  _preview.image_size = %s" % preview_image_size)
		else:
			fail += 1
			printerr("FAIL  _preview.image_size = %s (polygons would render at wrong coords)" % preview_image_size)

	editor.queue_free()

	# Cleanup.
	var dir_to_remove := "res://assets/palette/%s/%s" % [TEST_CATEGORY, TEST_NAME]
	var d := DirAccess.open(dir_to_remove)
	if d != null:
		for f_name in d.get_files():
			d.remove(f_name)
		DirAccess.remove_absolute(dir_to_remove)

	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
