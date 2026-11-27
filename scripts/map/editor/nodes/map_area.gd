@tool
class_name MapArea
extends MapNode
## Зона місії: ціль, зона захоплення, пристріляна зона мінометів противника (прямокутник X×Z, поворот не враховується).

## objective — ціль (показується на карті), capture — де рахується захоплення, mortar_zone — пристріляне поле,
## deploy_zone — де гравець може вільно обрати точку висадки на брифінгу.
@export_enum("objective", "capture", "mortar_zone", "deploy_zone") var kind: String = "objective":
	set(v):
		kind = v
		_touch()
## Розмір, м.
@export var size: Vector2 = Vector2(40, 20):
	set(v):
		size = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	# a frame on the ground, not a filled box: the ground stays visible
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var c := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	for k in 4:
		for off in [0.0, 0.25, 0.5]:
			im.surface_add_vertex(c[k] + Vector3(0, off, 0))
			im.surface_add_vertex(c[(k + 1) % 4] + Vector3(0, off, 0))
	im.surface_end()
	var col: Color = {"objective": Color(1, 0.85, 0.2), "capture": Color(1, 0.55, 0.2), "mortar_zone": Color(1, 0.3, 0.25), "deploy_zone": Color(0.35, 0.72, 1.0)}[kind]
	return {"mesh": im, "color": col, "y": 0.3, "label_y": 1.5,
		"text": {"objective": "ЦІЛЬ", "capture": "Зона захоплення", "mortar_zone": "Пристріляна зона", "deploy_zone": "Зона висадки"}[kind]}
