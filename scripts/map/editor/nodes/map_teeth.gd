@tool
class_name MapTeeth
extends MapPath
## «Зуби дракона»: техніка не пройде, піхота — повільно.

## Рядів.
@export_range(1, 4) var rows: int = 2:
	set(v):
		rows = v
		_touch()


func _touch() -> void:
	redraw()


func _style() -> Dictionary:
	return {"color": Color(0.75, 0.75, 0.72, 0.2), "width": 1.7 * rows, "text": "Зуби"}
