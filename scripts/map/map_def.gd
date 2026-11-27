@tool
class_name MapDef
extends RefCounted
## Data description of a mission map. Concrete maps extend this and fill
## the fields in setup(). MapManager turns the data into geometry.

var id := ""
var title := ""
var subtitle := ""
var terrain_type := ""
var terrain_desc := ""
var task_text := ""
var size := 160.0
var seed := 1
var relief := 0.8
var time_limit := 25.0 * 60.0

var palette := {
	"ground": [
		Color(0.40, 0.44, 0.24),  # GRASS
		Color(0.55, 0.50, 0.31),  # DRY
		Color(0.29, 0.24, 0.18),  # MUD
		Color(0.45, 0.38, 0.28),  # ROAD
		Color(0.31, 0.29, 0.18),  # FOREST floor
		Color(0.33, 0.26, 0.19),  # TRENCH
		Color(0.27, 0.22, 0.17),  # CRATER
		Color(0.40, 0.32, 0.23),  # DIRT
		Color(0.42, 0.40, 0.30),  # YARD
		Color(0.17, 0.15, 0.13),  # BURNT
	],
	"slope": Color(0.36, 0.28, 0.20),
	# trench spoil (бруствер): old positions are grassed over, fresh ones are bare clay
	"spoil": Color(0.52, 0.48, 0.33),
	"strata": [Color(0.24, 0.19, 0.14), Color(0.47, 0.36, 0.25), Color(0.40, 0.31, 0.22), Color(0.33, 0.26, 0.19)],
	"crown": [Color(0.24, 0.31, 0.14), Color(0.30, 0.35, 0.16), Color(0.40, 0.38, 0.17), Color(0.45, 0.33, 0.14), Color(0.21, 0.27, 0.13)],
	"trunk": Color(0.27, 0.22, 0.17),
	"dead_trunk": Color(0.33, 0.30, 0.26),
	"grass": [Color(0.42, 0.46, 0.22), Color(0.55, 0.52, 0.30), Color(0.36, 0.40, 0.20)],
	"sun": Color(1.0, 0.93, 0.82),
	"sun_energy": 1.25,
	"sun_rot": Vector3(-42, -35, 0),
	"sky_top": Color(0.42, 0.53, 0.66),
	"sky_horizon": Color(0.70, 0.72, 0.70),
	"fog": Color(0.66, 0.68, 0.66),
	"fog_density": 0.0016,
	"ambient": 0.55,
}

# features (x,z in metres, map centred at 0,0)
var treelines: Array = []   # {rect: Rect2, density: float, dead: float, kind: ""/"pine"/"mixed", vis: float (optional)}
# kind: "" — broadleaf (default), "pine" — tall pines, "mixed" — half and half.
# vis: how much the trees block sight (0.1..1, default = density): a tree line
# of density 0.85 is opaque at ~9 m, a pine forest with vis 0.2 at ~35 m.
var bushes: Array = []      # Vector3(x, z, radius)
var roads: Array = []       # {pts: PackedVector2Array, w: float}
var trenches: Array = []    # PackedVector2Array
var craters: Array = []     # Vector3(x, z, radius)
var houses: Array = []      # {pos: Vector2, size: Vector2, rot: float, ruin: float}
var sheds: Array = []       # {pos, size, rot}
var fences: Array = []      # PackedVector2Array
var bales: Array = []       # Vector2
var poles: Array = []       # Vector2
var wrecks: Array = []      # {pos: Vector2, rot: float, model: String}
var bunkers: Array = []     # {pos: Vector2, face: Vector2, kind: "mg"/"dugout"}
var sandbags: Array = []    # {pos: Vector2, rot: float, len: float}
var wire: Array = []        # PackedVector2Array
var burnt: Array = []       # Vector3(x, z, r) burnt ground patches
var smoke_columns: Array = []
var ew_stations: Array = []   # Vector2 enemy jammers (РЕБ)
var ew_decoys: Array = []     # Vector2 decoy jammers
var ew_backups: Array = []    # Vector2 spots for a backup jammer  # Vector2 ambient smoke

var player_entry := Vector3.ZERO
var player_entry_dir := Vector3(0, 0, -1)
var dismount_points: Array = []
var foot_spawn := Vector3.ZERO
var medevac_entry := Vector3.ZERO
var rally_point := Vector3.ZERO
## Where the column may be sent on the briefing photo: named points
## {name: String, pos: Vector2, desc: String, axis: Vector2 (optional: the
## line the dismount points spread along, default X)}, and/or a zone where any point
## may be picked by clicking. The dismount points keep their layout around
## the chosen point (their centre moves there). Empty = no choice.
var deploy_options: Array = []
var deploy_zone := Rect2()
## A harder operation gets more resources: extra budget points (a single
## battle; in a campaign half of it comes as the operation's own supply) and
## higher limits per item, e.g. {"rifle_squad": 1} (support items only in a
## campaign: squads and vehicles there are what the unit has).
var budget_bonus := 0
## Enemy reinforcements: [{after: s after the fight starts, men: [roles],
## vehicle: "bmp1"/"bmp2"/""}]. Empty = one default wave chosen by the game
## (a squad + a BMP on maps 300 m and larger, a squad on smaller ones);
## [{"none": true}] = no reinforcements.
var reinforcements: Array = []
var extra_max := {}
var enemy_retreat := Vector3.ZERO
var objective_rect := Rect2()
var capture_rect := Rect2()
var enemy_teams: Array = []   # {name, slots:[Vector2], alt:[Vector2], roles:[String], bunker:int, reserve:bool, fallback:[Vector2]}
var enemy_fallback: Array = []
var intel := {}
var photo_center := Vector3.ZERO
var photo_height := 110.0
var photo_size := 92.0
var minefields: Array = []   # {pts, w, density, type "ap"/"at"}
var camera_start := Vector3.ZERO
## Main task and optional tasks — see Objectives for the supported types.
var objective := {"type": "capture"}
var secondary: Array = []
## Shared environment preset (Environments.PRESETS key) applied before the
## map's own palette overrides; keeps every map in one visual style.
var environment := "steppe"
## Per-map overrides of difficulty parameters (see Game.DIFFICULTY), e.g. a
## gentle enemy on the training ground.
var diff_override := {}
## When set, the mission starts with this force and skips the planning screen.
var fixed_loadout := {}
## The enemy never orders a general withdrawal (small scripted positions).
var enemy_no_retreat := false
## Pre-registered enemy mortar fire zone (open approach), x/z rect.
var mortar_zone := Rect2()
## Camouflaged fighting positions, Vector3(x, z, radius): a still soldier
## there is much harder to spot; firing gives him away.
var camo: Array = []
## Covered dugouts (перекриття бліндажів) — log-roofed mounds: {pos: Vector2, rot: float, size: Vector2}
var dugouts: Array = []
## Anti-vehicle "dragon teeth" rows: {pts: PackedVector2Array, rows: int}
var teeth: Array = []
## City: apartment blocks {pos: Vector2, size: Vector2, rot: float, floors: int, ruin: float},
## concrete blocks / junk barricades {pts: PackedVector2Array, kind: "concrete"/"barricade"},
## burnt-out cars {pos: Vector2, rot: float}.
var apartments: Array = []
var blocks: Array = []
var cars: Array = []


## Centre of the dismount points (the default deployment point).
func dismount_center() -> Vector2:
	if dismount_points.is_empty():
		return Vector2(player_entry.x, player_entry.z)
	var c := Vector3.ZERO
	for p in dismount_points:
		c += p
	c /= dismount_points.size()
	return Vector2(c.x, c.z)


## Can the player pick the deployment point for this map?
func has_deploy_choice() -> bool:
	return not deploy_options.is_empty() or deploy_zone.has_area()


func setup() -> void:
	pass


# ------------------------------------------------------------------ trench design helpers
## Fire trench with traverses: between the anchor points the line breaks into
## short bays (~`bay` m) offset ±`amp` — the sawtooth seen on drone footage.
## Anchors stay on the line, so positions placed on anchors stay in the trench.
static func traversed(anchors: PackedVector2Array, bay: float = 4.5, amp: float = 1.2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var sgn := 1.0
	for k in anchors.size() - 1:
		var a: Vector2 = anchors[k]
		var b: Vector2 = anchors[k + 1]
		out.append(a)
		var l := a.distance_to(b)
		var m := int(floor(l / bay))
		if m < 2:
			continue
		var dir := (b - a) / l
		var nrm := Vector2(-dir.y, dir.x)
		for j in range(1, m):
			out.append(a + dir * (l * j / m) + nrm * amp * sgn)
			sgn = -sgn
	out.append(anchors[anchors.size() - 1])
	return chaikin(out)


## One pass of corner cutting: dug earth has no knife-edge corners, and the
## trench mesh folds less on rounded turns. End points are kept.
static func chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		if k > 0:
			out.append(a.lerp(b, 0.25))
		if k < pts.size() - 2:
			out.append(a.lerp(b, 0.75))
	out.append(pts[pts.size() - 1])
	return out


## Communication trench: a gently wandering line between anchors.
static func meander(anchors: PackedVector2Array, rng: RandomNumberGenerator, step: float = 5.0, amp: float = 0.9) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in anchors.size() - 1:
		var a: Vector2 = anchors[k]
		var b: Vector2 = anchors[k + 1]
		out.append(a)
		var l := a.distance_to(b)
		var m := int(floor(l / step))
		var dir := (b - a) / maxf(l, 0.001)
		var nrm := Vector2(-dir.y, dir.x)
		for j in range(1, m):
			out.append(a + dir * (l * j / m) + nrm * rng.randf_range(-amp, amp))
	out.append(anchors[anchors.size() - 1])
	return out


## Firing cells: short dead-end spurs off a trench every `every` m, pointing to
## `toward` (the expected attack direction). Returns the spur polylines.
static func firing_cells(line: PackedVector2Array, toward: Vector2, every: float = 9.0, length: float = 2.3, skip: float = 4.0) -> Array:
	var out: Array = []
	var acc := every - skip
	for k in line.size() - 1:
		var a: Vector2 = line[k]
		var b: Vector2 = line[k + 1]
		var l := a.distance_to(b)
		var t := 0.0
		while t < l:
			if acc >= every and t > 0.6 and t < l - 0.6:
				acc = 0.0
				var p := a.lerp(b, t / l)
				var dir := (b - a) / l
				var nrm := Vector2(-dir.y, dir.x)
				if nrm.dot(toward) < 0.0:
					nrm = -nrm
				out.append(PackedVector2Array([p, p + nrm * length]))
			t += 0.5
			acc += 0.5
	return out


## A trench line plus a dugout at its end, set back along the line direction.
func dugout_at_end(line: PackedVector2Array, size_v: Vector2 = Vector2(3.6, 3.0)) -> void:
	var e: Vector2 = line[line.size() - 1]
	var d: Vector2 = (e - line[line.size() - 2]).normalized()
	dugouts.append({"pos": e + d * (size_v.y * 0.5 + 0.6), "rot": atan2(-d.x, -d.y), "size": size_v})


## Natural ground height before trenches, roads and craters are dug in.
## noises = MapHeights.make_noises(seed).
func ground_height(x: float, z: float, noises: Array) -> float:
	return MapHeights.noise_height(noises, relief, x, z) + extra_height(x, z)


## Additional macro shaping of the terrain (slopes, ridges).
func extra_height(_x: float, _z: float) -> float:
	return 0.0
