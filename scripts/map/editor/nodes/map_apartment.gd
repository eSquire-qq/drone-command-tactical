@tool
class_name MapApartment
extends MapNode
## Багатоповерхівка (панельний будинок): поверхи по 3 м, вікна на кожному поверсі,
## під'їзди з боку +Z вузла. Противник займає вікна (переважно верхніх поверхів),
## наші — наказами «Тримати» / «Штурм» з ПКМ по будинку. Бетонні стіни не пробиваються.

## Розмір, м (X — довжина, Y — глибина).
@export var size: Vector2 = Vector2(24, 12):
	set(v):
		size = v
		_touch()
## Поверхів.
@export_range(1, 9) var floors: int = 4:
	set(v):
		floors = v
		_touch()
## Зруйнованість 0..1 (діри у стінах верхніх поверхів, провалений дах, уламки).
@export_range(0.0, 1.0, 0.05) var ruin: float = 0.3:
	set(v):
		ruin = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": box(Vector3(size.x, floors * 3.0, size.y)), "color": Color(0.8, 0.8, 0.8, 0.5), "y": floors * 1.5,
		"text": "Багатоповерхівка (%d пов.)" % floors, "label_y": floors * 3.0 + 2.0}


func _model() -> Node3D:
	return MapModels.apartment(_seed(), {"pos": _pos2(), "size": size, "floors": floors, "ruin": ruin})["node"]
