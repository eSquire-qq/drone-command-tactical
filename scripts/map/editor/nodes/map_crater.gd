@tool
class_name MapCrater
extends MapNode
## Стара вирва (на початку бою вже є).

## Радіус вирви, м. Від 2.0 — непрохідна для легкої техніки, від 2.7 — для гусеничної.
@export_range(0.6, 5.0, 0.1) var radius: float = 2.0:
	set(v):
		radius = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": ring(radius, 0.12), "color": Color(0.9, 0.6, 0.3, 0.35), "y": 0.2, "text": ""}
