@tool
class_name MapHeights
extends RefCounted
## Height function shared by the game (MapManager) and the editor preview
## (MapScene): base noise of the map + hand-placed relief brushes.


static func make_noises(seed: int) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.011
	noise.fractal_octaves = 3
	var micro := FastNoiseLite.new()
	micro.seed = seed + 7
	micro.frequency = 0.11
	return [noise, micro]


## Procedural ground of a map without hand-made relief.
static func noise_height(noises: Array, relief: float, x: float, z: float) -> float:
	return (noises[0] as FastNoiseLite).get_noise_2d(x, z) * relief * 1.4 + (noises[1] as FastNoiseLite).get_noise_2d(x, z) * 0.07


## Relief brushes: hills / hollows {pos: Vector2, rx, rz, rot, h},
## ridges / gullies {pts: PackedVector2Array, w, h}, tilt Vector2 (m per 100 m).
static func brushes(hills: Array, ridges: Array, tilt: Vector2, x: float, z: float) -> float:
	var h := (x * tilt.x + z * tilt.y) * 0.01
	for b in hills:
		var d: Vector2 = (Vector2(x, z) - b["pos"]).rotated(-float(b["rot"]))
		var e := pow(d.x / maxf(float(b["rx"]), 0.1), 2.0) + pow(d.y / maxf(float(b["rz"]), 0.1), 2.0)
		if e < 9.0:
			h += float(b["h"]) * exp(-e)
	for r in ridges:
		var pts: PackedVector2Array = r["pts"]
		var w: float = maxf(float(r["w"]), 0.5)
		var best := INF
		for k in pts.size() - 1:
			best = minf(best, seg_dist(Vector2(x, z), pts[k], pts[k + 1]))
		if best < w * 3.0:
			h += float(r["h"]) * exp(-pow(best / w, 2.0))
	return h


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.0001 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
