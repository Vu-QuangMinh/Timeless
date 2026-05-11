extends SceneTree

# Builds a synthetic res://assets/palette/ tree, asks EditMode's scanner to
# enumerate it, and verifies categorization + .tscn-shadows-.tres dedup.
# Run: godot --headless -s tests/test_palette_scan.gd


func _initialize() -> void:
	var fail := 0
	var pass_ := 0

	# Build fake palette: one Camera asset (just .tscn), one Wall asset
	# (both .tscn and .tres — .tres should be deduped out), one Artifact
	# .tres standalone.
	var paths := {
		"camera_a/camera_a.tscn": "[gd_scene format=3]\n[node name=\"Root\" type=\"Area2D\"]\n",
		"wall_b/wall_b.tscn": "[gd_scene format=3]\n[node name=\"Root\" type=\"StaticBody2D\"]\n",
		"wall_b/wall_b.tres": "[gd_resource type=\"CanvasTexture\" format=3]\n",
		"artifact_c/artifact_c.tres": "[gd_resource type=\"CanvasTexture\" format=3]\n",
	}
	# Categories live under PALETTE_ROOT/<category>/<asset>/<file>.
	var category_for := {
		"camera_a/camera_a.tscn": "Camera",
		"wall_b/wall_b.tscn": "Wall",
		"wall_b/wall_b.tres": "Wall",
		"artifact_c/artifact_c.tres": "Artifact",
	}

	DirAccess.make_dir_recursive_absolute("res://assets/palette/Camera/camera_a")
	DirAccess.make_dir_recursive_absolute("res://assets/palette/Wall/wall_b")
	DirAccess.make_dir_recursive_absolute("res://assets/palette/Artifact/artifact_c")

	for rel in paths:
		var full := "res://assets/palette/%s/%s" % [category_for[rel], rel]
		var f := FileAccess.open(full, FileAccess.WRITE)
		if f == null:
			printerr("FAIL: could not write %s" % full)
			quit(1)
			return
		f.store_string(paths[rel])
		f.close()

	var script := load("res://scripts/EditMode.gd")
	var em: Node = script.new()
	root.add_child(em)
	await process_frame

	var entries: Array = em.call("_scan_palette")

	# Expect 3 entries: camera_a.tscn (scene), wall_b.tscn (scene),
	# artifact_c.tres (sprite). wall_b.tres is deduped because wall_b.tscn exists
	# alongside.
	if entries.size() == 3:
		pass_ += 1
		print("PASS  scan returned 3 entries (%s)" % entries.size())
	else:
		fail += 1
		printerr("FAIL  scan returned %d entries, expected 3" % entries.size())
		for e in entries:
			printerr("       %s" % e)

	# Build (category, name, type) tuples for assertions.
	var actual := {}
	for e in entries:
		actual["%s|%s|%s" % [e["category"], e["name"], e["type"]]] = e["path"]

	var expected_keys := [
		"Camera|camera_a|scene",
		"Wall|wall_b|scene",
		"Artifact|artifact_c|sprite",
	]
	for k in expected_keys:
		if actual.has(k):
			pass_ += 1
			print("PASS  entry exists: %s" % k)
		else:
			fail += 1
			printerr("FAIL  missing entry: %s" % k)

	# Negative: wall_b.tres should NOT appear as its own entry (deduped).
	if not actual.has("Wall|wall_b|sprite"):
		pass_ += 1
		print("PASS  wall_b.tres deduped (no Wall|wall_b|sprite entry)")
	else:
		fail += 1
		printerr("FAIL  wall_b.tres leaked into scan as sprite")

	em.queue_free()

	# Clean up.
	for rel in paths:
		var full := "res://assets/palette/%s/%s" % [category_for[rel], rel]
		DirAccess.remove_absolute(full)
	for cat in ["Camera/camera_a", "Wall/wall_b", "Artifact/artifact_c"]:
		DirAccess.remove_absolute("res://assets/palette/%s" % cat)
	for cat in ["Camera", "Wall", "Artifact"]:
		DirAccess.remove_absolute("res://assets/palette/%s" % cat)
	DirAccess.remove_absolute("res://assets/palette")

	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
