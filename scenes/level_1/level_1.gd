extends Node2D

const SAVE_PATH := "user://level_1_edits.json"
const LIGHTS_SAVE_PATH := "user://level_1_lights.json"
const INTRO_DURATION := 1.5
const DOOR_SLIDE_X := 100.0

var _baseline_keys: Array = []
var _baseline_light_keys: Array = []


func _ready() -> void:
	call_deferred("_init_level")


func _init_level() -> void:
	_capture_baseline()
	_capture_baseline_lights()
	await _apply_saved_edits()
	await _apply_saved_light_edits()
	_start_door_intro()


func _capture_baseline_lights() -> void:
	_baseline_light_keys.clear()
	for n in _all_lights():
		_baseline_light_keys.append(_node_key(n))


func _all_lights() -> Array:
	var lighting := get_node_or_null("Lighting")
	if lighting == null:
		return []
	var arr: Array = []
	for n in lighting.get_children():
		if n is Light2D:
			arr.append(n)
	return arr


func _capture_baseline() -> void:
	_baseline_keys.clear()
	for n in get_tree().get_nodes_in_group("editable"):
		_baseline_keys.append(_node_key(n))


func _node_key(node: Node) -> String:
	var parent := node.get_parent()
	var parent_path := str(get_path_to(parent)) if parent else ""
	return "%s|%s" % [parent_path, str(node.name)]


func _apply_saved_edits() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
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

	var consumed := {}
	for n in get_tree().get_nodes_in_group("editable"):
		var key := _node_key(n)
		if by_key.has(key):
			_apply_transform_to_node(n, by_key[key])
			consumed[key] = true

	for n in get_tree().get_nodes_in_group("editable"):
		if _node_key(n) in deleted:
			n.queue_free()

	await get_tree().process_frame

	for key in by_key:
		if not consumed.has(key):
			_create_from_save(by_key[key])


func _apply_transform_to_node(node: Node, e: Dictionary) -> void:
	if not (node is Sprite2D):
		return
	var spr := node as Sprite2D
	var pos: Array = e.get("position", [spr.position.x, spr.position.y])
	spr.position = Vector2(float(pos[0]), float(pos[1]))
	var sc: Array = e.get("scale", [spr.scale.x, spr.scale.y])
	spr.scale = Vector2(float(sc[0]), float(sc[1]))
	spr.z_index = int(e.get("z_index", spr.z_index))


func _create_from_save(e: Dictionary) -> void:
	if e.get("type", "") != "Sprite2D":
		return
	var parent_path: String = e.get("parent", "")
	var parent := get_node_or_null(parent_path)
	if parent == null:
		return
	var spr := Sprite2D.new()
	spr.name = e.get("name", "Editable")
	spr.add_to_group("editable")
	spr.centered = e.get("centered", true)
	var tex_path: String = e.get("texture", "")
	if tex_path != "" and ResourceLoader.exists(tex_path):
		spr.texture = load(tex_path)
	var pos: Array = e.get("position", [0.0, 0.0])
	spr.position = Vector2(float(pos[0]), float(pos[1]))
	var sc: Array = e.get("scale", [1.0, 1.0])
	spr.scale = Vector2(float(sc[0]), float(sc[1]))
	spr.z_index = int(e.get("z_index", 0))
	parent.add_child(spr)


func save_edits() -> void:
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

	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"version": 2,
			"transforms": transforms,
			"deleted": deleted_keys,
		}, "\t"))
		f.close()


func _apply_saved_light_edits() -> void:
	if not FileAccess.file_exists(LIGHTS_SAVE_PATH):
		return
	var f := FileAccess.open(LIGHTS_SAVE_PATH, FileAccess.READ)
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

	var consumed := {}
	for n in _all_lights():
		var key := _node_key(n)
		if by_key.has(key):
			_apply_light_props(n, by_key[key])
			consumed[key] = true

	for n in _all_lights():
		if _node_key(n) in deleted:
			n.queue_free()

	await get_tree().process_frame

	for key in by_key:
		if not consumed.has(key):
			_create_light_from_save(by_key[key])


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
			if typeof(ov) == TYPE_DICTIONARY:
				var ov_node := l.get_node_or_null(str(ov.get("name", "")))
				if ov_node and ov_node is CanvasItem:
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


func _create_light_from_save(e: Dictionary) -> void:
	var lighting := get_node_or_null("Lighting")
	if lighting == null:
		return
	var t: String = e.get("type", "")
	var n: Light2D = null
	if t == "PointLight2D":
		var pl := PointLight2D.new()
		var tex_path: String = e.get("texture", "")
		if tex_path != "" and ResourceLoader.exists(tex_path):
			pl.texture = load(tex_path)
		else:
			pl.texture = _make_radial_texture()
		n = pl
	elif t == "DirectionalLight2D":
		n = DirectionalLight2D.new()
	if n == null:
		return
	n.name = str(e.get("name", "Light"))
	lighting.add_child(n)
	_apply_light_props(n, e)


func _make_radial_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


func save_light_edits() -> void:
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

	var f := FileAccess.open(LIGHTS_SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"version": 1,
			"lights": lights,
			"deleted": deleted_keys,
		}, "\t"))
		f.close()


func _start_door_intro() -> void:
	var door := get_node_or_null("Objects/Door") as Node2D
	if door == null:
		return
	var delta := _iso_project_v3(Vector3(DOOR_SLIDE_X, 0, 0))
	if delta.length() < 0.5:
		return
	var target := door.global_position + delta
	get_tree().paused = true
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(door, "global_position", target, INTRO_DURATION)
	tween.finished.connect(_on_door_intro_finished)


func _on_door_intro_finished() -> void:
	get_tree().paused = false


func _iso_project_v3(p: Vector3) -> Vector2:
	var c := cos(deg_to_rad(30.0))
	var s := sin(deg_to_rad(30.0))
	return Vector2((p.x + p.y) * c, (p.x - p.y) * s - p.z)


func get_wall_segments() -> Array:
	return []


func get_chest_obstacle() -> Dictionary:
	return {"center": Vector2.ZERO, "radius": 0.0}
