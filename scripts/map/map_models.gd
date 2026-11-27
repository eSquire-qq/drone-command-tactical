@tool
class_name MapModels
extends RefCounted
## Models of the point objects of a map (houses, sheds, bales, poles,
## sandbags, wrecks, dugouts, jammers). Each one is built from its own random
## numbers seeded by the map seed and its position, so the Godot editor
## (MapNode) and the game (MapManager) build exactly the same thing.


static func obj_rng(seed: int, p: Vector2) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed, int(round(p.x * 10.0)), int(round(p.y * 10.0))])
	return r


static func house(seed: int, h: Dictionary) -> Dictionary:
	return Props.ruined_house(h["size"], h["ruin"], obj_rng(seed, h["pos"]))


static func apartment(seed: int, a: Dictionary) -> Dictionary:
	return Props.apartment(a["size"], int(a.get("floors", 4)), float(a.get("ruin", 0.3)), obj_rng(seed, a["pos"]))


static func car(seed: int, p: Vector2) -> Node3D:
	return Props.car_wreck(obj_rng(seed, p))


static func shed(seed: int, s: Dictionary) -> Dictionary:
	return Props.shed(s["size"], obj_rng(seed, s["pos"]))


## A hay bale lying at a random angle (the wrapper keeps the map position).
static func bale(seed: int, p: Vector2) -> Node3D:
	var r := obj_rng(seed, p)
	var root := Node3D.new()
	var b := Props.hay_bale(r)
	b.rotation.y = r.randf() * TAU
	root.add_child(b)
	return root


static func pole(seed: int, p: Vector2) -> Node3D:
	var r := obj_rng(seed, p)
	var root := Node3D.new()
	var n := Props.pole(r, r.randf() < 0.3)
	n.rotation.y = r.randf_range(-0.2, 0.2)
	root.add_child(n)
	return root


static func sandbags(seed: int, sb: Dictionary) -> Node3D:
	return Props.sandbags(sb["len"], obj_rng(seed, sb["pos"]))


## A burnt-out vehicle, sunk a little and tilted.
static func wreck(model: String) -> Node3D:
	var root := Node3D.new()
	var vm := VehicleModel.new()
	vm.build(model, 0, true)
	vm.position = Vector3(0, -0.15, 0)
	vm.rotation = Vector3(0.04, 0, -0.06)
	root.add_child(vm)
	return root


## Log-roofed dugout: earth mound, logs across the top, dark entrance (+Z).
static func dugout(seed: int, d: Dictionary, spoil: Color) -> Node3D:
	var r := obj_rng(seed, d["pos"])
	var sz: Vector2 = d.get("size", Vector2(3.6, 3.0))
	var root := Node3D.new()
	MF.part(root, MF.box(sz.x + 1.4, 0.55, sz.y + 1.4), MF.mat(spoil.darkened(0.05)), Vector3(0, 0.18, 0))
	MF.part(root, MF.box(sz.x + 0.6, 0.3, sz.y + 0.6), MF.mat(spoil.lerp(Color(0.35, 0.38, 0.22), 0.35)), Vector3(0, 0.55, 0))
	var log_mesh := MF.cyl(0.13, 0.13, 1.0, 6)
	var lz := -sz.y * 0.5
	while lz <= sz.y * 0.5:
		MF.part(root, log_mesh, MF.mat(Color(0.36, 0.28, 0.19).darkened(r.randf() * 0.2)), Vector3(0, 0.72, lz),
			Vector3(0, 0, PI * 0.5), Vector3(1, sz.x + 1.0, 1))
		lz += 0.6
	MF.part(root, MF.box(1.0, 0.9, 0.12), MF.mat(Color(0.06, 0.05, 0.04)), Vector3(0, 0.05, sz.y * 0.5 + 0.72))
	return root


## Enemy jammer: equipment box, mast with antennas, camouflage net.
static func ew_station(rng: RandomNumberGenerator) -> Node3D:
	var model := Node3D.new()
	var m_box = MF.mat(Color(0.30, 0.32, 0.24))
	var m_dark = MF.mat(Color(0.12, 0.12, 0.12), 0.5, 0.5)
	var m_net = MF.mat(Color(0.28, 0.32, 0.17))
	MF.part(model, MF.box(1.6, 1.0, 1.1), m_box, Vector3(0, 0.5, 0))
	MF.part(model, MF.box(0.5, 0.25, 0.4), m_dark, Vector3(0.3, 1.12, 0.1), Vector3.ZERO, Vector3.ONE, false)
	MF.part(model, MF.cyl(0.05, 0.08, 7.0, 6), m_dark, Vector3(-0.5, 3.5, 0))
	for i in 3:
		var y = 4.6 + i * 0.9
		MF.part(model, MF.box(1.4 - i * 0.3, 0.04, 0.04), m_dark, Vector3(-0.5, y, 0), Vector3(0, i * 0.9, 0), Vector3.ONE, false)
	for k in 3:
		var a = k * TAU / 3.0
		MF.part(model, MF.cyl(0.015, 0.015, 4.2, 4), m_dark, Vector3(-0.5 + cos(a) * 1.0, 2.0, sin(a) * 1.0),
			Vector3(sin(a) * 0.25, 0, -cos(a) * 0.25), Vector3.ONE, false)
	MF.part(model, MF.sphere(1.0, 2.0, 7, 3, true, 0.12, rng.randi()), m_net, Vector3(0.1, 0.9, 0), Vector3.ZERO, Vector3(1.6, 0.6, 1.3), false)
	return model
