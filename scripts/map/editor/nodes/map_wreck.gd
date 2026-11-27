@tool
class_name MapWreck
extends MapNode
## Підбита техніка (укриття, перешкода). Поворот — обертанням вузла.

## Модель.
@export_enum("bmp1", "bmp2", "m113") var model: String = "bmp1":
	set(v):
		model = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": box(Vector3(3.0, 2.0, 6.5)), "color": Color(0.25, 0.22, 0.2), "y": 1.0, "text": "Підбита %s" % model}


func _model() -> Node3D:
	return MapModels.wreck(model)
