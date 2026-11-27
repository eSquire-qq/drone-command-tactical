@tool
class_name MapCamo
extends MapNode
## Підготовлене маскування (сітки, дерн): нерухомого бійця тут дуже важко помітити.

## Радіус, м.
@export_range(1.0, 20.0, 0.5) var radius: float = 3.0:
	set(v):
		radius = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": ring(radius, 0.2), "color": Color(0.5, 0.6, 0.3, 0.8), "y": 0.15, "text": "маск."}
