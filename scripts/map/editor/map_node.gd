@tool
class_name MapNode
extends Node3D
## Base of every object placed on an editor map (MapScene). In the editor it
## draws a simple marker (shape + caption) standing on the previewed ground;
## in the game it is only data that MapScene.to_mapdef() reads.
## Only X/Z of the position (and the turn around Y) matter in the game.

var _gz: MeshInstance3D
var _lb: Label3D
var _snapping := false
var _model_node: Node3D
var _model_at := Vector3(INF, 0, INF)   # where the model was built (it depends on the position)


func _ready() -> void:
	if MapScene.editing():
		set_notify_transform(true)
		redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and MapScene.editing() and not _snapping:
		var r = map_root()
		if r:
			r.on_child_moved(self)


func map_root():
	var p := get_parent()
	while p:
		if p is MapScene:
			return p
		p = p.get_parent()
	return null


## Keeps the marker on the previewed ground (editor only); gy is global Y.
func snap_to_ground(gy: float) -> void:
	if absf(global_position.y - gy) < 0.01:
		return
	_snapping = true
	global_position.y = gy
	_snapping = false


## The object's real model as the game builds it (override); null = marker only.
func _model() -> Node3D:
	return null


## The model depends on the position (seeded random details): rebuild after a move.
func model_outdated() -> bool:
	return _model_node != null and Vector2(global_position.x - _model_at.x, global_position.z - _model_at.z).length() > 0.05


## Map seed and position for seeded models.
func _seed() -> int:
	var r = map_root()
	return int(r.seed) if r else 1


func _pos2() -> Vector2:
	var r = map_root()
	if r:
		var l: Vector3 = r.to_local(global_position)
		return Vector2(l.x, l.z)
	return Vector2(position.x, position.z)


## Marker shape: override. {"mesh": Mesh, "color": Color, "y": float, "text": String}
func _gizmo() -> Dictionary:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	return {"mesh": m, "color": Color(1, 1, 1), "y": 0.5}


## Called from property setters: rebuild the marker.
func redraw() -> void:
	if not MapScene.editing() or not is_inside_tree():
		return
	var g := _gizmo()
	if _model_node:
		_model_node.free()
		_model_node = null
	var m := _model()
	if m:
		_model_node = m
		add_child(m, false, Node.INTERNAL_MODE_BACK)
		_model_at = global_position
	if _gz == null:
		_gz = MeshInstance3D.new()
		add_child(_gz, false, Node.INTERNAL_MODE_BACK)
		_lb = Label3D.new()
		_lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_lb.no_depth_test = true
		_lb.font_size = 40
		_lb.pixel_size = 0.01
		_lb.outline_size = 8
		add_child(_lb, false, Node.INTERNAL_MODE_BACK)
	_gz.mesh = null if m else g.get("mesh")
	_gz.position = Vector3(0, float(g.get("y", 0.0)), 0)
	_gz.rotation = g.get("rot", Vector3.ZERO)
	_gz.scale = g.get("scale", Vector3.ONE)
	var mat := StandardMaterial3D.new()
	var c: Color = g.get("color", Color.WHITE)
	mat.albedo_color = c
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_gz.material_override = mat
	_lb.text = String(g.get("text", name))
	_lb.position = Vector3(0, float(g.get("label_y", 2.5)), 0)
	_lb.modulate = c.lightened(0.3)
	_lb.modulate.a = 1.0
	var r = map_root()
	_lb.visible = _lb.text != "" and (r == null or r.show_labels)


static func box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


static func cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 16
	return c


static func ring(r: float, w: float = 0.3) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = maxf(0.05, r - w)
	t.outer_radius = r
	t.rings = 24
	t.ring_segments = 6
	return t
