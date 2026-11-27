@tool
class_name MapWire
extends MapPath
## Колючий дріт: піхота проходить дуже повільно.



func _touch() -> void:
	redraw()


func _style() -> Dictionary:
	return {"color": Color(0.8, 0.8, 0.8, 0.3), "width": 0.8, "text": "Дріт"}
