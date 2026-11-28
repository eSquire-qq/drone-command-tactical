class_name Squad
extends Node
## SquadController: shared knowledge of the enemy, orders, formation slots,
## bounding overwatch for assaults, mount/dismount, help requests, morale.

var side = 0
var sname = ""
var short = ""
var kind = ""
var members: Array = []
var order = "hold"
var order_pos = Vector3.ZERO
var order_dir = Vector3(0, 0, -1)
var rally = Vector3.ZERO
var known = {}
var danger_spots: Array = []   # [position, until] where a member fell
var leaderless_t := 0.0        # the leader is down: no command until this runs out
var acting = null              # who took over command
var pending_order = null       # an order given while there was no command: [type, pos, line_end]
var _reassault_n := 0      # how many times an "assault finished" was turned back into clearing
var clear_ext := 0       # times a clear order was extended along the trench
var bld = null           # building of an "occupy" / "clear_bld" order
var force_bound := false # "перебіжками": the assault machinery bounds even without contact
var follow_v = null      # order "follow_veh": the vehicle to walk behind
var _follow_t := 0.0
var sup_pos = null       # suppression order: fire at this point until sup_until
var sup_until := -1.0
var bld_phase := 0       # clear_bld: 0 stack at the entry, 1 grenade, 2 entry, 3 search
var bld_t := 0.0
var bld_entry: Dictionary = {}
var bld_quiet := 0.0
var corners = {}        # trench corners already cleared: key -> time
var vehicle = null
var mounted = false
var selected = false
var help_cd = 10.0
var losses_reported = 0
var help_time = -999.0
var half_lost = false
# assault
var assault_path = PackedVector3Array()
var assault_progress = 0.0
var assault_len = 0.0
var bound_team = 0
var bound_t = 0.0
var final_slots: Array = []
var contact_mode = false
var _pinned_msg_t := -99.0
var nade_claims := {}     # grenade target spot -> time (one grenade per spot at a time)
var nade_log: Array = []  # times of the squad's recent grenades
# assault pacing
var assault_start_n := 0
var loss_times: Array = []
var _down_seen := 0
var assault_pause_t := 0.0
# enemy data
var defend_slots: Array = []
var alt_slots: Array = []
var fallback_slots: Array = []
var is_reserve = false
var team_name = ""


func _ready() -> void:
	Events.unit_state_changed.connect(_on_member_down)


## After the spell without a leader: the most experienced man left takes over
## (rank, then steadiness), says so, and a waiting order is carried out.
func _take_command() -> void:
	var best = null
	var bs := -INF
	for m in active_members():
		var sc: float = (1.0 if m.rank_short != "" else 0.0) * 2.0 + m.discipline + m.grit + (0.5 if m.role in ["mg", "rifleman"] else 0.0) - m.supp_level * 0.3
		if sc > bs:
			bs = sc
			best = m
	acting = best
	if best == null:
		return
	if side == 0:
		radio("order", Loc.t("%s прийняв командування.") % best.display_name(), "info")
	if pending_order != null:
		var po: Array = pending_order
		pending_order = null
		issue_order(po[0], po[1], po[2])


func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("squad", t0)


func _process_body(delta: float) -> void:
	if not W.running():
		return
	help_cd -= delta
	_expire_knowledge()
	_update_solo_mount()
	if leaderless_t > 0.0:
		leaderless_t -= delta
		if leaderless_t <= 0.0:
			_take_command()
		elif order == "assault":
			return   # no new bounds without a leader: the men hold where they are
	if order == "assault":
		_update_assault(delta)
	elif order == "mount":
		_update_mount()
	elif order == "clear_bld":
		_update_clear_bld(delta)
	elif order == "occupy":
		_update_occupy(delta)
	elif order == "follow_veh":
		_update_follow(delta)
	elif order == "clear":
		if _all_arrived(3.0):
			# a known enemy further along the same trench: keep clearing
			var nxt = _clear_next()
			if nxt != null and clear_ext < 3:
				var ext := clear_ext + 1
				if side == 0:
					radio("order", Loc.t("противник далі по траншеї — продовжуємо зачистку."), "info")
				issue_order("clear", nxt)
				clear_ext = ext
				return
			order = "hold"
			for m in members:
				m.follow_ahead = null
			if side == 0:
				radio("order", Loc.t("ділянку окопу зачищено, закріплюємось."), "good")
				if W.blog:
					W.blog.add("order", Loc.t("%s: ділянку окопу зачищено") % short, center())
	elif order == "move" or order == "retreat":
		if not mounted and _all_arrived(3.0):
			order = "hold"
	_check_morale_and_help()


# ------------------------------------------------------------------ queries
func active_members() -> Array:
	var out: Array = []
	for m in members:
		if m.is_active():
			out.append(m)
	return out


func alive_count() -> int:
	var c = 0
	for m in members:
		if m.health != Soldier.H.DEAD and not m.evacuated:
			c += 1
	return c


func active_count() -> int:
	return active_members().size()


func center() -> Vector3:
	if mounted and vehicle != null and is_instance_valid(vehicle):
		return vehicle.global_position
	var act = active_members()
	if act.is_empty():
		for m in members:
			if m.health != Soldier.H.DEAD:
				return m.global_position
		return members[0].global_position if members.size() > 0 else Vector3.ZERO
	var c = Vector3.ZERO
	for m in act:
		c += m.global_position
	return c / act.size()


## Radio report from this squad (delayed / garbled by RadioSystem).
func radio(type: String, text: String, kind: String = "info") -> void:
	if side != 0:
		return
	if W.radio:
		W.radio.report(self, type, text, kind)
	else:
		Events.msg("%s: %s" % [short, text], kind)


## Contact report: how many, what, where - as the men see it.
func contact_report() -> String:
	var n := 0
	var kinds := {}
	var sum := Vector3.ZERO
	for e in known.keys():
		if not is_instance_valid(e) or W.time - float(known[e]["t"]) > 12.0:
			continue
		n += 1
		sum += known[e]["pos"]
		var k: String = W.intel._kind(e) if W.intel else Loc.t("піхота")
		kinds[k] = int(kinds.get(k, 0)) + 1
	if n == 0:
		return Loc.t("контакт! Переходимо до перебіжок.")
	var ld = leader()
	var reliable: bool = avg_level() < 2.5 and ld != null and ld.role == "leader"
	var c: Vector3 = center()
	var at: Vector3 = sum / n
	var what := Loc.t("піхота")
	if kinds.has("кулемет"):
		what = "кулемет" if n == 1 else Loc.t("піхота з кулеметом")
	elif kinds.has("техніка"):
		what = "техніка"
	var dist := int(round(c.distance_to(at) / 10.0) * 10.0)
	var cnt: String = RadioSystem.estimate(n, reliable) if reliable else "~" + RadioSystem.estimate(n, reliable)
	return Loc.t("контакт! %s, %s, %s, %d м. Переходимо до перебіжок.") % [Loc.t(what), cnt, RadioSystem.bearing(c, at), dist]


func leader():
	for m in members:
		if m.role == "leader" and m.is_active():
			return m
	if acting != null and is_instance_valid(acting) and acting.is_active():
		return acting
	var act = active_members()
	return act[0] if act.size() > 0 else null


func avg_suppression() -> float:
	var act = active_members()
	if act.is_empty():
		return 0.0
	var s = 0.0
	for m in act:
		s += m.suppression
	return s / act.size()


func avg_morale() -> float:
	var act = active_members()
	if act.is_empty():
		return 0.0
	var s = 0.0
	for m in act:
		s += m.morale
	return s / act.size()


func knows(e) -> bool:
	if known.has(e):
		return W.time - float(known[e]["t"]) < 10.0
	if side == 0 and e is Soldier and e.revealed > 0.0:
		return true
	if side == 0 and e is Soldier and e.marked:
		return true
	return false


func report(e, pos: Vector3) -> void:
	var fresh = not known.has(e)
	if fresh and known.is_empty():
		# the first contact surprises everybody, each in his own time
		for m in members:
			if m.is_active():
				m.surprise()
	known[e] = {"t": W.time, "pos": pos}
	if fresh and side == 1 and W.enemy_ai:
		W.enemy_ai.raise_alert(2)
	if side == 1 and e is Vehicle and W.enemy_ai:
		W.enemy_ai.share(self, e, pos)


func hear(pos: Vector3, src) -> void:
	# approximate knowledge from gunfire
	if src != null and is_instance_valid(src) and not known.has(src):
		known[src] = {"t": W.time - 5.0, "pos": pos + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))}
	if side == 0 and W.intel and src != null and is_instance_valid(src) and src.side != 0:
		W.intel.heard(src, pos, short)


func threat_level() -> int:
	for e in known.keys():
		if W.time - float(known[e]["t"]) < 12.0:
			return 1
	return 0


func nearest_threat(pos: Vector3):
	var best = null
	var bd = INF
	for e in known.keys():
		var p: Vector3 = known[e]["pos"]
		var d = p.distance_to(pos)
		if d < bd:
			bd = d
			best = p
	return best


## Up to `n` known enemy positions nearest to `p` (seen lately by this squad;
## for our side also the enemies the drone / other troops have revealed).
func threat_points(p: Vector3, n: int) -> Array:
	var pts: Array = []
	for e in known.keys():
		if W.is_alive_target(e) and W.time - float(known[e]["t"]) < 30.0:
			pts.append(known[e]["pos"])
	if side == 0:
		for u in W.units:
			if u.side == 1 and u.is_active() and (u.revealed > 0.0 or u.marked) and not known.has(u):
				pts.append(u.global_position)
	pts.sort_custom(func(a, b): return (a as Vector3).distance_to(p) < (b as Vector3).distance_to(p))
	return pts.slice(0, n)


## Where to look from a building when no enemy is known yet: on, the way we
## were going (our side), or towards where we come from (theirs).
func _look_dir_point(b: Dictionary) -> Vector3:
	var c: Vector3 = b["center"]
	var thr := threat_points(c, AIConfig.WIN_THREATS)
	if not thr.is_empty():
		var s := Vector3.ZERO
		for t in thr:
			s += t
		return s / thr.size()
	if side == 0 and W.mission:
		var r: Rect2 = W.mission.def.objective_rect
		if r.has_area():
			return Vector3(r.get_center().x, 0, r.get_center().y)
	var away: Vector3 = c - center()
	return c + (away.normalized() if away.length() > 1.0 else Vector3(0, 0, -1)) * 50.0


func occupied(except) -> Array:
	var out: Array = []
	for m in members:
		if m != except and m.is_active():
			out.append(m.slot if m.moving else m.global_position)
	# where a comrade has just fallen: nobody takes cover right there
	var i := danger_spots.size() - 1
	while i >= 0:
		if W.time > float(danger_spots[i][1]):
			danger_spots.remove_at(i)
		else:
			out.append(danger_spots[i][0])
		i -= 1
	return out


## A member is down: the men close by (their fright is DamageSystem's casualty
## shock) feel the strain, re-think their cover at once and avoid the spot
## For a while.
func _on_member_down(u, old: int, h: int) -> void:
	if u.squad != self or old >= Soldier.H.INCAP or h < Soldier.H.INCAP:
		return
	if (u.role == "leader" or u == acting) and active_count() > 0:
		acting = null
		leaderless_t = randf_range(AIConfig.LEADER_LOSS_MIN, AIConfig.LEADER_LOSS_MAX)
	var p: Vector3 = u.global_position
	danger_spots.append([p, W.time + AIConfig.DANGER_SPOT_T])
	for m in members:
		if m == u or not m.is_active():
			continue
		var d: float = m.global_position.distance_to(p)
		if d > AIConfig.COMRADE_R:
			continue
		var k: float = 1.0 - d / AIConfig.COMRADE_R
		m.stress = minf(100.0, m.stress + AIConfig.COMRADE_STRESS * k)
		m.ai.cover_t = 0.0


func _expire_knowledge() -> void:
	for e in known.keys():
		if not W.is_alive_target(e) or W.time - float(known[e]["t"]) > 25.0:
			known.erase(e)


func _all_arrived(tol: float) -> bool:
	for m in active_members():
		if m.moving or not m.arrived(tol):
			return false
	return true


# ------------------------------------------------------------------ orders
func formation_slots(pos: Vector3, dir: Vector3, count: int, line_end = null, spacing: float = 3.6) -> Array:
	var slots: Array = []
	var right = Vector3(-dir.z, 0, dir.x)
	for i in count:
		var p: Vector3
		if line_end != null:
			var k = 0.5 if count == 1 else float(i) / (count - 1)
			p = pos.lerp(line_end, k)
		else:
			var off = i - (count - 1) * 0.5
			p = pos + right * off * spacing - dir * absf(off) * 1.2
		p = W.grid.clamp_in(p, 3.0)
		slots.append(W.grid.free_point(p))
	return slots


## Nearest recently known, still fighting enemy in the trench within 35 m of
## the squad (the clear order ends at the clicked point; he may have pulled
## back along the trench). null when there is none.
func _clear_next():
	var c := center()
	# the clearing team looks and listens down the next bays of the trench
	for u in W.units:
		if u.side != side and u.is_active() and u.vehicle == null and u.global_position.distance_to(c) < 30.0 				and W.grid.in_channel(u.global_position, 1.5):
			known[u] = {"t": W.time, "pos": u.global_position}
	var best = null
	var bd := 35.0
	for e in known.keys():
		if not is_instance_valid(e) or not (e is Soldier) or not e.is_active() or W.time - float(known[e]["t"]) > 25.0:
			continue
		var p: Vector3 = known[e]["pos"]
		if not W.grid.in_channel(p, 1.5):
			continue
		var d := c.distance_to(p)
		if d < bd and d > 4.0:
			bd = d
			best = p
	return best


func issue_order(type: String, pos: Vector3, line_end = null) -> void:
	if leaderless_t > 0.0 and type != "retreat":
		var first := pending_order == null
		pending_order = [type, pos, line_end]
		if side == 0 and first:
			radio("order", Loc.t("командира немає — наказ виконаємо, щойно хтось прийме командування."), "warn")
		return
	clear_ext = 0
	if type in ["move", "hold", "retreat", "occupy", "mount"]:
		_reassault_n = 0
	force_bound = type == "bound"
	if type == "bound":
		type = "assault"
		if side == 0:
			radio("order", Loc.t("рухаємось перебіжками: одна група біжить, друга прикриває."), "info")
	follow_v = null
	sup_until = -1.0
	if mounted and vehicle != null and is_instance_valid(vehicle) and vehicle.state != "destroyed":
		if type == "move" or type == "assault" or type == "hold":
			vehicle.order_move(pos)
			return
	if type == "retreat":
		pos = rally
	# an order on a building: move / hold = take it, assault / clear = clear it
	var b = Buildings.at(pos) if side == 0 or type == "occupy" else null
	if b != null and type in ["move", "hold", "occupy"]:
		_occupy(b)
		return
	if b != null and type in ["assault", "clear", "clear_bld"]:
		_clear_building(b)
		return
	if type == "clear":
		var sp = W.grid.snap_to_trench(pos)
		if sp == null:
			type = "assault"
		else:
			pos = sp
	order = type
	order_pos = pos
	if side == 0 and W.blog and (type == "assault" or type == "clear" or type == "retreat"):
		W.blog.order(self, type, pos)
	for m in members:
		m.solo = ""
		m.follow_ahead = null
		m.prefer_trench = false
	if type == "clear":
		var act0 = active_members()
		clear_column(act0, pos)
		return
	var act = active_members()
	if act.is_empty():
		return
	var c = center()
	var dir = pos - c
	dir.y = 0.0
	if dir.length() < 1.0:
		dir = order_dir
	else:
		dir = dir.normalized()
	if line_end != null:
		var ld: Vector3 = (line_end - pos)
		dir = Vector3(ld.z, 0, -ld.x).normalized()
		if dir.dot(pos - c) < 0:
			dir = -dir
	order_dir = dir
	var slots = formation_slots(pos, dir, act.size(), line_end, 4.0 if type == "retreat" else 3.6)
	if type == "hold":
		var taken: Array = []
		for i in slots.size():
			var cp: Vector3 = W.grid.find_cover(slots[i], 4.0, nearest_threat(slots[i]), taken)
			slots[i] = cp
			taken.append(cp)
	var right = Vector3(-dir.z, 0, dir.x)
	act.sort_custom(func(a, b): return a.global_position.dot(right) < b.global_position.dot(right))
	slots.sort_custom(func(a, b): return a.dot(right) < b.dot(right))
	for i in act.size():
		var m = act[i]
		m.slot = slots[i]
		m.team = i % 2
		m.can_advance = true
		m.pinned_t = 0.0
		if m.aid_target != null and is_instance_valid(m.aid_target):
			m.aid_target.aid_by = null
		m.aid_target = null
		if type != "assault":
			m.move_to(slots[i], true)
	if type == "assault":
		final_slots = slots
		_start_assault()


# ------------------------------------------------------------------ with vehicles / suppression
## Walk behind a vehicle in two files, using it as cover; the vehicle keeps
## the infantry pace.
func follow_vehicle(v) -> void:
	if v == null or not is_instance_valid(v) or v.state == "destroyed":
		return
	issue_order("hold", center())
	order = "follow_veh"
	follow_v = v
	_follow_t = 0.0
	if side == 0:
		radio("order", Loc.t("рухаємось двома колонами за %s.") % v.vname, "info")


func _update_follow(delta: float) -> void:
	_follow_t -= delta
	if _follow_t > 0.0:
		return
	_follow_t = 0.6
	var v = follow_v
	if v == null or not is_instance_valid(v) or v.state == "destroyed" or v.offmap:
		order = "hold"
		follow_v = null
		return
	var f: Vector3 = v.forward()
	var r := Vector3(-f.z, 0, f.x)
	var back0: float = v.model.rear_z + 2.5
	var act := active_members()
	for i in act.size():
		var m = act[i]
		var col := -1.0 if i % 2 == 0 else 1.0
		var row: int = i / 2
		var p: Vector3 = v.global_position - f * (back0 + row * 2.6) + r * col * 1.4
		p = W.grid.free_point(p)
		m.slot = p
		if m.global_position.distance_to(p) > 1.8 and (not m.moving or m.path.size() == 0 or m.path[m.path.size() - 1].distance_to(p) > 1.5):
			m.move_to(p, v.speed > 2.0)


## Fire at a point for a while (where the enemy is, or may be), staying put.
func order_suppress(p: Vector3) -> void:
	issue_order("hold", center())
	sup_pos = p
	sup_until = W.time + AIConfig.SUPPRESS_T
	if side == 0:
		radio("order", Loc.t("ведемо вогонь на подавлення."), "info")


# ------------------------------------------------------------------ buildings
## Take a building: men go to the window posts that face the enemy (the
## rest wait inside) and fire out of the windows.
func _occupy(b: Dictionary) -> void:
	order = "occupy"
	order_pos = b["center"]
	bld = b
	var act := active_members()
	for m in act:
		if m.post != null:
			m.leave_post()   # a fresh choice for everybody
	var thr := threat_points(b["center"], AIConfig.WIN_THREATS)
	var posts := Buildings.pick_posts(b, act.size(), thr, _look_dir_point(b))
	var inner: Array = b["interior"]
	# the nearest free man to each post, the best posts first
	var free: Array = act.duplicate()
	for w in posts:
		var best = null
		var bd := INF
		for m in free:
			var d: float = m.global_position.distance_to(w.get("in", w["post"]))
			if d < bd:
				bd = d
				best = m
		free.erase(best)
		_send_to_post(best, w)
	var i := 0
	for m in free:
		m.post_pending = null
		m.slot = inner[i % inner.size()]
		i += 1
		m.move_to(m.slot, true)
	_win_review_t = AIConfig.WIN_REVIEW_T
	if side == 0:
		radio("order", Loc.t("займаємо будівлю, %d бійців біля вікон.") % mini(act.size(), posts.size()), "info")


## Clear a building: stack at the nearest door / breach, a grenade inside,
## then in; when nobody of the enemy is left inside — cleared, take it.
func _send_to_post(m, w: Dictionary) -> void:
	m.solo = ""
	m.follow_ahead = null
	m.can_advance = true
	if m.post != null:
		m.leave_post()
	m.post_pending = w
	m.slot = w.get("in", w["post"])
	m.move_to(m.slot, true)


## While holding a building: when the enemy shows up on another side, the men
## at windows that no longer help move to better free ones (a couple at a time).
var _win_review_t := 0.0


func _update_occupy(delta: float) -> void:
	_win_review_t -= delta
	if _win_review_t > 0.0 or bld == null:
		return
	_win_review_t = AIConfig.WIN_REVIEW_T
	var thr := threat_points(bld["center"], AIConfig.WIN_THREATS)
	if thr.is_empty():
		return
	var toward := _look_dir_point(bld)
	var cands: Array = []
	for w in Buildings.free_posts(bld):
		cands.append([Buildings.post_score(w, thr, toward), w])
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var worst: Array = []
	for m in active_members():
		if m.post != null and m.supp_level < 3:
			worst.append([Buildings.post_score(m.post, thr, toward), m])
	worst.sort_custom(func(a, b): return a[0] < b[0])
	var moved := 0
	for k in mini(worst.size(), AIConfig.WIN_SWITCH_MAX):
		var m = worst[k][1]
		# the best free post for him, counting the walk there
		var bi := -1
		var bs := -INF
		for i in cands.size():
			var w: Dictionary = cands[i][1]
			var s: float = float(cands[i][0]) - m.global_position.distance_to(w["post"]) * AIConfig.WIN_DIST_COST
			if s > bs:
				bs = s
				bi = i
		if bi < 0 or bs - float(worst[k][0]) < AIConfig.WIN_SWITCH:
			continue
		_send_to_post(m, cands[bi][1])
		cands.remove_at(bi)
		moved += 1
	if moved > 0 and side == 0:
		radio("order", Loc.t("противник з іншого боку — переходимо до інших вікон."), "info")


func _clear_building(b: Dictionary) -> void:
	order = "clear_bld"
	order_pos = b["center"]
	bld = b
	bld_phase = 0
	bld_t = 0.0
	bld_quiet = 0.0
	bld_entry = Buildings.entry(b, center())
	if bld_entry.is_empty():
		bld_entry = {"out": b["center"], "in": b["center"]}
	if side == 0 and W.blog:
		W.blog.order(self, "clear", b["center"])
	var act := active_members()
	var out: Vector3 = bld_entry["out"]
	var inn: Vector3 = bld_entry["in"]
	var side_v := (out - inn)
	side_v.y = 0.0
	var perp := Vector3(-side_v.z, 0, side_v.x).normalized()
	for i in act.size():
		var m = act[i]
		m.solo = ""
		m.follow_ahead = null
		m.post_pending = null
		m.can_advance = true
		# a stack beside the door, out of the line of the doorway
		m.slot = W.grid.ground(out + perp * (1.2 + i * 0.9) + side_v.normalized() * 0.5)
		m.move_to(m.slot, true)
	if side == 0:
		radio("order", Loc.t("зачищаємо будівлю, збираємось біля %s.") % (Loc.t("пролому") if bld_entry.get("breach", false) else Loc.t("входу")), "info")


func _update_clear_bld(delta: float) -> void:
	bld_t += delta
	var act := active_members()
	if act.is_empty() or bld == null:
		order = "hold"
		return
	var inside := Buildings.men_inside(bld, 1 - side)
	match bld_phase:
		0:
			var ready := 0
			for m in act:
				if not m.moving and m.global_position.distance_to(m.slot) < 3.0:
					ready += 1
			if ready * 2 >= act.size() or bld_t > AIConfig.BLD_STACK_T:
				bld_phase = 1
				bld_t = 0.0
				# the man nearest the door throws a grenade inside if he has one
				var best = null
				var bd := INF
				for m in act:
					var d: float = m.global_position.distance_to(bld_entry["out"])
					if d < bd and m.grenades > 0:
						bd = d
						best = m
				if best != null:
					best.grenades -= 1
					best.nades_used += 1
					W.combat.throw_grenade(best, bld["center"])
					if side == 0:
						radio("order", Loc.t("граната в будівлю!"), "info")
		1:
			if bld_t > AIConfig.BLD_NADE_WAIT:
				bld_phase = 2
				bld_t = 0.0
				var points: Array = (bld["interior"] as Array).duplicate()
				for w in bld["windows"]:
					points.append(w.get("in", w["post"]))
				for i in act.size():
					var m = act[i]
					m.slot = points[i % points.size()]
					m.path = W.grid.find_path_inf(m.global_position, bld_entry["in"]) + PackedVector3Array([m.slot])
					m.path_i = 0
					m.moving = true
					m.run = true
		2, 3:
			bld_phase = 3
			bld_quiet = bld_quiet + delta if inside.is_empty() else 0.0
			if bld_quiet >= AIConfig.BLD_CLEAR_T:
				if side == 0:
					radio("order", Loc.t("будівлю зачищено."), "good")
					if W.blog:
						W.blog.add("order", Loc.t("%s: будівлю зачищено") % short, bld["center"])
				_occupy(bld)


## Trench clearing: column along the trench, point man first, each man
## keeps his distance from the one in front; corners are handled by the
## soldiers themselves (grenade / slicing the pie).
static func clear_column(list: Array, pos: Vector3) -> void:
	if list.is_empty():
		return
	var g = W.grid
	var entry_id: int = g.trench_net.nearest_far(list[0].global_position, 150.0)
	var entry: Vector3 = g.trench_net.pts[entry_id] if entry_id >= 0 else pos
	list.sort_custom(func(a, b): return a.global_position.distance_to(entry) < b.global_position.distance_to(entry))
	var route: PackedVector3Array = g.find_path_inf(list[0].global_position, pos, true)
	for i in list.size():
		var m = list[i]
		m.prefer_trench = true
		m.follow_ahead = list[i - 1] if i > 0 else null
		m.can_advance = true
		m.pinned_t = 0.0
		var dest: Vector3 = pos
		var back := AIConfig.CLEAR_SPACING * i
		var k := route.size() - 1
		while k > 0 and back > 0.0:
			var seg: float = route[k].distance_to(route[k - 1])
			if seg >= back:
				dest = route[k].lerp(route[k - 1], back / seg)
				back = 0.0
			else:
				back -= seg
				dest = route[k - 1]
			k -= 1
		m.slot = dest
		m.move_to(dest, true)


func _start_assault() -> void:
	# an assault means leaving the building: the men come off the windows
	# (otherwise a first bound that ends inside the same building keeps them
	# at their posts, and the bound never starts)
	for m in active_members():
		if m.post != null:
			m.leave_post()
		m.post_pending = null
	assault_start_n = active_count()
	assault_pause_t = 0.0
	assault_path = W.grid.find_path(center(), order_pos, false)
	assault_path.insert(0, center())
	assault_len = 0.0
	for i in range(1, assault_path.size()):
		assault_len += assault_path[i - 1].distance_to(assault_path[i])
	assault_progress = 0.0
	bound_team = 0
	bound_t = 0.0
	contact_mode = threat_level() > 0
	if contact_mode:
		_next_bound()
	else:
		_advance_all()


func _point_on_path(dist: float) -> Vector3:
	var acc = 0.0
	for i in range(1, assault_path.size()):
		var seg = assault_path[i - 1].distance_to(assault_path[i])
		if acc + seg >= dist:
			return assault_path[i - 1].lerp(assault_path[i], (dist - acc) / maxf(seg, 0.001))
		acc += seg
	return assault_path[assault_path.size() - 1] if assault_path.size() > 0 else order_pos


func _advance_all() -> void:
	var act = active_members()
	for i in act.size():
		var m = act[i]
		m.can_advance = true
		m.slot = final_slots[i % final_slots.size()] if final_slots.size() > 0 else order_pos
		m.move_to(m.slot, true)


## Average suppression level of the active members.
func avg_level() -> float:
	var n := 0
	var s := 0.0
	for m in active_members():
		s += m.supp_level
		n += 1
	return s / maxf(n, 1)


func _next_bound() -> void:
	var step: float = AIConfig.ASSAULT_BOUND_UNDER_FIRE if avg_level() >= 1.5 else AIConfig.ASSAULT_BOUND
	assault_progress = minf(assault_progress + step, assault_len)
	var p = _point_on_path(assault_progress)
	var act = active_members()
	var team_members: Array = []
	var pinned := 0
	for m in act:
		if m.team == bound_team:
			team_members.append(m)
			m.can_advance = true
			if m.supp_level >= 2:
				pinned += 1
		else:
			m.can_advance = false
			if m.moving:
				m.stop()
	# most of the bounding team is pinned down: the bound waits, the rest keep
	# firing; the squad does not drive pinned men into the open
	if team_members.size() > 0 and pinned * 2 >= team_members.size():
		assault_progress = maxf(0.0, assault_progress - 14.0)
		bound_t = 0.0
		if side == 0 and W.time - _pinned_msg_t > 25.0:
			_pinned_msg_t = W.time
			radio("suppressed", Loc.t("притиснуті вогнем, перебіжку зупинено"), "warn")
		return
	var near_end = assault_progress >= assault_len - 1.0
	var slots = formation_slots(p, order_dir, team_members.size(), null, 4.5)
	for i in team_members.size():
		var m = team_members[i]
		var sp: Vector3 = slots[i]
		if near_end and final_slots.size() > 0:
			sp = final_slots[act.find(m) % final_slots.size()]
		else:
			sp = W.grid.find_cover(sp, 4.0, nearest_threat(sp), occupied(m))
		m.slot = sp
		if m.supp_level >= 2 and randf() > float(AIConfig.LEVEL_MOVE[m.supp_level]) * m.discipline:
			continue   # this one stays down; the AI moves him when he recovers
		m.move_to(sp, true)
	bound_t = 0.0


## Losses change the pace: a sharp loss stops the squad to dig in for a while,
## losing half the men calls the assault off until the commander decides.
func _assault_state(delta: float) -> bool:
	var down := 0
	for m in members:
		if m.health >= Soldier.H.INCAP:
			down += 1
	while _down_seen < down:
		_down_seen += 1
		loss_times.append(W.time)
	var recent := 0
	for t in loss_times:
		if W.time - float(t) < AIConfig.ASSAULT_LOSS_WINDOW:
			recent += 1
	var start: int = maxi(assault_start_n, 1)
	if active_count() <= int(floor(start * AIConfig.ASSAULT_ABORT_LEFT)):
		if side == 0:
			radio("casualty", Loc.t("втрати понад половину складу — штурм припинено, закріплюємось. Потрібне рішення командира."), "alert")
			if W.blog:
				W.blog.add("loss", Loc.t("%s: штурм припинено через втрати") % short, center())
		issue_order("hold", center())
		return false
	if assault_pause_t > 0.0:
		assault_pause_t -= delta
		if assault_pause_t <= 0.0 and avg_level() < 2.0:
			if side == 0:
				radio("order", Loc.t("продовжуємо штурм."), "info")
			bound_t = 0.0
			_next_bound()
		elif assault_pause_t <= 0.0:
			assault_pause_t = 6.0   # still pinned: wait a little more
		return false
	if recent >= maxi(2, int(ceil(start * AIConfig.ASSAULT_PAUSE_LOSSES))) and loss_times.size() > 0 and W.time - float(loss_times[loss_times.size() - 1]) < 2.0:
		assault_pause_t = AIConfig.ASSAULT_PAUSE_TIME
		for m in active_members():
			m.can_advance = false
			if m.moving and not m.in_trench():
				m.stop()
		if side == 0:
			radio("casualty", Loc.t("втрати (%d) — зупиняємось, займаємо укриття.") % recent, "warn")
		return false
	return true


func _update_assault(delta: float) -> void:
	if not _assault_state(delta):
		return
	bound_t += delta
	var threat = threat_level() > 0 or force_bound
	if threat and not contact_mode:
		contact_mode = true
		# project progress onto the path from the squad centre
		var c = center()
		var best = 0.0
		var bd = INF
		var k = 0.0
		while k <= assault_len:
			var d = _point_on_path(k).distance_to(c)
			if d < bd:
				bd = d
				best = k
			k += 4.0
		assault_progress = best
		_next_bound()
		if side == 0:
			radio("contact", contact_report(), "warn")
			if W.blog:
				W.blog.add("contact", Loc.t("%s: контакт, перебіжки") % short, center())
		return
	if not threat and contact_mode and bound_t > 6.0:
		contact_mode = false
		_advance_all()
		return
	if contact_mode:
		var moving_team = false
		for m in active_members():
			if m.team == bound_team and m.moving:
				moving_team = true
		if (not moving_team and bound_t > 3.5) or bound_t > 16.0:
			if assault_progress >= assault_len - 1.0:
				_finish_assault()
				return
			bound_team = 1 - bound_team
			_next_bound()
	else:
		if _all_arrived(3.0):
			_finish_assault()


func _finish_assault() -> void:
	# a known enemy still alive at the objective (a man ducking in the trench
	# who stopped shooting): the position is not taken yet — clear the trench,
	# or assault him in the open (twice at most, no endless loop)
	var left = null
	var lp := Vector3.ZERO
	var bd := 15.0
	for e in known.keys():
		if not W.is_alive_target(e) or not (e is Soldier) or not e.is_active():
			continue
		var kp: Vector3 = known[e]["pos"]
		var d := kp.distance_to(order_pos)
		if d < bd:
			bd = d
			left = e
			lp = kp
	if left != null and _reassault_n < 2:
		_reassault_n += 1
		if side == 0:
			radio("contact", Loc.t("противник ще на позиції — продовжуємо."), "warn")
		if W.grid.in_channel(lp, 1.2):
			issue_order("clear", lp)
		else:
			issue_order("assault", lp)
		return
	_reassault_n = 0
	order = "hold"
	for m in active_members():
		m.can_advance = true
	if side == 0:
		radio("order", Loc.t("рубіж зайнято."), "info")


func set_defend(slots: Array, alert: bool) -> void:
	defend_slots = slots
	order = "defend" if alert else "idle"
	var i = 0
	for m in members:
		if not m.is_active():
			continue
		var sp: Vector2 = slots[i % slots.size()]
		m.slot = W.grid.ground(Vector3(sp.x, 0, sp.y))
		i += 1
		if alert and m.bunker == null and not m.arrived(2.0):
			m.move_to(m.slot, true)


# ------------------------------------------------------------------ mount
func order_mount() -> void:
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.state == "destroyed":
		return
	order = "mount"
	for m in active_members():
		m.slot = vehicle.rear_point()
		m.move_to(m.slot, true)
	vehicle.stop()


func _update_mount() -> void:
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.state == "destroyed":
		order = "hold"
		return
	var rp: Vector3 = vehicle.rear_point()
	var all_in = true
	for m in active_members():
		all_in = false
		if m.global_position.distance_to(rp) < 2.6:
			vehicle.board(m)
		elif not m.moving:
			m.slot = rp
			m.move_to(rp, true)
	if all_in and vehicle.passengers.size() > 0:
		mounted = true
		order = "mounted"
		if side == 0:
			radio("regroup", Loc.t("посадку завершено."), "info")


## Individually ordered soldiers boarding the squad vehicle.
func _update_solo_mount() -> void:
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.state == "destroyed":
		return
	var any = false
	var rp: Vector3 = vehicle.rear_point()
	for m in members:
		if m.solo != "mount" or not m.is_active():
			continue
		any = true
		if m.global_position.distance_to(rp) < 2.6:
			vehicle.board(m)
			m.solo = ""
		elif not m.moving:
			m.slot = rp
			m.move_to(rp, true)
	if any and active_count() == 0 and vehicle.passengers.size() > 0:
		mounted = true
		order = "mounted"


func on_dismounted() -> void:
	mounted = false
	order = "hold"
	order_dir = -vehicle.global_basis.z if vehicle != null else order_dir
	if vehicle != null and active_count() > 0:
		var spot: Vector3 = vehicle.rear_point() - vehicle.forward() * 6.0
		issue_order("hold", W.grid.free_point(W.grid.clamp_in(spot, 4.0)))


# ------------------------------------------------------------------ morale & help
func _check_morale_and_help() -> void:
	var lost = 0
	for m in members:
		if m.health >= Soldier.H.INCAP:
			lost += 1
	if not half_lost and members.size() > 0 and lost * 2 >= members.size():
		half_lost = true
		for m in active_members():
			m.morale -= 18.0
		if side == 0:
			radio("casualty", Loc.t("втрати понад 50%! Боєздатність знижена."), "alert")
	if help_cd <= 0.0 and (lost > losses_reported or (avg_suppression() > 55.0 and active_count() > 0)):
		help_cd = 35.0
		losses_reported = lost
		help_time = W.time
		Events.squad_help_requested.emit(self)
		if side == 0 and kind != "medevac" and active_count() > 0:
			if lost > 0:
				radio("casualty", Loc.t("маємо втрати (%d), запитуємо підтримку!") % lost, "alert")
			else:
				radio("fire", Loc.t("під щільним вогнем, запитуємо підтримку!"), "alert")


func throw_smoke() -> bool:
	var tp = nearest_threat(center())
	var dir = order_dir
	if tp != null:
		dir = ((tp as Vector3) - center())
		dir.y = 0.0
		dir = dir.normalized()
	var thrown = 0
	for m in active_members():
		if m.smokes > 0 and m.action == "" and thrown < 2:
			m.smokes -= 1
			var p: Vector3 = m.global_position + dir * randf_range(10.0, 15.0) + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
			m.start_action("smoke", 1.1, p)
			thrown += 1
	return thrown > 0
