class_name SoldierAI
extends RefCounted
## Individual behaviour shared by both sides. Abstract state machine driven by
## perception, squad order, suppression and morale. Runs every ~0.45 s.

var s  # Soldier
var vis = {}
var want_posture = 0
var cover_t = 0.0
var idle_t = 0.0
var state = "idle"   # shown in HUD
var section_cd = 0.0
var peeking := true    # this tick the soldier rises to look / shoot


func _init(soldier) -> void:
	s = soldier
	want_posture = Soldier.P.STAND


func think(dt: float) -> void:
	if s.surrendered:
		return
	if s.side == 1 and W.prisoners and s.health < Soldier.H.INCAP:
		W.prisoners.consider(s)
		if s.surrendered:
			return
	if s.health >= Soldier.H.INCAP or s.vehicle != null or s.carried or s.on_board:
		return
	cover_t -= dt
	idle_t -= dt
	if not s.moving and s.post == null:
		_take_window()
	if s.noncombat or s.evac_walk:
		s.fire_ok = false
		return   # crew medics / walking wounded are driven by EvacuationSystem
	if s.bunker_deep:
		state = Loc.t("укриття")
		return
	_support()
	_perceive()
	if s.react_t > 0.0:
		# surprised: he takes in what happened before he acts — keeps
		# doing what he did, no new decision, no new target yet
		s.react_t -= dt
		return
	_pick_target()
	_pick_area_target()
	_behave(dt)


## Standing at (or sent to) a window post inside a building: take it.
func _take_window() -> void:
	if s.post_pending != null:
		# the post sits against the wall (a solid nav cell): the path ends a
		# step or two short of it, inside the same building
		var pp: Vector3 = s.post_pending["post"]
		# horizontal distance: the post may be on an upper floor
		var d: float = Vector2(s.global_position.x - pp.x, s.global_position.z - pp.z).length()
		# right by the window (the cell next to a wall may count as outside the
		# footprint), or anywhere close inside the same building
		if d < 2.8 or (d < 3.8 and Buildings.at(s.global_position) != null and Buildings.at(s.global_position)["id"] == s.post_pending["b"]):
			Buildings.claim(s, s.post_pending)
			if s.post == null:
				s.post_pending = null   # someone else took it
		return
	var b = Buildings.at(s.global_position)
	if b == null:
		return
	for w in Buildings.free_posts(b):
		if s.global_position.distance_to(w["post"]) < 1.0:
			Buildings.claim(s, w)
			return


## Calm comrades and the leader close by help a soldier recover.
func _support() -> void:
	var calm := 0
	var leader := false
	for m in s.squad.members:
		if m == s or not m.is_active():
			continue
		if m.global_position.distance_to(s.global_position) < AIConfig.SUPPORT_RANGE:
			if m.supp_level <= 1:
				calm += 1
			if m.role == "leader":
				leader = true
	s.support_k = (AIConfig.DECAY_SUPPORT if calm >= 2 else 1.0) * (AIConfig.DECAY_LEADER if leader else 1.0)


## Machine gunners keep firing at a position where an enemy was seen a moment
## ago and ducked (suppressive fire), instead of falling silent.
func _pick_area_target() -> void:
	var sq0 = s.squad
	if sq0 != null and sq0.sup_until > W.time and sq0.sup_pos != null and s.target == null:
		var aim0 := AIConfig.area_aim(sq0.sup_pos)
		if W.grid.visibility(s.eye_point(), aim0) >= 0.15:
			s.area_target = aim0
			return
	if s.target != null or s.role != "mg" or s.supp_level >= 2:
		s.area_target = null
		return
	if s.area_target != null and randf() < 0.7:
		return   # keeps working the same point for a few seconds
	s.area_target = null
	var sp: Vector3 = s.eye_point()
	var best = null
	var bd := INF
	for e in s.squad.known.keys():
		if not W.is_alive_target(e) or not (e is Soldier):
			continue
		var k: Dictionary = s.squad.known[e]
		if W.time - float(k["t"]) > AIConfig.AREA_FIRE_MEMORY:
			continue
		var p: Vector3 = k["pos"]
		var d := sp.distance_to(p)
		if d > float(s.weapon.get("range", 100.0)) or d < 15.0 or (d >= bd and randf() < 0.5):
			continue
		var aim := AIConfig.area_aim(p)
		if W.grid.visibility(sp, aim) < 0.2:
			continue
		bd = d
		best = aim
	s.area_target = best


# ------------------------------------------------------------------ perception
func _perceive() -> void:
	vis.clear()
	var eye: Vector3 = s.eye_point()
	if s.atgm > 0:
		# ATGM sight / periscope rises above the parapet even when the crew is crouched
		eye = s.global_position + Vector3(0, 2.2 if s.in_trench() else 1.6, 0)
	var vrange = (140.0 if s.atgm <= 0 else 195.0) * float(Game.wx("sight"))
	var sq = s.squad
	for e in W.opponents(s.side):
		if e is Soldier and e.bunker_deep:
			continue
		var ep: Vector3 = e.global_position
		var d = eye.distance_to(ep)
		if d > vrange:
			continue
		var v: float = W.grid.visibility(eye, e.aim_point())
		if v <= 0.08 and e is Soldier and d < 30.0 and Buildings.same(s, e):
			v = 0.7   # inside one building: the stairs and corridors
		if v <= 0.08:
			continue
		var known: bool = sq.knows(e)
		var p: float = v * e.signature() * (1.0 - d / vrange * 0.75) * 0.8
		# low and still in the grass is hard to pick out at range
		if e is Soldier and e.posture != Soldier.P.STAND and d > 50.0 and not e.in_trench():
			p *= 0.55
		if s.side == 1:
			p *= float(Game.diff("enemy_detect"))
		p *= float(Game.wx("detect"))
		# a new enemy is noticed best in front; at a window / in a bunker the
		# view is the opening itself, no extra penalty
		if not known and s.post == null and s.bunker == null:
			var off := absf(angle_difference(s.yaw, s.yaw_to(ep)))
			if off > AIConfig.FOV_SIDE:
				p *= AIConfig.FOV_REAR_K
			elif off > AIConfig.FOV_FRONT:
				p *= AIConfig.FOV_SIDE_K
		if known or randf() < p:
			vis[e] = v
			sq.report(e, ep)
			if s.side == 0:
				W.command.reveal(e, 3.0, sq.short)
			elif W.enemy_ai:
				W.enemy_ai.raise_alert(2)


func _pick_target() -> void:
	var best = null
	var best_s = -INF
	var wr: float = s.weapon.get("range", 100.0)
	var pos: Vector3 = s.global_position
	for e in vis.keys():
		if not W.is_alive_target(e):
			continue
		var d = pos.distance_to(e.global_position)
		var sc = 0.0
		if e is Vehicle:
			var can_at: bool = s.rockets > 0 and d <= Db.AT_ROCKET["range"]
			var can_atgm: bool = s.atgm > 0 and d <= Db.ATGM["range"]
			if not can_at and not can_atgm:
				continue
			sc = 70.0 - d * 0.2
		else:
			if d > wr:
				continue
			sc = 40.0 - d * 0.3
			if e.role == "mg":
				sc += 8.0
			if e.flash_t > 0.0:
				sc += 8.0
			if e.marked:
				sc += 25.0
			if e.health == Soldier.H.WOUNDED:
				sc -= 4.0
		if e == s.target:
			sc += 12.0
		sc += float(vis[e]) * 10.0
		if sc > best_s:
			best_s = sc
			best = e
	# AT gunners also go for revealed bunkers
	if s.rockets > 0 and s.side == 0 and (best == null or not (best is Vehicle)):
		for b in W.bunkers:
			if b.destroyed or not b.ever_seen or b.side == s.side:
				continue
			var d = pos.distance_to(b.global_position)
			if d > Db.AT_ROCKET["range"] * 0.9:
				continue
			var v: float = W.grid.visibility(s.eye_point(), b.aim_point() + Vector3(0, 0.4, 0))
			if v > 0.15 and (best == null or b.marked or randf() < 0.5):
				best = b
				vis[b] = v
				break
	s.target = best
	s.target_vis = float(vis.get(best, 0.0)) if best != null else 0.0


# ------------------------------------------------------------------ behaviour
func _behave(dt: float) -> void:
	var sq = s.squad
	var order: String = s.solo if s.solo != "" else sq.order
	var lvl: int = s.supp_level
	var threat: bool = sq.threat_level() > 0 or lvl >= 1
	var pinned: bool = lvl >= 3
	# in cover a suppressed soldier only rises now and then to look and shoot
	peeking = randf() < float(AIConfig.LEVEL_PEEK[lvl])
	# morale break
	if s.morale < 14.0 and not s.broken and s.health != Soldier.H.INCAP:
		s.broken = true
		if s.side == 0:
			sq.radio("suppressed", Loc.t("%s відходить у паніці") % s.display_name(), "warn")
	if s.broken:
		if s.morale > 38.0 or (s.global_position.distance_to(sq.rally) < 6.0 and s.suppression < 20.0):
			s.broken = false
		else:
			state = Loc.t("паніка")
			s.fire_ok = false
			s.target = null
			want_posture = Soldier.P.STAND
			if not s.moving:
				s.move_to(sq.rally, true)
			return
	# level 4: stress has piled up — he cowers in cover, does not shoot or move
	if lvl >= 4 and order != "retreat" and order != "escape":
		state = Loc.t("паніка")
		s.fire_ok = false
		s.target = null
		s.area_target = null
		want_posture = Soldier.P.CROUCH if s.in_trench() else Soldier.P.PRONE
		# he freezes where he is (a dash to cover already under way may finish);
		# when the fear subsides he returns to the order on his own
		if s.moving and s.cover_dash_t <= 0.0:
			s.stop()
		return
	if s.action != "":
		state = {"aid": Loc.t("допомога"), "grenade": Loc.t("граната"), "rocket": Loc.t("ПТ-постріл"), "atgm": Loc.t("пуск ПТУР"), "gl": Loc.t("граната"), "smoke": Loc.t("дим")}.get(s.action, Loc.t("дія"))
		return
	if _try_aid():
		state = Loc.t("допомога")
		return
	s.fire_ok = (s.target != null or s.area_target != null) and peeking
	if order == "retreat" or order == "escape":
		s.fire_ok = s.fire_ok and randf() < 0.35
	if s.fire_ok:
		_special_attacks()
		if s.action != "":
			return
	section_cd -= dt
	if _blind_grenade():
		return
	if s.side == 1 and _section_defence():
		return
	match order:
		"escort":
			state = Loc.t("конвоює полоненого")
			want_posture = Soldier.P.STAND
		"clear":
			s.fire_ok = s.target != null
			if s.moving:
				state = Loc.t("зачистка") if state != "граната за ріг" and state != "прострілює кут" else state
				want_posture = Soldier.P.CROUCH
			elif not s.arrived(2.0) and s.cqb_wait <= 0.0:
				s.move_to(s.slot, true)
			else:
				_hold_logic(threat, pinned, 3.0)
		"move", "retreat", "mount", "escape":
			if s.moving:
				state = Loc.t("рух") if order != "retreat" and order != "escape" else Loc.t("відхід")
				if order == "move" and threat and _refuses_move(lvl):
					_go_to_ground(lvl)
				else:
					want_posture = Soldier.P.CROUCH if threat and order == "move" else Soldier.P.STAND
			elif not s.arrived(2.0) and s.pinned_t <= 0.0:
				if order == "mount" and sq.vehicle != null:
					s.move_to(sq.vehicle.rear_point(), true)
				else:
					s.move_to(s.slot, true)
			else:
				_hold_logic(threat, pinned, 6.0)
		"assault":
			if s.can_advance:
				if s.moving:
					state = Loc.t("штурм")
					want_posture = Soldier.P.CROUCH if threat else Soldier.P.STAND
					if _refuses_move(lvl):
						_go_to_ground(lvl)
				elif not s.arrived(2.0) and s.pinned_t <= 0.0:
					s.move_to(s.slot, true)
				else:
					_hold_logic(threat, pinned, 4.0)
			else:
				_hold_logic(threat, pinned, 4.0)
				state = Loc.t("прикриття")
		"idle":
			_idle_logic(threat)
		_:
			# hold / defend
			if not s.moving and not s.arrived(4.0) and s.pinned_t <= 0.0 and s.bunker == null:
				s.move_to(s.slot, not threat or s.side == 1)
				state = Loc.t("висування")
			elif not s.moving:
				_hold_logic(threat, pinned, 6.0)
			else:
				want_posture = Soldier.P.CROUCH if threat else Soldier.P.STAND


func _hold_logic(threat: bool, pinned: bool, radius: float) -> void:
	var cv: float = W.grid.cover_at(s.global_position)
	if s.post != null:
		want_posture = Soldier.P.CROUCH
		state = Loc.t("бій біля вікна") if s.target != null else Loc.t("біля вікна")
		return
	if s.bunker != null:
		want_posture = Soldier.P.CROUCH
		state = Loc.t("бій") if s.target != null else Loc.t("спостереження")
		return
	if threat:
		if cover_t <= 0.0 and not pinned:
			cover_t = 7.0 + randf() * 2.0   # men do not all re-think at once
			var tp = s.squad.nearest_threat(s.global_position)
			# a poor spot, or a good one the known threat can see while it is
			# shooting at him (compromised): look for a better place
			var compromised: bool = tp != null and s.supp_level >= 1 and 				W.grid.visibility(tp + Vector3(0, 1.5, 0), s.global_position + Vector3(0, AIConfig.COVER_BODY_H, 0)) >= 0.3
			if cv < 0.3 or compromised:
				var c: Vector3 = W.grid.find_cover(s.global_position, radius, tp, s.squad.occupied(s), not s.is_medic)
				if Vector2(c.x - s.global_position.x, c.z - s.global_position.z).length() > 1.5:
					s.move_to(c, true)
					state = Loc.t("до укриття")
					return
		var lvl: int = s.supp_level
		var shoot: bool = peeking and (s.target != null or s.area_target != null)
		if s.in_trench():
			# below the parapet unless he is rising to fire
			want_posture = Soldier.P.STAND if shoot else Soldier.P.CROUCH
			state = Loc.t("бій") if shoot else (Loc.t("притиснутий в окопі") if lvl >= 3 else (Loc.t("пригнувся в окопі") if lvl >= 2 else Loc.t("в окопі")))
		elif pinned:
			want_posture = Soldier.P.PRONE
			state = Loc.t("притиснутий")
		elif cv >= 0.4:
			want_posture = Soldier.P.CROUCH if (shoot or lvl <= 1) else Soldier.P.PRONE
			state = Loc.t("бій") if shoot else (Loc.t("під вогнем") if lvl >= 2 else Loc.t("в укритті"))
		else:
			want_posture = Soldier.P.PRONE
			state = Loc.t("бій") if shoot else (Loc.t("під вогнем") if lvl >= 2 else Loc.t("лежить"))
	else:
		state = "очікування"
		want_posture = Soldier.P.CROUCH if s.side == 0 or s.in_trench() else Soldier.P.STAND


## Under fire a soldier may refuse to keep moving across open ground; the
## chance depends on the suppression level and his discipline. Moving to
## nearby cover is always allowed.
func _refuses_move(lvl: int) -> bool:
	if lvl < 2 or s.cover_dash_t > 0.0:
		return false
	if W.grid.cover_at(s.global_position) >= 0.4 and s.in_trench():
		return false   # moving inside a trench is moving in cover
	return randf() > float(AIConfig.LEVEL_MOVE[lvl]) * s.discipline


func _go_to_ground(lvl: int) -> void:
	s.stop()
	s.pinned_t = 2.0 + lvl * 1.2
	var cv: float = W.grid.cover_at(s.global_position)
	if cv < 0.3:
		var tp = s.squad.nearest_threat(s.global_position)
		var c: Vector3 = W.grid.find_cover(s.global_position, 6.0, tp, s.squad.occupied(s), not s.is_medic)
		if c.distance_to(s.global_position) > 1.5:
			s.pinned_t = 0.0
			s.cover_dash_t = 4.0
			s.move_to(c, true)
			state = Loc.t("кидок в укриття")
			return
	want_posture = Soldier.P.PRONE
	state = Loc.t("притиснутий") if lvl >= 3 else Loc.t("під вогнем")


func _idle_logic(threat: bool) -> void:
	# enemy calm state: sentries wander inside the trench, others rest
	if threat:
		_hold_logic(threat, false, 4.0)
		return
	state = Loc.t("чергування")
	want_posture = Soldier.P.CROUCH if randf() < 0.6 else Soldier.P.STAND
	if s.bunker != null or s.moving:
		return
	if idle_t <= 0.0:
		idle_t = randf_range(8.0, 20.0)
		if randf() < 0.35:
			var off = Vector3(randf_range(-6, 6), 0, randf_range(-2, 2))
			var p: Vector3 = s.slot + off
			if W.grid.is_trench(p):
				s.move_to(p, false)
		elif not s.arrived(3.0):
			s.move_to(s.slot, false)


## Grenade over the traverse at an enemy we know is there but cannot see.
func _blind_grenade() -> bool:
	if s.grenades <= 0 or s.grenade_cd > 0.0 or s.action != "":
		return false
	# outside a trench only when storming it (assault / clear), not from afar
	var storming: bool = s.in_trench() or (s.squad.order in ["assault", "clear", "clear_bld"] or s.solo in ["assault", "clear"])
	if not storming:
		return false
	var sp: Vector3 = s.global_position
	for e in s.squad.known.keys():
		if vis.has(e) or not W.is_alive_target(e) or not (e is Soldier):
			continue
		var kp: Vector3 = s.squad.known[e]["pos"]
		var d := sp.distance_to(kp)
		if d < 6.0 or d > 20.0 or W.time - float(s.squad.known[e]["t"]) > 8.0:
			continue
		if not W.grid.in_channel(kp, 1.3):
			continue
		if not GrenadeLogic.try_throw(s, kp, "hand", "blind", W.time - float(s.squad.known[e]["t"]), W.grid.cover_at(kp)):
			continue
		s.start_action("grenade", 1.1, kp + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), s.moving)
		state = "граната наосліп"
		return true
	return false


## Defenders give ground traverse by traverse when outnumbered in the trench.
func _section_defence() -> bool:
	if section_cd > 0.0 or not s.in_trench() or s.bunker != null:
		return false
	var sp: Vector3 = s.global_position
	var intr: Array = []
	var nearest = null
	var nd := 16.0
	for e in s.squad.known.keys():
		if not (e is Soldier) or not W.is_alive_target(e):
			continue
		var kp: Vector3 = s.squad.known[e]["pos"]
		var d := sp.distance_to(kp)
		if d < 16.0 and W.grid.in_channel(kp, 1.3):
			intr.append(e)
			if d < nd:
				nd = d
				nearest = kp
	if nearest == null:
		return false
	var allies := 0
	for u in W.units:
		if u.side == 1 and u != s and u.is_active() and u.global_position.distance_to(sp) < 9.0:
			allies += 1
	if intr.size() <= allies + 1 and s.morale > 35.0:
		return false
	section_cd = 9.0
	var node: int = W.grid.trench_net.fallback_node(sp, nearest, 12.0)
	if node < 0:
		return false
	s.slot = W.grid.trench_net.pts[node]
	s.move_to(s.slot, true)
	state = "відхід по траншеї"
	return true


func _special_attacks() -> void:
	var t = s.target
	if t == null or not W.is_alive_target(t):
		return
	var d: float = s.global_position.distance_to(t.global_position)
	if t is Vehicle or t is Bunker:
		if s.atgm > 0 and s.atgm_cd <= 0.0 and t is Vehicle and d < Db.ATGM["range"]:
			s.atgm_cd = Db.ATGM["reload"]
			s.atgm -= 1
			s.start_action("atgm", 3.2, t)
			return
		if s.rockets > 0 and s.rocket_cd <= 0.0 and d < Db.AT_ROCKET["range"]:
			s.rocket_cd = 9.0
			s.rockets -= 1
			s.start_action("rocket", 1.8, t)
		return
	var tc: float = t.cover_value()
	var tpos: Vector3 = t.global_position
	if GrenadeLogic.try_throw(s, tpos, "hand", "aimed", 0.0, tc):
		s.start_action("grenade", 1.1, tpos + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)))
	elif GrenadeLogic.try_throw(s, tpos, "gl", "aimed", 0.0, tc):
		s.start_action("gl", 0.7, tpos + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5)))


func _try_aid() -> bool:
	if s.health != Soldier.H.HEALTHY or s.suppression > 45.0 or s.bunker != null:
		return false
	var sq = s.squad
	# continue walking to an existing patient
	if s.aid_target != null:
		var at = s.aid_target
		if not is_instance_valid(at) or at.health != Soldier.H.INCAP or at.aided or at.carried or at.on_board:
			if is_instance_valid(at):
				at.aid_by = null
			s.aid_target = null
			return false
		var d: float = s.global_position.distance_to(at.global_position)
		# within reach — or as close as the ground lets him get (the casualty
		# may lie by a wall or in rubble where the cell next to him is blocked)
		if d < 1.6 or (d < 3.0 and not s.moving):
			s.start_action("aid", 6.0 if s.is_medic else 9.0, at)
			return true
		if W.time - s.aid_since > 20.0:
			# cannot get there: leave him to someone else / the evacuation
			at.aid_by = null
			s.aid_skip = at
			s.aid_target = null
			return false
		if not s.moving:
			s.move_to(W.grid.free_point(at.global_position + Vector3(0.8, 0, 0.4)), true)
		return true
	var reach = 40.0 if s.is_medic else 14.0
	var best = null
	var best_d = reach
	for m in sq.members:
		if m == s or m == s.aid_skip or m.health != Soldier.H.INCAP or m.aided or m.carried or m.on_board or m.evacuated:
			continue
		if m.aid_by != null and is_instance_valid(m.aid_by) and m.aid_by != s:
			continue
		var d: float = s.global_position.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best = m
	if best == null:
		return false
	if not s.is_medic:
		var tp = sq.nearest_threat(best.global_position)
		if tp != null and (tp as Vector3).distance_to(best.global_position) < 30.0:
			return false
	best.aid_by = s
	s.aid_target = best
	s.aid_since = W.time
	s.target = null
	s.move_to(W.grid.free_point(best.global_position + Vector3(0.8, 0, 0.4)), true)
	return true
