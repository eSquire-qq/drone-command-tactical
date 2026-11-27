@tool
class_name MapMinefield
extends MapPath
## Мінне поле вздовж лінії.

## Ширина смуги, м.
@export_range(2.0, 20.0, 0.5) var width: float = 6.0:
	set(v):
		width = v
		_touch()
## Мін на м² (0.015 — рідко, 0.05 — щільно).
@export_range(0.005, 0.15, 0.005) var density: float = 0.05:
	set(v):
		density = v
		_touch()
## ap — протипіхотні, at — протитанкові.
@export_enum("ap", "at") var mine_type: String = "ap":
	set(v):
		mine_type = v
		_touch()


func _touch() -> void:
	redraw()


func _style() -> Dictionary:
	return {"color": Color(1, 0.2, 0.2, 0.16) if mine_type == "ap" else Color(1, 0.5, 0.1, 0.16), "width": width, "text": "Міни " + mine_type.to_upper()}
