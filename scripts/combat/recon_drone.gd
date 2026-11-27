class_name ReconDrone
extends Node3D
## Enemy reconnaissance drone. Circles high over the field, sees our men
## by the same visibility rules as everybody (crowns, houses and smoke hide
## them, weather blurs), only approximately. What it sees reaches the enemy
## command after a relay delay — and only if our men are still there — and
## feeds the enemy's existing mortar / FPV targeting (EnemyAI.drone_known).
## The moment it spots a group or a vehicle our troops below call it out, so
## the player has time to scatter or take cover. It can be shot down.

var t_end := 0.0
var patrol := Vector3.ZERO
var orbit_c := Vector3.ZERO
var orbit_a := 0.0
var sense_t := 0.0
var shoot_t := 0.0
var retarget_t := 0.0
var leaving := false
var done := false
var revealed := false        # our side has seen / heard it (marker on screen)
var seen: Dictionary = {}    # our unit -> {pos (approximate), first: time, t: time}
var warned := {}             # our squad -> time of its last warning
var rotors: Array = []
var buzz: AudioStreamPlayer3D


func setup(start: Vector3, duration: float) -> void:
	global_position = start
	t_end = W.time + duration
	add_to_group("recon")
	_build()
	buzz = W.sfx.make_loop("fpv", self, -14.0)
	if buzz:
		buzz.pitch_scale = 0.7
	_pick_patrol()


func _build() -> void:
	var s := 3.2
	var mdark := MF.mat(Color(0.16, 0.17, 0.15), 0.6, 0.2)
	MF.part(self, MF.box(0.24, 0.1, 0.34), mdark, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * s, false)
	for k in 4:
		var ang := PI / 4.0 + k * PI / 2.0
		var off := Vector3(cos(ang), 0, sin(ang)) * 0.32
		MF.part(self, MF.box(0.04, 0.03, 0.46), mdark, off * 0.5 * s, Vector3(0, -ang + PI / 2, 0), Vector3.ONE * s, false)
		rotors.append(MF.part(self, MF.cyl(0.15, 0.15, 0.01, 8), MF.mat(Color(0.3, 0.3, 0.3)), off * s + Vector3(0, 0.07, 0), Vector3.ZERO, Vector3.ONE * s, false))
	MF.part(self, MF.sphere(0.07, 0.14, 6, 4), MF.mat(Color(0.08, 0.08, 0.08), 0.3, 0.4), Vector3(0, -0.1, 0.1) * s, Vector3.ZERO, Vector3.ONE * s, false)   # camera
	MF.part(self, MF.box(0.05, 0.05, 0.05), MF.glow(Color(1, 0.2, 0.1), 4.0), Vector3(0, 0.08, -0.17) * s, Vector3.ZERO, Vector3.ONE * s, false)


func aim_point() -> Vector3:
	return global_position


## Where to look: over men the enemy already knows about, else somewhere in
## the band between its position and the way we come.
func _pick_patrol() -> void:
	var def: MapDef = W.mission.def
	var known: Dictionary = W.enemy_ai._known_targets() if W.enemy_ai else {}
	if not known.is_empty():
		var ks: Array = known.values()
		patrol = ks[randi() % ks.size()]
	else:
		var obj := Vector3(def.objective_rect.get_center().x, 0, def.objective_rect.get_center().y)
		var k := randf_range(0.35, 0.75)
		patrol = obj.lerp(def.player_entry, k) + Vector3(randf_range(-60, 60), 0, randf_range(-30, 30))
	var h := def.size * 0.5 - 20.0
	patrol.x = clampf(patrol.x, -h, h)
	patrol.z = clampf(patrol.z, -h, h)
	orbit_c = patrol
	retarget_t = randf_range(25.0, 40.0)


func _process(delta: float) -> void:
	if done or not W.running():
		return
	for r in rotors:
		r.rotate_y(delta * 50.0)
	_fly(delta)
	sense_t -= delta
	if sense_t <= 0.0:
		sense_t = 1.0
		if not leaving:
			_sense()
			_relay()
	shoot_t -= delta
	if shoot_t <= 0.0:
		shoot_t = 0.5
		_spotted_by_ours()
		_air_defence()


func _fly(delta: float) -> void:
	var def: MapDef = W.mission.def
	if not leaving and (W.time > t_end or float(Game.wx("wind")) >= 2.5 and randf() < delta * 0.01):
		leaving = true
		orbit_c = Vector3(global_position.x, 0, -def.size * 0.5 - 80.0)
	retarget_t -= delta
	if retarget_t <= 0.0 and not leaving:
		_pick_patrol()
	var spd := AIConfig.RECON_SPEED
	var to: Vector3
	if leaving:
		to = orbit_c
	else:
		orbit_a += delta * spd / AIConfig.RECON_ORBIT_R
		to = orbit_c + Vector3(cos(orbit_a), 0, sin(orbit_a)) * AIConfig.RECON_ORBIT_R
	to.y = W.grid.height_at(to.x, to.z) + AIConfig.RECON_ALT
	var d := to - global_position
	var step := spd * delta
	if d.length() > 0.1:
		global_position += d.normalized() * minf(step, d.length())
		var look := global_position + Vector3(d.x, 0, d.z).normalized()
		if look.distance_to(global_position) > 0.01:
			look_at(look, Vector3.UP)
	if leaving and absf(global_position.z) > def.size * 0.5 + 60.0:
		done = true
		queue_free()


## The camera looks down: what of ours it can see within its footprint.
func _sense() -> void:
	var p := global_position
	for u in W.units:
		if u.side != 0 or not u.is_active():
			continue
		_look_at(u, p)
	for v in W.vehicles:
		if v.side != 0 or v.offmap or v.state == "destroyed":
			continue
		_look_at(v, p)


func _look_at(u, p: Vector3) -> void:
	var g: Vector3 = u.global_position
	var hd := Vector2(g.x - p.x, g.z - p.z).length()
	if hd > AIConfig.RECON_FOOTPRINT:
		return
	var vis: float = W.grid.visibility(p, u.aim_point())
	if vis < 0.15:
		return
	var sig: float = u.signature() if u.has_method("signature") else 1.5
	var pr: float = vis * sig * (1.0 - hd / AIConfig.RECON_FOOTPRINT * 0.6) * float(Game.wx("detect")) * float(Game.wx("sight")) * AIConfig.RECON_DETECT
	if u is Vehicle or (u.moving if "moving" in u else false):
		pr *= 1.5
	if randf() > pr:
		return
	var err := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * AIConfig.RECON_ERROR
	var e: Dictionary = seen.get(u, {})
	if e.is_empty():
		e = {"first": W.time}
	e["pos"] = g + err
	e["t"] = W.time
	seen[u] = e
	_warn_if_targeted(u)


## A group (or a vehicle) under the drone: our men call it out — the player's
## cue to scatter / take cover before the fire comes.
func _warn_if_targeted(u) -> void:
	var sq = u.squad if "squad" in u else null
	if sq == null and u is Vehicle:
		sq = u.squad
	var group := u is Vehicle
	if not group:
		var n := 0
		for o in seen.keys():
			if is_instance_valid(o) and W.time - float(seen[o]["t"]) < 8.0 and (seen[o]["pos"] as Vector3).distance_to(u.global_position) < 15.0:
				n += 1
		group = n >= 3
	if not group:
		return
	var key = sq if sq != null else u
	if W.time - float(warned.get(key, -999.0)) < 45.0:
		return
	warned[key] = W.time
	revealed = true
	var who: String = sq.short if sq != null else u.vname
	var text := Loc.t("%s: над нами кружляє ворожий дрон-розвідник — розосередитись, в укриття!") % who
	if sq != null and sq.has_method("radio"):
		sq.radio("drone", Loc.t("над нами кружляє ворожий дрон-розвідник — розосередитись, в укриття!"), "alert")
	else:
		Events.msg(text, "alert")
	if W.blog:
		W.blog.add("drone", Loc.t("Ворожий дрон-розвідник помітив %s") % who, u.global_position)


## After the relay delay, what is still true goes to the enemy command.
func _relay() -> void:
	if W.enemy_ai == null:
		return
	for u in seen.keys():
		if not is_instance_valid(u) or not W.is_alive_target(u):
			seen.erase(u)
			continue
		var e: Dictionary = seen[u]
		if W.time - float(e["first"]) < AIConfig.RECON_RELAY:
			continue
		# still there? (he moved away = the report is stale, not passed on)
		if (e["pos"] as Vector3).distance_to(u.global_position) > AIConfig.RECON_ERROR + 6.0:
			seen.erase(u)
			continue
		if W.time - float(e["t"]) < 6.0:
			if not W.enemy_ai.drone_known.has(u):
				W.enemy_ai.stats["recon_reports"] += 1
			W.enemy_ai.drone_known[u] = {"pos": e["pos"], "t": W.time}


## Our men notice it (sound / sight) — then it is marked on the screen.
func _spotted_by_ours() -> void:
	if revealed:
		return
	for u in W.units:
		if u.side == 0 and u.is_active() and u.global_position.distance_to(global_position) < AIConfig.RECON_HEARD:
			revealed = true
			if u.squad and W.time - float(warned.get(u.squad, -999.0)) > 45.0:
				warned[u.squad] = W.time
				u.squad.radio("drone", Loc.t("бачимо ворожий дрон-розвідник у небі."), "warn")
			return


## Rifle and MG fire at it when it is low enough to have a chance.
func _air_defence() -> void:
	var p := global_position
	var chance := 0.0
	var shooters := 0
	for u in W.units:
		if u.side != 0 or not u.is_active() or u.noncombat or shooters >= 5 or u.supp_level >= 3:
			continue
		var d: float = u.global_position.distance_to(p)
		if d > AIConfig.RECON_SHOOT_R or W.grid.visibility(u.eye_point(), p) < 0.2:
			continue
		shooters += 1
		chance += (AIConfig.RECON_HIT_MG if u.role == "mg" else AIConfig.RECON_HIT) * (1.0 - d / (AIConfig.RECON_SHOOT_R + 20.0))
		if randf() < 0.4:
			W.fx.tracer(u.model.muzzle_pos(), p + Vector3(randf_range(-4, 4), randf_range(-3, 3), randf_range(-4, 4)), true)
	if shooters > 0 and randf() < chance:
		done = true
		W.fx.explosion(global_position, 1.2)
		W.sfx.play("small_expl", global_position)
		Events.msg(Loc.t("Ворожий дрон-розвідник збито!"), "good")
		W.enemy_ai.stats["recon_down"] += 1
		if W.blog:
			W.blog.add("enemy", Loc.t("Ворожий дрон-розвідник збито"), global_position)
		var g: Vector3 = W.grid.ground(global_position)
		W.fx.launch(global_position, g, 2.5, 1.0, "grenade", func(_q: Vector3): pass)
		queue_free()
