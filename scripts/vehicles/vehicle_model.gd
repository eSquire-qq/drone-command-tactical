@tool
class_name VehicleModel
extends Node3D
## Low-poly vehicle visuals: BMP-1, BMP-2, M113, M113 medevac.
## Forward is -Z. Turret yaw / gun pitch nodes are exposed for animation.

var turret: Node3D
var gun: Node3D
var muzzle: Node3D
var wheels: Array = []
var beacon: MeshInstance3D
var kind = ""
var hull_len = 6.6
var rear_z = 3.3
var body: Node3D
var _beacon_t = 0.0


func build(p_kind: String, side: int, burnt: bool = false) -> void:
	kind = p_kind
	body = MF.pivot(self)
	var base = Color(0.30, 0.34, 0.22) if side == 0 else Color(0.38, 0.36, 0.28)
	if kind == "medevac":
		base = Color(0.56, 0.54, 0.44)
	if burnt:
		base = Color(0.14, 0.12, 0.11)
	var m_hull = MF.mat(base, 0.85, 0.15)
	var m_dark = MF.mat(base.darkened(0.3), 0.85, 0.15)
	var m_track = MF.mat(Color(0.13, 0.12, 0.11) if not burnt else Color(0.22, 0.16, 0.12), 0.9, 0.3)
	var m_wheel = MF.mat(Color(0.20, 0.21, 0.18) if not burnt else Color(0.18, 0.14, 0.11), 0.8, 0.3)
	var m_metal = MF.mat(Color(0.12, 0.12, 0.12), 0.5, 0.6)
	match kind:
		"bmp1", "bmp2":
			_bmp(m_hull, m_dark, m_track, m_wheel, m_metal, kind == "bmp2", burnt)
		_:
			_m113(m_hull, m_dark, m_track, m_wheel, m_metal, kind == "medevac", burnt)
	if not burnt and side == 0:
		# tactical marking: small light-blue chevrons on sides (IFF readability)
		var m_iff = MF.mat(Color(0.75, 0.85, 0.95), 0.6)
		MF.part(body, MF.box(0.02, 0.35, 0.6), m_iff, Vector3(1.46, 1.25, 0.6), Vector3(0, 0, 0), Vector3.ONE, false)
		MF.part(body, MF.box(0.02, 0.35, 0.6), m_iff, Vector3(-1.46, 1.25, 0.6), Vector3(0, 0, 0), Vector3.ONE, false)


func _tracks(m_track: Material, m_wheel: Material, length: float, width: float, wheel_n: int, wheel_r: float, skirt: Material) -> void:
	for sx in [-1.0, 1.0]:
		var x = sx * (width * 0.5 - 0.25)
		MF.part(body, MF.box(0.5, 0.18, length), m_track, Vector3(x, 0.09, 0))
		MF.part(body, MF.box(0.5, 0.14, length - 0.5), m_track, Vector3(x, wheel_r * 2.0 + 0.05, 0))
		# sprocket / idler
		MF.part(body, MF.cyl(wheel_r * 0.85, wheel_r * 0.85, 0.46, 8), m_track, Vector3(x, wheel_r + 0.12, -length * 0.5 + 0.35), Vector3(0, 0, PI / 2))
		MF.part(body, MF.cyl(wheel_r * 0.8, wheel_r * 0.8, 0.46, 8), m_track, Vector3(x, wheel_r + 0.12, length * 0.5 - 0.35), Vector3(0, 0, PI / 2))
		for i in wheel_n:
			var z = -length * 0.5 + 0.9 + i * (length - 1.8) / (wheel_n - 1)
			var w = MF.part(body, MF.cyl(wheel_r, wheel_r, 0.36, 9), m_wheel, Vector3(x + sx * 0.06, wheel_r + 0.02, z), Vector3(0, 0, PI / 2))
			wheels.append(w)
		if skirt:
			MF.part(body, MF.box(0.08, 0.45, length - 0.4), skirt, Vector3(sx * (width * 0.5 + 0.02), wheel_r * 2.0 + 0.25, 0))


func _bmp(m_hull: Material, m_dark: Material, m_track: Material, m_wheel: Material, m_metal: Material, is_bmp2: bool, burnt: bool) -> void:
	hull_len = 6.7
	rear_z = 3.3
	var w = 2.94
	_tracks(m_track, m_wheel, 6.3, w, 6, 0.36, m_hull)
	# lower hull
	MF.part(body, MF.box(w - 0.9, 0.7, 5.6), m_dark, Vector3(0, 0.75, 0.2))
	# upper hull
	MF.part(body, MF.box(w, 0.55, 4.6), m_hull, Vector3(0, 1.32, 0.75))
	# pointed glacis (two plates) + ribbed front
	MF.part(body, MF.box(w, 0.1, 2.1), m_hull, Vector3(0, 1.22, -2.15), Vector3(-0.22, 0, 0))
	MF.part(body, MF.box(w - 0.2, 0.1, 1.3), m_hull, Vector3(0, 0.72, -3.05), Vector3(0.9, 0, 0))
	for i in 4:
		MF.part(body, MF.box(w - 0.3, 0.06, 0.08), m_dark, Vector3(0, 1.12 - i * 0.05, -2.6 + i * 0.35), Vector3(-0.22, 0, 0), Vector3.ONE, false)
	# rear doors
	for sx in [-0.55, 0.55]:
		MF.part(body, MF.box(0.85, 0.9, 0.12), m_dark, Vector3(sx, 0.95, 3.07))
	# roof hatches
	for i in 4:
		MF.part(body, MF.box(0.55, 0.06, 0.6), m_dark, Vector3(-0.45 if i % 2 == 0 else 0.45, 1.62, 1.6 + (i / 2) * 0.75), Vector3.ZERO, Vector3.ONE, false)
	# driver hatch, headlights, exhaust
	MF.part(body, MF.cyl(0.25, 0.25, 0.12, 8), m_dark, Vector3(-0.75, 1.62, -1.1))
	MF.part(body, MF.box(0.18, 0.12, 0.1), MF.mat(Color(0.8, 0.8, 0.7)), Vector3(-1.0, 1.35, -1.98), Vector3.ZERO, Vector3.ONE, false)
	MF.part(body, MF.box(0.6, 0.2, 0.3), m_metal, Vector3(1.2, 1.4, -0.6), Vector3.ZERO, Vector3.ONE, false)
	# turret
	turret = MF.pivot(body, Vector3(0, 1.6, -0.25))
	if is_bmp2:
		MF.part(turret, MF.cyl(0.78, 1.08, 0.55, 9), m_hull, Vector3(0, 0.27, 0))
		MF.part(turret, MF.box(1.2, 0.18, 0.5), m_dark, Vector3(0, 0.62, 0.45))
		MF.part(turret, MF.cyl(0.18, 0.18, 0.2, 8), m_dark, Vector3(-0.45, 0.6, 0.1))
		# ATGM launcher on roof
		MF.part(turret, MF.cyl(0.09, 0.09, 1.2, 6), m_dark, Vector3(0.35, 0.72, -0.2), Vector3(PI / 2, 0, 0))
		gun = MF.pivot(turret, Vector3(0, 0.35, -0.75))
		MF.part(gun, MF.box(0.32, 0.26, 0.5), m_dark, Vector3(0, 0, 0))
		MF.part(gun, MF.cyl(0.045, 0.045, 2.6, 6), m_metal, Vector3(0, 0.02, -1.5), Vector3(PI / 2, 0, 0))
		MF.part(gun, MF.cyl(0.07, 0.07, 0.25, 6), m_metal, Vector3(0, 0.02, -2.75), Vector3(PI / 2, 0, 0))
		muzzle = MF.pivot(gun, Vector3(0, 0.02, -2.9))
	else:
		MF.part(turret, MF.cyl(0.62, 0.95, 0.55, 9), m_hull, Vector3(0, 0.27, 0))
		MF.part(turret, MF.cyl(0.2, 0.2, 0.18, 8), m_dark, Vector3(-0.35, 0.6, 0.1))
		gun = MF.pivot(turret, Vector3(0, 0.33, -0.6))
		MF.part(gun, MF.cyl(0.075, 0.09, 2.0, 7), m_metal, Vector3(0, 0, -1.0), Vector3(PI / 2, 0, 0))
		# ATGM rail above barrel
		MF.part(gun, MF.box(0.12, 0.08, 1.1), m_dark, Vector3(0, 0.22, -0.7))
		muzzle = MF.pivot(gun, Vector3(0, 0, -2.05))
	if burnt:
		turret.rotation = Vector3(0.0, 0.7, 0.12)


func _m113(m_hull: Material, m_dark: Material, m_track: Material, m_wheel: Material, m_metal: Material, medevac: bool, burnt: bool) -> void:
	hull_len = 4.9
	rear_z = 2.45
	var w = 2.68
	_tracks(m_track, m_wheel, 4.8, w, 5, 0.33, null)
	# box hull
	MF.part(body, MF.box(w - 0.1, 1.35, 4.1), m_hull, Vector3(0, 1.22, 0.3))
	# sloped front
	MF.part(body, MF.box(w - 0.1, 0.12, 1.05), m_hull, Vector3(0, 1.62, -1.98), Vector3(-0.5, 0, 0))
	MF.part(body, MF.box(w - 0.1, 0.85, 0.12), m_hull, Vector3(0, 0.82, -2.1), Vector3(0.45, 0, 0))
	# trim vane
	MF.part(body, MF.box(w - 0.3, 0.06, 0.6), m_dark, Vector3(0, 1.45, -2.45), Vector3(-1.0, 0, 0), Vector3.ONE, false)
	# rear ramp + door
	MF.part(body, MF.box(w - 0.4, 1.4, 0.1), m_dark, Vector3(0, 1.1, 2.37))
	MF.part(body, MF.box(0.6, 1.0, 0.04), m_hull, Vector3(0.5, 1.0, 2.43), Vector3.ZERO, Vector3.ONE, false)
	# roof hatch
	MF.part(body, MF.box(1.3, 0.08, 1.4), m_dark, Vector3(0.2, 1.93, 1.0), Vector3.ZERO, Vector3.ONE, false)
	MF.part(body, MF.box(0.18, 0.12, 0.1), MF.mat(Color(0.8, 0.8, 0.7)), Vector3(-1.0, 1.7, -1.75), Vector3.ZERO, Vector3.ONE, false)
	turret = MF.pivot(body, Vector3(-0.55, 1.9, -0.6))
	if medevac:
		# hi-vis band + beacon + markings
		var m_band = MF.mat(Color(0.95, 0.55, 0.12) if not burnt else Color(0.15, 0.1, 0.08), 0.6)
		MF.part(body, MF.box(w + 0.02, 0.22, 3.2), m_band, Vector3(0, 1.5, 0.5), Vector3.ZERO, Vector3.ONE, false)
		MF.part(turret, MF.cyl(0.3, 0.3, 0.2, 8), m_dark, Vector3(0, 0.08, 0))
		if not burnt:
			beacon = MF.part(body, MF.box(0.35, 0.18, 0.2), MF.glow(Color(1.0, 0.65, 0.1), 3.0), Vector3(0.6, 2.05, -0.9), Vector3.ZERO, Vector3.ONE, false)
			for sx in [-1.0, 1.0]:
				var lbl = Label3D.new()
				lbl.text = "MEDEVAC"
				lbl.font_size = 64
				lbl.pixel_size = 0.006
				lbl.modulate = Color(0.12, 0.12, 0.12)
				lbl.outline_size = 0
				lbl.position = Vector3(sx * (w * 0.5 + 0.03), 1.2, 0.5)
				lbl.rotation = Vector3(0, sx * PI / 2, 0)
				body.add_child(lbl)
		muzzle = MF.pivot(turret, Vector3(0, 0.2, -0.5))
		gun = turret
	else:
		MF.part(turret, MF.cyl(0.42, 0.45, 0.28, 8), m_dark, Vector3(0, 0.1, 0))
		MF.part(turret, MF.box(0.9, 0.55, 0.06), m_dark, Vector3(0, 0.45, -0.3))
		gun = MF.pivot(turret, Vector3(0, 0.42, -0.2))
		MF.part(gun, MF.box(0.14, 0.16, 0.7), m_metal, Vector3(0, 0, 0))
		MF.part(gun, MF.cyl(0.035, 0.035, 1.3, 6), m_metal, Vector3(0, 0, -0.9), Vector3(PI / 2, 0, 0))
		MF.part(gun, MF.box(0.1, 0.18, 0.16), m_hull, Vector3(0.12, -0.05, 0.05), Vector3.ZERO, Vector3.ONE, false)
		muzzle = MF.pivot(gun, Vector3(0, 0, -1.6))
	if burnt:
		turret.rotation = Vector3(0.2, -0.5, 0.0)


func animate(dt: float, speed: float) -> void:
	for w in wheels:
		w.rotate_object_local(Vector3.UP, -speed * dt / 0.35)
	if speed > 0.3:
		body.position.y = sin(Time.get_ticks_msec() * 0.02) * 0.015
	if beacon:
		_beacon_t += dt
		beacon.visible = fmod(_beacon_t, 0.8) < 0.4


func set_burnt() -> void:
	for c in body.find_children("*", "MeshInstance3D", true, false):
		var mi = c as MeshInstance3D
		var m = mi.material_override as StandardMaterial3D
		if m:
			mi.material_override = MF.mat(m.albedo_color.darkened(0.7).lerp(Color(0.12, 0.1, 0.09), 0.5), 1.0)
	for c in body.find_children("*", "Label3D", true, false):
		c.visible = false
	if beacon:
		beacon.visible = false
		beacon = null
	if turret:
		turret.rotation.z = 0.12
