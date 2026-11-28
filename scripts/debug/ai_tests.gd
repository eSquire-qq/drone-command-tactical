class_name AITests
extends Node
## Controlled AI scenarios on the training ground (`-- --autotest --map=training --aitest=<name>`):
##  trench_fire — a BMP-2 rakes the enemy trench for 45 s, then ceases fire;
##                logs suppression levels, how often defenders stand up and
##                how much they shoot, and the recovery after the fire stops.
##  blast       — explosions at different distances from soldiers in and out
##                of cover; logs suppression gained and damage.

var scenario := ""
var t0 := -1.0
var stage := 0
var log_t := 0.0
var bmp = null
var held_weapons: Array = []
var stats := {"fire": {"n": 0, "lvl": 0.0, "stand": 0, "shots0": 0}, "after": {}}
var ceasefire_t := -1.0
var recovered_t := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 2.0


const TRAINING_ONLY := ["trench_fire", "blast", "grenades", "assault", "building", "controls", "field", "fire", "intel"]


func _team(name: String):
	for sq in W.enemy_ai.squads:
		if sq.team_name == name:
			return sq
	return null


func _process(_d: float) -> void:
	if _hold_end_check():
		return
	if not W.running() or W.mission.phase != MissionManager.Phase.COMBAT:
		return
	if t0 < 0.0:
		t0 = W.time
		# these scenarios use the teams of the training ground (Пост, Окоп)
		if scenario in TRAINING_ONLY and _team("Пост") == null:
			print("[AITEST] RESULT %s: FAIL this scenario runs on the training ground: --map=training (now «%s»)" % [scenario, W.mission.def.id])
			get_tree().quit()
			return
		_setup()
	var t := W.time - t0
	match scenario:
		"trench_fire":
			_trench_fire(t)
		"blast":
			_blast(t)
		"grenades":
			_grenades(t)
		"assault":
			_assault(t)
		"vehicle_trench", "vehicle_blocked":
			_vehicle(t)
		"intel":
			_intel(t)
		"radio":
			_radio(t)
		"field":
			_field(t)
		"building":
			_building(t)
		"controls":
			_controls(t)
		"cover":
			_cover(t)
		"fire":
			_fire(t)
		"react":
			_react(t)
		"leader":
			_leader(t)
		"shift":
			_shift(t)
		"withdraw":
			_withdraw_test(t)
		"recon":
			_recon(t)
		"reinf":
			_reinf(t)
		"windows":
			_windows(t)
		"drag":
			_drag(t)
		"resupply":
			_resup(t)
		"hold":
			_hold(t)


func _setup() -> void:
	for v in W.mission.friendly_vehicles:
		bmp = v
	var sq = W.mission.friendly_squads[0]
	sq.issue_order("hold", W.grid.ground(Vector3(0, 0, 70)))
	if scenario == "trench_fire" and bmp:
		bmp.stop()
		bmp.global_position = W.grid.ground(Vector3(-38, 0, -5))
		bmp.set_yaw(0.0)
		# the crew has seen the trench garrison (as after a recon report)
		for m in _team("Окоп").members:
			m.marked = true
			sq.report(m, m.global_position)
	W.cam.teleport_view(Vector3(-42, 0, -60), 45.0, 40.0, 0.3)


func _row(tag: String, list: Array) -> String:
	var out := PackedStringArray()
	for m in list:
		out.append("%s:s%02d L%d st%02d %s %s" % [m.rdata["short"], int(m.suppression), m.supp_level, int(m.stress),
			["ST", "CR", "PR"][m.posture], m.ai.state])
	return tag + " | ".join(out)


var psy_last := {}
var psy_seq := {}


func _memory_test() -> void:
	var s := {"name": "Тест", "strain": 0.0, "memory": []}
	var lines: Array = []
	lines.append(Campaign.apply_memory(s, {"state": "ok", "pinned_s": 70.0, "comrades_lost": 1, "panicked": false}, false))
	var after1: float = s["strain"]
	lines.append(Campaign.apply_memory(s, {"state": "wounded", "wounded": true, "pinned_s": 10.0, "panicked": true}, false))
	var after2: float = s["strain"]
	lines.append(Campaign.apply_memory(s, {"state": "ok", "pinned_s": 0.0}, true))
	lines.append(Campaign.apply_memory(s, {"state": "ok", "pinned_s": 0.0}, true))
	print("[AITEST] MEMORY strain %.0f → %.0f → %.0f (grit bonus %.2f, memory %s)" % [after1, after2, s["strain"], float(s.get("grit_bonus", 0.0)), s["memory"]])
	for l in lines:
		print("[AITEST]   ", l)
	# a strained man starts the next mission stressed and less steady
	var u := Soldier.new()
	add_child(u)
	u.setup(0, "rifleman", null, "Тест")
	var m0: float = u.max_morale
	u.apply_memory({"strain": after2, "grit_bonus": 0.03, "memory": ["поранення"]})
	print("[AITEST] MEMORY next mission: base stress %.0f, max morale %.0f → %.0f" % [u.base_stress, m0, u.max_morale])
	u.queue_free()


func _trench_fire(t: float) -> void:
	var team = _team("Окоп")
	if team == null:
		return
	var men: Array = team.members.filter(func(m): return m.is_active())
	# test 4: psychological state transitions of every defender
	for m in men:
		var ps: int = m.psych_state()
		if psy_last.get(m, -1) != ps:
			psy_last[m] = ps
			psy_seq[m] = psy_seq.get(m, []) + [AIConfig.PSY_NAMES[ps]]
	# keep the garrison in view of the crew's memory while firing
	if ceasefire_t < 0.0:
		var sq = W.mission.friendly_squads[0]
		for m in men:
			if m.model.visible or randf() < 0.3:
				sq.report(m, m.global_position)
	log_t -= get_process_delta_time()
	if log_t <= 0.0:
		log_t = 3.0
		print("[AITEST] t=%3d %s%s" % [int(t), "FIRE " if ceasefire_t < 0.0 else "QUIET", _row(" ", men)])
		if bmp and int(t) < 10:
			print("[AITEST]   bmp pos=%s state=%s target=%s area=%s squad=%s known=%d offmap=%s" % [bmp.global_position.snapped(Vector3.ONE), bmp.state, bmp.target, bmp.area_target, bmp.squad, bmp.squad.known.size() if bmp.squad else -1, bmp.offmap])
	if ceasefire_t < 0.0:
		stats["fire"]["n"] += 1
		for m in men:
			stats["fire"]["lvl"] += m.supp_level
			if m.posture == Soldier.P.STAND:
				stats["fire"]["stand"] += 1
		if t > 45.0:
			ceasefire_t = t
			held_weapons = bmp.weapons
			bmp.weapons = []
			bmp.target = null
			bmp.area_target = null
			var shots := 0
			for m in team.members:
				shots += m.shots
			stats["fire"]["shots0"] = shots
			print("[AITEST] CEASEFIRE at t=%d" % int(t))
	else:
		var all_calm := true
		for m in men:
			if m.supp_level > 1:
				all_calm = false
		if all_calm and recovered_t < 0.0:
			recovered_t = t - ceasefire_t
		if t - ceasefire_t > 50.0:
			var n: int = maxi(1, stats["fire"]["n"] * maxi(1, men.size()))
			print("[AITEST] RESULT trench_fire: avg level under fire %.2f, standing %.0f%% of the time, defenders' shots under fire %d, back to level<=1 after %s s, alive %d/%d" % [
				stats["fire"]["lvl"] / n, 100.0 * stats["fire"]["stand"] / n, stats["fire"]["shots0"],
				("%.0f" % recovered_t) if recovered_t >= 0.0 else ">50", men.size(), team.members.size()])
			for m in men:
				print("[AITEST] PSY %s (grit %.2f): %s" % [m.uname, m.grit, " → ".join(psy_seq.get(m, []))])
			_memory_test()
			get_tree().quit()


# ------------------------------------------------------------------ test 9: controls, vehicles, formations
var ct := {}


func _src_at(p: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = p
	return n


func _click(button: int, sp: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = sp
	ev.global_position = sp
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _controls(t: float) -> void:
	var sq = W.mission.friendly_squads[0]
	var v = bmp
	if stage == 0 and t > 1.0:
		stage = 1
		# 1) armour: the same AT hit from the front, the side and the rear
		var res := []
		for asp in [["лоб", 0.0], ["борт", PI * 0.5], ["корма", PI]]:
			v.hp = v.max_hp
			v.state = "ok"
			var dir: Vector3 = v.forward().rotated(Vector3.UP, asp[1])
			var src := _src_at(v.global_position + dir * 40.0)
			seed(7)
			v.take_damage(100.0, "at", src)
			res.append("%s %.0f" % [asp[0], v.max_hp - v.hp])
			src.queue_free()
		v.hp = v.max_hp
		v.state = "ok"
		v.stop()
		print("[AITEST] ARMOUR one AT hit (100): " + ", ".join(res))
		# 2) aspect: an enemy to the east, hold the side to him
		var e = _team("Пост").members[0]
		ct["e"] = e
		v.target = null
		v.set_face("side")
		ct["face_t"] = t
	if stage == 1 and t > 12.0:
		stage = 2
		var d: Vector3 = ct["e"].global_position - v.global_position
		d.y = 0.0
		var ang := rad_to_deg(acos(clampf(v.forward().dot(d.normalized()), -1.0, 1.0)))
		print("[AITEST] FACE «бортом»: angle between the hull and the enemy %.0f° (want ~90)" % ang)
		v.set_face("")
		# 3) vehicle assault: slower, no pull-back
		v.order_assault(v.global_position + v.forward() * 40.0)
		ct["as_t"] = t
	if stage == 2 and t > 16.0:
		stage = 3
		print("[AITEST] VEHICLE ASSAULT: label «%s», speed %.1f m/s of max %.1f" % [v.order_label, v.speed, float(v.data["speed"])])
		# 4) suppression: the vehicle and the squad work a point
		var sp_pt: Vector3 = W.grid.ground(Vector3(13, 0, -34))
		v.order_suppress(sp_pt)
		sq.order_suppress(sp_pt)
		ct["shots0"] = _squad_shots(sq)
	if stage == 3 and t > 26.0:
		stage = 4
		var aimers := 0
		for m in sq.members:
			if m.area_target != null:
				aimers += 1
		print("[AITEST] SUPPRESS: vehicle area target %s, squad men aiming at the point %d, squad shots %d" % [
			v.area_target != null, aimers, _squad_shots(sq) - int(ct["shots0"])])
		v.sup_until = -1.0
		sq.sup_until = -1.0
		# the post fired back: take it out so the walk behind the vehicle is not pinned down
		for m in _team("Пост").members:
			W.damage.set_health(m, Soldier.H.DEAD, null, "test")
		for m in sq.members:
			m.suppression = 0.0
			m.supp_level = 0
		# 5) infantry behind the vehicle in two files
		sq.follow_vehicle(v)
		v.order_move(v.global_position + v.forward() * 45.0)
		ct["max_v"] = 0.0
	if stage == 4:
		ct["max_v"] = maxf(ct["max_v"], v.speed)
	if stage == 4 and t > 50.0:
		stage = 5
		var f: Vector3 = v.forward()
		var r := Vector3(-f.z, 0, f.x)
		var behind := 0
		var left := 0
		var right_n := 0
		for m in sq.active_members():
			var d: Vector3 = m.global_position - v.global_position
			if d.dot(f) < -2.0:
				behind += 1
			if d.dot(r) < 0.0:
				left += 1
			else:
				right_n += 1
		print("[AITEST] FOLLOW: %d of %d men behind the vehicle, files %d / %d, vehicle top speed %.1f m/s (limit %.1f)" % [
			behind, sq.active_count(), left, right_n, ct["max_v"], AIConfig.VEH_ESCORT_SPEED])
		# 6) bounding: the two halves take turns
		sq.issue_order("bound", sq.center() + Vector3(0, 0, -50))
		ct["switches"] = 0
		ct["last_team"] = sq.bound_team
	if stage == 5:
		if sq.bound_team != ct["last_team"]:
			ct["switches"] += 1
			ct["last_team"] = sq.bound_team
	if stage == 5 and t > 80.0:
		stage = 6
		print("[AITEST] BOUND: order «%s» force %s, team switches in 30 s: %d" % [sq.order, sq.force_bound, ct["switches"]])
		# 7) preview and mouse (RTS scheme): select, right click = order, left on empty = deselect
		W.command.select_object(sq)
		var gp: Vector3 = W.grid.ground(sq.center() + Vector3(10, 0, 15))
		var pv: Array = W.command.preview(gp)
		print("[AITEST] PREVIEW: %d unit(s), %d spots for %d men" % [pv.size(), pv[0]["slots"].size(), sq.active_count()])
		W.cam.teleport_view(gp, 60.0, 60.0, 0.0)
		ct["gp"] = gp
	if stage == 6 and t > 81.0 and not ct.has("shot") and DisplayServer.get_name() != "headless":
		ct["shot"] = true
		W.command._set_selection([sq, v])
		W.command.hover_point = ct["gp"]
		await get_tree().create_timer(0.6).timeout
		var pth := ProjectSettings.globalize_path("user://controls_preview.png")
		get_viewport().get_texture().get_image().save_png(pth)
		print("[AITEST] SHOT ", pth)
		W.command.select_object(sq)
	if stage == 6 and t > 82.0:
		stage = 7
		var c := get_viewport().get_camera_3d()
		var spos := c.unproject_position(ct["gp"])
		ct["spos"] = spos
		W.command.mode = "move"
		_click(MOUSE_BUTTON_RIGHT, spos, true)
		_click(MOUSE_BUTTON_RIGHT, spos, false)
	if stage == 7 and t > 83.0:
		stage = 8
		var dd: float = Vector2(sq.order_pos.x - ct["gp"].x, sq.order_pos.z - ct["gp"].z).length()
		print("[AITEST] MOUSE RTS: right click → order «%s» %.1f m from the click point; selection %d" % [sq.order, dd, W.command.selection.size()])
		var empty: Vector2 = ct["spos"] + Vector2(260, 0)
		_click(MOUSE_BUTTON_LEFT, empty, true)
		_click(MOUSE_BUTTON_LEFT, empty, false)
	if stage == 8 and t > 84.0:
		print("[AITEST] MOUSE RTS: left click on empty ground → selection %d" % W.command.selection.size())
		print("[AITEST] RESULT controls: done")
		get_tree().quit()


func _squad_shots(sq) -> int:
	var n := 0
	for m in sq.members:
		n += m.shots
	return n


# ------------------------------------------------------------------ test 8: fight in buildings
var bt := {}


func _building(t: float) -> void:
	var sq = W.mission.friendly_squads[0]
	if stage == 0 and t > 1.0:
		stage = 1
		var b = W.map.building_at(Vector3(-18, 0, 44))
		bt["b"] = b
		print("[AITEST] BUILDING %s: %d windows, %d doors, %d inner points, roof %s" % [b["kind"], b["windows"].size(), b["doors"].size(),
			b["interior"].size(), b["roof"]])
		# two men of the enemy post go into the ruin: one at a window, one deep inside
		var post = _team("Пост")
		var men: Array = post.members
		men[0].global_position = b["center"]
		Buildings.garrison(men[0])
		men[1].global_position = b["interior"][0]
		men[1].slot = men[1].global_position
		bt["win"] = men[0]
		bt["deep"] = men[1]
		post.set_defend([Vector2(men[0].global_position.x, men[0].global_position.z), Vector2(men[1].global_position.x, men[1].global_position.z)], true)
		W.enemy_ai.raise_alert(2)
		# our squad in the open, 40 m away on the side the window faces
		var w: Dictionary = men[0].post
		var stand: Vector3 = W.grid.ground(b["center"] + (w["dir"] as Vector3) * 40.0)
		var k := 0
		for m in sq.members:
			m.global_position = W.grid.ground(stand + Vector3((k - 3) * 2.0, 0, 0))
			m.stop()
			k += 1
		sq.issue_order("hold", stand)
		bt["stand"] = stand
		W.cam.teleport_view(b["center"], 45.0, 50.0, 0.0)
	if stage == 1 and t > 3.0:
		stage = 2
		var win = bt["win"]
		var deep = bt["deep"]
		var see_win := 0
		var see_deep := 0
		var win_sees := 0
		for m in sq.members:
			if W.grid.visibility(m.eye_point(), win.aim_point()) > 0.2:
				see_win += 1
			if W.grid.visibility(m.eye_point(), deep.aim_point()) > 0.2:
				see_deep += 1
			if W.grid.visibility(win.eye_point(), m.aim_point()) > 0.2:
				win_sees += 1
		print("[AITEST] LOS from %d men in the field: man at the window seen by %d, he sees %d; man deep inside seen by %d; cover at window %.2f, under roof (drone) %s" % [
			sq.members.size(), see_win, win_sees, see_deep, win.cover_value(), Buildings.under_roof(deep)])
		bt["t_fire"] = t
	if stage == 2 and t > 23.0:
		stage = 3
		var win = bt["win"]
		print("[AITEST] FIRE 20 s: window man shots %d (alive %s), our wounded/killed %d" % [win.shots, win.is_active(), _down(sq)])
		sq.issue_order("clear", bt["b"]["center"])
		print("[AITEST] CLEAR ordered: squad order «%s», entry %s" % [sq.order, "пролом" if sq.bld_entry.get("breach", false) else "двері"])
		bt["t_clear"] = t
		bt["phase_t"] = {}
	if stage == 3:
		var ph: int = sq.bld_phase
		if sq.order == "clear_bld" and not bt["phase_t"].has(ph):
			bt["phase_t"][ph] = int(t - bt["t_clear"])
		if sq.order == "occupy" and not bt.has("cleared"):
			bt["cleared"] = t - bt["t_clear"]
			var dead := 0
			for m in _team("Пост").members:
				if not m.is_active():
					dead += 1
			print("[AITEST] CLEARED after %.0f s (phases at %s s), enemy out of action %d/2, our wounded/killed %d, grenades used %d" % [
				bt["cleared"], bt["phase_t"], dead, _down(sq), _nades(sq)])
			bt["t_occ"] = t
		if bt.has("t_occ") and int(t - bt["t_occ"]) % 10 == 0 and not bt.has("d%d" % int(t - bt["t_occ"])):
			bt["d%d" % int(t - bt["t_occ"])] = true
			print("[AITEST]   occupy +%ds: %s" % [int(t - bt["t_occ"]), sq.members.filter(func(m): return m.is_active()).map(func(m):
				return "%s%s d%.1f L%d %s" % ["W" if m.post else ("p" if m.post_pending else "-"), "m" if m.moving else "", m.global_position.distance_to(m.slot), m.supp_level, m.ai.state])])
		if bt.has("t_occ") and t - bt["t_occ"] > 12.0 and not bt.has("shot") and DisplayServer.get_name() != "headless":
			bt["shot"] = true
			W.cam.teleport_view(bt["b"]["center"], 16.0, 48.0, 0.6)
			await get_tree().create_timer(1.0).timeout
			var pth := ProjectSettings.globalize_path("user://building_occupied.png")
			get_viewport().get_texture().get_image().save_png(pth)
			print("[AITEST] SHOT ", pth)
		if bt.has("t_occ") and t - bt["t_occ"] > 40.0:
			var on_post := 0
			for m in sq.members:
				if m.post != null:
					on_post += 1
			print("[AITEST] OCCUPY: %d of %d men at windows, states %s" % [on_post, sq.active_count(),
				sq.members.filter(func(m): return m.is_active()).map(func(m): return m.ai.state)])
			print("[AITEST] RESULT building: ok")
			get_tree().quit()
		if t - bt["t_clear"] > 150.0:
			print("[AITEST] RESULT building: clearing did not finish (phase %d, enemies inside %d)" % [ph, Buildings.men_inside(bt["b"], 1).size()])
			get_tree().quit()


func _down(sq) -> int:
	var n := 0
	for m in sq.members:
		if m.health != Soldier.H.HEALTHY:
			n += 1
	return n


func _nades(sq) -> int:
	var n := 0
	for m in sq.members:
		n += m.nades_used
	return n


# ------------------------------------------------------------------ test 5: dynamic battlefield
var fd := {}


func _path_len(path: PackedVector3Array, from: Vector3) -> float:
	var L := 0.0
	var prev := from
	for p in path:
		L += prev.distance_to(p)
		prev = p
	return L


func _field(t: float) -> void:
	var g = W.grid
	var bf = W.field
	if stage == 0 and t > 2.0:
		stage = 1
		# 1) craters: three mortar rounds into the same open spot
		var P: Vector3 = g.ground(Vector3(-30, 0, 22))
		fd["crater_p"] = P
		var a: Vector3 = g.ground(P + Vector3(-14, 0, 0))
		var b: Vector3 = g.ground(P + Vector3(14, 0, 0))
		var lp0 := _path_len(g.find_path(a, b, true, "light"), a)
		var c0: float = g.cover_at(P)
		var h0: float = g.height_at(P.x, P.z)
		var eye: Vector3 = g.ground(P + Vector3(0, 0, 30)) + Vector3(0, 1.7, 0)
		var vis0: float = g.visibility(eye, g.ground(P) + Vector3(0, 0.3, 0))
		W.combat.explosion(P, 6.0, 110.0, null, "mortar")
		print("[AITEST] CRATER ground %.2f -> %.2f m; a man lying in it seen from 30 m: %.2f -> %.2f" % [h0, g.height_at(P.x, P.z),
			vis0, g.visibility(eye, g.ground(P) + Vector3(0, 0.3, 0))])
		var r1: float = bf.craters[-1]["r"] if bf.craters.size() > 0 else 0.0
		print("[AITEST] CRATER 1 hit: craters=%d r=%.1f cover %.2f -> %.2f inf_w=%.2f veh_w=%.2f" % [bf.craters.size(), r1, c0, g.cover_at(P),
			g.inf_weight[g.cidx(P.x, P.z)], g.veh_weight[g.cidx(P.x, P.z)]])
		W.combat.explosion(P + Vector3(0.4, 0, 0.3), 6.0, 110.0, null, "mortar")
		W.combat.explosion(P + Vector3(-0.3, 0, 0.2), 6.0, 110.0, null, "mortar")
		var ci: int = g.cidx(P.x, P.z)
		print("[AITEST] CRATER 3 hits: craters=%d r=%.1f light_blocked=%s tracked_blocked=%s; light vehicle path %.0f m -> %.0f m" % [
			bf.craters.size(), bf.craters[-1]["r"], g.veh_solid_light[ci] != 0, g.veh_solid[ci] != 0, lp0,
			_path_len(g.find_path(a, b, true, "light"), a)])
		var fc: Vector3 = g.find_cover(P + Vector3(0, 0, 6), 8.0, P + Vector3(0, 0, -60), [])
		print("[AITEST] CRATER AI picks cover %.1f m from the crater (cover %.2f)" % [Vector2(fc.x - P.x, fc.z - P.z).length(), g.cover_at(fc)])
		# 2b) trees: two mortar rounds into the north tree line
		var tp := Vector3(-40, 0, -99)
		var f0: float = g.foliage_at(tp)
		W.combat.explosion(g.ground(tp), 6.0, 110.0, null, "mortar")
		W.combat.explosion(g.ground(tp + Vector3(3, 0, 1)), 6.0, 110.0, null, "mortar")
		print("[AITEST] TREES 2 rounds into the tree line: %d trees down, concealment %.2f -> %.2f" % [bf.stats["trees"], f0, g.foliage_at(tp)])
		# 2c) house wall: three HE rounds against the north wall of the ruin
		var hc := Vector3(-18, 0, 44)
		var wi := -1
		var wd := INF
		for i in bf.pieces.size():
			var pw: Dictionary = bf.pieces[i]
			if pw["kind"] == "wall" and pw["pos"].z < hc.z - 2.0:
				var dd: float = Vector2(pw["pos"].x - hc.x, pw["pos"].z - (hc.z - 3.0)).length()
				if dd < wd:
					wd = dd
					wi = i
		if wi >= 0:
			var pw2: Dictionary = bf.pieces[wi]
			var outside: Vector3 = g.ground(pw2["pos"] + (pw2["pos"] - hc).normalized() * 4.0)
			var inside: Vector3 = g.ground(hc)
			var l0 := _path_len(g.find_path(outside, inside, false), outside)
			var hits := 0
			while int(pw2["state"]) < 2 and hits < 6:
				hits += 1
				W.combat.explosion(g.ground(pw2["pos"] + (pw2["pos"] - hc).normalized() * 1.0), 4.0, 100.0, null, "he")
			var solid := 0
			for wc in pw2["cells"]:
				solid += g.inf_solid[int(wc[0])]
			print("[AITEST] WALL %d hits: state %s, blocked cells %d/%d; path from outside to the room %.0f m -> %.0f m" % [hits,
				["ціла", "пошкоджена", "зруйнована"][int(pw2["state"])], solid, pw2["cells"].size(), l0,
				_path_len(g.find_path(outside, inside, false), outside)])
		fd["wall_pos"] = bf.pieces[wi]["pos"] if wi >= 0 else hc
		# 2) sandbags: rounds land beside them until they are gone
		for i in bf.pieces.size():
			if bf.pieces[i]["kind"] == "sandbags":
				fd["pi"] = i
				break
		var pc: Dictionary = bf.pieces[fd["pi"]]
		fd["pp"] = pc["pos"]
		fd["sb_cov"] = [g.cover_at(pc["pos"])]
		fd["hits"] = 0
		# 3) smoke over one defender, another one in the clear as control
		var tr = _team("Окоп")
		var men: Array = tr.members.filter(func(m): return m.is_active())
		fd["e1"] = men[0]
		for m in men:
			if m.global_position.distance_to(men[0].global_position) > 14.0:
				fd["e2"] = m
				break
		W.combat.deploy_smoke(fd["e1"].global_position, 10.0, 45.0)
		fd["cloud"] = W.smoke_clouds[-1]
		fd["c0"] = fd["cloud"]["pos"]
		fd["st"] = W.time
		var mid: Vector3 = (fd["e1"].global_position + fd["e2"].global_position) * 0.5
		W.cam.teleport_view(mid, 55.0, 55.0, 0.0)
		W.intel.contacts.erase(fd["e1"])
		W.intel.contacts.erase(fd["e2"])
		print("[AITEST] WIND %s (%.2f m/s), smoke over %s; control %s %.0f m away" % [bf.wind_text(), bf.wind.length(), fd["e1"].display_name(),
			fd["e2"].display_name(), fd["e1"].global_position.distance_to(fd["e2"].global_position)])
	if stage == 1 and t > 3.0 + fd["hits"] * 1.4 and fd["hits"] < 8 and int(bf.pieces[fd["pi"]]["state"]) < 2:
		fd["hits"] += 1
		var pc2: Dictionary = bf.pieces[fd["pi"]]
		W.combat.explosion(g.ground(fd["pp"] + Vector3(2.5 if fd["hits"] < 5 else 1.2, 0, 1.0)), 4.0, 100.0, null, "he")
		fd["sb_cov"].append(g.cover_at(fd["pp"]))
		print("[AITEST] SANDBAGS hit %d: hp %.0f/%.0f state %s cover %.2f" % [fd["hits"], pc2["hp"], pc2["max_hp"],
			["ціле", "пошкоджене", "зруйноване"][int(pc2["state"])], g.cover_at(fd["pp"])])
	if stage == 1 and t > 16.0:
		stage = 2
		# a man lying behind the bags: _hold_logic looks for new cover below 0.3
		print("[AITEST] SANDBAGS cover at the bags %s; a man there now %s" % [" → ".join(fd["sb_cov"].map(func(v): return "%.2f" % v)),
			"looks for new cover" if g.cover_at(fd["pp"]) < 0.3 else "stays"])
		for k in ["e1", "e2"]:
			var e = fd[k]
			var c: Dictionary = W.intel.contacts.get(e, {})
			var cam_p: Vector3 = W.cam.cam.global_position
			print("[AITEST] SMOKE %s: opacity from drone %.2f, intel %s src=%s err=%.0f" % [k, bf.smoke_opacity(cam_p, e.global_position + Vector3(0, 1, 0)),
				["CONFIRMED", "PROBABLE", "LAST KNOWN", "UNVERIFIED", "LOST", "DESTROYED"][int(c["status"])] if not c.is_empty() else "нема",
				c.get("src", "-"), float(c.get("err", 0.0))])
	# windowed run: pictures of the crater, the bags and the smoke
	if stage == 2 and t > 18.0 and DisplayServer.get_name() != "headless":
		var shots := [[fd["crater_p"], 18.0, "field_crater"], [fd["pp"], 30.0, "field_sandbags"], [fd["e1"].global_position, 75.0, "field_smoke"],
			[Vector3(-38, 0, -96), 30.0, "field_trees"], [fd["wall_pos"], 22.0, "field_wall"]]
		var k := int((t - 18.0) / 2.0)
		if k < shots.size():
			if fmod(t - 18.0, 2.0) < 0.05 and not fd.has("v%d" % k):
				fd["v%d" % k] = true
				W.cam.teleport_view(shots[k][0], shots[k][1], 50.0, 0.4)
			if fmod(t - 18.0, 2.0) > 1.6 and not fd.has("s%d" % k):
				fd["s%d" % k] = true
				var img := get_viewport().get_texture().get_image()
				var path := ProjectSettings.globalize_path("user://%s.png" % shots[k][2])
				img.save_png(path)
				print("[AITEST] SHOT ", path)
	if stage == 2 and t > 40.0 and (DisplayServer.get_name() == "headless" or t > 30.0):
		stage = 3
		var cl: Dictionary = fd["cloud"]
		var el: float = W.time - float(fd["st"])
		print("[AITEST] SMOKE after %.0f s: drifted %.1f m (wind x time %.1f m), radius %.1f -> %.1f, density %.2f, alive %s" % [el,
			Vector2(cl["pos"].x - fd["c0"].x, cl["pos"].z - fd["c0"].z).length(), bf.wind.length() * el, float(cl["r0"]), float(cl["r"]),
			float(cl["dens"]), W.smoke_clouds.has(cl)])
		print("[AITEST] RESULT field: craters %d, cover damaged %d, destroyed %d, trees down %d" % [bf.stats["craters"], bf.stats["damaged"], bf.stats["destroyed"], bf.stats["trees"]])
		get_tree().quit()


func _blast(t: float) -> void:
	if stage == 0 and t > 3.0:
		stage = 1
		var post = _team("Пост")
		var tr = _team("Окоп")
		var before := {}
		for m in post.members + tr.members:
			before[m] = m.suppression
		# a shell 7 m from the post (soldiers behind sandbags in a short trench)
		var p1: Vector3 = W.grid.ground(post.members[0].global_position + Vector3(0, 0, 7))
		W.combat.explosion(p1, 4.0, 100.0, null)
		# a shell in the open 18 m from the trench
		var p2: Vector3 = W.grid.ground(tr.members[0].global_position + Vector3(6, 0, 17))
		W.combat.explosion(p2, 4.0, 100.0, null)
		await get_tree().create_timer(0.2).timeout
		for m in post.members + tr.members:
			var d1: float = m.global_position.distance_to(p1)
			var d2: float = m.global_position.distance_to(p2)
			print("[AITEST] blast %s d=%dm cover=%.2f supp %d -> %d (L%d) health=%d flinch=%s" % [m.rdata["short"], int(minf(d1, d2)),
				m.cover_value(), int(before[m]), int(m.suppression), m.supp_level, m.health, m.flinch_t > 0.0])
		stage = 2
	if stage == 2 and t > 20.0:
		for m in _team("Пост").members + _team("Окоп").members:
			print("[AITEST] after 17 s %s supp=%d L%d stress=%d" % [m.rdata["short"], int(m.suppression), m.supp_level, int(m.stress)])
		get_tree().quit()


# ------------------------------------------------------------------ grenades
var nade_seen := {}
var nade_events: Array = []   # {t, who, pos}
var nade_start := {}


func _grenades(t: float) -> void:
	var sq = W.mission.friendly_squads[0]
	if stage == 0:
		stage = 1
		for m in sq.members:
			nade_start[m] = {"g": m.grenades, "gl": m.gl_rounds}
			nade_seen[m] = 0
		# the squad storms the trench at the north tree line
		sq.issue_order("clear", W.grid.ground(Vector3(-42, 0, -68)))
		W.cam.teleport_view(Vector3(-42, 0, -60), 60.0, 45.0, 0.2)
	for m in sq.members:
		if m.nades_used > nade_seen[m]:
			nade_seen[m] = m.nades_used
			var tgt = m.action_payload if m.action_payload is Vector3 else m.global_position
			nade_events.append({"t": W.time, "who": m.uname, "pos": tgt})
			print("[AITEST] t=%d %s throws (left %d hand, %d gl) state=%s" % [int(t), m.uname, m.grenades, m.gl_rounds, m.ai.state])
	var done: bool = _team("Окоп") == null or _team("Окоп").members.all(func(e): return not e.is_active())
	if done or t > 240.0:
		var ok := true
		var used := 0
		for m in sq.members:
			var g0: int = nade_start[m]["g"] + nade_start[m]["gl"]
			var left: int = m.grenades + m.gl_rounds
			used += g0 - left
			if left > g0 or m.grenades < 0 or m.gl_rounds < 0:
				ok = false
			print("[AITEST]   %s %s: start %d, left %d, used %d" % [m.rdata["short"], m.uname, g0, left, m.nades_used])
		var worst := 0
		var dup := 0
		for i in nade_events.size():
			var n := 0
			for j in nade_events.size():
				var dt: float = nade_events[j]["t"] - nade_events[i]["t"]
				if dt >= 0.0 and dt < AIConfig.NADE_WINDOW:
					n += 1
				if j > i and absf(dt) < AIConfig.NADE_CLAIM_TIME and (nade_events[i]["pos"] as Vector3).distance_to(nade_events[j]["pos"]) < AIConfig.NADE_CLAIM_CELL * 0.6:
					dup += 1
			worst = maxi(worst, n)
		print("[AITEST] RESULT grenades: trench cleared=%s in %d s, used %d, stock consistent=%s, max per %ds window=%d (limit %d), same spot twice within %ds=%d" % [
			done, int(t), used, ok, int(AIConfig.NADE_WINDOW), worst, AIConfig.NADE_PER_WINDOW, int(AIConfig.NADE_CLAIM_TIME), dup])
		get_tree().quit()


# ------------------------------------------------------------------ assault under fire
var moved_pinned := 0
var pinned_samples := 0
var last_pos := {}


func _assault(t: float) -> void:
	var sq = W.mission.friendly_squads[0]
	if stage == 0:
		stage = 1
		Events.message.connect(func(txt, _k): if txt.begins_with(sq.short): print("[AITEST]   MSG t=%d %s" % [int(W.time - t0), txt]))
		# the BMP stays back; the squad alone storms the post across the field
		if bmp:
			bmp.weapons = []
		sq.issue_order("assault", W.grid.ground(Vector3(13, 0, -30)))
		W.cam.teleport_view(Vector3(5, 0, 10), 90.0, 45.0, 0.0)
	# a pinned man (level 3+) in the open should not keep advancing on his own
	for m in sq.active_members():
		var p: Vector3 = m.global_position
		if last_pos.has(m) and m.supp_level >= 3 and W.grid.cover_at(p) < 0.3:
			pinned_samples += 1
			if p.distance_to(last_pos[m]) > 1.2 and m.cover_dash_t <= 0.0:
				moved_pinned += 1
		last_pos[m] = p
	log_t -= get_process_delta_time()
	if log_t <= 0.0:
		log_t = 6.0
		var mv := 0
		for m in sq.active_members():
			if m.moving:
				mv += 1
		print("[AITEST] t=%3d order=%s active=%d/%d moving=%d avg_level=%.1f pause=%.0f progress=%.0f/%.0f" % [int(t), sq.order, sq.active_count(), sq.members.size(), mv, sq.avg_level(), sq.assault_pause_t, sq.assault_progress, sq.assault_len])
	var post = _team("Пост")
	var won: bool = post.members.all(func(e): return not e.is_active())
	# clearing the trench the assault ended in is part of the same assault
	if won or t > 300.0 or not (sq.order in ["assault", "clear"]) and t > 5.0:
		for e in post.members:
			var nd := INF
			for m in sq.active_members():
				nd = minf(nd, m.global_position.distance_to(e.global_position))
			print("[AITEST]   post man %s pos=%s health=%d active=%s surrendered=%s supp=%d ai=%s known_by_squad=%s nearest ours %.1f m" % [e.rdata["short"], e.global_position.snapped(Vector3.ONE),
				e.health, e.is_active(), e.surrendered, e.supp_level, e.ai.state, sq.knows(e), nd])
		print("[AITEST] RESULT assault: post taken=%s, order now=%s, t=%d, active %d/%d, pinned-in-open samples %d, of them still advancing %d" % [
			won, sq.order, int(t), sq.active_count(), sq.members.size(), pinned_samples, moved_pinned])
		get_tree().quit()


# ------------------------------------------------------------------ vehicles
var in_trench_samples := 0
var veh_samples := 0
var reports: Array = []
var still_t := 0.0
var last_vpos := Vector3.ZERO


func _vehicle(t: float) -> void:
	if bmp == null:
		return
	if stage == 0:
		stage = 1
		Events.message.connect(func(txt, _k): if txt.begins_with(bmp.vname): reports.append("%d %s" % [int(W.time - t0), txt]))
		bmp.weapons = []
		var start := Vector3(-42, 0, -45) if scenario == "vehicle_trench" else Vector3(0, 0, 40)
		if scenario == "vehicle_blocked":
			# an impassable ring (rubble / obstacles) around the goal
			var g := Vector3(0, 0, -10)
			for cz in W.grid.cn:
				for cx in W.grid.cn:
					var c: Vector3 = W.grid.cell_center(Vector2i(cx, cz))
					var d := Vector2(c.x - g.x, c.z - g.z).length()
					if d > 9.0 and d < 12.5:
						var i: int = cz * W.grid.cn + cx
						W.grid.veh_solid[i] = 1
						W.grid.veh_solid_light[i] = 1
			W.grid.build_nav()
		bmp.stop()
		bmp.global_position = W.grid.ground(start)
		bmp.set_yaw(0.0)
		var goal := Vector3(-42, 0, -86) if scenario == "vehicle_trench" else Vector3(0, 0, -10)
		bmp.order_move(goal)
		last_vpos = bmp.global_position
		W.cam.teleport_view(Vector3(-42, 0, -70), 70.0, 50.0, 0.0)
		print("[AITEST] %s: order from %s to %s, path %d points, partial=%s, label=%s" % [scenario, start, goal, bmp.path.size(), W.grid.last_partial, bmp.order_label])
	veh_samples += 1
	if W.grid.trench_d(bmp.global_position.x, bmp.global_position.z) < TerrainGrid.T_FOOT:
		in_trench_samples += 1
	if bmp.global_position.distance_to(last_vpos) < 0.05:
		still_t += get_process_delta_time()
	else:
		still_t = 0.0
	last_vpos = bmp.global_position
	log_t -= get_process_delta_time()
	if log_t <= 0.0:
		log_t = 5.0
		print("[AITEST] t=%3d pos=%s moving=%s label=%s" % [int(t), bmp.global_position.snapped(Vector3.ONE), bmp.moving, bmp.order_label])
	if (not bmp.moving and still_t > 8.0 and t > 5.0) or t > 150.0:
		var goal_d: float = bmp.global_position.distance_to(Vector3(-42, 0, -86) if scenario == "vehicle_trench" else Vector3(0, 0, -10))
		print("[AITEST] RESULT %s: ended at %s (%.0f m from the goal), time %d s, samples inside a trench %d of %d, crew reports: %s" % [
			scenario, bmp.global_position.snapped(Vector3.ONE), goal_d, int(t), in_trench_samples, veh_samples, reports])
		get_tree().quit()


# ------------------------------------------------------------------ intel: lost contact
var moved_away := false
var transitions: Array = []
var last_st := {}


func _intel(t: float) -> void:
	var post = _team("Пост")
	var watch: Vector3 = Vector3(13, 0, -34)
	if stage == 0:
		stage = 1
		if bmp:
			bmp.weapons = []
		W.mission.friendly_squads[0].issue_order("hold", W.grid.ground(Vector3(0, 0, 95)))
		W.cam.teleport_view(watch, 55.0, 45.0, 0.0)
		W.cam.zoom_t = 3.0
	# phase 1: drone watches the post until both men are confirmed
	if stage == 1:
		var conf := 0
		for m in post.members:
			if W.intel.contact_of(m).get("status", -1) == IntelSystem.S.CONFIRMED:
				conf += 1
		if conf == post.members.size() or t > 60.0:
			stage = 2
			print("[AITEST] t=%d confirmed %d/%d — drone looks away, the post moves 35 m west" % [int(t), conf, post.members.size()])
			W.cam.teleport_view(Vector3(60, 0, 60), 60.0, 45.0, 0.0)
			W.cam.zoom_t = 1.0
			var slots: Array = [Vector2(-22, -66), Vector2(-26, -67)]
			post.set_defend(slots, false)
			for i in post.members.size():
				post.members[i].slot = W.grid.ground(Vector3(slots[i].x, 0, slots[i].y))
				post.members[i].move_to(post.members[i].slot, true)
	for m in post.members:
		var c: Dictionary = W.intel.contact_of(m)
		var st: int = c.get("status", -1)
		if last_st.get(m, -2) != st:
			last_st[m] = st
			var name: String = IntelSystem.NAMES[st] if st >= 0 else "ЗАБУТО"
			var err: float = (c["pos"] as Vector3).distance_to(m.global_position) if st >= 0 else -1.0
			transitions.append("%s t=%d %s" % [m.uname, int(t), name])
			print("[AITEST] t=%3d %s -> %s (marker %.0f m from the real man, model visible=%s)" % [int(t), m.uname, name, err, m.model.visible])
	if stage == 2 and t > 260.0:
		# fuzzy sighting through a jammed link
		var m0 = post.members[0]
		W.intel.contacts.erase(m0)
		m0.revealed = 0.0
		W.intel.observe(m0, "дрон (поганий сигнал)", 0.35)
		var c: Dictionary = W.intel.contact_of(m0)
		print("[AITEST] jammed sighting q=0.35: status=%s, error radius %.0f m, marker %.0f m off, model visible=%s" % [
			IntelSystem.NAMES[c["status"]], c["err"], (c["pos"] as Vector3).distance_to(m0.global_position), m0.model.visible])
		print("[AITEST] RESULT intel: transitions %s" % [transitions])
		get_tree().quit()


# ------------------------------------------------------------------ test 3: radio
var _rseen := 0


func _radio(t: float) -> void:
	var sq = W.mission.friendly_squads[0]
	if stage == 0:
		stage = 1
		print("[AITEST] radio: same squad, three conditions")
		W.radio.report(sq, "order", "ТЕСТ-1 чистий ефір, відділення в нормі.", "info", null, 0.0)
		W.radio.report(sq, "fire", "ТЕСТ-2 сильні перешкоди: під щільним вогнем, запитуємо підтримку з лівого флангу", "alert", null, 0.95)
	if stage == 1 and t > 3.0:
		stage = 2
		for m in sq.active_members():
			m.supp_level = 3
		W.radio.report(sq, "contact", "ТЕСТ-3 притиснуті: " + sq.contact_report(), "warn", null, 0.0)
		print("[AITEST] estimate(5, unreliable) x4: %s %s %s %s" % [RadioSystem.estimate(5, false), RadioSystem.estimate(5, false), RadioSystem.estimate(5, false), RadioSystem.estimate(5, true)])
	if stage == 2 and t > 6.0:
		for m in sq.active_members():
			m.supp_level = 0
	while _rseen < W.radio.entries.size():
		var e: Dictionary = W.radio.entries[_rseen]
		_rseen += 1
		print("[AITEST] t=%5.1f RADIO %-12s delay=%.1f s rel=%-9s %s" % [t, e["type"], float(e["delay"]), e["rel"], e["text"]])
	if t > 240.0 and stage < 9:
		stage = 9
		print("[AITEST] false reports in 240 s: %d (entries %d)" % [W.radio.false_reports, W.radio.entries.size()])
		get_tree().quit()


## `--aitest=cover`: how good is the cover the AI picks? A threat (the enemy
## post) and ~200 positions in front of it: for each, the cover search runs
## once; the chosen spot is "hidden" if a man lying / crouching there cannot be
## seen from the threat. A second search from the chosen spot shows if men
## would hop on ("oscillation").
func _cover(t: float) -> void:
	if stage != 0 or t < 2.0:
		return
	stage = 1
	var g: TerrainGrid = W.grid
	# the threat: a man standing in the open field north of the ruins, looking
	# south over the cratered field, the ruins and our tree line
	var T: Vector3 = g.ground(Vector3(-15, 0, -5))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--threat="):
			var xz := a.substr(9).split(",")
			T = g.ground(Vector3(float(xz[0]), 0, float(xz[1])))
	var eye := T + Vector3(0, 1.6, 0)
	var cal := [0, 0, 0]
	var possible := 0
	var cn := 0
	var n := 0
	var hid0 := 0
	var hid := 0
	var moved := 0
	var hops := 0
	var vsum := 0.0
	var dsum := 0.0
	var z := T.z + 20.0
	while z <= T.z + 95.0:
		var x := T.x - 50.0
		while x <= T.x + 50.0:
			var P := g.ground(Vector3(x, 0, z))
			if g.inf_solid[g.cidx(P.x, P.z)] == 0:
				cn += 1
				for hi in 3:
					if g.visibility(eye, P + Vector3(0, [0.55, 1.05, 1.6][hi], 0)) >= 0.2:
						cal[hi] += 1
				n += 1
				if g.visibility(eye, P + Vector3(0, 0.55, 0)) < 0.2:
					hid0 += 1
				var C: Vector3 = g.find_cover(P, 6.0, T, [])
				var v: float = g.visibility(eye, C + Vector3(0, 0.55, 0))
				vsum += v
				if v < 0.2:
					hid += 1
				var dm := Vector2(C.x - P.x, C.z - P.z).length()
				if dm > 1.5:
					moved += 1
					dsum += dm
				# the upper bound: is there any hidden free cell within 6 m at all?
				var c0 := g.cell_of(P.x, P.z)
				var any := false
				for dz in range(-3, 4):
					for dx in range(-3, 4):
						var cc := Vector2i(c0.x + dx, c0.y + dz)
						var w := g.cell_center(cc)
						if any or g.inf_solid[g.ci(cc)] != 0 or Vector2(w.x - P.x, w.z - P.z).length() > 6.0:
							continue
						if g.visibility(eye, w + Vector3(0, 0.55, 0)) < 0.2:
							any = true
				if any:
					possible += 1
				var C2: Vector3 = g.find_cover(C, 6.0, T, [])
				if Vector2(C2.x - C.x, C2.z - C.z).length() > 1.5:
					hops += 1
			x += 7.0
		z += 7.0
	print("[AITEST] COVER positions %d: hidden before %d%%, after the search %d%% (mean visibility %.2f); moved %d (avg %.1f m); would hop on %d (%d%%)" % [
		n, hid0 * 100 / maxi(n, 1), hid * 100 / maxi(n, 1), vsum / maxf(n, 1), moved, dsum / maxf(moved, 1), hops, hops * 100 / maxi(n, 1)])
	print("[AITEST] COVER a hidden cell within 6 m exists for %d%% of the positions (the best a search can do)" % [possible * 100 / maxi(n, 1)])
	print("[AITEST] COVER calibration: seen lying %d%%, crouching %d%%, standing %d%%" % [cal[0] * 100 / maxi(cn, 1), cal[1] * 100 / maxi(cn, 1), cal[2] * 100 / maxi(cn, 1)])
	print("[AITEST] RESULT cover: done")
	get_tree().quit()


## `--aitest=fire`: ammunition, the field of view for new contacts, and
## the "why is he not shooting" reasons.
func _fire(t: float) -> void:
	if stage != 0 or t < 2.0:
		return
	stage = 1
	var sq = W.mission.friendly_squads[0]
	var u = null
	for m in sq.active_members():
		if m.role == "rifleman":
			u = m
			break
	# 1) ammunition: spares run down, then he is out
	var start: int = u.rounds_left()
	var reloads := 0
	while u.mags_left > 0:
		u.mag = 0
		u._reload()
		reloads += 1
	u.mag = 0
	u._reload()
	print("[AITEST] AMMO rifleman: %d rounds at the start, %d reloads from spares, now out=%s, reason «%s»" % [start, reloads, u.out_of_ammo(), u.fire_reason()])
	u.mags_left = 7
	u.mag = 30
	u.reloading = 0.0
	# 2) field of view: a stranger standing in the open 60 m away — in front,
	# to the side, behind
	var post = _team("Пост")
	var e = post.members[0]
	e.stop()
	e.global_position = W.grid.ground(Vector3(40, 0, 10))
	e.posture = Soldier.P.STAND
	var ep: Vector3 = e.global_position
	u.stop()
	u.global_position = W.grid.ground(Vector3(40, 0, 70))
	var hits := {"front": 0, "side": 0, "rear": 0}
	for k in ["front", "side", "rear"]:
		var face: float = u.yaw_to(ep) + {"front": 0.0, "side": PI * 0.5, "rear": PI}[k]
		for i in 200:
			sq.known.clear()
			e.revealed = -99.0   # not seen by the drone / anyone (a NEW contact)
			e.marked = false
			u.yaw = face
			u.ai._perceive()
			if u.ai.vis.has(e):
				hits[k] += 1
	print("[AITEST] FOV a new enemy 60 m away (visibility %.2f) noticed in 200 looks: front %d, side %d, rear %d" % [W.grid.visibility(u.eye_point(), e.aim_point()), hits["front"], hits["side"], hits["rear"]])
	# 3) reasons
	u.yaw = u.yaw_to(ep)
	sq.known.clear()
	u.target = null
	u.area_target = null
	print("[AITEST] REASON nobody known: «%s»" % u.fire_reason())
	sq.known[e] = {"t": W.time, "pos": ep}
	print("[AITEST] REASON enemy known but not his target: «%s»" % u.fire_reason())
	u.reloading = 1.0
	print("[AITEST] REASON reloading: «%s»" % u.fire_reason())
	u.reloading = 0.0
	u.suppression = 80.0
	u._update_supp_level()
	print("[AITEST] REASON suppressed: «%s»" % u.fire_reason())
	print("[AITEST] RESULT fire: done")
	get_tree().quit()


## `--aitest=react`: individual reaction delays to a sudden burst of fire,
## and what a comrade going down does to the men around him.
func _react(t: float) -> void:
	if stage != 0 or t < 12.0:
		return
	stage = 1
	var sq = W.mission.friendly_squads[0]
	var act: Array = sq.active_members()
	for m in act:
		m.react_t = 0.0
		m.last_threat_t = -100.0
	for m in act:
		m.add_suppression(10.0, "bullet")
	var rt: Array = []
	for m in act:
		rt.append(snappedf(m.react_t, 0.01))
	rt.sort()
	print("[AITEST] REACT delays after the same burst: %s (spread %.2f s)" % [str(rt), float(rt[rt.size() - 1]) - float(rt[0])])
	# a comrade goes down in the middle of the squad
	var victim = act[act.size() / 2]
	var near: Array = []
	for m in act:
		if m != victim and m.global_position.distance_to(victim.global_position) < AIConfig.COMRADE_R:
			near.append(m)
			m.ai.cover_t = 5.0
	var stress0: Array = near.map(func(m): return m.stress)
	var supp0: Array = near.map(func(m): return m.suppression)
	W.damage.set_health(victim, Soldier.H.INCAP, null, "test")
	var lines: Array = []
	for i in near.size():
		var m = near[i]
		lines.append("%s d%.1f supp %+.0f stress %+.1f cover re-think %s" % [m.rdata["short"], m.global_position.distance_to(victim.global_position),
			m.suppression - float(supp0[i]), m.stress - float(stress0[i]), m.ai.cover_t <= 0.0])
	print("[AITEST] COMRADE DOWN, men within %.0f m: %s" % [AIConfig.COMRADE_R, lines])
	var occ: Array = sq.occupied(act[0])
	print("[AITEST] DANGER SPOT in the occupied list: %s" % [occ.any(func(p): return (p as Vector3).distance_to(victim.global_position) < 0.5)])
	print("[AITEST] RESULT react: done")
	get_tree().quit()


## `--aitest=leader`: the leader goes down; an order given right after
## waits until someone takes command.
var _ld_order_t := -1.0
var _ld_done := false


func _leader(t: float) -> void:
	var sq = W.mission.friendly_squads[0]
	if stage == 0 and t > 8.0:
		stage = 1
		var ld = null
		for m in sq.members:
			if m.role == "leader":
				ld = m
		W.damage.set_health(ld, Soldier.H.INCAP, null, "test")
		print("[AITEST] LEADER down at t=%.1f, spell %.1f s" % [t, sq.leaderless_t])
		sq.issue_order("move", sq.center() + Vector3(0, 0, -25))
		_ld_order_t = t
		print("[AITEST] LEADER order given at t=%.1f: squad order now «%s», pending %s" % [t, sq.order, sq.pending_order != null])
	elif stage == 1 and sq.acting != null:
		stage = 2
		print("[AITEST] LEADER %s took command at t=%.1f (%.1f s after the order); order now «%s», pending %s" % [sq.acting.uname, t, t - _ld_order_t, sq.order, sq.pending_order != null])
		print("[AITEST] LEADER leader() = %s" % sq.leader().uname)
		print("[AITEST] RESULT leader: done")
		get_tree().quit()
	elif t > 60.0:
		print("[AITEST] RESULT leader: nobody took command in 60 s")
		get_tree().quit()


## `--map=treeline --aitest=shift`: our squad shows itself in front of
## the western team; the enemy should send a pair from a calm team — and
## nothing while no team has seen us.
var _sh_team = null
var _sh_d0 := {}


func _shift(t: float) -> void:
	var sq = W.mission.friendly_squads[0]
	if stage == 0 and t > 3.0:
		stage = 1
		_sh_team = _team("Захід")
		var c: Vector3 = _sh_team.center()
		var i := 0
		for m in sq.active_members():
			m.stop()
			m.global_position = W.grid.free_point(c + Vector3(-10 + i * 3, 0, 45))
			i += 1
		print("[AITEST] SHIFT before anyone sees us: shifts %d" % W.enemy_ai.shifts)
		for e in sq.active_members():
			_sh_team.report(e, e.global_position)
		W.enemy_ai.raise_alert(2)
		for s2 in W.enemy_ai.squads:
			for m in s2.active_members():
				_sh_d0[m] = m.global_position.distance_to(c)
	elif stage == 1:
		for e in sq.active_members():
			_sh_team.report(e, e.global_position)   # keep them in sight
		if W.enemy_ai.shifts > 0 or t > 90.0:
			stage = 2
			print("[AITEST] SHIFT after %.0f s: shifts %d" % [t - 3.0, W.enemy_ai.shifts])
	elif stage == 2 and (t > 100.0 or W.enemy_ai.shifts > 0 and t > 50.0):
		var c: Vector3 = _sh_team.center()
		var moved: Array = []
		for m in _sh_d0.keys():
			if m.is_active() and m.squad != _sh_team and float(_sh_d0[m]) - m.global_position.distance_to(c) > 8.0:
				moved.append("%s %s %.0f→%.0f m" % [m.squad.team_name, m.rdata["short"], _sh_d0[m], m.global_position.distance_to(c)])
		print("[AITEST] SHIFT men who came closer to the western team: %s" % [moved])
		print("[AITEST] RESULT shift: done")
		get_tree().quit()


## `--map=treeline --aitest=withdraw`: the position collapses — who
## covers, who pulls back, is there smoke, do the cover men follow later.
var _wd_t := -1.0
var _wd_smoke0 := 0


func _withdraw_test(t: float) -> void:
	var ai = W.enemy_ai
	if stage == 0 and t > 3.0:
		stage = 1
		ai.raise_alert(2)
		var all: Array = []
		for sq in ai.squads:
			for m in sq.active_members():
				all.append(m)
		all.shuffle()
		var kill := int(all.size() * 0.76)
		for i in kill:
			W.damage.set_health(all[i], Soldier.H.DEAD, null, "test")
		_wd_smoke0 = W.smoke_clouds.size()
		print("[AITEST] WITHDRAW %d of %d enemies down" % [kill, all.size()])
	elif stage == 1 and ai.retreat_ordered:
		stage = 2
		_wd_t = t
	elif stage == 2 and t > _wd_t + 4.0:
		stage = 3
		var cov := 0
		var go := 0
		for sq in ai.squads:
			for m in sq.active_members():
				if m.solo == "hold":
					cov += 1
				elif m.moving:
					go += 1
		print("[AITEST] WITHDRAW +4 s: covering %d, pulling back %d, smoke clouds +%d" % [cov, go, W.smoke_clouds.size() - _wd_smoke0])
	elif stage == 3 and t > _wd_t + 50.0:
		var cov := 0
		var left := 0
		for sq in ai.squads:
			for m in sq.active_members():
				left += 1
				if m.solo == "hold":
					cov += 1
		print("[AITEST] WITHDRAW +50 s: still covering %d, still on the map %d, escaped %d" % [cov, left, ai.escaped])
		print("[AITEST] RESULT withdraw: done")
		get_tree().quit()
	elif t > 200.0:
		print("[AITEST] RESULT withdraw: no withdrawal")
		get_tree().quit()


## `--map=treeline --aitest=recon [--recon-cover]`: our squad stands
## bunched in the open field (or under the trees of our tree line); the enemy
## recon drone circles over it.
var _rc_msgs: Array = []
var _rc_r0 := 0
var _rc_t := -1.0
var _rc_known_t := -1.0


func _recon(t: float) -> void:
	var sq = W.mission.friendly_squads[0]
	var ai = W.enemy_ai
	var spot := Vector3(-20, 0, 40) if not ("--recon-cover" in OS.get_cmdline_user_args()) else Vector3(-20, 0, 70)
	if stage == 0 and t > 3.0:
		stage = 1
		Events.message.connect(func(txt, _k): if txt.contains(Loc.t("дрон-розвідник")): _rc_msgs.append("%d %s" % [int(W.time - _rc_t), txt]))
		var i := 0
		for m in sq.active_members():
			m.stop()
			m.global_position = W.grid.free_point(W.grid.ground(spot) + Vector3((i % 4) * 2.5, 0, (i / 4) * 2.5))
			i += 1
		sq.issue_order("hold", W.grid.ground(spot))
		ai.raise_alert(1)
		ai.recon_t = W.time
		_rc_r0 = ai.mortar_rounds
	elif stage == 1 and ai.recon != null and is_instance_valid(ai.recon):
		stage = 2
		_rc_t = W.time
		ai.recon.orbit_c = W.grid.ground(spot)
		ai.recon.retarget_t = 999.0
		ai.recon.global_position = W.grid.ground(spot) + Vector3(0, AIConfig.RECON_ALT, -60)
	elif stage == 2:
		if _rc_known_t < 0.0 and not ai.drone_known.is_empty():
			_rc_known_t = W.time - _rc_t
		if W.time - _rc_t > 75.0:
			var d = ai.recon
			print("[AITEST] RECON %s: seen %d of ours, first report to the enemy at %s s, warnings %s, enemy mortar rounds used %d" % [
				"under the trees" if "--recon-cover" in OS.get_cmdline_user_args() else "in the open",
				d.seen.size() if d != null and is_instance_valid(d) else -1,
				("%.0f" % _rc_known_t) if _rc_known_t >= 0.0 else "never", _rc_msgs, _rc_r0 - ai.mortar_rounds])
			print("[AITEST] RESULT recon: done")
			get_tree().quit()


## `--map=field --aitest=reinf`: the fight has gone on long enough — a
## wave comes from the rear, its BMP follows; hidden until our side sees it.
var _rf_msgs: Array = []


func _reinf(t: float) -> void:
	var ai = W.enemy_ai
	if stage == 0 and t > 3.0:
		stage = 1
		Events.message.connect(func(txt, _k): _rf_msgs.append("%d %s" % [int(t), txt]))
		ai.raise_alert(2)
	elif stage == 1 and ai.reinf_init:
		stage = 2
		ai.fight_t -= 1000.0   # pretend the fight has gone on for a long time
		var entry: Vector3 = W.grid.ground(W.mission.def.enemy_retreat)
		var near := 999.0
		for u in W.units:
			if u.side == 0 and u.is_active():
				near = minf(near, u.global_position.distance_to(entry))
		print("[AITEST] REINF waves planned %s, entry %s, nearest of ours %.0f m" % [str(ai.waves), entry.snapped(Vector3.ONE), near])
	elif stage == 2 and t > 45.0:
		stage = 3
		var men := 0
		var veh = null
		for u in ai.wave_units:
			if u is Soldier:
				men += 1
			else:
				veh = u
		print("[AITEST] REINF wave: %d men, vehicle %s; men visible to us %d" % [men, veh.vname if veh else "none",
			ai.wave_units.filter(func(u): return u is Soldier and u.model.visible).size()])
		if veh:
			print("[AITEST] REINF vehicle at %s, moving %s, visible %s, hp %d" % [veh.global_position.snapped(Vector3.ONE), veh.moving, veh.visible, int(veh.hp)])
			# our squad shows up in front of it
			var sq = W.mission.friendly_squads[0]
			var i := 0
			for m in sq.active_members():
				m.stop()
				m.global_position = W.grid.free_point(veh.global_position + Vector3(-8 + i * 2.5, 0, 100))
				i += 1
	elif stage == 3 and t > 75.0:
		var veh = null
		for u in ai.wave_units:
			if u is Vehicle:
				veh = u
		if veh:
			print("[AITEST] REINF after our men came close: vehicle visible %s, ever seen %s, hp %d, state %s" % [veh.visible, veh.ever_seen, int(veh.hp), veh.state])
		print("[AITEST] REINF messages: %s" % [_rf_msgs.filter(func(m): return m.contains(Loc.t("підкріплення")) or m.contains(Loc.t("техніку")))])
		print("[AITEST] RESULT reinf: done")
		get_tree().quit()


## `--map=urban --aitest=windows`: our squad takes a front-row block with the
## enemy known in the towers to the north; how many men end up at windows
## that face the enemy AND see him. Then enemies show up on the south side:
## do the men move to other windows?
var _wn_b = null
var _wn_t := 0.0


func _useful(sq, thr: Array) -> Array:
	var at := 0
	var good := 0
	for m in sq.active_members():
		if m.post == null:
			continue
		at += 1
		var eye: Vector3 = m.post["post"] + Vector3(0, AIConfig.BLD_EYE, 0)
		var c := Vector3.ZERO
		var sees := false
		for p in thr:
			c += p
			if W.grid.visibility(eye, (p as Vector3) + Vector3(0, 1.2, 0)) >= 0.2:
				sees = true
		c /= maxf(thr.size(), 1)
		var dir: Vector3 = c - m.post["post"]
		dir.y = 0.0
		if sees and (m.post["dir"] as Vector3).dot(dir.normalized()) > 0.3:
			good += 1
	return [at, good]


func _windows(t: float) -> void:
	var sq = W.mission.friendly_squads[0]
	if stage == 0 and t > 3.0:
		stage = 1
		_wn_b = Buildings.at(W.grid.ground(Vector3(52, 0, 42)))
		var i := 0
		for m in sq.active_members():
			m.stop()
			m.global_position = W.grid.free_point(Vector3(46 + i * 2.0, 0, 56))
			i += 1
		for e in W.enemy_ai.squads:
			for u in e.active_members():
				if u.global_position.z < 0.0 and u.global_position.z > -60.0:
					sq.report(u, u.global_position)
		sq.issue_order("hold", _wn_b["center"])
		_wn_t = t
	elif stage == 1 and t - _wn_t <= 35.0:
		for e in W.enemy_ai.squads:   # the towers stay in sight
			for u in e.active_members():
				if u.global_position.z < 0.0 and u.global_position.z > -60.0:
					sq.report(u, u.global_position)
	elif stage == 1:
		stage = 2
		var thr: Array = sq.known.values().map(func(k): return k["pos"])
		var r := _useful(sq, thr)
		print("[AITEST] WINDOWS north threat: %d men at windows, %d of them face and see the enemy (of %d posts in the block)" % [r[0], r[1], _wn_b["windows"].size()])
		for m in sq.members:
			if m.post == null:
				print("[AITEST]   not at a window: %s pending=%s moving=%s ai=%s slot_d=%.1f in_bld=%s post_d=%.1f" % [m.rdata["short"], m.post_pending != null, m.moving, m.ai.state,
					m.global_position.distance_to(m.slot), Buildings.at(m.global_position) != null,
					Vector2(m.global_position.x - m.post_pending["post"].x, m.global_position.z - m.post_pending["post"].z).length() if m.post_pending != null else -1.0])
		# can one walk across the block inside? north post "in" -> south post "in"
		var nw = null
		var sw = null
		for w in _wn_b["windows"]:
			if int(w["floor"]) == 0 and (w["dir"] as Vector3).z < -0.5 and nw == null:
				nw = w
			if int(w["floor"]) == 0 and (w["dir"] as Vector3).z > 0.5 and sw == null:
				sw = w
		if nw and sw:
			var path: PackedVector3Array = W.grid.find_path_inf(nw["in"], sw["in"], false)
			var outside := 0
			for q in path:
				if Buildings.at(q) == null:
					outside += 1
			print("[AITEST]   across the block: %s -> %s, %d points, %d of them outside; in-cells solid %d / %d; doors %d" % [nw["in"].snapped(Vector3.ONE), sw["in"].snapped(Vector3.ONE), path.size(), outside,
				W.grid.inf_solid[W.grid.cidx(nw["in"].x, nw["in"].z)], W.grid.inf_solid[W.grid.cidx(sw["in"].x, sw["in"].z)], _wn_b["doors"].size()])
			var line := ""
			var z0: float = nw["in"].z
			var x0: float = nw["in"].x
			for dz in range(-2, 16):
				var c: Vector2i = W.grid.cell_of(x0, z0 + dz * 1.0)
				line += str(W.grid.inf_solid[W.grid.ci(c)])
			print("[AITEST]   solid cells north->south through the block at x=%.0f: %s" % [x0, line])
		# the enemy turns up south of the block
		sq.known.clear()
		var k := 0
		for e in W.enemy_ai.squads:
			for u in e.active_members():
				if k < 4:
					u.stop()
					u.global_position = W.grid.free_point(Vector3(30 + k * 12, 0, 100))
					u.set_meta("moved", true)
					sq.report(u, u.global_position)
					k += 1
		for u in W.units:
			if u.side == 1 and not u.has_meta("moved"):
				u.revealed = -99.0
		_wn_t = t
	elif stage == 2:
		for u in W.units:
			if u.side == 1 and u.has_meta("moved"):
				sq.report(u, u.global_position)   # keep them in sight
		if t - _wn_t > 25.0:
			var thr: Array = sq.known.values().map(func(k): return k["pos"])
			var r := _useful(sq, thr)
			print("[AITEST] WINDOWS south threat after 25 s: %d men at windows, %d face and see the new enemy" % [r[0], r[1]])
			print("[AITEST]   squad order %s" % sq.order)
			for m in sq.members:
				print("[AITEST]   %s %s post=%s pending=%s moving=%s ai=%s supp=%d slot_d=%.1f in_bld=%s" % [m.rdata["short"], m.health, m.post != null, m.post_pending != null, m.moving, m.ai.state, m.supp_level,
					m.global_position.distance_to(m.slot), Buildings.at(m.global_position) != null])
			print("[AITEST] RESULT windows: done")
			get_tree().quit()


## `--aitest=drag` (field): a man goes down in the open, in view of the known
## trench garrison (held silent so fire does not muddle the test); two of his
## comrades drag him to cover, then first aid as usual.
var _dg_v = null
var _dg_eye := Vector3.ZERO
var _dg_vis0 := 0.0
var _dg_t := 0.0
var _dg_p := Vector3.ZERO
var _dg_start := -1.0
var _dg_foe = null


func _dg_vis(p: Vector3) -> float:
	return W.grid.visibility(_dg_eye, W.grid.ground(p) + Vector3(0, AIConfig.COVER_BODY_H, 0))


## Is there cover near `p` from `e`, and a short way to it?
func _dg_cover_ok(p: Vector3, e: Vector3) -> bool:
	for u in W.units:
		if u.side == 1 and u.is_active() and u.global_position.distance_to(p) < AIConfig.DRAG_CLOSE + 15.0:
			return false
	var sq = W.mission.friendly_squads[0]
	return sq._drag_spot(p, [e], e, _dg_vis(p)) != null


func _drag(t: float) -> void:
	var sq = W.mission.friendly_squads[0]
	if stage == 0 and t > 3.0:
		stage = 1
		for u in W.units:
			if u.side == 1:
				u.noncombat = true
			elif u.squad != sq:
				u.noncombat = true   # nobody else shoots the test garrison away
		for m in sq.members:
			m.mag = 0
			m.mags_left = 0   # and the test squad does not shoot them away either
			m.grenades = 0
		for v in W.mission.friendly_vehicles:
			v.stop()
			v.offmap = true
			v.visible = false
		# enemy squads nearest to where we come from first
		var foes: Array = []
		for es in W.enemy_ai.squads:
			if not es.members.is_empty() and es.members[0].global_position.z < 60.0:
				foes.append(es)
		foes.sort_custom(func(a, b): return a.members[0].global_position.z > b.members[0].global_position.z)
		var spot = null
		var e := Vector3.ZERO
		for fsq in foes.slice(0, 6):
			e = fsq.members[0].global_position
			_dg_eye = e + Vector3(0, 1.5, 0)
			# an open spot 60+ m from them, seen well, with cover a short drag away
			for z in range(25, 120, 4):
				for x in range(-60, 61, 5):
					var p: Vector3 = W.grid.ground(Vector3(e.x + x, 0, e.z + z))
					if p.distance_to(e) <= 60.0 or _dg_vis(p) <= 0.7 or W.grid.in_channel(p, 1.2) or Buildings.at(p) != null:
						continue
					if W.grid.find_path_inf(p, p + Vector3(3, 0, 0), false).size() > 0 and _dg_cover_ok(p, e):
						spot = p
						break
				if spot != null:
					break
			if spot != null:
				_dg_foe = fsq
				break
		if spot != null:
			for m in _dg_foe.members:
				m.marked = true
				sq.report(m, m.global_position)
		if spot == null:
			print("[AITEST] RESULT drag: FAIL no open spot")
			get_tree().quit()
			return
		sq.issue_order("hold", spot + Vector3(0, 0, 6))
		var act: Array = sq.active_members()
		for i in act.size():
			act[i].stop()
			act[i].global_position = W.grid.free_point(spot + Vector3(-6 + (i % 4) * 3, 0, 6 + (i / 4) * 3))
		_dg_v = act[act.size() - 1]
		_dg_v.global_position = spot
		W.damage.set_health(_dg_v, Soldier.H.INCAP, null, "test")
		_dg_vis0 = _dg_vis(spot)
		_dg_p = spot
		_dg_t = t
		print("[AITEST] DRAG casualty at %s, %.0f m from the trench, seen %.2f" % [spot.snapped(Vector3.ONE), spot.distance_to(e), _dg_vis0])
		return
	if stage >= 1 and _dg_foe != null:
		for m in _dg_foe.members:
			if m.is_active():
				sq.report(m, m.global_position)   # the contact goes on
	if stage == 1 and "--verbose" in OS.get_cmdline_user_args() and int(t * 2.0) != int((t - get_process_delta_time()) * 2.0):
		var tl: Array = []
		for tp in sq.threat_points(_dg_v.global_position, AIConfig.DRAG_THREATS):
			tl.append("%.0f/%.2f%s" % [(tp as Vector3).distance_to(_dg_v.global_position), sq._seen_from(tp, _dg_v.global_position), "*" if _dg_foe.members.any(func(m): return m.global_position.distance_to(tp) < 1.0) else ""])
		print("[AITEST] DRAG trace t=%.1f pos %s carried %s aided %s drag %s cover %s helpers %d thr %s" % [t - _dg_t, _dg_v.global_position.snapped(Vector3.ONE), _dg_v.carried, _dg_v.aided, not sq.drag.is_empty(), sq._drag_cover(_dg_v), sq._drag_helpers(_dg_v, sq.active_members()).size(), tl])
	if stage == 1:
		if not sq.drag.is_empty() and _dg_start < 0.0:
			_dg_start = t - _dg_t
		if sq.drag_done > 0:
			stage = 2
			var p: Vector3 = _dg_v.global_position
			var helpers := 0
			for m in sq.active_members():
				if m.global_position.distance_to(p) < 4.0:
					helpers += 1
			print("[AITEST] DRAG started after %.0f s" % _dg_start)
			print("[AITEST] DRAG done in %.0f s: moved %.1f m, seen %.2f -> %.2f, %d men next to him, carried=%s" % [t - _dg_t,
				p.distance_to(_dg_p), _dg_vis0, _dg_vis(p), helpers, _dg_v.carried])
			_dg_t = t
		elif t - _dg_t > 70.0:
			var p: Vector3 = _dg_v.global_position
			var thr = sq.nearest_threat(p)
			var cov: Vector3 = W.grid.find_cover(p, AIConfig.DRAG_COVER_R, thr, sq.occupied(null), false) if thr != null else p
			print("[AITEST] DRAG debug: threat %s d=%.0f, cover %s (%.1f m, seen %.2f), helpers %d, act %d, order %s, leaderless %.1f" % [thr,
				(thr as Vector3).distance_to(p) if thr != null else -1.0, cov.snapped(Vector3.ONE), cov.distance_to(p), _dg_vis(cov),
				sq._drag_helpers(_dg_v, sq.active_members()).size(), sq.active_members().size(), sq.order, sq.leaderless_t])
			var tl: Array = []
			for tp in sq.threat_points(p, AIConfig.DRAG_THREATS):
				tl.append("%.0f m seen %.2f" % [(tp as Vector3).distance_to(p), sq._seen_from(tp, p)])
			print("[AITEST] DRAG debug: test foes %s" % [_dg_foe.members.map(func(m): return "%s h%d surr %s known %s alive %s pos %s veh %s" % [m.role, m.health, m.surrendered, sq.known.has(m), W.is_alive_target(m), m.global_position.snapped(Vector3.ONE), m.vehicle])])
			print("[AITEST] DRAG debug: threats %s, _drag_cover %s, aided %s, aid_by %s" % [tl, sq._drag_cover(_dg_v), _dg_v.aided, _dg_v.aid_by])
			for m in sq.active_members():
				print("[AITEST]   %s d=%.1f supp=%d health=%d action=%s solo=%s" % [m.rdata["short"], m.global_position.distance_to(p), m.supp_level, m.health, m.action, m.solo])
			print("[AITEST] RESULT drag: FAIL not dragged (drag=%s)" % [sq.drag])
			get_tree().quit()
		return
	if stage == 2:
		if _dg_v.aided or t - _dg_t > 40.0:
			var busy := 0
			for m in sq.members:
				if m.dragging != null:
					busy += 1
			print("[AITEST] DRAG first aid after the drag: %s; men still marked dragging: %d" % [_dg_v.aided, busy])
			print("[AITEST] RESULT drag: %s" % ("ok" if _dg_v.aided and busy == 0 else "FAIL"))
			get_tree().quit()


# ------------------------------------------------------------------ resupply
## A squad short of magazines holding next to its BMP tops up on its own
## (phase 1), the "ammo" order walks it from 100 m to the vehicle (phase 2),
## aboard the men top up from the stock (phase 3).
var _rs_v = null
var _rs_t := 0.0
var _rs_stock := 0


func _rs_drain(sq, left: int) -> void:
	for m in sq.members:
		if m.mags_start > 0:
			m.mags_left = mini(left, m.mags_start)
		m.grenades = 0


func _rs_full(sq) -> bool:
	for m in sq.members:
		if m.health >= Soldier.H.INCAP or m.evacuated:
			continue
		if m.mags_start > 0 and m.mags_left < m.mags_start:
			return false
		if m.grenades < m.nades_start:
			return false
	return true


func _rs_dump(sq) -> void:
	for m in sq.members:
		print("[AITEST]   %s mags %d/%d nades %d/%d resup_v=%s act=%s moving=%s state=%s d=%.1f" % [m.uname, m.mags_left, m.mags_start, m.grenades, m.nades_start,
			m.resup_v != null, m.action, m.moving, m.ai.state, m.global_position.distance_to(_rs_v.rear_point())])
	print("[AITEST]   order=%s mounted=%s stock %d / %d nades %d" % [sq.order, sq.mounted, _rs_v.stock_rounds, _rs_v.stock_rounds0, _rs_v.stock_nades])


func _resup(t: float) -> void:
	var sq = W.mission.friendly_squads[0]
	if stage == 0 and t > 3.0:
		for u in W.units:
			if u.side == 1:
				u.noncombat = true
		for v in W.mission.friendly_vehicles:
			if v.stock_rounds0 > 0 and v.state != "destroyed":
				_rs_v = v
				break
		if _rs_v == null or sq.mounted:
			print("[AITEST] RESULT resupply: FAIL setup (vehicle=%s mounted=%s)" % [_rs_v != null, sq.mounted])
			get_tree().quit()
			return
		_rs_v.stop()
		sq.vehicle = _rs_v
		var spot: Vector3 = W.grid.free_point(_rs_v.rear_point() - _rs_v.forward() * 14.0)
		sq.issue_order("hold", spot)
		var act: Array = sq.active_members()
		for i in act.size():
			act[i].stop()
			act[i].global_position = W.grid.free_point(spot + Vector3(-5 + (i % 4) * 3, 0, (i / 4) * 3))
		sq.issue_order("hold", spot)
		_rs_drain(sq, 1)
		_rs_stock = _rs_v.stock_rounds
		_rs_t = t
		stage = 1
		print("[AITEST] resupply: %s, %d men, stock %d rounds / %d grenades" % [_rs_v.vname, act.size(), _rs_v.stock_rounds, _rs_v.stock_nades])
	elif stage == 1:
		if _rs_full(sq) and sq.resup_men.is_empty():
			print("[AITEST] phase 1 (hold next to the vehicle): topped up in %.1f s, %d rounds taken, %d men" % [t - _rs_t, _rs_stock - _rs_v.stock_rounds, sq.resup_done])
			# phase 2: 100 m away, the "ammo" order
			var far = null
			for k in range(0, 16):
				var a: float = TAU * k / 16.0
				var p: Vector3 = W.grid.free_point(W.grid.clamp_in(_rs_v.global_position + Vector3(cos(a), 0, sin(a)) * 100.0, 6.0))
				if p.distance_to(_rs_v.global_position) > 80.0 and W.grid.find_path_inf(p, _rs_v.rear_point(), false).size() > 0:
					far = p
					break
			if far == null:
				print("[AITEST] RESULT resupply: FAIL no spot 100 m away")
				get_tree().quit()
				return
			sq.issue_order("hold", far)
			var act: Array = sq.active_members()
			for i in act.size():
				act[i].stop()
				act[i].global_position = W.grid.free_point(far + Vector3(-5 + (i % 4) * 3, 0, (i / 4) * 3))
			sq.issue_order("hold", far)
			_rs_drain(sq, 3)
			_rs_v.stock_rounds = _rs_v.stock_rounds0
			_rs_v.stock_nades = _rs_v.stock_nades0
			_rs_stock = _rs_v.stock_rounds
			_rs_t = t
			stage = 2
		elif t - _rs_t > 70.0:
			print("[AITEST] phase 1 timeout")
			_rs_dump(sq)
			print("[AITEST] RESULT resupply: FAIL phase 1")
			get_tree().quit()
	elif stage == 2 and t - _rs_t > 4.0:
		var auto_n: int = sq.resup_men.size()
		W.command.selection = [sq]
		W.command.cmd_resupply()
		print("[AITEST] phase 2: the \"ammo\" order from %.0f m (runners before the order: %d), call=%s" % [sq.center().distance_to(_rs_v.global_position), auto_n, sq.resup_call != null])
		stage = 3
	elif stage == 3:
		if _rs_full(sq) and sq.resup_men.is_empty():
			print("[AITEST] phase 2 (the \"ammo\" order): topped up in %.1f s, %d rounds taken, call cleared=%s" % [t - _rs_t, _rs_stock - _rs_v.stock_rounds, sq.resup_call == null])
			_rs_drain(sq, 2)
			_rs_v.stock_rounds = _rs_v.stock_rounds0
			_rs_v.stock_nades = _rs_v.stock_nades0
			_rs_stock = _rs_v.stock_rounds
			for m in sq.active_members():
				_rs_v.board(m)
			sq.mounted = true
			sq.order = "mounted"
			_rs_t = t
			stage = 4
		elif t - _rs_t > 120.0:
			print("[AITEST] phase 2 timeout")
			_rs_dump(sq)
			print("[AITEST] RESULT resupply: FAIL phase 2")
			get_tree().quit()
	elif stage == 4:
		var aboard_full := true
		var aboard := 0
		for m in _rs_v.passengers:
			aboard += 1
			if m.mags_left < m.mags_start or m.grenades < m.nades_start:
				aboard_full = false
		if aboard > 0 and aboard_full:
			print("[AITEST] phase 3 (aboard): %d men topped up in %.1f s, %d rounds taken, stock left %d" % [aboard, t - _rs_t, _rs_stock - _rs_v.stock_rounds, _rs_v.stock_rounds])
			print("[AITEST] RESULT resupply: ok")
			get_tree().quit()
		elif t - _rs_t > 90.0:
			print("[AITEST] phase 3 timeout")
			_rs_dump(sq)
			print("[AITEST] RESULT resupply: FAIL phase 3")
			get_tree().quit()


# ------------------------------------------------------------------ capture and hold
## The garrison is gone and our squads stand in the position: the hold phase
## starts, the counterattack waves come at the position, the battle ends one
## way or the other. `--hold-lose`: our men walk out of the position once the
## hold has begun — the enemy must take it back.
var _hd_end := false
var _hd_log_t := 0.0
var _hd_phase := false
var _hd_lost := false


func _hold_end_check() -> bool:
	if scenario != "hold" or _hd_end or W.mission.phase != MissionManager.Phase.ENDED:
		return false
	_hd_end = true
	var r: Dictionary = W.mission.result
	print("[AITEST] END reason=%s success=%s held %.0f s, waves %d, kia %d, wia %d" % [r.get("reason", "?"), r.get("success", false), float(r.get("held_s", 0)), int(r.get("counter_waves", 0)), int(r.get("kia", 0)), int(r.get("wia", 0))])
	var lose: bool = "--hold-lose" in OS.get_cmdline_user_args()
	var ok: bool = (_hd_lost and r.get("reason", "") == "timeout") if lose else (r.get("reason", "") == "captured" and int(r.get("counter_waves", 0)) >= 2)
	print("[AITEST] RESULT hold: %s" % ("ok" if ok else "FAIL"))
	get_tree().quit()
	return true


func _hold(t: float) -> void:
	var m = W.mission
	var lose: bool = "--hold-lose" in OS.get_cmdline_user_args()
	if stage == 0 and t > 3.0:
		stage = 1
		for u in W.units.duplicate():
			if u.side == 1 and u.health < Soldier.H.DEAD:
				W.damage.set_health(u, Soldier.H.DEAD, null, "test")
		var r: Rect2 = m.def.objective_rect
		var k := 0
		for sq in m.friendly_squads:
			var p := Vector3(r.position.x + r.size.x * (0.2 + 0.2 * (k % 4)), 0, r.position.y + r.size.y * (0.35 + 0.3 * (k / 4)))
			p = W.grid.free_point(p)
			var act: Array = sq.active_members()
			for i in act.size():
				act[i].stop()
				act[i].global_position = W.grid.free_point(p + Vector3((i % 4) * 2.5 - 4.0, 0, (i / 4) * 2.5))
			sq.issue_order("hold", p)
			k += 1
		print("[AITEST] hold: %d squads in the position, hold %.0f s, waves %d" % [k, m.hold_need(), m._counter_waves().size()])
	elif stage >= 1:
		if m.hold_phase and not _hd_phase:
			_hd_phase = true
			print("[AITEST] hold phase began at t=%.0f" % t)
		if lose and _hd_phase and m.counter_sent >= 1 and stage == 1:
			# the counterattack is on its way: everybody walks back out of the position
			stage = 2
			print("[AITEST] t=%.0f the counterattack is coming: our men leave the position" % t)
			for sq in m.friendly_squads:
				sq.issue_order("move", W.grid.free_point(Vector3(0, 0, 100)))
		if _hd_phase and not m.hold_phase and not _hd_lost:
			_hd_lost = true
			print("[AITEST] position lost at t=%.0f (held %.0f s)" % [t, m.hold_t])
			if lose:
				print("[AITEST] RESULT hold: ok")
				get_tree().quit()
				return
		if t - _hd_log_t > 15.0:
			_hd_log_t = t
			var cs := []
			for sq in W.enemy_ai.counter_squads:
				var d: float = sq.center().distance_to(Vector3(m.def.objective_rect.get_center().x, 0, m.def.objective_rect.get_center().y))
				cs.append("%s %d act, %s, %.0f m" % [sq.short, sq.active_count(), sq.order, d])
			print("[AITEST] type=%s capture=%.2f phase=%d" % [m.objectives.type(), m.capture, m.phase])
			print("[AITEST] t=%.0f held %.0f, in zone ours %d / theirs %d, status «%s», counter: %s" % [t, m.hold_t, m.friendlies_in_zone(), m.enemies_in_zone(), m.status_text, "; ".join(cs)])
		if t > 900.0:
			print("[AITEST] RESULT hold: FAIL no end in 900 s")
			get_tree().quit()
