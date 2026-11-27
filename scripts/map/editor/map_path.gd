@tool
class_name MapPath
extends Path3D
## Base of line objects on an editor map (roads, trenches, wire, fences,
## minefields, ridges). Draw the line with the Path3D tools: add points in the
## viewport, drag them. Only X/Z of the points matter in the game. In the
## editor the line is shown as a coloured ribbon lying on the previewed ground.

var _gz: MeshInstance3D
var _lb: Label3D


func _ready() -> void:
	if MapScene.editing():
		if curve == null:
			curve = Curve3D.new()
		if not curve.changed.is_connected(_on_curve):
			curve.changed.connect(_on_curve)
		set_notify_transform(true)
		redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and MapScene.editing():
		_on_curve()


func _on_curve() -> void:
	redraw()
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


## Ribbon look: override. {"color": Color, "width": float, "text": String}
func _style() -> Dictionary:
	return {"color": Color(1, 1, 1), "width": 1.0}


## Points of the line in the map's X/Z (local to the MapScene root).
func points_2d(root_xf: Transform3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	if curve == null:
		return out
	for i in curve.point_count:
		var p: Vector3 = root_xf * curve.get_point_position(i)
		out.append(Vector2(p.x, p.z))
	return out


func redraw() -> void:
	if not MapScene.editing() or not is_inside_tree() or curve == null:
		return
	var st := _style()
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
	var root = map_root()
	var w: float = float(st.get("width", 1.0)) * 0.5
	var c: Color = st.get("color", Color.WHITE)
	var im := ImmediateMesh.new()
	var n := curve.point_count
	if n >= 2:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		# densify so the ribbon follows the ground between far-apart points
		var pts: Array = []
		for i in n - 1:
			var a := curve.get_point_position(i)
			var b := curve.get_point_position(i + 1)
			var steps := maxi(1, int(a.distance_to(b) / 3.0))
			for k in steps:
				pts.append(a.lerp(b, float(k) / steps))
		pts.append(curve.get_point_position(n - 1))
		for i in pts.size():
			var p: Vector3 = pts[i]
			var d: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)])
			d.y = 0.0
			var side := Vector3(-d.z, 0, d.x).normalized() * w
			for q in [p + side, p - side]:
				var gq: Vector3 = q
				if root:
					var gp: Vector3 = global_transform * q
					gq.y = (global_transform.affine_inverse() * Vector3(gp.x, root.preview_height_global(gp.x, gp.z) + 0.25, gp.z)).y
				im.surface_add_vertex(gq)
		im.surface_end()
	_gz.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if c.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_gz.material_override = mat
	_lb.text = String(st.get("text", name))
	_lb.visible = _lb.text != "" and (root == null or root.show_labels)
	_lb.modulate = c.lightened(0.3)
	_lb.modulate.a = 1.0
	if n > 0:
		var p0 := curve.get_point_position(0)
		_lb.position = p0 + Vector3(0, 3.0, 0)
		if root:
			var gp0: Vector3 = global_transform * p0
			_lb.position.y = (global_transform.affine_inverse() * Vector3(gp0.x, root.preview_height_global(gp0.x, gp0.z) + 3.0, gp0.z)).y
