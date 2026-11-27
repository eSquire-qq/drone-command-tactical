@tool
class_name MapBurnt
extends MapNode
## Випалена земля (лише вигляд).

## Радіус плями, м.
@export_range(1.0, 20.0, 0.5) var radius: float = 5.0:
	set(v):
		radius = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": cyl(radius, 0.1), "color": Color(0.1, 0.08, 0.07, 0.12), "y": 0.1, "text": ""}
