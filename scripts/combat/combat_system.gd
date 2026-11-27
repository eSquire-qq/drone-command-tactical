class_name CombatSystem
extends Node
## Resolves all weapon use: small arms, HE guns, grenades, AT rockets,
## and player support assets (mortar, FPV, smoke). Abstract balance model:
## hit chance from range, visibility, cover, suppression and movement.

var scheduled: Array = []   # {t, cb}


func _process(_delta: float) -> void:
	if not Prof.on:
		_process_body(_delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(_delta)
	Prof.add("combat", t0)


func _process_body(_delta: float) -> void:
	if not W.running():
		return
	var i = scheduled.size() - 1
	while i >= 0:
		if W.time >= float(scheduled[i]["t"]):
			var cb: Callable = scheduled[i]["cb"]
			scheduled.remove_at(i)
			cb.call()
		i -= 1


func schedule(delay: float, cb: Callable) -> void:
	scheduled.append({"t": W.time + delay, "cb": cb})


func _muzzle(shooter) -> Vector3:
	if shooter is Soldier:
		return shooter.model.muzzle_pos()
	if shooter is Vehicle:
		return shooter.muzzle_pos()
	return shooter.global_position + Vector3(0, 1.5, 0)


# ------------------------------------------------------------------ small arms
func fire(shooter, target, w: Dictionary) -> void:
	var from = _muzzle(shooter)
	var to: Vector3 = target.aim_point()
	var dist = from.distance_to(to)
	# long range is mostly suppressive; machine guns keep their reach over open ground
	var rng_exp: float = 1.6 if w.get("snd", "") == "mg" else 2.2
	var rng_f = clampf(1.0 - pow(dist / float(w["range"]), rng_exp), 0.03, 1.0)
	var vis = 1.0
	if shooter is Soldier:
		vis = clampf(shooter.target_vis * 1.6, 0.25, 1.0)
	var p: float = float(w["acc"]) * rng_f * vis
	if target is Soldier:
		var cov: float = target.cover_value()
		# a man at a window is covered only towards the window: from inside the
		# building (the clearing team behind him) he is in the open
		if target.post != null and (from - target.global_position).dot(target.post["dir"]) < 0.0:
			cov = AIConfig.BLD_INSIDE_COVER
		if dist < 12.0:
			cov *= 0.5           # point-blank in the trench: walls help less
			p = minf(0.6, p * 1.7 * (1.0 + (shooter.vet_close if shooter is Soldier else 0.0)))
		p *= 1.0 - cov
		if target.moving:
			p *= 0.8
	if shooter is Soldier:
		p *= shooter.skill
		p *= float(AIConfig.LEVEL_ACC[shooter.supp_level])
		if shooter.moving:
			p *= 0.45
		if shooter.health == Soldier.H.WOUNDED:
			p *= 0.7
		if shooter.side == 1:
			p *= float(Game.diff("enemy_acc"))
	else:
		if shooter.moving:
			p *= 0.6
	p *= lerpf(1.0, float(Game.wx("acc")), clampf(dist / 120.0, 0.0, 1.0))
	var hit = randf() < p
	var end = to
	if not hit:
		var miss = Vector3(randf_range(-1, 1), randf_range(-0.6, 0.4), randf_range(-1, 1)).normalized() * randf_range(0.8, 3.0)
		end = to + miss
		# continue the ray to the ground for the impact puff
		var dir = (end - from).normalized()
		var gp = W.grid.raycast(from, dir, dist + 25.0)
		if gp != null:
			end = gp
	var friendly: bool = shooter.side == 0
	var tr_every: int = int(w.get("tracer", 3))
	if randi() % tr_every == 0:
		W.fx.tracer(from, end, friendly, w.get("snd", "") == "hmg")
	W.fx.muzzle_flash(from, shooter is Vehicle)
	W.sfx.play(w.get("snd", "rifle"), from, -4.0 if shooter is Soldier else -1.0)
	if hit:
		if target is Soldier:
			W.damage.bullet_hit(target, float(w["dmg"]), shooter)
		elif target is Vehicle:
			target.take_damage(float(w.get("armor", w["dmg"])), "bullet", shooter)
			W.fx.sparks(to)
	else:
		W.fx.impact(end)
		_suppress_near(end, float(w["supp"]), shooter.side, float(AIConfig.NEAR_MISS_RADIUS.get(w.get("snd", "rifle"), 3.5)))
	_crack(from, end, float(w["supp"]), shooter.side, target)
	if target is Soldier:
		target.add_suppression(float(w["supp"]) * (0.5 if hit else 1.0), "bullet")
		if target.squad != null and target.squad.side != shooter.side:
			target.squad.hear(shooter.global_position, shooter)
	_alert(shooter)


## Short burst at a point (clearing a corner): hits whoever is really there.
func fire_at_point(shooter, pt: Vector3) -> void:
	var w: Dictionary = shooter.weapon
	if w.is_empty():
		return
	var best = null
	var bd := 4.0
	for u in W.units:
		if u.side == shooter.side or not W.is_alive_target(u):
			continue
		var d: float = u.global_position.distance_to(pt)
		if d < bd and W.grid.visibility(shooter.eye_point(), u.aim_point()) > 0.2:
			bd = d
			best = u
	for i in 3:
		if best != null:
			shooter.target_vis = 1.0
			fire(shooter, best, w)
		else:
			var from: Vector3 = _muzzle(shooter)
			var end: Vector3 = pt + Vector3(randf_range(-0.6, 0.6), randf_range(-0.5, 0.3), randf_range(-0.6, 0.6))
			W.fx.tracer(from, end, shooter.side == 0)
			W.fx.muzzle_flash(from)
			W.fx.impact(end)
			W.sfx.play(w.get("snd", "rifle"), from, -4.0)
			_suppress_near(end, float(w["supp"]) * 1.5, shooter.side, 4.0)
	shooter.flash_t = 0.3
	shooter.model.do_kick()


func _suppress_near(pos: Vector3, amount: float, from_side: int, radius: float) -> void:
	for u in W.units:
		if u.side == from_side or not u.is_active():
			continue
		var d: float = u.global_position.distance_to(pos)
		if d < radius:
			u.add_suppression(amount * (1.0 - d / radius), "bullet")


## Rounds cracking past: everyone of the other side close to the last metres
## of the trajectory feels it, not only the target.
func _crack(from: Vector3, to: Vector3, supp: float, from_side: int, skip = null) -> void:
	var seg := to - from
	var L := seg.length()
	if L < 1.0:
		return
	var dir := seg / L
	var start := maxf(0.0, L - AIConfig.CRACK_LENGTH)
	for u in W.units:
		if u == skip or u.side == from_side or not u.is_active():
			continue
		var p: Vector3 = u.global_position + Vector3(0, 0.9, 0)
		var t := clampf((p - from).dot(dir), start, L)
		var d := p.distance_to(from + dir * t)
		if d < AIConfig.CRACK_RADIUS:
			u.add_suppression(supp * AIConfig.CRACK_FACTOR * (1.0 - d / AIConfig.CRACK_RADIUS), "crack")


## Suppressive fire at a point (last known enemy position): rounds land around
## it; whoever is exposed there can be hit, everyone near is suppressed.
func fire_area(shooter, pt: Vector3, w: Dictionary) -> void:
	var from = _muzzle(shooter)
	var r: float = AIConfig.AREA_FIRE_RADIUS
	var end: Vector3 = pt + Vector3(randf_range(-r, r), randf_range(-0.4, 0.8), randf_range(-r, r))
	var friendly: bool = shooter.side == 0
	if randi() % int(w.get("tracer", 3)) == 0:
		W.fx.tracer(from, end, friendly, w.get("snd", "") == "hmg")
	W.fx.muzzle_flash(from, shooter is Vehicle)
	W.fx.impact(end)
	W.sfx.play(w.get("snd", "rifle"), from, -4.0 if shooter is Soldier else -1.0)
	for u in W.units:
		if u.side == shooter.side or not u.is_active():
			continue
		if u.global_position.distance_to(end) < 2.5 and W.grid.visibility(from, u.aim_point()) > 0.2:
			# only a man who is actually exposed (rising to look / shoot) can be hit
			var p: float = float(w["acc"]) * 0.5 * (1.0 - u.cover_value())
			if randf() < p:
				W.damage.bullet_hit(u, float(w["dmg"]), shooter)
	_suppress_near(end, float(w["supp"]) * AIConfig.AREA_FIRE_SUPP, shooter.side, float(AIConfig.NEAR_MISS_RADIUS.get(w.get("snd", "rifle"), 3.5)) + 1.0)
	_crack(from, end, float(w["supp"]), shooter.side)
	_alert(shooter)


## HE round at a point (suppressive fire of vehicle guns).
func fire_he_area(shooter, pt: Vector3, w: Dictionary) -> void:
	var from = _muzzle(shooter)
	var dist = from.distance_to(pt)
	var spread = dist * (1.0 - float(w["acc"])) * 0.07 + 1.5
	# the gunner walks rounds along the parapet in front of the position
	var toward: Vector3 = (from - pt)
	toward.y = 0.0
	var front: Vector3 = pt + toward.normalized() * 2.8
	var impact: Vector3 = W.grid.ground(front + Vector3(randf_range(-spread, spread), 0, randf_range(-spread * 0.4, spread * 0.4)))
	W.fx.muzzle_flash(from, true)
	W.sfx.play(w["snd"], from, 2.0)
	var src = shooter
	W.fx.launch(from, impact, dist / 320.0, 0.0, "shell", func(p: Vector3):
		explosion(p, float(w["radius"]), float(w["power"]), src, "he"))
	_alert(shooter)


func _alert(shooter) -> void:
	if shooter.side == 0 and W.enemy_ai != null:
		W.enemy_ai.on_friendly_fire(shooter.global_position)


# ------------------------------------------------------------------ HE weapons
func fire_he(shooter, target, w: Dictionary) -> void:
	var from = _muzzle(shooter)
	var to: Vector3 = target.aim_point()
	var dist = from.distance_to(to)
	var spread = dist * (1.0 - float(w["acc"])) * 0.07 + 0.5
	var hit_vehicle = target is Vehicle and randf() < float(w["acc"])
	var impact = to
	if not hit_vehicle and not (target is Bunker and randf() < float(w["acc"]) * 0.8):
		impact = to + Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread))
		impact = W.grid.ground(impact)
	W.fx.muzzle_flash(from, true)
	W.sfx.play(w["snd"], from, 2.0)
	var travel = dist / 320.0
	var src = shooter
	var direct = target if (hit_vehicle or impact == to) else null
	W.fx.launch(from, impact, travel, 0.0, "shell", func(p: Vector3):
		if direct is Vehicle and W.is_alive_target(direct):
			direct.take_damage(float(w["armor"]), "he", src)
		elif direct is Bunker and W.is_alive_target(direct):
			direct.take_damage(float(w.get("bunker", 30.0)), src)
		explosion(p, float(w["radius"]), float(w["power"]), src, "he")
	)
	_alert(shooter)


# ------------------------------------------------------------------ grenades & rockets
func throw_grenade(thrower, pos: Vector3) -> void:
	var from: Vector3 = thrower.global_position + Vector3(0, 1.6, 0)
	pos = W.grid.ground(pos)
	var d = from.distance_to(pos)
	var src = thrower
	W.fx.launch(from, pos, 0.6 + d * 0.035, 2.0 + d * 0.15, "grenade", func(p: Vector3):
		schedule(randf_range(0.3, 0.8), func(): explosion(p, Db.GRENADE["radius"], Db.GRENADE["power"], src, "grenade"))
	)


func fire_gl(shooter, pos: Vector3) -> void:
	var from: Vector3 = _muzzle(shooter)
	pos = W.grid.ground(pos)
	var d = from.distance_to(pos)
	var src = shooter
	W.sfx.play("thud", from, -2.0)
	W.fx.launch(from, pos, 0.4 + d * 0.012, 1.0 + d * 0.06, "grenade", func(p: Vector3):
		explosion(p, Db.GL["radius"], Db.GL["power"], src, "grenade")
	)
	_alert(shooter)


func throw_smoke(thrower, pos: Vector3) -> void:
	var from: Vector3 = thrower.global_position + Vector3(0, 1.6, 0)
	pos = W.grid.ground(pos)
	var d = from.distance_to(pos)
	W.fx.launch(from, pos, 0.6 + d * 0.035, 2.0 + d * 0.15, "smoke", func(p: Vector3):
		deploy_smoke(p, 7.0, 35.0)
	)


func fire_rocket(shooter, target) -> void:
	var from = _muzzle(shooter) + Vector3(0, 0.15, 0)
	var to: Vector3 = target.aim_point()
	var dist = from.distance_to(to)
	var p = float(Db.AT_ROCKET["acc"]) * clampf(1.15 - dist / float(Db.AT_ROCKET["range"]), 0.2, 1.0)
	if shooter is Soldier:
		p *= lerpf(1.0, float(AIConfig.LEVEL_ACC[shooter.supp_level]), 0.7)
	if target is Vehicle and target.moving:
		p *= 0.75
	var hit = randf() < p
	var impact = to
	if not hit:
		impact = W.grid.ground(to + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
	W.sfx.play("rocket", from, 3.0)
	W.fx.muzzle_flash(from, true)
	W.fx.impact(from - (to - from).normalized() * 1.5)
	var src = shooter
	W.fx.launch(from, impact, dist / 70.0, 0.4, "rocket", func(pt: Vector3):
		if hit and W.is_alive_target(target):
			if target is Vehicle:
				target.take_damage(float(Db.AT_ROCKET["armor"]), "at", src)
			elif target is Bunker:
				target.take_damage(float(Db.AT_ROCKET["bunker"]), src)
		explosion(pt, Db.AT_ROCKET["radius"], Db.AT_ROCKET["power"], src, "at")
	)
	if shooter is Soldier:
		shooter.flash_t = 1.0
	_alert(shooter)


# ------------------------------------------------------------------ explosions
func explosion(pos: Vector3, radius: float, power: float, source, kind: String = "he") -> void:
	W.fx.explosion(pos, radius)
	W.sfx.play("explosion" if radius >= 4.0 else "small_expl", pos, 2.0 if radius >= 4.0 else 0.0)
	if W.cam:
		W.cam.shake(pos, power)
	var src_side: int = source.side if (source != null and is_instance_valid(source) and "side" in source) else -1
	var in_trench: bool = W.grid.is_trench(pos)
	for u in W.units:
		if u.health == Soldier.H.DEAD or u.vehicle != null or u.evacuated or u.on_board:
			continue
		var d: float = u.global_position.distance_to(pos)
		if d < radius:
			var cov: float = u.cover_value()
			# a grenade inside his own building: the window wall does not shield him
			if u.post != null:
				var eb = Buildings.at(pos)
				if eb != null and eb["id"] == u.post["b"]:
					cov = AIConfig.BLD_INSIDE_COVER
			if u.bunker_deep:
				cov = 0.97 * (AIConfig.BUNKER_DAMAGED_PROT if u.bunker.damaged else 1.0)
			elif u.bunker != null:
				cov = 0.75 * (AIConfig.BUNKER_DAMAGED_PROT if u.bunker.damaged else 1.0)
			elif in_trench and d < 3.0:
				cov *= 0.3
			elif d < 1.5:
				cov *= 0.4
			var dmg = power * pow(1.0 - d / radius, 0.6) * (1.0 - cov * 0.75) * randf_range(0.7, 1.3)
			if dmg > 6.0:
				W.damage.apply(u, dmg, source, true)
		var reach: float = radius * AIConfig.BLAST_REACH + power * AIConfig.BLAST_REACH_POWER
		if d < reach and u.health < Soldier.H.INCAP:
			u.add_suppression(power * AIConfig.BLAST_SUPP * (1.0 - d / reach), "blast")
			if u.squad != null and src_side >= 0 and u.side != src_side and source != null and is_instance_valid(source):
				u.squad.hear(source.global_position, source)
	for v in W.vehicles:
		if v.state == "destroyed" or v.offmap:
			continue
		var d: float = v.global_position.distance_to(pos)
		if d < radius + 2.5:
			v.take_damage(power * 0.5 * (1.0 - d / (radius + 2.5)), "he", source)
	for b in W.bunkers:
		if b.destroyed:
			continue
		var d: float = b.global_position.distance_to(pos)
		if d < radius + 2.0:
			b.take_damage(power * 0.35 * (1.0 - d / (radius + 2.0)), source)
	if W.ew != null:
		for st in W.ew.stations:
			if st.destroyed:
				continue
			var ds: float = st.global_position.distance_to(pos)
			if ds < radius + 1.5:
				st.take_damage(power * 1.2 * (1.0 - ds / (radius + 1.5)), source, kind, ds)
	if W.field != null:
		W.field.on_explosion(pos, radius, power, kind)
	if W.enemy_ai != null and src_side == 0:
		W.enemy_ai.on_friendly_fire(pos)


func deploy_smoke(pos: Vector3, radius: float, duration: float) -> void:
	duration *= float(Game.wx("smoke"))
	var node: Node3D = W.fx.smoke_screen(pos, radius, duration)
	W.smoke_clouds.append({"pos": pos + Vector3(0, 1.5, 0), "r": radius, "end": W.time + duration,
		"r0": radius, "t0": W.time, "dur": duration, "dens": 1.0, "node": node})
	if node != null and W.field != null:
		(node as CPUParticles3D).gravity = W.field.wind * 0.8 + Vector3(0, 0.25, 0)
	W.sfx.play("thud", pos, -6.0)


# ------------------------------------------------------------------ support assets
var mortar_busy := {0: 0.0, 1: 0.0}


## Mortar fire mission. The crew needs time to receive the call, lay the
## tube and fire; rounds land with a wide, uneven spread and an occasional
## stray round far from the aiming point. Returns ETA of the first round.
func mortar_strike(pos: Vector3, rounds: int, dispersion: float, side: int) -> float:
	dispersion *= float(Game.wx("mortar"))
	if side == 1 and W.blog:
		W.blog.add("support", Loc.t("Противник веде мінометний вогонь"), pos)
	var start: float = maxf(W.time, float(mortar_busy[side])) - W.time
	var first: float = start + randf_range(10.0, 14.0)
	var t: float = first
	for i in rounds:
		var off := Vector2(randfn(0.0, dispersion), randfn(0.0, dispersion))
		if randf() < 0.14:
			off = Vector2.from_angle(randf() * TAU) * randf_range(25.0, 60.0)   # stray round
		var p = W.grid.ground(W.grid.clamp_in(pos + Vector3(off.x, 0, off.y), 2.0))
		schedule(t - 1.3, _whistle.bind(p))
		schedule(t - 0.25, _mortar_round.bind(p, side))
		t += randf_range(6.0, 10.0)
	mortar_busy[side] = W.time + t
	return first


func _whistle(p: Vector3) -> void:
	W.sfx.play("whistle", p + Vector3(0, 25, 0), 0.0, 0.05)


func _mortar_round(p: Vector3, side: int) -> void:
	W.fx.launch(p + Vector3(0, 30, 0), p, 0.25, 0.0, "mortar", _mortar_hit.bind(side))


func _mortar_hit(pt: Vector3, side: int) -> void:
	explosion(pt, 6.0, 110.0, _virtual_source(side), "mortar")


func smoke_barrage(pos: Vector3) -> void:
	for i in 3:
		var p = W.grid.ground(pos + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)))
		schedule(2.5 + i * 0.7, _smoke_round.bind(p))


func _smoke_round(p: Vector3) -> void:
	W.fx.launch(p + Vector3(0, 30, 0), p, 0.25, 0.0, "mortar", _smoke_hit)


func _smoke_hit(pt: Vector3) -> void:
	deploy_smoke(pt, 10.0, 45.0)


func fpv_strike(target, start: Vector3, side: int = 0) -> FpvDrone:
	var d = FpvDrone.new()
	add_child(d)
	d.setup(side, target, start)
	if side == 0:
		Events.msg(Loc.t("FPV-дрон у повітрі, підліт ~%d с") % int(d.eta()), "info")
	return d


func fire_atgm(shooter, target) -> void:
	var from = _muzzle(shooter) + Vector3(0, 0.2, 0)
	var to: Vector3 = target.aim_point()
	var dist = from.distance_to(to)
	var p: float = float(Db.ATGM["acc"])
	if shooter.side == 1:
		p = minf(0.95, p * float(Game.diff("atgm_acc")))
	if target is Vehicle and target.moving:
		p *= 0.85
	if shooter is Soldier:
		p *= lerpf(1.0, float(AIConfig.LEVEL_ACC[shooter.supp_level]), 0.7)
	var hit = randf() < p
	W.sfx.play("rocket", from, 4.0)
	W.fx.muzzle_flash(from, true)
	W.fx.impact(from - (to - from).normalized() * 2.0)
	if shooter is Soldier:
		shooter.flash_t = 2.5
	if target is Vehicle and target.side == 0:
		Events.msg(Loc.t("УВАГА! Пуск ПТУР по %s!") % target.vname, "alert")
		target.on_missile_warning()
	var src = shooter
	var on_hit = func(pt: Vector3):
		var ok: bool = hit and W.is_alive_target(target)
		# smoke between launcher and target spoils guidance
		if ok and is_instance_valid(src) and W.grid.visibility(src.global_position + Vector3(0, 2.2, 0), target.aim_point()) <= 0.0 and randf() < 0.7:
			ok = false
		if ok:
			if target is Vehicle:
				target.take_damage(float(Db.ATGM["armor"]), "at", src)
			elif target is Bunker:
				target.take_damage(float(Db.ATGM["bunker"]), src)
			explosion(pt, Db.ATGM["radius"], Db.ATGM["power"], src, "at")
		else:
			var miss = W.grid.ground(pt + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)))
			explosion(miss, Db.ATGM["radius"], Db.ATGM["power"], src, "at")
	W.fx.launch(from, to, 1.0, 0.0, "rocket", on_hit, target, float(Db.ATGM["speed"]))
	_alert(shooter)


var _vsources = {}


## A lightweight stand-in "shooter" for off-map assets (side + position).
func _virtual_source(side: int) -> Node3D:
	if _vsources.has(side) and is_instance_valid(_vsources[side]):
		return _vsources[side]
	var n = VirtualSource.new()
	n.side = side
	add_child(n)
	_vsources[side] = n
	return n


class VirtualSource extends Node3D:
	var side = 0
	var kills = 0
