@tool
class_name MapHeightData
extends Resource
## Baked ground heights of a map (metres, before trenches, roads and craters
## are dug in). Converted maps keep their original relief exactly this way;
## brushes on the map add to it.

@export var size := 160.0
@export var res := 0.8
@export var n := 0
@export var data := PackedFloat32Array()


func sample(x: float, z: float) -> float:
	if n < 2 or data.size() < n * n:
		return 0.0
	var half := size * 0.5
	var fx := clampf((x + half) / res, 0.0, n - 1.001)
	var fz := clampf((z + half) / res, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * n + ix
	return lerpf(lerpf(data[i], data[i + 1], tx), lerpf(data[i + n], data[i + n + 1], tx), tz)
