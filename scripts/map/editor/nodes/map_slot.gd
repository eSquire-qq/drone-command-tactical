@tool
class_name MapSlot
extends MapNode
## Позиція бійця загону противника (дочірній вузол MapEnemyTeam).

## slot — основна позиція, alt — запасна, fallback — рубіж відходу.
@export_enum("slot", "alt", "fallback") var kind: String = "slot":
	set(v):
		kind = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": cyl(0.35, 1.8), "color": {"slot": Color(1, 0.25, 0.2), "alt": Color(1, 0.6, 0.2), "fallback": Color(0.7, 0.4, 1.0)}[kind], "y": 0.9, "text": ""}
