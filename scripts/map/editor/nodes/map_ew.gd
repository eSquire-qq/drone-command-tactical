@tool
class_name MapEW
extends MapNode
## Станція РЕБ противника.

## station — справжня, decoy — макет, backup — місце для запасної.
@export_enum("station", "decoy", "backup") var kind: String = "station":
	set(v):
		kind = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": cyl(0.5, 4.0), "color": {"station": Color(0.9, 0.2, 0.2), "decoy": Color(0.9, 0.6, 0.2), "backup": Color(0.6, 0.6, 0.6)}[kind], "y": 2.0, "text": {"station": "РЕБ", "decoy": "РЕБ (макет)", "backup": "РЕБ (запасна)"}[kind]}


func _model() -> Node3D:
	return MapModels.ew_station(MapModels.obj_rng(_seed(), _pos2()))
