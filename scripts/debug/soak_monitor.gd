class_name SoakMonitor
extends Node
## Watches a test battle for problems (`-- --soak [--soak-dir=<dir>]`, together
## with --balance=… or --autotest; tools/soak.py runs it for every map and
## language). Prints machine-readable lines that tools/soak.py parses:
##   [SOAK-EVENT] {json}  — a problem as it happens (stuck soldier / vehicle,
##                          battle that does not end, too many units)
##   [SOAK] {json}        — the summary when the battle ends
## In a windowed run the first problem of each kind is also saved as a picture
## into --soak-dir.

const SAMPLE_T := 2.0          # how often positions are sampled, s of game time
const STUCK_T := 16.0          # wants to move but has not moved for this long
const STUCK_D := 0.8           # "has not moved": less than this, m
const OVERTIME := 120.0        # the battle runs this much past its time limit

var shot_dir := ""
var _t := 0.0
var _hist := {}                # unit -> [[time, pos], ...]
var _stuck := {}               # unit -> true while it is stuck (one event per episode)
var _events: Array = []
var _kinds_shot := {}
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _fps: PackedFloat32Array = PackedFloat32Array()
var _mem0 := 0.0
var _nodes0 := 0
var _mem_max := 0.0
var _nodes_max := 0
var _units0 := {}
var _units_max := {0: 0, 1: 0}
var _reg0 := -1                # W.units size when the combat phase starts
var _reg_reported := false
var _episodes := {}            # unit -> how many times it got stuck
var _started := false
var _over_reported := false
var _nav_fail := 0
var _done := false
var _crowd := [0, 0]          # [men standing within 1.2 m of a comrade, men sampled]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--soak-dir="):
			shot_dir = a.substr(11)
	Events.mission_ended.connect(_on_end)   # before the bot, which quits on the same signal
	Events.message.connect(_on_message)


func _on_message(text: String, _kind: String) -> void:
	# a vehicle / squad that could not find a route reports it on the radio
	for key in ["немає маршруту", "маршрут недоступний — наказ не виконано", "не можу проїхати — зупинилась, потрібен новий наказ"]:
		if text.contains(Loc.t(key)):
			_nav_fail += 1
			_event("nav_fail", {"text": text})
			return


func _process(delta: float) -> void:
	if not W.running() or W.mission == null:
		return
	if get_tree().paused:
		return
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	_frame_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_fps.append(Performance.get_monitor(Performance.TIME_FPS))
	if not _started and W.time > 10.0:
		_started = true
		_check_trapped()
		_check_buildings()
		# the language really is the one asked for (a wrong fallback locale once
		# showed English to Ukrainian players)
		var probe := Loc.t("ВИХІД")
		if (Loc.is_uk() and probe != "ВИХІД") or (not Loc.is_uk() and probe == "ВИХІД"):
			_event("wrong_language", {"lang": Loc.lang(), "probe": probe})
		_mem0 = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		_nodes0 = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		_units0 = _count_units()
	_t += real_dt * Engine.time_scale
	if _t < SAMPLE_T:
		return
	_t = 0.0
	_mem_max = maxf(_mem_max, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	_nodes_max = maxi(_nodes_max, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	var uc := _count_units()
	for side in [0, 1]:
		_units_max[side] = maxi(_units_max[side], int(uc[side]))
	# units multiplying / leaking: the register grows well past its size at
	# the start of the fight (reinforcement waves are counted in later stages)
	if _reg0 < 0 and W.mission.phase == MissionManager.Phase.COMBAT:
		_reg0 = W.units.size()
	elif _reg0 >= 0 and not _reg_reported and W.units.size() > _reg0 + 16:
		_reg_reported = true
		_event("unit_count", {"registered": W.units.size(), "at_combat_start": _reg0})
	_check_stuck()
	_sample_crowding()
	if not _over_reported and W.time > W.mission.def.time_limit + OVERTIME:
		_over_reported = true
		_event("no_end", {"t": int(W.time), "limit": int(W.mission.def.time_limit)})
		_finish("no_end")
		get_tree().quit()


## Every enemy soldier must be able to walk out of his position (to the
## retreat point and to the objective): a man walled in by the map — inside a
## house without a reachable door, say — never joins the fight.
func _check_trapped() -> void:
	var def: MapDef = W.mission.def
	var goals: Array = [def.enemy_retreat, Vector3(def.objective_rect.get_center().x, 0, def.objective_rect.get_center().y), def.rally_point]
	for u in W.units:
		if u.side != 1 or not u.is_active() or u.bunker != null:
			continue
		var reach := 0
		for g in goals:
			var path: PackedVector3Array = W.grid.find_path_inf(u.global_position, g, false)
			if path.size() > 0 and (path[path.size() - 1] as Vector3).distance_to(W.grid.ground(g)) < 8.0:
				reach += 1
		if reach == 0:
			var d := _describe(u)
			d["building"] = Buildings.at(u.global_position) != null
			_event("trapped", d)


## Every building with doors must be walkable from inside to outside.
func _check_buildings() -> void:
	var sealed: Array = []
	var total := 0
	for b in W.map.buildings:
		if b["doors"].is_empty() or b["interior"].is_empty():
			continue
		total += 1
		var a: Vector3 = b["interior"][b["interior"].size() / 2]
		var out: Vector3 = b["doors"][0]["out"]
		var path: PackedVector3Array = W.grid.find_path_inf(a, out, false)
		if path.is_empty() or (path[path.size() - 1] as Vector3).distance_to(out) > 3.0:
			sealed.append({"id": b["id"], "kind": b["kind"], "center": [snappedf(b["center"].x, 0.1), snappedf(b["center"].z, 0.1)],
				"path_end": [snappedf(path[path.size() - 1].x, 0.1), snappedf(path[path.size() - 1].z, 0.1)] if not path.is_empty() else []})
	if not sealed.is_empty():
		_event("sealed_buildings", {"count": sealed.size(), "of": total, "list": sealed.slice(0, 6)})


## Bunching: our men standing still in the open (not in a trench, building,
## vehicle) with a comrade closer than 1.2 m.
func _sample_crowding() -> void:
	for u in W.units:
		if u.side != 0 or not u.is_active() or u.moving or u.post != null or u.in_trench() or u.squad == null:
			continue
		_crowd[1] += 1
		for m in u.squad.members:
			if m != u and m.is_active() and m.global_position.distance_to(u.global_position) < 1.2:
				_crowd[0] += 1
				break


func _count_units() -> Dictionary:
	var c := {0: 0, 1: 0}
	for u in W.units:
		if u.is_active():
			c[u.side] = int(c[u.side]) + 1
	return c


func _check_stuck() -> void:
	var now: float = W.time
	for u in W.units:
		if not is_instance_valid(u) or not u.is_active():
			_hist.erase(u)
			_stuck.erase(u)
			continue
		# a panicking or pinned man who refuses to move is behaviour, not a bug
		var wants: bool = u.moving and u.global_position.distance_to(u.slot) > 2.0 and u.supp_level < 3
		# a man in a file keeping his interval behind a slow but moving head of
		# the column is waiting, not stuck (the head itself is still checked)
		if wants and _column_head_moving(u):
			wants = false
		_track(u, now, wants, "soldier")
	for v in W.vehicles:
		if not is_instance_valid(v) or v.state == "destroyed" or v.state == "immobile" or v.offmap:
			_hist.erase(v)
			_stuck.erase(v)
			continue
		_track(v, now, v.moving and v.path.size() > 0, "vehicle")


func _column_head_moving(u) -> bool:
	var h = u.follow_ahead
	var guard := 0
	while h != null and is_instance_valid(h) and h.follow_ahead != null and guard < 12:
		h = h.follow_ahead
		guard += 1
	if h == null or not is_instance_valid(h) or h == u:
		return false
	return h.moving or h.cqb_wait > 0.0 or h.action != ""


func _track(u, now: float, wants: bool, what: String) -> void:
	var h: Array = _hist.get_or_add(u, [])
	if not wants:
		h.clear()
		_stuck.erase(u)
		return
	h.append([now, u.global_position])
	while h.size() > 2 and now - float(h[1][0]) >= STUCK_T:
		h.pop_front()
	if now - float(h[0][0]) < STUCK_T:
		return
	var moved: float = (h[0][1] as Vector3).distance_to(u.global_position)
	if moved < STUCK_D:
		if not _stuck.has(u):
			_stuck[u] = true
			_episodes[u] = int(_episodes.get(u, 0)) + 1
			if int(_episodes[u]) == 1:   # one report per unit, the summary counts the episodes
				_event("stuck_" + what, _describe(u))
	else:
		_stuck.erase(u)


func _describe(u) -> Dictionary:
	var p: Vector3 = u.global_position
	var d := {"pos": [snappedf(p.x, 0.1), snappedf(p.z, 0.1)], "t": int(W.time)}
	if u is Soldier:
		d["name"] = "%s %s (%s)" % [u.rdata["short"], u.uname, u.squad.short if u.squad else "-"]
		d["side"] = u.side
		d["order"] = String(u.squad.order) if u.squad else ""
		d["ai"] = String(u.ai.state)
		d["slot_d"] = snappedf(p.distance_to(u.slot), 0.1)
		d["path_left"] = u.path.size() - u.path_i
		d["cqb_wait"] = snappedf(u.cqb_wait, 0.1)
		d["follow"] = u.follow_ahead != null
		if u.follow_ahead != null and is_instance_valid(u.follow_ahead):
			var fa = u.follow_ahead
			d["ahead"] = {"d": snappedf(p.distance_to(fa.global_position), 0.1), "moving": fa.moving, "cqb": snappedf(fa.cqb_wait, 0.1),
				"act": fa.action, "ai": String(fa.ai.state), "path": "%d/%d" % [fa.path_i, fa.path.size()], "prog_t": snappedf(fa._prog_t, 0.1),
				"follow": fa.follow_ahead != null, "supp": fa.supp_level}
		d["escort"] = u.escort != null
		d["trench"] = u.in_trench()
		d["post"] = u.post != null
		var i: int = W.grid.cidx(p.x, p.z)
		d["inf_weight"] = snappedf(W.grid.inf_weight[i], 0.1)
		d["inf_solid"] = W.grid.inf_solid[i]
	else:
		d["name"] = u.vname
		d["side"] = u.side
		d["state"] = u.state
		d["path_left"] = u.path.size()
	return d


func _event(kind: String, data: Dictionary) -> void:
	data["kind"] = kind
	data["map"] = W.mission.def.id if W.mission and W.mission.def else ""
	_events.append(data)
	print("[SOAK-EVENT] ", JSON.stringify(data))
	if shot_dir != "" and DisplayServer.get_name() != "headless" and not _kinds_shot.has(kind) and data.has("pos"):
		_kinds_shot[kind] = true
		_shot_at(kind, data)


## A picture of the place where the problem is (windowed runs only).
func _shot_at(kind: String, data: Dictionary) -> void:
	var pos: Array = data["pos"]
	W.cam.teleport_view(Vector3(float(pos[0]), 0, float(pos[1])), 40.0, 35.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var p := shot_dir.path_join("%s_%s_%d.png" % [data["map"], kind, int(data.get("t", 0))])
	img.save_png(p)
	print("[SOAK-SHOT] ", p)


func _stats(a: PackedFloat32Array) -> Dictionary:
	if a.is_empty():
		return {"avg": 0, "p99": 0, "max": 0, "min": 0}
	var s := a.duplicate()
	s.sort()
	var sum := 0.0
	for x in s:
		sum += x
	return {"avg": snappedf(sum / s.size(), 0.01), "p99": snappedf(s[int(s.size() * 0.99)], 0.01),
		"max": snappedf(s[s.size() - 1], 0.01), "min": snappedf(s[0], 0.01), "p1": snappedf(s[int(s.size() * 0.01)], 0.01)}


## Rounds fired per man by weapon (to size the ammunition loads).
func _rounds() -> Dictionary:
	var by := {}
	for u in W.units:
		if not (u is Soldier) or u.weapon.is_empty():
			continue
		var k := "%d:%s" % [u.side, String(u.rdata.get("weapon", "?"))]
		var a: Array = by.get_or_add(k, [])
		a.append(u.shots)
	var out := {}
	for k in by.keys():
		var a: Array = by[k]
		a.sort()
		var sum := 0
		for x in a:
			sum += int(x)
		out[k] = {"n": a.size(), "avg": sum / maxi(a.size(), 1), "p90": a[int(a.size() * 0.9)], "max": a[a.size() - 1]}
	return out


func _stuck_list() -> Array:
	var out: Array = []
	for u in _episodes.keys():
		if is_instance_valid(u):
			out.append("%s ×%d" % [(u.uname + " " + String(u.rdata["short"])) if u is Soldier else u.vname, _episodes[u]])
	return out


func _on_end(_r: Dictionary) -> void:
	_finish(String(_r.get("reason", "")))


func _finish(reason: String) -> void:
	if _done:
		return
	_done = true
	var kinds := {}
	for e in _events:
		kinds[e["kind"]] = int(kinds.get(e["kind"], 0)) + 1
	var sum := {
		"map": W.mission.def.id, "lang": Loc.lang(), "reason": reason, "t": int(W.time),
		"frame_ms": _stats(_frame_ms), "fps": _stats(_fps),
		"mem_mb_start": snappedf(_mem0, 0.1), "mem_mb_end": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"mem_mb_max": snappedf(_mem_max, 0.1), "nodes_start": _nodes0, "nodes_end": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"nodes_max": _nodes_max, "units_start": _units0, "units_max": _units_max, "events": kinds, "nav_fail": _nav_fail,
		"stuck_units": _stuck_list(), "rounds": _rounds(), "enemy": W.enemy_ai.stats if W.enemy_ai else {}, "drags": _drags(), "crowded_pct": snappedf(100.0 * _crowd[0] / maxf(_crowd[1], 1), 0.1),
		"headless": DisplayServer.get_name() == "headless",
	}
	print("[SOAK] ", JSON.stringify(sum))


## Casualties our squads dragged to cover (D2).
func _drags() -> int:
	var n := 0
	for sq in W.mission.friendly_squads:
		n += int(sq.drag_done)
	return n
