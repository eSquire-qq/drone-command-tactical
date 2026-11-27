@tool
class_name MapBale
extends MapNode
## Тюк сіна: слабке укриття, легко руйнується.



func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": box(Vector3(1.2, 1.5, 1.5)), "color": Color(0.8, 0.7, 0.35), "y": 0.75, "text": ""}


func _model() -> Node3D:
	return MapModels.bale(_seed(), _pos2())
