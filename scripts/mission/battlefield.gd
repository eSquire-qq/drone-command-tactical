class_name Battlefield
extends Node
## Dynamic battlefield: the ground changes during the fight.
##  - Heavy explosions (mortar, 73 mm HE, mines) leave craters: a visual bowl
##    with a spoil rim, cover in the crater cells, slower going for vehicles.
##    Only the touched cells and their A* points are updated (no nav rebuild).
##  - Field fortifications (sandbags, hay bales, dugouts) have durability:
##    intact / damaged / destroyed changes their cover value, which the AI
##    reads directly when it picks a position (TerrainGrid.find_cover).
##    Bunkers keep their own HP (Bunker) and get a damaged state too.
##  - Wind carries smoke clouds, they grow and thin out at the end of their
##    life; the drone sensor sees through thin smoke only approximately and
##    not at all through dense smoke.
## All numbers — AIConfig.CRATER_* / COVER_* / WIND_* / SMOKE_*.

var craters: Array = []      # {pos: Vector3, r: float, node: Node3D}
var pieces: Array = []       # see MapManager._reg_piece
var wind := Vector3.ZERO     # m/s, horizontal
var stats := {"craters": 0, "damaged": 0, "destroyed": 0}
var dyn_cover := PackedFloat32Array()   # cover from craters per cell (floor for pieces)
var static_cover := {}       # cell -> cover without any piece
var cell_pieces := {}        # cell -> [piece index]
var _crater_tex: GradientTexture2D
var _rim_mats: Array = []
var _radio_t := {}           # squad -> last "cover lost" report
var _tree_cells := {}        # Vector2i(8 m) -> [tree index]


func setup(def: MapDef) -> void:
	dyn_cover.resize(W.grid.cn * W.grid.cn)
	dyn_cover.fill(0.0)
	pieces = W.map.pieces
	static_cover = W.map.piece_static
	cell_pieces = W.map.piece_cells
	for p in pieces:
		p["max_hp"] = float(p["hp"])
		p["state"] = 0
	var trees: Array = W.map.trees
	for ti in trees.size():
		var tp: Vector3 = trees[ti]["pos"]
		_tree_cells.get_or_add(Vector2i(int(floor(tp.x / 8.0)), int(floor(tp.z / 8.0))), []).append(ti)
	stats["trees"] = 0
	var a := randf() * TAU
	wind = Vector3(cos(a), 0, sin(a)) * AIConfig.WIND_BASE * float(Game.wx("wind"))
	_crater_tex = GradientTexture2D.new()
	_crater_tex.fill = GradientTexture2D.FILL_RADIAL
	_crater_tex.fill_from = Vector2(0.5, 0.5)
	_crater_tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0.14, 0.11, 0.08, 0.95), Color(0.22, 0.18, 0.13, 0.9),
		Color(0.36, 0.30, 0.21, 0.7), Color(0.4, 0.34, 0.24, 0.0)])
	_crater_tex.gradient = g
	_crater_tex.width = 64
	_crater_tex.height = 64
	var spoil: Color = def.palette.get("spoil", Color(0.52, 0.48, 0.33))
	for k in 4:
		_rim_mats.append(MF.mat(spoil.darkened(0.04 + k * 0.08).lerp(Color(0.3, 0.26, 0.2), k * 0.1)))


func wind_text() -> String:
	var sp := wind.length()
	if sp < 0.05:
		return Loc.t("штиль")
	# smoke goes where the wind blows; name the direction it blows FROM
	return Loc.t("%s, %.1f м/с") % [RadioSystem.bearing(Vector3.ZERO, -wind), sp]


# ------------------------------------------------------------------ explosions
func on_explosion(pos: Vector3, radius: float, power: float, kind: String) -> void:
	var cr: float = float(AIConfig.CRATER_R.get(kind, 0.0))
	if kind == "he" and power < AIConfig.CRATER_HE_POWER:
		cr = 0.0
	if cr > 0.0:
		add_crater(pos, cr * randf_range(0.85, 1.15))
	_blast_trees(pos, radius, power)
	var reach := radius + 1.5
	for i in pieces.size():
		var p: Dictionary = pieces[i]
		if int(p["state"]) == 2:
			continue
		var d: float = Vector2(p["pos"].x - pos.x, p["pos"].z - pos.z).length() - float(p["size"])
		if d >= reach:
			continue
		var dmg := power * AIConfig.COVER_DMG_K * (1.0 - maxf(d, 0.0) / reach) * randf_range(0.8, 1.2)
		damage_piece(i, dmg)


func damage_piece(i: int, dmg: float) -> void:
	var p: Dictionary = pieces[i]
	p["hp"] = float(p["hp"]) - dmg
	var st := 0
	if float(p["hp"]) <= 0.0:
		st = 2
	elif float(p["hp"]) < float(p["max_hp"]) * AIConfig.COVER_DAMAGED_HP:
		st = 1
	if st <= int(p["state"]):
		return
	p["state"] = st
	stats["damaged" if st == 1 else "destroyed"] += 1
	for ci in p["cells"]:
		_refresh_cell(int(ci[0]))
	_show_piece(p, st)
	if W.blog and st == 2 and p["kind"] != "wall":
		W.blog.add("field", Loc.t("Зруйновано укриття: %s") % p["title"], p["pos"])
	# men behind it notice and report
	for u in W.units:
		if not u.is_active() or u.vehicle != null or u.squad == null:
			continue
		if Vector2(u.global_position.x - p["pos"].x, u.global_position.z - p["pos"].z).length() > float(p["size"]) + 2.5:
			continue
		u.add_suppression(AIConfig.COVER_LOST_SUPP, "blast")
		if u.side == 0 and W.time - float(_radio_t.get(u.squad, -99.0)) > 20.0:
			_radio_t[u.squad] = W.time
			u.squad.radio("fire", (Loc.t("укриття зруйновано, змінюємо позицію.") if st == 2 else Loc.t("укриття пошкоджено.")), "warn")


func _refresh_cell(i: int) -> void:
	var g = W.grid
	var v: float = maxf(float(static_cover.get(i, 0.0)), dyn_cover[i])
	var ob := 0.0
	var nb := 0     # wall pieces that block this cell while standing
	var nd := 0     # of them destroyed
	var breach := false   # a destroyed wall piece centred in this cell
	var rubble := false
	for pi in cell_pieces.get(i, []):
		var p: Dictionary = pieces[pi]
		var st := int(p["state"])
		var k: float = [1.0, AIConfig.COVER_DAMAGED, AIConfig.COVER_DESTROYED][st]
		if p["kind"] == "wall":
			# a wall keeps half its height when damaged, a heap of rubble when gone
			k = [1.0, AIConfig.WALL_DAMAGED_H, 0.0][st]
			v = maxf(v, float(p["cov"]) * (1.0 if st < 2 else AIConfig.WALL_RUBBLE_COVER / float(p["cov"])))
			rubble = rubble or st == 2
		else:
			v = maxf(v, float(p["cov"]) * k)
		for ci in p["cells"]:
			if int(ci[0]) != i:
				continue
			if float(ci[2]) > 0.0:
				ob = maxf(ob, float(ci[2]) * k if st < 2 else (AIConfig.WALL_RUBBLE_H if p["kind"] == "wall" else 0.0))
			if ci.size() > 3 and bool(ci[3]):
				nb += 1
				if st == 2:
					nd += 1
					if g.cidx(p["pos"].x, p["pos"].z) == i:
						breach = true
	g.cover[i] = v
	if not cell_pieces.has(i):
		return
	g.obstacle[i] = maxf(float(W.map.piece_static_obst.get(i, 0.0)), ob)
	# a breached wall opens a way through for infantry: A* point updated in place
	# a 2 m cell holds ~2 m of wall: half of it gone is a man-sized breach
	var solid: bool = (nb > 0 and nd * 2 < nb and not breach) or int(W.map.piece_static_inf.get(i, 0)) != 0
	if W.map.door_cells.has(i):
		solid = false   # a doorway stays a doorway
	if (g.inf_solid[i] != 0) != solid:
		g.inf_solid[i] = 1 if solid else 0
		var cc := Vector2i(i % g.cn, i / g.cn)
		g.astar_inf.set_point_solid(cc, solid)
		if not solid and rubble:
			g.inf_weight[i] = maxf(g.inf_weight[i], AIConfig.WALL_RUBBLE_W)
			g.astar_inf.set_point_weight_scale(cc, g.inf_weight[i])


func _show_piece(p: Dictionary, st: int) -> void:
	if p["kind"] == "wall":
		_show_wall(p, st)
		return
	var node: Node3D = p["node"]
	if node == null or not is_instance_valid(node):
		return
	var parts: Array = []
	for c in node.get_children():
		if c is MeshInstance3D:
			parts.append(c)
	match String(p["kind"]):
		"sandbags":
			# top bags thrown off, the rest knocked about
			parts.sort_custom(func(a, b): return a.position.y > b.position.y)
			var drop := int(parts.size() * (0.4 if st == 1 else 0.75))
			for k in parts.size():
				var m: MeshInstance3D = parts[k]
				if k < drop:
					m.visible = false
				else:
					m.rotation.y += randf_range(-0.4, 0.4)
					m.rotation.z = randf_range(-0.25, 0.25)
					m.position.x += randf_range(-0.12, 0.12)
		"bale":
			if st == 2:
				node.visible = false
			else:
				node.rotation.z = randf_range(-0.3, 0.3)
		_:
			pass
	for m in parts:
		var mat := m.material_override as StandardMaterial3D
		if mat:
			m.material_override = MF.mat(mat.albedo_color.darkened(0.25 if st == 1 else 0.5))
	if st == 2:
		W.fx.scorch(p["pos"], float(p["size"]) + 1.0)


## Wall piece: knocked down to half height, then to a heap of rubble.
func _show_wall(p: Dictionary, st: int) -> void:
	for m in p["parts"]:
		if not is_instance_valid(m):
			continue
		if st == 2:
			m.visible = false
		else:
			m.scale.y *= AIConfig.WALL_DAMAGED_H
			m.position.y *= AIConfig.WALL_DAMAGED_H
			m.rotation.z += randf_range(-0.08, 0.08)
			var mat := m.material_override as StandardMaterial3D
			if mat:
				m.material_override = MF.mat(mat.albedo_color.darkened(0.2))
	if st == 2:
		var gp: Vector3 = p["pos"]
		var mat2 := MF.mat(Props.PLASTER.darkened(0.3))
		for k in 4:
			var s := randf_range(0.25, 0.55)
			var m2 := MF.part(W.map, MF.box(s * 1.5, s * 0.6, s), mat2, W.grid.ground(gp + Vector3(randf_range(-0.7, 0.7), 0, randf_range(-0.7, 0.7))) + Vector3(0, s * 0.2, 0),
				Vector3(randf() * 0.4, randf() * TAU, randf() * 0.4))
			m2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		W.fx.explosion(gp + Vector3(0, 1.0, 0), 1.5)


# ------------------------------------------------------------------ trees
func _blast_trees(pos: Vector3, radius: float, power: float) -> void:
	var reach := radius * 0.55 + 1.0
	var c0 := Vector2i(int(floor(pos.x / 8.0)), int(floor(pos.z / 8.0)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for ti in _tree_cells.get(Vector2i(c0.x + dx, c0.y + dz), []):
				var t: Dictionary = W.map.trees[ti]
				if t["down"]:
					continue
				var d: float = Vector2(t["pos"].x - pos.x, t["pos"].z - pos.z).length()
				if d >= reach:
					continue
				var chance := power / 110.0 * (1.0 - d / reach) * AIConfig.TREE_FELL * (1.4 if t["dead"] else 1.0)
				if randf() < chance:
					fell_tree(ti, Vector2(t["pos"].x - pos.x, t["pos"].z - pos.z))


## A tree goes down away from the blast: the trunk lies on the ground, one
## crown blob lies at its end, the rest is gone. The tree line gets thinner.
func fell_tree(ti: int, away: Vector2) -> void:
	var t: Dictionary = W.map.trees[ti]
	t["down"] = true
	stats["trees"] += 1
	var base: Vector3 = t["pos"]
	var dir := away.normalized() if away.length() > 0.1 else Vector2.from_angle(randf() * TAU)
	dir = dir.rotated(randf_range(-0.5, 0.5))
	var d3 := Vector3(dir.x, 0, dir.y)
	var trunk_done := false
	var crown_done := false
	var length := 4.0
	for part in t["parts"]:
		var mmi: MultiMeshInstance3D = part[0]
		if not is_instance_valid(mmi):
			continue
		var mm := mmi.multimesh
		var idx: int = part[1]
		var xf := mm.get_instance_transform(idx)
		if part[2] == "trunk" and not trunk_done:
			trunk_done = true
			var rad := xf.basis.x.length()
			length = maxf(1.5, xf.basis.y.length() * 0.85)
			# lying along `dir`: rotate the up axis onto the ground direction
			var yaw := atan2(d3.x, d3.z)
			var bs := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(rad, length, rad))
			var mid := base + d3 * (length * 0.5 + 0.3)
			mid.y = W.grid.height_at(mid.x, mid.z) + rad * 0.6
			mm.set_instance_transform(idx, Transform3D(bs, mid))
		elif part[2] == "crown" and not crown_done:
			crown_done = true
			var s := xf.basis.get_scale()
			var end := base + d3 * (length + 0.6)
			end.y = W.grid.height_at(end.x, end.z) + s.y * 0.35
			mm.set_instance_transform(idx, Transform3D(Basis(Vector3.UP, randf() * TAU) * Basis.from_scale(Vector3(s.x, s.y * 0.55, s.z)), end))
		else:
			mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin))
	# less leaf cover around it: the tree line thins out
	var g = W.grid
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var p := base + Vector3(dx * 2.0, 0, dz * 2.0)
			if g.in_bounds(p.x, p.z):
				var i: int = g.cidx(p.x, p.z)
				g.foliage[i] = maxf(0.0, g.foliage[i] - AIConfig.TREE_FOLIAGE_LOSS * (1.0 if dx == 0 and dz == 0 else 0.4))


# ------------------------------------------------------------------ craters
func add_crater(pos: Vector3, r: float) -> void:
	var g = W.grid
	if g.in_channel(pos, 1.2) or not g.in_bounds(pos.x, pos.z, 3.0):
		return
	# a second hit in the same place widens the old crater
	for c in craters:
		if Vector2(c["pos"].x - pos.x, c["pos"].z - pos.z).length() < float(c["r"]) * 0.8:
			var old: float = c["r"]
			c["r"] = minf(AIConfig.CRATER_MAX_R, old * 1.15 + 0.1)
			if c.get("deformed", false):
				_deform(c["pos"], old, float(c["r"]))
			var node: Node3D = c["node"]
			if is_instance_valid(node):
				var k: float = float(c["r"]) / old
				for ch in node.get_children():
					if ch is Decal:
						ch.size = Vector3(float(c["r"]) * 2.6, 3.0, float(c["r"]) * 2.6)
					elif ch is MeshInstance3D:
						var lp: Vector3 = ch.position * Vector3(k, 0, k)
						lp.y = W.grid.height_at(node.global_position.x + lp.x, node.global_position.z + lp.z) - node.global_position.y + 0.03
						ch.position = lp
			_crater_cells(c["pos"], float(c["r"]))
			return
	if craters.size() >= AIConfig.CRATER_MAX:
		return
	var deformed := _can_deform(pos, AIConfig.CRATER_MAX_R)
	if deformed:
		_deform(pos, 0.0, r)
	var gp: Vector3 = g.ground(pos)
	var node := Node3D.new()
	node.name = "Crater"
	add_child(node)
	node.global_position = gp
	var d := Decal.new()
	d.texture_albedo = _crater_tex
	d.size = Vector3(r * 2.6, 3.0, r * 2.6)
	d.rotation.y = randf() * TAU
	d.cull_mask = 1          # the clods (layer 2) keep their own colour
	node.add_child(d)
	# thrown-out earth: an uneven, broken ring of small clods
	var clods := int(clampf(r * 14.0, 10, 34))
	for k in clods:
		if randf() < 0.15:
			continue
		var a := randf() * TAU
		var rr := r * randf_range(0.85, 1.45)
		var lp := Vector3(cos(a) * rr, 0, sin(a) * rr)
		var h: float = g.height_at(gp.x + lp.x, gp.z + lp.z) - gp.y
		var m := MeshInstance3D.new()
		var sz := randf_range(0.14, 0.38) * (1.4 if rr < r * 1.1 else 1.0)
		m.mesh = MF.box(sz * randf_range(0.8, 1.6), sz * randf_range(0.3, 0.6), sz)
		m.material_override = _rim_mats[randi() % _rim_mats.size()]
		m.position = lp + Vector3(0, h + sz * 0.12, 0)
		m.rotation = Vector3(randf_range(-0.4, 0.4), randf() * TAU, randf_range(-0.4, 0.4))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.layers = 2
		node.add_child(m)
	craters.append({"pos": gp, "r": r, "r0": r, "node": node, "deformed": deformed})
	stats["craters"] += 1
	_crater_cells(gp, r)


## Height profile of a crater of radius r at distance d (0 outside the rim).
static func crater_profile(d: float, r: float) -> float:
	if r <= 0.0:
		return 0.0
	if d < r:
		var k := d / r
		return -r * AIConfig.CRATER_DEPTH * (1.0 - k * k)
	if d < r * 1.55:
		return r * AIConfig.CRATER_RIM * sin((d - r) / (r * 0.55) * PI)
	return 0.0


## The ground may sink only in the open: not under trenches (their walls
## are separate geometry), buildings, bunkers or fortifications.
func _can_deform(pos: Vector3, r: float) -> bool:
	var g = W.grid
	var span := r * 1.6
	var x := pos.x - span
	while x <= pos.x + span:
		var z := pos.z - span
		while z <= pos.z + span:
			if g.in_bounds(x, z):
				var i: int = g.cidx(x, z)
				if g.trench_near[i] != 0 or g.inf_solid[i] != 0 or g.obstacle[i] > 0.0 or cell_pieces.has(i):
					return false
			z += TerrainGrid.CS
		x += TerrainGrid.CS
	for b in W.bunkers:
		if b.global_position.distance_to(pos) < span + 3.5:
			return false
	return true


## Sinks the ground from a crater of radius r0 to r1 (r0 = 0: new crater):
## height field, ground type, the touched terrain chunks, grass in the hole,
## and the men and vehicles standing there.
func _deform(pos: Vector3, r0: float, r1: float) -> void:
	var g = W.grid
	var span := r1 * 1.6
	var ix0 := clampi(int(floor((pos.x - span + g.half) / g.res)), 0, g.n - 1)
	var ix1 := clampi(int(ceil((pos.x + span + g.half) / g.res)), 0, g.n - 1)
	var iz0 := clampi(int(floor((pos.z - span + g.half) / g.res)), 0, g.n - 1)
	var iz1 := clampi(int(ceil((pos.z + span + g.half) / g.res)), 0, g.n - 1)
	var has_nat: bool = not g.nat.is_empty()
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var d := Vector2(g.vx(ix) - pos.x, g.vx(iz) - pos.z).length()
			var dh := crater_profile(d, r1) - crater_profile(d, r0)
			if dh == 0.0:
				continue
			var i: int = iz * g.n + ix
			g.heights[i] += dh
			if has_nat:
				g.nat[i] += dh
			if d < r1 * 0.8:
				g.gtype[i] = TerrainGrid.G.CRATER
			elif d < r1 * 1.2 and g.gtype[i] != TerrainGrid.G.ROAD:
				g.gtype[i] = TerrainGrid.G.DIRT
	W.map.rebuild_terrain(ix0, iz0, ix1, iz1)
	# grass tufts in the hole and on the fresh spoil
	var gc0 := Vector2i(int(floor((pos.x - r1 * 1.3) / 4.0)), int(floor((pos.z - r1 * 1.3) / 4.0)))
	var gc1 := Vector2i(int(floor((pos.x + r1 * 1.3) / 4.0)), int(floor((pos.z + r1 * 1.3) / 4.0)))
	for cz in range(gc0.y, gc1.y + 1):
		for cx in range(gc0.x, gc1.x + 1):
			for gi in W.map.grass_cells.get(Vector2i(cx, cz), []):
				var mmi: MultiMeshInstance3D = gi[0]
				if not is_instance_valid(mmi):
					continue
				var xf: Transform3D = mmi.multimesh.get_instance_transform(gi[1])
				if Vector2(xf.origin.x - pos.x, xf.origin.z - pos.z).length() < r1 * 1.3:
					mmi.multimesh.set_instance_transform(gi[1], Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin))
	for u in W.units:
		if u.vehicle == null and not u.on_board and Vector2(u.global_position.x - pos.x, u.global_position.z - pos.z).length() < span:
			u.global_position.y = g.height_at(u.global_position.x, u.global_position.z)


## Cover in the crater, rough going for vehicles; A* points updated in place.
func _crater_cells(pos: Vector3, r: float) -> void:
	var g = W.grid
	var c0: Vector2i = g.cell_of(pos.x, pos.z)
	var span := int(ceil(r / TerrainGrid.CS)) + 1
	var cov: float = AIConfig.CRATER_COVER if r >= 1.4 else AIConfig.CRATER_COVER_SMALL
	var tr: Dictionary = Db.MOBILITY["tracked"]
	var lt: Dictionary = Db.MOBILITY["light"]
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var cc := Vector2i(c0.x + dx, c0.y + dz)
			if cc.x < 1 or cc.y < 1 or cc.x >= g.cn - 1 or cc.y >= g.cn - 1:
				continue
			var w: Vector3 = g.cell_center(cc)
			if Vector2(w.x - pos.x, w.z - pos.z).length() > maxf(r * 0.9, TerrainGrid.CS * 0.75):
				continue
			var i: int = g.ci(cc)
			if g.inf_solid[i] != 0:
				continue
			dyn_cover[i] = maxf(dyn_cover[i], cov)
			if cell_pieces.has(i):
				_refresh_cell(i)
			else:
				g.cover[i] = maxf(g.cover[i], cov)
			# infantry: a little slower across broken ground
			if g.inf_weight[i] < AIConfig.CRATER_INF_W:
				g.inf_weight[i] = AIConfig.CRATER_INF_W
				g.astar_inf.set_point_weight_scale(cc, g.inf_weight[i])
			# vehicles: rough or impassable depending on size and profile
			if g.veh_solid[i] == 0:
				if r >= float(tr["crater"]):
					g.veh_solid[i] = 1
					g.astar_veh.set_point_solid(cc, true)
				else:
					g.veh_weight[i] = maxf(g.veh_weight[i], AIConfig.CRATER_VEH_W)
					g.astar_veh.set_point_weight_scale(cc, g.veh_weight[i])
			if g.veh_solid_light.size() == g.veh_solid.size() and g.veh_solid_light[i] == 0:
				if r >= float(lt["crater"]):
					g.veh_solid_light[i] = 1
					g.astar_light.set_point_solid(cc, true)
				else:
					g.astar_light.set_point_weight_scale(cc, g.veh_weight[i])


# ------------------------------------------------------------------ smoke
func _process(delta: float) -> void:
	if not W.running():
		return
	for sc in W.smoke_clouds:
		if not sc.has("dur"):
			continue
		var age: float = W.time - float(sc["t0"])
		var life: float = clampf(age / float(sc["dur"]), 0.0, 1.0)
		sc["pos"] += wind * delta
		sc["r"] = float(sc["r0"]) * (1.0 + life * AIConfig.SMOKE_GROW)
		sc["dens"] = clampf((1.0 - life) / AIConfig.SMOKE_FADE, 0.0, 1.0)
		var node = sc.get("node")
		if node != null and is_instance_valid(node):
			node.global_position += wind * delta


## How much smoke hides the line a→b: 0 clear .. 1 opaque.
func smoke_opacity(a: Vector3, b: Vector3) -> float:
	var clear := 1.0
	var d := b - a
	var L := d.length()
	if L < 0.01:
		return 0.0
	var dir := d / L
	for sc in W.smoke_clouds:
		var c: Vector3 = sc["pos"]
		var r: float = float(sc["r"])
		var k := clampf((c - a).dot(dir), 0.0, L)
		var off: float = (a + dir * k).distance_to(c) / r
		if off >= 1.0:
			continue
		clear *= 1.0 - (1.0 - off * off) * 0.97 * float(sc.get("dens", 1.0))
	return 1.0 - clear
