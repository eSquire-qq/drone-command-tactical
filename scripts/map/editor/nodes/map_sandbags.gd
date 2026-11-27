@tool
class_name MapSandbags
extends MapNode
## Мішки з піском: добре укриття, вибухи їх розбивають. Поворот — обертанням вузла.

## Довжина, м.
@export_range(1.0, 12.0, 0.5) var length: float = 4.0:
	set(v):
		length = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": box(Vector3(length, 0.7, 0.45)), "color": Color(0.75, 0.68, 0.5), "y": 0.35, "text": ""}


func _model() -> Node3D:
	return MapModels.sandbags(_seed(), {"pos": _pos2(), "len": length})
