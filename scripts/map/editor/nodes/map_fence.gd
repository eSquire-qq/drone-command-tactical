@tool
class_name MapFence
extends MapPath
## Паркан (лише вигляд).



func _touch() -> void:
	redraw()


func _style() -> Dictionary:
	return {"color": Color(0.55, 0.42, 0.3, 0.3), "width": 0.25, "text": ""}
