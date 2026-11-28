class_name EnemyAI
extends Node
## Enemy commander. Spawns the garrison, manages alert level and reacts to
## the fight: reinforcements from the reserve, MG relocation, local
## counter-attacks, fallback to the rear trench, full retreat, mortar fire.

var squads: Array = []
var reserve = null
var alert = 0
var tick = 2.0
var mortar_rounds = 9
var reg_rounds = 0          # kept for the pre-registered open approach
var mortar_cd = 70.0
var reserve_committed = false
var counterattack_done = false
var retreat_ordered = false
var relocate_cd = 40.0
var def: MapDef
var start_count = 0
var escaped = 0
var fpv_count = 4
var fpv_cd = 25.0
var fpv_active: Array = []
var shift_cd := 20.0   # the first shift can come soon after the alarm
var covering: Array = []    # men holding while their teams withdraw
var drone_known := {}       # our units reported by the recon drone: unit -> {pos, t}
var recon_left := -1        # sorties left (set from the difficulty when alerted)
var recon_t := -1.0         # when the next sortie takes off (-1: not alerted yet)
var recon = null
var stats := {"recon_sorties": 0, "recon_reports": 0, "recon_down": 0, "shifts_men": 0, "withdraw_cover": 0}
var shifts := 0
var fight_t := -1.0         # when the fight started (alert 2)
var reinf_init := false
var waves: Array = []       # [{after, men, vehicle, sent}]
var wave_units: Array = []  # men / vehicles of waves on the way (for the "arrived" call-out)
var wave_seen := false


func spawn(p_def: MapDef) -> void:
	def = p_def
	var rng = RandomNumberGenerator.new()
	rng.seed = randi()   # follows the global seed (tests: --seed)
	var bunkers: Array = W.bunkers
	for td in def.enemy_teams:
		var sq = Squad.new()
		sq.side = 1
		sq.team_name = td["name"]
		sq.sname = Loc.t("Противник: ") + String(td["name"])
		sq.short = String(td["name"])
		sq.rally = def.enemy_retreat
		sq.is_reserve = td.get("reserve", false)
		add_child(sq)
		W.squads.append(sq)
		squads.append(sq)
		# outdated intel: some positions are shuffled with alternatives
		var slots: Array = (td["slots"] as Array).duplicate()
		var alts: Array = (td["alt"] as Array).duplicate()
		for i in slots.size():
			if alts.size() > 0 and rng.randf() < 0.35:
				var k = rng.randi() % alts.size()
				var tmp = slots[i]
				slots[i] = alts[k]
				alts[k] = tmp
		var bunker_team: bool = int(td.get("bunker", -1)) >= 0
		if not bunker_team:
			# map coordinates are design points: put each one on the trench centre
			# line if it is meant to be in a trench (traverses shift the line)
			slots = _snap_slots(slots)
			alts = _snap_slots(alts)
		sq.defend_slots = slots
		sq.alt_slots = alts
		sq.fallback_slots = _snap_slots(td.get("fallback", []))
		var roles: Array = (td["roles"] as Array).duplicate()
		var bunker_i: int = td.get("bunker", -1)

		for i in roles.size():
			var u = Soldier.new()
			add_child(u)
			u.setup(1, roles[i], sq, "")
			var sp: Vector2 = slots[i % slots.size()]
			u.global_position = W.grid.ground(Vector3(sp.x, 0, sp.y))
			u.slot = u.global_position
			u.yaw = PI + rng.randf_range(-0.4, 0.4)
			u.rotation.y = u.yaw
			u.posture = Soldier.P.CROUCH
			Buildings.garrison(u)
			if bunker_i >= 0 and bunker_i < bunkers.size():
				var b: Bunker = bunkers[bunker_i]
				u.bunker = b
				u.bunker_deep = sq.is_reserve
				b.occupants.append(u)
			sq.members.append(u)
			# portable trench jammer: one per line team
			if i == 0 and bunker_i < 0 and not String(td["name"]).begins_with("ПТРК"):
				u.ew_carrier = true
			W.units.append(u)
		sq.order = "idle"
		if sq.is_reserve:
			reserve = sq
	start_count = 0
	for sq in squads:
		start_count += sq.members.size()


## The garrison is placed when the map loads (before the menu), so the
## difficulty chosen in the menu is applied when the mission starts.
func apply_difficulty() -> void:
	mortar_rounds = int(Game.diff("mortar"))
	reg_rounds = int(round(AIConfig.MORTAR_REGISTERED_STOCK * float(Game.diff("mortar")) / 7.0))
	fpv_count = int(Game.diff("fpv"))
	for sq in squads:
		for u in sq.members:
			u.max_morale *= float(Game.diff("enemy_morale"))
			u.morale = u.max_morale
		# easy: every line team of three or more is one man short
		if Game.diff("thin") and sq.members.size() >= 3 and not sq.is_reserve and sq.members[0].bunker == null:
			var u = sq.members.pop_back()
			W.units.erase(u)
			u.queue_free()
	if Game.mode == "campaign" and Game.campaign.active:
		_campaign_strength(Game.campaign.flags.get("next", {}))
	start_count = 0
	for sq in squads:
		start_count += sq.members.size()


## Campaign consequences: the garrison is bigger or smaller than planned,
## with more or fewer mortar rounds and FPV; fresh intel reveals the
## fortifications we already knew about.
var campaign_delta := 0


func _campaign_strength(nx: Dictionary) -> void:
	if nx.is_empty():
		return
	var k: float = float(nx.get("enemy_k", 1.0))
	var total := 0
	for sq in squads:
		total += sq.members.size()
	var delta := int(round(total * (k - 1.0)))
	campaign_delta = 0
	var line: Array = squads.filter(func(s): return not s.is_reserve and s.members.size() > 0 and s.members[0].bunker == null)
	var guard := 0
	while delta < 0 and guard < 200:
		guard += 1
		line.sort_custom(func(a, b): return a.members.size() > b.members.size())
		if line.is_empty() or line[0].members.size() < 2:
			break
		var u = line[0].members.pop_back()
		W.units.erase(u)
		u.queue_free()
		delta += 1
		campaign_delta -= 1
	var i := 0
	while delta > 0 and not line.is_empty() and guard < 200:
		guard += 1
		var sq = line[i % line.size()]
		_add_man(sq, "mg" if i % 4 == 3 else "rifleman")
		delta -= 1
		campaign_delta += 1
		i += 1
	mortar_rounds = int(round(mortar_rounds * k))
	reg_rounds = int(round(reg_rounds * k))
	fpv_count = int(round(fpv_count * k))
	if float(nx.get("intel_q", 0.0)) >= 0.7:
		for b in W.bunkers:
			if b.side == 1:
				b.ever_seen = true


## A reinforcement: one more man in a team, near its positions.
func _add_man(sq, role: String) -> void:
	var u = Soldier.new()
	add_child(u)
	u.setup(1, role, sq, "")
	var slots: Array = sq.alt_slots if sq.alt_slots.size() > 0 else sq.defend_slots
	var sp: Vector2 = slots[sq.members.size() % maxi(1, slots.size())] if slots.size() > 0 else Vector2(sq.center().x, sq.center().z)
	sp += Vector2(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0))
	u.global_position = W.grid.ground(Vector3(sp.x, 0, sp.y))
	u.slot = u.global_position
	u.yaw = PI + randf_range(-0.4, 0.4)
	u.rotation.y = u.yaw
	u.posture = Soldier.P.CROUCH
	u.max_morale *= float(Game.diff("enemy_morale"))
	u.morale = u.max_morale
	sq.members.append(u)
	W.units.append(u)


func active_total() -> int:
	var c = 0
	for sq in squads:
		c += sq.active_count()
	return c


func raise_alert(level: int) -> void:
	if level <= alert:
		return
	var was = alert
	alert = level
	if was == 0:
		for sq in squads:
			if sq == reserve:
				continue
			sq.set_defend(sq.defend_slots, true)


func on_friendly_fire(pos: Vector3) -> void:
	if alert >= 2:
		return
	for sq in squads:
		if sq.center().distance_to(pos) < 160.0:
			raise_alert(2)
			return


func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("enemy_ai", t0)


func _process_body(delta: float) -> void:
	if not W.running():
		return
	tick -= delta
	mortar_cd -= delta
	relocate_cd -= delta
	fpv_cd -= delta
	if tick > 0.0:
		return
	tick = 2.0
	_detect_vehicles()
	_check_escapes()
	_recon_drone()
	_reinforce()
	_fpv()
	if alert < 2:
		return
	_evaluate()


func _detect_vehicles() -> void:
	if alert >= 1:
		return
	# engines are heard: a moving vehicle of ours within earshot of any of
	# their men (never a hidden one far away)
	for v in W.vehicles:
		if v.side != 0 or v.offmap or v.state == "destroyed" or not v.moving:
			continue
		for sq in squads:
			for m in sq.members:
				if m.is_active() and m.global_position.distance_to(v.global_position) < AIConfig.ENGINE_HEARING:
					raise_alert(1)
					for s2 in squads:
						if s2 != reserve:
							s2.order = "defend"
					sq.hear(v.global_position, v)
					return


func _check_escapes() -> void:
	for sq in squads:
		if sq.order != "escape":
			continue
		for m in sq.members:
			if m.is_active() and m.global_position.distance_to(def.enemy_retreat) < 5.0:
				m.evacuated = true
				m.escaping = true
				m.model.visible = false
				escaped += 1


func _evaluate() -> void:
	var total = active_total()
	# full retreat when the position is collapsing
	if not retreat_ordered and not def.enemy_no_retreat and start_count > 0 and total <= max(2, int(start_count * 0.28)):
		retreat_ordered = true
		if W.blog:
			W.blog.add("enemy", Loc.t("Противник відходить з позиції"), null)
		_begin_withdrawal()
		var rep = null
		var bd := INF
		if W.mission:
			for fsq in W.mission.friendly_squads:
				if fsq.active_count() > 0 and fsq.center().distance_to(W.mission.def.enemy_retreat) < bd:
					bd = fsq.center().distance_to(W.mission.def.enemy_retreat)
					rep = fsq
		if rep != null:
			rep.radio("retreat", Loc.t("противник залишає позиції та відходить!"), "good")
		else:
			Events.msg(Loc.t("Противник залишає позиції та відходить!"), "good")
		return
	if retreat_ordered:
		_update_withdrawal()
		return
	for sq in squads:
		if sq == reserve and not reserve_committed:
			continue
		var n: int = sq.members.size()
		var act: int = sq.active_count()
		if act == 0:
			continue
		# fallback
		if sq.order == "defend" and n > 0 and (float(act) / n <= 0.34 or sq.avg_morale() < 25.0) and sq.fallback_slots.size() > 0:
			sq.defend_slots = sq.fallback_slots
			sq.set_defend(sq.fallback_slots, true)
			for m in sq.active_members():
				if m.bunker != null:
					m.bunker.release_occupant(m)
					m.move_to(m.slot, true)
			continue
		# reinforcement request
		if not reserve_committed and reserve != null and (W.time - sq.help_time < 8.0 or float(act) / n < 0.7):
			_commit_reserve(sq)
		# MG shoot-and-scoot
		if relocate_cd <= 0.0 and sq.alt_slots.size() > 0:
			for m in sq.active_members():
				if m.role == "mg" and m.suppression > 35.0 and m.bunker == null:
					var a: Vector2 = sq.alt_slots[randi() % sq.alt_slots.size()]
					m.slot = W.grid.ground(Vector3(a.x, 0, a.y))
					m.move_to(m.slot, true)
					relocate_cd = 35.0
					break
	_redistribute()
	_counterattack()
	_mortar()


## The teams pull back under smoke while one man of each covers them.
func _begin_withdrawal() -> void:
	var lone_covers := true
	for sq in squads:
		var act: Array = sq.active_members()
		if act.is_empty():
			continue
		sq.throw_smoke()
		var cover = null
		var pick: bool = act.size() >= 2
		if act.size() == 1:
			pick = lone_covers          # lone men: every other one covers
			lone_covers = not lone_covers
		if pick:
			var best_s := -INF
			for m in act:
				var sc: float = (2.0 if m.role == "mg" else 0.0) + m.discipline - m.supp_level * 0.5 + (1.0 if m.post != null or m.in_trench() else 0.0)
				if sc > best_s:
					best_s = sc
					cover = m
		sq.order = "escape"
		for m in act:
			if m == cover:
				m.solo = "hold"
				m.set_meta("cover_until", W.time + randf_range(AIConfig.WD_COVER_MIN, AIConfig.WD_COVER_MAX))
				covering.append(m)
				stats["withdraw_cover"] += 1
				continue
			_withdraw(m)


func _withdraw(m) -> void:
	m.solo = ""
	if m.bunker != null:
		m.bunker.release_occupant(m)
	if m.post != null:
		m.leave_post()
	m.slot = W.grid.ground(def.enemy_retreat + Vector3(randf_range(-8, 8), 0, 0))
	m.move_to(m.slot, true)


func _update_withdrawal() -> void:
	var i := covering.size() - 1
	while i >= 0:
		var m = covering[i]
		if not is_instance_valid(m) or not m.is_active():
			covering.remove_at(i)
		elif W.time > float(m.get_meta("cover_until", 0.0)) or m.supp_level >= 3:
			_withdraw(m)
			covering.remove_at(i)
		i -= 1


## A team under more pressure than it can take gets a pair from the
## calmest team nearby — judged only by what the teams have seen of us.
func _redistribute() -> void:
	shift_cd -= 2.0
	var press := {}
	for sq in squads:
		if sq.order == "escape" or sq.active_count() == 0:
			continue
		var c: Vector3 = sq.center()
		var n := 0
		for e in sq.known.keys():
			if not (e is Soldier) or not W.is_alive_target(e):
				continue
			var k: Dictionary = sq.known[e]
			if W.time - float(k["t"]) < AIConfig.SHIFT_SEEN_T and (k["pos"] as Vector3).distance_to(c) < AIConfig.SHIFT_R:
				n += 1
		press[sq] = n
		if n > 0:
			sq.set_meta("press_t", W.time)
	if shift_cd > 0.0 or shifts >= AIConfig.SHIFT_MAX:
		return
	var tgt = null
	var worst := 0.0
	for sq in press.keys():
		var r: float = float(press[sq]) / maxf(sq.active_count(), 1)
		if press[sq] >= AIConfig.SHIFT_MIN_SEEN and r >= AIConfig.SHIFT_RATIO and r > worst:
			worst = r
			tgt = sq
	if tgt == null:
		return
	var donor = null
	var dd := AIConfig.SHIFT_DIST
	for sq in press.keys():
		if sq == tgt or (sq == reserve and not reserve_committed) or not (sq.order in ["defend", "idle"]):
			continue
		if W.time - float(sq.get_meta("press_t", -999.0)) < AIConfig.SHIFT_CALM_T:
			continue
		if sq.active_count() < AIConfig.SHIFT_KEEP + 1:
			continue
		var d: float = sq.center().distance_to(tgt.center())
		if d < dd:
			dd = d
			donor = sq
	if donor == null:
		return
	# where they go: the posts of the fallen first, then the team's alternates
	var spots: Array = []
	for i in tgt.members.size():
		if not tgt.members[i].is_active() and tgt.defend_slots.size() > 0:
			spots.append(tgt.defend_slots[i % tgt.defend_slots.size()])
	spots.append_array(tgt.alt_slots)
	if spots.is_empty():
		var cc: Vector3 = tgt.center()
		spots = [Vector2(cc.x + 3, cc.z), Vector2(cc.x - 3, cc.z)]
	var sent: Array = []
	var can_send: int = mini(AIConfig.SHIFT_MEN, donor.active_count() - AIConfig.SHIFT_KEEP)
	for m in donor.active_members():
		if sent.size() >= can_send:
			break
		if m.role in ["mg", "atgm", "leader"] or m.bunker != null:
			continue   # the team's key weapons stay where they are
		var sp: Vector2 = spots[sent.size() % spots.size()]
		if m.post != null:
			m.leave_post()
		m.slot = W.grid.free_point(Vector3(sp.x + randf_range(-1.5, 1.5), 0, sp.y + randf_range(-1.5, 1.5)))
		m.move_to(m.slot, true)
		sent.append(m)
	if sent.is_empty():
		return
	shifts += 1
	stats["shifts_men"] += sent.size()
	shift_cd = AIConfig.SHIFT_CD
	if W.blog:
		W.blog.add("enemy", Loc.t("Противник перекидає сили на загрозливий напрямок"), tgt.center())
	if "--verbose" in OS.get_cmdline_user_args() or "--aitest=shift" in OS.get_cmdline_user_args():
		print("[SHIFT] t=%d %d men %s -> %s (seen %d of ours vs %d of theirs)" % [int(W.time), sent.size(), donor.team_name, tgt.team_name, press[tgt], tgt.active_count()])


func _commit_reserve(target_sq) -> void:
	reserve_committed = true
	var slots: Array = []
	# fill gaps of the requesting team first, then its alternates
	for i in target_sq.members.size():
		if not target_sq.members[i].is_active():
			slots.append(target_sq.defend_slots[i % target_sq.defend_slots.size()])
	slots.append_array(target_sq.alt_slots)
	if slots.is_empty():
		slots = target_sq.defend_slots
	for m in reserve.members:
		if m.bunker != null:
			m.bunker.release_occupant(m)
	reserve.alt_slots = target_sq.alt_slots
	reserve.fallback_slots = target_sq.fallback_slots
	reserve.set_defend(slots, true)


func _counterattack() -> void:
	if counterattack_done:
		return
	# only intruders some team actually knows about (seen / heard recently)
	var intruders: Array = []
	var ipos := {}
	for sq in squads:
		for e in sq.known.keys():
			if not (e is Soldier) or not W.is_alive_target(e) or W.time - float(sq.known[e]["t"]) > 15.0:
				continue
			var kp: Vector3 = sq.known[e]["pos"]
			if def.objective_rect.grow(4.0).has_point(Vector2(kp.x, kp.z)) and not ipos.has(e):
				intruders.append(e)
				ipos[e] = kp
	if intruders.is_empty():
		return
	var best = null
	for sq in squads:
		if sq.order == "escape" or sq.active_count() < 3:
			continue
		if sq.center().distance_to(ipos[intruders[0]]) < 45.0:
			best = sq
			break
	if best == null:
		return
	if intruders.size() > best.active_count() + 1:
		return
	counterattack_done = true
	best.issue_order("assault", ipos[intruders[0]])
	Events.msg(Loc.t("Противник контратакує в окопах!"), "alert")
	if W.blog:
		W.blog.add("enemy", Loc.t("Контратака противника в окопах"), ipos[intruders[0]])


## Radio net: armour sightings are passed to every team (ATGM crews use it).
func share(from_sq, e, pos: Vector3) -> void:
	for sq in squads:
		if sq != from_sq:
			sq.known[e] = {"t": W.time, "pos": pos}


func _known_targets() -> Dictionary:
	var known = {}
	for sq in squads:
		for e in sq.known.keys():
			if W.time - float(sq.known[e]["t"]) < 15.0 and W.is_alive_target(e):
				known[e] = sq.known[e]["pos"]
	for e in drone_known.keys():
		if W.time - float(drone_known[e]["t"]) < 15.0 and W.is_alive_target(e):
			known[e] = drone_known[e]["pos"]
	return known


## Reinforcement waves from the rear, once the fight has gone on a while.
func _reinforce() -> void:
	if alert < 2 or retreat_ordered:
		return
	if not reinf_init:
		reinf_init = true
		fight_t = W.time
		waves = []
		var cfg: Array = def.reinforcements
		if cfg.is_empty():
			# the default wave follows the difficulty (none on easy / the training ground)
			var after := float(Game.diff("reinf_after"))
			if float(Game.diff("mortar")) > 0.0 and after > 0.0:
				var men: Array = AIConfig.REINF_MEN.slice(0, int(Game.diff("reinf_men")))
				cfg = [{"after": after, "men": men, "vehicle": "bmp2" if def.size >= float(Game.diff("reinf_veh_size")) else ""}]
		for w in cfg:
			if not w.get("none", false):
				waves.append({"after": float(w.get("after", AIConfig.REINF_AFTER)), "men": w.get("men", AIConfig.REINF_MEN),
					"vehicle": String(w.get("vehicle", "")), "sent": false})
	for w in waves:
		if w["sent"] or W.time - fight_t < float(w["after"]):
			continue
		# they come from the rear, never in front of our men
		var entry: Vector3 = W.grid.ground(def.enemy_retreat)
		var seen := false
		for u in W.units:
			if u.side == 0 and u.is_active() and u.global_position.distance_to(entry) < AIConfig.REINF_UNSEEN_R:
				seen = true
				break
		if seen:
			continue
		w["sent"] = true
		_send_wave(w, entry)
	# the call-out when our side first sees them
	if not wave_seen:
		for u in wave_units:
			if is_instance_valid(u) and ((u is Soldier and u.ever_seen) or (u is Vehicle and u.ever_seen)):
				wave_seen = true
				Events.msg(Loc.t("Противник підтягує підкріплення!"), "alert")
				if W.blog:
					W.blog.add("enemy", Loc.t("Противник підтягує підкріплення"), u.global_position)
				break


func _send_wave(w: Dictionary, entry: Vector3) -> void:
	var obj := Vector3(def.objective_rect.get_center().x, 0, def.objective_rect.get_center().y)
	var sq = Squad.new()
	sq.side = 1
	sq.team_name = Loc.t("Підкріплення %d") % (waves.find(w) + 1)
	sq.sname = Loc.t("Противник: ") + Loc.t("підкріплення")
	sq.short = sq.team_name
	sq.rally = def.enemy_retreat
	add_child(sq)
	W.squads.append(sq)
	squads.append(sq)
	# where they go: the posts of the fallen in the objective first
	var spots: Array = []
	for s2 in squads:
		if s2 == sq:
			continue
		for i in s2.members.size():
			if not s2.members[i].is_active() and s2.defend_slots.size() > 0:
				var sp: Vector2 = s2.defend_slots[i % s2.defend_slots.size()]
				if def.capture_rect.grow(10.0).has_point(sp):
					spots.append(sp)
	while spots.size() < (w["men"] as Array).size():
		spots.append(Vector2(obj.x + randf_range(-15, 15), obj.z + randf_range(-10, 10)))
	sq.defend_slots = spots
	sq.fallback_slots = []
	var i := 0
	for role in w["men"]:
		var u = Soldier.new()
		add_child(u)
		u.setup(1, role, sq, "")
		u.global_position = W.grid.free_point(entry + Vector3((i - 3) * 2.0, 0, randf_range(-2, 2)))
		u.max_morale *= float(Game.diff("enemy_morale"))
		u.morale = u.max_morale
		sq.members.append(u)
		W.units.append(u)
		wave_units.append(u)
		i += 1
	sq.set_defend(spots, true)
	start_count += sq.members.size()
	if w["vehicle"] != "":
		get_tree().create_timer(AIConfig.REINF_VEH_DELAY).timeout.connect(_send_vehicle.bind(String(w["vehicle"]), entry, obj))
	if "--verbose" in OS.get_cmdline_user_args() or "--aitest=reinf" in OS.get_cmdline_user_args():
		print("[REINF] t=%d wave: %d men%s from %s" % [int(W.time), sq.members.size(), (" + " + String(w["vehicle"])) if w["vehicle"] != "" else "", entry.snapped(Vector3.ONE)])


func _send_vehicle(vt: String, entry: Vector3, obj: Vector3) -> void:
	if not W.running() or retreat_ordered:
		return
	var v = Vehicle.new()
	W.mission.add_child(v)
	v.setup(vt, 1, Loc.t("Ворожа %s") % Db.VEHICLES[vt]["name"])
	v.global_position = W.grid.free_point(entry, true)
	v.visible = false
	W.vehicles.append(v)
	wave_units.append(v)
	# it stops short of the objective, on the enemy side, and fights from there
	var dir := (obj - entry)
	dir.y = 0.0
	var stop := obj - dir.normalized() * 25.0
	v.order_move(W.grid.free_point(stop, true))
	stats["veh"] = int(stats.get("veh", 0)) + 1


## The recon drone — up some time after the alarm, a couple of sorties.
func _recon_drone() -> void:
	if recon_left < 0:
		recon_left = int(Game.diff("recon_sorties"))
	if alert < 1 or recon_left <= 0 or retreat_ordered:
		return
	if float(Game.diff("mortar")) <= 0.0 and fpv_count <= 0:
		return   # nothing to direct (the training ground)
	if recon != null and is_instance_valid(recon):
		return
	if recon_t < 0.0:
		recon_t = W.time + randf_range(AIConfig.RECON_DELAY[0], AIConfig.RECON_DELAY[1])
		return
	if W.time < recon_t:
		return
	recon_left -= 1
	stats["recon_sorties"] += 1
	recon_t = W.time + AIConfig.RECON_TIME + AIConfig.RECON_GAP
	var half: float = def.size * 0.5
	var c := Vector3(def.objective_rect.get_center().x, 0, def.objective_rect.get_center().y)
	recon = ReconDrone.new()
	W.mission.add_child(recon)
	recon.setup(Vector3(c.x + randf_range(-40, 40), W.grid.height_at(c.x, c.z) + AIConfig.RECON_ALT, clampf(c.z - 40.0, -half, half)), AIConfig.RECON_TIME)


## FPV strikes from an off-map crew: armour first, then infantry groups.
func _fpv() -> void:
	var i = fpv_active.size() - 1
	while i >= 0:
		if not is_instance_valid(fpv_active[i]):
			fpv_active.remove_at(i)
		i -= 1
	if alert < 1 or fpv_count <= 0 or fpv_cd > 0.0 or fpv_active.size() >= 2 or retreat_ordered:
		return
	var known = _known_targets()
	var best = null
	var best_s = 0.0
	for e in known.keys():
		var sc = 0.0
		if e is Vehicle:
			sc = (5.0 if e.is_medevac else 10.0) + (3.0 if not e.moving else 0.0)
		elif e is Soldier:
			var n = 0
			for f in known.keys():
				if f is Soldier and (known[f] as Vector3).distance_to(known[e]) < 9.0:
					n += 1
			if n >= 4:
				sc = float(n)
		if sc > best_s:
			best_s = sc
			best = e
	if best == null:
		return
	fpv_count -= 1
	fpv_cd = randf_range(40.0, 70.0)
	var half: float = def.size * 0.5
	var start = Vector3(randf_range(-40, 40), 25, -half - 45)
	fpv_active.append(W.combat.fpv_strike(best, start, 1))
	var what: String = best.vname if best is Vehicle else Loc.t("піхоту")
	Events.msg(Loc.t("УВАГА! Ворожий FPV-дрон заходить на %s!") % what, "alert")


## Radio-recon (РЕР) has direction-found our drone link: the enemy learns the
## approximate positions of our troops and fires on the densest group.
func on_rer_fix() -> void:
	raise_alert(2)
	var ours: Array = []
	for u in W.units:
		if u.side == 0 and u.is_active() and u.role != "crew_medic":
			ours.append(u)
	for v in W.vehicles:
		if v.side == 0 and W.is_alive_target(v):
			ours.append(v)
	if ours.is_empty():
		return
	# the fix gives a bearing on the drone link, i.e. only the AREA under the
	# drone: our troops it was hovering over, with a large error
	var dp: Vector3 = W.cam.cam.global_position if W.cam and W.cam.cam else ours[0].global_position
	dp.y = 0.0
	var near: Array = []
	for u in ours:
		var g: Vector3 = u.global_position
		g.y = 0.0
		if g.distance_to(dp) < AIConfig.RER_AREA:
			near.append(u)
	var err := AIConfig.RER_ERROR
	for sq in squads:
		for u in near:
			if randf() < 0.5:
				sq.known[u] = {"t": W.time, "pos": u.global_position + Vector3(randf_range(-err, err), 0, randf_range(-err, err))}
	var best: Vector3 = dp + Vector3(randf_range(-err, err), 0, randf_range(-err, err))
	if not near.is_empty():
		var c := Vector3.ZERO
		for u in near:
			c += u.global_position
		best = c / near.size() + Vector3(randf_range(-err, err), 0, randf_range(-err, err))
	Events.msg(Loc.t("РЕР противника запеленгувала канал нашого дрона! Очікуйте вогневе ураження."), "alert")
	if mortar_rounds > 0:
		var r = mini(3, mortar_rounds)
		mortar_rounds -= r
		mortar_cd = maxf(mortar_cd, 30.0)
		W.combat.mortar_strike(best, r, 12.0, 1)
	elif fpv_count > 0:
		fpv_count -= 1
		var half: float = def.size * 0.5
		fpv_active.append(W.combat.fpv_strike(best, Vector3(randf_range(-40, 40), 25, -half - 45), 1))


func _snap_slots(list: Array) -> Array:
	var out: Array = []
	for sp in list:
		var c: Vector3 = W.grid.trench_closest(sp.x, sp.y)
		out.append(Vector2(c.x, c.y) if c.z < 2.6 else sp)
	return out


func _in_open_approach(p: Vector3) -> bool:
	var zone: Rect2 = W.mission.def.mortar_zone
	if zone.size == Vector2.ZERO:
		# default: the 60 m strip in front of the enemy position
		var c: Rect2 = W.mission.def.capture_rect
		zone = Rect2(c.position.x, c.end.y, c.size.x, 60.0)
	if not zone.has_point(Vector2(p.x, p.z)):
		return false
	# men in cover (a crater, a trench, a tree line, a building) are not the
	# plotted field's easy target
	if W.grid.in_channel(p, 1.5) or W.grid.foliage_at(p) > 0.3 or W.grid.cover_at(p) > 0.4:
		return false
	return true


func _mortar() -> void:
	if (mortar_rounds <= 0 and reg_rounds <= 0) or mortar_cd > 0.0:
		return
	# find a cluster of known friendlies
	var known = {}
	for sq in squads:
		for e in sq.known.keys():
			if W.time - float(sq.known[e]["t"]) < 15.0:
				known[e] = sq.known[e]["pos"]
	for e in drone_known.keys():
		if W.time - float(drone_known[e]["t"]) < 15.0:
			known[e] = drone_known[e]["pos"]
	var best_p = null
	var best_n = 0
	for e in known.keys():
		var p: Vector3 = known[e]
		var c = 0
		for f in known.keys():
			if (known[f] as Vector3).distance_to(p) < 12.0:
				c += 3 if f is Vehicle else 1
		if c > best_n:
			best_n = c
			best_p = p
	if best_p == null:
		return
	# pre-registered fire: the open field in front of the position is plotted,
	# so troops caught there get a quicker, tighter barrage than troops in cover
	var registered: bool = _in_open_approach(best_p)
	if best_n < (AIConfig.MORTAR_REGISTERED_MIN if registered else AIConfig.MORTAR_UNPLOTTED_MIN):
		return
	var rounds := 0
	if registered and reg_rounds > 0:
		rounds = mini(3, reg_rounds)
		reg_rounds -= rounds
	else:
		if mortar_rounds <= 0:
			return
		rounds = mini(3, mortar_rounds)
		mortar_rounds -= rounds
	mortar_cd = randf_range(30.0, 45.0) if registered else randf_range(55.0, 80.0)
	W.combat.mortar_strike(best_p, rounds, 5.0 if registered else AIConfig.MORTAR_UNPLOTTED_SPREAD, 1)
	Events.msg(Loc.t("Увага! Вхідний мінометний вогонь противника!"), "alert")
