@tool
class_name MapSmokeColumn
extends MapNode
## Стовп диму від пожежі (лише вигляд).



func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": cyl(0.6, 8.0), "color": Color(0.5, 0.5, 0.5, 0.4), "y": 4.0, "text": ""}
