class_name Buildings
extends RefCounted
## Fight in buildings: a building is a set of positions, not a
## modelled interior. A man at a WINDOW POST fires out and is seen only
## through that window (TerrainGrid.win_cell), with good cover; men deeper
## inside are hidden from outside. Doors and wall breaches are the ways in.
## Data: MapManager.buildings (see _reg_building). Orders: Squad "occupy" and
## "clear_bld". Numbers — AIConfig.BLD_*.


static func at(p: Vector3):
	return W.map.building_at(p) if W.map else null


## Puts a man on a window post (frees his old one).
static func claim(u, w: Dictionary) -> void:
	release(u)
	var o = w["occupant"]
	if o != null and is_instance_valid(o) and o != u and o.is_active():
		return
	w["occupant"] = u
	u.post = w
	u.post_pending = null
	u.global_position = w["post"]
	# face out of the window
	var d: Vector3 = w["dir"]
	u.yaw = atan2(-d.x, -d.z)
	u.rotation.y = u.yaw


static func release(u) -> void:
	if u.post != null:
		if u.post["occupant"] == u:
			u.post["occupant"] = null
		u.post = null


static func free_posts(b: Dictionary) -> Array:
	var out: Array = []
	for w in b["windows"]:
		if w["occupant"] == null or not is_instance_valid(w["occupant"]) or not w["occupant"].is_active():
			out.append(w)
	return out


## Window posts ordered by how well they face `toward` (null = any order).
static func posts_facing(b: Dictionary, toward) -> Array:
	var list := free_posts(b)
	if toward is Vector3:
		var c: Vector3 = b["center"]
		var dir := (toward as Vector3) - c
		dir.y = 0.0
		dir = dir.normalized()
		list.sort_custom(func(a, z): return (a["dir"] as Vector3).dot(dir) > (z["dir"] as Vector3).dot(dir))
	return list


## Enemy garrison placed on a slot inside a building: take the nearest free
## window (or stay inside).
static func garrison(u) -> void:
	var b = at(u.global_position)
	if b == null:
		return
	var best = null
	var bd := INF
	for w in free_posts(b):
		var p: Vector3 = w["post"]
		var d: float = Vector2(p.x - u.global_position.x, p.z - u.global_position.z).length() - float(w.get("floor", 0)) * 3.0
		if d < bd:
			bd = d
			best = w
	if best != null:
		claim(u, best)
		u.slot = u.global_position


## Active men of `side` inside the building's footprint.
static func men_inside(b: Dictionary, side: int) -> Array:
	var out: Array = []
	for u in W.units:
		if u.side == side and u.is_active() and u.vehicle == null:
			var i: int = W.grid.cidx(u.global_position.x, u.global_position.z)
			if W.map.building_cell.get(i, -1) == b["id"]:
				out.append(u)
	return out


## The way in nearest to `from`: a door, or a breached wall piece of this building.
static func entry(b: Dictionary, from: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for d in b["doors"]:
		var dd: float = (d["out"] as Vector3).distance_to(from)
		if dd < bd:
			bd = dd
			best = d
	if W.field:
		for p in W.field.pieces:
			if p["kind"] == "wall" and int(p["state"]) == 2:
				var pp: Vector3 = p["pos"]
				if W.map.building_cell.get(W.grid.cidx(pp.x, pp.z), -1) != b["id"]:
					continue
				var c: Vector3 = b["center"]
				var n := (pp - c)
				n.y = 0.0
				n = n.normalized()
				var e := {"out": W.grid.ground(pp + n * 2.0), "in": W.grid.ground(pp - n * 1.2), "breach": true}
				var dd: float = (e["out"] as Vector3).distance_to(from)
				if dd < bd:
					bd = dd
					best = e
	return best


## Is a man inside under the roof (hidden from the drone above)?
static func under_roof(u) -> bool:
	var b = at(u.global_position)
	return b != null and bool(b["roof"])


## Buildings that still hold active men of `side` (nearest to `from` first).
static func held_by(side: int, from: Vector3) -> Array:
	var out: Array = []
	if W.map == null:
		return out
	for b in W.map.buildings:
		if not men_inside(b, side).is_empty():
			out.append(b)
	out.sort_custom(func(a, z): return (a["center"] as Vector3).distance_to(from) < (z["center"] as Vector3).distance_to(from))
	return out


## Both men inside the same building: they meet on the stairs and in the
## corridors (floors and rooms are not modelled) — they can see each other.
static func same(a, b) -> bool:
	var ba = at(a.global_position)
	if ba == null:
		return false
	var bb = at(b.global_position)
	return bb != null and bb["id"] == ba["id"]
