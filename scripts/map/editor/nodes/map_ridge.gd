@tool
class_name MapRidge
extends MapPath
## Рельєф уздовж лінії: вал / гребінь (висота > 0) або балка / лощина (висота < 0).

## Півширина схилу, м (на цій відстані від осі ~37 % висоти).
@export_range(1.0, 60.0, 0.5) var width: float = 8.0:
	set(v):
		width = v
		_touch()
## Висота, м (мінус — балка).
@export_range(-10.0, 15.0, 0.1) var height: float = -2.0:
	set(v):
		height = v
		_touch()


func _touch() -> void:
	redraw()
	var r = map_root()
	if r:
		r.on_child_moved(self)


func _style() -> Dictionary:
	return {"color": Color(0.3, 0.9, 0.4, 0.4) if height >= 0.0 else Color(0.3, 0.6, 1.0, 0.4), "width": width * 2.0, "text": ("Вал %+.1f м" if height >= 0.0 else "Балка %+.1f м") % height}
