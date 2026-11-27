@tool
class_name MapBunker
extends MapNode
## ДЗОТ або бліндаж противника, у якому сидить загін. Амбразура дивиться вздовж −Z вузла (синя стрілка Godot у протилежний бік).

## mg — кулеметний ДЗОТ, dugout — бліндаж.
@export_enum("mg", "dugout") var kind: String = "mg":
	set(v):
		kind = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": box(Vector3(4.2, 1.6, 3.4)), "color": Color(0.35, 0.25, 0.15), "y": 0.8, "text": "ДЗОТ" if kind == "mg" else "Бліндаж"}


func _model() -> Node3D:
	return Props.bunker(kind, MapModels.obj_rng(_seed(), _pos2()))
