class_name SoldierModel
extends Node3D
## Low-poly infantry figure with procedural animation (walk, crouch, prone,
## firing recoil, throw, first aid, wounded on the ground, dead).

const SCALE := 1.22

var body: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var fore_l: Node3D
var fore_r: Node3D
var gun: Node3D
var muzzle: Node3D
var launcher: Node3D

var phase := 0.0
var kick := 0.0
var crouch := 0.0
var prone := 0.0
var lie := 0.0
var dead := 0.0
var dead_roll := 0.0
var throw_t := -1.0
var aid := 0.0
var launch_pose := 0.0
var lift := 0.0
var t := 0.0
var hands_up := false


func build(side: int, role: String) -> void:
	scale = Vector3.ONE * SCALE
	dead_roll = randf_range(-0.6, 0.6)
	var uni: Color
	var gear: Color
	var helm: Color
	var tape: Color
	if side == 0:
		uni = Color(0.33, 0.37, 0.25).lerp(Color(0.39, 0.37, 0.27), randf())
		gear = Color(0.23, 0.26, 0.18)
		helm = Color(0.28, 0.32, 0.21)
		tape = Color(0.20, 0.55, 1.0)
	else:
		uni = Color(0.49, 0.43, 0.32).lerp(Color(0.42, 0.40, 0.31), randf())
		gear = Color(0.34, 0.31, 0.23)
		helm = Color(0.37, 0.35, 0.26)
		tape = Color(0.90, 0.20, 0.12)
	if role == "crew_medic":
		gear = Color(0.85, 0.50, 0.12)
	var skin := Color(0.80, 0.62, 0.50).darkened(randf() * 0.3)
	var mu := MF.mat(uni)
	var mg := MF.mat(gear)
	var mh := MF.mat(helm)
	var mt := MF.glow(tape, 0.6)
	var ms := MF.mat(skin)
	var mb := MF.mat(Color(0.12, 0.11, 0.10))
	var mgun := MF.mat(Color(0.09, 0.09, 0.09), 0.6, 0.3)

	body = MF.pivot(self)
	hips = MF.pivot(body, Vector3(0, 0.97, 0))
	MF.part(hips, MF.box(0.34, 0.18, 0.21), mu)
	var ll := _leg(hips, -0.1, mu, mb)
	leg_l = ll[0]
	shin_l = ll[1]
	var lr := _leg(hips, 0.1, mu, mb)
	leg_r = lr[0]
	shin_r = lr[1]
	torso = MF.pivot(hips, Vector3(0, 0.06, 0))
	MF.part(torso, MF.box(0.36, 0.5, 0.22), mu, Vector3(0, 0.27, 0))
	MF.part(torso, MF.box(0.41, 0.34, 0.29), mg, Vector3(0, 0.31, 0))
	MF.part(torso, MF.box(0.37, 0.1, 0.07), mg, Vector3(0, 0.18, -0.17), Vector3.ZERO, Vector3.ONE, false)
	if role != "crew_medic":
		MF.part(torso, MF.box(0.31, 0.36, 0.17), MF.mat(gear.darkened(0.12)), Vector3(0, 0.32, 0.22))
	if role == "leader":
		MF.part(torso, MF.cyl(0.008, 0.012, 0.9, 4), mgun, Vector3(0.1, 0.85, 0.27), Vector3(-0.12, 0, 0), Vector3.ONE, false)
	if role == "medic" or role == "crew_medic":
		MF.part(torso, MF.box(0.14, 0.2, 0.2), MF.mat(Color(0.62, 0.64, 0.56)), Vector3(-0.27, 0.1, 0.05), Vector3.ZERO, Vector3.ONE, false)
	head = MF.pivot(torso, Vector3(0, 0.56, 0))
	MF.part(head, MF.box(0.09, 0.08, 0.09), ms, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE, false)
	MF.part(head, MF.sphere(0.105, 0.24, 7, 4), ms, Vector3(0, 0.13, 0))
	MF.part(head, MF.sphere(0.145, 0.145, 8, 3, true), mh, Vector3(0, 0.155, 0.005))
	MF.part(head, MF.cyl(0.147, 0.147, 0.035, 8), mt, Vector3(0, 0.17, 0.005), Vector3.ZERO, Vector3.ONE, false)
	# arms
	var ar := _arm(torso, 0.22, mu, ms)
	arm_r = ar[0]
	fore_r = ar[1]
	var al := _arm(torso, -0.22, mu, ms)
	arm_l = al[0]
	fore_l = al[1]
	MF.part(arm_l, MF.box(0.115, 0.07, 0.115), mt, Vector3(0, -0.08, 0), Vector3.ZERO, Vector3.ONE, false)
	# weapon
	gun = MF.pivot(torso, Vector3(0.1, 0.36, -0.2))
	match role:
		"crew_medic":
			gun.visible = false
		"mg":
			MF.part(gun, MF.box(0.08, 0.12, 0.62), mgun, Vector3(0, 0, -0.08))
			MF.part(gun, MF.box(0.04, 0.04, 0.45), mgun, Vector3(0, 0.02, -0.6), Vector3.ZERO, Vector3.ONE, false)
			MF.part(gun, MF.box(0.1, 0.12, 0.12), MF.mat(Color(0.25, 0.27, 0.2)), Vector3(-0.08, -0.08, -0.05), Vector3.ZERO, Vector3.ONE, false)
			MF.part(gun, MF.box(0.06, 0.1, 0.22), mgun, Vector3(0, -0.02, 0.32), Vector3.ZERO, Vector3.ONE, false)
			muzzle = MF.pivot(gun, Vector3(0, 0.02, -0.85))
		_:
			MF.part(gun, MF.box(0.055, 0.1, 0.42), mgun, Vector3(0, 0, -0.05))
			MF.part(gun, MF.box(0.03, 0.03, 0.3), mgun, Vector3(0, 0.02, -0.4), Vector3.ZERO, Vector3.ONE, false)
			MF.part(gun, MF.box(0.04, 0.15, 0.06), mgun, Vector3(0, -0.1, -0.08), Vector3(0.25, 0, 0), Vector3.ONE, false)
			MF.part(gun, MF.box(0.05, 0.09, 0.22), mgun, Vector3(0, -0.02, 0.26), Vector3.ZERO, Vector3.ONE, false)
			if role == "grenadier":
				MF.part(gun, MF.box(0.06, 0.06, 0.2), mgun, Vector3(0, -0.07, -0.28), Vector3.ZERO, Vector3.ONE, false)
			muzzle = MF.pivot(gun, Vector3(0, 0.02, -0.58))
	if role == "at" or role == "atgm":
		launcher = MF.pivot(torso, Vector3(0.0, 0.34, 0.26), Vector3(0, 0, 0.9))
		var big := role == "atgm"
		MF.part(launcher, MF.cyl(0.085 if big else 0.055, 0.085 if big else 0.055, 1.25 if big else 1.0, 8), MF.mat(Color(0.30, 0.33, 0.22)))
		if big:
			MF.part(launcher, MF.box(0.16, 0.2, 0.22), MF.mat(Color(0.2, 0.22, 0.17)), Vector3(0.1, 0.1, 0), Vector3.ZERO, Vector3.ONE, false)
		MF.part(launcher, MF.cyl(0.075, 0.06, 0.18, 7), MF.mat(Color(0.25, 0.27, 0.18)), Vector3(0, -0.5, 0), Vector3.ZERO, Vector3.ONE, false)


func _leg(parent: Node3D, x: float, mu: Material, mb: Material) -> Array:
	var hip := MF.pivot(parent, Vector3(x, -0.05, 0))
	MF.part(hip, MF.box(0.15, 0.45, 0.17), mu, Vector3(0, -0.22, 0))
	var knee := MF.pivot(hip, Vector3(0, -0.45, 0))
	MF.part(knee, MF.box(0.13, 0.43, 0.15), mu, Vector3(0, -0.21, 0))
	MF.part(knee, MF.box(0.14, 0.1, 0.27), mb, Vector3(0, -0.44, -0.04))
	return [hip, knee]


func _arm(parent: Node3D, x: float, mu: Material, ms: Material) -> Array:
	var sh := MF.pivot(parent, Vector3(x, 0.46, 0))
	MF.part(sh, MF.box(0.1, 0.3, 0.1), mu, Vector3(0, -0.14, 0))
	var el := MF.pivot(sh, Vector3(0, -0.28, 0))
	MF.part(el, MF.box(0.09, 0.26, 0.09), mu, Vector3(0, -0.12, 0), Vector3.ZERO, Vector3.ONE, false)
	MF.part(el, MF.box(0.08, 0.08, 0.08), ms, Vector3(0, -0.27, 0), Vector3.ZERO, Vector3.ONE, false)
	return [sh, el]


func muzzle_pos() -> Vector3:
	if launch_pose > 0.5 and launcher:
		return launcher.global_position + (-global_basis.z) * 0.6
	if muzzle:
		return muzzle.global_position
	return global_position + Vector3(0, 1.4, 0)


func do_kick() -> void:
	kick = 1.0


func start_throw() -> void:
	throw_t = 0.0


## posture: 0 stand, 1 crouch, 2 prone. hstate: Soldier.H
func animate(dt: float, speed: float, posture: int, hstate: int, aiding: bool, launching: bool, p_lift: float) -> void:
	t += dt
	var tc := 1.0 if posture == 1 else 0.0
	var tp := 1.0 if posture == 2 else 0.0
	var tl := 1.0 if hstate == 2 else 0.0
	var td := 1.0 if hstate == 3 else 0.0
	if hstate >= 2:
		tc = 0.0
		tp = 0.0
	crouch = move_toward(crouch, tc, dt * 4.0)
	prone = move_toward(prone, tp, dt * 3.0)
	lie = move_toward(lie, tl, dt * 3.0)
	dead = move_toward(dead, td, dt * 3.5)
	aid = move_toward(aid, 1.0 if aiding else 0.0, dt * 3.0)
	launch_pose = move_toward(launch_pose, 1.0 if launching else 0.0, dt * 4.0)
	lift = move_toward(lift, p_lift, dt * 2.0)
	kick = move_toward(kick, 0.0, dt * 12.0)
	var sn := clampf(speed / 3.4, 0.0, 1.0)
	phase += dt * (speed * 3.0 + (2.0 if prone > 0.5 and speed > 0.1 else 0.0))
	var sw := sin(phase) * sn
	var down := maxf(prone, dead)
	var ground_pose := maxf(down, lie)
	# body orientation
	body.rotation.x = -PI / 2.0 * down + PI / 2.0 * lie
	body.rotation.z = dead_roll * dead
	body.position = Vector3(0, 0.15 * ground_pose, 0.95 * down - 0.95 * lie)
	position.y = lift
	# hips & torso
	hips.position.y = 0.97 - crouch * 0.4 * (1.0 - ground_pose) + absf(sin(phase)) * 0.04 * sn * (1.0 - ground_pose)
	torso.rotation.x = -(0.1 * sn + crouch * 0.28 + aid * 0.5) * (1.0 - ground_pose)
	torso.position.z = kick * 0.035
	# legs
	var amp := 0.55 * (1.0 - ground_pose)
	var crawl := prone * sn
	leg_l.rotation.x = sw * amp + crouch * 1.35 + crawl * sin(phase) * 0.4
	leg_r.rotation.x = -sw * amp + crouch * 0.15 - crawl * sin(phase) * 0.4
	shin_l.rotation.x = -maxf(0.0, -sw) * 0.9 * (1.0 - ground_pose) - crouch * 1.45
	shin_r.rotation.x = -maxf(0.0, sw) * 0.9 * (1.0 - ground_pose) - crouch * 1.6
	leg_l.rotation.z = -0.1 * dead - 0.15 * lie
	leg_r.rotation.z = 0.15 * dead + 0.1 * lie
	if lie > 0.5:
		var wr := sin(t * 1.3) * 0.25
		leg_l.rotation.x = 0.5 + wr
		shin_l.rotation.x = -0.9 - wr
	# arms: hold weapon pose by default
	var hold := 1.0 - maxf(lie, dead)
	arm_r.rotation = Vector3(0.55 * hold + aid * 0.6, 0, 0.18 * hold)
	fore_r.rotation = Vector3(1.15 * hold, 0, 0)
	arm_l.rotation = Vector3(1.1 * hold + aid * 0.3, 0, -0.45 * hold)
	fore_l.rotation = Vector3(0.45 * hold, 0, 0)
	if lie > 0.5:
		arm_r.rotation = Vector3(0.3, 0, 0.6 + sin(t * 0.9) * 0.2)
		arm_l.rotation = Vector3(2.4, 0, -0.3)
	if dead > 0.5:
		arm_r.rotation = Vector3(2.8, 0, 0.5)
		arm_l.rotation = Vector3(0.2, 0, -0.9)
	if throw_t >= 0.0:
		throw_t += dt
		var k := throw_t / 0.7
		if k < 0.45:
			arm_r.rotation = Vector3(-2.4 * (k / 0.45), 0, 0.2)
		else:
			arm_r.rotation = Vector3(lerpf(-2.4, 1.6, clampf((k - 0.45) / 0.3, 0, 1)), 0, 0.2)
		fore_r.rotation.x = 0.3
		if k >= 1.0:
			throw_t = -1.0
	if hands_up and hstate < 2:
		arm_r.rotation = Vector3(2.9, 0, 0.35)
		arm_l.rotation = Vector3(2.9, 0, -0.35)
		fore_r.rotation = Vector3(0.4, 0, 0)
		fore_l.rotation = Vector3(0.4, 0, 0)
	# weapon
	gun.visible = hstate < 2 and muzzle != null and not hands_up
	gun.rotation.x = PI / 2.0 * prone
	if launcher:
		launcher.position = Vector3(0.0, 0.34, 0.26).lerp(Vector3(0.18, 0.58, -0.05), launch_pose)
		launcher.rotation = Vector3(0, 0, 0.9).lerp(Vector3(-PI / 2.0 + PI / 2.0 * prone, 0, 0), launch_pose)
		launcher.visible = hstate < 2
