class_name VisionPreview
extends RefCounted
## What a unit can see from a point: the ground a man standing there would
## see (terrain, buildings, trench walls, foliage, fog), drawn under the
## selected unit and, while an order is being placed, from the order point.
## Only the ground is checked — enemies are never revealed by it.
##
## A cheap viewshed: RAYS rays from the eye, each marched outward in STEP
## metre steps keeping the highest elevation angle met so far (the horizon);
## a sample is visible when it lies above that horizon and the foliage on the
## way still lets the eye through. Result: per ray, the runs [t0, t1] that
## are visible.

const RAYS := 72
const STEP := 3.0
const RANGE := 170.0
const TARGET_H := 1.0          # a man (crouched) at the sample point
const MIN_VIS := 0.25          # foliage / fog let this much through


static func compute(eye: Vector3) -> Array:
	var g: TerrainGrid = W.grid
	var out: Array = []
	var eh: float = eye.y
	for k in RAYS:
		var a := TAU * k / RAYS
		var dir := Vector2(sin(a), cos(a))
		var runs: Array = []
		var horizon := -INF
		var fol := 0.0
		var start := -1.0
		var t := STEP
		while t <= RANGE:
			var px := eye.x + dir.x * t
			var pz := eye.z + dir.y * t
			if absf(px) > g.half - 2.0 or absf(pz) > g.half - 2.0:
				break
			var gh: float = g.height_at(px, pz)
			var i: int = g.cidx(px, pz)
			if g.trench_near[i] != 0:
				gh = g.los_ground(px, pz, gh)
			var v := exp(-fol * 0.085)
			if g.fog_len > 0.0:
				v *= exp(-t / g.fog_len)
			var seen: bool = (gh + TARGET_H - eh) / t >= horizon and fol <= 7.0 and v >= MIN_VIS
			if seen and start < 0.0:
				start = t - STEP * 0.5
			elif not seen and start >= 0.0:
				runs.append(Vector2(start, t - STEP * 0.5))
				start = -1.0
			if v < MIN_VIS * 0.5 or fol > 7.0:
				break   # nothing further along this ray can be seen
			var top := gh + 0.05
			var ob: float = g.obstacle[i]
			if ob > 0.0:
				top = gh + ob
			horizon = maxf(horizon, (top - eh) / t)
			var f: float = g.foliage[i]
			if f > 0.0:
				fol += f * STEP
			t += STEP
		if start >= 0.0:
			runs.append(Vector2(start, minf(t, RANGE)))
		out.append(runs)
	return out


## Ground quads to draw: [[p0, p1, p2, p3], ...] in world space (a run on ray
## k spans the wedge between ray k and ray k+1).
static func quads(eye: Vector3, rays: Array) -> Array:
	var g: TerrainGrid = W.grid
	var out: Array = []
	var n := rays.size()
	for k in n:
		var a0 := TAU * (k - 0.5) / n
		var a1 := TAU * (k + 0.5) / n
		var d0 := Vector2(sin(a0), cos(a0))
		var d1 := Vector2(sin(a1), cos(a1))
		for r in rays[k]:
			var t0: float = r.x
			var t1: float = r.y
			# long runs are split so the quads follow the ground
			var segs := maxi(1, int(ceil((t1 - t0) / 18.0)))
			for s in segs:
				var u0 := lerpf(t0, t1, float(s) / segs)
				var u1 := lerpf(t0, t1, float(s + 1) / segs)
				out.append([
					g.ground(Vector3(eye.x + d0.x * u0, 0, eye.z + d0.y * u0)),
					g.ground(Vector3(eye.x + d1.x * u0, 0, eye.z + d1.y * u0)),
					g.ground(Vector3(eye.x + d1.x * u1, 0, eye.z + d1.y * u1)),
					g.ground(Vector3(eye.x + d0.x * u1, 0, eye.z + d0.y * u1)),
				])
	return out
