extends SceneTree

# Loads the user's actual saved asset file (not a synthesized one) and asserts
# that _polygons + _preview.polygons + _preview.image_size are populated.
# Run: godot --headless -s tests/test_load_user_asset.gd

const ASSET_JSON := "res://assets/palette/Artifact/laser_sensor/laser_sensor.borders.json"


func _initialize() -> void:
	var fail := 0
	var pass_ := 0

	if not FileAccess.file_exists(ASSET_JSON):
		printerr("FAIL: %s missing on disk" % ASSET_JSON)
		quit(1)
		return
	pass_ += 1
	print("PASS  user asset on disk: %s" % ASSET_JSON)

	# Sanity: the JSON parses and has 2 polygons.
	var f := FileAccess.open(ASSET_JSON, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		var polys: Array = parsed.get("polygons", [])
		if polys.size() == 2:
			pass_ += 1
			print("PASS  JSON has 2 polygon entries")
		else:
			fail += 1
			printerr("FAIL  JSON has %d polygon entries" % polys.size())
		var collision_count := 0
		var recognition_count := 0
		for p in polys:
			match p.get("type", ""):
				"collision":
					collision_count += 1
				"recognition":
					recognition_count += 1
		if collision_count == 1 and recognition_count == 1:
			pass_ += 1
			print("PASS  JSON has 1 collision + 1 recognition")
		else:
			fail += 1
			printerr("FAIL  JSON: collision=%d recognition=%d" % [collision_count, recognition_count])

	# Now exercise the editor's _load_asset on the actual file.
	var script := load("res://scripts/asset_editor.gd")
	var editor: Node = script.new()
	root.add_child(editor)
	await process_frame
	await process_frame  # _build_ui ran inside _ready

	# Pre-load: empty state.
	var pre_polys: Array = editor.get("_polygons")
	if pre_polys.is_empty():
		pass_ += 1
		print("PASS  editor pre-load: _polygons is empty")
	else:
		fail += 1
		printerr("FAIL  editor pre-load: _polygons.size = %d" % pre_polys.size())

	editor.call("_load_asset", ASSET_JSON)
	await process_frame

	var post_polys: Array = editor.get("_polygons")
	if post_polys.size() == 2:
		pass_ += 1
		print("PASS  post-load _polygons.size = 2")
	else:
		fail += 1
		printerr("FAIL  post-load _polygons.size = %d (expected 2)" % post_polys.size())
		for p in post_polys:
			printerr("       %s" % p)

	# Critical: does _preview have the polygons too?
	var preview = editor.get("_preview")
	if preview == null:
		fail += 1
		printerr("FAIL  _preview is null")
	else:
		var preview_polys: Array = preview.get("polygons")
		if preview_polys.size() == 2:
			pass_ += 1
			print("PASS  _preview.polygons.size = 2")
		else:
			fail += 1
			printerr("FAIL  _preview.polygons.size = %d (expected 2)" % preview_polys.size())

		var preview_image_size: Vector2 = preview.get("image_size")
		if preview_image_size.x > 0 and preview_image_size.y > 0:
			pass_ += 1
			print("PASS  _preview.image_size = %s" % preview_image_size)
		else:
			fail += 1
			printerr("FAIL  _preview.image_size = %s (zero — _draw_polygons would render at wrong coords)" % preview_image_size)

		# The actual rendered output requires _draw to fire. We can verify
		# the underlying state and trust queue_redraw + _draw to work.
		# But let's also verify each polygon's vertex array is the right type.
		for i in range(preview_polys.size()):
			var p: Dictionary = preview_polys[i]
			var verts: PackedVector2Array = p.get("vertices", PackedVector2Array())
			if verts.size() >= 3:
				pass_ += 1
				print("PASS  polygon[%d].vertices = %d verts (renderable)" % [i, verts.size()])
			else:
				fail += 1
				printerr("FAIL  polygon[%d].vertices = %d verts (< 3 = skipped by _draw_polygons)" % [i, verts.size()])

		# Visibility check on the preview Control itself.
		if preview.visible:
			pass_ += 1
			print("PASS  _preview.visible = true")
		else:
			fail += 1
			printerr("FAIL  _preview.visible = false (would not render)")

		# Verify queue_redraw fires by triggering it manually and checking _draw runs.
		# (We can't intercept _draw directly, but we can check the preview is in a
		# valid drawing state.)
		if preview.size.x > 0 and preview.size.y > 0:
			pass_ += 1
			print("PASS  _preview.size = %s (has area to draw in)" % preview.size)
		else:
			# This often happens in headless when the Control has no parent layout.
			print("INFO  _preview.size = %s (headless test; in real F6 the panel sizes it)" % preview.size)

	# REGRESSION: also exercise the "Load PNG..." path. _on_png_chosen on a
	# saved-asset PNG should now auto-restore polygons via sibling borders.json.
	editor.set("_polygons", [])
	if editor.get("_preview") != null:
		editor.get("_preview").set_polygons([])
	var png_path := "res://assets/palette/Artifact/laser_sensor/laser_sensor.png"
	editor.call("_on_png_chosen", png_path)
	await process_frame
	var lp_polys: Array = editor.get("_polygons")
	if lp_polys.size() == 2:
		pass_ += 1
		print("PASS  Load PNG... auto-restored 2 polygons from sibling borders.json")
	else:
		fail += 1
		printerr("FAIL  Load PNG... left _polygons.size = %d (expected 2)" % lp_polys.size())

	# Negative: a PNG with NO sibling borders.json (e.g. a plain asset) should
	# NOT spuriously load polygons.
	editor.set("_polygons", [])
	editor.get("_preview").set_polygons([])
	var bare_png := "res://assets/level1/CCTV.png"  # no borders.json next to it
	editor.call("_on_png_chosen", bare_png)
	await process_frame
	var bare_polys: Array = editor.get("_polygons")
	if bare_polys.is_empty():
		pass_ += 1
		print("PASS  bare PNG (no sibling borders.json) leaves _polygons empty")
	else:
		fail += 1
		printerr("FAIL  bare PNG load polluted _polygons with %d entries" % bare_polys.size())

	editor.queue_free()
	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
