extends Node2D

@export var show_debug_walls: bool = true

var chest_locked: bool = true
var chest_picked_up: bool = false

# F4 EditMode persistence — JSON save of `editable`-group sprite transforms.
# Format matches the v2 spec in changelog.md (transforms + deleted baseline keys).
const DEFAULT_EDITS_PATH := "user://level_1_edits.json"
var current_edits_path: String = DEFAULT_EDITS_PATH
var _baseline_keys: Array = []

# F5 LightMode persistence — JSON save of Lighting subtree (per-light props +
# overlays). Loader uses the same defensive pattern as the objects layer:
# only apply props to lights that exist in the captured baseline.
const DEFAULT_LIGHTS_PATH := "user://level_1_lights.json"
var current_lights_path: String = DEFAULT_LIGHTS_PATH
var _baseline_light_keys: Array = []


func _ready() -> void:
	call_deferred("_init_editor_state")


func _init_editor_state() -> void:
	_capture_baseline()
	_capture_baseline_lights()
	await _apply_saved_edits(current_edits_path)
	await _apply_saved_light_edits(current_lights_path)


func _capture_baseline() -> void:
	_baseline_keys.clear()
	for n in get_tree().get_nodes_in_group("editable"):
		_baseline_keys.append(_node_key(n))


func _node_key(node: Node) -> String:
	var parent := node.get_parent()
	var parent_path := str(get_path_to(parent)) if parent else ""
	return "%s|%s" % [parent_path, str(node.name)]


func _apply_saved_edits(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var transforms: Variant = parsed.get("transforms", parsed.get("objects", []))
	if typeof(transforms) != TYPE_ARRAY:
		return
	var deleted: Variant = parsed.get("deleted", [])
	if typeof(deleted) != TYPE_ARRAY:
		deleted = []

	var by_key := {}
	for e in transforms:
		if typeof(e) == TYPE_DICTIONARY:
			var key := "%s|%s" % [str(e.get("parent", "")), str(e.get("name", ""))]
			by_key[key] = e

	# Drift warning: surface save-vs-baseline mismatches loudly so future scene
	# edits that drop nodes referenced by a save are caught early. The user's
	# saved data stays in the JSON file untouched — only the in-scene apply is
	# skipped (the loader is defensive on purpose; see Phase 1 retro for the
	# 2026-05-08 incident where this was the bug we wished we'd had).
	for entry_key in by_key:
		if not _baseline_keys.has(entry_key):
			push_warning("level_1: save references '%s' but no such node in scene baseline. Either the .tscn was edited or the save is from a different version. Saved data is preserved in the save file but will not be restored." % entry_key)

	# Only restore transforms to nodes that already exist in the scene; never
	# instantiate "missing" entries (matches the defensive design above).
	# Same for `deleted`: only drop if it was in the captured baseline.
	for n in get_tree().get_nodes_in_group("editable"):
		var key := _node_key(n)
		if by_key.has(key):
			_apply_transform_to_node(n, by_key[key])

	for n in get_tree().get_nodes_in_group("editable"):
		var key2 := _node_key(n)
		if key2 in deleted and key2 in _baseline_keys:
			n.queue_free()

	await get_tree().process_frame


func _apply_transform_to_node(node: Node, e: Dictionary) -> void:
	if not (node is Sprite2D):
		return
	var spr := node as Sprite2D
	var pos: Array = e.get("position", [spr.position.x, spr.position.y])
	spr.position = Vector2(float(pos[0]), float(pos[1]))
	var sc: Array = e.get("scale", [spr.scale.x, spr.scale.y])
	spr.scale = Vector2(float(sc[0]), float(sc[1]))
	spr.z_index = int(e.get("z_index", spr.z_index))


# Writes `editable`-group sprite transforms to JSON. Returns "" on success or
# an error string. EditMode calls this from its Save / Save As buttons.
func save_edits_to(path: String) -> String:
	var transforms := []
	var current_keys := {}
	for n in get_tree().get_nodes_in_group("editable"):
		if n is Sprite2D:
			var spr := n as Sprite2D
			var parent_path := str(get_path_to(spr.get_parent()))
			var tex := ""
			if spr.texture and spr.texture.resource_path:
				tex = spr.texture.resource_path
			transforms.append({
				"name": str(spr.name),
				"parent": parent_path,
				"type": "Sprite2D",
				"texture": tex,
				"position": [spr.position.x, spr.position.y],
				"scale": [spr.scale.x, spr.scale.y],
				"centered": spr.centered,
				"z_index": spr.z_index,
			})
			current_keys[_node_key(spr)] = true

	var deleted_keys := []
	for bk in _baseline_keys:
		if not current_keys.has(bk):
			deleted_keys.append(bk)

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Could not open %s for writing (error %d)" % [path, FileAccess.get_open_error()]
	f.store_string(JSON.stringify({
		"version": 2,
		"transforms": transforms,
		"deleted": deleted_keys,
	}, "\t"))
	f.close()
	current_edits_path = path
	return ""


func save_edits() -> String:
	return save_edits_to(current_edits_path)


# ── F5 lights persistence ───────────────────────────────────────────────────

func _all_lights() -> Array:
	var lighting := get_node_or_null("Lighting")
	if lighting == null:
		return []
	var arr: Array = []
	for n in lighting.get_children():
		if n is Light2D:
			arr.append(n)
	return arr


func _capture_baseline_lights() -> void:
	_baseline_light_keys.clear()
	for n in _all_lights():
		_baseline_light_keys.append(_node_key(n))


func _apply_saved_light_edits(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var lights: Variant = parsed.get("lights", [])
	if typeof(lights) != TYPE_ARRAY:
		return
	var deleted: Variant = parsed.get("deleted", [])
	if typeof(deleted) != TYPE_ARRAY:
		deleted = []

	var by_key := {}
	for e in lights:
		if typeof(e) == TYPE_DICTIONARY:
			var key := "%s|%s" % [str(e.get("parent", "")), str(e.get("name", ""))]
			by_key[key] = e

	# Drift warning — same purpose as in _apply_saved_edits.
	for entry_key in by_key:
		if not _baseline_light_keys.has(entry_key):
			push_warning("level_1: light save references '%s' but no such Light2D in scene baseline. Either the .tscn was edited or the save is from a different version. Saved data is preserved in the save file but will not be restored." % entry_key)

	# Only restore properties to lights that already exist in the baseline; never
	# instantiate "missing" entries. Same defensive pattern as objects loader.
	for n in _all_lights():
		var key := _node_key(n)
		if by_key.has(key):
			_apply_light_props(n, by_key[key])

	for n in _all_lights():
		var key2 := _node_key(n)
		if key2 in deleted and key2 in _baseline_light_keys:
			n.queue_free()

	await get_tree().process_frame


func _apply_light_props(node: Node, e: Dictionary) -> void:
	if not (node is Light2D):
		return
	var l := node as Light2D
	var pos: Array = e.get("position", [l.position.x, l.position.y])
	l.position = Vector2(float(pos[0]), float(pos[1]))
	if e.has("rotation"):
		l.rotation = float(e["rotation"])
	if e.has("energy"):
		l.energy = float(e["energy"])
	if e.has("color"):
		var col: Array = e["color"]
		var a: float = float(col[3]) if col.size() > 3 else 1.0
		l.color = Color(float(col[0]), float(col[1]), float(col[2]), a)
	if "height" in l and e.has("height"):
		l.height = float(e["height"])
	if l is PointLight2D and e.has("texture_scale"):
		(l as PointLight2D).texture_scale = float(e["texture_scale"])
	if "base_rotation_deg" in l and e.has("base_rotation_deg"):
		l.set("base_rotation_deg", float(e["base_rotation_deg"]))
	if e.has("enabled"):
		l.enabled = bool(e["enabled"])
	if e.has("overlays") and typeof(e["overlays"]) == TYPE_ARRAY:
		for ov in e["overlays"]:
			if typeof(ov) != TYPE_DICTIONARY:
				continue
			var ov_node := l.get_node_or_null(str(ov.get("name", "")))
			if ov_node == null or not (ov_node is CanvasItem):
				continue
			var ci := ov_node as CanvasItem
			ci.visible = bool(ov.get("visible", true))
			if ov.has("opacity"):
				var m: Color = ci.modulate
				m.a = float(ov["opacity"])
				ci.modulate = m
			if ov.has("cone_color") and ci.material is ShaderMaterial:
				var arr: Array = ov["cone_color"]
				if arr.size() >= 3:
					var ca: float = float(arr[3]) if arr.size() >= 4 else 1.0
					var c := Color(float(arr[0]), float(arr[1]), float(arr[2]), ca)
					(ci.material as ShaderMaterial).set_shader_parameter("cone_color", c)


# Writes Lighting subtree to JSON. Returns "" on success or an error string.
# light_mode.gd's _persist() calls this via owner.call_deferred("save_light_edits").
func save_light_edits_to(path: String) -> String:
	var lights := []
	var current_keys := {}
	for n in _all_lights():
		var entry := {
			"name": str(n.name),
			"parent": str(get_path_to(n.get_parent())),
			"position": [n.position.x, n.position.y],
			"rotation": n.rotation,
			"energy": n.energy,
			"color": [n.color.r, n.color.g, n.color.b, n.color.a],
		}
		if n is PointLight2D:
			entry["type"] = "PointLight2D"
			entry["texture_scale"] = (n as PointLight2D).texture_scale
			var pl_tex := (n as PointLight2D).texture
			if pl_tex and pl_tex.resource_path:
				entry["texture"] = pl_tex.resource_path
		elif n is DirectionalLight2D:
			entry["type"] = "DirectionalLight2D"
		else:
			entry["type"] = "Light2D"
		if "height" in n:
			entry["height"] = n.height
		if "base_rotation_deg" in n:
			entry["base_rotation_deg"] = n.get("base_rotation_deg")
		entry["enabled"] = n.enabled

		var overlays := []
		for child in n.get_children():
			if child is CanvasItem and not (child is Light2D):
				var ci := child as CanvasItem
				var ov_entry := {
					"name": str(child.name),
					"visible": child.visible,
					"opacity": ci.modulate.a,
				}
				if ci.material is ShaderMaterial:
					var mat := ci.material as ShaderMaterial
					var ovc = mat.get_shader_parameter("cone_color")
					if ovc is Color:
						ov_entry["cone_color"] = [ovc.r, ovc.g, ovc.b, ovc.a]
				overlays.append(ov_entry)
		if overlays.size() > 0:
			entry["overlays"] = overlays
		lights.append(entry)
		current_keys[_node_key(n)] = true

	var deleted_keys := []
	for bk in _baseline_light_keys:
		if not current_keys.has(bk):
			deleted_keys.append(bk)

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Could not open %s for writing (error %d)" % [path, FileAccess.get_open_error()]
	f.store_string(JSON.stringify({
		"version": 1,
		"lights": lights,
		"deleted": deleted_keys,
	}, "\t"))
	f.close()
	current_lights_path = path
	return ""


func save_light_edits() -> String:
	return save_light_edits_to(current_lights_path)


# ── Wall pixel constants (texture space) ──────────────────────────────────────
# Extracted by scripts/tools/analyze_walls.py from Wall_X.png and Wall_Y.png
# alpha edges. Texture size 2412×1760, sprite scale 0.5307, position (0,0).
#
# Wall_X runs at roughly constant world_y ≈ 4 m (the back wall, with door).
# Wall_Y runs at roughly constant world_x ≈ −5 m (the left wall, solid).
# The two walls share a corner at approximately world (−4.55, 3.56).

const _WX_SEG1_A := Vector2(1155.0,  635.0)   # Wall_X seg-1 start — shared wall corner
const _WX_SEG1_B := Vector2(1453.0,  754.0)   # Wall_X seg-1 end   — left door edge
const _WX_SEG2_A := Vector2(1546.0,  841.0)   # Wall_X seg-2 start — right door edge
const _WX_SEG2_B := Vector2(2033.0, 1064.0)   # Wall_X seg-2 end   — far-right corner

const _WY_SEG_A  := Vector2( 279.0, 1065.0)   # Wall_Y start — far end (bottom)
const _WY_SEG_B  := Vector2(1154.0,  636.0)   # Wall_Y end   — shared wall corner


func unlock_chest() -> void:
	chest_locked = false
	queue_redraw()


func lock_chest() -> void:
	chest_locked = true
	queue_redraw()


func pickup_chest() -> void:
	chest_picked_up = true
	queue_redraw()


func _draw() -> void:
	if not show_debug_walls:
		return
	for seg in get_wall_segments():
		draw_line(IsoMath.project(seg["a"]), IsoMath.project(seg["b"]), Color.RED, 2.0)
	var chest := get_chest_obstacle()
	if chest_picked_up:
		return
	var screen_center: Vector2 = IsoMath.project(chest["center"])
	var r: float = chest["radius"] * IsoMath.PPM * 0.6
	if chest_locked:
		draw_circle(screen_center, r, Color(1.0, 0.85, 0.1, 0.7))   # gold = locked
		draw_arc(screen_center, r, 0.0, TAU, 24, Color(0.8, 0.6, 0.0), 2.0)
	else:
		draw_circle(screen_center, r, Color(0.65, 0.65, 0.65, 0.7)) # grey = unlocked


# Convert a texture-space pixel coordinate to world meters, accounting for the
# sprite's scale and centered-origin placement in the scene.
func _texture_pixel_to_world(tex_px: Vector2, sprite: Sprite2D) -> Vector2:
	var tex_size: Vector2 = sprite.texture.get_size()
	var screen_offset: Vector2 = (tex_px - tex_size * 0.5) * sprite.scale
	var screen_pos: Vector2 = sprite.position + screen_offset
	return IsoMath.unproject(screen_pos)


func get_wall_segments() -> Array:
	# Lines are flush with the floor diamond edges, not the alpha-detected wall base
	# (which tilts due to 3D wall thickness in the art).
	# Door gap on the back wall: world x ∈ [0.28, 2.61] from alpha analysis.
	return [
		{"a": Vector2(-4.54,  3.56), "b": Vector2( 0.28,  3.56)},  # back wall, left of door
		{"a": Vector2( 2.61,  3.56), "b": Vector2(10.97,  3.56)},  # back wall, right of door
		{"a": Vector2(-4.54, -11.94), "b": Vector2(-4.54,  3.56)}, # left wall
	]


# Axis-aligned bounding rectangle of the room floor in world meters.
# Derived from wall endpoints — not from Floor.png alpha (which has debris).
func get_room_bounds() -> Rect2:
	var wx: Sprite2D = $Background/Wall_X
	var wy: Sprite2D = $Background/Wall_Y
	var junction := _texture_pixel_to_world(_WX_SEG1_A, wx)  # shared corner = (x_min, y_max)
	var x_max    := _texture_pixel_to_world(_WX_SEG2_B, wx).x
	var y_min    := _texture_pixel_to_world(_WY_SEG_A,  wy).y
	return Rect2(Vector2(junction.x, y_min), Vector2(x_max - junction.x, junction.y - y_min))


func get_door_centers() -> Array:
	return [Vector2(1.44, 3.56)]  # midpoint of door gap at the back wall's y


func get_chest_obstacle() -> Dictionary:
	# Chest at floor centroid so it stays centered if the sprite ever moves.
	return {"center": get_room_bounds().get_center(), "radius": 0.75}
