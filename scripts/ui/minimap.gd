class_name Minimap
extends Control
## North-up tactical minimap drawn from map data. Click to move the camera.

var def: MapDef


func _ready() -> void:
	custom_minimum_size = Vector2(230, 230)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_d: float) -> void:
	if not Prof.on:
		_process_body(_d)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(_d)
	Prof.add("minimap", t0)


func _process_body(_d: float) -> void:
	queue_redraw()


func w2m(p: Vector3) -> Vector2:
	var half = def.size * 0.5
	return Vector2((p.x + half) / def.size * size.x, (p.z + half) / def.size * size.y)


func v2m(p: Vector2) -> Vector2:
	return w2m(Vector3(p.x, 0, p.y))


var _drag := false   # the press was on the minimap (a box selection passing over it must not move the camera)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_drag = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if W.command and W.command.lmb_down:
			return
		_drag = true
		var mp: Vector2 = event.position
		var half = def.size * 0.5
		var wp = Vector3(mp.x / size.x * def.size - half, 0, mp.y / size.y * def.size - half)
		W.cam.follow = null
		W.cam.focus_t = wp
		accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and _drag:
		var mp: Vector2 = event.position
		var half = def.size * 0.5
		W.cam.focus_t = Vector3(mp.x / size.x * def.size - half, 0, mp.y / size.y * def.size - half)
		accept_event()


func _draw() -> void:
	if def == null:
		return
	var f: Font = UIK.font if UIK.font else get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.15, 0.10, 0.95))
	var k = size.x / def.size
	for tl in def.treelines:
		var r: Rect2 = tl["rect"]
		draw_rect(Rect2(v2m(r.position), r.size * k), Color(0.10, 0.22, 0.10, 0.95))
	for road in def.roads:
		var pts: PackedVector2Array = road["pts"]
		for i in pts.size() - 1:
			draw_line(v2m(pts[i]), v2m(pts[i + 1]), Color(0.45, 0.38, 0.28), maxf(1.0, float(road["w"]) * k * 0.6))
	for tr in def.trenches:
		for i in tr.size() - 1:
			draw_line(v2m(tr[i]), v2m(tr[i + 1]), Color(0.08, 0.06, 0.04), 2.0)
	for wl in def.wire:
		for i in wl.size() - 1:
			draw_dashed_line(v2m(wl[i]), v2m(wl[i + 1]), Color(0.6, 0.6, 0.6, 0.6), 1.0, 3.0)
	for h in def.houses:
		draw_rect(Rect2(v2m(h["pos"] - h["size"] * 0.5), h["size"] * k), Color(0.55, 0.53, 0.5))
	for h in def.sheds:
		draw_rect(Rect2(v2m(h["pos"] - h["size"] * 0.5), h["size"] * k), Color(0.45, 0.43, 0.4))
	var obj: Rect2 = def.objective_rect
	var o0 = v2m(obj.position)
	var o1 = v2m(obj.end)
	var orc = Rect2(o0, o1 - o0)
	draw_rect(orc, Color(UIK.ACCENT, 0.08))
	draw_rect(orc, Color(UIK.ACCENT, 0.7), false, 1.0)
	# camera footprint
	var cam = get_viewport().get_camera_3d()
	if cam:
		var vs = get_viewport().get_visible_rect().size
		var poly = PackedVector2Array()
		for c in [Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y), Vector2(0, vs.y)]:
			var o = cam.project_ray_origin(c)
			var d = cam.project_ray_normal(c)
			var t = 400.0
			if d.y < -0.01:
				t = minf(400.0, (o.y - 0.0) / -d.y)
			poly.append(w2m(o + d * t).clamp(Vector2(-20, -20), size + Vector2(20, 20)))
		poly.append(poly[0])
		draw_polyline(poly, Color(1, 1, 1, 0.5), 1.0)
	# EW jamming zones (known jammers) and our drone
	if W.ew:
		for st in W.ew.stations:
			if st.destroyed or not st.ever_seen:
				continue
			var sp = w2m(st.global_position)
			draw_arc(sp, st.radius * k * 0.55, 0, TAU, 32, Color(UIK.ENEMY, 0.25), 1.0)
			draw_arc(sp, st.radius * k, 0, TAU, 32, Color(UIK.ENEMY, 0.12), 1.0)
			draw_string(f, sp + Vector2(4, -3), Loc.t("РЕБ"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIK.ENEMY)
		if cam:
			var dp = w2m(cam.global_position)
			var lk: float = W.ew.link
			var dc = UIK.GOOD if lk >= EwSystem.DEGRADED else (UIK.WOUND if lk > 0.35 else UIK.ALERT)
			draw_line(dp, w2m(W.cam.look_point), Color(dc, 0.5), 1.0)
			var hd := Vector2(-sin(W.cam.yaw), -cos(W.cam.yaw))
			var hr := Vector2(-hd.y, hd.x)
			draw_colored_polygon(PackedVector2Array([dp + hd * 7.0, dp - hd * 4.0 + hr * 4.0, dp - hd * 4.0 - hr * 4.0]), dc)
			draw_string(f, dp + Vector2(6, 10), Loc.t("БПЛА %dм") % int(W.cam.altitude()), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dc)
	if W.mines:
		for m in W.mines.mines:
			if m["revealed"] and m["alive"]:
				draw_circle(w2m(m["pos"]), 1.3, Color(1.0, 0.35, 0.2))
	# units
	for b in W.bunkers:
		if b.ever_seen and not b.destroyed:
			var p = w2m(b.global_position)
			draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), UIK.ENEMY, false, 1.5)
	for u in W.units:
		if u.evacuated or u.vehicle != null or u.on_board:
			continue
		var p = w2m(u.global_position)
		if u.side == 0:
			if u.health == Soldier.H.DEAD:
				continue
			var col = UIK.FRIEND
			if u.health == Soldier.H.INCAP:
				col = UIK.INCAP
			elif u.health == Soldier.H.WOUNDED:
				col = UIK.WOUND
			draw_circle(p, 2.2 if not u.selected else 3.0, col)
		elif u.health < Soldier.H.INCAP and u.model.visible:
			draw_circle(p, 2.4, UIK.ENEMY)
			if u.marked:
				draw_arc(p, 5.0, 0, TAU, 12, UIK.ENEMY, 1.0)
	# contacts not in view: reported positions only, fading with confidence
	if W.intel:
		for e in W.intel.contacts.keys():
			var c: Dictionary = W.intel.contacts[e]
			var st: int = c["status"]
			if st == IntelSystem.S.DESTROYED or st == IntelSystem.S.LOST:
				continue
			if st == IntelSystem.S.CONFIRMED and is_instance_valid(e) and e is Soldier and e.model.visible:
				continue
			var cp = w2m(c["pos"])
			var a: float = 0.25 + W.intel.confidence(c) * 0.6
			var col: Color = Color(UIK.WOUND, a) if st == IntelSystem.S.UNVERIFIED else Color(UIK.ENEMY, a)
			draw_arc(cp, 2.6, 0, TAU, 8, col, 1.2)
	for v in W.vehicles:
		if v.offmap:
			continue
		var p = w2m(v.global_position)
		var col = UIK.FRIEND if v.side == 0 else UIK.ENEMY
		if v.state == "destroyed":
			col = Color(0.4, 0.4, 0.4)
		elif v.is_medevac:
			col = Color(1.0, 0.65, 0.25)
		draw_rect(Rect2(p - Vector2(3.5, 3.5), Vector2(7, 7)), col)
	draw_rect(Rect2(Vector2.ZERO, size), UIK.LINE, false, 1.0)
	draw_string(f, Vector2(6, 14), Loc.t("Пн ▲"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIK.DIM)
