@tool
class_name Props
extends RefCounted
## Procedural low-poly prop builders. Each returns a Node3D positioned at the
## origin; the caller places it and registers tactical data in the grid.

const PLASTER := Color(0.70, 0.67, 0.60)
const BRICK := Color(0.55, 0.36, 0.28)
const ROOF := Color(0.42, 0.44, 0.45)
const WOOD := Color(0.36, 0.28, 0.20)
const LOG := Color(0.34, 0.27, 0.19)
const EARTH := Color(0.33, 0.27, 0.19)
const SANDBAG := Color(0.52, 0.48, 0.36)


## Ruined rural house. Returns {node, walls:[[a,b,h]...] (local), door_side}
static func ruined_house(sz: Vector2, ruin: float, rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	var wall_h := 2.7
	var th := 0.32
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	var m_wall := MF.mat(PLASTER.darkened(rng.randf() * 0.12))
	var m_brick := MF.mat(BRICK)
	var m_roof := MF.mat(ROOF)
	var m_wood := MF.mat(WOOD)
	var m_dark := MF.mat(Color(0.12, 0.11, 0.10))
	# plinth
	MF.part(root, MF.box(sz.x + 0.3, 0.35, sz.y + 0.3), MF.mat(Color(0.45, 0.43, 0.40)), Vector3(0, 0.0, 0))
	var walls: Array = []
	var windows: Array = []   # [centre (local x/z), outward normal]
	var doors: Array = []
	var sides := [
		[Vector2(-hx, hz), Vector2(hx, hz), true],     # south (+z) with door
		[Vector2(hx, hz), Vector2(hx, -hz), false],
		[Vector2(hx, -hz), Vector2(-hx, -hz), false],
		[Vector2(-hx, -hz), Vector2(-hx, hz), false],
	]
	for s in sides:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var L := a.distance_to(b)
		var dir := (b - a) / L
		var pieces := int(ceil(L / 1.0))
		var pl := L / pieces
		var door_i := pieces / 2 if s[2] else -1
		var win_i := [1, pieces - 2]
		var mid := (a + b) * 0.5
		var nrm := Vector2(-dir.y, dir.x)
		if nrm.dot(mid) < 0.0:
			nrm = -nrm
		for pi in pieces:
			var c := a + dir * (pl * (pi + 0.5))
			var h := wall_h
			if rng.randf() < ruin * 0.6:
				h = wall_h * rng.randf_range(0.25, 0.8)
			if pi == door_i:
				doors.append([c, nrm])
				walls.append([a + dir * pl * pi, a + dir * pl * (pi + 1), 0.0])
				MF.part(root, MF.box(pl, 0.3, th), m_wall, Vector3(c.x, wall_h - 0.15, c.y), Vector3(0, -atan2(dir.y, dir.x), 0))
				continue
			var yaw := -atan2(dir.y, dir.x)
			var sp: Array = []   # this wall piece's meshes (destructible as one)
			if pi in win_i and h > 1.6:
				windows.append([c, nrm])
				sp.append(MF.part(root, MF.box(pl, 0.95, th), m_wall, Vector3(c.x, 0.47, c.y), Vector3(0, yaw, 0)))
				sp.append(MF.part(root, MF.box(pl, h - 1.9, th), m_wall, Vector3(c.x, 1.9 + (h - 1.9) * 0.5, c.y), Vector3(0, yaw, 0)))
				sp.append(MF.part(root, MF.box(pl * 0.7, 0.9, 0.05), m_dark, Vector3(c.x, 1.4, c.y), Vector3(0, yaw, 0), Vector3.ONE, false))
			else:
				sp.append(MF.part(root, MF.box(pl, h, th), m_wall, Vector3(c.x, h * 0.5, c.y), Vector3(0, yaw, 0)))
				if h < wall_h * 0.9 and rng.randf() < 0.6:
					sp.append(MF.part(root, MF.box(pl * 0.6, 0.25, th + 0.02), m_brick, Vector3(c.x, h - 0.05, c.y), Vector3(0, yaw, rng.randf_range(-0.2, 0.2))))
			walls.append([a + dir * pl * pi, a + dir * pl * (pi + 1), h, sp])
	# roof: half intact, half collapsed
	var slope := 0.55
	var rl := hz / cos(slope) + 0.4
	var rx := sz.x + 0.6
	if ruin < 0.7:
		var r1 := MF.part(root, MF.box(rx * 0.55, 0.12, rl), m_roof, Vector3(-rx * 0.22, wall_h + sin(slope) * hz * 0.5, -hz * 0.5), Vector3(slope, 0, 0))
		r1.position.y += 0.05
		MF.part(root, MF.box(rx * 0.55, 0.12, rl), m_roof, Vector3(-rx * 0.22, wall_h + sin(slope) * hz * 0.5, hz * 0.5), Vector3(-slope, 0, 0))
		# collapsed part
		MF.part(root, MF.box(rx * 0.4, 0.12, rl), m_roof, Vector3(rx * 0.25, 1.2, 0.2), Vector3(0.25, 0.2, 0.55))
		# exposed rafters
		for i in 4:
			var x := rx * 0.08 + i * 0.9
			MF.part(root, MF.box(0.12, 0.12, rl * 1.6), m_wood, Vector3(x, wall_h + 0.4, 0), Vector3(rng.randf_range(-0.3, 0.3), 0, 0))
	# chimney
	MF.part(root, MF.box(0.6, 1.6, 0.6), m_brick, Vector3(-hx * 0.4, wall_h + 0.6, -hz * 0.2))
	# rubble
	for i in 14:
		var p := Vector3(rng.randf_range(-hx - 1.5, hx + 1.5), 0.15, rng.randf_range(-hz - 1.5, hz + 1.5))
		var s := rng.randf_range(0.2, 0.6)
		var col := PLASTER if rng.randf() < 0.6 else BRICK
		MF.part(root, MF.box(s * 1.4, s * 0.6, s), MF.mat(col.darkened(rng.randf() * 0.2)), p,
			Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5), Vector3.ONE, false)
	return {"node": root, "walls": walls, "windows": windows, "doors": doors, "roof": ruin < 0.7}


static func shed(sz: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	var m_wood := MF.mat(WOOD.lightened(0.05))
	var m_metal := MF.mat(Color(0.45, 0.42, 0.38), 0.6, 0.4)
	var m_rust := MF.mat(Color(0.48, 0.30, 0.20), 0.8, 0.2)
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	var walls: Array = []
	for c in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]:
		MF.part(root, MF.box(0.25, 2.6, 0.25), m_wood, Vector3(c.x, 1.3, c.y))
	# back + side planks
	walls.append([Vector2(-hx, -hz), Vector2(hx, -hz), 2.2, [MF.part(root, MF.box(sz.x, 2.2, 0.12), m_wood, Vector3(0, 1.1, -hz))], "plank"])
	walls.append([Vector2(hx, -hz), Vector2(hx, hz), 2.2, [MF.part(root, MF.box(0.12, 2.2, sz.y), m_wood, Vector3(hx, 1.1, 0))], "plank"])
	MF.part(root, MF.box(0.12, 1.0, sz.y * 0.6), m_wood, Vector3(-hx, 0.5, -hz * 0.4), Vector3(0, 0, 0.1))
	# corrugated roof, partly torn
	for i in 6:
		var x := -hx + (i + 0.5) * sz.x / 6.0
		if i == 4:
			continue
		MF.part(root, MF.box(sz.x / 6.0 - 0.04, 0.05, sz.y + 0.6), m_metal if i % 2 == 0 else m_rust,
			Vector3(x, 2.75 + (i % 2) * 0.03, 0), Vector3(0.12, 0, rng.randf_range(-0.05, 0.05)))
	MF.part(root, MF.box(sz.x / 6.0, 0.05, sz.y), m_rust, Vector3(hx - 1.8, 0.6, hz + 0.8), Vector3(0.9, 0.3, 0.2))
	# junk inside
	MF.part(root, MF.cyl(0.35, 0.35, 0.9, 8), m_rust, Vector3(-1.2, 0.45, -1.0))
	MF.part(root, MF.box(1.2, 0.6, 0.8), m_wood, Vector3(1.0, 0.3, -0.8))
	# open front and a half-open side are the ways in
	return {"node": root, "walls": walls, "windows": [], "doors": [[Vector2(0, hz), Vector2(0, 1)], [Vector2(-hx, 0), Vector2(-1, 0)]], "roof": true}


static func bunker(kind: String, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var m_log := MF.mat(LOG)
	var m_log2 := MF.mat(LOG.darkened(0.15))
	var m_earth := MF.mat(EARTH)
	var m_dark := MF.mat(Color(0.05, 0.05, 0.05))
	var w := 4.2 if kind == "mg" else 5.0
	var d := 3.4 if kind == "mg" else 4.4
	var h := 1.5 if kind == "mg" else 1.1
	var log_mesh := MF.cyl(0.17, 0.17, 1.0, 6)
	# log walls (stacked), front has an embrasure gap
	var rows := 4 if kind == "mg" else 3
	for r in rows:
		var y := 0.17 + r * 0.32
		var mm := m_log if r % 2 == 0 else m_log2
		# back
		MF.part(root, log_mesh, mm, Vector3(0, y, d * 0.5), Vector3(0, 0, PI / 2), Vector3(1, w, 1))
		# sides
		MF.part(root, log_mesh, mm, Vector3(-w * 0.5, y, 0), Vector3(PI / 2, 0, 0), Vector3(1, d, 1))
		MF.part(root, log_mesh, mm, Vector3(w * 0.5, y, 0), Vector3(PI / 2, 0, 0), Vector3(1, d, 1))
		# front (embrasure at row 2 for mg)
		if kind == "mg" and r == 2:
			MF.part(root, log_mesh, mm, Vector3(-w * 0.36, y, -d * 0.5), Vector3(0, 0, PI / 2), Vector3(1, w * 0.28, 1))
			MF.part(root, log_mesh, mm, Vector3(w * 0.36, y, -d * 0.5), Vector3(0, 0, PI / 2), Vector3(1, w * 0.28, 1))
			MF.part(root, MF.box(w * 0.45, 0.3, 0.3), m_dark, Vector3(0, y, -d * 0.5 + 0.1), Vector3.ZERO, Vector3.ONE, false)
		else:
			MF.part(root, log_mesh, mm, Vector3(0, y, -d * 0.5), Vector3(0, 0, PI / 2), Vector3(1, w, 1))
	# roof logs
	for i in int(w / 0.36):
		var x := -w * 0.5 + 0.18 + i * 0.36
		MF.part(root, log_mesh, m_log2 if i % 2 else m_log, Vector3(x, h + 0.2, 0), Vector3(PI / 2, 0, 0), Vector3(1, d + 0.6, 1))
	# earth mound on top
	var mound := MF.sphere(1.0, 2.0, 9, 4, true, 0.08, rng.randi())
	MF.part(root, mound, m_earth, Vector3(0, h + 0.3, 0.2), Vector3.ZERO, Vector3(w * 0.62, 0.7, d * 0.7))
	# grass / branches camouflage
	var m_g := MF.mat(Color(0.30, 0.34, 0.17))
	for i in 7:
		MF.part(root, MF.sphere(0.5, 0.6, 6, 3, false, 0.08, i), m_g,
			Vector3(rng.randf_range(-w * 0.45, w * 0.45), h + 0.75, rng.randf_range(-d * 0.35, d * 0.4)),
			Vector3(0, rng.randf() * TAU, 0), Vector3(rng.randf_range(0.8, 1.5), 0.5, rng.randf_range(0.8, 1.4)), false)
	if kind == "dugout":
		# entrance at the back with steps
		MF.part(root, MF.box(1.2, 1.3, 0.1), m_dark, Vector3(0, 0.6, d * 0.5 + 0.2), Vector3.ZERO, Vector3.ONE, false)
		for s in 3:
			MF.part(root, MF.box(1.2, 0.18, 0.4), m_log2, Vector3(0, 0.1 + s * 0.25, d * 0.5 + 0.6 + s * 0.4))
	return root


static func sandbags(length: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var bag := MF.box(0.62, 0.24, 0.34)
	var count := int(length / 0.6)
	for row in 3:
		for i in count - row:
			var x := -length * 0.5 + 0.3 + i * 0.6 + row * 0.3
			var col := SANDBAG.darkened(rng.randf() * 0.18)
			MF.part(root, bag, MF.mat(Color(snappedf(col.r, 0.03), snappedf(col.g, 0.03), snappedf(col.b, 0.03))), Vector3(x, 0.12 + row * 0.23, 0),
				Vector3(0, rng.randf_range(-0.08, 0.08), 0))
	return root


static func fence_segment(a: Vector3, b: Vector3, rng: RandomNumberGenerator, parent: Node3D) -> void:
	var m_wood := MF.mat(Color(0.40, 0.33, 0.24))
	var L := a.distance_to(b)
	var dir := (b - a) / L
	var yaw := atan2(-dir.x, -dir.z)
	var posts := int(L / 2.2) + 1
	for i in posts + 1:
		var p := a + dir * (L * i / posts)
		if rng.randf() < 0.15:
			continue
		MF.part(parent, MF.box(0.12, 1.3, 0.12), m_wood, p + Vector3(0, 0.6, 0), Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.15, 0.15)))
	for i in posts:
		if rng.randf() < 0.3:
			continue
		var p := a + dir * (L * (i + 0.5) / posts)
		for k in 2:
			MF.part(parent, MF.box(0.05, 0.12, L / posts), m_wood, p + Vector3(0, 0.45 + k * 0.5, 0), Vector3(0, yaw, rng.randf_range(-0.06, 0.06)), Vector3.ONE, false)


static func hay_bale(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	MF.part(root, MF.cyl(0.75, 0.75, 1.2, 10), MF.mat(Color(0.62, 0.55, 0.33).darkened(rng.randf() * 0.2)), Vector3(0, 0.72, 0), Vector3(0, 0, PI / 2))
	return root


static func pole(rng: RandomNumberGenerator, broken: bool) -> Node3D:
	var root := Node3D.new()
	var m := MF.mat(Color(0.36, 0.32, 0.27))
	var h := 3.0 if broken else 7.5
	var p := MF.part(root, MF.cyl(0.11, 0.14, h, 6), m, Vector3(0, h * 0.5, 0))
	if broken:
		p.rotation = Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(0.3, 0.6))
	else:
		MF.part(root, MF.box(1.6, 0.1, 0.1), m, Vector3(0, h - 0.5, 0))
	return root


## Concertina wire along a polyline, as a MultiMesh of tori + pickets.
static func wire(points: PackedVector2Array, grid: TerrainGrid, parent: Node3D) -> void:
	var coils: Array = []
	var pickets: Array = []
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var L := a.distance_to(b)
		var dir := (b - a) / L
		var k := 0.0
		while k < L:
			var p := a + dir * k
			var h := grid.height_at(p.x, p.y)
			var basis := Basis.looking_at(Vector3(dir.x, 0, dir.y), Vector3.UP) * Basis(Vector3.RIGHT, PI / 2)
			coils.append(Transform3D(basis, Vector3(p.x, h + 0.42, p.y)))
			if int(k / 0.45) % 6 == 0:
				pickets.append(Vector3(p.x, h, p.y))
			k += 0.45
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = MF.torus(0.36, 0.42, 10, 3)
	mm.instance_count = coils.size()
	for i in coils.size():
		mm.set_instance_transform(i, coils[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = MF.mat(Color(0.30, 0.29, 0.28), 0.5, 0.6)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	var m_post := MF.mat(Color(0.30, 0.27, 0.22))
	for p in pickets:
		MF.part(parent, MF.box(0.07, 1.1, 0.07), m_post, p + Vector3(0, 0.5, 0), Vector3(0, 0, 0.35))
		MF.part(parent, MF.box(0.07, 1.1, 0.07), m_post, p + Vector3(0, 0.5, 0), Vector3(0, 0, -0.35))


# ------------------------------------------------------------------ city
## Solid box into a SurfaceTool (vertex colour), axis aligned, centre c.
static func _stbox(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3(0, 0, 1), [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3(0, 0, -1), [Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3(1, 0, 0), [Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)]],
		[Vector3(-1, 0, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, 1, 0), [Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, -1, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var q: Array = f[1]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(c + q[k])


const PANEL := Color(0.64, 0.62, 0.57)
const FLOOR_H := 3.0


## Multi-storey apartment block (panel building): floors of 3 m, a window in
## every other 2 m bay on every floor, entrances (під'їзди) on the +Z side.
## Concrete walls are not breached. Returns node, walls (for the grid),
## windows [centre, outward normal, floor], doors, roof, floor_h.
static func apartment(sz: Vector2, floors: int, ruin: float, rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# weathered concrete: grey-brown, darker on a ruined (burnt) block
	var panel := PANEL.darkened(0.22 + rng.randf() * 0.15 + ruin * 0.3).lerp(Color(0.36, 0.33, 0.3), rng.randf() * 0.6)
	var dark := Color(0.07, 0.075, 0.08)
	var slab := Color(0.5, 0.5, 0.48)
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	var th := 0.3
	var walls: Array = []
	var windows: Array = []
	var doors: Array = []
	var top := floors * FLOOR_H
	var soot := Color(0.09, 0.085, 0.08)
	# whole floors burnt through: a black band along the building
	var burnt_floor := {}
	for f in floors:
		if rng.randf() < ruin * 0.45:
			burnt_floor[f] = true
	# collapsed sections: a few bays fallen in from some floor up to the roof
	var collapse: Array = []   # [side, first bay, last bay, from floor]
	if ruin > 0.3:
		for k in int(ruin * 3.0):
			collapse.append([rng.randi_range(0, 3) if k > 0 else 0, 0, 0, rng.randi_range(1, maxi(1, floors - 2))])
	var sides := [
		[Vector2(-hx, hz), Vector2(hx, hz), true],
		[Vector2(hx, hz), Vector2(hx, -hz), false],
		[Vector2(hx, -hz), Vector2(-hx, -hz), false],
		[Vector2(-hx, -hz), Vector2(-hx, hz), false],
	]
	for s in sides:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var L := a.distance_to(b)
		var dir := (b - a) / L
		var nrm := Vector2(-dir.y, dir.x)
		if nrm.dot((a + b) * 0.5) < 0.0:
			nrm = -nrm
		var bays := maxi(2, int(round(L / 2.0)))
		var bl := L / bays
		var side_i := sides.find(s)
		for cl in collapse:
			if cl[0] == side_i and cl[2] == 0:
				var w := rng.randi_range(2, 4)
				cl[1] = rng.randi_range(1, maxi(1, bays - w - 1))
				cl[2] = cl[1] + w
		var door_bays: Array = []
		if s[2]:
			door_bays = [bays / 3, bays * 2 / 3]
		for bi in bays:
			var c := a + dir * (bl * (bi + 0.5))
			var seg_a := a + dir * bl * bi
			var seg_b := a + dir * bl * (bi + 1)
			var along := absf(dir.x) > 0.5
			var size_of := func(w: float, h: float) -> Vector3:
				return Vector3(w if along else th, h, th if along else w)
			walls.append([seg_a, seg_b, 0.0 if bi in door_bays else top + 0.4])
			var burnt_from := floors + 1
			if bi % 2 == 1 and rng.randf() < ruin * 1.1:
				burnt_from = rng.randi_range(0, floors - 1)   # soot streaks up the facade from a burnt flat
			for f in floors:
				var y0 := f * FLOOR_H
				var fallen := false
				for cl in collapse:
					if cl[0] == side_i and bi >= cl[1] and bi <= cl[2] and f >= cl[3]:
						fallen = true
				if fallen:
					continue
				# the upper floors of a ruined block have holes
				if f > 0 and rng.randf() < ruin * 0.3 * float(f) / floors:
					continue
				var pc: Color = panel if f < burnt_from else panel.lerp(soot, clampf(0.6 + (f - burnt_from) * 0.12, 0.0, 0.9))
				if burnt_floor.has(f):
					pc = pc.lerp(soot, 0.75)
				if f == 0 and bi in door_bays:
					_stbox(st, Vector3(c.x, y0 + 2.6, c.y), size_of.call(bl, 0.8), pc)
					_stbox(st, Vector3(c.x - nrm.x * 0.6, y0 + 1.1, c.y - nrm.y * 0.6), size_of.call(bl * 0.8, 2.2), dark)
					if f == 0:
						doors.append([c, nrm])
					continue
				if bi % 2 == 1:
					_stbox(st, Vector3(c.x, y0 + 0.45, c.y), size_of.call(bl, 0.9), pc)
					_stbox(st, Vector3(c.x, y0 + 2.55, c.y), size_of.call(bl, 0.9), pc)
					_stbox(st, Vector3(c.x - nrm.x * 0.08, y0 + 1.5, c.y - nrm.y * 0.08), size_of.call(bl * 0.8, 1.2), dark)
					windows.append([c, nrm, f])
				else:
					_stbox(st, Vector3(c.x, y0 + FLOOR_H * 0.5, c.y), size_of.call(bl, FLOOR_H), pc)
	# floor slabs and the roof (partly fallen in on a ruined block)
	for f in range(1, floors + 1):
		var tiles := 4
		for k in tiles:
			if f == floors and rng.randf() < ruin * 0.5:
				continue
			if f > 2 and rng.randf() < ruin * 0.15:
				continue
			var x0 := -hx + sz.x * (k + 0.5) / tiles
			_stbox(st, Vector3(x0, f * FLOOR_H - 0.1, 0), Vector3(sz.x / tiles, 0.2, sz.y), slab)
	# parapet on the roof
	_stbox(st, Vector3(0, top + 0.3, hz), Vector3(sz.x, 0.6, 0.2), panel)
	_stbox(st, Vector3(0, top + 0.3, -hz), Vector3(sz.x, 0.6, 0.2), panel)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = MF.vcol(0.95)
	root.add_child(mi)
	# rubble at the foot of a ruined block
	for i in int(6 + ruin * 40):
		var p := Vector3(rng.randf_range(-hx - 2.5, hx + 2.5), 0.2, rng.randf_range(-hz - 2.5, hz + 2.5))
		if absf(p.x) < hx and absf(p.z) < hz:
			continue
		var sc := rng.randf_range(0.3, 0.9)
		MF.part(root, MF.box(sc * 1.6, sc * 0.6, sc), MF.mat(panel.darkened(rng.randf() * 0.3)), p, Vector3(rng.randf() * 0.4, rng.randf() * TAU, rng.randf() * 0.4), Vector3.ONE, false)
	return {"node": root, "walls": walls, "windows": windows, "doors": doors, "roof": true, "floor_h": FLOOR_H}


## Concrete road blocks / a junk barricade along a line (cover, stops vehicles).
static func blocks(pts: PackedVector2Array, kind: String, grid, rng: RandomNumberGenerator, parent: Node3D) -> Array:
	var cells: Array = []
	var conc := MF.mat(Color(0.66, 0.65, 0.62))
	var junk := [MF.mat(Color(0.32, 0.3, 0.28)), MF.mat(Color(0.45, 0.3, 0.2)), MF.mat(Color(0.25, 0.27, 0.22)), MF.mat(Color(0.12, 0.12, 0.12))]
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var L := a.distance_to(b)
		var dir := (b - a) / maxf(L, 0.01)
		var yaw := atan2(-dir.x, -dir.y)
		var t := 0.0
		while t <= L:
			var p := a + dir * t
			var g: Vector3 = grid.ground(Vector3(p.x, 0, p.y))
			if kind == "concrete":
				MF.part(parent, MF.box(0.6, 0.9, 1.5), conc, g + Vector3(0, 0.45, 0), Vector3(0, yaw + rng.randf_range(-0.08, 0.08), 0))
			else:
				for k in rng.randi_range(2, 4):
					var s := Vector3(rng.randf_range(0.5, 1.6), rng.randf_range(0.3, 0.9), rng.randf_range(0.4, 1.0))
					MF.part(parent, MF.box(s.x, s.y, s.z), junk[rng.randi() % junk.size()], g + Vector3(rng.randf_range(-0.6, 0.6), s.y * 0.5 + k * 0.15, rng.randf_range(-0.4, 0.4)),
						Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
			cells.append(p)
			t += 1.6
	return cells


## A burnt-out car.
static func car_wreck(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var body := MF.mat(Color(0.22, 0.17, 0.14).lerp(Color(0.35, 0.33, 0.3), rng.randf() * 0.5))
	var dark := MF.mat(Color(0.08, 0.08, 0.08))
	MF.part(root, MF.box(1.8, 0.7, 4.2), body, Vector3(0, 0.55, 0))
	MF.part(root, MF.box(1.6, 0.55, 2.0), body, Vector3(0, 1.15, -0.2))
	MF.part(root, MF.box(1.5, 0.45, 1.9), dark, Vector3(0, 1.16, -0.2), Vector3.ZERO, Vector3(1.04, 1, 1.02), false)
	for wx in [-0.8, 0.8]:
		for wz in [-1.3, 1.3]:
			MF.part(root, MF.cyl(0.32, 0.32, 0.25, 8), dark, Vector3(wx, 0.3, wz), Vector3(0, 0, PI / 2))
	root.rotation.z = rng.randf_range(-0.05, 0.05)
	return root
