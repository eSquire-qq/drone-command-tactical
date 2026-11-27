@tool
class_name MapBush
extends MapNode
## Кущ (маскування, трохи укриття).

## Радіус куща, м.
@export_range(0.5, 6.0, 0.1) var radius: float = 2.0:
	set(v):
		radius = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": cyl(radius, 1.4), "color": Color(0.3, 0.75, 0.3, 0.12), "y": 0.7, "text": ""}
