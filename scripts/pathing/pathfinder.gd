class_name Pathfinder

const CHAR_RADIUS := 0.5  # meters
const EPSILON := 0.03     # meters

var _wall_segs: Array = []   # Array of {a: Vector2, b: Vector2}
var _obstacles: Array = []   # Array of {center: Vector2, radius: float}


func setup(wall_segs: Array, obstacles: Array) -> void:
	_wall_segs = wall_segs
	_obstacles = obstacles


func find_path(from: Vector2, to: Vector2) -> Array:
	if _los_clear(from, to):
		return [from, to]

	var nodes: Array = [from, to]

	const N_RING := 24
	for obs in _obstacles:
		var r_los: float = float(obs["radius"]) + CHAR_RADIUS
		# r_ring chosen so chord midpoint between adjacent ring nodes >= r_los
		# chord_midpoint = r_ring * cos(PI/N_RING)  =>  r_ring = r_los / cos(PI/N_RING) + EPSILON
		var r_ring: float = r_los / cos(PI / N_RING) + EPSILON
		var obs_center: Vector2 = obs["center"]
		for i in range(N_RING):
			var angle: float = i * TAU / N_RING
			var p: Vector2 = obs_center + Vector2(cos(angle), sin(angle)) * r_ring
			if _is_valid(p):
				nodes.append(p)

	for seg in _wall_segs:
		var wall_dir: Vector2 = (seg["b"] - seg["a"]).normalized()
		var perp := Vector2(-wall_dir.y, wall_dir.x)
		var pad := CHAR_RADIUS + EPSILON
		for pt in [seg["a"], seg["b"]]:
			for side in [1, -1]:
				for candidate in [
					pt + perp * (side * pad),
					pt + perp * (side * pad) + wall_dir * pad,
					pt + perp * (side * pad) - wall_dir * pad,
				]:
					if _is_valid(candidate):
						nodes.append(candidate)

	return _astar(from, to, nodes)


func _is_valid(p: Vector2) -> bool:
	for obs in _obstacles:
		if p.distance_to(obs["center"]) < obs["radius"] + CHAR_RADIUS - EPSILON:
			return false
	return true


func _los_clear(a: Vector2, b: Vector2) -> bool:
	for seg in _wall_segs:
		if _segs_intersect(a, b, seg["a"], seg["b"]):
			return false
	for obs in _obstacles:
		if _seg_circle_blocks(a, b, obs["center"], obs["radius"] + CHAR_RADIUS):
			return false
	return true


static func _segs_intersect(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	var d1 := a2 - a1
	var d2 := b2 - b1
	var cross := d1.cross(d2)
	if abs(cross) < 1e-9:
		return false
	var t := (b1 - a1).cross(d2) / cross
	var u := (b1 - a1).cross(d1) / cross
	# t is strict: graph nodes at wall tips are valid path endpoints.
	# u is inclusive: a path grazing a wall endpoint (u=0 or u=1) IS blocked.
	return t > 1e-6 and t < 1.0 - 1e-6 and u >= -1e-6 and u <= 1.0 + 1e-6


static func _point_seg_dist_sq(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.dot(ab)
	if len_sq < 1e-9:
		return p.distance_squared_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)


static func _seg_circle_blocks(a: Vector2, b: Vector2, center: Vector2, radius: float) -> bool:
	return _point_seg_dist_sq(center, a, b) < radius * radius


func _astar(start: Vector2, goal: Vector2, nodes: Array) -> Array:
	var n := nodes.size()
	if n == 0:
		return []

	# Build adjacency
	var adj: Array = []
	for i in range(n):
		adj.append([])
	for i in range(n):
		for j in range(i + 1, n):
			if _los_clear(nodes[i], nodes[j]):
				adj[i].append(j)
				adj[j].append(i)

	# A*
	var g: Array = []
	var f: Array = []
	for i in range(n):
		g.append(INF)
		f.append(INF)

	var came_from: Dictionary = {}
	var open_set: Dictionary = {}

	g[0] = 0.0
	f[0] = nodes[0].distance_to(nodes[1])
	open_set[0] = true

	while not open_set.is_empty():
		var current := _min_f(open_set, f)
		if current == 1:
			return _reconstruct(came_from, nodes, 1)
		open_set.erase(current)
		for nb in adj[current]:
			var tg: float = g[current] + nodes[current].distance_to(nodes[nb])
			if tg < g[nb]:
				came_from[nb] = current
				g[nb] = tg
				f[nb] = tg + nodes[nb].distance_to(nodes[1])
				open_set[nb] = true

	return []


static func _min_f(open_set: Dictionary, f: Array) -> int:
	var best := -1
	var best_f := INF
	for idx in open_set:
		if f[idx] < best_f:
			best_f = f[idx]
			best = idx
	return best


static func _reconstruct(came_from: Dictionary, nodes: Array, current: int) -> Array:
	var path := [nodes[current]]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(nodes[current])
	return path
