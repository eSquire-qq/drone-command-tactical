class_name DroneCamera
extends Node3D
## Recon drone. The drone is a physical object (position, altitude, inertia,
## wind drift) carrying a stabilised camera gimbal with OPTICAL zoom.
##  * WASD / arrows / screen edges — fly (accelerates and coasts, Shift faster)
##  * Q / E — turn the drone, PgUp / PgDn or Shift+wheel — climb / descend
##  * mouse wheel — optical zoom x1..x10 (the drone does NOT move)
##  * middle mouse drag — turn / tilt the gimbal
##  * F — follow selection, H — climb to an overview, minimap click — fly there
## The EW link depends only on where the drone physically is, never on zoom.
## Also acts as the drone sensor that detects enemies in view.

const MAX_SPEED := 12.0
const BOOST := 1.7
const ACCEL := 4.5
const DRAG := 0.9
const CLIMB := 4.5
const YAW_RATE := 0.85
const MIN_ALT := 12.0
const MAX_ALT := 230.0
const BASE_FOV := 58.0
const MAX_ZOOM := 10.0

var cam: Camera3D
var pos := Vector3(0, 80, 60)
var vel := Vector3.ZERO
var vy := 0.0
var yaw := 0.0
var yaw_vel := 0.0
var pitch := deg_to_rad(42.0)     # gimbal tilt below the horizon
var pitch_t := deg_to_rad(42.0)
var zoom := 1.0
var zoom_t := 1.0
var alt_t := 70.0
var follow = null
var autopilot = null              # Vector3 (x, 0, z) where the drone should go
var look_target = null            # Vector3 ground point the gimbal tracks
var standoff := 80.0
var input_enabled := true
var cinematic := false
var cinematic_center := Vector3.ZERO
var cin_a := 0.0
var shake_amt := 0.0
var mmb := false
var edge_scroll := true
var bounds := 80.0
var look_point := Vector3.ZERO
var dist := 90.0                  # drone -> centre of view (read-only)
var speed := 0.0
var zoom_flash := 0.0
var roll := 0.0
var ground_s := 0.0
var _t := 0.0
var _scan_t := 0.0
var _follow_t := 0.0

## Compatibility helpers used by UI / tests: "look at this point".
var focus_t: Vector3:
	get:
		return look_point
	set(v):
		fly_to(v)
var dist_t: float:
	get:
		return standoff
	set(v):
		standoff = clampf(v, 15.0, 320.0)
		if look_target != null:
			fly_to(look_target)
var focus: Vector3:
	get:
		return look_point


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cam = Camera3D.new()
	cam.fov = BASE_FOV
	cam.near = 0.3
	cam.far = 2200.0
	add_child(cam)
	cam.current = true


func altitude() -> float:
	return pos.y - (W.grid.height_at(pos.x, pos.z) if W.grid else 0.0)


func set_cinematic(center: Vector3) -> void:
	cinematic = true
	cinematic_center = center
	zoom = 1.0
	zoom_t = 1.0


## Autopilot: fly to a stand-off position from which the gimbal sees p.
func fly_to(p: Vector3, d: float = -1.0) -> void:
	cinematic = false
	if W.grid:
		p = W.grid.ground(p)
	look_target = p
	if d > 0.0:
		standoff = clampf(d, 15.0, 320.0)
	var tilt := clampf(pitch_t, deg_to_rad(30.0), deg_to_rad(70.0))
	var horiz := standoff * cos(tilt)
	var dirv := Vector3(sin(yaw), 0, cos(yaw))
	var tgt := p + dirv * horiz
	autopilot = Vector3(tgt.x, 0, tgt.z)
	alt_t = clampf(standoff * sin(tilt), MIN_ALT, MAX_ALT)


## Place the drone instantly (mission start, spare drone arriving).
func focus_on(p: Vector3, d: float = -1.0, teleport: bool = true) -> void:
	cinematic = false
	if d > 0.0:
		standoff = d
	if teleport:
		teleport_view(p, standoff, 45.0, 0.0)
	else:
		fly_to(p, d)


func teleport_view(look: Vector3, d: float, pitch_deg: float, p_yaw: float) -> void:
	cinematic = false
	yaw = p_yaw
	pitch = deg_to_rad(pitch_deg)
	pitch_t = pitch
	standoff = d
	var g: Vector3 = W.grid.ground(look) if W.grid else look
	pos = g + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * d
	alt_t = clampf(pos.y - (W.grid.height_at(pos.x, pos.z) if W.grid else 0.0), MIN_ALT, MAX_ALT)
	vel = Vector3.ZERO
	vy = 0.0
	autopilot = null
	look_target = null
	_apply_camera(0.0)


func overview() -> void:
	follow = null
	pitch_t = deg_to_rad(60.0)
	zoom_t = 1.0
	fly_to(Vector3(0, 0, -10), 260.0)


func shake(p: Vector3, power: float) -> void:
	var d := look_point.distance_to(p)
	shake_amt = maxf(shake_amt, clampf(power / 110.0, 0.0, 1.0) * clampf(1.0 - d / 140.0, 0.0, 1.0) * 0.5)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or cinematic:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
			if mb.shift_pressed:
				alt_t = clampf(alt_t + (-6.0 if up else 6.0), MIN_ALT, MAX_ALT)
			else:
				zoom_t = clampf(zoom_t * (1.2 if up else 1.0 / 1.2), 1.0, MAX_ZOOM)
				zoom_flash = 2.0
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			mmb = mb.pressed
	elif event is InputEventMouseMotion and mmb:
		var mm := event as InputEventMouseMotion
		var k := 1.0 / zoom
		yaw_vel = 0.0
		yaw -= mm.relative.x * 0.004 * k
		pitch_t = clampf(pitch_t + mm.relative.y * 0.003 * k, deg_to_rad(12.0), deg_to_rad(89.0))
		look_target = null if follow == null else look_target
	elif event is InputEventKey and event.pressed and not event.echo:
		var act := Game.action_for(event.physical_keycode)
		if act == "follow":
			var sel = W.command.primary_selection() if W.command else null
			follow = sel
			if sel == null:
				Events.msg(Loc.t("Немає вибраного підрозділу для супроводу"), "info")
		elif act == "overview" or event.physical_keycode == KEY_HOME:
			overview()


func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("camera", t0)


func _process_body(delta: float) -> void:
	var dt := delta / maxf(Engine.time_scale, 0.01)
	_t += dt
	zoom_flash = maxf(0.0, zoom_flash - dt)
	if cinematic:
		cin_a += dt * 0.05
		var c := cinematic_center
		pos = c + Vector3(sin(cin_a) * 130.0, 90.0, cos(cin_a) * 130.0)
		yaw = cin_a
		pitch = atan2(90.0, 130.0)
		pitch_t = pitch
		zoom = 1.0
		_apply_camera(dt)
		return
	var acc := Vector3.ZERO
	var steering := false
	if input_enabled:
		var mv := _move_input()
		if mv != Vector2.ZERO:
			steering = true
			autopilot = null
			follow = null
			look_target = null
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			var right := Vector3(cos(yaw), 0, -sin(yaw))
			acc = (fwd * -mv.y + right * mv.x).normalized() * ACCEL * (BOOST if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0) * float(Game.settings.get("cam_speed", 1.0))
		var turn := 0.0
		if Input.is_physical_key_pressed(KEY_Q):
			turn += 1.0
		if Input.is_physical_key_pressed(KEY_E):
			turn -= 1.0
		yaw_vel = move_toward(yaw_vel, turn * YAW_RATE * float(Game.settings.get("cam_turn", 1.0)), dt * 1.6)
		if turn != 0.0:
			look_target = null if follow == null else look_target
		if Input.is_physical_key_pressed(KEY_PAGEUP):
			alt_t = clampf(alt_t + CLIMB * dt, MIN_ALT, MAX_ALT)
		if Input.is_physical_key_pressed(KEY_PAGEDOWN):
			alt_t = clampf(alt_t - CLIMB * dt, MIN_ALT, MAX_ALT)
	else:
		yaw_vel = move_toward(yaw_vel, 0.0, dt * 1.6)
	# follow / autopilot
	if follow != null:
		_follow_t -= dt
		var fp = _follow_pos()
		if fp == null:
			follow = null
		elif _follow_t <= 0.0:
			_follow_t = 0.6
			fly_to(fp)
	var max_s := MAX_SPEED * (BOOST if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	if autopilot != null and not steering:
		var to: Vector3 = autopilot - Vector3(pos.x, 0, pos.z)
		var dd := to.length()
		var want := Vector3.ZERO if dd < 0.5 else to / dd * minf(max_s, dd * 0.45)
		acc = (want - Vector3(vel.x, 0, vel.z)).limit_length(ACCEL)
		if dd < 1.5 and Vector2(vel.x, vel.z).length() < 0.6 and follow == null:
			autopilot = null
	# gimbal tracks its target while flying on autopilot / following
	if look_target != null:
		var lt: Vector3 = look_target
		var h := Vector2(lt.x - pos.x, lt.z - pos.z)
		if h.length() > 2.0:
			var want_yaw := atan2(-h.x, -h.y)
			yaw = rotate_toward(yaw, want_yaw, YAW_RATE * dt)
			pitch_t = clampf(atan2(pos.y - lt.y, h.length()), deg_to_rad(12.0), deg_to_rad(89.0))
	yaw += yaw_vel * dt
	# horizontal motion: inertia, drag, wind
	var hv := Vector3(vel.x, 0, vel.z)
	if acc == Vector3.ZERO:
		hv -= hv * minf(1.0, DRAG * dt)
	hv += acc * dt
	hv = hv.limit_length(max_s)
	var wind := Vector3(sin(_t * 0.13) * 0.5 + sin(_t * 0.41) * 0.25, 0, cos(_t * 0.11) * 0.45 + sin(_t * 0.29) * 0.2)
	vel = Vector3(hv.x, 0, hv.z)
	pos += (vel + wind * 0.35 * float(Game.wx("wind"))) * dt
	var lim := bounds + 40.0
	pos.x = clampf(pos.x, -lim, lim)
	pos.z = clampf(pos.z, -lim, lim)
	# altitude hold over terrain
	var gh: float = W.grid.height_at(pos.x, pos.z) if W.grid else 0.0
	ground_s = lerpf(ground_s, gh, 1.0 - exp(-dt * 0.8))
	var want_vy := clampf((ground_s + alt_t - pos.y) * 0.9, -CLIMB, CLIMB)
	vy = move_toward(vy, want_vy, dt * 3.0)
	pos.y += vy * dt
	pos.y = maxf(pos.y, gh + 4.0)
	speed = vel.length()
	# bank into acceleration (gimbal mostly cancels it)
	var right2 := Vector3(cos(yaw), 0, -sin(yaw))
	roll = lerpf(roll, -acc.dot(right2) / ACCEL * 0.035, 1.0 - exp(-dt * 3.0))
	pitch = lerpf(pitch, pitch_t, 1.0 - exp(-dt * 4.0))
	zoom = lerpf(zoom, zoom_t, 1.0 - exp(-dt * 4.0))
	_apply_camera(dt)
	if W.running():
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scan_t = 0.4
			_scan()


func _follow_pos():
	var f = follow
	if f is Squad and (f.active_count() > 0 or f.mounted):
		return f.center()
	if f is Soldier and is_instance_valid(f) and f.is_active():
		return f.global_position
	if f is Vehicle and is_instance_valid(f) and not f.offmap and f.state != "destroyed":
		return f.global_position
	return null


func _move_input() -> Vector2:
	var mv := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		mv.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		mv.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		mv.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		mv.x += 1
	if edge_scroll and DisplayServer.get_name() != "headless" and DisplayServer.window_is_focused():
		var vp := get_viewport()
		var mp := vp.get_mouse_position()
		var sz := vp.get_visible_rect().size
		if mp.x >= 0 and mp.y >= 0 and mp.x <= sz.x and mp.y <= sz.y:
			if mp.x < 6:
				mv.x -= 1
			elif mp.x > sz.x - 6:
				mv.x += 1
			if mp.y < 6:
				mv.y -= 1
			elif mp.y > sz.y - 6:
				mv.y += 1
	return mv


func _apply_camera(dt: float) -> void:
	# residual vibration of the stabilised gimbal: grows with optical zoom
	var j := deg_to_rad(0.06 + 0.07 * zoom)
	var jit := Vector3(sin(_t * 2.3) + sin(_t * 5.1) * 0.5, sin(_t * 1.9 + 1.0) + sin(_t * 4.3) * 0.4, sin(_t * 1.7) * 0.6) * j
	jit += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * deg_to_rad(shake_amt * 1.5)
	shake_amt = move_toward(shake_amt, 0.0, dt * 2.0)
	var bob := Vector3(0, sin(_t * 1.3) * 0.15 + sin(_t * 2.9) * 0.05, 0)
	var b := Basis.from_euler(Vector3(-pitch + jit.x, yaw + jit.y, roll + jit.z))
	cam.global_transform = Transform3D(b, pos + bob)
	cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(BASE_FOV) * 0.5) / zoom))
	var fwd := -b.z
	var hit = W.grid.raycast(pos, fwd, 1500.0) if W.grid else null
	if hit == null:
		hit = pos + fwd * (pos.y / maxf(-fwd.y, 0.05))
	look_point = hit
	dist = pos.distance_to(look_point)


## Enemy vehicles in the camera view: big and loud — spotted quickly unless
## under trees or in smoke.
func _scan_vehicles() -> void:
	var sz := get_viewport().get_visible_rect().size
	var cpos := cam.global_position
	for v in W.vehicles:
		if v.side != 1 or v.offmap or v.state == "destroyed":
			continue
		var p: Vector3 = v.global_position + Vector3(0, 1.5, 0)
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		if sp.x < 0 or sp.y < 0 or sp.x > sz.x or sp.y > sz.y:
			continue
		if cpos.distance_to(p) / pow(zoom, 0.7) > 240.0:
			continue
		var smoke: float = W.field.smoke_opacity(cpos, p) if W.field else 0.0
		if smoke >= AIConfig.SMOKE_DRONE_BLOCK or W.grid.foliage_at(v.global_position) > 0.6:
			continue
		if randf() < 0.5 * (W.ew.link if W.ew else 1.0):
			W.command.reveal(v, 6.0, Loc.t("дрон"))


## Drone sensor: enemies inside the camera view get detected over time.
## Optical zoom extends the effective observation range.
func _scan() -> void:
	if W.ew and W.ew.drone_down:
		return
	_scan_vehicles()
	var vp := get_viewport()
	var sz := vp.get_visible_rect().size
	var cpos := cam.global_position
	var zk := pow(zoom, 0.7)
	var chance_fog := 1.0
	for u in W.units:
		if u.side != 1 or not u.is_active() or u.bunker_deep:
			continue
		var p: Vector3 = u.global_position + Vector3(0, 1.0, 0)
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		if sp.x < 0 or sp.y < 0 or sp.x > sz.x or sp.y > sz.y:
			continue
		var d := cpos.distance_to(p) / zk
		if d > 190.0:
			continue
		var canopy: float = W.grid.foliage_at(u.global_position)
		if W.grid.fog_len > 0.0:
			chance_fog = exp(-cpos.distance_to(p) / W.grid.fog_len)
		else:
			chance_fog = 1.0
		# smoke between the camera and the man: dense hides him, thin blurs him
		var smoke: float = W.field.smoke_opacity(cpos, p) if W.field else 0.0
		if smoke >= AIConfig.SMOKE_DRONE_BLOCK:
			continue
		var chance: float = 0.35 * (1.0 - canopy * 0.8) * (1.0 - d / 210.0) * u.signature() * chance_fog * (1.0 - smoke)
		if u.post == null and Buildings.under_roof(u):
			chance *= AIConfig.BLD_ROOF_DRONE
		var cdist := (sp - sz * 0.5).length() / sz.length()
		if W.ew:
			chance *= pow(W.ew.link, 1.5)
		chance *= 1.0 - cdist * 0.8
		u.detect += chance
		if u.detect >= 1.0:
			u.detect = 0.6
			# a weak / jammed video link gives only an approximate position
			var q: float = W.ew.link if W.ew else 1.0
			if smoke >= AIConfig.SMOKE_DRONE_VAGUE:
				if W.intel:
					W.intel.observe(u, Loc.t("дрон (крізь дим)"), minf(q, (1.0 - smoke) * 0.85))
			elif q >= AIConfig.INTEL_CONFIRM_Q:
				W.command.reveal(u, 6.0, Loc.t("дрон"), q)
			elif W.intel:
				W.intel.observe(u, Loc.t("дрон (поганий сигнал)"), q)
	if W.ew:
		for st in W.ew.stations:
			if st.destroyed or st.ever_seen:
				continue
			var sp2: Vector3 = st.global_position + Vector3(0, 3, 0)
			if cam.is_position_behind(sp2):
				continue
			var s2 := cam.unproject_position(sp2)
			if s2.x < 0 or s2.y < 0 or s2.x > sz.x or s2.y > sz.y:
				continue
			if W.field and W.field.smoke_opacity(cpos, sp2) > AIConfig.SMOKE_DRONE_VAGUE:
				continue
			if cpos.distance_to(sp2) / zk < 110.0 and W.ew.link > 0.4 and randf() < 0.06 * W.ew.link:
				st.ever_seen = true
				Events.msg(Loc.t("Дрон: виявлено станцію РЕБ противника — уразити можна FPV-дроном"), "warn")
	for bk in W.bunkers:
		if bk.destroyed or bk.ever_seen:
			continue
		var p2: Vector3 = bk.global_position
		if cam.is_position_behind(p2):
			continue
		var sp3 := cam.unproject_position(p2)
		if sp3.x < 0 or sp3.y < 0 or sp3.x > sz.x or sp3.y > sz.y:
			continue
		if W.field and W.field.smoke_opacity(cpos, p2 + Vector3(0, 0.8, 0)) > AIConfig.SMOKE_DRONE_VAGUE:
			continue
		if cpos.distance_to(p2) / zk < 90.0 and randf() < 0.12:
			bk.ever_seen = true
			Events.msg(Loc.t("Дрон: виявлено %s") % bk.title.to_lower(), "warn")
