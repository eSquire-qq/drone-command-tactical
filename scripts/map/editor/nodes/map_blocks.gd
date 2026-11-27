@tool
class_name MapBlocks
extends MapPath
## Бетонні блоки або барикада з мотлоху вздовж лінії: добре укриття, техніка не проїде,
## піхота перелазить повільно.

## concrete — бетонні блоки, barricade — барикада з мотлоху.
@export_enum("concrete", "barricade") var kind: String = "concrete":
	set(v):
		kind = v
		_on_curve()


func _style() -> Dictionary:
	return {"color": Color(0.75, 0.75, 0.72, 0.25) if kind == "concrete" else Color(0.5, 0.35, 0.25, 0.3), "width": 1.6,
		"text": "Блоки" if kind == "concrete" else "Барикада"}
