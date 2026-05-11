extends RefCounted

# Preloaded by callers (main.gd, tests) — no class_name so we don't depend on
# Godot's editor scan to register a global identifier.

# Walks a scene subtree and extracts pathfinder-format wall segments from
# CollisionPolygon2D children of physics bodies on collision_layer 1 (StaticBody2D /
# CharacterBody2D / etc.). Recognition Area2Ds (collision_layer 2) are skipped —
# they're detection zones, not movement obstacles.
#
# Output is in WORLD METERS to match Pathfinder's coordinate system. Polygon
# vertices are pulled through the parent body's global_transform (so spawned-and-
# moved walls follow their position/scale/rotation), then unprojected from
# iso-pixel world space to meters via the inline iso math (constants duplicated
# from autoloads/iso_math.gd so this helper is self-contained and unit-testable
# without the autoload graph).
#
# Returns Array of {a: Vector2, b: Vector2} matching the existing wall_segs schema.

const COLLISION_LAYER_PHYSICS_BIT := 1  # bit 0 → layer 1
const _COS30 := 0.8660254
const _SIN30 := 0.5
const _PPM := 32.0


static func collect_wall_segments(world_root: Node) -> Array:
	var segs: Array = []
	if world_root == null:
		return segs
	_collect_recursive(world_root, segs)
	return segs


static func _collect_recursive(node: Node, segs: Array) -> void:
	if node is CollisionPolygon2D:
		var parent := node.get_parent()
		if parent is CollisionObject2D:
			var co := parent as CollisionObject2D
			# Include only physics-layer obstacles, not recognition Area2Ds.
			if (co.collision_layer & COLLISION_LAYER_PHYSICS_BIT) != 0:
				_polygon_to_segments(node as CollisionPolygon2D, segs)
	for child in node.get_children():
		_collect_recursive(child, segs)


static func _polygon_to_segments(cp: CollisionPolygon2D, segs: Array) -> void:
	var poly: PackedVector2Array = cp.polygon
	if poly.size() < 2:
		return
	var xform := cp.global_transform
	# Transform local polygon vertices into world iso-pixel space, then unproject
	# to world meters. Edge segments wrap-close the polygon (last → first).
	var meter_verts := PackedVector2Array()
	for v in poly:
		var pixel_world := xform * v
		meter_verts.append(_unproject_iso(pixel_world))
	var n := meter_verts.size()
	for i in range(n):
		var a := meter_verts[i]
		var b := meter_verts[(i + 1) % n]
		segs.append({"a": a, "b": b})


static func _unproject_iso(pixel: Vector2) -> Vector2:
	var u := pixel.x / (_COS30 * _PPM)
	var v := pixel.y / (_SIN30 * _PPM)
	return Vector2((u + v) * 0.5, (u - v) * 0.5)
