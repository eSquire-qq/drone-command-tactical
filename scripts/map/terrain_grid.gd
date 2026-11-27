@tool
class_name TerrainGrid
extends RefCounted
## Height field + tactical cell grid (2 m cells): cover, foliage, obstacles,
## trench flags and navigation (AStarGrid2D) for infantry and vehicles.
## Also provides line-of-sight and mouse ray picking without physics.

const CS := 2.0

enum G { GRASS, DRY, MUD, ROAD, FOREST, TRENCH, CRATER, DIRT, YARD, BURNT, SPOIL }

# dug trench profile (metres from the centre line)
const T_WALL := 0.7      # revetted wall face
const T_CAP := 1.75       # outer edge of the parapet
const T_FOOT := 2.35      # where the parapet slope meets the ground
const T_DEPTH := 1.85     # floor below natural ground
const T_PARAPET := 0.32   # parapet height above natural ground

var size := 160.0
var half := 80.0
var res := 0.8
var n := 0
var heights := PackedFloat32Array()
var nat := PackedFloat32Array()          # natural ground before trenches
var t_segs: Array = []                   # [Vector2 a, Vector2 b, int line]
var t_buckets := {}                      # Vector2i(4 m cell) -> PackedInt32Array
var trench_near := PackedByteArray()
var trench_net = null                    # TrenchNet
var gtype := PackedByteArray()

var cn := 0
var foliage := PackedFloat32Array()
var camo := PackedByteArray()
var win_cell := PackedByteArray()   # cells with a window: line of sight passes at window height near its ends
var fog_len := 0.0                 # weather: sight fades with distance (0 = clear air)      # prepared camouflage (nets, turf) over fighting positions
var cover := PackedFloat32Array()
var obstacle := PackedFloat32Array()
var trench := PackedByteArray()
var inf_solid := PackedByteArray()
var veh_solid := PackedByteArray()
var inf_weight := PackedFloat32Array()
var veh_weight := PackedFloat32Array()
var astar_inf: AStarGrid2D
var astar_veh: AStarGrid2D


func setup(p_size: float, p_res: float) -> void:
	size = p_size
	half = size * 0.5
	res = p_res
	n = int(round(size / res)) + 1
	heights.resize(n * n)
	gtype.resize(n * n)
	cn = int(size / CS)
	var c2 := cn * cn
	foliage.resize(c2)
	camo.resize(c2)
	win_cell.resize(c2)
	cover.resize(c2)
	obstacle.resize(c2)
	trench.resize(c2)
	trench_near.resize(c2)
	inf_solid.resize(c2)
	veh_solid.resize(c2)
	inf_weight.resize(c2)
	veh_weight.resize(c2)
	inf_weight.fill(1.0)
	veh_weight.fill(1.0)


# ---------------------------------------------------------------- heights
func vx(ix: int) -> float:
	return -half + ix * res


func height_at(x: float, z: float) -> float:
	var fx := clampf((x + half) / res, 0.0, n - 1.001)
	var fz := clampf((z + half) / res, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * n + ix
	var a := lerpf(heights[i], heights[i + 1], tx)
	var b := lerpf(heights[i + n], heights[i + n + 1], tx)
	return lerpf(a, b, tz)


func nat_at(x: float, z: float) -> float:
	if nat.is_empty():
		return height_at(x, z)
	var fx := clampf((x + half) / res, 0.0, n - 1.001)
	var fz := clampf((z + half) / res, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * n + ix
	return lerpf(lerpf(nat[i], nat[i + 1], tx), lerpf(nat[i + n], nat[i + n + 1], tx), tz)


# ---------------------------------------------------------------- trenches
func add_trench_lines(lines: Array) -> void:
	t_segs.clear()
	t_buckets.clear()
	for li in lines.size():
		var pts: PackedVector2Array = lines[li]
		for k in pts.size() - 1:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var si := t_segs.size()
			t_segs.append([a, b, li])
			var r := Rect2(a, Vector2.ZERO).expand(b).grow(T_FOOT + 1.0)
			for bz in range(int(floor(r.position.y / 4.0)), int(floor(r.end.y / 4.0)) + 1):
				for bx in range(int(floor(r.position.x / 4.0)), int(floor(r.end.x / 4.0)) + 1):
					var key := Vector2i(bx, bz)
					if not t_buckets.has(key):
						t_buckets[key] = PackedInt32Array()
					var arr: PackedInt32Array = t_buckets[key]
					arr.append(si)
					t_buckets[key] = arr


## Closest point on any trench centre line: Vector3(x, z, distance).
## exclude_line skips one polyline (for junction tests).
func trench_closest(x: float, z: float, exclude_line: int = -1) -> Vector3:
	var key := Vector2i(int(floor(x / 4.0)), int(floor(z / 4.0)))
	if not t_buckets.has(key):
		return Vector3(x, z, INF)
	var p := Vector2(x, z)
	var best := Vector3(x, z, INF)
	for si in t_buckets[key]:
		var sg: Array = t_segs[si]
		if int(sg[2]) == exclude_line:
			continue
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 0.0001 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var c := a + ab * t
		var d := p.distance_to(c)
		if d < best.z:
			best = Vector3(c.x, c.y, d)
	return best


## A clicked / ordered point near a trench (within `radius` m) moved onto the
## trench centre line; null when no trench is that close.
func snap_to_trench(p: Vector3, radius: float = 4.0):
	var c := trench_closest(p.x, p.z)
	if c.z > radius:
		# trench_closest only looks into the 4 m bucket of the point
		for off in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
			var c2 := trench_closest(p.x + off.x, p.z + off.y)
			if c2.z < INF:
				c2.z = Vector2(c2.x, c2.y).distance_to(Vector2(p.x, p.z))
				if c2.z < c.z:
					c = c2
	if c.z > radius:
		return null
	return ground(Vector3(c.x, 0, c.y))


func trench_d(x: float, z: float) -> float:
	return trench_closest(x, z).z


func in_channel(p: Vector3, tol: float = 0.9) -> bool:
	return trench_near[cidx(p.x, p.z)] != 0 and trench_d(p.x, p.z) < tol


## Ground height as seen by line-of-sight: revetted walls and parapets block.
func los_ground(x: float, z: float, gh: float) -> float:
	var d := trench_d(x, z)
	if d < T_WALL or d >= T_CAP:
		return gh
	return nat_at(x, z) + T_PARAPET


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.8
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func ground(p: Vector3) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.z), p.z)


func in_bounds(x: float, z: float, margin: float = 0.0) -> bool:
	return absf(x) <= half - margin and absf(z) <= half - margin


func clamp_in(p: Vector3, margin: float = 2.0) -> Vector3:
	return Vector3(clampf(p.x, -half + margin, half - margin), p.y, clampf(p.z, -half + margin, half - margin))


# ---------------------------------------------------------------- cells
func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int((x + half) / CS), 0, cn - 1), clampi(int((z + half) / CS), 0, cn - 1))


func ci(c: Vector2i) -> int:
	return c.y * cn + c.x


func cidx(x: float, z: float) -> int:
	return clampi(int((z + half) / CS), 0, cn - 1) * cn + clampi(int((x + half) / CS), 0, cn - 1)


func cell_center(c: Vector2i) -> Vector3:
	var x := -half + (c.x + 0.5) * CS
	var z := -half + (c.y + 0.5) * CS
	return Vector3(x, height_at(x, z), z)


func cover_at(p: Vector3) -> float:
	return cover[cidx(p.x, p.z)]


func foliage_at(p: Vector3) -> float:
	return foliage[cidx(p.x, p.z)]


func camo_at(p: Vector3) -> bool:
	return camo[cidx(p.x, p.z)] != 0


func is_trench(p: Vector3) -> bool:
	return trench[cidx(p.x, p.z)] != 0


func is_inf_solid(p: Vector3) -> bool:
	return inf_solid[cidx(p.x, p.z)] != 0


# ---------------------------------------------------------------- line of sight
## Returns visibility 0..1 between two points (0 = blocked).
func visibility(a: Vector3, b: Vector3) -> float:
	if not Prof.on:
		return _visibility_raw(a, b)
	var t0 := Time.get_ticks_usec()
	var r := _visibility_raw(a, b)
	Prof.add("grid.visibility", t0)
	return r


func _visibility_raw(a: Vector3, b: Vector3) -> float:
	var d := b - a
	var dist := d.length()
	if dist < 1.0:
		return 1.0
	var dir := d / dist
	var step := 2.0
	var fol := 0.0
	var t := 1.0
	while t < dist - 1.0:
		var px := a.x + dir.x * t
		var py := a.y + dir.y * t
		var pz := a.z + dir.z * t
		var gh := height_at(px, pz)
		var i := cidx(px, pz)
		if trench_near[i] != 0:
			gh = los_ground(px, pz, gh)
		if py < gh + 0.05:
			return 0.0
		var ob := obstacle[i]
		if ob > 0.0 and py < gh + ob:
			# through a window: only right next to one end of the line (the man at
			# the window, or a man looking in from just outside), at window height
			if not (win_cell[i] != 0 and (t < 2.6 or t > dist - 2.6) and py > gh + 0.9):
				return 0.0
		var f := foliage[i]
		if f > 0.0 and py < gh + 7.5:
			fol += f * step
			if fol > 7.0:
				return 0.0   # a dense tree line is opaque at depth
		t += step
	for sc in W.smoke_clouds:
		var c: Vector3 = sc["pos"]
		var r: float = sc["r"]
		var k := clampf((c - a).dot(dir), 0.0, dist)
		if (a + dir * k).distance_to(c) < r * 0.85 * minf(1.0, float(sc.get("dens", 1.0)) * 1.4):
			return 0.0
	var v := exp(-fol * 0.085)
	if fog_len > 0.0:
		v *= exp(-dist / fog_len)
	return v


## Marches a ray against the height field. Returns hit point or null.
func raycast(origin: Vector3, dir: Vector3, max_dist: float = 900.0):
	if dir.y >= -0.0001:
		return null
	var t := 0.0
	if origin.y > 6.0:
		t = (origin.y - 6.0) / -dir.y
	var step := 0.6
	var prev := t
	while t < max_dist:
		var p := origin + dir * t
		if absf(p.x) > half + 1.0 or absf(p.z) > half + 1.0:
			if p.y < -2.0:
				return null
		elif p.y <= height_at(p.x, p.z):
			var lo := prev
			var hi := t
			for _i in 10:
				var mid := (lo + hi) * 0.5
				var q := origin + dir * mid
				if q.y <= height_at(q.x, q.z):
					hi = mid
				else:
					lo = mid
			var hp := origin + dir * hi
			if not in_bounds(hp.x, hp.z):
				return null
			return hp
		prev = t
		t += step
	return null


# ---------------------------------------------------------------- navigation
var veh_solid_light := PackedByteArray()   # stricter mobility profile (M113 / medevac)
var astar_light: AStarGrid2D
var last_partial := false                  # the last vehicle path could not reach the target


func build_nav() -> void:
	astar_inf = _make_astar(inf_solid, inf_weight)
	astar_veh = _make_astar(veh_solid, veh_weight)
	if veh_solid_light.size() != veh_solid.size():
		veh_solid_light = veh_solid.duplicate()
	astar_light = _make_astar(veh_solid_light, veh_weight)


func _solid_for(vehicle: bool, profile: String) -> PackedByteArray:
	if not vehicle:
		return inf_solid
	return veh_solid_light if profile == "light" else veh_solid


func _make_astar(solid: PackedByteArray, weight: PackedFloat32Array) -> AStarGrid2D:
	var a := AStarGrid2D.new()
	a.region = Rect2i(0, 0, cn, cn)
	a.cell_size = Vector2(CS, CS)
	a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	a.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	a.update()
	for z in cn:
		for x in cn:
			var i := z * cn + x
			if solid[i] != 0:
				a.set_point_solid(Vector2i(x, z), true)
			elif weight[i] != 1.0:
				a.set_point_weight_scale(Vector2i(x, z), weight[i])
	return a


func nearest_free(c: Vector2i, vehicle: bool, profile: String = "tracked") -> Vector2i:
	var solid := _solid_for(vehicle, profile)
	if solid[ci(c)] == 0:
		return c
	for r in range(1, 14):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var cc := Vector2i(c.x + dx, c.y + dz)
				if cc.x < 0 or cc.y < 0 or cc.x >= cn or cc.y >= cn:
					continue
				if solid[ci(cc)] == 0:
					return cc
	return c


func free_point(p: Vector3, vehicle: bool = false) -> Vector3:
	var c := cell_of(p.x, p.z)
	var f := nearest_free(c, vehicle)
	if f == c:
		return ground(p)
	return cell_center(f)


func find_path(from: Vector3, to: Vector3, vehicle: bool = false, profile: String = "tracked") -> PackedVector3Array:
	if not Prof.on:
		return _find_path_raw(from, to, vehicle, profile)
	var t0 := Time.get_ticks_usec()
	var r := _find_path_raw(from, to, vehicle, profile)
	Prof.add("grid.find_path", t0)
	return r


func _find_path_raw(from: Vector3, to: Vector3, vehicle: bool, profile: String = "tracked") -> PackedVector3Array:
	var a := astar_inf
	if vehicle:
		a = astar_light if profile == "light" else astar_veh
	var c0 := nearest_free(cell_of(from.x, from.z), vehicle, profile)
	var tc := cell_of(to.x, to.z)
	var c1 := nearest_free(tc, vehicle, profile)
	var out := PackedVector3Array()
	var ids: Array[Vector2i] = a.get_id_path(c0, c1, false)
	last_partial = false
	if ids.is_empty() and c0 != c1:
		# no full route: go as close as possible and let the caller report it
		ids = a.get_id_path(c0, c1, true)
		last_partial = true
		if vehicle and ids.size() <= 1:
			return out
		c1 = ids[ids.size() - 1] if ids.size() > 0 else c1
	if c1 != nearest_free(tc, vehicle, profile):
		tc = Vector2i(-1, -1)
	if ids.size() <= 1:
		out.append(ground(to) if c1 == tc else cell_center(c1))
		return out
	var raw: Array = []
	for id in ids:
		raw.append(cell_center(id))
	if c1 == tc:
		raw[raw.size() - 1] = ground(to)
	# string pulling
	var cur := from
	var i := 0
	while i < raw.size():
		var j := mini(raw.size() - 1, i + 12)
		while j > i and not _clear_line(cur, raw[j], vehicle):
			j -= 1
		out.append(raw[j])
		cur = raw[j]
		i = j + 1
	return out


## Infantry pathing that knows the trench network: inside the trench units
## follow the trench; with prefer_trench they enter at the closest point and
## move along it (trench clearing); leaving the trench uses the exit nearest
## to the destination.
func find_path_inf(from: Vector3, to: Vector3, prefer_trench: bool = false) -> PackedVector3Array:
	if trench_net == null:
		return find_path(from, to, false)
	var fin := in_channel(from, 1.0)
	var tin := in_channel(to, 1.2)
	var out := PackedVector3Array()
	if fin and tin:
		var a: int = trench_net.nearest(from, 3.0)
		var b: int = trench_net.nearest(to, 3.0)
		var tp: PackedVector3Array = trench_net.path(a, b)
		if tp.size() > 0:
			out.append_array(tp)
			out.append(ground(to))
			return out
	if tin and prefer_trench:
		var e: int = trench_net.nearest_far(from, 120.0)
		var b2: int = trench_net.nearest(to, 3.0)
		if e >= 0 and b2 >= 0:
			var entry: Vector3 = trench_net.pts[e]
			out.append_array(find_path(from, entry, false))
			out.append_array(trench_net.path(e, b2))
			out.append(ground(to))
			return out
	if fin and not tin:
		var a3: int = trench_net.nearest(from, 3.0)
		var b3: int = trench_net.nearest_far(to, 40.0)
		if a3 >= 0 and b3 >= 0 and a3 != b3:
			var exitp: Vector3 = trench_net.pts[b3]
			if exitp.distance_to(to) < from.distance_to(to) - 4.0:
				out.append_array(trench_net.path(a3, b3))
				out.append_array(find_path(exitp, to, false))
				return out
	return find_path(from, to, false)


func _clear_line(a: Vector3, b: Vector3, vehicle: bool) -> bool:
	var solid := veh_solid_light if vehicle and veh_solid_light.size() == veh_solid.size() else (veh_solid if vehicle else inf_solid)
	var w := veh_weight if vehicle else inf_weight
	var dx := b.x - a.x
	var dz := b.z - a.z
	var L := sqrt(dx * dx + dz * dz)
	var steps := int(L / (CS * 0.5)) + 1
	for s in range(steps + 1):
		var t := float(s) / steps
		var i := cidx(a.x + dx * t, a.z + dz * t)
		if solid[i] != 0 or w[i] > 1.5:
			return false
	return true


## Picks the best cover cell around pos. threat: Vector3 or null.
## The best nearby spot to take cover. Every free cell within the radius gets
## a base score (cover, concealment, distance, not running towards the threat,
## not on top of a comrade); with a known threat the best few are checked
## against it for real — is a man lying / crouching there seen from the threat?
## — and, for a man who has to fight, whether he can see the threat when he
## rises to shoot. A new spot must be clearly better than where he stands
## (hysteresis): otherwise his own position comes back and he stays.
func find_cover(pos: Vector3, radius: float, threat, occupied: Array, needs_view: bool = true) -> Vector3:
	var c0 := cell_of(pos.x, pos.z)
	var r := int(ceil(radius / CS))
	var tdir := Vector3.ZERO
	if threat != null:
		tdir = (threat - pos)
		tdir.y = 0.0
		tdir = tdir.normalized()
	var cands: Array = []   # [score, cell centre]
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := Vector2i(c0.x + dx, c0.y + dz)
			if c.x < 1 or c.y < 1 or c.x >= cn - 1 or c.y >= cn - 1:
				continue
			var i := ci(c)
			if inf_solid[i] != 0:
				continue
			var cc := cell_center(c)
			var d := Vector2(cc.x - pos.x, cc.z - pos.z).length()
			if d > radius:
				continue
			var s := cover[i] * 2.0 + foliage[i] * 0.35 - d / radius * 0.45
			if threat != null and (cc - pos).dot(tdir) > 3.0:
				s -= 0.35
			for o in occupied:
				if Vector2(o.x - cc.x, o.z - cc.z).length_squared() < 2.6:
					s -= 1.2
			s += randf() * 0.06
			cands.append([s, cc])
	if cands.is_empty():
		return ground(pos)
	cands.sort_custom(func(a, b): return a[0] > b[0])
	if threat == null:
		var b0: Vector3 = cands[0][1]
		return ground(b0 + Vector3(randf_range(-0.45, 0.45), 0, randf_range(-0.45, 0.45)))
	var here := cover_score(pos, threat, needs_view) + cover[cidx(pos.x, pos.z)] * 2.0 + foliage[cidx(pos.x, pos.z)] * 0.35
	var best := pos
	var best_s := here + AIConfig.COVER_HYSTERESIS
	for k in mini(AIConfig.COVER_CHECKS, cands.size()):
		var cc: Vector3 = cands[k][1]
		var s2: float = float(cands[k][0]) + cover_score(cc, threat, needs_view)
		if s2 > best_s:
			best_s = s2
			best = cc
	if best == pos:
		return pos
	return ground(best + Vector3(randf_range(-0.35, 0.35), 0, randf_range(-0.35, 0.35)))


## How well a spot protects from one threat: hidden when lying / crouching
## there (seen from the threat's eye), plus — for a man who has to fight — a
## view of the threat when he rises to shoot.
func cover_score(p: Vector3, threat: Vector3, needs_view: bool) -> float:
	var g := ground(p)
	var eye := threat + Vector3(0, 1.5, 0)
	var v_low := visibility(eye, g + Vector3(0, AIConfig.COVER_BODY_H, 0))
	var s := (1.0 - v_low) * AIConfig.COVER_HIDDEN_W
	if needs_view:
		var v_up := visibility(g + Vector3(0, AIConfig.COVER_PEEK_H, 0), eye)
		if v_up >= 0.2:
			s += AIConfig.COVER_VIEW_W
	return s


# ---------------------------------------------------------------- mesh
func build_mesh(pal: Dictionary, noise: FastNoiseLite) -> ArrayMesh:
	return build_mesh_region(pal, noise, 0, 0, n - 1, n - 1)


## Mesh of the quads ix0..ix1-1 / iz0..iz1-1 (vertex indices). The terrain is
## split into such chunks so a crater rebuilds only the chunk it hit.
func build_mesh_region(pal: Dictionary, noise: FastNoiseLite, ix0: int, iz0: int, ix1: int, iz1: int) -> ArrayMesh:
	var gcols: Array = pal["ground"]
	var slope_col: Color = pal["slope"]
	var w := ix1 - ix0 + 1
	var vc := PackedColorArray()
	vc.resize(w * (iz1 - iz0 + 1))
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var i := iz * n + ix
			var c: Color = gcols[gtype[i]]
			var nv := noise.get_noise_2d(ix * res * 4.0, iz * res * 4.0)
			if nv > 0.0:
				c = c.lightened(nv * 0.10)
			else:
				c = c.darkened(-nv * 0.14)
			vc[(iz - iz0) * w + (ix - ix0)] = c
	var tri_count := (ix1 - ix0) * (iz1 - iz0) * 2
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(tri_count * 3)
	norms.resize(tri_count * 3)
	cols.resize(tri_count * 3)
	var k := 0
	for iz in range(iz0, iz1):
		var z0 := -half + iz * res
		var z1 := z0 + res
		for ix in range(ix0, ix1):
			var x0 := -half + ix * res
			var x1 := x0 + res
			var i00 := iz * n + ix
			var i10 := i00 + 1
			var i01 := i00 + n
			var i11 := i01 + 1
			var l00 := (iz - iz0) * w + (ix - ix0)
			var l10 := l00 + 1
			var l01 := l00 + w
			var l11 := l01 + 1
			var p00 := Vector3(x0, heights[i00], z0)
			var p10 := Vector3(x1, heights[i10], z0)
			var p01 := Vector3(x0, heights[i01], z1)
			var p11 := Vector3(x1, heights[i11], z1)
			if (ix + iz) % 2 == 0:
				k = _tri(verts, norms, cols, k, p00, p10, p11, vc[l00], vc[l10], vc[l11], slope_col)
				k = _tri(verts, norms, cols, k, p00, p11, p01, vc[l00], vc[l11], vc[l01], slope_col)
			else:
				k = _tri(verts, norms, cols, k, p00, p10, p01, vc[l00], vc[l10], vc[l01], slope_col)
				k = _tri(verts, norms, cols, k, p10, p11, p01, vc[l10], vc[l11], vc[l01], slope_col)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _tri(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, k: int,
		a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, slope_col: Color) -> int:
	var nrm := (c - a).cross(b - a).normalized()
	var col := Color((ca.r + cb.r + cc.r) / 3.0, (ca.g + cb.g + cc.g) / 3.0, (ca.b + cb.b + cc.b) / 3.0)
	if nrm.y < 0.82:
		col = col.lerp(slope_col, clampf((0.82 - nrm.y) * 2.2, 0.0, 0.85))
	verts[k] = a
	verts[k + 1] = b
	verts[k + 2] = c
	norms[k] = nrm
	norms[k + 1] = nrm
	norms[k + 2] = nrm
	cols[k] = col
	cols[k + 1] = col
	cols[k + 2] = col
	return k + 3


## Earth "diorama" sides around the play area.
func build_skirt(depth: float, strata: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var edges := [
		[Vector2i(0, 0), Vector2i(1, 0), Vector3(0, 0, -1)],
		[Vector2i(n - 1, 0), Vector2i(0, 1), Vector3(1, 0, 0)],
		[Vector2i(n - 1, n - 1), Vector2i(-1, 0), Vector3(0, 0, 1)],
		[Vector2i(0, n - 1), Vector2i(0, -1), Vector3(-1, 0, 0)],
	]
	var bands: Array = [0.0, -0.5, -1.6, -2.4, -depth]
	for e in edges:
		var start: Vector2i = e[0]
		var stepv: Vector2i = e[1]
		var nrm: Vector3 = e[2]
		for s in n - 1:
			var ia := start + stepv * s
			var ib := start + stepv * (s + 1)
			var pa := Vector3(vx(ia.x), heights[ia.y * n + ia.x], vx(ia.y))
			var pb := Vector3(vx(ib.x), heights[ib.y * n + ib.x], vx(ib.y))
			for bi in bands.size() - 1:
				var ya0: float = pa.y if bi == 0 else bands[bi]
				var yb0: float = pb.y if bi == 0 else bands[bi]
				var y1: float = bands[bi + 1]
				var col: Color = strata[bi % strata.size()]
				var a0 := Vector3(pa.x, ya0, pa.z)
				var b0 := Vector3(pb.x, yb0, pb.z)
				var a1 := Vector3(pa.x, y1, pa.z)
				var b1 := Vector3(pb.x, y1, pb.z)
				for p in [a0, b0, b1, a0, b1, a1]:
					verts.append(p)
					norms.append(nrm)
					cols.append(col)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
