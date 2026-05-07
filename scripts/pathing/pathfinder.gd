## Pathfinder
## Visibility-graph + A* pathfinder on continuous 2D pixel coordinates.
## Inputs: start/goal (Vector2), circular obstacles ({center, radius}), wall segments (PackedVector2Array[2]).
## Output: Array[Vector2] of waypoints start→goal, or [] if unreachable.
## Obstacles are inflated by CHAR_RADIUS (Minkowski sum) so the output path is valid for character centers.
## Does NOT smooth paths (use PathSmoother). Does NOT access scene nodes or game state.

class_name Pathfinder

const CHAR_RADIUS := 8.0   # pixels; 0.5m × 16px/m — inflated onto all obstacle radii
const EPSILON     := 0.5   # px; tolerance for duplicate nodes and edge clearance

## circles: Array of {center: Vector2, radius: float}
## wall_segs: Array of PackedVector2Array, each with exactly 2 points [p1, p2]
static func compute(
		from: Vector2,
		to: Vector2,
		circles: Array,
		wall_segs: Array) -> Array[Vector2]:

	if from.distance_to(to) < EPSILON:
		return [from] as Array[Vector2]

	# 1 — inflate all circles by CHAR_RADIUS
	var inflated: Array = []
	for c in circles:
		inflated.append({center = c["center"], radius = c["radius"] + CHAR_RADIUS})

	# 2 — Build candidate VG nodes
	var nodes: Array[Vector2] = []
	nodes.append(from)   # index 0
	nodes.append(to)     # index 1

	# Wall endpoints (door corners)
	for ws: PackedVector2Array in wall_segs:
		_add_unique(nodes, ws[0])
		_add_unique(nodes, ws[1])

	# Tangent points from primary nodes to each inflated circle
	var primary_count := nodes.size()
	for i in primary_count:
		for circ in inflated:
			_add_tangent_nodes(nodes, nodes[i], circ)

	# Second pass: tangent points from tangent nodes to each circle
	# (handles paths that navigate around two circles sequentially)
	var sec_end := nodes.size()
	for i in range(primary_count, sec_end):
		for circ in inflated:
			_add_tangent_nodes(nodes, nodes[i], circ)

	# 3 — Build visibility edges
	var n := nodes.size()
	var adj: Array = []
	adj.resize(n)
	for i in n:
		adj[i] = []

	for i in n:
		for j in range(i + 1, n):
			if _edge_clear(nodes[i], nodes[j], inflated, wall_segs):
				var cost := nodes[i].distance_to(nodes[j])
				adj[i].append({j = j, cost = cost})
				adj[j].append({j = i, cost = cost})

	# 4 — A* from index 0 (from) to index 1 (to)
	return _astar(nodes, adj, 0, 1)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _add_unique(nodes: Array[Vector2], p: Vector2) -> void:
	for existing: Vector2 in nodes:
		if existing.distance_squared_to(p) < EPSILON * EPSILON:
			return
	nodes.append(p)

static func _add_tangent_nodes(
		nodes: Array[Vector2], p: Vector2, circ: Dictionary) -> void:
	var c: Vector2 = circ["center"]
	var r: float   = circ["radius"]
	var d := p.distance_to(c)
	if d <= r + EPSILON:
		return  # p inside or on inflated circle — no tangent
	var u := (c - p) / d
	var v := Vector2(-u.y, u.x)
	var t_along := (d * d - r * r) / d
	var t_perp  := r * sqrt(maxf(0.0, 1.0 - (r * r) / (d * d)))
	_add_unique(nodes, p + t_along * u + t_perp * v)
	_add_unique(nodes, p + t_along * u - t_perp * v)

static func _edge_clear(
		a: Vector2, b: Vector2,
		inflated: Array, wall_segs: Array) -> bool:
	for circ in inflated:
		if _pt_seg_dist_sq(circ["center"], a, b) < circ["radius"] * circ["radius"] - EPSILON:
			return false
	for ws: PackedVector2Array in wall_segs:
		if _segs_intersect(a, b, ws[0], ws[1]):
			return false
	return true

static func _pt_seg_dist_sq(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_squared_to(a + t * ab)

static func _segs_intersect(
		a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	var d1 := a2 - a1
	var d2 := b2 - b1
	var denom := d1.x * d2.y - d1.y * d2.x
	if absf(denom) < 1e-9:
		return false  # parallel
	var t := ((b1.x - a1.x) * d2.y - (b1.y - a1.y) * d2.x) / denom
	var u := ((b1.x - a1.x) * d1.y - (b1.y - a1.y) * d1.x) / denom
	# Use strict interior check (0.01…0.99) so shared endpoints don't count as crossings.
	return t > 0.01 and t < 0.99 and u > 0.01 and u < 0.99

# ---------------------------------------------------------------------------
# A*
# ---------------------------------------------------------------------------

static func _astar(
		nodes: Array[Vector2], adj: Array,
		start_idx: int, goal_idx: int) -> Array[Vector2]:
	var n := nodes.size()
	var g: Array[float] = []
	g.resize(n)
	g.fill(INF)
	g[start_idx] = 0.0

	var came_from: Array[int] = []
	came_from.resize(n)
	came_from.fill(-1)

	var closed: Array[bool] = []
	closed.resize(n)
	closed.fill(false)

	# open_set: unsorted array; we pop the lowest-f entry each step.
	var open_set: Array = [{idx = start_idx, f = nodes[start_idx].distance_to(nodes[goal_idx])}]

	while not open_set.is_empty():
		# Find and remove lowest f
		var best_i := 0
		for i in range(1, open_set.size()):
			if open_set[i].f < open_set[best_i].f:
				best_i = i
		var cur: Dictionary = open_set[best_i]
		open_set.remove_at(best_i)

		var ci: int = cur.idx
		if closed[ci]:
			continue
		closed[ci] = true

		if ci == goal_idx:
			return _reconstruct(came_from, nodes, goal_idx)

		for edge in adj[ci]:
			var nb: int = edge.j
			if closed[nb]:
				continue
			var tentative: float = (g[ci] as float) + (edge.cost as float)
			if tentative < (g[nb] as float):
				g[nb] = tentative
				came_from[nb] = ci
				open_set.append({idx = nb, f = tentative + nodes[nb].distance_to(nodes[goal_idx])})

	return []  # unreachable

static func _reconstruct(
		came_from: Array[int], nodes: Array[Vector2], goal: int) -> Array[Vector2]:
	var path: Array[Vector2] = []
	var cur := goal
	while cur != -1:
		path.append(nodes[cur])
		cur = came_from[cur]
	path.reverse()
	return path
