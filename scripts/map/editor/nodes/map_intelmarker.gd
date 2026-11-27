@tool
class_name MapIntelMarker
extends MapNode
## Позначка розвідданих на знімку брифінгу (не сам противник!).

## Підпис.
@export var label: String = "ПОСТ":
	set(v):
		label = v
		_touch()
## Радіус кола, м.
@export_range(2.0, 60.0, 0.5) var radius: float = 8.0:
	set(v):
		radius = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": ring(radius, 0.25), "color": Color(1, 0.85, 0.3, 0.8), "y": 0.3, "text": "розвідка: " + label}
