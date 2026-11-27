@tool
class_name MapHouse
extends MapNode
## Будинок (зруйнований): стіни дають укриття, вибухи їх руйнують і пробивають проломи.
## Поворот — обертанням вузла навколо Y.

## Розмір будинку, м.
@export var size: Vector2 = Vector2(8, 6):
	set(v):
		size = v
		_touch()
## Наскільки зруйнований 0..1 (понад 0.7 — без даху).
@export_range(0.0, 1.0, 0.05) var ruin: float = 0.5:
	set(v):
		ruin = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": box(Vector3(size.x, 3.0, size.y)), "color": Color(0.85, 0.8, 0.7, 0.7), "y": 1.5, "text": "Будинок"}


func _model() -> Node3D:
	return MapModels.house(_seed(), {"pos": _pos2(), "size": size, "ruin": ruin})["node"]
