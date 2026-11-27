@tool
class_name MapManager
extends Node3D
## Turns a MapDef into a playable diorama: terrain, vegetation, structures,
## lighting and the tactical grid used by AI and navigation.

var def: MapDef
var grid: TerrainGrid
var rng := RandomNumberGenerator.new()
var tdist := PackedFloat32Array()
var foliage_mat: ShaderMaterial
var sun: DirectionalLight3D
var environment: Environment
var bunker_nodes: Array = []
## destructible field fortifications (Battlefield): {kind, title, node, pos,
## size, hp, cov, cells: [[cell, prior_cov, own_obst]]}
var pieces: Array = []
var piece_static := {}        # cell -> cover before any piece touched it
var piece_static_obst := {}   # cell -> obstacle before any piece touched it
var piece_cells := {}         # cell -> [piece index]
var piece_static_inf := {}    # cell -> inf_solid before any piece touched it
var door_cells := {}           # cell -> true: a doorway, always walkable (_carve_doors)
## Buildings as sets of positions (fight in buildings):
## {id, kind, center, rot, size, roof, windows: [{post, out, dir, occupant, b}],
##  doors: [{out, in}], interior: [Vector3], cells: [int]}
var buildings: Array = []
var building_cell := {}       # cell -> building id
const G := TerrainGrid.G


## Editor preview (MapScene): the real ground, trenches, roads, craters,
## vegetation and line objects; no game systems (W is not running).
var preview := false


func build_preview(p_def: MapDef, with_light: bool) -> void:
	preview = true
	def = p_def
	rng.seed = def.seed
	grid = TerrainGrid.new()
	grid.setup(def.size, 0.8)
	var gcols: Array = (def.palette["ground"] as Array).duplicate()
	while gcols.size() <= TerrainGrid.G.SPOIL:
		gcols.append(def.palette.get("spoil", Color(0.52, 0.48, 0.33)))
	def.palette["ground"] = gcols
	foliage_mat = ShaderMaterial.new()
	foliage_mat.shader = load("res://shaders/foliage.gdshader")
	if with_light:
		_build_environment()
	_compute_heights()
	grid.trench_net = TrenchNet.new()
	grid.trench_net.build(def.trenches, grid)
	_compute_cells()
	_build_terrain_mesh()
	_build_trench_meshes()
	var root := Node3D.new()
	root.name = "Lines"
	add_child(root)
	_build_lines(root)
	_build_vegetation()


func build(p_def: MapDef) -> void:
	def = p_def
	rng.seed = def.seed
	grid = TerrainGrid.new()
	grid.setup(def.size, 0.8)
	if not preview:
		W.grid = grid
	# ground colour for trench spoil (G.SPOIL) comes from the map's palette
	var gcols: Array = (def.palette["ground"] as Array).duplicate()
	while gcols.size() <= TerrainGrid.G.SPOIL:
		gcols.append(def.palette.get("spoil", Color(0.52, 0.48, 0.33)))
	def.palette["ground"] = gcols
	foliage_mat = ShaderMaterial.new()
	foliage_mat.shader = load("res://shaders/foliage.gdshader")
	_build_environment()
	_compute_heights()
	grid.trench_net = TrenchNet.new()
	grid.trench_net.build(def.trenches, grid)
	_compute_cells()
	_build_terrain_mesh()
	_build_trench_meshes()
	_build_structures()
	_build_vegetation()
	_vehicle_mobility()
	grid.build_nav()
	apply_weather()


## Craters and steep ground per mobility profile (Db.MOBILITY): the tracked
## profile writes into veh_solid, the light one gets its own stricter copy.
func _vehicle_mobility() -> void:
	var tr: Dictionary = Db.MOBILITY["tracked"]
	var lt: Dictionary = Db.MOBILITY["light"]
	var light := grid.veh_solid.duplicate()
	var road := PackedByteArray()
	road.resize(grid.cn * grid.cn)
	for i in road.size():
		road[i] = 1 if grid.veh_weight[i] < 0.6 else 0
	for c in def.craters:
		var r: float = c.z
		if r < float(lt["crater"]):
			continue
		var cc := grid.cell_of(c.x, c.y)
		var span := int(ceil(r * 0.75 / TerrainGrid.CS))
		for dz in range(-span, span + 1):
			for dx in range(-span, span + 1):
				var k := Vector2i(cc.x + dx, cc.y + dz)
				if k.x < 0 or k.y < 0 or k.x >= grid.cn or k.y >= grid.cn:
					continue
				var ci := grid.ci(k)
				if road[ci] != 0:
					continue
				var w := grid.cell_center(k)
				if Vector2(w.x - c.x, w.z - c.y).length() > r * 0.75:
					continue
				light[ci] = 1
				if r >= float(tr["crater"]):
					grid.veh_solid[ci] = 1
				else:
					grid.veh_weight[ci] = maxf(grid.veh_weight[ci], 2.5)
	# slope: height difference across a cell
	for cz in range(1, grid.cn - 1):
		for cx in range(1, grid.cn - 1):
			var ci := cz * grid.cn + cx
			if road[ci] != 0:
				continue
			var c := grid.cell_center(Vector2i(cx, cz))
			var h := TerrainGrid.CS
			var sx := absf(grid.height_at(c.x + h, c.z) - grid.height_at(c.x - h, c.z)) / (2.0 * h)
			var sz := absf(grid.height_at(c.x, c.z + h) - grid.height_at(c.x, c.z - h)) / (2.0 * h)
			var sl := maxf(sx, sz)
			if sl > float(lt["max_slope"]):
				light[ci] = 1
			if sl > float(tr["max_slope"]):
				grid.veh_solid[ci] = 1
	for i in light.size():
		if grid.veh_solid[i] != 0:
			light[i] = 1
	grid.veh_solid_light = light


var weather_base := {}
var terrain_mat: StandardMaterial3D
var grass_mat: ShaderMaterial
var rain = null


func apply_weather() -> void:
	WeatherFx.apply(self)


# ------------------------------------------------------------------ helpers
static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var L2 := ab.length_squared()
	if L2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / L2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func poly_dist(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, seg_dist(p, pts[i], pts[i + 1]))
	return best


func _vrange(r: Rect2) -> Array:
	var ix0 := clampi(int(floor((r.position.x + grid.half) / grid.res)), 0, grid.n - 1)
	var ix1 := clampi(int(ceil((r.end.x + grid.half) / grid.res)), 0, grid.n - 1)
	var iz0 := clampi(int(floor((r.position.y + grid.half) / grid.res)), 0, grid.n - 1)
	var iz1 := clampi(int(ceil((r.end.y + grid.half) / grid.res)), 0, grid.n - 1)
	return [ix0, ix1, iz0, iz1]


func _seg_rect(a: Vector2, b: Vector2, pad: float) -> Rect2:
	var r := Rect2(a, Vector2.ZERO).expand(b)
	return r.grow(pad)


# ------------------------------------------------------------------ environment
func _build_environment() -> void:
	var pal := def.palette
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = pal["sky_top"]
	psm.sky_horizon_color = pal["sky_horizon"]
	psm.ground_horizon_color = pal["sky_horizon"]
	psm.ground_bottom_color = Color(0.22, 0.23, 0.22)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = pal["ambient"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.8
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = pal["fog"]
	env.fog_density = pal["fog_density"]
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.07
	we.environment = env
	environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = pal["sun_rot"]
	sun.light_color = pal["sun"]
	sun.light_energy = pal["sun_energy"]
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 240.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.2
	add_child(sun)


# ------------------------------------------------------------------ heights
func _compute_heights() -> void:
	var n := grid.n
	var noises := MapHeights.make_noises(def.seed)
	var micro: FastNoiseLite = noises[1]
	var patch := FastNoiseLite.new()
	patch.seed = def.seed + 3
	patch.frequency = 0.035
	for iz in n:
		var z := grid.vx(iz)
		for ix in n:
			var x := grid.vx(ix)
			var i := iz * n + ix
			grid.heights[i] = def.ground_height(x, z, noises)
			var pv := patch.get_noise_2d(x, z)
			var g := G.GRASS
			if pv > 0.22:
				g = G.DRY
			elif pv < -0.48:
				g = G.MUD
			grid.gtype[i] = g
	# forest floor
	for tl in def.treelines:
		var r: Rect2 = tl["rect"]
		var vr := _vrange(r.grow(2.0))
		for iz in range(vr[2], vr[3] + 1):
			for ix in range(vr[0], vr[1] + 1):
				var p := Vector2(grid.vx(ix), grid.vx(iz))
				var edge := patch.get_noise_2d(p.x * 3.0, p.y * 3.0) * 1.8
				if r.grow(edge).has_point(p):
					grid.gtype[iz * n + ix] = G.FOREST
	# yards around houses
	for h in def.houses:
		var hp: Vector2 = h["pos"]
		var vr := _vrange(Rect2(hp - Vector2(9, 9), Vector2(18, 18)))
		for iz in range(vr[2], vr[3] + 1):
			for ix in range(vr[0], vr[1] + 1):
				var p := Vector2(grid.vx(ix), grid.vx(iz))
				if p.distance_to(hp) < 8.0 + patch.get_noise_2d(p.x * 4, p.y * 4) * 2.0:
					grid.gtype[iz * n + ix] = G.YARD
	for b in def.burnt:
		var c := Vector2(b.x, b.y)
		var vr := _vrange(Rect2(c - Vector2(b.z, b.z), Vector2(b.z, b.z) * 2))
		for iz in range(vr[2], vr[3] + 1):
			for ix in range(vr[0], vr[1] + 1):
				var p := Vector2(grid.vx(ix), grid.vx(iz))
				if p.distance_to(c) < b.z * (0.7 + micro.get_noise_2d(p.x * 5, p.y * 5) * 0.4):
					grid.gtype[iz * n + ix] = G.BURNT
	for road in def.roads:
		_stamp_road(road["pts"], road["w"])
	for c in def.craters:
		_stamp_crater(c)
	for b in def.bunkers:
		var bp: Vector2 = b["pos"]
		var vr := _vrange(Rect2(bp - Vector2(4, 4), Vector2(8, 8)))
		for iz in range(vr[2], vr[3] + 1):
			for ix in range(vr[0], vr[1] + 1):
				var d := Vector2(grid.vx(ix), grid.vx(iz)).distance_to(bp)
				if d < 3.2:
					grid.heights[iz * n + ix] -= 0.55 * (1.0 - d / 3.2)
					grid.gtype[iz * n + ix] = G.DIRT
	_stamp_trenches()


func _stamp_road(pts: PackedVector2Array, w: float) -> void:
	var n := grid.n
	var hw := w * 0.5
	var done := {}
	for s in pts.size() - 1:
		var a := pts[s]
		var b := pts[s + 1]
		var vr := _vrange(_seg_rect(a, b, hw + 1.0))
		for iz in range(vr[2], vr[3] + 1):
			for ix in range(vr[0], vr[1] + 1):
				var i := iz * n + ix
				if done.has(i):
					continue
				var p := Vector2(grid.vx(ix), grid.vx(iz))
				var d := poly_dist(p, pts)
				if d < hw + 0.8:
					done[i] = true
					grid.heights[i] -= 0.08 * (1.0 - d / (hw + 0.8))
					if d < hw:
						grid.gtype[i] = G.ROAD
						if absf(d - hw * 0.45) < 0.3:
							grid.heights[i] -= 0.05


func _stamp_crater(c: Vector3) -> void:
	var n := grid.n
	var cp := Vector2(c.x, c.y)
	var r := c.z
	var vr := _vrange(Rect2(cp - Vector2(r, r) * 1.6, Vector2(r, r) * 3.2))
	for iz in range(vr[2], vr[3] + 1):
		for ix in range(vr[0], vr[1] + 1):
			var i := iz * n + ix
			var d := Vector2(grid.vx(ix), grid.vx(iz)).distance_to(cp)
			if d < r:
				var k := d / r
				grid.heights[i] -= r * 0.36 * (1.0 - k * k)
				grid.gtype[i] = G.CRATER if k < 0.8 else G.DIRT
			elif d < r * 1.55:
				grid.heights[i] += r * 0.08 * sin((d - r) / (r * 0.55) * PI)
				if rng.randf() < 0.6:
					grid.gtype[i] = G.DIRT


func _stamp_trenches() -> void:
	var n := grid.n
	grid.nat = grid.heights.duplicate()
	grid.add_trench_lines(def.trenches)
	tdist.resize(n * n)
	tdist.fill(99.0)
	for pts in def.trenches:
		for k in pts.size() - 1:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var vr := _vrange(_seg_rect(a, b, BERM_W + TerrainGrid.T_FOOT + 0.5))
			for iz in range(vr[2], vr[3] + 1):
				for ix in range(vr[0], vr[1] + 1):
					var i := iz * n + ix
					var d := seg_dist(Vector2(grid.vx(ix), grid.vx(iz)), a, b)
					if d < tdist[i]:
						tdist[i] = d
	var cap := TerrainGrid.T_CAP
	var foot := TerrainGrid.T_FOOT
	var depth := TerrainGrid.T_DEPTH
	var bnoise := FastNoiseLite.new()
	bnoise.seed = def.seed + 31
	bnoise.frequency = 0.25
	for i in n * n:
		var d := tdist[i]
		if d >= foot + BERM_W:
			continue
		if d >= foot:
			# spoil berm (бруствер): the dug earth lies in a wide low bank on both
			# sides — this is what makes a position readable from the air
			var x := grid.vx(i % n)
			var z := grid.vx(i / n)
			var nv := bnoise.get_noise_2d(x, z)
			var k := (d - foot) / BERM_W
			grid.heights[i] = maxf(grid.heights[i], grid.nat[i] + BERM_H * (1.0 - k * k) * (0.8 + nv * 0.4))
			if k < 0.75 + nv * 0.35:
				grid.gtype[i] = G.SPOIL
			continue
		if d < cap:
			grid.heights[i] = grid.nat[i] - depth
		else:
			grid.heights[i] = grid.nat[i] - depth * (1.0 - (d - cap) / (foot - cap))
		grid.gtype[i] = G.TRENCH if d < TerrainGrid.T_WALL + 0.2 else G.DIRT


const BERM_W := 2.2     # width of the spoil bank beyond the trench lip, m
const BERM_H := 0.34    # its height at the lip (matches the parapet)


# ------------------------------------------------------------------ dug trench geometry
var _tv := PackedVector3Array()
var _tn := PackedVector3Array()
var _tc := PackedColorArray()


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, face: Vector3) -> void:
	var nrm := (c - a).cross(b - a)
	if nrm.length_squared() < 0.000001:
		return
	nrm = nrm.normalized()
	if face != Vector3.ZERO and nrm.dot(face) < 0.0:
		nrm = -nrm
	for v in [a, b, c, a, c, d]:
		_tv.append(v)
		_tn.append(nrm)
		_tc.append(col)


func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var m := maxi(1, int(ceil(a.distance_to(b) / step)))
		for j in m:
			out.append(a.lerp(b, float(j) / m))
	out.append(pts[pts.size() - 1])
	return out


func _build_trench_meshes() -> void:
	_tv.clear()
	_tn.clear()
	_tc.clear()
	var tw := TerrainGrid.T_WALL
	var cap := TerrainGrid.T_CAP
	var foot := TerrainGrid.T_FOOT
	var depth := TerrainGrid.T_DEPTH
	var par := TerrainGrid.T_PARAPET
	var boards := [Color(0.42, 0.32, 0.21), Color(0.36, 0.27, 0.18), Color(0.45, 0.35, 0.23), Color(0.33, 0.25, 0.17)]
	var spoil: Color = def.palette.get("spoil", Color(0.52, 0.48, 0.33))
	var c_cap := spoil.darkened(0.08)
	var c_slope := spoil.darkened(0.03)
	var c_floor := Color(0.21, 0.17, 0.13)
	var posts: Array = []
	var slats: Array = []
	var steps: Array = []
	for li in def.trenches.size():
		var pts := _resample(def.trenches[li], 0.7)
		var cnt := pts.size()
		if cnt < 2:
			continue
		var nrm: Array = []
		var scl: Array = []
		var tan: Array = []
		for i in cnt:
			var t_prev: Vector2 = (pts[i] - pts[i - 1]).normalized() if i > 0 else (pts[1] - pts[0]).normalized()
			var t_next: Vector2 = (pts[i + 1] - pts[i]).normalized() if i < cnt - 1 else t_prev
			var t := (t_prev + t_next).normalized()
			if t.length_squared() < 0.01:
				t = t_next
			var nn := Vector2(-t.y, t.x)
			var np := Vector2(-t_prev.y, t_prev.x)
			tan.append(t)
			nrm.append(nn)
			scl.append(1.0 / maxf(0.55, nn.dot(np)))
		# which centre points sit inside another trench (junction openings)
		# junctions: a wall is left out only on the side where another trench
		# opens into this one (a spur on the left must not cut the right wall)
		var open_pt: Array = []
		var open_side := {-1.0: [], 1.0: []}
		for i in cnt:
			open_pt.append(grid.trench_closest(pts[i].x, pts[i].y, li).z < tw - 0.05)
			for sd in [-1.0, 1.0]:
				var q: Vector2 = pts[i] + (nrm[i] as Vector2) * sd * (tw + 0.3)
				open_side[sd].append(grid.trench_closest(q.x, q.y, li).z < tw + 0.1)
		var line_len := 0.0
		for i in cnt - 1:
			line_len += pts[i].distance_to(pts[i + 1])
		var short_line := line_len < 6.0
		var floor_h: Array = []
		for i in cnt:
			floor_h.append(grid.nat_at(pts[i].x, pts[i].y) - depth)
		# floor + duckboards
		for i in cnt - 1:
			var pa: Vector2 = pts[i]
			var pb: Vector2 = pts[i + 1]
			var na: Vector2 = nrm[i] * tw * float(scl[i])
			var nb: Vector2 = nrm[i + 1] * tw * float(scl[i + 1])
			_quad(Vector3(pa.x - na.x, floor_h[i], pa.y - na.y), Vector3(pb.x - nb.x, floor_h[i + 1], pb.y - nb.y),
				Vector3(pb.x + nb.x, floor_h[i + 1], pb.y + nb.y), Vector3(pa.x + na.x, floor_h[i], pa.y + na.y), c_floor, Vector3.UP)
		var acc := 0.0
		for i in cnt - 1:
			var seg := pts[i].distance_to(pts[i + 1])
			var k := 0.0
			while k < seg:
				if fmod(acc + k, 0.45) < 0.01 or k == 0.0:
					var pp: Vector2 = pts[i].lerp(pts[i + 1], k / seg)
					var t2: Vector2 = tan[i]
					var yaw := atan2(-t2.x, -t2.y)
					slats.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(pp.x, lerpf(floor_h[i], floor_h[i + 1], k / seg) + 0.05, pp.y)))
				k += 0.45
			acc += seg
		# walls, parapet caps, outer slopes, posts, firing steps
		for side in [-1.0, 1.0]:
			var since_post := 0.0
			var since_step := 2.0
			for i in cnt - 1:
				if open_side[side][i] or open_side[side][i + 1]:
					continue
				var pa: Vector2 = pts[i]
				var pb: Vector2 = pts[i + 1]
				var na: Vector2 = nrm[i] * side * float(scl[i])
				var nb: Vector2 = nrm[i + 1] * side * float(scl[i + 1])
				var wa := pa + na * tw
				var wb := pb + nb * tw
				var ca := pa + na * cap
				var cb := pb + nb * cap
				var fa := pa + na * foot
				var fb := pb + nb * foot
				var top_a := grid.nat_at(wa.x, wa.y) + par
				var top_b := grid.nat_at(wb.x, wb.y) + par
				var inward := Vector3(-na.x, 0, -na.y)
				# revetment boards (horizontal bands)
				var lv := [0.0, 0.55, 1.1, 1.6]
				for bi in 4:
					var y0a: float = floor_h[i] + lv[bi]
					var y0b: float = floor_h[i + 1] + lv[bi]
					var y1a: float = top_a if bi == 3 else floor_h[i] + lv[bi + 1]
					var y1b: float = top_b if bi == 3 else floor_h[i + 1] + lv[bi + 1]
					var col: Color = boards[(bi + i / 3) % boards.size()]
					_quad(Vector3(wa.x, y0a, wa.y), Vector3(wb.x, y0b, wb.y), Vector3(wb.x, y1b, wb.y), Vector3(wa.x, y1a, wa.y), col, inward)
				var cvar := c_cap.darkened(0.06 * float(i % 3))
				# short spurs (firing cells, connectors) leave their parapet to the
				# trench they branch from where the two overlap — no doubled slabs
				if short_line and (grid.trench_closest(ca.x, ca.y, li).z < cap or grid.trench_closest(cb.x, cb.y, li).z < cap):
					continue
				_quad(Vector3(wa.x, top_a, wa.y), Vector3(wb.x, top_b, wb.y), Vector3(cb.x, grid.nat_at(cb.x, cb.y) + par, cb.y),
					Vector3(ca.x, grid.nat_at(ca.x, ca.y) + par, ca.y), cvar, Vector3.UP)
				_quad(Vector3(ca.x, grid.nat_at(ca.x, ca.y) + par, ca.y), Vector3(cb.x, grid.nat_at(cb.x, cb.y) + par, cb.y),
					Vector3(fb.x, grid.height_at(fb.x, fb.y) + 0.02, fb.y), Vector3(fa.x, grid.height_at(fa.x, fa.y) + 0.02, fa.y), c_slope, Vector3.UP)
				var seg := pa.distance_to(pb)
				since_post += seg
				if since_post >= 1.4:
					since_post = 0.0
					var pp := wa - na.normalized() * 0.05
					posts.append(Transform3D(Basis.from_scale(Vector3(1, depth + par + 0.15, 1)), Vector3(pp.x, floor_h[i] + (depth + par + 0.15) * 0.5, pp.y)))
				# firing steps on the side facing the attacker (south, +z)
				since_step += seg
				if na.y > 0.3 and since_step >= 4.5:
					since_step = 0.0
					var sp := pa + na.normalized() * (tw - 0.22)
					var t3: Vector2 = tan[i]
					steps.append(Transform3D(Basis(Vector3.UP, atan2(-t3.x, -t3.y)), Vector3(sp.x, floor_h[i] + 0.3, sp.y)))
		# end walls where a trench stops in the open
		for e in [0, cnt - 1]:
			if open_pt[e]:
				continue
			var pe: Vector2 = pts[e]
			var nn2: Vector2 = nrm[e] * float(scl[e])
			var t4: Vector2 = tan[e] * (1.0 if e == cnt - 1 else -1.0)
			var l := pe + nn2 * tw
			var r := pe - nn2 * tw
			var top := grid.nat_at(pe.x, pe.y) + par
			_quad(Vector3(l.x, floor_h[e], l.y), Vector3(r.x, floor_h[e], r.y), Vector3(r.x, top, r.y), Vector3(l.x, top, l.y), boards[1], Vector3(-t4.x, 0, -t4.y))
			var l2 := pe + nn2 * cap
			var r2 := pe - nn2 * cap
			var ext := t4 * cap
			_quad(Vector3(l2.x, top, l2.y), Vector3(r2.x, top, r2.y), Vector3(r2.x + ext.x, top, r2.y + ext.y), Vector3(l2.x + ext.x, top, l2.y + ext.y), c_cap, Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _tv
	arrays[Mesh.ARRAY_NORMAL] = _tn
	arrays[Mesh.ARRAY_COLOR] = _tc
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mat := MF.vcol(0.95).duplicate()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.name = "Trenches"
	add_child(mi)
	var white: Array = []
	for i in posts.size():
		white.append(Color(0.30, 0.23, 0.16))
	_mm(MF.box(0.1, 1.0, 0.1), posts, white, MF.vcol(0.95))
	var sc: Array = []
	for i in slats.size():
		sc.append(Color(0.40, 0.31, 0.20).darkened(randf() * 0.15))
	_mm(MF.box(1.08, 0.05, 0.2), slats, sc, MF.vcol(0.95), false)
	var stc: Array = []
	for i in steps.size():
		stc.append(Color(0.50, 0.45, 0.33))
	_mm(MF.box(1.1, 0.6, 0.42), steps, stc, MF.vcol(0.95))


# ------------------------------------------------------------------ tactical cells
func _compute_cells() -> void:
	var cn := grid.cn
	var n := grid.n
	var fnoise := FastNoiseLite.new()
	fnoise.seed = def.seed + 11
	fnoise.frequency = 0.15
	for cz in cn:
		for cx in cn:
			var i := cz * cn + cx
			var x := -grid.half + (cx + 0.5) * TerrainGrid.CS
			var z := -grid.half + (cz + 0.5) * TerrainGrid.CS
			var p := Vector2(x, z)
			var vi := clampi(int(round((z + grid.half) / grid.res)), 0, n - 1) * n + clampi(int(round((x + grid.half) / grid.res)), 0, n - 1)
			var cov := 0.0
			# edge of play area
			if absf(x) > grid.half - 3.0 or absf(z) > grid.half - 3.0:
				grid.veh_solid[i] = 1
			# trench
			var td: float = grid.trench_d(x, z)
			if td < TerrainGrid.T_FOOT + 1.6:
				grid.trench_near[i] = 1
			if td < 1.0:
				grid.trench[i] = 1
				cov = 0.72
				grid.inf_weight[i] = 0.85
				grid.veh_weight[i] = 6.0
			elif td < TerrainGrid.T_FOOT + BERM_W:
				cov = 0.22
				grid.veh_weight[i] = 2.0
				grid.inf_weight[i] = 1.6
			# a trench with its parapet is an obstacle for every vehicle (a road
			# through the position below re-opens a crossing)
			if td < TerrainGrid.T_FOOT + 0.6:
				grid.veh_solid[i] = 1
			# vegetation
			for tl in def.treelines:
				var r: Rect2 = tl["rect"]
				if r.has_point(p):
					if tl.has("vis"):
						grid.foliage[i] = clampf(float(tl["vis"]) * (0.8 + fnoise.get_noise_2d(x, z) * 0.35), 0.08, 1.0)
					else:
						grid.foliage[i] = clampf(float(tl["density"]) * (0.8 + fnoise.get_noise_2d(x, z) * 0.35), 0.2, 1.0)
					cov = maxf(cov, 0.28)
					grid.veh_solid[i] = 1
			for bsh in def.bushes:
				if p.distance_to(Vector2(bsh.x, bsh.y)) < bsh.z + 1.0:
					grid.foliage[i] = maxf(grid.foliage[i], 0.6)
					cov = maxf(cov, 0.12)
			for c in def.craters:
				var d := p.distance_to(Vector2(c.x, c.y))
				if d < c.z * 0.9:
					cov = maxf(cov, 0.42 if c.z > 1.6 else 0.3)
			# roads (vehicles prefer them, also clear tree cells)
			for road in def.roads:
				var d := poly_dist(p, road["pts"])
				if d < float(road["w"]) * 0.5 + 0.6:
					grid.veh_solid[i] = 1 if absf(x) > grid.half - 1.0 or absf(z) > grid.half - 1.0 else 0
					grid.veh_weight[i] = 0.55
					grid.foliage[i] = 0.0
			for wl in def.wire:
				if poly_dist(p, wl) < 1.3:
					grid.inf_weight[i] = 5.0
					cov = minf(cov, 0.05)
			for cm in def.camo:
				if p.distance_to(Vector2(cm.x, cm.y)) < cm.z:
					grid.camo[i] = 1
			grid.cover[i] = cov


func _set_cell(x: float, z: float, cov: float = -1.0, obst: float = -1.0, inf_block: int = -1, veh_block: int = -1) -> void:
	if not grid.in_bounds(x, z):
		return
	var i := grid.cidx(x, z)
	if cov >= 0.0:
		grid.cover[i] = maxf(grid.cover[i], cov)
	if obst >= 0.0:
		grid.obstacle[i] = maxf(grid.obstacle[i], obst)
	if inf_block >= 0:
		grid.inf_solid[i] = inf_block
	if veh_block >= 0:
		grid.veh_solid[i] = veh_block


## A destructible piece of cover: stamps its cells (like _area_cells) and
## remembers what they were before, so damage can lower them again.
## radius 0 = only the cell under `center`; obst goes on the centre cell.
func _reg_piece(kind: String, title: String, node: Node3D, center: Vector2, radius: float, cov: float, obst: float = -1.0) -> void:
	var idx := pieces.size()
	var cells: Array = []
	var ccell := grid.cidx(center.x, center.y)
	var list: Array = [ccell]
	if radius > 0.0:
		var r := int(ceil(radius / TerrainGrid.CS))
		var c0 := grid.cell_of(center.x, center.y)
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cc := Vector2i(c0.x + dx, c0.y + dz)
				if cc.x < 0 or cc.y < 0 or cc.x >= grid.cn or cc.y >= grid.cn:
					continue
				var w := grid.cell_center(cc)
				var i := grid.ci(cc)
				if Vector2(w.x, w.z).distance_to(center) <= radius and i != ccell:
					list.append(i)
	for i in list:
		_snap_static(i)
		piece_cells.get_or_add(i, []).append(idx)
		var ob: float = obst if (i == ccell and obst > 0.0) else 0.0
		cells.append([i, grid.cover[i], ob, false])
		grid.cover[i] = maxf(grid.cover[i], cov)
		if ob > 0.0:
			grid.obstacle[i] = maxf(grid.obstacle[i], ob)
	pieces.append({"kind": kind, "title": title, "node": node, "pos": grid.ground(Vector3(center.x, 0, center.y)),
		"size": maxf(radius * 0.6, 0.8), "hp": float(AIConfig.COVER_HP[kind]), "cov": cov, "cells": cells})


## The building whose footprint contains p, or null.
func building_at(p: Vector3):
	if grid == null:
		return null
	var id = building_cell.get(grid.cidx(p.x, p.z), -1)
	return buildings[id] if id >= 0 else null


func _reg_building(res: Dictionary, center: Vector3, basis: Basis, rot: float, sz: Vector2) -> void:
	var id := buildings.size()
	var fh: float = float(res.get("floor_h", 0.0))
	var kind := "shed" if res.get("windows", []).is_empty() else ("block" if fh > 0.0 else "house")
	var b := {"id": id, "kind": kind, "center": grid.ground(center), "rot": rot,
		"size": sz, "roof": res.get("roof", true), "windows": [], "doors": [], "interior": [], "cells": [], "floors": 1}
	for w in res.get("windows", []):
		var c: Vector2 = w[0]
		var n: Vector2 = w[1]
		var fl: int = int(w[2]) if w.size() > 2 else 0
		b["floors"] = maxi(b["floors"], fl + 1)
		var lift := Vector3(0, fl * fh, 0)
		var post := center + basis * Vector3(c.x - n.x * 0.6, 0, c.y - n.y * 0.6)
		var at := center + basis * Vector3(c.x, 0, c.y)
		# "in": where a man walks to before taking the post — a step further
		# inside. The post itself sits in the wall's nav cell; walking straight
		# at it, the path could end in the nearest free cell OUTSIDE the wall.
		var inside := center + basis * Vector3(c.x - n.x * 1.7, 0, c.y - n.y * 1.7)
		b["windows"].append({"post": grid.ground(post) + lift, "out": grid.ground(at) + lift, "in": grid.ground(inside), "dir": basis * Vector3(n.x, 0, n.y),
			"occupant": null, "b": id, "floor": fl})
		grid.win_cell[grid.cidx(at.x, at.z)] = 1
	for d in res.get("doors", []):
		var c: Vector2 = d[0]
		var n: Vector2 = d[1]
		b["doors"].append({"out": grid.ground(center + basis * Vector3(c.x + n.x * 2.0, 0, c.y + n.y * 2.0)),
			"in": grid.ground(center + basis * Vector3(c.x - n.x * 1.2, 0, c.y - n.y * 1.2))})
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	var lx := -hx + 1.4
	while lx <= hx - 1.4 + 0.01:
		var lz := -hz + 1.4
		while lz <= hz - 1.4 + 0.01:
			b["interior"].append(grid.ground(center + basis * Vector3(lx, 0, lz)))
			lz += 2.2
		lx += 2.2
	if b["interior"].is_empty():
		b["interior"].append(grid.ground(center))
	var gx := -hx
	while gx <= hx + 0.01:
		var gz := -hz
		while gz <= hz + 0.01:
			var w := center + basis * Vector3(gx, 0, gz)
			if grid.in_bounds(w.x, w.z):
				var i := grid.cidx(w.x, w.z)
				if not building_cell.has(i):
					building_cell[i] = id
					b["cells"].append(i)
			gz += 1.0
		gx += 1.0
	buildings.append(b)


func _snap_static(i: int) -> void:
	if not piece_static.has(i):
		piece_static[i] = grid.cover[i]
		piece_static_obst[i] = grid.obstacle[i]
		piece_static_inf[i] = grid.inf_solid[i]


## One wall segment of a building as a destructible piece: its cells block
## infantry while it stands (h > 1.2) and open up when it is breached.
func _reg_wall(parts: Array, a: Vector3, b: Vector3, h: float, plank: bool) -> void:
	var idx := pieces.size()
	var cells: Array = []
	var seen := {}
	var L := a.distance_to(b)
	var k := 0.0
	while k <= L:
		var w := a.lerp(b, k / maxf(L, 0.001))
		if grid.in_bounds(w.x, w.z):
			var i := grid.cidx(w.x, w.z)
			if not seen.has(i):
				seen[i] = true
				_snap_static(i)
				piece_cells.get_or_add(i, []).append(idx)
				cells.append([i, grid.cover[i], h, h > 1.2])
		k += 0.5
	pieces.append({"kind": "wall", "title": Loc.t("стіна"), "node": null, "parts": parts, "pos": grid.ground((a + b) * 0.5),
		"size": maxf(L * 0.5 - 0.3, 0.3), "hp": float(AIConfig.COVER_HP["plank" if plank else "wall"]), "cov": 0.5, "cells": cells})


func _area_cells(center: Vector2, radius: float, cov: float, veh_block: int = -1) -> void:
	var r := int(ceil(radius / TerrainGrid.CS))
	var c0 := grid.cell_of(center.x, center.y)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cc := Vector2i(c0.x + dx, c0.y + dz)
			if cc.x < 0 or cc.y < 0 or cc.x >= grid.cn or cc.y >= grid.cn:
				continue
			var w := grid.cell_center(cc)
			if Vector2(w.x, w.z).distance_to(center) <= radius:
				_set_cell(w.x, w.z, cov, -1.0, -1, veh_block)


# ------------------------------------------------------------------ meshes
const TCHUNK := 32                 # terrain chunk size in height-field quads
var terrain_chunks := {}           # Vector2i -> MeshInstance3D
var terrain_noise: FastNoiseLite


## Rebuilds the terrain chunks covering the vertex range (after a crater).
func rebuild_terrain(ix0: int, iz0: int, ix1: int, iz1: int) -> void:
	var nq := grid.n - 1
	for cz in range(maxi(0, iz0 - 1) / TCHUNK, mini(nq - 1, iz1) / TCHUNK + 1):
		for cx in range(maxi(0, ix0 - 1) / TCHUNK, mini(nq - 1, ix1) / TCHUNK + 1):
			var mi: MeshInstance3D = terrain_chunks.get(Vector2i(cx, cz))
			if mi:
				mi.mesh = grid.build_mesh_region(def.palette, terrain_noise, cx * TCHUNK, cz * TCHUNK,
					mini(cx * TCHUNK + TCHUNK, nq), mini(cz * TCHUNK + TCHUNK, nq))


func _build_terrain_mesh() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = def.seed + 99
	noise.frequency = 0.08
	var m := MF.vcol(0.97)
	m = m.duplicate()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	terrain_mat = m
	terrain_noise = noise
	var root := Node3D.new()
	root.name = "Terrain"
	add_child(root)
	# chunks of TCHUNK quads: a crater rebuilds only the chunk(s) it touches
	var nq := grid.n - 1
	for cz in range(0, nq, TCHUNK):
		for cx in range(0, nq, TCHUNK):
			var mi := MeshInstance3D.new()
			mi.mesh = grid.build_mesh_region(def.palette, noise, cx, cz, mini(cx + TCHUNK, nq), mini(cz + TCHUNK, nq))
			mi.material_override = m
			root.add_child(mi)
			terrain_chunks[Vector2i(cx / TCHUNK, cz / TCHUNK)] = mi
	var skirt := MeshInstance3D.new()
	skirt.mesh = grid.build_skirt(4.0, def.palette["strata"])
	skirt.material_override = m
	add_child(skirt)
	# diorama plinth
	MF.part(self, MF.box(def.size + 2.4, 0.8, def.size + 2.4), MF.mat(Color(0.16, 0.12, 0.09), 0.7), Vector3(0, -4.35, 0))
	MF.part(self, MF.box(def.size + 3.2, 0.25, def.size + 3.2), MF.mat(Color(0.32, 0.30, 0.26), 0.5, 0.3), Vector3(0, -4.85, 0))
	# far ground (out-of-scope area), deliberately plain
	var far := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	far.mesh = pm
	far.material_override = MF.mat(Color(0.20, 0.21, 0.19), 1.0)
	far.position = Vector3(0, -14.0, 0)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)


var grass_nodes: Array = []
var trees: Array = []        # {pos, dead, parts: [[MultiMeshInstance3D, idx, "trunk"/"crown"]], down}
var grass_cells := {}        # Vector2i(4 m) -> [[MultiMeshInstance3D, idx]]
var bush_nodes: Array = []


## Quality preset hook (Game.apply_quality): post effects, shadow cascades,
## grass draw distance, bush shadows.
func apply_quality(q: Dictionary) -> void:
	if environment:
		environment.ssao_enabled = q["ssao"]
		environment.glow_enabled = q["glow"]
	if sun:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(q["splits"]) == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = float(q["shadow_dist"])
	for g in grass_nodes:
		if is_instance_valid(g):
			g.visibility_range_end = float(q["grass"])
			g.visibility_range_end_margin = 10.0
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for b in bush_nodes:
		if is_instance_valid(b):
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if q["bush_shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Like _mm but split into square chunks, so the camera frustum culls what is
## off screen (one MultiMesh per chunk instead of one for the whole map).
## `where` (optional) is filled with [MultiMeshInstance3D, index] for every
## input transform, so single instances can be changed later (destruction).
func _mm_chunked(mesh: Mesh, xforms: Array, colors: Array, material: Material, shadows: bool = true, chunk: float = 50.0, where = null) -> Array:
	var buckets := {}
	for i in xforms.size():
		var o: Vector3 = (xforms[i] as Transform3D).origin
		var key := Vector2i(int(floor(o.x / chunk)), int(floor(o.z / chunk)))
		if not buckets.has(key):
			buckets[key] = [[], [], []]
		buckets[key][0].append(xforms[i])
		buckets[key][1].append(colors[i])
		buckets[key][2].append(i)
	if where is Array:
		where.resize(xforms.size())
	var out: Array = []
	for key in buckets.keys():
		var n = _mm(mesh, buckets[key][0], buckets[key][1], material, shadows)
		if n:
			out.append(n)
			if where is Array:
				var src: Array = buckets[key][2]
				for li in src.size():
					where[src[li]] = [n, li]
	return out


func _mm(mesh: Mesh, xforms: Array, colors: Array, material: Material, shadows: bool = true) -> MultiMeshInstance3D:
	if xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _blocked_for_tree(p: Vector2) -> bool:
	var i := clampi(int(round((p.y + grid.half) / grid.res)), 0, grid.n - 1) * grid.n + clampi(int(round((p.x + grid.half) / grid.res)), 0, grid.n - 1)
	if tdist[i] < 2.4:
		return true
	for road in def.roads:
		if poly_dist(p, road["pts"]) < float(road["w"]) * 0.5 + 1.6:
			return true
	for b in def.bunkers:
		if p.distance_to(b["pos"]) < 4.5:
			return true
	for blds in [def.apartments, def.houses, def.sheds]:
		for a in blds:
			var lp: Vector2 = (p - a["pos"]).rotated(float(a.get("rot", 0.0)))
			var hs: Vector2 = a["size"] * 0.5 + Vector2(2.5, 2.5)
			if absf(lp.x) < hs.x and absf(lp.y) < hs.y:
				return true
	return false


func _build_vegetation() -> void:
	var vrng := RandomNumberGenerator.new()
	vrng.seed = def.seed + 77
	var pal := def.palette
	var crowns: Array = pal["crown"]
	var trunk_mesh := MF.cyl(0.35, 0.5, 1.0, 6)
	var crown_a := MF.sphere(1.0, 2.0, 7, 5, false, 0.13, 1)
	var crown_b := MF.sphere(1.0, 2.0, 6, 4, false, 0.16, 2)
	var crown_c := MF.cyl(0.0, 1.0, 1.0, 7)   # pine: cone tiers
	var cc_x: Array = []
	var cc_c: Array = []
	var pine_bark := Color(0.40, 0.26, 0.17)
	var pine_cols: Array = pal.get("pine", [Color(0.13, 0.22, 0.12), Color(0.16, 0.25, 0.13), Color(0.11, 0.19, 0.11), Color(0.18, 0.26, 0.15)])
	var bush_mesh := MF.sphere(1.0, 2.0, 6, 4, false, 0.15, 3)
	var tuft := MF.cyl(0.0, 0.14, 0.55, 4)
	var t_x: Array = []
	var t_c: Array = []
	var ca_x: Array = []
	var ca_c: Array = []
	var cb_x: Array = []
	var cb_c: Array = []
	var b_x: Array = []
	var b_c: Array = []
	var g_x: Array = []
	var g_c: Array = []
	var trunk_col: Color = pal["trunk"]
	var dead_col: Color = pal["dead_trunk"]
	var tree_raw: Array = []   # per tree: {pos, h, t: [t_x idx], a: [ca_x idx], b: [cb_x idx]}
	for tl in def.treelines:
		var r: Rect2 = tl["rect"]
		var count := int(r.get_area() * float(tl["density"]) * 0.075)
		for k in count:
			var p := Vector2(vrng.randf_range(r.position.x, r.end.x), vrng.randf_range(r.position.y, r.end.y))
			if _blocked_for_tree(p):
				continue
			var gy := grid.height_at(p.x, p.y)
			var dead := vrng.randf() < float(tl["dead"])
			var t0 := t_x.size()
			var a0 := ca_x.size()
			var b0 := cb_x.size()
			var c0 := cc_x.size()
			var kind := String(tl.get("kind", ""))
			var pine := kind == "pine" or (kind == "mixed" and vrng.randf() < 0.5)
			if pine and not dead:
				# a tall pine: a bare reddish trunk, the crown high up in cone tiers
				var h := vrng.randf_range(10.0, 16.0)
				var rad := vrng.randf_range(0.32, 0.48)
				var lean := Basis.from_euler(Vector3(vrng.randf_range(-0.04, 0.04), 0, vrng.randf_range(-0.04, 0.04)))
				t_x.append(Transform3D(lean * Basis.from_scale(Vector3(rad, h, rad)), Vector3(p.x, gy + h * 0.5 - 0.1, p.y)))
				t_c.append(pine_bark.darkened(vrng.randf() * 0.25))
				var tiers := vrng.randi_range(2, 4)
				var top := h + vrng.randf_range(0.5, 1.5)
				for ti in tiers:
					var w := vrng.randf_range(1.6, 2.6) * (1.0 - ti * 0.18)
					var th := vrng.randf_range(2.2, 3.2)
					var y := top - (tiers - ti) * th * 0.55
					cc_x.append(Transform3D(Basis(Vector3.UP, vrng.randf() * TAU) * Basis.from_scale(Vector3(w, th, w)),
						Vector3(p.x, gy, p.y) + lean * Vector3(0, y, 0)))
					cc_c.append((pine_cols[vrng.randi() % pine_cols.size()] as Color).lightened(vrng.randf_range(-0.04, 0.06)))
			elif dead:
				var h := vrng.randf_range(1.2, 5.0)
				var rad := vrng.randf_range(0.5, 0.8)
				var tilt := Basis.from_euler(Vector3(vrng.randf_range(-0.25, 0.25), vrng.randf() * TAU, vrng.randf_range(-0.25, 0.25)))
				var bs := tilt * Basis.from_scale(Vector3(rad, h, rad))
				t_x.append(Transform3D(bs, Vector3(p.x, gy, p.y) + tilt * Vector3(0, h * 0.5 - 0.1, 0)))
				t_c.append(dead_col.darkened(vrng.randf() * 0.25))
				# broken branches
				for bi in vrng.randi_range(0, 2):
					var bb := tilt * Basis.from_euler(Vector3(vrng.randf_range(0.6, 1.2), vrng.randf() * TAU, 0)) * Basis.from_scale(Vector3(0.18, vrng.randf_range(0.8, 1.6), 0.18))
					t_x.append(Transform3D(bb, Vector3(p.x, gy, p.y) + tilt * Vector3(0, h * vrng.randf_range(0.5, 0.9), 0)))
					t_c.append(dead_col)
				if vrng.randf() < 0.35:
					var cs := vrng.randf_range(0.7, 1.2)
					cb_x.append(Transform3D(Basis.from_scale(Vector3(cs, cs * 0.7, cs)), Vector3(p.x, gy, p.y) + tilt * Vector3(0, h, 0)))
					cb_c.append((crowns[vrng.randi() % crowns.size()] as Color).darkened(0.15))
				if vrng.randf() < 0.25:
					var L := vrng.randf_range(3.0, 6.0)
					var lb := Basis.from_euler(Vector3(PI / 2, vrng.randf() * TAU, 0)) * Basis.from_scale(Vector3(0.55, L, 0.55))
					t_x.append(Transform3D(lb, Vector3(p.x + vrng.randf_range(-2, 2), gy + 0.2, p.y + vrng.randf_range(-2, 2))))
					t_c.append(dead_col.darkened(0.2))
			else:
				var h := vrng.randf_range(3.5, 6.8)
				var rad := vrng.randf_range(0.5, 0.75)
				t_x.append(Transform3D(Basis.from_scale(Vector3(rad, h, rad)), Vector3(p.x, gy + h * 0.5 - 0.1, p.y)))
				t_c.append(trunk_col.darkened(vrng.randf() * 0.2))
				var blobs := vrng.randi_range(1, 3)
				for bi in blobs:
					var s := Vector3(vrng.randf_range(1.5, 2.6), vrng.randf_range(1.2, 2.0), vrng.randf_range(1.5, 2.6))
					var off := Vector3(vrng.randf_range(-1.2, 1.2), h + vrng.randf_range(-0.4, 1.0), vrng.randf_range(-1.2, 1.2))
					var xf := Transform3D(Basis(Vector3.UP, vrng.randf() * TAU) * Basis.from_scale(s), Vector3(p.x, gy, p.y) + off)
					var col: Color = crowns[vrng.randi() % crowns.size()]
					col = col.lightened(vrng.randf_range(-0.05, 0.1))
					if bi % 2 == 0:
						ca_x.append(xf)
						ca_c.append(col)
					else:
						cb_x.append(xf)
						cb_c.append(col)
			tree_raw.append({"pos": Vector3(p.x, gy, p.y), "dead": dead, "t": range(t0, t_x.size()), "a": range(a0, ca_x.size()), "b": range(b0, cb_x.size()),
				"c": range(c0, cc_x.size())})
		# undergrowth
		var bcount := int(r.get_area() * 0.035)
		for k in bcount:
			var p := Vector2(vrng.randf_range(r.position.x, r.end.x), vrng.randf_range(r.position.y, r.end.y))
			if _blocked_for_tree(p):
				continue
			var s := vrng.randf_range(0.8, 1.7)
			b_x.append(Transform3D(Basis(Vector3.UP, vrng.randf() * TAU) * Basis.from_scale(Vector3(s, s * vrng.randf_range(0.5, 0.8), s)), Vector3(p.x, grid.height_at(p.x, p.y) + 0.2, p.y)))
			b_c.append((crowns[vrng.randi() % crowns.size()] as Color).darkened(vrng.randf_range(0.05, 0.25)))
	for bsh in def.bushes:
		var blobs := vrng.randi_range(2, 5)
		for k in blobs:
			var p = Vector2(bsh.x, bsh.y) + Vector2(vrng.randf_range(-1, 1), vrng.randf_range(-1, 1)) * bsh.z * 0.7
			var s = vrng.randf_range(0.7, 1.5) * (bsh.z / 2.0)
			b_x.append(Transform3D(Basis(Vector3.UP, vrng.randf() * TAU) * Basis.from_scale(Vector3(s, s * 0.7, s)), Vector3(p.x, grid.height_at(p.x, p.y) + 0.15, p.y)))
			b_c.append((crowns[vrng.randi() % crowns.size()] as Color).darkened(vrng.randf_range(0.0, 0.2)))
	# grass tufts
	var grass: Array = pal["grass"]
	var gi := 0
	while gi < mini(int(9000.0 * pow(def.size / 160.0, 2.0)), 60000):
		gi += 1
		var x := vrng.randf_range(-grid.half + 0.5, grid.half - 0.5)
		var z := vrng.randf_range(-grid.half + 0.5, grid.half - 0.5)
		var vi := clampi(int(round((z + grid.half) / grid.res)), 0, grid.n - 1) * grid.n + clampi(int(round((x + grid.half) / grid.res)), 0, grid.n - 1)
		var g := grid.gtype[vi]
		if g == G.ROAD or g == G.TRENCH or g == G.CRATER or g == G.BURNT or g == G.MUD:
			continue
		var s := vrng.randf_range(0.6, 1.4)
		var bs := Basis.from_euler(Vector3(vrng.randf_range(-0.25, 0.25), vrng.randf() * TAU, vrng.randf_range(-0.25, 0.25))) * Basis.from_scale(Vector3(s, s * vrng.randf_range(0.7, 1.4), s))
		g_x.append(Transform3D(bs, Vector3(x, grid.height_at(x, z) + 0.2 * s, z)))
		var gc: Color = grass[vrng.randi() % grass.size()]
		if g == G.DRY:
			gc = gc.lerp(Color(0.62, 0.56, 0.36), 0.5)
		g_c.append(gc.lightened(vrng.randf_range(-0.08, 0.08)))
	var wt: Array = []
	var wa: Array = []
	var wb: Array = []
	_mm_chunked(trunk_mesh, t_x, t_c, MF.vcol(0.95), true, 50.0, wt)
	_mm_chunked(crown_a, ca_x, ca_c, foliage_mat, true, 50.0, wa)
	_mm_chunked(crown_b, cb_x, cb_c, foliage_mat, true, 50.0, wb)
	var wc: Array = []
	if not cc_x.is_empty():
		_mm_chunked(crown_c, cc_x, cc_c, foliage_mat, true, 50.0, wc)
	for tr in tree_raw:
		var parts: Array = []
		for i in tr["t"]:
			parts.append([wt[i][0], wt[i][1], "trunk"])
		for i in tr["a"]:
			parts.append([wa[i][0], wa[i][1], "crown"])
		for i in tr["b"]:
			parts.append([wb[i][0], wb[i][1], "crown"])
		for i in tr["c"]:
			parts.append([wc[i][0], wc[i][1], "crown"])
		trees.append({"pos": tr["pos"], "dead": tr["dead"], "parts": parts, "down": false})
	bush_nodes = _mm_chunked(bush_mesh, b_x, b_c, foliage_mat)
	var gmat := foliage_mat.duplicate()
	gmat.set_shader_parameter("sway", 0.12)
	grass_mat = gmat
	var wg: Array = []
	grass_nodes = _mm_chunked(tuft, g_x, g_c, gmat, false, 40.0, wg)
	for i in g_x.size():
		var o: Vector3 = (g_x[i] as Transform3D).origin
		grass_cells.get_or_add(Vector2i(int(floor(o.x / 4.0)), int(floor(o.z / 4.0))), []).append(wg[i])
	if not preview:
		apply_quality(Game.quality())


func _build_structures() -> void:
	var root := Node3D.new()
	root.name = "Structures"
	add_child(root)
	_build_lines(root)
	_build_points(root)


## Line objects (fences, wire, dragon teeth): part of the editor preview too.
func _build_lines(root: Node3D) -> void:
	for f in def.fences:
		var frng := MapModels.obj_rng(def.seed, f[0] if f.size() > 0 else Vector2.ZERO)
		for i in f.size() - 1:
			var a: Vector2 = f[i]
			var b: Vector2 = f[i + 1]
			Props.fence_segment(grid.ground(Vector3(a.x, 0, a.y)), grid.ground(Vector3(b.x, 0, b.y)), frng, root)
	for wl in def.wire:
		Props.wire(wl, grid, root)
	_build_teeth()
	for bl in def.blocks:
		var pts: PackedVector2Array = bl["pts"]
		var brng := MapModels.obj_rng(def.seed, pts[0] if pts.size() > 0 else Vector2.ZERO)
		for p in Props.blocks(pts, String(bl.get("kind", "concrete")), grid, brng, root):
			var i := grid.cidx(p.x, p.y)
			grid.cover[i] = maxf(grid.cover[i], 0.7)
			grid.obstacle[i] = maxf(grid.obstacle[i], 1.0)
			grid.veh_solid[i] = 1
			grid.inf_weight[i] = maxf(grid.inf_weight[i], 2.5)


## Point objects: every one is built by MapModels from its own seeded random
## numbers, so the editor shows exactly the same model (MapNode._model).
func _build_points(root: Node3D) -> void:
	for h in def.houses:
		var res := MapModels.house(def.seed, h)
		_place_building(root, res, h["pos"], h["rot"], h["size"])
	for sh in def.sheds:
		var res := MapModels.shed(def.seed, sh)
		_place_building(root, res, sh["pos"], sh["rot"], sh["size"])
	for ap in def.apartments:
		var res := MapModels.apartment(def.seed, ap)
		_place_building(root, res, ap["pos"], ap["rot"], ap["size"])
	for c in def.cars:
		var node := MapModels.car(def.seed, c["pos"])
		var cp: Vector2 = c["pos"]
		node.position = grid.ground(Vector3(cp.x, 0, cp.y))
		node.rotation.y = c["rot"]
		root.add_child(node)
		var fwd := Vector3(-sin(float(c["rot"])), 0, -cos(float(c["rot"])))
		for k in [-1.4, 0.0, 1.4]:
			var q = Vector3(cp.x, 0, cp.y) + fwd * k
			_set_cell(q.x, q.z, 0.5, 1.3, 1, 1)
	for b in def.bales:
		var node := MapModels.bale(def.seed, b)
		node.position = grid.ground(Vector3(b.x, 0, b.y))
		root.add_child(node)
		_reg_piece("bale", Loc.t("тюк сіна"), node.get_child(0), b, 0.0, 0.35, 1.3)
	for p in def.poles:
		var node := MapModels.pole(def.seed, p)
		node.position = grid.ground(Vector3(p.x, 0, p.y))
		root.add_child(node)
	for sb in def.sandbags:
		var node := MapModels.sandbags(def.seed, sb)
		var sp: Vector2 = sb["pos"]
		node.position = grid.ground(Vector3(sp.x, 0, sp.y))
		node.rotation.y = sb["rot"]
		root.add_child(node)
		_reg_piece("sandbags", Loc.t("мішки з піском"), node, sp, 2.2, 0.62)
	for wr in def.wrecks:
		var vm := MapModels.wreck(wr["model"])
		var wp: Vector2 = wr["pos"]
		vm.position = grid.ground(Vector3(wp.x, 0, wp.y))
		vm.rotation.y = wr["rot"]
		root.add_child(vm)
		_area_cells(wp, 4.0, 0.5, 1)
		var fwd := Vector3(-sin(float(wr["rot"])), 0, -cos(float(wr["rot"])))
		for k in [-2.0, 0.0, 2.0]:
			var q = Vector3(wp.x, 0, wp.y) + fwd * k
			_set_cell(q.x, q.z, 0.5, 1.9, 1, 1)
	for b in def.bunkers:
		var bk := Bunker.new()
		var bp: Vector2 = b["pos"]
		var face: Vector2 = b["face"]
		bk.setup(b["kind"], Vector3(face.x, 0, face.y), MapModels.obj_rng(def.seed, bp))
		bk.position = grid.ground(Vector3(bp.x, 0, bp.y))
		add_child(bk)
		bunker_nodes.append(bk)
		W.bunkers.append(bk)
		_area_cells(bp, 3.0, 0.4, 1)
		_set_cell(bp.x, bp.y, 0.88)
	_build_dugouts(root)
	# ambient smoke columns
	for sc in def.smoke_columns:
		W.fx.burning(grid.ground(Vector3(sc.x, 0, sc.y)), false, true)


## Covered dugouts (log-roofed earth mounds): cover and a low obstacle.
func _build_dugouts(root: Node3D) -> void:
	var spoil: Color = def.palette.get("spoil", Color(0.52, 0.48, 0.33))
	for dg in def.dugouts:
		var p: Vector2 = dg["pos"]
		var sz: Vector2 = dg.get("size", Vector2(3.6, 3.0))
		var node := MapModels.dugout(def.seed, dg, spoil)
		node.position = grid.ground(Vector3(p.x, 0, p.y))
		node.rotation.y = dg["rot"]
		root.add_child(node)
		_reg_piece("dugout", Loc.t("перекриття бліндажа"), node, p, maxf(sz.x, sz.y) * 0.5 + 0.6, 0.8, 0.85)


## Anti-vehicle "dragon teeth": rows of concrete pyramids. Vehicles cannot
## pass; infantry can (slowly) and gets a little cover.
func _build_teeth() -> void:
	var trng := RandomNumberGenerator.new()
	trng.seed = def.seed + 91
	var xs: Array = []
	var cols: Array = []
	for row_def in def.teeth:
		var pts: PackedVector2Array = row_def["pts"]
		var rows: int = int(row_def.get("rows", 2))
		for k in pts.size() - 1:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var l := a.distance_to(b)
			var dir := (b - a) / l
			var nrm := Vector2(-dir.y, dir.x)
			var t := 0.0
			while t <= l:
				for r in rows:
					var off := (float(r) - (rows - 1) * 0.5) * 1.7
					var q := a + dir * (t + (0.85 if r % 2 == 1 else 0.0)) + nrm * off
					var g := grid.ground(Vector3(q.x, 0, q.y))
					var bs := Basis(Vector3.UP, trng.randf_range(-0.2, 0.2) + atan2(dir.x, dir.y)).scaled(Vector3.ONE * trng.randf_range(0.9, 1.08))
					xs.append(Transform3D(bs, g + Vector3(0, 0.45, 0)))
					cols.append(Color(0.62, 0.61, 0.57).darkened(trng.randf() * 0.18))
					var ci := grid.ci(grid.cell_of(q.x, q.y))
					grid.veh_solid[ci] = 1
					grid.cover[ci] = maxf(grid.cover[ci], 0.3)
					grid.inf_weight[ci] = maxf(grid.inf_weight[ci], 2.0)
				t += 1.7
	if xs.is_empty():
		return
	var pyr := CylinderMesh.new()
	pyr.top_radius = 0.07
	pyr.bottom_radius = 0.62
	pyr.height = 0.95
	pyr.radial_segments = 4
	pyr.rings = 1
	_mm(pyr, xs, cols, MF.vcol(0.95))


func _place_building(root: Node3D, res: Dictionary, pos: Vector2, rot: float, sz: Vector2) -> void:
	var node: Node3D = res["node"]
	var gy := grid.height_at(pos.x, pos.y)
	node.position = Vector3(pos.x, gy, pos.y)
	node.rotation.y = rot
	root.add_child(node)
	var basis := Basis(Vector3.UP, rot)
	var center := Vector3(pos.x, 0, pos.y)
	# interior & surroundings
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	var lx := -hx - 2.0
	while lx <= hx + 2.0:
		var lz := -hz - 2.0
		while lz <= hz + 2.0:
			var w := center + basis * Vector3(lx, 0, lz)
			var inside := absf(lx) < hx - 0.3 and absf(lz) < hz - 0.3
			if inside:
				_set_cell(w.x, w.z, 0.55, -1.0, -1, 1)
			else:
				_set_cell(w.x, w.z, 0.3, -1.0, -1, 1)
			lz += 1.0
		lx += 1.0
	_reg_building(res, center, basis, rot, sz)
	# walls: register every destructible piece first (remembering the cells as
	# they were), then stamp exactly the cells each piece owns
	var first_piece := pieces.size()
	for wl in res["walls"]:
		if wl.size() > 3 and float(wl[2]) > 0.0:
			var a: Vector2 = wl[0]
			var b: Vector2 = wl[1]
			_reg_wall(wl[3], center + basis * Vector3(a.x, 0, a.y), center + basis * Vector3(b.x, 0, b.y), wl[2], wl.size() > 4 and wl[4] == "plank")
	for pi in range(first_piece, pieces.size()):
		for ci in pieces[pi]["cells"]:
			var i: int = ci[0]
			var h: float = ci[2]
			grid.cover[i] = maxf(grid.cover[i], 0.5)
			grid.obstacle[i] = maxf(grid.obstacle[i], h)
			if h > 1.2:
				grid.inf_solid[i] = 1
			grid.veh_solid[i] = 1
	for wl in res["walls"]:
		var a: Vector2 = wl[0]
		var b: Vector2 = wl[1]
		var h: float = wl[2]
		if h <= 0.0 or wl.size() > 3:
			continue
		var L := a.distance_to(b)
		var k := 0.0
		while k <= L:
			var lp := a.lerp(b, k / maxf(L, 0.001))
			var w := center + basis * Vector3(lp.x, 0, lp.y)
			_set_cell(w.x, w.z, 0.5, h, 1 if h > 1.2 else -1, 1)
			k += 0.5
	_carve_doors(buildings[buildings.size() - 1])


## Doorways are narrower than a 2 m nav cell: the walls on either side of a
## door used to mark its cell solid, so many buildings could only be left
## through a breach (garrisons never fell back, reserves never came out).
## Open a walking line from inside to outside through every door — for
## infantry only; sight through it is unchanged.
func _carve_doors(b: Dictionary) -> void:
	for d in b["doors"]:
		var a: Vector3 = d["in"]
		var e: Vector3 = d["out"]
		var L := a.distance_to(e)
		var k := 0.0
		while k <= L:
			var w := a.lerp(e, k / maxf(L, 0.001))
			if grid.in_bounds(w.x, w.z):
				var i := grid.cidx(w.x, w.z)
				grid.inf_solid[i] = 0
				door_cells[i] = true
				if piece_static_inf.has(i):
					piece_static_inf[i] = 0
			k += 0.4
