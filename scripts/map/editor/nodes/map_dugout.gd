@tool
class_name MapDugout
extends MapNode
## Перекрите бліндажне укриття (земляний горб з колод). Поворот — обертанням вузла.

## Розмір, м.
@export var size: Vector2 = Vector2(3.6, 3.0):
	set(v):
		size = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": box(Vector3(size.x + 1.4, 0.8, size.y + 1.4)), "color": Color(0.45, 0.36, 0.25), "y": 0.4, "text": "Бліндаж"}


func _model() -> Node3D:
	var r = map_root()
	return MapModels.dugout(_seed(), {"pos": _pos2(), "size": size}, r.spoil_color() if r else Color(0.52, 0.48, 0.33))
