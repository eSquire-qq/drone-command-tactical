@tool
class_name MapHill
extends MapNode
## Рельєф: пагорб (висота > 0) або западина (висота < 0). Еліпс, поворот — обертанням вузла.
## Мʼякий схил (гаусів профіль): на відстані радіуса висота ~37 %.

## Радіус по X, м.
@export_range(2.0, 200.0, 0.5) var radius_x: float = 20.0:
	set(v):
		radius_x = v
		_touch()
## Радіус по Z, м.
@export_range(2.0, 200.0, 0.5) var radius_z: float = 20.0:
	set(v):
		radius_z = v
		_touch()
## Висота, м (мінус — западина).
@export_range(-15.0, 25.0, 0.1) var height: float = 3.0:
	set(v):
		height = v
		_touch()


func _touch() -> void:
	redraw()
	var r = map_root()
	if r:
		r.on_child_moved(self)


func _gizmo() -> Dictionary:
	var t := ring(1.0, 0.04)
	return {"mesh": t, "color": Color(0.3, 0.9, 0.4) if height >= 0.0 else Color(0.3, 0.6, 1.0), "y": 0.3,
		"text": "%s %+.1f м" % ["Пагорб" if height >= 0.0 else "Западина", height], "rot": Vector3.ZERO, "scale": Vector3(radius_x, 1.0, radius_z)}
