@tool
class_name MF
extends RefCounted
## Mesh factory: cached low-poly meshes and materials, flat-shading helpers.

static var _mats := {}
static var _meshes := {}


static func mat(c: Color, rough: float = 0.92, metal: float = 0.0) -> StandardMaterial3D:
	var key := "m%s_%.2f_%.2f" % [c.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


static func glow(c: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "g%s_%.2f" % [c.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


static func vcol(rough: float = 0.95, transparent: bool = false, unshaded: bool = false) -> StandardMaterial3D:
	var key := "vc%.2f_%s_%s" % [rough, transparent, unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


static func box(x: float, y: float, z: float) -> Mesh:
	var key := "box%.3f_%.3f_%.3f" % [x, y, z]
	if _meshes.has(key):
		return _meshes[key]
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	_meshes[key] = b
	return b


static func sphere(r: float, h: float, seg: int = 7, rings: int = 4, hemi: bool = false, jitter: float = 0.0, seed: int = 0) -> Mesh:
	var key := "sph%.3f_%.3f_%d_%d_%s_%.3f_%d" % [r, h, seg, rings, hemi, jitter, seed]
	if _meshes.has(key):
		return _meshes[key]
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = seg
	s.rings = rings
	s.is_hemisphere = hemi
	var m := flat(s, jitter, seed)
	_meshes[key] = m
	return m


static func cyl(rt: float, rb: float, h: float, seg: int = 6) -> Mesh:
	var key := "cyl%.3f_%.3f_%.3f_%d" % [rt, rb, h, seg]
	if _meshes.has(key):
		return _meshes[key]
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	var m := flat(c)
	_meshes[key] = m
	return m


static func torus(inner: float, outer: float, rings: int = 12, segs: int = 4) -> Mesh:
	var key := "tor%.3f_%.3f_%d_%d" % [inner, outer, rings, segs]
	if _meshes.has(key):
		return _meshes[key]
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = rings
	t.ring_segments = segs
	_meshes[key] = t
	return t


## Converts any mesh to a flat-shaded (faceted) ArrayMesh, optionally
## jittering vertices for an organic low-poly look.
static func flat(src: Mesh, jitter: float = 0.0, seed: int = 0) -> ArrayMesh:
	var arr := src.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = PackedInt32Array()
	if arr[Mesh.ARRAY_INDEX] != null:
		idx = arr[Mesh.ARRAY_INDEX]
	if jitter > 0.0:
		var rng := RandomNumberGenerator.new()
		for i in v.size():
			var p := v[i]
			rng.seed = hash(Vector3i(roundi(p.x * 997.0), roundi(p.y * 997.0), roundi(p.z * 997.0))) + seed
			v[i] = p + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * jitter
	var count := idx.size() if idx.size() > 0 else v.size()
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	ov.resize(count)
	on.resize(count)
	var i := 0
	while i + 2 < count:
		var a: Vector3
		var b: Vector3
		var c: Vector3
		if idx.size() > 0:
			a = v[idx[i]]
			b = v[idx[i + 1]]
			c = v[idx[i + 2]]
		else:
			a = v[i]
			b = v[i + 1]
			c = v[i + 2]
		var nrm := (c - a).cross(b - a)
		if nrm.length_squared() > 0.0:
			nrm = nrm.normalized()
		else:
			nrm = Vector3.UP
		ov[i] = a
		ov[i + 1] = b
		ov[i + 2] = c
		on[i] = nrm
		on[i + 1] = nrm
		on[i + 2] = nrm
		i += 3
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = ov
	out[Mesh.ARRAY_NORMAL] = on
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return am


static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO,
		rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation = rot
	parent.add_child(n)
	return n


static func yaw_facing(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
