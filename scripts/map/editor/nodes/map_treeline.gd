@tool
class_name MapTreeline
extends MapNode
## Посадка / лісосмуга: прямокутник дерев і підліску (розмір X×Z, поворот не враховується).

## Розмір посадки, м (X — ширина, Y — глибина по Z).
@export var size: Vector2 = Vector2(30, 10):
	set(v):
		size = v
		_touch()
## Густота дерев 0..1.
@export_range(0.1, 1.0, 0.05) var density: float = 0.85:
	set(v):
		density = v
		_touch()
## Частка сухих / зламаних дерев 0..1.
@export_range(0.0, 1.0, 0.05) var dead: float = 0.2:
	set(v):
		dead = v
		_touch()
## Порода: листяні (посадка), сосни або мішаний ліс.
@export_enum("broadleaf", "pine", "mixed") var kind: String = "broadleaf":
	set(v):
		kind = v
		_touch()
## Наскільки дерева закривають огляд 0.1..1 (0 — як густота). Посадка 0.85 непрозора вже за ~9 м,
## сосновий ліс 0.2 — за ~35 м.
@export_range(0.0, 1.0, 0.05) var sight_block: float = 0.0:
	set(v):
		sight_block = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": box(Vector3(size.x, 6.0, size.y)), "color": Color(0.2, 0.7, 0.25, 0.08), "y": 3.0, "text": "Посадка"}
