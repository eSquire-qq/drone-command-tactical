class_name Vehicle
extends Node3D
## VehicleController: path driving with terrain alignment, passengers,
## dismount/board, turret AI with weapons, damage states.

var vtype = "bmp2"
var data: Dictionary = {}
var side = 0
var vname = ""
var hp = 300.0
var max_hp = 300.0
var state = "ok"   # ok, damaged, immobile, destroyed
var passengers: Array = []
var squad = null
var is_medevac = false
var model: VehicleModel
var path = PackedVector3Array()
var path_i = 0
var moving = false
var speed = 0.0
var yaw = 0.0
var pitch = 0.0
var roll = 0.0
var weapons: Array = []
var target = null
var area_target = null      # suppressive fire at a last known enemy position
var think_t = 0.0
var selected = false
var auto_dismount = false
var revealed := 0.0          # enemy vehicles: seen by our side recently (fog of war)
var ever_seen := false
var dismount_queue: Array = []
var dismount_t = 0.0
var flash_t = 0.0
var offmap = false
var arrive_cb: Callable
var turret_yaw = 0.0
var ring: MeshInstance3D
var engine: AudioStreamPlayer3D
var burn_node: Node3D
var order_label = "очікування"
var last_hit_t = -99.0
var smoke_charges = 1
var face_mode := ""           # "" free / front / side / rear: aspect held to the enemy when stopped
var assault_mode := false     # vehicle assault: slow, fires on the move, no pull-back
var sup_point = null          # suppression order: fire at this point until sup_until
var sup_until := -1.0
var last_hit_dir := Vector3.ZERO
const FACE_NAMES_UK := {"": "вільно", "front": "лобом", "side": "бортом", "rear": "кормою"}
static var FACE_NAMES = FACE_NAMES_UK   # the current language (Loc.localize_all)


## Called when an ATGM is launched at us: chance the crew pops smoke in time.
func on_missile_warning() -> void:
	if smoke_charges <= 0 or state == "destroyed" or randf() > 0.35:
		return
	smoke_charges -= 1
	W.combat.deploy_smoke(global_position + forward() * 5.0, 8.0, 30.0)
	if side == 0:
		radio("vehicle", Loc.t("поставлено димову завісу!"), "info")


func setup(p_type: String, p_side: int, p_name: String) -> void:
	vtype = p_type
	side = p_side
	vname = p_name
	data = Db.VEHICLES[vtype]
	mobility = String(data.get("mobility", "tracked"))
	max_hp = float(data["hp"])
	hp = max_hp
	is_medevac = vtype == "medevac"
	model = VehicleModel.new()
	add_child(model)
	model.build(vtype, side)
	for wid in data["weapons"]:
		var w: Dictionary = Db.WEAPONS[wid]
		weapons.append({"w": w, "cd": randf() * 1.5, "burst": 0, "mag": int(w["mag"]), "reload": 0.0})
	ring = MeshInstance3D.new()
	ring.mesh = MF.torus(3.6, 3.9, 28, 3)
	ring.material_override = MF.glow(Color(0.3, 0.75, 1.0), 1.5)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.15
	ring.visible = false
	add_child(ring)
	engine = W.sfx.make_loop("engine", self, -6.0)


func capacity() -> int:
	return int(data["cap"])


func aim_point() -> Vector3:
	return global_position + Vector3(0, 1.3, 0)


func signature() -> float:
	return 3.0 * (1.4 if moving else 1.0) * (1.5 if flash_t > 0.0 else 1.0)


func cover_value() -> float:
	return 0.0


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func rear_point() -> Vector3:
	return W.grid.ground(global_position - forward() * (model.rear_z + 1.0))


func set_yaw(y: float) -> void:
	yaw = y
	rotation.y = y


# ------------------------------------------------------------------ orders
func order_move(p: Vector3, cb: Callable = Callable()) -> void:
	if state == "destroyed":
		return
	assault_mode = false
	sup_until = -1.0
	if state == "immobile":
		_report(Loc.t("знерухомлена — рух неможливий"))
		return
	move_goal = p
	repaths = 0
	path = W.grid.find_path(global_position, p, true, mobility)
	path_i = 0
	moving = path.size() > 0
	arrive_cb = cb
	order_label = Loc.t("рух")
	_prog_pos = global_position
	_prog_t = 0.0
	if path.is_empty():
		order_label = Loc.t("немає маршруту")
		_report(Loc.t("маршрут недоступний — наказ не виконано"))
	elif W.grid.last_partial and path[path.size() - 1].distance_to(p) > 10.0:
		order_label = Loc.t("обхід / найближча точка")
		_report(Loc.t("прямого маршруту немає (окопи / вирви / перешкоди) — під'їжджаю якнайближче"))


## Vehicle assault: forward at reduced speed, guns firing on the move, no
## backing off after the first hit.
func order_assault(p: Vector3) -> void:
	order_move(p)
	if moving:
		assault_mode = true
		order_label = Loc.t("штурм")
		if side == 0:
			radio("order", Loc.t("висуваюсь у штурм, веду вогонь з ходу."), "info")


## Suppression: fire at a point (where the enemy is or may be) for a while.
func order_suppress(p: Vector3) -> void:
	sup_point = W.grid.ground(p) + Vector3(0, 1.0, 0)
	sup_until = W.time + AIConfig.SUPPRESS_T
	order_label = "подавлення"
	if side == 0:
		radio("order", Loc.t("веду вогонь на подавлення."), "info")


func set_face(m: String) -> void:
	face_mode = m
	if side == 0 and m != "":
		radio("order", Loc.t("тримаю %s до противника.") % FACE_NAMES[m], "info")


## Where the threat is: the target, the suppression point, the last known
## enemy, or where the last hit came from.
func threat_point():
	if target != null and W.is_alive_target(target):
		return target.global_position
	if sup_until > W.time and sup_point != null:
		return sup_point
	if area_target != null:
		return area_target
	if squad != null:
		var t = squad.nearest_threat(global_position)
		if t != null:
			return t
	if last_hit_dir != Vector3.ZERO and W.time - last_hit_t < 60.0:
		return global_position + last_hit_dir * 50.0
	return null


func _hold_aspect(delta: float) -> void:
	if face_mode == "" or moving or state == "immobile" or not dismount_queue.is_empty():
		return
	var tp = threat_point()
	if tp == null:
		return
	var d: Vector3 = (tp as Vector3) - global_position
	if Vector2(d.x, d.z).length() < 3.0:
		return
	var to_threat := atan2(-d.x, -d.z)
	var want := to_threat
	match face_mode:
		"rear":
			want = to_threat + PI
		"side":
			var a := to_threat + PI * 0.5
			var b := to_threat - PI * 0.5
			want = a if absf(angle_difference(yaw, a)) < absf(angle_difference(yaw, b)) else b
	yaw = rotate_toward(yaw, want, AIConfig.VEH_FACE_RATE * delta)


## Rate-limited radio report from the crew.
func radio(type: String, text: String, kind: String = "info") -> void:
	if side != 0:
		return
	if W.radio:
		W.radio.report(self, type, text, kind)
	else:
		Events.msg("%s: %s" % [vname, text], kind)


func _report(txt: String) -> void:
	if side != 0 or W.time - _report_t < 6.0:
		return
	_report_t = W.time
	radio("vehicle", txt, "warn")


func stop() -> void:
	moving = false
	path = PackedVector3Array()


func board(m) -> void:
	if passengers.has(m) or passengers.size() >= capacity():
		return
	passengers.append(m)
	m.vehicle = self
	m.stop()
	m.target = null
	m.global_position = global_position


func dismount() -> void:
	if passengers.is_empty() or state == "destroyed":
		return
	stop()
	dismount_queue = passengers.duplicate()
	dismount_t = 0.6
	order_label = Loc.t("висадка")


# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("vehicle", t0)


func _process_body(delta: float) -> void:
	if not W.running():
		return
	if side == 1:
		# fog of war: an enemy vehicle shows while our side has it in sight
		# (and a little after), like an enemy soldier
		revealed -= delta
		visible = state == "destroyed" and ever_seen or (ever_seen and revealed > -20.0)
	if state == "destroyed" or offmap:
		return   # not in the area yet (waiting in the column) / back at base
	_hold_aspect(delta)
	_drive(delta)
	_watchdog(delta)
	under_fire_t -= delta
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.5
		_think()
	_update_weapons(delta)
	_update_dismount(delta)
	model.animate(delta, speed)
	flash_t -= delta
	ring.visible = selected
	if engine:
		engine.pitch_scale = 0.8 + speed * 0.06
		engine.volume_db = -10.0 + speed * 0.8


var mobility := "tracked"
var move_goal := Vector3.ZERO
var repaths := 0
var _prog_pos := Vector3.ZERO
var _prog_t := 0.0
var _report_t := -99.0
var under_fire_t := 0.0
var _pullback_t := -99.0


## No progress for a while: try another route once, then stop and report —
## never keep pushing into an obstacle.
func _watchdog(delta: float) -> void:
	if not moving:
		_prog_t = 0.0
		_prog_pos = global_position
		return
	_prog_t += delta
	if _prog_t < 6.0:
		return
	var moved := global_position.distance_to(_prog_pos)
	_prog_t = 0.0
	_prog_pos = global_position
	if moved > 1.5:
		return
	if repaths < 1:
		repaths += 1
		var goal := move_goal
		var cb := arrive_cb
		order_move(goal, cb)
		repaths = 1
		_report(Loc.t("застрягла — шукаю інший маршрут"))
	else:
		stop()
		order_label = Loc.t("застрягла")
		_report(Loc.t("не можу проїхати — зупинилась, потрібен новий наказ"))


func _drive(delta: float) -> void:
	if not moving or state == "immobile" or not dismount_queue.is_empty():
		speed = move_toward(speed, 0.0, delta * 6.0)
		if speed > 0.05:
			global_position += forward() * speed * delta
		_apply_ground(delta)
		return
	if path_i >= path.size():
		_arrive()
		return
	var tgt: Vector3 = path[path_i]
	var to = Vector2(tgt.x - global_position.x, tgt.z - global_position.z)
	var L = to.length()
	var last = path_i == path.size() - 1
	if L < (1.2 if last else 3.0):
		path_i += 1
		if path_i >= path.size():
			_arrive()
		return
	var want = atan2(-to.x, -to.y)
	var diff = angle_difference(yaw, want)
	yaw += clampf(diff, -1.0 * delta, 1.0 * delta)
	var maxs: float = float(data["speed"]) * (0.5 if state == "damaged" else 1.0)
	if assault_mode:
		maxs *= AIConfig.VEH_ASSAULT_SPEED
	if _escorted():
		maxs = minf(maxs, AIConfig.VEH_ESCORT_SPEED)
	if W.grid.veh_weight[W.grid.cidx(global_position.x, global_position.z)] > 0.6:
		maxs *= float(Game.wx("veh"))   # off-road: mud in the rain
	var ts = maxs * clampf(1.0 - absf(diff) / 1.3, 0.12, 1.0)
	if last:
		ts = minf(ts, L * 0.7 + 0.6)
	var w = W.grid.veh_weight[W.grid.cidx(global_position.x, global_position.z)]
	if w > 1.5:
		ts *= float(Db.MOBILITY[mobility]["rough"])
	for v in W.vehicles:
		if v == self or v.state == "destroyed" or v.offmap:
			continue
		var d: Vector3 = v.global_position - global_position
		d.y = 0.0
		if d.length() < 8.0 and d.normalized().dot(forward()) > 0.6:
			ts *= 0.25
	speed = move_toward(speed, ts, delta * 3.0)
	global_position += forward() * speed * delta
	_apply_ground(delta)
	if side == 0 and W.mines and speed > 0.3:
		W.mines.check_vehicle(self)


func _area_weapons(delta: float) -> void:
	var d: Vector3 = area_target - global_position
	var local = global_basis.inverse() * d
	var want := atan2(-local.x, -local.z)
	turret_yaw = rotate_toward(turret_yaw, want, delta * 1.4)
	model.turret.rotation.y = turret_yaw
	if absf(angle_difference(turret_yaw, want)) > 0.1:
		return
	var dist := global_position.distance_to(area_target)
	for wd in weapons:
		wd["cd"] -= delta
		wd["reload"] -= delta
		if wd["cd"] > 0.0 or wd["reload"] > 0.0:
			continue
		var w: Dictionary = wd["w"]
		if dist > float(w["range"]):
			continue
		if wd["mag"] <= 0:
			wd["reload"] = float(w["reload"])
			wd["mag"] = int(w["mag"])
			continue
		if wd["burst"] <= 0:
			var b: Array = w["burst"]
			wd["burst"] = randi_range(b[0], b[1])
		if w["kind"] == "he":
			W.combat.fire_he_area(self, area_target, w)
		else:
			W.combat.fire_area(self, area_target, w)
		wd["mag"] -= 1
		wd["burst"] -= 1
		if wd["burst"] <= 0:
			var pz: Array = w["pause"]
			wd["cd"] = randf_range(pz[0], pz[1]) * 1.3
		else:
			wd["cd"] = float(w["interval"])


## Infantry walking behind (order "за технікою"): keep their pace.
func _escorted() -> bool:
	for sq in W.squads:
		if sq.side == side and sq.order == "follow_veh" and sq.follow_v == self and sq.active_count() > 0:
			return true
	return false


func _apply_ground(delta: float) -> void:
	var p = global_position
	var f = forward()
	var r = Vector3(-f.z, 0, f.x)
	var g = W.grid
	var hf: float = g.height_at(p.x + f.x * 2.5, p.z + f.z * 2.5)
	var hb: float = g.height_at(p.x - f.x * 2.5, p.z - f.z * 2.5)
	var hr: float = g.height_at(p.x + r.x * 1.3, p.z + r.z * 1.3)
	var hl: float = g.height_at(p.x - r.x * 1.3, p.z - r.z * 1.3)
	var hc: float = g.height_at(p.x, p.z)
	p.y = maxf(hc, (hf + hb + hr + hl) * 0.25)
	global_position = p
	var k = clampf(delta * 6.0, 0.0, 1.0)
	pitch = lerpf(pitch, atan2(hf - hb, 5.0), k)
	roll = lerpf(roll, atan2(hr - hl, 2.6), k)
	basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)


func _arrive() -> void:
	moving = false
	assault_mode = false
	order_label = "очікування"
	if auto_dismount and not passengers.is_empty():
		auto_dismount = false
		dismount()
	if arrive_cb.is_valid():
		var cb = arrive_cb
		arrive_cb = Callable()
		cb.call(self)


func _update_dismount(delta: float) -> void:
	if dismount_queue.is_empty() or speed > 0.6:
		return
	dismount_t -= delta
	if dismount_t > 0.0:
		return
	dismount_t = 0.35
	var m = dismount_queue.pop_front()
	var idx = passengers.find(m)
	passengers.erase(m)
	if not is_instance_valid(m):
		return
	m.vehicle = null
	var rp = rear_point()
	m.global_position = rp
	m.yaw = yaw + PI
	var n = dismount_queue.size() + passengers.size() + 1
	var right = Vector3(-forward().z, 0, forward().x)
	var k = float(idx) - n * 0.5
	var dest: Vector3 = rp - forward() * 3.5 + right * k * 3.0 + forward() * absf(k) * 0.8
	dest = W.grid.free_point(W.grid.clamp_in(dest, 3.0))
	m.slot = dest
	m.move_to(dest, true)
	if dismount_queue.is_empty():
		order_label = "очікування"
		if squad != null and not is_medevac:
			squad.on_dismounted()
			if side == 0:
				squad.radio("regroup", Loc.t("десант висаджено."), "info")


func _think() -> void:
	if weapons.is_empty():
		return
	var best = null
	var best_s = -INF
	var gun_eye = global_position + Vector3(0, 2.3, 0)
	var maxr = 0.0
	for wd in weapons:
		maxr = maxf(maxr, float(wd["w"]["range"]))
	for e in W.opponents(side):
		if e is Soldier and e.bunker_deep:
			continue
		var d = gun_eye.distance_to(e.global_position)
		if d > maxr * float(Game.wx("sight")):
			continue
		var known: bool = squad != null and squad.knows(e)
		if side == 0 and e is Soldier and (e.revealed > 0.0 or e.marked):
			known = true
		var v: float = W.grid.visibility(gun_eye, e.aim_point())
		if v < 0.1:
			continue
		if not known and randf() > v * e.signature() * 0.6:
			continue
		if side == 0:
			W.command.reveal(e, 3.0, vname)
		if squad != null:
			squad.report(e, e.global_position)
		var sc = 50.0 - d * 0.2 + v * 10.0
		if e is Soldier and e.marked:
			sc += 30.0
		if e is Soldier and e.role == "at":
			sc += 15.0
		if e == target:
			sc += 10.0
		if sc > best_s:
			best_s = sc
			best = e
	# HE guns can engage revealed bunkers
	if side == 0:
		for b in W.bunkers:
			if b.destroyed or not b.ever_seen:
				continue
			var has_he = false
			for wd in weapons:
				if wd["w"]["kind"] == "he":
					has_he = true
			if not has_he:
				break
			var d = gun_eye.distance_to(b.global_position)
			if d < 160.0 and W.grid.visibility(gun_eye, b.aim_point() + Vector3(0, 0.5, 0)) > 0.15:
				var sc = 45.0 + (40.0 if b.marked else 0.0)
				if sc > best_s:
					best_s = sc
					best = b
	target = best
	area_target = null
	if best == null:
		area_target = _area_point(gun_eye, maxr)
	# suppression order: the guns work the point (a marked target still comes first)
	if sup_until > W.time and sup_point != null and not (best is Soldier and best.marked):
		target = null
		area_target = sup_point
	elif sup_until > 0.0 and sup_until <= W.time:
		sup_until = -1.0
		if order_label == "подавлення":
			order_label = "очікування"
	if target != null and order_label == "очікування":
		order_label = Loc.t("бій")


## Last known enemy position (seen recently, point still in view) for
## suppressive fire.
func _area_point(eye: Vector3, maxr: float):
	# keep working the current point for a while, then shift fire to another
	# known position (the gunner sweeps the whole trench section)
	if area_target != null and randf() < 0.75:
		return area_target
	var cands: Array = []
	for sq in W.squads:
		if sq.side != side:
			continue
		for e in sq.known.keys():
			if not W.is_alive_target(e) or not (e is Soldier):
				continue
			var k: Dictionary = sq.known[e]
			if W.time - float(k["t"]) > AIConfig.AREA_FIRE_MEMORY:
				continue
			var p: Vector3 = k["pos"]
			var d := eye.distance_to(p)
			if d > maxr:
				continue
			var aim := AIConfig.area_aim(p)
			if W.grid.visibility(eye, aim) < 0.2:
				continue
			cands.append(aim)
	return cands[randi() % cands.size()] if not cands.is_empty() else null


func _update_weapons(delta: float) -> void:
	if model.turret == null:
		return
	var want = 0.0
	if (target == null or not W.is_alive_target(target)) and area_target != null:
		_area_weapons(delta)
		return
	if target != null and W.is_alive_target(target):
		var d = target.global_position - global_position
		var local = global_basis.inverse() * d
		want = atan2(-local.x, -local.z)
	turret_yaw = rotate_toward(turret_yaw, want, delta * 1.4)
	model.turret.rotation.y = turret_yaw
	if target == null or not W.is_alive_target(target):
		return
	if absf(angle_difference(turret_yaw, want)) > 0.08:
		return
	for wd in weapons:
		wd["cd"] -= delta
		wd["reload"] -= delta
		if wd["cd"] > 0.0 or wd["reload"] > 0.0:
			continue
		var w: Dictionary = wd["w"]
		var dist = global_position.distance_to(target.global_position)
		if dist > float(w["range"]):
			continue
		if w["kind"] == "bullet" and (target is Bunker):
			continue
		if wd["mag"] <= 0:
			wd["reload"] = float(w["reload"])
			wd["mag"] = int(w["mag"])
			continue
		if wd["burst"] <= 0:
			var b: Array = w["burst"]
			wd["burst"] = randi_range(b[0], b[1])
		if w["kind"] == "he":
			W.combat.fire_he(self, target, w)
		else:
			W.combat.fire(self, target, w)
		wd["mag"] -= 1
		wd["burst"] -= 1
		flash_t = 0.4
		if wd["burst"] <= 0:
			var pz: Array = w["pause"]
			wd["cd"] = randf_range(pz[0], pz[1])
		else:
			wd["cd"] = float(w["interval"])


func muzzle_pos() -> Vector3:
	if model.muzzle:
		return model.muzzle.global_position
	return global_position + Vector3(0, 2.2, 0)


# ------------------------------------------------------------------ damage
func take_damage(amount: float, kind: String, source) -> void:
	if state == "destroyed":
		return
	var armor: float = data["armor"]
	var dmg = amount
	# which side is hit: the front armour is thick, the sides and the rear are not
	var aspect := ""
	if source != null and is_instance_valid(source) and source is Node3D:
		var hd: Vector3 = (source as Node3D).global_position - global_position
		hd.y = 0.0
		if hd.length() > 0.5:
			hd = hd.normalized()
			last_hit_dir = hd
			var c := forward().dot(hd)
			aspect = "front" if c > 0.7 else ("rear" if c < -0.7 else "side")
	var asp_k: float = {"": 1.0, "front": AIConfig.ARMOR_FRONT, "side": AIConfig.ARMOR_SIDE, "rear": AIConfig.ARMOR_REAR}[aspect]
	dmg *= asp_k
	match kind:
		"bullet":
			dmg = dmg * pow(1.0 - armor, 3.0)
		"he":
			dmg = dmg * (1.0 - armor * 0.75)
		"at":
			dmg = dmg * randf_range(0.8, 1.2)
	hp -= dmg
	last_hit_t = W.time
	under_fire_t = 10.0
	if kind == "at":
		W.fx.sparks(aim_point())
		for m in passengers.duplicate():
			if randf() < 0.25:
				W.damage.apply(m, randf_range(40, 110), source, true)
		if state != "immobile" and randf() < 0.22 * (AIConfig.ARMOR_IMMOB_SIDE if aspect in ["side", "rear"] else 1.0) and hp > 0.0:
			state = "immobile"
			stop()
			if side == 0:
				radio("vehicle", Loc.t("знерухомлено!"), "alert")
	if hp <= 0.0:
		destroy(source)
	elif hp < max_hp * 0.5 and state == "ok":
		state = "damaged"
		if side == 0:
			radio("vehicle", Loc.t("пошкоджено (%d%%)") % int(hp / max_hp * 100.0), "warn")
	elif side == 0 and kind == "at" and state != "destroyed":
		radio("vehicle", {"front": Loc.t("влучання ПТ-засобу в лоб — броня витримала!"), "side": Loc.t("влучання ПТ-засобу в борт!"),
			"rear": Loc.t("влучання ПТ-засобу в корму!")}.get(aspect, Loc.t("влучання ПТ-засобу!")), "alert")
	# a hit from an AT weapon: the crew backs out of the line of fire (once in
	# a while; not while dropping troops, not when it cannot move)
	if kind == "at" and not assault_mode and state != "destroyed" and state != "immobile" and dismount_queue.is_empty() and W.time - _pullback_t > 25.0:
		_pullback_t = W.time
		var back: Vector3 = global_position - forward() * 16.0
		order_move(back)
		order_label = Loc.t("відхід з-під вогню")
		if side == 0:
			radio("fire", Loc.t("під вогнем ПТ-засобів, відходжу в укриття"), "warn")


func destroy(source) -> void:
	if state == "destroyed":
		return
	state = "destroyed"
	moving = false
	selected = false
	if W.blog:
		W.blog.add("loss" if side == 0 else "enemy", Loc.t("%s знищено") % vname, global_position)
	ring.visible = false
	W.fx.explosion(global_position + Vector3(0, 1.2, 0), 6.0)
	W.sfx.play("explosion", global_position, 6.0)
	model.set_burnt()
	burn_node = W.fx.burning(global_position + Vector3(0, 1.4, 0), true)
	if engine:
		engine.stop()
	var right = Vector3(-forward().z, 0, forward().x)
	var i = 0
	for m in passengers.duplicate():
		passengers.erase(m)
		m.vehicle = null
		m.on_board = false
		var p: Vector3 = global_position + right * (2.0 if i % 2 == 0 else -2.0) - forward() * (i * 0.7 - 2.0)
		m.global_position = W.grid.free_point(p)
		var r = randf()
		if m.health == Soldier.H.INCAP:
			if r < 0.5:
				W.damage.set_health(m, Soldier.H.DEAD, source, "vehicle")
		elif r < 0.3:
			W.damage.set_health(m, Soldier.H.DEAD, source, "vehicle")
		elif r < 0.65:
			W.damage.set_health(m, Soldier.H.INCAP, source, "vehicle")
		else:
			W.damage.apply(m, 55.0, source, true)
		i += 1
	dismount_queue.clear()
	if squad != null and squad.vehicle == self:
		squad.mounted = false
		if squad.order == "mounted" or squad.order == "mount":
			squad.order = "hold"
	var c = W.grid.cidx(global_position.x, global_position.z)
	W.grid.cover[c] = maxf(W.grid.cover[c], 0.5)
	W.grid.obstacle[c] = maxf(W.grid.obstacle[c], 1.6)
	Events.vehicle_destroyed.emit(self)
	if side == 0:
		Events.msg(Loc.t("%s ЗНИЩЕНО!") % vname, "alert")
