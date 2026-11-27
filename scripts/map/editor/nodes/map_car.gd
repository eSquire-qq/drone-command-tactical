@tool
class_name MapCar
extends MapNode
## Згоріла автівка: укриття, перешкода для техніки й піхоти. Поворот — обертанням вузла.


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": box(Vector3(1.8, 1.4, 4.2)), "color": Color(0.3, 0.25, 0.2), "y": 0.7, "text": ""}


func _model() -> Node3D:
	return MapModels.car(_seed(), _pos2())
