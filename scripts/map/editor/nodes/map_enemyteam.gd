@tool
class_name MapEnemyTeam
extends MapNode
## Загін противника. Позиції — дочірні вузли MapSlot (slot — основні, alt — запасні, fallback — рубіж відходу) у потрібному порядку.

## Назва загону (видно в журналі й навчанні).
@export var team_name: String = "Загін":
	set(v):
		team_name = v
		_touch()
## Ролі бійців по порядку: leader, rifleman, mg, at, grenadier, atgm, medic, sniper…
@export var roles: PackedStringArray = PackedStringArray(["rifleman", "rifleman"]):
	set(v):
		roles = v
		_touch()
## Резерв: сидить у бліндажі й контратакує.
@export var reserve: bool = false:
	set(v):
		reserve = v
		_touch()
## ДЗОТ / бліндаж (MapBunker), у якому сидить загін.
@export var bunker: NodePath = NodePath():
	set(v):
		bunker = v
		_touch()


func _touch() -> void:
	redraw()


func _gizmo() -> Dictionary:
	return {"mesh": cyl(0.3, 0.2), "color": Color(1, 0.35, 0.3), "y": 0.1, "text": team_name + " (%d)" % roles.size()}
