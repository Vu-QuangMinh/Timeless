extends SceneTree

# Loads the live Level1.tscn AND the user's actual save, then queries
# WorldObstacles to see how many wall segments are extracted from spawned items.
# Expected from current save: 2 Camera spawns (have collision) → ~10 segments.
# Run: godot --headless -s tests/test_live_collision.gd

const WorldObstaclesScript := preload("res://scripts/pathing/world_obstacles.gd")


func _initialize() -> void:
	var fail := 0
	var pass_ := 0

	var level_packed: PackedScene = load("res://scenes/level_1/level_1.tscn")
	var level: Node = level_packed.instantiate()
	root.add_child(level)
	# _init_editor_state defers; wait for spawned_scenes to instantiate.
	await process_frame
	await process_frame
	await process_frame

	var objects = level.get_node_or_null("Objects")
	if objects == null:
		printerr("FAIL: no Objects node")
		quit(1)
		return
	print("Spawned items under Objects:")
	for child in objects.get_children():
		var src: String = child.get_meta("palette_source", "<not palette>")
		print("  %s (type=%s, src=%s)" % [child.name, child.get_class(), src])
		# Walk children for collision bodies + polygon counts.
		_print_collision_subtree(child, "    ")

	# Now extract via WorldObstacles.
	var segs: Array = WorldObstaclesScript.collect_wall_segments(level)
	print("WorldObstacles.collect_wall_segments(level) → %d segments" % segs.size())
	if segs.size() > 0:
		pass_ += 1
		print("PASS  WorldObstacles found %d segments" % segs.size())
	else:
		fail += 1
		printerr("FAIL  WorldObstacles found 0 segments — no spawned collision is reaching the pathfinder")

	# Per-spawn breakdown: which spawned items contributed.
	for child in objects.get_children():
		var child_segs: Array = WorldObstaclesScript.collect_wall_segments(child)
		var src: String = child.get_meta("palette_source", "")
		print("  %s (%s) → %d segments" % [child.name, src, child_segs.size()])

	level.queue_free()
	print("---")
	print("Total: %d passed, %d failed" % [pass_, fail])
	quit(0 if fail == 0 else 1)


func _print_collision_subtree(node: Node, indent: String) -> void:
	for child in node.get_children():
		if child is CollisionPolygon2D:
			var parent_co := child.get_parent() as CollisionObject2D
			var layer := parent_co.collision_layer if parent_co else -1
			print("%s%s (parent_layer=%d, %d verts)" % [indent, child.name, layer, (child as CollisionPolygon2D).polygon.size()])
		else:
			_print_collision_subtree(child, indent + "  ")
