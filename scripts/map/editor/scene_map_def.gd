@tool
class_name SceneMapDef
extends MapDef
## MapDef built from an editor map (MapScene.to_mapdef): the base relief comes
## from baked heights or noise, plus the hand-placed brushes.

var base: MapHeightData = null
var hills: Array = []
var ridges: Array = []
var tilt := Vector2.ZERO


func ground_height(x: float, z: float, noises: Array) -> float:
	var b := base.sample(x, z) if base else MapHeights.noise_height(noises, relief, x, z)
	return b + MapHeights.brushes(hills, ridges, tilt, x, z)
