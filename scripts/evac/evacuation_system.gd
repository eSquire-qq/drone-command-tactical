class_name EvacuationSystem
extends Node
## Medical evacuation: marking casualties, dispatching medevac vehicles,
## medics carrying the wounded, loading, return trips, losses en route.

const TURNAROUND := 25.0
const PICKUP_RADIUS := 45.0

var total = 0
var runs: Array = []          # {v, phase, medics, loaded, carry, t, ready_t}
var queue: Array = []
var evacuated: Array = []
var lost_onboard = 0
var crew_squad: Squad
var _warn_t = -99.0
var _medic_n = 0


func setup(count: int) -> void:
	total = count
	crew_squad = Squad.new()
	crew_squad.side = 0
	crew_squad.sname = Loc.t("Евакуаційна група")
	crew_squad.short = Loc.t("ЕВАК")
	crew_squad.kind = "medevac"
	crew_squad.rally = W.mission.def.medevac_entry
	add_child(crew_squad)
	Events.vehicle_destroyed.connect(_on_vehicle_destroyed)


func available() -> int:
	var used = 0
	for r in runs:
		if r["phase"] != "base" or W.time < float(r["ready_t"]):
			used += 1
	return total - used


func is_valid_patient(u) -> bool:
	return u is Soldier and u.side == 0 and not u.evacuated and not u.on_board and u.vehicle == null \
		and (u.health == Soldier.H.WOUNDED or u.health == Soldier.H.INCAP) and u.role != "crew_medic"


func request(u) -> bool:
	if not is_valid_patient(u):
		return false
	if not u.evac_marked:
		u.evac_marked = true
		queue.append(u)
		Events.msg(Loc.t("Позначено для евакуації: %s") % u.display_name(), "info")
		if W.blog:
			W.blog.evac_requested(u)
	_try_dispatch()
	return true


func _try_dispatch() -> void:
	_clean_queue()
	if queue.is_empty():
		return
	for r in runs:
		if r["phase"] == "inbound" or r["phase"] == "loading":
			return
	var run = null
	for r in runs:
		if r["phase"] == "base" and W.time >= float(r["ready_t"]):
			run = r
			break
	if run == null:
		if runs.size() >= total:
			if W.time - _warn_t > 20.0:
				_warn_t = W.time
				if total == 0:
					Events.msg(Loc.t("Евакуаційний транспорт не залучено в цій місії."), "warn")
				else:
					Events.msg(Loc.t("Немає вільної евакуаційної машини — очікуйте повернення."), "warn")
			return
		run = _new_run()
	_dispatch(run)


func _new_run() -> Dictionary:
	var v = Vehicle.new()
	W.mission.add_child(v)
	v.setup("medevac", 0, Loc.t("Евак. M113 «%d»") % (runs.size() + 1))
	v.offmap = true
	v.visible = false
	v.global_position = W.mission.def.medevac_entry + Vector3(0, -30, 60)
	W.vehicles.append(v)
	var r = {"v": v, "phase": "base", "medics": [], "loaded": [], "carry": null, "t": 0.0, "ready_t": 0.0}
	runs.append(r)
	return r


func _ensure_medics(r: Dictionary) -> void:
	var alive: Array = []
	for m in r["medics"]:
		if is_instance_valid(m) and m.health < Soldier.H.INCAP and not m.evacuated:
			alive.append(m)
	while alive.size() < 2:
		var m = Soldier.new()
		W.mission.add_child(m)
		_medic_n += 1
		m.setup(0, "crew_medic", crew_squad, Db.SURNAMES[(_medic_n * 7) % Db.SURNAMES.size()])
		W.units.append(m)
		crew_squad.members.append(m)
		alive.append(m)
	r["medics"] = alive


func _dispatch(r: Dictionary) -> void:
	var v: Vehicle = r["v"]
	var entry: Vector3 = W.mission.def.medevac_entry
	v.global_position = W.grid.ground(entry)
	v.set_yaw(PI * 0.0)
	v.offmap = false
	v.visible = true
	v.state = "ok" if v.hp > v.max_hp * 0.5 else "damaged"
	_ensure_medics(r)
	for m in r["medics"]:
		m.global_position = v.global_position
		v.board(m)
	r["phase"] = "inbound"
	r["loaded"] = []
	r["carry"] = null
	r["t"] = 0.0
	var first: Soldier = queue[0]
	var stage = _stage_point(first.global_position)
	v.order_move(stage)
	v.order_label = Loc.t("евакуація")
	v.radio("evac", Loc.t("вирушила до пораненого (%s)") % (first.squad.short if first.squad else "—"), "info")
	W.sfx.ui("radio")


func _stage_point(p: Vector3) -> Vector3:
	var entry: Vector3 = W.mission.def.medevac_entry
	var dir = (entry - p)
	dir.y = 0.0
	dir = dir.normalized()
	var s = p + dir * 7.0
	return W.grid.free_point(W.grid.clamp_in(s, 4.0), true)


func _clean_queue() -> void:
	var i = queue.size() - 1
	while i >= 0:
		var u = queue[i]
		if not is_instance_valid(u) or u.health == Soldier.H.DEAD or u.evacuated or u.on_board or u.health == Soldier.H.HEALTHY:
			if is_instance_valid(u):
				u.evac_marked = false
				u.evac_walk = false
			queue.remove_at(i)
		i -= 1


# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("evac", t0)


func _process_body(delta: float) -> void:
	if not W.running():
		return
	_clean_queue()
	for r in runs:
		match r["phase"]:
			"inbound":
				_inbound(r)
			"loading":
				_loading(r, delta)
			"outbound":
				_outbound(r)
	if not queue.is_empty():
		_try_dispatch()


func _inbound(r: Dictionary) -> void:
	var v: Vehicle = r["v"]
	if v.moving:
		return
	r["phase"] = "loading"
	r["t"] = 0.0
	v.order_label = Loc.t("завантаження")
	v.dismount()


func _patients_near(v: Vehicle) -> Array:
	var out: Array = []
	for u in W.units:
		if not is_valid_patient(u):
			continue
		var d: float = u.global_position.distance_to(v.global_position)
		if d > PICKUP_RADIUS:
			continue
		if u.evac_marked or (u.health == Soldier.H.INCAP and d < 30.0):
			out.append(u)
	out.sort_custom(func(a, b): return a.global_position.distance_to(v.global_position) < b.global_position.distance_to(v.global_position))
	return out


func _loading(r: Dictionary, delta: float) -> void:
	var v: Vehicle = r["v"]
	r["t"] += delta
	if not v.dismount_queue.is_empty():
		return
	var rear = v.rear_point()
	var medics: Array = []
	for m in r["medics"]:
		if is_instance_valid(m) and m.is_active():
			medics.append(m)
	var cap = v.capacity()
	var loaded: Array = r["loaded"]
	var pats = _patients_near(v)
	# walking wounded go to the vehicle by themselves
	for u in pats:
		if u.health == Soldier.H.WOUNDED and loaded.size() < cap:
			u.evac_walk = true
			if u.global_position.distance_to(rear) < 2.8:
				_load(r, u)
			elif not u.moving:
				u.move_to(rear, true)
	# carrying
	var c = r["carry"]
	if c != null and (not is_instance_valid(c) or c.health == Soldier.H.DEAD or medics.is_empty()):
		if is_instance_valid(c):
			c.carried = false
		r["carry"] = null
		c = null
	if c == null and not medics.is_empty() and loaded.size() < cap:
		for u in pats:
			if u.health == Soldier.H.INCAP and not u.carried:
				r["carry"] = u
				c = u
				for m in medics:
					m.move_to(u.global_position + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8)), true)
				break
	if c != null:
		if not c.carried:
			var near = 0
			for m in medics:
				if m.global_position.distance_to(c.global_position) < 2.2:
					near += 1
				elif not m.moving:
					m.move_to(c.global_position, true)
			if near >= medics.size() and near > 0:
				c.carried = true
				for m in medics:
					m.move_to(rear, false)
		else:
			var mid = Vector3.ZERO
			for m in medics:
				mid += m.global_position
			mid /= medics.size()
			c.global_position = mid + Vector3(0, 0.75, 0)
			c.yaw = medics[0].yaw
			c.rotation.y = c.yaw
			if mid.distance_to(rear) < 2.8:
				c.carried = false
				_load(r, c)
				r["carry"] = null
			else:
				for m in medics:
					if not m.moving:
						m.move_to(rear, false)
	# done?
	var remaining = 0
	for u in pats:
		if not loaded.has(u):
			remaining += 1
	var done = loaded.size() >= cap or (remaining == 0 and r["carry"] == null) or r["t"] > 100.0 or medics.is_empty()
	if done:
		var all_in = true
		for m in medics:
			if m.global_position.distance_to(rear) < 2.8:
				v.board(m)
			else:
				all_in = false
				if not m.moving:
					m.move_to(rear, true)
		if all_in or r["t"] > 130.0:
			for u in pats:
				u.evac_walk = false
			r["phase"] = "outbound"
			v.order_label = Loc.t("відхід")
			v.order_move(W.mission.def.medevac_entry)
			v.radio("evac", Loc.t("на борту %d поранених, відходимо.") % loaded.size(), "info")


func _load(r: Dictionary, u: Soldier) -> void:
	var loaded: Array = r["loaded"]
	if loaded.has(u):
		return
	loaded.append(u)
	u.on_board = true
	u.carried = false
	u.evac_walk = false
	u.stop()
	queue.erase(u)


func _outbound(r: Dictionary) -> void:
	var v: Vehicle = r["v"]
	if v.moving:
		return
	var loaded: Array = r["loaded"]
	for u in loaded:
		u.evacuated = true
		u.on_board = false
		evacuated.append(u)
	if loaded.size() > 0:
		Events.msg(Loc.t("Евакуйовано %d поранених. Машина повернеться за ~%d с.") % [loaded.size(), int(TURNAROUND)], "good")
		if W.blog:
			W.blog.evacuated(loaded.size(), v.global_position)
	r["loaded"] = []
	r["phase"] = "base"
	r["ready_t"] = W.time + TURNAROUND
	v.offmap = true
	v.visible = false
	v.selected = false
	for m in r["medics"]:
		if is_instance_valid(m):
			m.global_position = v.global_position


func _on_vehicle_destroyed(v) -> void:
	for r in runs:
		if r["v"] != v:
			continue
		for u in r["loaded"]:
			u.on_board = false
			u.global_position = W.grid.free_point(v.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
			if randf() < 0.5:
				W.damage.set_health(u, Soldier.H.DEAD, null, "vehicle")
				lost_onboard += 1
			else:
				u.evac_marked = false
		if r["carry"] != null and is_instance_valid(r["carry"]):
			r["carry"].carried = false
		r["loaded"] = []
		r["phase"] = "destroyed"
		Events.msg(Loc.t("Евакуаційну машину втрачено разом з пораненими на борту!"), "alert")
		if W.blog:
			W.blog.add("loss", Loc.t("Евакуаційну машину втрачено з пораненими"), null)
