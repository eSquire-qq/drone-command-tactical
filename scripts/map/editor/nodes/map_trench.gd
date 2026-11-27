@tool
class_name MapTrench
extends MapPath
## Окоп / хід сполучення. Ставте опорні точки по осі окопу.
## style: plain — як намальовано; traversed — пилоподібні траверси між точками; meander — звивистий хід сполучення.

## Як викопано.
@export_enum("plain", "traversed", "meander") var style: String = "traversed":
	set(v):
		style = v
		_touch()
## Довжина колін (traversed) / крок (meander), м.
@export_range(2.0, 10.0, 0.5) var bay: float = 4.0:
	set(v):
		bay = v
		_touch()
## Відхилення колін, м.
@export_range(0.0, 3.0, 0.1) var amp: float = 1.2:
	set(v):
		amp = v
		_touch()
## Бліндаж у кінці окопу.
@export var dugout_at_end: bool = false:
	set(v):
		dugout_at_end = v
		_touch()


func _touch() -> void:
	redraw()


func _style() -> Dictionary:
	return {"color": Color(0.9, 0.5, 0.2, 0.22), "width": 1.6, "text": "Окоп"}
