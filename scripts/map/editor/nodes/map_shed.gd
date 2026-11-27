@tool
class_name MapShed
extends MapNode
## Сарай / господарська будівля (дощані стіни слабші за цегляні).

## Розмір, м.
@export var size: Vector2 = Vector2(6, 5):
	set(v):
		size = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": box(Vector3(size.x, 2.6, size.y)), "color": Color(0.6, 0.45, 0.3, 0.7), "y": 1.3, "text": "Сарай"}


func _model() -> Node3D:
	return MapModels.shed(_seed(), {"pos": _pos2(), "size": size})["node"]
