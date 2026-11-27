@tool
class_name MapScene
extends Node3D
## Root of a map built by hand in the Godot editor (res://maps/*.tscn).
##
## How to use:
##  * add objects as child nodes (Add Child Node → type "Map…"): MapTreeline,
##    MapHouse, MapTrench, MapRoad, MapHill, MapEnemyTeam + MapSlot, …;
##    group them in plain Node3D folders as you like;
##  * relief = base (baked heights of a converted map, or noise from Seed and
##    Relief) + brushes MapHill / MapRidge + Tilt; the editor shows a preview of
##    the ground (button "Оновити рельєф"), objects stand on it;
##  * F6 (Run Current Scene) starts a battle on this map;
##  * files in res://maps/custom/ appear in the game menu automatically.
## Everything is turned into a MapDef by to_mapdef() when the game loads the map.

@export_group("Карта")
## Ідентифікатор (латиницею, без пробілів). Для карт у maps/custom/ — імʼя файлу.
@export var map_id := "custom"
@export var title := "НОВА КАРТА"
@export var subtitle := ""
@export var terrain_type := "Поле"
@export_multiline var terrain_desc := ""
@export_multiline var task_text := "Захопити опорний пункт противника."
## Розмір квадратної карти, м.
@export_range(80.0, 400.0, 10.0) var size := 160.0:
	set(v):
		size = v
		_relief_changed()
## Зерно випадкового рельєфу (і кольорових плям ґрунту).
@export var seed := 1:
	set(v):
		seed = v
		_relief_changed()
## Сила випадкових горбків рельєфу (0 — рівно).
@export_range(0.0, 3.0, 0.05) var relief := 0.8:
	set(v):
		relief = v
		_relief_changed()
## Нахил усієї карти: м на 100 м уздовж X і Z (наприклад (0, -1) — північ вища).
@export var tilt := Vector2.ZERO:
	set(v):
		tilt = v
		_relief_changed()
## Запечений базовий рельєф (у конвертованих картах). Якщо порожньо — шум із Seed / Relief.
@export var base_heights: MapHeightData:
	set(v):
		base_heights = v
		_relief_changed()
## Набір кольорів і світла: steppe, field, forest, village, urban.
@export_enum("steppe", "field", "forest", "village", "urban") var environment := "steppe"
## Повна палітра (необовʼязково): якщо задано, замінює набір Environment.
@export var palette: Dictionary = {}
@export_range(5.0, 90.0, 1.0) var time_limit_min := 25.0

@export_group("Місія")
## Головне завдання: {"type": "capture"} / {"type": "recon"} / {"type": "training"} …
@export var objective: Dictionary = {"type": "capture"}
## Додаткові завдання, напр. [{"type": "no_vloss"}, {"type": "pows", "n": 1}].
@export var secondary: Array = []
## Зміни складності для цієї карти (див. Game.DIFFICULTY), напр. {"mortar": 0}.
@export var diff_override: Dictionary = {}
## Якщо задано — сили фіксовані й екран планування пропускається, напр. {"rifle_squad": 1, "medevac": 1}.
@export var fixed_loadout: Dictionary = {}
## Складна операція: додаткові очки на сили й підтримку (у кампанії — половина як постачання на операцію).
@export_range(0, 2000, 10) var budget_bonus := 0
## Складна операція: вищі ліміти, напр. {"rifle_squad": 1, "fpv": 2}.
@export var extra_max: Dictionary = {}
## Противник ніколи не відходить загалом.
@export var enemy_no_retreat := false
@export var photo_height := 110.0
@export var photo_size := 92.0

@export_group("Розвіддані")
@export var intel_age := "знімок зроблено 3 год тому"
@export var intel_estimate := ""
@export var intel_lines: PackedStringArray = []

@export_group("Редактор")
## Перебудувати землю зараз і поставити всі обʼєкти на неї.
@export_tool_button("Оновити рельєф", "Reload") var _btn_relief = rebuild_preview
## Показувати землю (справжню, як у грі) в редакторі.
@export var show_ground := true:
	set(v):
		show_ground = v
		if _ground:
			_ground.visible = v
## Світло, небо й туман гри в редакторі.
@export var show_lighting := true:
	set(v):
		show_lighting = v
		_relief_changed()
## Через скільки секунд після зміни перебудовувати землю.
@export_range(0.2, 5.0, 0.1) var ground_delay := 0.8
## Показувати підписи об'єктів.
@export var show_labels := true:
	set(v):
		show_labels = v
		_snap_dirty = true

## Debug: show the editor view (ground preview + markers) in a running game.
static var preview_in_game := false


static func editing() -> bool:
	return Engine.is_editor_hint() or preview_in_game


var _ground: MapManager       # the real map, built for the editor view
var _body: StaticBody3D       # ground collision: dropped objects land on it
var _dirty := false
var _snap_dirty := false
var _t := 0.0
var _changed_t := 0.0
var _noises: Array = []
var _brush_hills: Array = []
var _brush_ridges: Array = []


# ------------------------------------------------------------------ editor
func _ready() -> void:
	if editing():
		set_process(true)
		_dirty = true
		return
	# F6 in the editor: play a battle on this map
	if get_tree().current_scene == self:
		get_node("/root/Game").play_scene_map(scene_file_path)


func _process(delta: float) -> void:
	if not editing():
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	var now := Time.get_ticks_msec() / 1000.0
	if _dirty and now - _changed_t >= ground_delay:
		_dirty = false
		rebuild_preview()
	elif _snap_dirty:
		_snap_dirty = false
		_snap_all()


func _relief_changed() -> void:
	_dirty = true
	_changed_t = Time.get_ticks_msec() / 1000.0


## Objects that are part of the ground build (relief, trenches, roads,
## craters, vegetation, line obstacles): changing them rebuilds the ground.
static func affects_ground(n: Node) -> bool:
	return n is MapHill or n is MapRidge or n is MapTrench or n is MapRoad or n is MapCrater or n is MapBurnt \
		or n is MapTreeline or n is MapBush or n is MapFence or n is MapWire or n is MapTeeth or n is MapBunker or n is MapBlocks


## A child moved or changed.
func on_child_moved(n: Node) -> void:
	if affects_ground(n):
		_relief_changed()
	else:
		_snap_dirty = true


## Builds the map exactly as the game does (ground, trenches, roads, craters,
## trees, bushes, grass, fences, wire), without the game systems. Houses,
## bunkers and other point objects show their own models (MapNode).
func rebuild_preview() -> void:
	if not is_inside_tree():
		return
	var t0 := Time.get_ticks_msec()
	_unique_curves()
	_collect_brushes()
	_noises = MapHeights.make_noises(seed)
	if _ground:
		_ground.free()
		_ground = null
	_ground = MapManager.new()
	_ground.name = "_Ground"
	add_child(_ground, false, Node.INTERNAL_MODE_FRONT)
	_ground.build_preview(to_mapdef(), show_lighting)
	_ground.visible = show_ground
	# collision of the ground (drag & drop from the FileSystem lands on it)
	if _body:
		_body.free()
	_body = StaticBody3D.new()
	add_child(_body, false, Node.INTERNAL_MODE_FRONT)
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	var g: TerrainGrid = _ground.grid
	hm.map_width = g.n
	hm.map_depth = g.n
	hm.map_data = g.heights
	cs.shape = hm
	cs.scale = Vector3(g.res, 1.0, g.res)
	_body.add_child(cs)
	_snap_all(true)
	if Engine.is_editor_hint():
		print("[Map] %s: землю перебудовано за %d мс" % [title, Time.get_ticks_msec() - t0])


## A line duplicated in the editor (Ctrl+D) shares its Curve3D with the
## original: moving a point of one would move both. Give each its own.
func _unique_curves() -> void:
	var seen := {}
	for n in _all(self):
		if n is MapPath and n.curve != null:
			var id: int = n.curve.get_instance_id()
			if seen.has(id):
				n.curve = n.curve.duplicate()
			else:
				seen[id] = true


## Height of the ground at map X/Z (with trenches, roads and craters once
## the ground is built).
func height_at(x: float, z: float) -> float:
	if _ground and _ground.grid:
		return _ground.grid.height_at(x, z)
	if _noises.is_empty():
		_noises = MapHeights.make_noises(seed)
	var b := base_heights.sample(x, z) if base_heights else MapHeights.noise_height(_noises, relief, x, z)
	return b + MapHeights.brushes(_brush_hills, _brush_ridges, tilt, x, z)


## Same for a global X/Z (editor gizmos).
func preview_height_global(gx: float, gz: float) -> float:
	var l := to_local(Vector3(gx, 0, gz))
	return to_global(Vector3(l.x, height_at(l.x, l.z), l.z)).y


func _snap_all(all_models: bool = false) -> void:
	for n in _all(self):
		if n is MapNode:
			var l := to_local(n.global_position)
			n.snap_to_ground(to_global(Vector3(l.x, height_at(l.x, l.z), l.z)).y)
			if all_models or n.model_outdated():
				n.redraw()
		elif n is MapPath:
			n.redraw()


## Trench spoil colour of this map (dugout models).
func spoil_color() -> Color:
	if palette.has("spoil"):
		return palette["spoil"]
	return Color(0.52, 0.48, 0.33)


func _collect_brushes() -> void:
	_brush_hills.clear()
	_brush_ridges.clear()
	for n in _all(self):
		if n is MapHill:
			var xf := _xf(n)
			_brush_hills.append({"pos": Vector2(xf.origin.x, xf.origin.z), "rx": n.radius_x, "rz": n.radius_z,
				"rot": -xf.basis.get_euler().y, "h": n.height})
		elif n is MapRidge:
			_brush_ridges.append({"pts": n.points_2d(_xf(n)), "w": n.width, "h": n.height})


# ------------------------------------------------------------------ helpers
static func _all(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		out.append(c)
		out.append_array(_all(c))
	return out


## Transform of a node relative to this root (works outside the scene tree).
func _xf(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != self:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _p2(n: Node3D) -> Vector2:
	var o := _xf(n).origin
	return Vector2(o.x, o.z)


func _p3(n: Node3D) -> Vector3:
	var o := _xf(n).origin
	return Vector3(o.x, 0, o.z)


## Turn of a node around Y in the map's convention (MapDef "rot").
func _rot(n: Node3D) -> float:
	return _xf(n).basis.get_euler().y


## Forward (−Z) of a node on the map plane.
func _fwd(n: Node3D) -> Vector2:
	var f := -_xf(n).basis.z
	return Vector2(f.x, f.z).normalized()


# ------------------------------------------------------------------ game
## Builds the game's map description from the nodes (game side only).
func to_mapdef() -> MapDef:
	var d := SceneMapDef.new()
	Environments.apply(d, environment)
	if not palette.is_empty():
		for k in palette.keys():
			d.palette[k] = palette[k]
	d.id = map_id
	d.title = title
	d.subtitle = subtitle
	d.terrain_type = terrain_type
	d.terrain_desc = terrain_desc
	d.task_text = task_text
	d.size = size
	d.seed = seed
	d.relief = relief
	d.time_limit = time_limit_min * 60.0
	d.objective = objective.duplicate(true)
	d.secondary = secondary.duplicate(true)
	d.diff_override = diff_override.duplicate(true)
	d.fixed_loadout = fixed_loadout.duplicate(true)
	d.budget_bonus = budget_bonus
	d.extra_max = extra_max.duplicate(true)
	d.enemy_no_retreat = enemy_no_retreat
	d.photo_height = photo_height
	d.photo_size = photo_size
	d.base = base_heights
	d.tilt = tilt
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 5
	var markers: Array = []
	var bunker_nodes: Array = []
	var teams: Array = []
	for n in _all(self):
		if n is MapBunker:
			bunker_nodes.append(n)
	for n in _all(self):
		if n is MapTreeline:
			var c := _p2(n)
			var tl := {"rect": Rect2(c - n.size * 0.5, n.size), "density": n.density, "dead": n.dead}
			if n.kind != "broadleaf":
				tl["kind"] = n.kind
			if n.sight_block > 0.0:
				tl["vis"] = n.sight_block
			d.treelines.append(tl)
		elif n is MapBush:
			var c := _p2(n)
			d.bushes.append(Vector3(c.x, c.y, n.radius))
		elif n is MapCrater:
			var c := _p2(n)
			d.craters.append(Vector3(c.x, c.y, n.radius))
		elif n is MapBurnt:
			var c := _p2(n)
			d.burnt.append(Vector3(c.x, c.y, n.radius))
		elif n is MapCamo:
			var c := _p2(n)
			d.camo.append(Vector3(c.x, c.y, n.radius))
		elif n is MapHouse:
			d.houses.append({"pos": _p2(n), "size": n.size, "rot": _rot(n), "ruin": n.ruin})
		elif n is MapShed:
			d.sheds.append({"pos": _p2(n), "size": n.size, "rot": _rot(n)})
		elif n is MapApartment:
			d.apartments.append({"pos": _p2(n), "size": n.size, "rot": _rot(n), "floors": n.floors, "ruin": n.ruin})
		elif n is MapCar:
			d.cars.append({"pos": _p2(n), "rot": _rot(n)})
		elif n is MapBlocks:
			d.blocks.append({"pts": n.points_2d(_xf(n)), "kind": n.kind})
		elif n is MapBale:
			d.bales.append(_p2(n))
		elif n is MapPole:
			d.poles.append(_p2(n))
		elif n is MapWreck:
			d.wrecks.append({"pos": _p2(n), "rot": _rot(n), "model": n.model})
		elif n is MapSandbags:
			d.sandbags.append({"pos": _p2(n), "rot": _rot(n), "len": n.length})
		elif n is MapDugout:
			d.dugouts.append({"pos": _p2(n), "rot": _rot(n), "size": n.size})
		elif n is MapBunker:
			d.bunkers.append({"pos": _p2(n), "face": _fwd(n), "kind": n.kind})
		elif n is MapEW:
			match n.kind:
				"station":
					d.ew_stations.append(_p2(n))
				"decoy":
					d.ew_decoys.append(_p2(n))
				_:
					d.ew_backups.append(_p2(n))
		elif n is MapSmokeColumn:
			d.smoke_columns.append(_p2(n))
		elif n is MapHill:
			var xf := _xf(n)
			d.hills.append({"pos": Vector2(xf.origin.x, xf.origin.z), "rx": n.radius_x, "rz": n.radius_z, "rot": -xf.basis.get_euler().y, "h": n.height})
		elif n is MapRidge:
			d.ridges.append({"pts": n.points_2d(_xf(n)), "w": n.width, "h": n.height})
		elif n is MapRoad:
			d.roads.append({"pts": n.points_2d(_xf(n)), "w": n.width})
		elif n is MapTrench:
			var pts: PackedVector2Array = n.points_2d(_xf(n))
			if pts.size() < 2:
				continue
			match n.style:
				"traversed":
					pts = MapDef.traversed(pts, n.bay, n.amp)
				"meander":
					pts = MapDef.meander(pts, rng, n.bay, n.amp)
			d.trenches.append(pts)
			if n.dugout_at_end:
				d.dugout_at_end(pts)
		elif n is MapFence:
			d.fences.append(n.points_2d(_xf(n)))
		elif n is MapWire:
			d.wire.append(n.points_2d(_xf(n)))
		elif n is MapTeeth:
			d.teeth.append({"pts": n.points_2d(_xf(n)), "rows": n.rows})
		elif n is MapMinefield:
			d.minefields.append({"pts": n.points_2d(_xf(n)), "w": n.width, "density": n.density, "type": n.mine_type})
		elif n is MapMarker:
			var p3 := _p3(n)
			match n.kind:
				"player_entry":
					d.player_entry = p3
					var f := _fwd(n)
					d.player_entry_dir = Vector3(f.x, 0, f.y)
				"foot_spawn":
					d.foot_spawn = p3
				"dismount":
					d.dismount_points.append(p3)
				"medevac_entry":
					d.medevac_entry = p3
				"rally_point":
					d.rally_point = p3
				"enemy_retreat":
					d.enemy_retreat = p3
				"camera_start":
					d.camera_start = p3
				"photo_center":
					d.photo_center = p3
				"enemy_fallback":
					d.enemy_fallback.append(_p2(n))
				"deploy_option":
					# the dismount points spread along the node's X axis (rotate the node)
					var ax := _xf(n).basis.x
					d.deploy_options.append({"name": n.label if n.label != "" else n.name, "pos": _p2(n), "desc": n.desc,
						"axis": Vector2(ax.x, ax.z).normalized().snapped(Vector2(0.001, 0.001))})
		elif n is MapArea:
			var r := Rect2(_p2(n) - n.size * 0.5, n.size)
			match n.kind:
				"objective":
					d.objective_rect = r
				"capture":
					d.capture_rect = r
				"mortar_zone":
					d.mortar_zone = r
				"deploy_zone":
					d.deploy_zone = r
		elif n is MapEnemyTeam:
			teams.append(n)
		elif n is MapIntelMarker:
			markers.append({"pos": _p2(n), "label": n.label, "r": n.radius})
	for tm in teams:
		var t := {"name": tm.team_name, "roles": Array(tm.roles), "slots": [], "alt": [], "fallback": []}
		for c in tm.get_children():
			if c is MapSlot:
				t[c.kind if c.kind != "slot" else "slots"].append(_p2(c))
		if tm.reserve:
			t["reserve"] = true
		if not tm.bunker.is_empty():
			var bn = tm.get_node_or_null(tm.bunker)
			var bi := bunker_nodes.find(bn)
			if bi >= 0:
				t["bunker"] = bi
		d.enemy_teams.append(t)
	d.intel = {"age": intel_age, "estimate": intel_estimate, "lines": Array(intel_lines), "markers": markers}
	return d
