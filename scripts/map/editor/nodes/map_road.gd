@tool
class_name MapRoad
extends MapPath
## Дорога (техніка їде швидше, дерева й кущі на ній прибираються).

## Ширина, м.
@export_range(1.5, 10.0, 0.1) var width: float = 3.5:
	set(v):
		width = v
		_touch()


func _touch() -> void:
	redraw()


func _style() -> Dictionary:
	return {"color": Color(0.55, 0.45, 0.32, 0.18), "width": width, "text": "Дорога"}
