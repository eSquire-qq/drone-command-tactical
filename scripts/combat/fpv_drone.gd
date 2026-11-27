class_name FpvDrone
extends Node3D
## FPV strike drone (either side). Flies in from off-map at a realistic,
## unhurried pace, cruises at altitude, then dives on the target.
## Enemy infantry near its path can shoot it down.

var side := 0
var target = null          # Soldier / Vehicle / Bunker or null
var target_pos := Vector3.ZERO
var speed := Db.FPV_SPEED
var cruise_alt := 22.0
var shoot_t := 0.0
var done := false
var buzz: AudioStreamPlayer3D
var rotors: Array = []
var revealed := true


func setup(p_side: int, p_target, start: Vector3) -> void:
	side = p_side
	if p_target is Vector3:
		target_pos = p_target
	else:
		target = p_target
		target_pos = p_target.aim_point()
	global_position = start
	add_to_group("fpv")
	_build()
	buzz = W.sfx.make_loop("fpv", self, -4.0)


func _build() -> void:
	var s = 1.7
	var mdark = MF.mat(Color(0.12, 0.12, 0.12), 0.5, 0.3)
	MF.part(self, MF.box(0.2, 0.08, 0.28), mdark, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * s, false)
	for k in 4:
		var ang = PI / 4.0 + k * PI / 2.0
		var off = Vector3(cos(ang), 0, sin(ang)) * 0.28
		MF.part(self, MF.box(0.04, 0.03, 0.4), mdark, off * 0.5 * s, Vector3(0, -ang + PI / 2, 0), Vector3.ONE * s, false)
		var r = MF.part(self, MF.cyl(0.13, 0.13, 0.01, 8), MF.mat(Color(0.35, 0.35, 0.35)), off * s + Vector3(0, 0.06, 0), Vector3.ZERO, Vector3.ONE * s, false)
		rotors.append(r)
	MF.part(self, MF.cyl(0.06, 0.06, 0.25, 6), MF.mat(Color(0.35, 0.38, 0.25)), Vector3(0, -0.1, -0.15), Vector3(PI / 2, 0, 0), Vector3.ONE * s, false)
	var led = Color(1, 0.2, 0.1) if side == 1 else Color(0.2, 0.6, 1.0)
	MF.part(self, MF.box(0.05, 0.05, 0.05), MF.glow(led, 5.0), Vector3(0, 0.09, 0.2), Vector3.ZERO, Vector3.ONE * s, false)


func aim_point() -> Vector3:
	return global_position


func eta() -> float:
	var p = global_position
	return Vector2(target_pos.x - p.x, target_pos.z - p.z).length() / speed + 2.0


func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("fpv", t0)


func _process_body(delta: float) -> void:
	if done or not W.running():
		return
	for r in rotors:
		r.rotate_y(delta * 60.0)
	if target != null and W.is_alive_target(target):
		target_pos = target.aim_point()
	var p = global_position
	var flat = Vector2(target_pos.x - p.x, target_pos.z - p.z)
	var hd = flat.length()
	var want_y: float = W.grid.height_at(p.x, p.z) + cruise_alt
	if hd < 35.0:
		want_y = lerpf(target_pos.y, want_y, clampf((hd - 4.0) / 31.0, 0.0, 1.0))
	var to = Vector3(target_pos.x, want_y, target_pos.z)
	if hd < 4.0:
		to = target_pos
	var d = to - p
	var step = speed * (1.35 if hd < 35.0 else 1.0) * delta
	if d.length() <= step + 0.4 and hd < 4.0:
		_impact()
		return
	var dir = d.normalized()
	global_position = p + dir * step + Vector3(0, sin(W.time * 7.0) * 0.015, 0)
	var look = global_position + Vector3(dir.x, dir.y * 0.4, dir.z)
	if look.distance_to(global_position) > 0.01:
		look_at(look, Vector3.UP)
	shoot_t -= delta
	if shoot_t <= 0.0:
		shoot_t = 0.5
		if side == 0 and W.ew and W.ew.fpv_link_lost(global_position):
			_link_lost()
			return
		_air_defence()


## Infantry of the other side fire at the drone when it's close and visible.
func _air_defence() -> void:
	var p = global_position
	var chance = 0.0
	var shooters = 0
	for u in W.units:
		if u.side == side or not u.is_active() or u.noncombat or shooters >= 4:
			continue
		var d: float = u.global_position.distance_to(p)
		if d > 45.0:
			continue
		if W.grid.visibility(u.eye_point(), p) < 0.2:
			continue
		shooters += 1
		var c = 0.05 if u.role != "mg" else 0.09
		c *= 1.0 - d / 60.0
		chance += c
		if randf() < 0.6:
			W.fx.tracer(u.model.muzzle_pos(), p + Vector3(randf_range(-2, 2), randf_range(-1, 2), randf_range(-2, 2)), u.side == 0)
			W.sfx.play("rifle", u.global_position, -6.0)
	if shooters > 0 and randf() < chance:
		_shot_down()


func _link_lost() -> void:
	done = true
	Events.msg(Loc.t("FPV-дрон втратив зв'язок через РЕБ противника"), "warn")
	var g = W.grid.ground(global_position + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)))
	W.fx.launch(global_position, g, 1.4, 1.0, "grenade", func(p: Vector3): W.fx.explosion(p, 1.2))
	queue_free()


func _shot_down() -> void:
	done = true
	W.fx.explosion(global_position, 1.5)
	W.sfx.play("small_expl", global_position)
	if side == 1:
		Events.msg(Loc.t("Ворожий FPV-дрон збито!"), "good")
	else:
		Events.msg(Loc.t("Наш FPV-дрон збито противником"), "warn")
	queue_free()


func _impact() -> void:
	done = true
	var src = W.combat._virtual_source(side)
	if randf() < float(Game.wx("fpv_miss")):
		# weather: the pilot loses the picture in the last seconds and misses
		var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(5.0, 10.0)
		W.combat.explosion(W.grid.ground(global_position + off), 3.0, 85.0, src, "fpv")
		Events.msg(Loc.t("FPV-дрон промахнувся: погода (%s)") % String(Game.wx("name")).to_lower(), "warn")
		queue_free()
		return
	if target != null and W.is_alive_target(target):
		if target is Vehicle:
			target.take_damage(250.0, "at", src)
		elif target is Bunker or target is EwStation:
			target.take_damage(220.0, src)
		elif target is Soldier:
			W.damage.apply(target, 140.0, src, true)
	W.combat.explosion(global_position, 3.0, 85.0, src, "fpv")
	queue_free()
