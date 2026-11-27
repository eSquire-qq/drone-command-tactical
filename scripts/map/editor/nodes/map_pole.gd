@tool
class_name MapPole
extends MapNode
## Стовп лінії електропередач (деякі зламані — випадково).

func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": cyl(0.15, 7.5), "color": Color(0.4, 0.35, 0.3), "y": 3.75, "text": ""}


func _model() -> Node3D:
	return MapModels.pole(_seed(), _pos2())
