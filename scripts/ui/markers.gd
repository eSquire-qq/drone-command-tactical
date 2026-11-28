class_name Markers
extends Control
## Screen-space tactical overlay: IFF markers, wounded, marked targets,
## last-known positions, order lines, support tool cursor, selection box.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_d: float) -> void:
	if not Prof.on:
		_process_body(_d)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(_d)
	Prof.add("markers", t0)


func _process_body(_d: float) -> void:
	queue_redraw()


func _sp(p: Vector3):
	var c = get_viewport().get_camera_3d()
	if c == null or c.is_position_behind(p):
		return null
	return c.unproject_position(p)


func _draw() -> void:
	if W.mission == null or not (W.mission.phase == MissionManager.Phase.DEPLOY or W.mission.phase == MissionManager.Phase.COMBAT):
		return
	if W.ew and W.ew.drone_down:
		return
	var f: Font = UIK.font if UIK.font else get_theme_default_font()
	var cmd = W.command
	var blink = fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.5
	_draw_vision()
	# objective zone outline
	var r: Rect2 = W.mission.def.objective_rect
	var corners = [Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, 0, r.position.y), Vector3(r.end.x, 0, r.end.y), Vector3(r.position.x, 0, r.end.y)]
	var pts: Array = []
	for c in corners:
		var sp = _sp(W.grid.ground(c) + Vector3(0, 0.5, 0))
		if sp == null:
			pts.clear()
			break
		pts.append(sp)
	if pts.size() == 4 and W.mission.objectives.type() in ["capture", "hold"]:
		for i in 4:
			draw_dashed_line(pts[i], pts[(i + 1) % 4], Color(UIK.ACCENT, 0.35), 1.5, 10.0)
		draw_string(f, pts[0] + Vector2(4, -6), Loc.t("ОБ'ЄКТ: ОПОРНИЙ ПУНКТ"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UIK.ACCENT, 0.7))
	# friendly squads: order lines + labels
	for sq in W.squads:
		if sq.side != 0 or sq.kind == "medevac":
			continue
		var c3: Vector3 = sq.center()
		var csp = _sp(c3 + Vector3(0, 4.2, 0))
		if sq.selected and sq.order in ["move", "assault", "retreat", "hold", "occupy", "clear_bld"] and not sq.mounted:
			var a = _sp(c3 + Vector3(0, 0.3, 0))
			var b = _sp(sq.order_pos + Vector3(0, 0.3, 0))
			if a != null and b != null:
				var col = UIK.FRIEND if sq.order != "assault" else UIK.ACCENT
				draw_dashed_line(a, b, Color(col, 0.7), 1.5, 8.0)
				draw_circle(b, 4.0, col)
		var waiting: bool = sq.mounted and sq.vehicle != null and sq.vehicle.offmap
		if csp != null and not waiting and (sq.active_count() > 0 or sq.mounted):
			var col = UIK.FRIEND if not sq.selected else Color(0.7, 0.92, 1.0)
			var txt: String = sq.short
			if sq.mounted:
				txt += Loc.t(" [ДЕСАНТ]")
			draw_string(f, csp + Vector2(-20, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
			if W.time - sq.help_time < 8.0 and blink:
				draw_arc(csp + Vector2(0, -4), 16.0, 0, TAU, 20, UIK.ALERT, 2.0)
				draw_string(f, csp + Vector2(-26, -24), Loc.t("ДОПОМОГА!"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIK.ALERT)
	# soldiers
	for u in W.units:
		if u.evacuated or u.vehicle != null or u.on_board:
			continue
		if u.side == 0:
			if u.health == Soldier.H.DEAD:
				var sp = _sp(u.global_position + Vector3(0, 0.6, 0))
				if sp != null:
					_draw_x(sp, 4.0, Color(0.6, 0.6, 0.6, 0.6))
				continue
			var sp = _sp(u.global_position + Vector3(0, 2.75, 0))
			if sp == null:
				continue
			if u.health == Soldier.H.INCAP:
				var wp = _sp(u.global_position + Vector3(0, 1.2, 0))
				if wp == null:
					continue
				var col = UIK.INCAP
				draw_circle(wp, 9.0, Color(0, 0, 0, 0.55))
				draw_line(wp + Vector2(-6, 0), wp + Vector2(6, 0), col, 3.0)
				draw_line(wp + Vector2(0, -6), wp + Vector2(0, 6), col, 3.0)
				var lbl = "%s %s" % [UIK.mmss(u.bleed), Loc.t("ЕВАК") if u.evac_marked else ""]
				if u.carried:
					lbl = Loc.t("ВИНОСЯТЬ")
				draw_string(f, wp + Vector2(11, 5), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
				if cmd.sel_wounded.has(u):
					draw_arc(wp, 14.0, 0, TAU, 20, Color(1, 1, 1), 2.0)
				continue
			var col = UIK.FRIEND
			if u.role == "crew_medic":
				col = Color(1.0, 0.65, 0.25)
			elif u.health == Soldier.H.WOUNDED:
				col = UIK.WOUND
			elif u.broken:
				col = Color(0.8, 0.5, 1.0)
			var s = 5.0 if not u.selected else 6.5
			var tri = PackedVector2Array([sp + Vector2(-s, -s), sp + Vector2(s, -s), sp + Vector2(0, s * 0.4)])
			draw_primitive(tri, PackedColorArray([col, col, col]), PackedVector2Array())
			if u.suppression > 60.0:
				draw_arc(sp + Vector2(0, -2), 9.0, PI * 1.1, PI * 1.9, 6, Color(UIK.ALERT, 0.8), 1.5)
			if u.selected and u.solo != "" and u.moving:
				var fa = _sp(u.global_position + Vector3(0, 0.3, 0))
				var fb = _sp(u.slot + Vector3(0, 0.3, 0))
				if fa != null and fb != null:
					draw_dashed_line(fa, fb, Color(col, 0.6), 1.0, 6.0)
					draw_circle(fb, 3.0, col)
			if u.evac_marked:
				draw_string(f, sp + Vector2(8, 4), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIK.WOUND)
		else:
			if u.health >= Soldier.H.INCAP:
				continue
			if u.model.visible:
				var sp = _sp(u.global_position + Vector3(0, 2.7, 0))
				if sp == null:
					continue
				var s = 6.0
				var dia = PackedVector2Array([sp + Vector2(0, -s), sp + Vector2(s, 0), sp + Vector2(0, s), sp + Vector2(-s, 0)])
				var ec = Color(UIK.ENEMY, 0.9)
				draw_primitive(dia, PackedColorArray([ec, ec, ec, ec]), PackedVector2Array())
				if u.marked:
					var bp = _sp(u.global_position + Vector3(0, 1.0, 0))
					_draw_brackets(bp, 16.0, UIK.ENEMY)
					draw_string(f, bp + Vector2(18, -10), Loc.t("ЦІЛЬ"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIK.ENEMY)
	# what the commander knows: contacts that are not in view right now
	_draw_contacts(f)
	# enemy EW posts
	if W.ew:
		for st in W.ew.stations:
			if st.destroyed or not st.ever_seen:
				continue
			var ssp = _sp(st.global_position + Vector3(0, 8.0, 0))
			if ssp != null:
				draw_rect(Rect2(ssp - Vector2(9, 7), Vector2(18, 14)), UIK.ENEMY, false, 2.0)
				draw_string(f, ssp + Vector2(12, 5), Loc.t("РЕБ"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIK.ENEMY)
				if st.marked:
					_draw_brackets(_sp(st.global_position + Vector3(0, 1, 0)), 20.0, UIK.ENEMY)
			var ring: Array = []
			for i in 40:
				var a = TAU * i / 40.0
				var gp = W.grid.ground(st.global_position + Vector3(cos(a), 0, sin(a)) * st.radius * 0.55) + Vector3(0, 0.4, 0)
				ring.append(_sp(gp))
			for i in ring.size():
				var a1 = ring[i]
				var b1 = ring[(i + 1) % ring.size()]
				if a1 != null and b1 != null and i % 2 == 0:
					draw_line(a1, b1, Color(UIK.ENEMY, 0.35), 1.5)
	# bunkers
	for b in W.bunkers:
		if b.destroyed or not b.ever_seen:
			continue
		var sp = _sp(b.global_position + Vector3(0, 3.2, 0))
		if sp == null:
			continue
		var col = UIK.ENEMY
		draw_rect(Rect2(sp - Vector2(9, 7), Vector2(18, 14)), col, false, 2.0)
		draw_string(f, sp + Vector2(12, 5), b.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		if b.marked:
			_draw_brackets(_sp(b.global_position + Vector3(0, 1, 0)), 24.0, col)
	# vehicles
	for v in W.vehicles:
		if v.offmap or (v.side == 1 and not v.visible):
			continue
		var sp = _sp(v.global_position + Vector3(0, 3.6, 0))
		if sp == null:
			continue
		if v.state == "destroyed":
			_draw_x(sp, 6.0, Color(0.6, 0.6, 0.6, 0.6))
			continue
		var col = UIK.FRIEND if v.side == 0 else UIK.ENEMY
		if v.is_medevac:
			col = Color(1.0, 0.65, 0.25)
		if v.selected:
			col = Color(0.7, 0.92, 1.0)
		draw_rect(Rect2(sp - Vector2(10, 6), Vector2(20, 12)), col, false, 2.0)
		draw_line(sp + Vector2(-10, 6), sp + Vector2(10, -6), col, 1.0)
		draw_string(f, sp + Vector2(14, 5), v.vname, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		if v.hp < v.max_hp:
			var k: float = v.hp / v.max_hp
			draw_rect(Rect2(sp + Vector2(-10, 9), Vector2(20, 3)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(sp + Vector2(-10, 9), Vector2(20 * k, 3)), UIK.GOOD.lerp(UIK.ALERT, 1.0 - k))
		if v.selected and v.moving and v.path.size() > 0:
			var a = _sp(v.global_position + Vector3(0, 0.3, 0))
			var bpt = _sp(v.path[v.path.size() - 1] + Vector3(0, 0.3, 0))
			if a != null and bpt != null:
				draw_dashed_line(a, bpt, Color(UIK.FRIEND, 0.7), 1.5, 8.0)
	# known mines
	if W.mines:
		for m in W.mines.mines:
			if not m["revealed"] or not m["alive"]:
				continue
			var mp = _sp(m["pos"] + Vector3(0, 0.3, 0))
			if mp != null:
				var mc := Color(1.0, 0.35, 0.2, 0.9)
				_draw_x(mp, 4.0 if m["type"] == "ap" else 6.0, mc)
				if m["type"] == "at":
					draw_string(f, mp + Vector2(7, 4), Loc.t("ТМ"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, mc)
	# prisoners
	if W.prisoners:
		for u in W.prisoners.prisoners:
			if not is_instance_valid(u):
				continue
			var pp = _sp(u.global_position + Vector3(0, 2.7, 0))
			if pp != null:
				draw_rect(Rect2(pp - Vector2(6, 6), Vector2(12, 12)), Color(0.95, 0.95, 0.95), false, 2.0)
				draw_string(f, pp + Vector2(10, 5), Loc.t("ПОЛОНЕНИЙ"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.95, 0.95))
	# the enemy recon drone, once our men have spotted it
	for d in get_tree().get_nodes_in_group("recon"):
		if not d.revealed:
			continue
		var sp = _sp(d.global_position)
		if sp == null:
			continue
		if blink:
			draw_arc(sp, 15.0, 0, TAU, 18, UIK.ENEMY, 2.0)
		draw_rect(Rect2(sp - Vector2(6, 6), Vector2(12, 12)), UIK.ENEMY, false, 1.5)
		draw_string(f, sp + Vector2(14, -6), Loc.t("РОЗВІДДРОН"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIK.ENEMY)
	# FPV drones in the air
	for d in get_tree().get_nodes_in_group("fpv"):
		var sp = _sp(d.global_position)
		if sp == null:
			continue
		var col = UIK.ENEMY if d.side == 1 else UIK.FRIEND
		if d.side == 1 and blink:
			draw_arc(sp, 13.0, 0, TAU, 16, col, 2.0)
		draw_rect(Rect2(sp - Vector2(5, 5), Vector2(10, 10)), col, false, 1.5)
		draw_string(f, sp + Vector2(12, -6), Loc.t("FPV %dс") % int(d.eta()), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	# order markers
	for m in cmd.order_markers:
		var sp = _sp(m["pos"] + Vector3(0, 0.3, 0))
		if sp == null:
			continue
		var k: float = clampf(m["t"], 0.0, 1.0)
		var col = UIK.FRIEND
		match m["kind"]:
			"assault":
				col = UIK.ACCENT
			"hold":
				col = UIK.GOOD
			"mortar", "smoke":
				col = UIK.ALERT if m["kind"] == "mortar" else Color(0.85, 0.85, 0.85)
		draw_arc(sp, 10.0 + (1.0 - k) * 14.0, 0, TAU, 24, Color(col, k), 2.0)
	# support tool cursor
	if cmd.tool != "" and cmd.hover_point != null:
		var hp: Vector3 = cmd.hover_point
		var rad = 7.0 if cmd.tool == "mortar" else (10.0 if cmd.tool == "smoke" else 2.0)
		var ring: Array = []
		for i in 24:
			var a = TAU * i / 24.0
			var sp = _sp(W.grid.ground(hp + Vector3(cos(a), 0, sin(a)) * rad) + Vector3(0, 0.2, 0))
			if sp != null:
				ring.append(sp)
		var col = UIK.ALERT if cmd.tool != "smoke" else Color(0.9, 0.9, 0.9)
		for i in ring.size():
			draw_line(ring[i], ring[(i + 1) % ring.size()], col, 1.5)
		var c = _sp(hp)
		if c != null:
			draw_line(c + Vector2(-14, 0), c + Vector2(14, 0), col, 1.0)
			draw_line(c + Vector2(0, -14), c + Vector2(0, 14), col, 1.0)
			var names = {"mortar": Loc.t("МІНОМЕТ"), "fpv": Loc.t("FPV — ЛКМ ПО ЦІЛІ"), "smoke": Loc.t("ДИМ")}
			draw_string(f, c + Vector2(16, -16), names[cmd.tool], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	# selection box / formation line
	if cmd.dragging:
		draw_rect(cmd.box_rect, Color(UIK.FRIEND, 0.12), true)
		draw_rect(cmd.box_rect, Color(UIK.FRIEND, 0.8), false, 1.0)
	_draw_preview(f)
	# where each man of the selected squads is heading now
	for u in W.units:
		if u.side == 0 and u.selected and u.moving and u.is_active():
			var ds = _sp(u.slot + Vector3(0, 0.2, 0))
			if ds != null:
				draw_arc(ds, 3.5, 0, TAU, 10, Color(UIK.FRIEND, 0.75), 1.5)


## Intelligence contacts (W.intel): drawn at the REPORTED position, never the
## true one; each status has its own look so reliability reads at a glance.
func _draw_contacts(f: Font) -> void:
	if W.intel == null:
		return
	for e in W.intel.contacts.keys():
		var c: Dictionary = W.intel.contacts[e]
		var st: int = c["status"]
		if st == IntelSystem.S.CONFIRMED and is_instance_valid(e) and e is Soldier and e.model.visible:
			continue   # in view: the live diamond is drawn already
		var p: Vector3 = c["pos"]
		var sp = _sp(W.grid.ground(p) + Vector3(0, 1.8, 0))
		if sp == null:
			continue
		var age: float = W.time - float(c["t"])
		var conf: float = W.intel.confidence(c)
		var col := Color(UIK.ENEMY, 0.25 + conf * 0.65)
		var age_txt := Loc.t("%d с") % int(age) if age < 100.0 else Loc.t("%d хв") % int(age / 60.0)
		match st:
			IntelSystem.S.CONFIRMED, IntelSystem.S.PROBABLE:
				var s := 6.0
				var dia := PackedVector2Array([sp + Vector2(0, -s), sp + Vector2(s, 0), sp + Vector2(0, s), sp + Vector2(-s, 0), sp + Vector2(0, -s)])
				draw_polyline(dia, col, 2.0)
				if float(c["err"]) > 2.0:
					_ground_ring(p, float(c["err"]), Color(UIK.ENEMY, 0.35 * conf + 0.1))
				draw_string(f, sp + Vector2(9, 4), "~%s" % age_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
			IntelSystem.S.LAST_KNOWN:
				draw_string(f, sp + Vector2(-4, 5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
				draw_string(f, sp + Vector2(8, 4), Loc.t("%s тому") % age_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
			IntelSystem.S.UNVERIFIED:
				_ground_ring(p, float(c["err"]), Color(UIK.WOUND, 0.4), true)
				draw_string(f, sp + Vector2(-4, 5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(UIK.WOUND, 0.75))
				draw_string(f, sp + Vector2(8, 4), Loc.t("постріли"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UIK.WOUND, 0.7))
			IntelSystem.S.LOST:
				draw_string(f, sp + Vector2(-4, 5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UIK.ENEMY, 0.18))
			IntelSystem.S.DESTROYED:
				_draw_x(sp, 5.0, Color(0.75, 0.75, 0.75, 0.7))
				draw_string(f, sp + Vector2(8, 4), Loc.t("уражено"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.75, 0.75, 0.6))
		if e is Soldier and is_instance_valid(e) and e.marked and st != IntelSystem.S.DESTROYED:
			_draw_brackets(sp, 14.0, Color(UIK.ENEMY, conf * 0.8 + 0.2))


## Error circle on the ground (dashed for unverified reports).
func _ground_ring(p: Vector3, r: float, col: Color, dashed: bool = false) -> void:
	var pts: Array = []
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(_sp(W.grid.ground(p + Vector3(cos(a), 0, sin(a)) * r) + Vector3(0, 0.3, 0)))
	for i in pts.size():
		if dashed and i % 2 == 1:
			continue
		var a1 = pts[i]
		var b1 = pts[(i + 1) % pts.size()]
		if a1 != null and b1 != null:
			draw_line(a1, b1, col, 1.2)


func _draw_x(p: Vector2, s: float, c: Color) -> void:
	draw_line(p + Vector2(-s, -s), p + Vector2(s, s), c, 1.5)
	draw_line(p + Vector2(-s, s), p + Vector2(s, -s), c, 1.5)


func _draw_brackets(p, s: float, c: Color) -> void:
	if p == null:
		return
	var q: Vector2 = p
	var k = s * 0.4
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner = q + Vector2(sx * s, sy * s)
			draw_line(corner, corner - Vector2(sx * k, 0), c, 2.0)
			draw_line(corner, corner - Vector2(0, sy * k), c, 2.0)


# ------------------------------------------------------------------ vision preview (F1)
var _vq: Array = []            # ground quads seen
var _vq_order := false         # from the order point (else from the unit)
var _vq_key := ""
var _vq_t := 0


## The ground the selected unit sees now, or — while an order is being placed —
## would see from the order point. Recomputed at most twice a second.
func _update_vision() -> void:
	var cmd = W.command
	var now := Time.get_ticks_msec()
	if not bool(Game.settings.get("vision_preview", true)) or cmd.selection.size() != 1 or cmd.tool != "" or cmd.dragging:
		_vq = []
		_vq_key = ""
		return
	var o = cmd.selection[0]
	var eye = null
	var order := false
	if (o is Squad or o is Soldier) and o.side == 0:
		var sq = o if o is Squad else o.squad
		if o is Squad and sq.mounted:
			return
		if cmd.hover_point != null and cmd.mode in ["move", "hold", "assault", "bound", "clear"] and get_viewport().gui_get_hovered_control() == null:
			eye = W.grid.ground(cmd.hover_point) + Vector3(0, 1.5, 0)
			order = true
		elif o is Squad and o.active_count() > 0:
			eye = W.grid.ground(o.center()) + Vector3(0, 1.5, 0)
		elif o is Soldier and o.is_active():
			eye = o.eye_point()
	elif o is Vehicle and o.side == 0 and o.state != "destroyed":
		if cmd.hover_point != null and cmd.mode in ["move", "assault"] and get_viewport().gui_get_hovered_control() == null:
			eye = W.grid.ground(cmd.hover_point) + Vector3(0, 2.6, 0)
			order = true
		else:
			eye = o.global_position + Vector3(0, 2.6, 0)
	if eye == null:
		_vq = []
		_vq_key = ""
		return
	var key := "%s|%s" % [order, (eye as Vector3).snapped(Vector3.ONE * 2.0)]
	if key == _vq_key or now - _vq_t < 500:
		return
	_vq_key = key
	_vq_t = now
	_vq_order = order
	var t0 := Time.get_ticks_usec()
	_vq = VisionPreview.quads(eye, VisionPreview.compute(eye))
	if Prof.on:
		Prof.add("vision", t0)


func _draw_vision() -> void:
	_update_vision()
	if _vq.is_empty():
		return
	var col := Color(UIK.GOOD, 0.13) if _vq_order else Color(UIK.FRIEND, 0.09)
	var c = get_viewport().get_camera_3d()
	if c == null:
		return
	var sz := get_viewport_rect().size
	var cols := PackedColorArray([col])
	for q in _vq:
		var pts := PackedVector2Array()
		var ok := true
		var inside := false
		for p in q:
			if c.is_position_behind(p):
				ok = false
				break
			var sp := c.unproject_position(p + Vector3(0, 0.15, 0))
			if sp.x > -50 and sp.y > -50 and sp.x < sz.x + 50 and sp.y < sz.y + 50:
				inside = true
			pts.append(sp)
		if not ok or not inside:
			continue
		# a wedge seen edge-on collapses to a line: skip it (triangulation fails)
		var area := absf((pts[2] - pts[0]).cross(pts[3] - pts[1])) * 0.5
		if area < 1.0:
			continue
		draw_primitive(pts, cols, PackedVector2Array())


# ------------------------------------------------------------------ order preview
var _pv: Array = []
var _pv_key := ""
var _pv_t := 0


## Before the order: from each selected unit a dashed line to where it goes
## and a mark where every man (or the vehicle) will stand — as in RTS games.
func _draw_preview(f: Font) -> void:
	var cmd = W.command
	if not bool(Game.settings.get("move_preview", true)) or cmd.selection.is_empty() or cmd.tool != "" or cmd.dragging:
		return
	var gp = cmd.hover_point
	var le = null
	if cmd.rmb_drag and cmd.rline_start != null:
		gp = cmd.rline_start
		le = cmd.hover_point
	if gp == null:
		return
	var key := "%s|%s|%s|%d" % [cmd.mode, (gp as Vector3).snapped(Vector3.ONE * 0.5), le, cmd.selection.size()]
	var now := Time.get_ticks_msec()
	if key != _pv_key and now - _pv_t > 90:
		_pv_key = key
		_pv_t = now
		_pv = cmd.preview(gp, le)
	var col: Color = {"move": UIK.FRIEND, "assault": UIK.ACCENT, "hold": UIK.GOOD, "clear": UIK.ACCENT, "bound": UIK.ACCENT,
		"suppress": UIK.ALERT}.get(cmd.mode, UIK.FRIEND)
	for d in _pv:
		var a = _sp(d["from"] + Vector3(0, 0.3, 0))
		var b = _sp(W.grid.ground(d["to"]) + Vector3(0, 0.3, 0))
		if cmd.mode == "suppress":
			if b != null:
				draw_arc(b, 16.0, 0, TAU, 24, Color(col, 0.8), 1.5)
				draw_line(b + Vector2(-22, 0), b + Vector2(22, 0), Color(col, 0.8), 1.0)
				draw_line(b + Vector2(0, -22), b + Vector2(0, 22), Color(col, 0.8), 1.0)
			if a != null and b != null:
				draw_dashed_line(a, b, Color(col, 0.45), 1.0, 5.0)
			continue
		if a != null and b != null:
			draw_dashed_line(a, b, Color(col, 0.55), 1.5, 7.0)
		for sl in d["slots"]:
			var p = _sp(sl + Vector3(0, 0.15, 0))
			if p == null:
				continue
			if d["vehicle"]:
				draw_rect(Rect2(p - Vector2(9, 6), Vector2(18, 12)), Color(col, 0.85), false, 2.0)
			else:
				draw_circle(p, 4.0, Color(col, 0.35))
				draw_arc(p, 4.5, 0, TAU, 12, Color(col, 0.95), 1.5)
	var mp := get_local_mouse_position()
	var names := {"move": Loc.t("РУХ"), "assault": Loc.t("ШТУРМ"), "hold": Loc.t("ТРИМАТИ"), "clear": Loc.t("ЗАЧИСТКА"), "bound": Loc.t("ПЕРЕБІЖКИ"), "suppress": Loc.t("ПОДАВЛЕННЯ")}
	var t: String = names.get(cmd.mode, cmd.mode)
	if le != null:
		t += Loc.t(" — рубіж")
	elif Buildings.at(gp) != null and cmd.mode in ["move", "hold"]:
		t += Loc.t(" — зайняти будівлю")
	elif Buildings.at(gp) != null and cmd.mode in ["assault", "clear"]:
		t = Loc.t("ЗАЧИСТКА БУДІВЛІ")
	draw_string(f, mp + Vector2(16, 22), t + Loc.t("  (ПКМ)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(col, 0.95))
