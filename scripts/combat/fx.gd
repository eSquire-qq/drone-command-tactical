class_name FxSystem
extends Node3D
## Visual effects: tracers, muzzle flashes, impacts, explosions, smoke
## screens, fires, scorch decals and generic ballistic projectiles.

var tracers: Array = []
var tracer_pool: Array = []
var flashes: Array = []
var flash_pool: Array = []
var dust_pool: Array = []
var dust_i := 0
var expl_pool: Array = []
var expl_i := 0
var spark_pool: Array = []
var spark_i := 0
var projectiles: Array = []
var timed: Array = []    # {node, end}
var decals: Array = []
var scorch_tex: GradientTexture2D

var m_tr_f: StandardMaterial3D
var m_tr_e: StandardMaterial3D
var m_flash: StandardMaterial3D
var puff_mesh: Mesh
var chunk_mesh: Mesh


func _ready() -> void:
	m_tr_f = MF.glow(Color(1.0, 0.72, 0.30), 6.0)
	m_tr_e = MF.glow(Color(0.55, 1.0, 0.45), 6.0)
	m_flash = MF.glow(Color(1.0, 0.8, 0.45), 8.0)
	puff_mesh = MF.sphere(0.5, 1.0, 9, 5)
	chunk_mesh = MF.box(0.18, 0.12, 0.16)
	for i in 60:
		var mi := MeshInstance3D.new()
		mi.mesh = MF.box(0.05, 0.05, 2.4)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		tracer_pool.append(mi)
	for i in 30:
		var mi := MeshInstance3D.new()
		mi.mesh = MF.sphere(0.5, 1.0, 5, 3)
		mi.material_override = m_flash
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		flash_pool.append(mi)
	for i in 28:
		dust_pool.append(_make_dust())
	for i in 10:
		expl_pool.append(_make_explosion())
	for i in 6:
		spark_pool.append(_make_sparks())
	scorch_tex = GradientTexture2D.new()
	scorch_tex.fill = GradientTexture2D.FILL_RADIAL
	scorch_tex.fill_from = Vector2(0.5, 0.5)
	scorch_tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(0.06, 0.05, 0.04, 0.9))
	g.set_color(1, Color(0.1, 0.08, 0.06, 0.0))
	g.add_point(0.55, Color(0.10, 0.08, 0.06, 0.65))
	scorch_tex.gradient = g
	scorch_tex.width = 64
	scorch_tex.height = 64


# ------------------------------------------------------------------ builders
func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, cols[0])
	g.set_color(1, cols[cols.size() - 1])
	for i in range(1, cols.size() - 1):
		g.add_point(float(i) / (cols.size() - 1), cols[i])
	return g


func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	return c


func _particles(amount: int, life: float, mesh: Mesh, ramp: Gradient, vmin: float, vmax: float,
		spread: float, gravity: Vector3, smin: float, smax: float, scurve: Curve, unshaded: bool = false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.emitting = false
	p.mesh = mesh
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = gravity
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	if scurve:
		p.scale_amount_curve = scurve
	p.color_ramp = ramp
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.material_override = MF.vcol(1.0, true, unshaded)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _make_dust() -> CPUParticles3D:
	var p := _particles(7, 1.1, puff_mesh, _ramp([Color(0.45, 0.38, 0.28, 0.8), Color(0.5, 0.44, 0.34, 0.0)]),
		1.0, 3.0, 35.0, Vector3(0, -2.0, 0), 0.25, 0.6, _curve([Vector2(0, 0.5), Vector2(1, 1.4)]))
	add_child(p)
	return p


func _make_sparks() -> CPUParticles3D:
	var p := _particles(14, 0.5, MF.box(0.06, 0.06, 0.06), _ramp([Color(1, 0.9, 0.5, 1), Color(1, 0.4, 0.1, 0)]),
		4.0, 9.0, 80.0, Vector3(0, -9.0, 0), 0.6, 1.2, null, true)
	add_child(p)
	return p


func _make_explosion() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var fire := _particles(14, 0.55, puff_mesh, _ramp([Color(1, 0.95, 0.6, 1), Color(1, 0.55, 0.15, 0.9), Color(0.3, 0.2, 0.15, 0)]),
		3.0, 8.0, 70.0, Vector3(0, 2.0, 0), 0.9, 2.0, _curve([Vector2(0, 0.6), Vector2(1, 1.4)]), true)
	root.add_child(fire)
	var smoke := _particles(18, 4.5, puff_mesh, _ramp([Color(0.25, 0.23, 0.21, 0.85), Color(0.42, 0.40, 0.37, 0.5), Color(0.5, 0.48, 0.45, 0.0)]),
		1.5, 5.0, 50.0, Vector3(0.6, 1.2, 0.2), 1.2, 2.6, _curve([Vector2(0, 0.5), Vector2(1, 2.4)]))
	smoke.explosiveness = 0.75
	root.add_child(smoke)
	var debris := _particles(16, 1.6, chunk_mesh, _ramp([Color(0.25, 0.2, 0.15, 1), Color(0.25, 0.2, 0.15, 1)]),
		5.0, 12.0, 40.0, Vector3(0, -14.0, 0), 0.6, 1.6, null)
	debris.damping_min = 0.0
	debris.damping_max = 0.2
	debris.angular_velocity_min = -400
	debris.angular_velocity_max = 400
	root.add_child(debris)
	var dust := _particles(12, 2.2, puff_mesh, _ramp([Color(0.48, 0.41, 0.31, 0.7), Color(0.55, 0.5, 0.4, 0)]),
		4.0, 7.0, 90.0, Vector3(0, -0.5, 0), 1.0, 2.0, _curve([Vector2(0, 0.6), Vector2(1, 2.0)]))
	dust.direction = Vector3(0, 0.15, 1)
	dust.flatness = 0.9
	root.add_child(dust)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 0.0
	light.omni_range = 14.0
	light.shadow_enabled = false
	root.add_child(light)
	return {"root": root, "fire": fire, "smoke": smoke, "debris": debris, "dust": dust, "light": light}


## Fires every effect once while the menu / briefing is on screen, deep
## underground but inside the camera frustum: the GPU compiles the shaders
## now instead of freezing the first time a shell lands in battle.
func prewarm() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if W.cam == null or W.cam.cam == null:
		return
	var c: Camera3D = W.cam.cam
	var vp := get_viewport().get_visible_rect().size
	var p := c.project_position(vp * 0.5, minf(c.far * 0.8, 900.0))
	p.y = minf(p.y, W.grid.height_at(p.x, p.z) - 40.0) if W.grid else p.y
	explosion(p, 3.0)
	impact(p)
	sparks(p)
	tracer(p, p + Vector3(5, 0, 0), true)
	tracer(p, p + Vector3(0, 0, 5), false)
	muzzle_flash(p, true)
	var b := burning(p, true)
	smoke_screen(p, 4.0, 1.0)
	launch(p, p + Vector3(3, 0, 0), 0.5, 1.0, "mortar", func(_a = null): pass)
	await get_tree().create_timer(1.5, true, false, true).timeout
	if is_instance_valid(b):
		b.queue_free()


# ------------------------------------------------------------------ api
func tracer(from: Vector3, to: Vector3, friendly: bool, heavy: bool = false) -> void:
	if tracer_pool.is_empty():
		return
	var mi: MeshInstance3D = tracer_pool.pop_back()
	mi.material_override = m_tr_f if friendly else m_tr_e
	mi.visible = true
	mi.scale = Vector3(2.0, 2.0, 1.4) if heavy else Vector3.ONE
	var dir := (to - from)
	var L := dir.length()
	if L < 0.5:
		tracer_pool.append(mi)
		mi.visible = false
		return
	dir /= L
	mi.global_position = from
	mi.look_at(from + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	tracers.append({"m": mi, "from": from, "dir": dir, "len": L, "t": 0.0})


func muzzle_flash(pos: Vector3, big: bool = false) -> void:
	if flash_pool.is_empty():
		return
	var mi: MeshInstance3D = flash_pool.pop_back()
	mi.visible = true
	mi.global_position = pos
	mi.scale = Vector3.ONE * (0.7 if big else 0.32) * randf_range(0.8, 1.2)
	flashes.append({"m": mi, "t": 0.05 if not big else 0.09})


func impact(pos: Vector3) -> void:
	var p: CPUParticles3D = dust_pool[dust_i]
	dust_i = (dust_i + 1) % dust_pool.size()
	p.global_position = pos
	p.restart()


func sparks(pos: Vector3) -> void:
	var p: CPUParticles3D = spark_pool[spark_i]
	spark_i = (spark_i + 1) % spark_pool.size()
	p.global_position = pos
	p.restart()


func explosion(pos: Vector3, radius: float) -> void:
	var e: Dictionary = expl_pool[expl_i]
	expl_i = (expl_i + 1) % expl_pool.size()
	var root: Node3D = e["root"]
	root.global_position = pos
	var k := clampf(radius / 4.0, 0.5, 1.8)
	for key in ["fire", "smoke", "debris", "dust"]:
		var p: CPUParticles3D = e[key]
		p.scale_amount_min = (0.9 if key == "fire" else 1.0) * k
		p.scale_amount_max = (2.0 if key != "debris" else 1.6) * k
		p.initial_velocity_max = (8.0 if key == "fire" else 7.0) * sqrt(k)
		p.restart()
	var light: OmniLight3D = e["light"]
	light.omni_range = 10.0 * k + 4.0
	light.light_energy = 9.0
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	if radius >= 2.0:
		scorch(pos, radius * 0.8)


func scorch(pos: Vector3, radius: float) -> void:
	var d := Decal.new()
	d.texture_albedo = scorch_tex
	d.size = Vector3(radius * 2.0, 4.0, radius * 2.0)
	d.cull_mask = 1
	d.rotation.y = randf() * TAU
	add_child(d)
	d.global_position = pos
	decals.append(d)
	if decals.size() > 60:
		var old: Node = decals.pop_front()
		old.queue_free()


func smoke_screen(pos: Vector3, radius: float, duration: float) -> Node3D:
	var p := CPUParticles3D.new()
	p.amount = int(clampf(radius * 6.0, 24, 70))
	p.lifetime = 7.0
	p.one_shot = false
	p.explosiveness = 0.0
	p.mesh = puff_mesh
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.55
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0.5, 0.25, 0.15)
	p.scale_amount_min = radius * 0.28
	p.scale_amount_max = radius * 0.5
	p.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(0.3, 1.0), Vector2(1, 1.3)])
	p.color_ramp = _ramp([Color(0.62, 0.63, 0.61, 0.0), Color(0.66, 0.67, 0.65, 0.55), Color(0.60, 0.60, 0.58, 0.42), Color(0.56, 0.56, 0.54, 0.0)])
	p.material_override = MF.vcol(1.0, true, false)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos + Vector3(0, radius * 0.3, 0)
	p.emitting = true
	timed.append({"node": p, "stop": W.time + duration, "end": W.time + duration + 8.0})
	return p


## Persistent fire + smoke column. small=true for ambient smoulder.
## Fires burn till the end of the battle: their lights and CPU particles are
## budgeted by the graphics preset (only the first few fires cast light).
var _fire_lights: Array = []


func burning(pos: Vector3, big: bool, ambient: bool = false) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var q: Dictionary = Game.quality()
	var k: float = float(q.get("fx", 1.0))
	if not ambient:
		var fire := CPUParticles3D.new()
		fire.amount = maxi(4, int((16 if big else 8) * k))
		fire.lifetime = 0.9
		fire.mesh = puff_mesh
		fire.local_coords = false
		fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		fire.emission_sphere_radius = 1.0 if big else 0.5
		fire.direction = Vector3.UP
		fire.spread = 15.0
		fire.initial_velocity_min = 1.5
		fire.initial_velocity_max = 3.0
		fire.gravity = Vector3(0, 1.5, 0)
		fire.scale_amount_min = 0.5
		fire.scale_amount_max = 1.1
		fire.scale_amount_curve = _curve([Vector2(0, 1.0), Vector2(1, 0.2)])
		fire.color_ramp = _ramp([Color(1, 0.9, 0.5, 1), Color(1, 0.45, 0.1, 0.9), Color(0.3, 0.1, 0.05, 0)])
		fire.material_override = MF.vcol(1.0, true, true)
		fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fire)
		_fire_lights = _fire_lights.filter(func(l): return is_instance_valid(l))
		if _fire_lights.size() < int(q.get("fire_lights", 6)):
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.55, 0.2)
			light.light_energy = 2.5 if big else 1.2
			light.omni_range = 9.0
			light.position.y = 1.0
			root.add_child(light)
			_fire_lights.append(light)
			var tw := light.create_tween().set_loops()   # dies with the light
			tw.tween_property(light, "light_energy", light.light_energy * 0.6, 0.12)
			tw.tween_property(light, "light_energy", light.light_energy, 0.15)
	var smoke := CPUParticles3D.new()
	smoke.amount = maxi(6, int((26 if big or ambient else 14) * k))
	smoke.lifetime = 9.0
	smoke.mesh = puff_mesh
	smoke.local_coords = false
	smoke.direction = Vector3.UP
	smoke.spread = 10.0
	smoke.initial_velocity_min = 1.8
	smoke.initial_velocity_max = 2.8
	smoke.gravity = Vector3(0.7, 0.3, 0.25)
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 1.4
	smoke.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 4.0)])
	var dark := 0.16 if not ambient else 0.32
	smoke.color_ramp = _ramp([Color(dark, dark, dark, 0.0), Color(dark, dark * 0.97, dark * 0.95, 0.75), Color(0.45, 0.44, 0.42, 0.35), Color(0.5, 0.5, 0.48, 0.0)])
	smoke.material_override = MF.vcol(1.0, true, false)
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(smoke)
	return root


## Generic projectile. kind: "grenade", "shell", "rocket", "mortar", "fpv".
## homing: optional target object (follows aim_point).
func launch(from: Vector3, to: Vector3, dur: float, arc: float, kind: String, cb: Callable, homing = null, spd: float = 0.0) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_position = from
	var trail: CPUParticles3D = null
	match kind:
		"grenade":
			MF.part(node, MF.sphere(0.09, 0.16, 6, 3), MF.mat(Color(0.2, 0.24, 0.15)), Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 1.6, false)
		"smoke":
			MF.part(node, MF.cyl(0.05, 0.05, 0.16, 6), MF.mat(Color(0.5, 0.55, 0.5)), Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 1.6, false)
		"shell":
			MF.part(node, MF.box(0.08, 0.08, 0.7), MF.glow(Color(1.0, 0.8, 0.4), 5.0), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		"mortar":
			MF.part(node, MF.cyl(0.04, 0.07, 0.45, 6), MF.mat(Color(0.2, 0.22, 0.2)), Vector3.ZERO, Vector3(PI / 2, 0, 0), Vector3.ONE * 1.5, false)
		"rocket":
			MF.part(node, MF.cyl(0.05, 0.05, 0.6, 6), MF.mat(Color(0.25, 0.28, 0.2)), Vector3.ZERO, Vector3(PI / 2, 0, 0), Vector3.ONE, false)
			MF.part(node, MF.sphere(0.12, 0.24, 5, 3), MF.glow(Color(1.0, 0.75, 0.3), 6.0), Vector3(0, 0, 0.35), Vector3.ZERO, Vector3.ONE, false)
			trail = _trail(Color(0.75, 0.74, 0.72))
		"fpv":
			var mdark := MF.mat(Color(0.12, 0.12, 0.12), 0.5, 0.3)
			MF.part(node, MF.box(0.2, 0.08, 0.28), mdark, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 1.6, false)
			for k in 4:
				var ang := PI / 4.0 + k * PI / 2.0
				var off := Vector3(cos(ang), 0, sin(ang)) * 0.28
				MF.part(node, MF.box(0.04, 0.03, 0.4), mdark, off * 0.5 * 1.6, Vector3(0, -ang + PI / 2, 0), Vector3.ONE * 1.6, false)
				MF.part(node, MF.cyl(0.13, 0.13, 0.01, 8), MF.mat(Color(0.3, 0.3, 0.3, 1)), off * 1.6 + Vector3(0, 0.06, 0), Vector3.ZERO, Vector3.ONE * 1.6, false)
			MF.part(node, MF.cyl(0.06, 0.06, 0.25, 6), MF.mat(Color(0.35, 0.38, 0.25)), Vector3(0, -0.1, -0.15), Vector3(PI / 2, 0, 0), Vector3.ONE * 1.6, false)
			MF.part(node, MF.box(0.04, 0.04, 0.04), MF.glow(Color(1, 0.2, 0.1), 4.0), Vector3(0, 0.08, 0.2), Vector3.ZERO, Vector3.ONE * 1.6, false)
	projectiles.append({"node": node, "from": from, "to": to, "t": 0.0, "dur": maxf(dur, 0.05), "arc": arc,
		"cb": cb, "trail": trail, "homing": homing, "spd": spd, "kind": kind})


func _trail(col: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.6
	p.mesh = puff_mesh
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	p.gravity = Vector3(0, 0.4, 0)
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.45
	p.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(1, 2.2)])
	p.color_ramp = _ramp([Color(col.r, col.g, col.b, 0.7), Color(col.r, col.g, col.b, 0.0)])
	p.material_override = MF.vcol(1.0, true, false)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	return p


func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("fx", t0)


func _process_body(delta: float) -> void:
	var paused := not W.running() and not W.photo_mode
	if paused:
		return
	# tracers
	var i := tracers.size() - 1
	while i >= 0:
		var tr: Dictionary = tracers[i]
		tr["t"] += delta * 280.0
		var mi: MeshInstance3D = tr["m"]
		if tr["t"] >= tr["len"]:
			mi.visible = false
			tracer_pool.append(mi)
			tracers.remove_at(i)
		else:
			mi.global_position = tr["from"] + tr["dir"] * tr["t"]
		i -= 1
	i = flashes.size() - 1
	while i >= 0:
		flashes[i]["t"] -= delta
		if flashes[i]["t"] <= 0.0:
			var mi: MeshInstance3D = flashes[i]["m"]
			mi.visible = false
			flash_pool.append(mi)
			flashes.remove_at(i)
		i -= 1
	# projectiles
	i = projectiles.size() - 1
	while i >= 0:
		var pr: Dictionary = projectiles[i]
		var node: Node3D = pr["node"]
		var done := false
		if pr["homing"] != null:
			var h = pr["homing"]
			if is_instance_valid(h) and W.is_alive_target(h):
				pr["to"] = h.aim_point()
			var to: Vector3 = pr["to"]
			var d := to - node.global_position
			var step: float = float(pr["spd"]) * delta
			if d.length() <= step + 0.3:
				node.global_position = to
				done = true
			else:
				var dir := d.normalized()
				node.global_position += dir * step
				# hover wobble for fpv
				node.global_position.y += sin(W.time * 9.0) * 0.02
				node.look_at(node.global_position + dir, Vector3.UP)
		else:
			pr["t"] += delta
			var k: float = clampf(pr["t"] / pr["dur"], 0.0, 1.0)
			var from: Vector3 = pr["from"]
			var to: Vector3 = pr["to"]
			var p := from.lerp(to, k) + Vector3(0, float(pr["arc"]) * 4.0 * k * (1.0 - k), 0)
			var prev := node.global_position
			node.global_position = p
			if (p - prev).length() > 0.001:
				var up := Vector3.UP if absf((p - prev).normalized().y) < 0.99 else Vector3.RIGHT
				node.look_at(p + (p - prev), up)
			done = k >= 1.0
		var trail: CPUParticles3D = pr["trail"]
		if trail:
			trail.global_position = node.global_position
		if done:
			var cb: Callable = pr["cb"]
			var endp := node.global_position
			node.queue_free()
			if trail:
				trail.emitting = false
				timed.append({"node": trail, "stop": W.time, "end": W.time + 2.0})
			projectiles.remove_at(i)
			if cb.is_valid():
				cb.call(endp)
		i -= 1
	# timed nodes
	i = timed.size() - 1
	while i >= 0:
		var td: Dictionary = timed[i]
		if W.time >= float(td["stop"]):
			var n = td["node"]
			if n is CPUParticles3D:
				n.emitting = false
		if W.time >= float(td["end"]):
			td["node"].queue_free()
			timed.remove_at(i)
		i -= 1
