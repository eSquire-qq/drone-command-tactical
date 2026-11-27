class_name MissionManager
extends Node
## Mission flow: briefing -> planning -> deployment -> combat -> results.
## Spawns the player's force from the loadout, tracks objectives & stats.

enum Phase { BRIEFING, PLANNING, DEPLOY, COMBAT, ENDED }

var phase = Phase.BRIEFING
var def: MapDef
var t = 0.0
var capture = 0.0
var support = {"mortar": 0, "fpv": 0, "smoke": 0}
var support_used = {"mortar": 0, "fpv": 0, "smoke": 0}
var loadout = {}
var friendly_squads: Array = []
var friendly_vehicles: Array = []
var spawn_queue: Array = []
var spawn_t = 0.0
var _check_t = 0.0
var result = {}
var status_text = ""
var _name_i = 0
var budget_at_start := 1000.0
var objectives: Objectives


func setup(p_def: MapDef) -> void:
	def = p_def
	objectives = Objectives.new(def)
	W.enemy_ai.spawn(def)


func running() -> bool:
	return phase == Phase.DEPLOY or phase == Phase.COMBAT


func set_phase(p: int) -> void:
	phase = p
	Events.phase_changed.emit(p)


func time_left() -> float:
	return maxf(0.0, def.time_limit - t)


# ------------------------------------------------------------------ start
func start_mission() -> void:
	loadout = Game.loadout.duplicate()
	budget_at_start = Game.budget()
	if Game.mode == "campaign":
		Game.campaign.supply -= maxi(0, Game.loadout_cost(loadout) - Game.mission_grant())
		Game.campaign.save()
	support["mortar"] = int(loadout.get("mortar", 0))
	support["fpv"] = int(loadout.get("fpv", 0))
	support["smoke"] = int(loadout.get("smoke", 0))
	W.ew.spares = int(loadout.get("recon_drone", 0))
	W.evac.setup(int(loadout.get("medevac", 0)))
	W.enemy_ai.apply_difficulty()
	_build_force()
	set_phase(Phase.DEPLOY)
	W.cam.focus_on(def.camera_start, 85.0)
	Events.msg(Loc.t("Початок операції. Підрозділи висуваються на вихідні рубежі."), "info")
	W.sfx.ui("radio")


func _next_name() -> String:
	_name_i += 1
	return Db.SURNAMES[(_name_i * 5 + 3) % Db.SURNAMES.size()]


func _build_force() -> void:
	var vehicles: Array = []
	for vt in ["bmp2", "bmp1", "m113"]:
		for i in int(loadout.get(vt, 0)):
			vehicles.append(vt)
	var squads_spec: Array = []
	for st in ["assault_group", "rifle_squad"]:
		for i in int(loadout.get(st, 0)):
			squads_spec.append(st)
	var sq_n = 0
	var asl_n = 0
	var kind_idx := {}
	var veh_objs: Array = []
	var vnum = 21
	for vt in vehicles:
		var v = Vehicle.new()
		add_child(v)
		var nm = "%s «%d»" % [Db.VEHICLES[vt]["name"], vnum]
		vnum += 1
		v.setup(vt, 0, nm)
		v.offmap = true
		v.global_position = def.player_entry + Vector3(0, -30, 60)
		v.visible = false
		W.vehicles.append(v)
		friendly_vehicles.append(v)
		veh_objs.append(v)
	var free_cap: Array = []
	for v in veh_objs:
		free_cap.append(v.capacity())
	var dp_i = 0
	# the column goes where the player chose on the briefing photo
	var dpts: Array = def.dismount_points
	var dep: Dictionary = Game.deploy_for(def)
	if not dep.is_empty():
		# keep the layout of the dismount points around the chosen point,
		# spread along the option's axis (a flank forest track runs N-S)
		var c := def.dismount_center()
		var ax: Vector2 = dep.get("axis", Vector2(1, 0)).normalized()
		var pr := Vector2(-ax.y, ax.x)
		dpts = []
		for p in def.dismount_points:
			var o := Vector2(p.x - c.x, p.z - c.y)
			var q: Vector2 = dep["pos"] + ax * o.x + pr * o.y
			dpts.append(Vector3(q.x, 0, q.y))
		Events.msg(Loc.t("Колона висувається в район «%s».") % dep["name"], "info")
	for st in squads_spec:
		var sq = Squad.new()
		sq.side = 0
		sq.kind = st
		if st == "assault_group":
			asl_n += 1
			sq.sname = Loc.t("Штурмова група %d") % asl_n
			sq.short = Loc.t("Ш-%d") % asl_n
		else:
			sq_n += 1
			sq.sname = Loc.t("%d-ше відділення") % sq_n
			sq.short = Loc.t("В-%d") % sq_n
		sq.rally = def.rally_point
		add_child(sq)
		W.squads.append(sq)
		friendly_squads.append(sq)
		var roles: Array = Game.CATALOG[st]["roles"]
		var ki: int = kind_idx.get(st, 0)
		kind_idx[st] = ki + 1
		var cunit = Game.campaign.unit_by_kind_index(st, ki) if Game.mode == "campaign" else null
		if cunit != null:
			sq.sname = Loc.t(cunit["name"])
			sq.short = Loc.t(cunit["short"])
			roles = []
			for cs in Game.campaign.ready_members(cunit):
				var rk: Dictionary = Campaign.rank_of(int(cs["xp"]))
				var u = Soldier.new()
				add_child(u)
				u.setup(0, cs["role"], sq, cs["name"])
				u.camp_id = cs["id"]
				u.apply_rank(rk)
				u.apply_memory(cs)
				u.apply_cohesion(float(cunit.get("cohesion", 1.0)))
				sq.members.append(u)
				W.units.append(u)
				roles.append(cs["role"])
		else:
			for r in roles:
				var u = Soldier.new()
				add_child(u)
				u.setup(0, r, sq, _next_name())
				sq.members.append(u)
				W.units.append(u)
		# transport assignment
		var vi = -1
		for i in veh_objs.size():
			if veh_objs[i].squad == null and free_cap[i] >= roles.size():
				vi = i
				break
		var dpt: Vector3 = _dest(dpts[dp_i % dpts.size()])
		dp_i += 1
		if vi >= 0:
			var v: Vehicle = veh_objs[vi]
			v.squad = sq
			sq.vehicle = v
			sq.mounted = true
			sq.order = "mounted"
			free_cap[vi] = 0
			for u in sq.members:
				v.board(u)
			spawn_queue.append({"v": v, "dest": dpt})
		else:
			# waits off-map until its turn in the column
			for u in sq.members:
				u.on_board = true
				u.global_position = W.grid.ground(def.foot_spawn)
			spawn_queue.append({"squad": sq, "dest": dpt})
	# empty vehicles still come as fire support
	for v in veh_objs:
		if v.squad == null:
			var dpt: Vector3 = _dest(dpts[dp_i % dpts.size()] + Vector3(0, 0, -6))
			dp_i += 1
			spawn_queue.append({"v": v, "dest": dpt})


## A shifted dismount point: inside the map and on free ground.
func _dest(p: Vector3) -> Vector3:
	var h := def.size * 0.5 - 6.0
	p.x = clampf(p.x, -h, h)
	p.z = clampf(p.z, -h, h)
	return W.grid.free_point(p)


func _spawn_next() -> void:
	if spawn_queue.is_empty():
		return
	var e: Dictionary = spawn_queue.pop_front()
	if e.has("v"):
		var v: Vehicle = e["v"]
		v.offmap = false
		v.visible = true
		v.global_position = W.grid.ground(def.player_entry)
		v.set_yaw(0.0)
		v.auto_dismount = v.squad != null
		v.order_move(e["dest"])
		if v.squad:
			Events.msg(Loc.t("%s з десантом (%s) входить у район.") % [v.vname, v.squad.short], "info")
		else:
			Events.msg(Loc.t("%s входить у район.") % v.vname, "info")
	else:
		var sq: Squad = e["squad"]
		var i = 0
		for u in sq.members:
			u.on_board = false
			u.global_position = W.grid.free_point(def.foot_spawn + Vector3((i - 4) * 1.6, 0, randf_range(-1, 1)))
			i += 1
		sq.mounted = false
		sq.issue_order("move", e["dest"])
		Events.msg(Loc.t("%s висувається пішки.") % sq.short, "info")


# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("mission", t0)


func _process_body(delta: float) -> void:
	if not running():
		return
	t += delta
	W.time += delta
	W.update_smoke()
	if not spawn_queue.is_empty():
		spawn_t -= delta
		if spawn_t <= 0.0:
			spawn_t = 5.0
			_spawn_next()
	if phase == Phase.DEPLOY and spawn_queue.is_empty():
		var any_mounted = false
		for sq in friendly_squads:
			if sq.mounted and sq.vehicle != null and sq.vehicle.auto_dismount:
				any_mounted = true
		if not any_mounted:
			set_phase(Phase.COMBAT)
			Events.msg(Loc.t("Висадку завершено. Підрозділи готові до виконання завдання."), "info")
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 1.0
		_check_end()


func enemies_in_zone() -> int:
	var c = 0
	for u in W.units:
		if u.side == 1 and u.is_active() and def.capture_rect.has_point(Vector2(u.global_position.x, u.global_position.z)):
			c += 1
	return c


func friendlies_in_zone() -> int:
	var c = 0
	for u in W.units:
		if u.side == 0 and u.is_active() and u.role != "crew_medic" and def.objective_rect.grow(3.0).has_point(Vector2(u.global_position.x, u.global_position.z)):
			c += 1
	return c


func friendly_combat_strength() -> int:
	var c = 0
	for sq in friendly_squads:
		for m in sq.members:
			if m.health < Soldier.H.INCAP and not m.evacuated:
				c += 1
	return c


func _check_end() -> void:
	if objectives.type() != "capture":
		if phase == Phase.COMBAT and objectives.primary_done():
			end_mission("completed")
			return
		if phase == Phase.COMBAT and friendly_combat_strength() == 0:
			end_mission("wiped")
			return
		if t >= def.time_limit:
			end_mission("timeout")
		return
	var ez = enemies_in_zone()
	var fz = friendlies_in_zone()
	if ez == 0 and fz >= 2:
		capture += 0.1
		status_text = Loc.t("ЗАКРІПЛЕННЯ НА ПОЗИЦІЇ %d%%") % int(capture * 100)
		if capture >= 1.0:
			end_mission("captured")
			return
	else:
		capture = maxf(0.0, capture - 0.05)
		if fz > 0:
			status_text = Loc.t("БІЙ ЗА ПОЗИЦІЮ: противника в зоні — %d") % ez if ez > 0 else Loc.t("ЗАЧИЩЕННЯ")
		else:
			status_text = ""
	if phase == Phase.COMBAT and friendly_combat_strength() == 0:
		end_mission("wiped")
		return
	if t >= def.time_limit:
		end_mission("timeout")


func use_support(kind: String) -> bool:
	if int(support.get(kind, 0)) <= 0:
		return false
	support[kind] -= 1
	support_used[kind] += 1
	return true


func _campaign_outcome(r: Dictionary) -> Dictionary:
	var outcomes := {}
	for u in W.units:
		if u.side != 0 or u.camp_id == "":
			continue
		var st := "ok"
		if u.health == Soldier.H.DEAD:
			st = "kia"
		elif u.evacuated:
			st = "evacuated"
		elif u.health == Soldier.H.INCAP:
			st = "incap"
		elif u.health == Soldier.H.WOUNDED:
			st = "wounded"
		var mates := 0
		if u.squad:
			for m in u.squad.members:
				if m != u and m.health == Soldier.H.DEAD:
					mates += 1
		outcomes[u.camp_id] = {"state": st, "kills": u.kills, "pinned_s": u.pinned_s, "panicked": u.panicked, "role": u.role,
			"comrades_lost": mates, "wounded": u.was_wounded}
	var lost: Array = []
	for v in friendly_vehicles:
		if v.state == "destroyed":
			lost.append(v.vtype)
	for run in W.evac.runs:
		if run["phase"] == "destroyed":
			lost.append("medevac")
	return Game.campaign.apply_result(r, outcomes, lost)


# ------------------------------------------------------------------ results
func end_mission(reason: String) -> void:
	if phase == Phase.ENDED:
		return
	var r = {}
	r["reason"] = reason
	r["captured"] = reason == "captured"
	r["success"] = reason == "captured" or reason == "completed"
	r["objective"] = objectives.primary_title()
	r["objective_type"] = objectives.type()
	r["time"] = t
	var kia = 0
	var wia = 0
	var evac = 0
	var wia_left = 0
	var total = 0
	for u in W.units:
		if u.side != 0:
			continue
		total += 1
		if u.health == Soldier.H.DEAD:
			kia += 1
		elif u.was_wounded:
			wia += 1
			if u.evacuated:
				evac += 1
			elif u.health == Soldier.H.INCAP or u.health == Soldier.H.WOUNDED:
				wia_left += 1
	var vlost = 0
	var vlist: Array = []
	for v in W.vehicles:
		if v.side == 0 and v.state == "destroyed":
			vlost += 1
			vlist.append(v.vname)
	var e_dead = 0
	var e_wia = 0
	var e_total = 0
	for u in W.units:
		if u.side != 1:
			continue
		e_total += 1
		if u.health == Soldier.H.DEAD:
			e_dead += 1
		elif u.health == Soldier.H.INCAP:
			e_wia += 1
	var e_esc: int = W.enemy_ai.escaped
	var pows: int = W.prisoners.captured if W.prisoners else 0
	var pows_pending := 0
	for u in W.units:
		if u.side == 1 and u.surrendered and not u.captured and u.health < Soldier.H.INCAP:
			pows_pending += 1
	var spent = Game.loadout_cost(loadout)
	var unused = 0
	for k in support.keys():
		unused += int(support[k]) * int(Game.CATALOG[k]["cost"])
	var used_cost = spent - unused
	# score: the task (40) + damage to the enemy (20) + people kept alive (25)
	# + care for the wounded (10) + vehicles kept (5) + economy (5) + bonuses
	var score = 0.0
	if r["success"]:
		score += 40.0
	if e_total > 0:
		score += 20.0 * float(e_dead + e_wia + e_esc + pows + pows_pending) / e_total
	var combat_pers := maxf(1.0, float(total - 2 * W.evac.runs.size()))
	score += 25.0 * clampf(1.0 - float(kia) / (0.5 * combat_pers), 0.0, 1.0)
	if wia > 0:
		score += 10.0 * float(evac) / wia
	else:
		score += 10.0
	score -= 1.0 * wia_left
	var vtot := maxf(1.0, float(friendly_vehicles.size()))
	score += 5.0 * (1.0 - float(vlost) / vtot)
	score += 5.0 * clampf(1.0 - float(used_cost) / maxf(budget_at_start, 1.0), 0.0, 1.0)
	score += 2.0 * mini(pows + pows_pending, 4)
	score -= 3.0 * (W.ew.drones_lost if W.ew else 0)
	if reason == "timeout":
		score -= 10.0
	r["kia"] = kia
	r["wia_left"] = wia_left
	r["vehicles_lost"] = vlost
	r["prisoners"] = pows + pows_pending
	r["secondary"] = objectives.evaluate_secondary(r)
	for o in r["secondary"]:
		if o["done"]:
			score += Objectives.SECONDARY_BONUS
	score = clampf(score, 0.0, 100.0)
	var grade = Loc.t("НЕЗАДОВІЛЬНО")
	if score >= 85.0:
		grade = Loc.t("ВІДМІННО")
	elif score >= 65.0:
		grade = Loc.t("ДОБРЕ")
	elif score >= 45.0:
		grade = Loc.t("ЗАДОВІЛЬНО")
	r["kia"] = kia
	r["wia"] = wia
	r["evacuated"] = evac
	r["wia_left"] = wia_left
	r["personnel"] = total
	r["vehicles_lost"] = vlost
	r["vehicles_list"] = vlist
	r["vehicles_total"] = friendly_vehicles.size() + W.evac.runs.size()
	r["enemy_total"] = e_total
	r["enemy_dead"] = e_dead
	r["enemy_wia"] = e_wia
	r["enemy_escaped"] = e_esc
	r["prisoners"] = pows + pows_pending
	r["drones_lost"] = W.ew.drones_lost if W.ew else 0
	r["mines"] = W.mines.triggered if W.mines else 0
	r["cost_total"] = spent
	r["cost_used"] = used_cost
	r["support_used"] = support_used.duplicate()
	r["score"] = int(score)
	r["grade"] = grade
	r["map"] = def.title
	r["difficulty"] = Game.difficulty()
	r["support_left"] = support.duplicate()
	var rounds := 0
	var nades := 0
	for u in W.units:
		if u.side == 0:
			rounds += u.shots
			nades += u.nades_used
	r["rounds"] = rounds
	var pan := 0
	for u in W.units:
		if u.side == 0 and u.panicked:
			pan += 1
	r["panicked"] = pan
	r["grenades_used"] = nades
	if W.blog:
		var why := {"captured": Loc.t("Позицію захоплено"), "completed": Loc.t("Завдання виконано"), "wiped": Loc.t("Підрозділи втратили боєздатність"),
			"timeout": Loc.t("Час вичерпано"), "abort": Loc.t("Операцію припинено")}
		W.blog.add("end", String(why.get(reason, reason)), null)
		r["analysis"] = W.blog.analyze(r)
	r["weather"] = "%s %s" % [Game.wx("icon"), Game.wx("name")]
	# for the campaign: how much of the enemy we had seen, the clock, worn-out vehicles
	var seen := 0
	for u in W.units:
		if u.side == 1 and u.ever_seen:
			seen += 1
	r["recon"] = float(seen) / maxf(1.0, float(e_total))
	r["time_limit"] = def.time_limit
	var vdam: Array = []
	for v in friendly_vehicles:
		if v.state != "destroyed" and float(v.hp) < float(v.max_hp) * AIConfig.CQ_REPAIR_HP:
			vdam.append(v.vtype)
	r["vehicles_damaged"] = vdam
	if Game.mode == "campaign":
		r["campaign"] = _campaign_outcome(r)
	result = r
	Game.last_result = r
	set_phase(Phase.ENDED)
	Engine.time_scale = 1.0
	Events.mission_ended.emit(r)
