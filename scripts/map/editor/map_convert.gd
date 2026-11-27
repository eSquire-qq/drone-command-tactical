class_name MapConvert
extends RefCounted
## Turns a script map (MapDef subclass) into an editable scene (MapScene with
## nodes) and checks that the scene gives back the same map.
##   -- --map=<id> --convert-map=res://maps/<id>.tscn
##   -- --map=<id> --verify-map=res://maps/<id>.tscn

var root: MapScene
var groups := {}


static func convert(def: MapDef, out_path: String) -> void:
	var c := MapConvert.new()
	c._convert(def, out_path)


func _convert(def: MapDef, out_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	root = MapScene.new()
	root.name = def.id.capitalize().replace(" ", "")
	root.map_id = def.id
	root.title = def.title
	root.subtitle = def.subtitle
	root.terrain_type = def.terrain_type
	root.terrain_desc = def.terrain_desc
	root.task_text = def.task_text
	root.size = def.size
	root.seed = def.seed
	root.relief = def.relief
	root.environment = def.environment
	root.palette = def.palette.duplicate(true)
	root.time_limit_min = def.time_limit / 60.0
	root.objective = def.objective.duplicate(true)
	root.secondary = def.secondary.duplicate(true)
	root.diff_override = def.diff_override.duplicate(true)
	root.fixed_loadout = def.fixed_loadout.duplicate(true)
	root.budget_bonus = def.budget_bonus
	root.extra_max = def.extra_max.duplicate(true)
	root.enemy_no_retreat = def.enemy_no_retreat
	root.photo_height = def.photo_height
	root.photo_size = def.photo_size
	root.intel_age = String(def.intel.get("age", ""))
	root.intel_estimate = String(def.intel.get("estimate", ""))
	root.intel_lines = PackedStringArray(def.intel.get("lines", []))
	# the relief exactly as the script made it (noise + its own hills / gullies)
	var hd := MapHeightData.new()
	hd.size = def.size
	hd.res = 0.8
	hd.n = int(round(def.size / hd.res)) + 1
	hd.data.resize(hd.n * hd.n)
	var noises := MapHeights.make_noises(def.seed)
	for iz in hd.n:
		for ix in hd.n:
			hd.data[iz * hd.n + ix] = def.ground_height(-def.size * 0.5 + ix * hd.res, -def.size * 0.5 + iz * hd.res, noises)
	var hpath := out_path.get_basename() + "_heights.res"
	ResourceSaver.save(hd, hpath)
	root.base_heights = load(hpath)

	for t in def.treelines:
		var r: Rect2 = t["rect"]
		var n := MapTreeline.new()
		n.size = r.size
		n.density = t["density"]
		n.dead = t["dead"]
		n.kind = String(t.get("kind", "broadleaf"))
		n.sight_block = float(t.get("vis", 0.0))
		_add("Рослинність", n, "Ліс" if n.kind != "broadleaf" else "Посадка", r.get_center())
	for b in def.bushes:
		var n := MapBush.new()
		n.radius = b.z
		_add("Рослинність/Кущі", n, "Кущ", Vector2(b.x, b.y))
	for c in def.craters:
		var n := MapCrater.new()
		n.radius = c.z
		_add("Вирви", n, "Вирва", Vector2(c.x, c.y))
	for b in def.burnt:
		var n := MapBurnt.new()
		n.radius = b.z
		_add("Вирви", n, "Згарище", Vector2(b.x, b.y))
	for r in def.roads:
		var n := MapRoad.new()
		n.width = r["w"]
		_add_path("Дороги", n, "Дорога", r["pts"])
	for t in def.trenches:
		var n := MapTrench.new()
		n.style = "plain"
		_add_path("Окопи", n, "Окоп", t)
	for h in def.houses:
		var n := MapHouse.new()
		n.size = h["size"]
		n.ruin = h["ruin"]
		_add("Будівлі", n, "Будинок", h["pos"], h["rot"])
	for h in def.sheds:
		var n := MapShed.new()
		n.size = h["size"]
		_add("Будівлі", n, "Сарай", h["pos"], h["rot"])
	for f in def.fences:
		_add_path("Будівлі", MapFence.new(), "Паркан", f)
	for ap in def.apartments:
		var n := MapApartment.new()
		n.size = ap["size"]
		n.floors = int(ap.get("floors", 4))
		n.ruin = float(ap.get("ruin", 0.3))
		_add("Будівлі", n, "Багатоповерхівка", ap["pos"], ap["rot"])
	for c in def.cars:
		_add("Укриття", MapCar.new(), "Автівка", c["pos"], c["rot"])
	for bl in def.blocks:
		var n := MapBlocks.new()
		n.kind = String(bl.get("kind", "concrete"))
		_add_path("Загородження", n, "Блоки" if n.kind == "concrete" else "Барикада", bl["pts"])
	for b in def.bales:
		_add("Укриття", MapBale.new(), "Тюк", b)
	for p in def.poles:
		_add("Будівлі", MapPole.new(), "Стовп", p)
	for w in def.wrecks:
		var n := MapWreck.new()
		n.model = w["model"]
		_add("Укриття", n, "Підбита техніка", w["pos"], w["rot"])
	for s in def.sandbags:
		var n := MapSandbags.new()
		n.length = s["len"]
		_add("Укриття", n, "Мішки", s["pos"], s["rot"])
	for d in def.dugouts:
		var n := MapDugout.new()
		n.size = d.get("size", Vector2(3.6, 3.0))
		_add("Окопи", n, "Бліндаж", d["pos"], d["rot"])
	var bunker_nodes: Array = []
	for b in def.bunkers:
		var n := MapBunker.new()
		n.kind = b["kind"]
		var f: Vector2 = b["face"]
		_add("Противник/ДЗОТи", n, "ДЗОТ" if b["kind"] == "mg" else "Бліндаж", b["pos"], atan2(-f.x, -f.y))
		bunker_nodes.append(n)
	for w in def.wire:
		_add_path("Загородження", MapWire.new(), "Дріт", w)
	for t in def.teeth:
		var n := MapTeeth.new()
		n.rows = int(t.get("rows", 2))
		_add_path("Загородження", n, "Зуби", t["pts"])
	for m in def.minefields:
		var n := MapMinefield.new()
		n.width = m["w"]
		n.density = m["density"]
		n.mine_type = m["type"]
		_add_path("Загородження", n, "Міни", m["pts"])
	for c in def.camo:
		var n := MapCamo.new()
		n.radius = c.z
		_add("Противник/Маскування", n, "Маскування", Vector2(c.x, c.y))
	for e in def.ew_stations:
		_add("Противник/РЕБ", _ew("station"), "РЕБ", e)
	for e in def.ew_decoys:
		_add("Противник/РЕБ", _ew("decoy"), "РЕБ макет", e)
	for e in def.ew_backups:
		_add("Противник/РЕБ", _ew("backup"), "РЕБ запасна", e)
	for s in def.smoke_columns:
		_add("Вирви", MapSmokeColumn.new(), "Дим", s)
	for t in def.enemy_teams:
		var n := MapEnemyTeam.new()
		n.team_name = t["name"]
		n.roles = PackedStringArray(t["roles"])
		n.reserve = bool(t.get("reserve", false))
		var all: Array = t["slots"] + t["alt"] + t["fallback"]
		var cen := Vector2.ZERO
		for p in t["slots"]:
			cen += p
		cen /= maxf(1.0, t["slots"].size())
		_add("Противник", n, String(t["name"]), cen)
		for key in ["slots", "alt", "fallback"]:
			for p in t[key]:
				var sl := MapSlot.new()
				sl.kind = "slot" if key == "slots" else key
				sl.name = {"slots": "Позиція", "alt": "Запасна", "fallback": "Відхід"}[key]
				sl.position = Vector3(p.x - cen.x, 0, p.y - cen.y)
				n.add_child(sl, true)
				sl.owner = root
		if t.has("bunker"):
			n.bunker = n.get_path_to(bunker_nodes[int(t["bunker"])])
	for p in def.enemy_fallback:
		_marker("enemy_fallback", Vector3(p.x, 0, p.y))
	_marker("player_entry", def.player_entry, def.player_entry_dir)
	_marker("foot_spawn", def.foot_spawn)
	_marker("medevac_entry", def.medevac_entry)
	_marker("rally_point", def.rally_point)
	_marker("enemy_retreat", def.enemy_retreat)
	_marker("camera_start", def.camera_start)
	_marker("photo_center", def.photo_center)
	for p in def.dismount_points:
		_marker("dismount", p)
	for o in def.deploy_options:
		var n := MapMarker.new()
		n.kind = "deploy_option"
		n.label = o["name"]
		n.desc = String(o.get("desc", ""))
		var ax: Vector2 = o.get("axis", Vector2(1, 0))
		_add("Маркери", n, "Район висадки " + String(o["name"]), o["pos"], atan2(-ax.y, ax.x))
	_area("deploy_zone", def.deploy_zone)
	_area("objective", def.objective_rect)
	_area("capture", def.capture_rect)
	_area("mortar_zone", def.mortar_zone)
	for m in def.intel.get("markers", []):
		var n := MapIntelMarker.new()
		n.label = m["label"]
		n.radius = m["r"]
		_add("Розвіддані", n, "Позначка " + String(m["label"]), m["pos"])
	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, out_path)
	print("[CONVERT] %s -> %s (%s), nodes %d" % [def.id, out_path, error_string(err), MapScene._all(root).size()])
	root.free()


func _ew(kind: String) -> MapEW:
	var n := MapEW.new()
	n.kind = kind
	return n


func _group(path: String) -> Node3D:
	if groups.has(path):
		return groups[path]
	var parent: Node = root
	var acc := ""
	for part in path.split("/"):
		acc = part if acc == "" else acc + "/" + part
		if not groups.has(acc):
			var g := Node3D.new()
			g.name = part
			parent.add_child(g)
			g.owner = root
			groups[acc] = g
		parent = groups[acc]
	return parent


func _add(group: String, n: Node3D, nm: String, p: Vector2, rot: float = 0.0) -> void:
	n.name = nm
	n.position = Vector3(p.x, 0, p.y)
	n.rotation.y = rot
	_group(group).add_child(n, true)
	n.owner = root


func _add_path(group: String, n: Path3D, nm: String, pts: PackedVector2Array) -> void:
	n.name = nm
	n.curve = Curve3D.new()
	for p in pts:
		n.curve.add_point(Vector3(p.x, 0, p.y))
	_group(group).add_child(n, true)
	n.owner = root


func _marker(kind: String, p: Vector3, dir: Vector3 = Vector3.ZERO) -> void:
	if p == Vector3.ZERO and kind in ["camera_start", "photo_center", "medevac_entry", "foot_spawn"]:
		return
	var n := MapMarker.new()
	n.kind = kind
	_add("Маркери", n, MapMarker.NAMES.get(kind, kind), Vector2(p.x, p.z), atan2(-dir.x, -dir.z) if dir != Vector3.ZERO else 0.0)


func _area(kind: String, r: Rect2) -> void:
	if r.size == Vector2.ZERO:
		return
	var n := MapArea.new()
	n.kind = kind
	n.size = r.size
	_add("Маркери", n, {"objective": "Ціль", "capture": "Зона захоплення", "mortar_zone": "Пристріляна зона", "deploy_zone": "Зона висадки"}[kind], r.get_center())


# ------------------------------------------------------------------ verification
## Differences between two map descriptions (tolerance 0.02 m).
static func diff(a: MapDef, b: MapDef) -> Array:
	var out: Array = []
	for k in ["id", "title", "size", "seed", "relief", "time_limit", "environment", "palette", "treelines", "bushes", "roads", "trenches",
			"craters", "houses", "sheds", "fences", "bales", "poles", "wrecks", "bunkers", "sandbags", "wire", "burnt", "smoke_columns",
			"ew_stations", "ew_decoys", "ew_backups", "player_entry", "player_entry_dir", "dismount_points", "foot_spawn", "medevac_entry",
			"rally_point", "enemy_retreat", "objective_rect", "capture_rect", "enemy_teams", "enemy_fallback", "intel", "photo_center",
			"photo_height", "photo_size", "minefields", "camera_start", "objective", "secondary", "diff_override", "fixed_loadout",
			"enemy_no_retreat", "mortar_zone", "camo", "dugouts", "teeth", "apartments", "blocks", "cars", "deploy_options", "deploy_zone", "budget_bonus", "extra_max"]:
		var why := _cmp(a.get(k), b.get(k))
		if why != "":
			out.append("%s: %s" % [k, why])
	var na := MapHeights.make_noises(a.seed)
	var worst := 0.0
	var x := -a.size * 0.5
	while x <= a.size * 0.5:
		var z := -a.size * 0.5
		while z <= a.size * 0.5:
			worst = maxf(worst, absf(a.ground_height(x, z, na) - b.ground_height(x, z, na)))
			z += 1.6
		x += 1.6
	if worst > 0.02:
		out.append("heights: max diff %.3f m" % worst)
	return out


static func _cmp(x, y) -> String:
	if typeof(x) in [TYPE_FLOAT, TYPE_INT] and typeof(y) in [TYPE_FLOAT, TYPE_INT]:
		return "" if absf(float(x) - float(y)) < 0.02 else "%s != %s" % [x, y]
	if x is Vector2 or x is Vector3 or x is Rect2:
		if typeof(x) != typeof(y):
			return "type"
		var ax: Array = [x.x, x.y] if x is Vector2 else ([x.x, x.y, x.z] if x is Vector3 else [x.position.x, x.position.y, x.size.x, x.size.y])
		var ay: Array = [y.x, y.y] if y is Vector2 else ([y.x, y.y, y.z] if y is Vector3 else [y.position.x, y.position.y, y.size.x, y.size.y])
		for i in ax.size():
			if absf(float(ax[i]) - float(ay[i])) > 0.02:
				return "%s != %s" % [x, y]
		return ""
	if x is Array or x is PackedVector2Array or x is PackedStringArray:
		var ya = Array(y) if (y is Array or y is PackedVector2Array or y is PackedStringArray) else null
		if ya == null:
			return "type"
		var xa := Array(x)
		if xa.size() != ya.size():
			return "size %d != %d" % [xa.size(), ya.size()]
		for i in xa.size():
			var w := _cmp(xa[i], ya[i])
			if w != "":
				return "[%d] %s" % [i, w]
		return ""
	if x is Dictionary:
		if not (y is Dictionary):
			return "type"
		for k in x.keys():
			if not y.has(k):
				return "missing key %s" % k
			var w := _cmp(x[k], y[k])
			if w != "":
				return "%s: %s" % [k, w]
		for k in y.keys():
			if not x.has(k):
				return "extra key %s" % k
		return ""
	return "" if x == y else "%s != %s" % [str(x).left(60), str(y).left(60)]
