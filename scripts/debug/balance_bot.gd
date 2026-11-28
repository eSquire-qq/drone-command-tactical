class_name BalanceBot
extends Node
## Balance harness (`-- --balance=smart` or `-- --balance=frontal`): plays the
## first mission with a scripted plan and prints one [BALANCE] line.
##  smart   — what a competent player would do: base of fire from our tree
##            line, assault group flanks through the western gully, FPV on
##            the MG bunkers, mortar and smoke before the rush, trench
##            clearing, evacuation of every seriously wounded soldier.
##  frontal — everyone straight at the centre, vehicles in the open field.

var plan := "smart"
var t0 := -1.0
var done := {}
var evac_t := 0.0
var manage_t := 60.0


var downs := {}
var where := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 6.0
	Events.mission_ended.connect(_on_end)
	Events.unit_state_changed.connect(_on_state)
	if "--profile" in OS.get_cmdline_user_args():
		Prof.on = true


var edowns := {}


func _on_state(u, _old: int, h: int) -> void:
	if u.side == 1 and h >= Soldier.H.INCAP and _old < Soldier.H.INCAP:
		var ek: String = u.down_by if u.down_by != "" else "?"
		edowns[ek] = edowns.get(ek, 0) + 1
	if u.side != 0 or h < Soldier.H.INCAP or (h == Soldier.H.DEAD and _old == Soldier.H.INCAP):
		return
	var k: String = u.down_by if u.down_by != "" else "?"
	downs[k] = downs.get(k, 0) + 1
	var p: Vector3 = u.global_position
	var zone := "поле"
	if W.grid.in_channel(p, 1.2):
		zone = "окоп"
	elif p.z > 45.0:
		zone = "тил/посадка"
	elif p.x < -68.0 and p.z > -20.0:
		zone = "балка"
	var tz := "%s@%d" % [zone, int((W.time - t0) / 60.0)]
	if "--verbose" in OS.get_cmdline_user_args():
		print("[DOWN] t=%d %s %s %s pos=%s by=%s order=%s solo=%s" % [int(W.time - t0), u.squad.short, u.rdata["short"], "KIA" if h == Soldier.H.DEAD else "WIA", p.snapped(Vector3.ONE), k, u.squad.order, u.solo])
	where[tz] = where.get(tz, 0) + 1


func _process(delta: float) -> void:
	if not W.running():
		return
	if W.mission.phase != MissionManager.Phase.COMBAT:
		return
	if t0 < 0.0 and "--losprobe" in OS.get_cmdline_user_args():
		_los_probe()
	if t0 < 0.0:
		t0 = W.time
		W.cam.teleport_view(Vector3(-20, 0, -30), 110.0, 40.0, 0.0)
		W.cam.zoom_t = 2.5
	var t := W.time - t0
	if W.mission.hold_phase:
		_mh_t -= delta
		if _mh_t <= 0.0:
			_mh_t = 20.0
			_manage_hold()
	elif W.mission.def.id == "recon":
		_smart_recon(delta, t)
	elif plan == "frontal":
		_frontal(t)
	elif W.mission.def.id == "field":
		_smart_field(t)
	elif W.mission.def.id == "urban":
		_smart_urban(t)
	elif W.mission.def.id == "forest":
		_smart_forest(t)
	elif W.mission.def.id == "village":
		_smart_village(t)
	else:
		_smart(t)
	_dodge_recon(delta)
	_ammo_check(delta, t)
	evac_t -= delta
	if evac_t <= 0.0:
		evac_t = 4.0
		for u in W.units:
			if W.evac.is_valid_patient(u) and u.health == Soldier.H.INCAP and not u.evac_marked:
				W.evac.request(u)


## What a player does on "an enemy recon drone over us": a squad holding in
## one place moves 25–35 m aside and spreads into cover.
## Capture and hold: like a player, the squads dig in inside the position
## (houses, trenches) instead of chasing the counterattack out of it; the
## vehicles stand behind it; enemies already inside are thrown out.
func _manage_hold() -> void:
	var r: Rect2 = W.mission.def.objective_rect
	var inside: Array = []
	for u in W.units:
		if u.side == 1 and u.is_active() and r.grow(4.0).has_point(Vector2(u.global_position.x, u.global_position.z)):
			inside.append(u)
	# an enemy vehicle we can see: FPV it, as a player would
	for v in W.vehicles:
		if is_instance_valid(v) and v.side == 1 and v.state != "destroyed" and v.ever_seen and v.revealed > -5.0:
			_fpv(v)
			break
	# our vehicles come up right behind the position (fire support, ammunition)
	var vk := 0
	for v in W.mission.friendly_vehicles:
		if not is_instance_valid(v) or v.state == "destroyed" or v.offmap or v.is_medevac or v.state == "immobile":
			continue
		var vp := Vector3(r.get_center().x - 15.0 + 30.0 * (vk % 2), 0, r.end.y + 8.0 + 6.0 * (vk / 2))
		vk += 1
		if v.global_position.distance_to(vp) > 25.0 and not v.moving:
			v.order_move(W.grid.free_point(vp, true))
	# the houses of the position, those facing the enemy first
	var houses: Array = []
	if W.map:
		for b in W.map.buildings:
			var bc: Vector3 = b["center"]
			if b["kind"] != "shed" and not (b["windows"] as Array).is_empty() and r.has_point(Vector2(bc.x, bc.z)):
				houses.append(b)
	var er: Vector3 = W.mission.def.enemy_retreat
	houses.sort_custom(func(a, b): return (a["center"] as Vector3).distance_to(er) < (b["center"] as Vector3).distance_to(er))
	var k := 0
	for sq in W.mission.friendly_squads:
		k += 1
		if sq.active_count() < 1 or sq.mounted or sq.resup_call != null or not sq.resup_men.is_empty():
			continue
		var c: Vector3 = sq.center()
		if not inside.is_empty() and sq.active_count() >= 3:
			var best = null
			var bd := INF
			for u in inside:
				var d: float = u.global_position.distance_to(c)
				if d < bd:
					bd = d
					best = u
			if bd < 60.0 and sq.order != "assault" and sq.order != "clear_bld":
				sq.issue_order("assault", best.global_position)
				continue
		if r.has_point(Vector2(c.x, c.z)) and sq.order in ["hold", "occupy", "defend"]:
			continue
		if sq.order in ["assault", "clear_bld", "clear"]:
			continue
		var p := Vector3(r.position.x + r.size.x * (0.25 + 0.25 * (k % 3)), 0, r.position.y + r.size.y * 0.4)
		if k - 1 < houses.size():
			p = houses[k - 1]["center"]   # a house: «Тримати» on it = occupy it
		sq.issue_order("hold", W.grid.free_point(p) if Buildings.at(p) == null else p)
	if not _hold_told:
		_hold_told = true
		print("[BALANCE] t=%d hold phase: squads dig in" % int(W.mission.t))


var _hold_told := false
var _mh_t := 0.0
## «СІРА ЗОНА» as a player would fly it: the infantry stays on our line, the
## drone visits the areas from the briefing at a stand-off with the zoom on,
## and backs off (further, higher) whenever the link goes bad.
var _rc_i := -1
var _rc_t := 0.0
var _rc_d := 0.0
const RECON_ROUTE := [
	[Vector2(-62, -12), 95.0], [Vector2(-20, -48), 120.0], [Vector2(-54, -87), 135.0],
	[Vector2(4, -96), 150.0], [Vector2(62, -84), 135.0], [Vector2(46, -6), 95.0],
]


func _smart_recon(delta: float, _t: float) -> void:
	if W.ew == null or W.ew.drone_down:
		return
	_rc_t -= delta
	W.cam.zoom_t = 3.0
	if _rc_i < 0 or _rc_t <= 0.0:
		_rc_i = (_rc_i + 1) % RECON_ROUTE.size()
		_rc_t = 30.0
		_rc_d = float(RECON_ROUTE[_rc_i][1]) if plan != "frontal" else 60.0   # "frontal": low and close, as a careless player
		_rc_fly()
		print("[BALANCE] t=%d recon leg %d → %s, stand-off %.0f" % [int(W.mission.t), _rc_i, RECON_ROUTE[_rc_i][0], _rc_d])
		return
	# a bad link: further and higher, at once
	if plan != "frontal" and W.ew.link < 0.5 and _rc_d < 220.0:
		_rc_d += 25.0
		_rc_fly()


func _rc_fly() -> void:
	var p: Vector2 = RECON_ROUTE[_rc_i][0]
	W.cam.pitch_t = deg_to_rad(50.0)
	W.cam.fly_to(Vector3(p.x, 0, p.y), _rc_d)


var _ammo_t := 10.0
var _ammo_cd := {}


## Like a player: a holding squad that has used up half its magazines is
## sent to the nearest vehicle for ammunition (the "ammo" button).
func _ammo_check(delta: float, t: float) -> void:
	_ammo_t -= delta
	if _ammo_t > 0.0:
		return
	_ammo_t = 10.0
	for sq in W.mission.friendly_squads:
		if sq.mounted or sq.order != "hold" or sq.leaderless_t > 0.0 or sq.resup_call != null:
			continue
		if t < float(_ammo_cd.get(sq, -1.0)) or sq.active_count() < 3:
			continue
		var miss := 0
		var full := 0
		for m in sq.active_members():
			if m.mags_start > 0:
				miss += m.mags_start - maxi(m.mags_left, 0)
				full += m.mags_start
		# while holding: only in the lull before the counterattack (then fight)
		var hold: bool = W.mission.hold_phase
		if hold and W.mission.counter_sent > 0:
			continue
		if full == 0 or float(miss) / full < (0.2 if hold else 0.35):
			continue
		if hold:
			# not away from the position: only a vehicle right behind it
			var near := false
			for v in W.vehicles:
				if is_instance_valid(v) and v.side == 0 and v.state != "destroyed" and v.stock_rounds > 0 and v.global_position.distance_to(sq.center()) < 60.0:
					near = true
			if not near:
				continue
		_ammo_cd[sq] = t + 120.0
		if sq.order_resupply():
			print("[BALANCE] t=%d %s: ammo order (%d of %d magazines used)" % [int(t), sq.short, miss, full])


var _dodge_t := 0.0


func _dodge_recon(delta: float) -> void:
	_dodge_t -= delta
	if _dodge_t > 0.0:
		return
	_dodge_t = 6.0
	for d in get_tree().get_nodes_in_group("recon"):
		if not d.revealed:
			continue
		for sq in W.mission.friendly_squads:
			if sq.active_count() < 2 or sq.mounted or not (sq.order in ["hold", "move", "occupy"]) or sq.get_meta("dodged_t", -99.0) > W.time - 40.0:
				continue
			var c: Vector3 = sq.center()
			var n := 0
			for e in d.seen.keys():
				if is_instance_valid(e) and e is Soldier and e.squad == sq:
					n += 1
			if n < 3 or Vector2(d.global_position.x - c.x, d.global_position.z - c.z).length() > 90.0:
				continue
			sq.set_meta("dodged_t", W.time)
			var side := Vector3(randf_range(-1, 1), 0, randf_range(-0.3, 0.3)).normalized()
			sq.issue_order("hold", W.grid.free_point(c + side * randf_range(25.0, 35.0)))


func _once(key: String, at: float, t: float) -> bool:
	if t >= at and not done.has(key):
		done[key] = true
		return true
	return false


func _sq(i: int):
	var l: Array = W.mission.friendly_squads
	return l[i] if i < l.size() else null


func _frontal(t: float) -> void:
	if _once("go", 0.0, t):
		var i := 0
		# treeline: the front trench at z -29; other maps: front edge of the objective
		var r: Rect2 = W.mission.def.objective_rect
		var front := Vector3(-14, 0, -29) if W.mission.def.id == "treeline" else Vector3(r.get_center().x, 0, r.end.y)
		for sq in W.mission.friendly_squads:
			sq.issue_order("assault", front + Vector3(i * 18 - 18, 0, 0))
			i += 1
		for v in W.mission.friendly_vehicles:
			v.order_move(Vector3(front.x - 10 + i * 12, 0, front.z + 45))
			i += 1
	if _once("fpv", 30.0, t):
		_fpv(W.bunkers[0])
	_manage(t)


var stage := 0
var stage_t := 0.0


func _arrived(list: Array) -> bool:
	for sq in list:
		if sq.active_count() > 0 and not sq._all_arrived(4.0):
			return false
	return true


func _smart(t: float) -> void:
	# assault group + one rifle squad flank, the other rifle squad is the base of fire
	var flank: Array = []
	var base = null
	for sq in W.mission.friendly_squads:
		if sq.kind == "assault_group" or flank.size() == 0:
			flank.append(sq)
		elif base == null:
			base = sq
		else:
			flank.append(sq)
	stage_t += get_process_delta_time()
	match stage:
		0:
			if base:
				base.issue_order("hold", Vector3(-6, 0, 50))
			for sq in flank:
				sq.issue_order("move", Vector3(-99 + flank.find(sq) * 3, 0, 46))
			var k := 0
			for v in W.mission.friendly_vehicles:
				v.order_move(Vector3(-20 + k * 30, 0, 74))   # hull-down behind our tree line
				k += 1
			_fpv(W.bunkers[0])
			_mortar(Vector3(-78, 0, -29))
			stage = 1
			stage_t = 0.0
			print("[PLAN] t=%d stage 1" % int(t))
		1:
			if _arrived(flank) or stage_t > 120.0:
				for sq in flank:
					sq.issue_order("move", Vector3(-99 + flank.find(sq) * 3, 0, -18))   # inside the cross tree line
				stage = 2
				stage_t = 0.0
				print("[PLAN] t=%d stage 2 flank=%s" % [int(t), str(flank.map(func(q): return "%s:%d@%s" % [q.short, q.active_count(), q.center().snapped(Vector3.ONE)]))])
		2:
			if _arrived(flank) or stage_t > 120.0:
				_smoke(Vector3(-78, 0, -20))
				var k2 := 0
				for v in W.mission.friendly_vehicles:
					if v.state != "destroyed":
						v.order_move(Vector3(-40 + k2 * 40, 0, 47))   # fire support from the edge of our tree line
					k2 += 1
				_fpv(W.bunkers[2])
				_mortar(Vector3(-48, 0, -29))
				stage = 3
				stage_t = 0.0
				print("[PLAN] t=%d stage 3 flank=%s" % [int(t), str(flank.map(func(q): return "%s:%d@%s" % [q.short, q.active_count(), q.center().snapped(Vector3.ONE)]))])
		3:
			if stage_t > 8.0:
				for sq in flank:
					sq.issue_order("clear", Vector3(-74 + flank.find(sq) * 8, 0, -29))
				stage = 4
				stage_t = 0.0
				print("[PLAN] t=%d stage 4 flank=%s" % [int(t), str(flank.map(func(q): return "%s:%d@%s" % [q.short, q.active_count(), q.center().snapped(Vector3.ONE)]))])
		4:
			if (_arrived(flank) and stage_t > 20.0) or stage_t > 120.0:
				for sq in flank:
					sq.issue_order("clear", Vector3(-48 + flank.find(sq) * 10, 0, -28.5))
				# pin the centre at the same moment: smoke screen, then the base of fire rushes
				_smoke(Vector3(-16, 0, -12))
				stage = 5
				stage_t = 0.0
				print("[PLAN] t=%d stage 5 flank=%s" % [int(t), str(flank.map(func(q): return "%s:%d@%s" % [q.short, q.active_count(), q.center().snapped(Vector3.ONE)]))])
		5:
			if base and stage_t > 6.0:
				base.issue_order("assault", Vector3(-16, 0, -30))
				stage = 6
				stage_t = 0.0
	_manage(t)


## "ВИСОТА": base of fire takes the outpost from the abandoned trench, the
## flank goes up the eastern fold to the pump station and rolls up the front
## trench from its east end, vehicles stay hull-down at the tree line.
## «КВАРТАЛ»: take our blocks by the park, fire from their windows, smoke and
## mortar on the western five-storey block, clear it, then block by block.
## «КВАРТАЛ»: up the tree belt (the fields are mined and watched), clear the
## outpost and the machine-gun trench in it, then smoke the gap and clear the
## edge blocks; vehicles support from the belt's southern end.
func _smart_urban(t: float) -> void:
	# deployment "Посадка": along the belt, then the empty front row, fire
	# from its windows, then the towers
	var sqs: Array = W.mission.friendly_squads
	if _once("belt", 0.0, t):
		for i in sqs.size():
			sqs[i].issue_order("move", Vector3(-4 + i * 4, 0, 200 - i * 6))
		var k := 0
		for v in W.mission.friendly_vehicles:
			v.order_move(Vector3(24 + k * 6, 0, 212))
			v.set_face("front")
			k += 1
	if _once("outpost", 70.0, t):
		for sq in sqs:
			sq.issue_order("clear", Vector3(0, 0, 172))
	if _once("mortar1", 140.0, t):
		_mortar(Vector3(0, 0, 119))
	if _once("smoke1", 160.0, t):
		_smoke(Vector3(0, 0, 100))
	if _once("trench", 175.0, t):
		for sq in sqs:
			sq.issue_order("clear", Vector3(0, 0, 119))
	if _once("fpv", 200.0, t):
		for u in W.units:
			if u.side == 1 and u.is_active() and u.post != null and u.role in ["mg", "atgm"]:
				_fpv(u)
				break
	if _once("front_row", 290.0, t):
		# take the empty blocks of the front row
		var spots := [Vector3(-48, 0, 46), Vector3(52, 0, 42), Vector3(-130, 0, 40)]
		for i in sqs.size():
			sqs[i].issue_order("hold", spots[i % spots.size()])
		for v in W.mission.friendly_vehicles:
			v.order_move(Vector3(10, 0, 84))
	if _once("veh_sup", 420.0, t):
		for v in W.mission.friendly_vehicles:
			v.order_suppress(Vector3(-15, 0, -45))
	if _once("smoke2", 470.0, t):
		_smoke(Vector3(-2, 0, 5))
	if _once("checkpoint", 480.0, t):
		var n := 0
		for sq in sqs:
			if sq.kind == "assault_group" or n == 0:
				sq.issue_order("clear", Vector3(-2, 0, -12))
				n += 1
	if t > 560.0:
		_manage_urban(t)


## «Хутір»: through the western orchard (out of sight of the southern row),
## FPV on the bunker and mortar on the trench, the vehicles fire at the
## western house from our tree line, smoke, the western flank (trench end and
## house), then house by house.
func _smart_village(t: float) -> void:
	var sqs: Array = W.mission.friendly_squads
	# nothing moves until everybody is out of the vehicles in the tree line:
	# a carrier sent forward with the troops inside is the ATGM's first kill
	if _v_t0 < 0.0:
		for sq in sqs:
			if sq.order == "mounted" and t < 60.0:
				return
		_v_t0 = t
	var tv := t - _v_t0
	if _once("west", 0.0, tv):
		# west inside the tree line, then down the western windbreak
		for i in sqs.size():
			sqs[i].issue_order("move", Vector3(-121 + i * 2, 0, 104 - i * 2))
		# the vehicles wait on the road behind the trees
	if _once("windbreak", 35.0, tv):
		for i in sqs.size():
			sqs[i].issue_order("move", Vector3(-123 + (i % 2) * 3, 0, 52 - i * 7))
	if _once("orchard", 75.0, tv):
		for i in sqs.size():
			sqs[i].issue_order("move", Vector3(-106 + i * 5, 0, 16 - i * 4))
	if _once("fpv_atgm", 40.0, tv):
		# the briefing names the ATGM in the eastern yard: the first FPV is for it
		for u in W.units:
			if u.side == 1 and u.is_active() and u.role == "atgm":
				_fpv(u)
				break
	if _once("fpv_bunker", 95.0, tv) and W.bunkers.size() > 0:
		_fpv(W.bunkers[0])
	if _once("mortar1", 100.0, tv):
		_mortar(Vector3(-8, 0, 4))
	if _once("veh_edge", 105.0, tv):
		var atgm_alive := false
		for u in W.units:
			if u.side == 1 and u.is_active() and u.role == "atgm":
				atgm_alive = true
		if not atgm_alive:
			var k := 0
			for v in W.mission.friendly_vehicles:
				v.order_move(Vector3(-40 + k * 22, 0, 98))
				v.set_face("front")
				k += 1
	if _once("veh_sup", 120.0, tv):
		for v in W.mission.friendly_vehicles:
			v.order_suppress(Vector3(-38, 0, -10))
	if _once("smoke1", 125.0, tv):
		_smoke(Vector3(-66, 0, 2))
	if _once("flank", 135.0, tv):
		for i in sqs.size():
			if i == 0:
				sqs[i].issue_order("clear", Vector3(-24, 0, 6))      # the trench from its western end
			else:
				sqs[i].issue_order("clear", Vector3(-38, 0, -10))    # the western house
	if _once("fpv2", 200.0, tv):
		for u in W.units:
			if u.side == 1 and u.is_active() and u.role in ["atgm", "mg"]:
				_fpv(u)
				break
	if _once("centre", 300.0, tv):
		var n := 0
		for sq in sqs:
			if sq.active_count() >= 3 and n < 2:
				sq.issue_order("clear", Vector3(-13, 0, -11))
				n += 1
	if tv > 380.0:
		_manage_urban(t)


var _v_t0 := -1.0


## «Лісовий масив», deployment "Центр": up the footpath, the listening post,
## mortar on the trench line, the vehicles fire along the east firebreak, both
## halves of the trench, then the clearing's trench and the forester's house.
func _smart_forest(t: float) -> void:
	var sqs: Array = W.mission.friendly_squads
	if _once("path", 0.0, t):
		for i in sqs.size():
			sqs[i].issue_order("move", Vector3(-6 + i * 6, 0, 122 - i * 4))
		var k := 0
		for v in W.mission.friendly_vehicles:
			v.order_move(Vector3(100, 0, 96 + k * 8))
			v.set_face("front")
			k += 1
	if _once("post", 45.0, t):
		for sq in sqs:
			sq.issue_order("clear", Vector3(0, 0, 91))
	if _once("mortar1", 100.0, t):
		_mortar(Vector3(0, 0, 22))
	if _once("veh_sup", 110.0, t):
		for v in W.mission.friendly_vehicles:
			v.order_suppress(Vector3(100, 0, 44))
	if _once("line", 125.0, t):
		for i in sqs.size():
			sqs[i].issue_order("clear", Vector3(-30 if i % 2 == 0 else 30, 0, 22))
	if _once("fpv", 150.0, t):
		for u in W.units:
			if u.side == 1 and u.is_active() and u.role in ["mg", "atgm"]:
				_fpv(u)
				break
	if _once("edge", 300.0, t):
		for sq in sqs:
			sq.issue_order("clear", Vector3(0, 0, -31))
	if _once("house", 400.0, t):
		var n := 0
		for sq in sqs:
			if sq.kind == "assault_group" or n == 0:
				sq.issue_order("clear", Vector3(0, 0, -64))
				n += 1
	if t > 460.0:
		_manage_urban(t)


var _mu_t := 0.0


## After the first block: every squad goes for the nearest enemy (a house =
## clearing it), with smoke when the way is open.
func _manage_urban(_t: float) -> void:
	_mu_t -= get_process_delta_time()
	if _mu_t > 0.0:
		return
	_mu_t = 25.0
	if W.mission.hold_phase:
		_manage_hold()
		return
	for sq in W.mission.friendly_squads:
		if sq.active_count() < 2 or sq.mounted or not (sq.order in ["hold", "move", "occupy"]):
			continue
		if sq.resup_call != null or not sq.resup_men.is_empty():
			continue   # walking to the vehicle for ammunition
		var c: Vector3 = sq.center()
		var best = null
		var bd := INF
		# the objective first: the enemies inside the capture zone
		var zone: Rect2 = W.mission.def.capture_rect.grow(6.0)
		var any_in: bool = W.mission.enemies_in_zone() > 0
		for u in W.units:
			if u.side == 1 and u.is_active():
				if any_in and not zone.has_point(Vector2(u.global_position.x, u.global_position.z)):
					continue
				var d: float = u.global_position.distance_to(c)
				if d < bd:
					bd = d
					best = u
		if best == null:
			continue
		if bd > 30.0:
			_smoke(c.lerp(best.global_position, 0.5))
		sq.issue_order("assault", best.global_position)


func _smart_field(t: float) -> void:
	var flank: Array = []
	var base = null
	for sq in W.mission.friendly_squads:
		if sq.kind == "assault_group" or flank.size() == 0:
			flank.append(sq)
		elif base == null:
			base = sq
		else:
			flank.append(sq)
	stage_t += get_process_delta_time()
	match stage:
		0:
			if base:
				base.issue_order("hold", Vector3(-52, 0, 30))   # abandoned trench: base of fire
			for sq in flank:
				sq.issue_order("move", Vector3(88 + flank.find(sq) * 4, 0, 116))   # behind our tree line to the fold's mouth
			var k := 0
			for v in W.mission.friendly_vehicles:
				v.order_move(Vector3(-30 + k * 30, 0, 114))
				k += 1
			_fpv(W.bunkers[2])
			_mortar(Vector3(4, 0, 1))
			stage = 1
			stage_t = 0.0
			print("[PLAN] t=%d field stage 1" % int(t))
		1:
			if _arrived(flank) or stage_t > 120.0:
				for sq in flank:
					sq.issue_order("move", Vector3(90 + flank.find(sq) * 3, 0, 62))
				stage = 10
				stage_t = 0.0
				print("[PLAN] t=%d field stage 1b (fold)" % int(t))
		10:
			if _arrived(flank) or stage_t > 120.0:
				# leaving the fold: blind the pump-station post, then storm it
				_smoke(Vector3(70, 0, -2))
				_mortar(Vector3(70, 0, -12))
				for sq in flank:
					sq.issue_order("assault", Vector3(72 + flank.find(sq) * 5, 0, -10))
				stage = 2
				stage_t = 0.0
				print("[PLAN] t=%d field stage 2" % int(t))
		2:
			if (_arrived(flank) and stage_t > 15.0) or stage_t > 120.0:
				_smoke(Vector3(58, 0, -24))
				_mortar(Vector3(30, 0, -33))
				_fpv(W.bunkers[0])
				if base:
					# the outpost is cut off once the flank is at the pump station
					_smoke(Vector3(-6, 0, -12))
					base.issue_order("assault", Vector3(4, 0, 1))
				stage = 3
				stage_t = 0.0
				print("[PLAN] t=%d field stage 3" % int(t))
		3:
			if stage_t > 8.0:
				for sq in flank:
					sq.issue_order("clear", Vector3(44 - flank.find(sq) * 8, 0, -38))
				stage = 4
				stage_t = 0.0
		4:
			if (_arrived(flank) and stage_t > 20.0) or stage_t > 120.0:
				for sq in flank:
					sq.issue_order("clear", Vector3(-4 + flank.find(sq) * 10, 0, -34))
				_smoke(Vector3(-10, 0, -14))
				stage = 5
				stage_t = 0.0
				print("[PLAN] t=%d field stage 5" % int(t))
		5:
			if base and stage_t > 6.0:
				base.issue_order("assault", Vector3(-14, 0, -31))
				stage = 6
	_manage(t)


## Later on: every squad that is holding goes after the nearest enemy left
## in the position (trench clearing if he is in a trench).
func _manage(t: float) -> void:
	if t < 420.0:
		return
	manage_t -= get_process_delta_time()
	if manage_t > 0.0:
		return
	manage_t = 30.0
	if W.mission.hold_phase:
		_manage_hold()
		return
	for sq in W.mission.friendly_squads:
		if sq.active_count() < 2 or sq.mounted or not (sq.order in ["hold", "move", "occupy"]):
			continue
		if sq.resup_call != null or not sq.resup_men.is_empty():
			continue   # walking to the vehicle for ammunition
		var c: Vector3 = sq.center()
		var best = null
		var bd := INF
		for u in W.units:
			if u.side == 1 and u.is_active():
				var d: float = u.global_position.distance_to(c)
				if d < bd:
					bd = d
					best = u
		if best == null:
			# nobody left: occupy the position
			var r: Rect2 = W.mission.def.objective_rect
			sq.issue_order("move", W.grid.free_point(Vector3(r.get_center().x, 0, r.get_center().y)))
			continue
		var p: Vector3 = best.global_position
		# crossing open ground: smoke first if we still have it
		if not W.grid.in_channel(c, 1.5) and c.distance_to(p) > 25.0:
			_smoke(c.lerp(p, 0.6))
		sq.issue_order("clear" if W.grid.in_channel(p, 1.2) else "assault", p)


## Prints how many enemy soldiers can see points along the eastern fold of
## "ВИСОТА" (centre line, and 5 m to each side), eye height 1.0 m.
func _los_probe() -> void:
	var def = W.mission.def
	if not def.has_method("_balka_point"):
		return
	for i in 11:
		var k := float(i) / 10.0
		var bp: Vector2 = def._balka_point(k)
		var line := "[LOS] k=%.1f (%d,%d)" % [k, int(bp.x), int(bp.y)]
		for off in [-5.0, 0.0, 5.0]:
			var p: Vector3 = W.grid.ground(Vector3(bp.x + off, 0, bp.y)) + Vector3(0, 1.0, 0)
			var seen := 0
			for u in W.units:
				if u.side == 1 and u.is_active() and W.grid.visibility(u.eye_point(), p) > 0.15:
					seen += 1
			line += "  dx%+d:%d" % [int(off), seen]
		print(line)


func _fpv(target) -> void:
	if target == null or not W.is_alive_target(target):
		return
	if W.mission.use_support("fpv"):
		target.ever_seen = true
		W.combat.fpv_strike(target, Vector3(randf_range(-30, 30), 25, W.mission.def.size * 0.5 + 45))


func _mortar(p: Vector3) -> void:
	if W.mission.use_support("mortar"):
		W.combat.mortar_strike(p, 4, 11.0, 0)


func _smoke(p: Vector3) -> void:
	if W.mission.use_support("smoke"):
		W.combat.smoke_barrage(p)


func _on_end(r: Dictionary) -> void:
	print("[BALANCE] map=" + W.mission.def.id + " diff=%s plan=%s reason=%s win=%s t=%d kia=%d wia=%d evac=%d vlost=%d enemy=%d/%d pows=%d mines=%d drone=%d score=%d" % [
		Game.difficulty(), plan, r["reason"], r["success"], int(r["time"]), r["kia"], r["wia"], r["evacuated"], r["vehicles_lost"],
		int(r["enemy_dead"]) + int(r["enemy_wia"]) + int(r.get("prisoners", 0)) + int(r["enemy_escaped"]), r["enemy_total"],
		r.get("prisoners", 0), r.get("mines", 0), r.get("drones_lost", 0), r["score"]])
	print("[BALANCE] downed_by=", downs, " where(zone@minute)=", where)
	print("[BALANCE] enemy_downed_by=", edowns)
	if Prof.on:
		print("[BALANCE] prof:
" + Prof.report(maxi(Engine.get_process_frames(), 1)))
	if r["reason"] == "timeout":
		# who was still fighting when the clock ran out (a battle that never ends)
		for sq in W.mission.friendly_squads:
			for m in sq.members:
				if m.health < Soldier.H.INCAP and not m.evacuated:
					print("[BALANCE] alive %s %s pos=%s order=%s state=%s solo=%s" % [sq.short, m.rdata["short"], m.global_position.snapped(Vector3.ONE), sq.order, m.state_text() if m.has_method("state_text") else "", m.solo])
		for u in W.units:
			if u.side == 1 and u.is_active():
				print("[BALANCE] enemy %s pos=%s" % [u.role, u.global_position.snapped(Vector3.ONE)])
	for sq in W.mission.friendly_squads:
		var st: Array = []
		for m in sq.members:
			if m.is_active():
				st.append("%s mv=%s ai=%s slot_d=%d follow=%s cqbw=%.1f pos=%s" % [m.rdata["short"], m.moving, m.ai.state, int(m.global_position.distance_to(m.slot)), m.follow_ahead != null, m.cqb_wait, m.global_position.snapped(Vector3.ONE)])
		print("[END] %s order=%s active=%d %s" % [sq.short, sq.order, sq.active_count(), st])
	var left: Array = []
	for u in W.units:
		if u.side == 1 and u.is_active():
			left.append("%s@%s" % [u.rdata["short"], u.global_position.snapped(Vector3.ONE)])
	print("[END] enemies left: ", left)
	if "--cinematic" in OS.get_cmdline_user_args():
		return   # the director shows the results screen, then quits
	get_tree().quit()
