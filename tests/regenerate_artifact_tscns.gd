extends SceneTree

# One-shot migration: walks res://assets/palette/Artifact/ and re-saves every
# asset that has red collision polygons in its borders.json but no `Body`
# StaticBody2D in its .tscn. After the Artifact-collision fix, this brings
# previously-saved Artifact assets up to the new structure so spawned instances
# block movement via the pathfinder.
# Run: godot --headless -s tests/regenerate_artifact_tscns.gd

const ROOT := "res://assets/palette/Artifact"


func _initialize() -> void:
	var regenerated := 0
	var skipped := 0
	var failed := 0

	if not DirAccess.dir_exists_absolute(ROOT):
		print("No Artifact assets — nothing to regenerate")
		quit(0)
		return

	var script := load("res://scripts/asset_editor.gd")
	var editor: Node = script.new()
	root.add_child(editor)
	await process_frame

	var d := DirAccess.open(ROOT)
	for asset_name in d.get_directories():
		var dir := "%s/%s" % [ROOT, asset_name]
		var json_path := "%s/%s.borders.json" % [dir, asset_name]
		var png_path := "%s/%s.png" % [dir, asset_name]
		var normal_path := "%s/%s_normal.png" % [dir, asset_name]
		if not FileAccess.file_exists(json_path) or not FileAccess.file_exists(png_path):
			print("SKIP  %s — missing borders.json or png" % asset_name)
			skipped += 1
			continue

		# Parse borders.json
		var f := FileAccess.open(json_path, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			print("SKIP  %s — borders.json malformed" % asset_name)
			skipped += 1
			continue

		# Count red polys (only worth regenerating if there are any)
		var raw_polys: Array = parsed.get("polygons", [])
		var red_count := 0
		for p in raw_polys:
			if p.get("type", "") == "collision":
				red_count += 1
		if red_count == 0:
			print("SKIP  %s — no red collision polys to compile" % asset_name)
			skipped += 1
			continue

		# Load image
		var img := Image.new()
		if img.load(png_path) != OK:
			printerr("FAIL  %s — could not load PNG" % asset_name)
			failed += 1
			continue

		# Rebuild _polygons from borders.json
		var loaded: Array = []
		for p in raw_polys:
			if typeof(p) != TYPE_DICTIONARY:
				continue
			var verts := PackedVector2Array()
			var rv: Array = p.get("vertices", [])
			for pair in rv:
				if typeof(pair) == TYPE_ARRAY and pair.size() >= 2:
					verts.append(Vector2(float(pair[0]), float(pair[1])))
			loaded.append({"type": p.get("type", "collision"), "vertices": verts})

		# Set editor state and re-run _save_asset (preserves normal map if it
		# already exists on disk — we pass with_normal = FileAccess.file_exists(...))
		editor.set("_image", img)
		editor.set("_texture", ImageTexture.create_from_image(img))
		editor.set("_texture_filename", "%s.png" % asset_name)
		editor.set("_polygons", loaded)

		var with_normal: bool = FileAccess.file_exists(normal_path)
		var err: String = editor.call("_save_asset", asset_name, "Artifact", with_normal)
		if err != "":
			printerr("FAIL  %s — %s" % [asset_name, err])
			failed += 1
			continue

		# Verify the regenerated .tscn has a Body
		var tscn_path := "%s/%s.tscn" % [dir, asset_name]
		var packed: PackedScene = load(tscn_path)
		var inst: Node = packed.instantiate()
		var has_body: bool = inst.get_node_or_null("Body") is StaticBody2D
		inst.queue_free()
		if has_body:
			print("OK    %s — regenerated with Body StaticBody2D (%d red polys)" % [asset_name, red_count])
			regenerated += 1
		else:
			printerr("FAIL  %s — regenerated .tscn still has no Body" % asset_name)
			failed += 1

	editor.queue_free()
	print("---")
	print("Regenerated: %d  Skipped: %d  Failed: %d" % [regenerated, skipped, failed])
	quit(0 if failed == 0 else 1)
