class_name MineSystem
extends Node
## Enemy minefields: anti-personnel strips in front of the trenches and a few
## anti-tank mines on vehicle approaches, with gaps the enemy uses himself.
## Mines are hidden until spotted by the drone, by soldiers close by, or
## revealed by a detonation. Spotted mines are avoided by path-finding.

var mines: Array = []      # {pos, type, alive, revealed, node}
var buckets := {}          # grid cell index -> Array of mine indices
var triggered := 0
var _scan_t := 1.0
var _warned_fields := {}
var m_ap: Material
var m_at: Material


func setup(def: MapDef) -> void:
	m_ap = MF.mat(Color(0.20, 0.26, 0.15))
	m_at = MF.mat(Color(0.30, 0.33, 0.22), 0.7, 0.2)
	var rng = RandomNumberGenerator.new()
	rng.seed = def.seed + 303
	for fi in def.minefields.size():
		var f: Dictionary = def.minefields[fi]
		var pts: PackedVector2Array = f["pts"]
		var w: float = f["w"]
		for k in pts.size() - 1:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var L = a.distance_to(b)
			var dir = (b - a) / L
			var nrm = Vector2(-dir.y, dir.x)
			var count = int(round(L * w * float(f["density"])))
			for i in count:
				var p = a + dir * rng.randf_range(0.0, L) + nrm * rng.randf_range(-w * 0.5, w * 0.5)
				_add(Vector3(p.x, 0, p.y), f["type"], fi)


func _add(p: Vector3, type: String, field: int) -> void:
	var g = W.grid
	p = g.ground(p)
	var node = MeshInstance3D.new()
	if type == "at":
		node.mesh = MF.cyl(0.17, 0.17, 0.09, 8)
		node.material_override = m_at
	else:
		node.mesh = MF.cyl(0.07, 0.07, 0.06, 6)
		node.material_override = m_ap
	node.position = p + Vector3(0, 0.03, 0)
	node.visible = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	var idx = mines.size()
	mines.append({"pos": p, "type": type, "alive": true, "revealed": false, "node": node, "field": field})
	var c: int = g.cidx(p.x, p.z)
	if not buckets.has(c):
		buckets[c] = []
	buckets[c].append(idx)


func _near(p: Vector3, r: float) -> Array:
	var g = W.grid
	var out: Array = []
	var cr = int(ceil(r / TerrainGrid.CS))
	var c0 = g.cell_of(p.x, p.z)
	for dz in range(-cr, cr + 1):
		for dx in range(-cr, cr + 1):
			var cc = Vector2i(c0.x + dx, c0.y + dz)
			if cc.x < 0 or cc.y < 0 or cc.x >= g.cn or cc.y >= g.cn:
				continue
			var ci: int = g.ci(cc)
			if buckets.has(ci):
				for mi in buckets[ci]:
					if mines[mi]["alive"]:
						out.append(mi)
	return out


## Called by moving friendly soldiers.
func check_soldier(u) -> void:
	var c: int = W.grid.cidx(u.global_position.x, u.global_position.z)
	if not buckets.has(c):
		return
	for mi in buckets[c]:
		var m: Dictionary = mines[mi]
		if not m["alive"]:
			continue
		var r = 0.75 if m["type"] == "ap" else 0.3
		if Vector2(m["pos"].x - u.global_position.x, m["pos"].z - u.global_position.z).length() < r:
			_detonate(mi, u)
			return


## Called by moving friendly vehicles.
func check_vehicle(v) -> void:
	for mi in _near(v.global_position, 3.0):
		var m: Dictionary = mines[mi]
		var d = Vector2(m["pos"].x - v.global_position.x, m["pos"].z - v.global_position.z).length()
		if (m["type"] == "at" and d < 2.4) or (m["type"] == "ap" and d < 1.8):
			_detonate(mi, v)
			return


func _detonate(mi: int, victim) -> void:
	var m: Dictionary = mines[mi]
	m["alive"] = false
	m["node"].visible = false
	triggered += 1
	var src = W.combat._virtual_source(1)
	var pos: Vector3 = m["pos"]
	if m["type"] == "at":
		W.combat.explosion(pos, 4.5, 130.0, src, "mine")
		if victim is Vehicle:
			victim.take_damage(280.0, "at", src)
			if victim.state != "destroyed":
				victim.state = "immobile"
				victim.stop()
			Events.msg(Loc.t("%s підірвалась на протитанковій міні!") % victim.vname, "alert")
	else:
		W.combat.explosion(pos, 2.4, 70.0, src, "mine")
		if victim is Soldier and victim.health < Soldier.H.INCAP:
			W.damage.apply(victim, randf_range(90.0, 160.0), src, true)
		if victim is Vehicle:
			victim.take_damage(30.0, "he", src)
		Events.msg(Loc.t("Підрив на протипіхотній міні! Мінне поле — обережно."), "alert")
	for mj in _near(pos, 7.0):
		reveal(mj, false)


func reveal(mi: int, announce: bool = true) -> void:
	var m: Dictionary = mines[mi]
	if m["revealed"] or not m["alive"]:
		return
	m["revealed"] = true
	m["node"].visible = true
	var g = W.grid
	var c = g.cell_of(m["pos"].x, m["pos"].z)
	var i: int = g.ci(c)
	if m["type"] == "ap":
		g.inf_weight[i] = 12.0
		g.astar_inf.set_point_weight_scale(c, 12.0)
	else:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var cc = Vector2i(c.x + dx, c.y + dz)
				if cc.x >= 0 and cc.y >= 0 and cc.x < g.cn and cc.y < g.cn and g.veh_solid[g.ci(cc)] == 0:
					g.astar_veh.set_point_weight_scale(cc, 30.0)
	var f: int = m["field"]
	if announce and not _warned_fields.has(f):
		_warned_fields[f] = true
		Events.msg(Loc.t("Виявлено %s. Позначено на карті, маршрути їх оминають.") % (Loc.t("протитанкові міни") if m["type"] == "at" else Loc.t("мінне поле")), "warn")


func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("mines", t0)


func _process_body(delta: float) -> void:
	if not W.running():
		return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = 0.6
	# soldiers notice mines right in front of them
	for u in W.units:
		if u.side != 0 or not u.is_active() or not u.moving:
			continue
		for mi in _near(u.global_position, 3.5):
			if not mines[mi]["revealed"] and randf() < 0.1:
				reveal(mi)
	# the drone camera spots surface-laid mines it looks at from close enough
	if W.ew and W.ew.drone_down:
		return
	var cam = W.cam.cam if W.cam else null
	if cam == null:
		return
	var link: float = W.ew.link if W.ew else 1.0
	var vp = get_viewport().get_visible_rect().size
	for mi in mines.size():
		var m: Dictionary = mines[mi]
		if m["revealed"] or not m["alive"]:
			continue
		var p: Vector3 = m["pos"]
		var deff: float = cam.global_position.distance_to(p) / pow(W.cam.zoom, 0.7)
		if deff > 75.0 or cam.is_position_behind(p):
			continue
		var sp = cam.unproject_position(p)
		if sp.x < 0 or sp.y < 0 or sp.x > vp.x or sp.y > vp.y:
			continue
		var ch = (0.05 if m["type"] == "at" else 0.02) * link * (1.0 - deff / 90.0)
		if randf() < ch:
			reveal(mi)
