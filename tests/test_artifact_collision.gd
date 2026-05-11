extends SceneTree

# Verifies the F6 Artifact category now compiles drawn red polys into a
# `Body` StaticBody2D, so spawned artifacts can block movement.
# Run: godot --headless -s tests/test_artifact_collision.gd

const TEST_NAME := "smoke_artifact_collision"
const TEST_CATEGORY := "Artifact"


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
	await process_frame

	editor.set("_image", img)
	editor.set("_texture", ImageTexture.create_from_image(img))
	editor.set("_texture_filename", "CCTV.png")

	# One red (collision) + one yellow (recognition).
	editor.set("_polygons", [
		{"type": "collision", "vertices": PackedVector2Array([
			Vector2(10, 10), Vector2(50, 10), Vector2(50, 50), Vector2(10, 50)
		])},
		{"type": "recognition", "vertices": PackedVector2Array([
			Vector2(60, 60), Vector2(100, 60), Vector2(100, 100), Vector2(60, 100)
		])},
	])

	var err: String = editor.call("_save_asset", TEST_NAME, TEST_CATEGORY, false)
	if err == "":
		pass_ += 1
		print("PASS  _save_asset(Artifact) returned no error")
	else:
		fail += 1
		printerr("FAIL  _save_asset returned: %s" % err)

	# Load the saved .tscn and inspect its structure.
	var tscn_path := "res://assets/palette/%s/%s/%s.tscn" % [TEST_CATEGORY, TEST_NAME, TEST_NAME]
	var packed: PackedScene = load(tscn_path)
	if packed == null:
		printerr("FAIL: could not load %s" % tscn_path)
		quit(1)
		return
	var inst: Node = packed.instantiate()

	# Root: Node2D
	if inst is Node2D and not (inst is Area2D) and not (inst is CollisionObject2D):
		pass_ += 1
		print("PASS  root is plain Node2D (Artifact)")
	else:
		fail += 1
		printerr("FAIL  root type = %s, expected Node2D" % inst.get_class())

	# Sprite present
	var sprite: Node = inst.get_node_or_null("Sprite")
	if sprite != null:
		pass_ += 1
		print("PASS  Sprite child present")
	else:
		fail += 1
		printerr("FAIL  Sprite child missing")

	# NEW: Body StaticBody2D with the red collision poly
	var body: Node = inst.get_node_or_null("Body")
	if body != null and body is StaticBody2D:
		pass_ += 1
		print("PASS  Body StaticBody2D present (Artifact now respects red polys)")
	else:
		fail += 1
		printerr("FAIL  Body StaticBody2D missing (Artifact still drops red polys)")
	if body:
		var collision_count := 0
		for c in body.get_children():
			if c is CollisionPolygon2D:
				collision_count += 1
		if collision_count == 1:
			pass_ += 1
			print("PASS  Body has 1 CollisionPolygon2D (matching the 1 red poly drawn)")
		else:
			fail += 1
			printerr("FAIL  Body has %d collision polys (expected 1)" % collision_count)

	# Recognition Area2D (yellow polys)
	var rec: Node = inst.get_node_or_null("Recognition")
	if rec != null and rec is Area2D:
		var area := rec as Area2D
		if area.collision_layer == 2:
			pass_ += 1
			print("PASS  Recognition Area2D on collision_layer = 2")
		else:
			fail += 1
			printerr("FAIL  Recognition Area2D layer = %d" % area.collision_layer)

	# Sanity: WorldObstacles can now extract from this artifact's Body
	var WorldObstaclesScript = load("res://scripts/pathing/world_obstacles.gd")
	var segs: Array = WorldObstaclesScript.collect_wall_segments(inst)
	if segs.size() == 4:  # 4-vert square → 4 edges
		pass_ += 1
		print("PASS  WorldObstacles extracted 4 edges from Artifact's Body")
	else:
		fail += 1
		printerr("FAIL  WorldObstacles extracted %d edges (expected 4)" % segs.size())

	inst.queue_free()
	editor.queue_free()

	# Clean up
	var dir := "res://assets/palette/%s/%s" % [TEST_CATEGORY, TEST_NAME]
	var d := DirAccess.open(dir)
	if d != null:
		for f_name in d.get_files():
			d.remove(f_name)
		DirAccess.remove_absolute(dir)

	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)
