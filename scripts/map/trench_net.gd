@tool
class_name TrenchNet
extends RefCounted
## Route network along trench centre lines. Units moving inside the trench
## follow it (single file through traverses) instead of the open-ground grid.

var astar := AStar3D.new()
var pts: Array = []          # Vector3 node positions (on the floor)
var line_of: Array = []      # polyline index per node
var buckets := {}            # Vector2i(4 m) -> PackedInt32Array


func build(lines: Array, grid: TerrainGrid) -> void:
	var step := 1.6
	for li in lines.size():
		var src: PackedVector2Array = lines[li]
		var prev := -1
		for k in src.size() - 1:
			var a: Vector2 = src[k]
			var b: Vector2 = src[k + 1]
			var m := maxi(1, int(ceil(a.distance_to(b) / step)))
			for j in m + (1 if k == src.size() - 2 else 0):
				var p := a.lerp(b, float(j) / m)
				var id := _add(Vector3(p.x, grid.height_at(p.x, p.y), p.y), li)
				if prev >= 0:
					astar.connect_points(prev, id)
				prev = id
	# junctions: connect nodes of different lines that touch
	for i in pts.size():
		for j in _near_ids(pts[i], 2.2):
			if j != i and line_of[j] != line_of[i] and not astar.are_points_connected(i, j):
				if (pts[i] as Vector3).distance_to(pts[j]) < 2.2:
					astar.connect_points(i, j)


func _add(p: Vector3, li: int) -> int:
	var id := pts.size()
	pts.append(p)
	line_of.append(li)
	astar.add_point(id, p)
	var key := Vector2i(int(floor(p.x / 4.0)), int(floor(p.z / 4.0)))
	if not buckets.has(key):
		buckets[key] = PackedInt32Array()
	var arr: PackedInt32Array = buckets[key]
	arr.append(id)
	buckets[key] = arr
	return id


func _near_ids(p: Vector3, r: float) -> Array:
	var out: Array = []
	var k0 := Vector2i(int(floor((p.x - r) / 4.0)), int(floor((p.z - r) / 4.0)))
	var k1 := Vector2i(int(floor((p.x + r) / 4.0)), int(floor((p.z + r) / 4.0)))
	for bz in range(k0.y, k1.y + 1):
		for bx in range(k0.x, k1.x + 1):
			var key := Vector2i(bx, bz)
			if buckets.has(key):
				for id in buckets[key]:
					out.append(id)
	return out


func nearest(p: Vector3, max_d: float = 3.0) -> int:
	var best := -1
	var bd := max_d
	for id in _near_ids(p, max_d):
		var d: float = Vector2(p.x - pts[id].x, p.z - pts[id].z).length()
		if d < bd:
			bd = d
			best = id
	return best


## Nearest node over a larger radius (for entering the trench from outside).
func nearest_far(p: Vector3, max_d: float = 60.0) -> int:
	var best := -1
	var bd := max_d
	for id in pts.size():
		var d: float = Vector2(p.x - pts[id].x, p.z - pts[id].z).length()
		if d < bd:
			bd = d
			best = id
	return best


func path(a: int, b: int) -> PackedVector3Array:
	if a < 0 or b < 0:
		return PackedVector3Array()
	return astar.get_point_path(a, b)


## A node roughly `dist` metres along the network away from `threat`.
func fallback_node(from: Vector3, threat: Vector3, dist: float) -> int:
	var start := nearest(from, 3.0)
	if start < 0:
		return -1
	var best := -1
	var best_s := -INF
	for id in _near_ids(from, dist + 6.0):
		var p: Vector3 = pts[id]
		var dd := from.distance_to(p)
		if dd < dist * 0.6 or dd > dist * 1.5:
			continue
		var sc := p.distance_to(threat) - from.distance_to(threat)
		if sc > best_s:
			best_s = sc
			best = id
	return best
