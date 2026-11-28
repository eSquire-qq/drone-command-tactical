extends MapDef
## Village — «ХУТІР»: the enemy holds a farmstead village on a low rise:
##  * two rows of houses along the main street; the southern row faces the
##    field and fires from its windows (fight in buildings: window posts,
##    doors, breaches); a big brick house on the northern row covers the
##    street;
##  * a short trench with an MG bunker at the southern edge, wire in front,
##    AT mines on the road into the village;
##  * the field in front is plotted for the enemy mortar; covered approaches:
##    the orchard and gardens on the west, the gully on the east;
##  * yards with fences and sheds — short sight lines, fighting from yard to yard.


func setup() -> void:
	Environments.apply(self, "village")
	id = "village"
	title = "ХУТІР"
	subtitle = "Опорний пункт у сільській забудові"
	terrain_type = "Сільська забудова"
	task_text = "Вибити противника з хутора: зачистити садиби південного ряду, захопити центр хутора й перехрестя — і втримати хутір 5 хв: противник контратакуватиме резервом із тилу."
	terrain_desc = "Район 260×260 м. Хутір на пологому підвищенні: два ряди хат уздовж головної вулиці, подвір'я з парканами й сараями, городи. " + \
		"Перед хутором ~80 м відкритого поля з вирвами. Захід: старий сад і городи — прихований підхід. Схід: неглибока балка до крайніх садиб. " + \
		"Дорога з півдня веде просто на перехрестя."
	size = 260.0
	seed = 4417
	relief = 0.6
	time_limit = 30.0 * 60.0
	budget_bonus = 250   # a harder operation: more points for the force
	extra_max = {"assault_group": 1}

	treelines = [
		{"rect": Rect2(-130, 98, 260, 22), "density": 0.95, "dead": 0.12},     # our tree line (start), deep enough to hide the assembly
		{"rect": Rect2(-130, -112, 260, 12), "density": 0.85, "dead": 0.2},    # belt behind the village
		{"rect": Rect2(-112, -72, 32, 52), "density": 0.55, "dead": 0.25},     # old orchard (west)
		{"rect": Rect2(-112, -16, 22, 40), "density": 0.45, "dead": 0.3},      # orchard edge / gardens
		{"rect": Rect2(84, -70, 22, 30), "density": 0.7, "dead": 0.3},         # grove east
		{"rect": Rect2(-6, -74, 10, 8), "density": 0.6, "dead": 0.2},          # trees in the yard of the brick house
		{"rect": Rect2(-128, 30, 10, 60), "density": 0.7, "dead": 0.3},        # western windbreak
	]
	for c in [Vector2(-75, 50), Vector2(55, 60), Vector2(-48, 30), Vector2(30, 40), Vector2(75, 20), Vector2(-20, 70)]:
		treelines.append({"rect": Rect2(c.x - 2.5, c.y - 2.5, 5, 5), "density": 0.6, "dead": 0.35})
	roads = [
		{"pts": PackedVector2Array([Vector2(4, 132), Vector2(2, 90), Vector2(-2, 40), Vector2(0, 0), Vector2(0, -30), Vector2(-2, -80), Vector2(4, -132)]), "w": 4.0},
		{"pts": PackedVector2Array([Vector2(-132, -32), Vector2(-60, -30), Vector2(0, -30), Vector2(60, -31), Vector2(132, -28)]), "w": 3.6},
		{"pts": PackedVector2Array([Vector2(-132, 124), Vector2(0, 123), Vector2(132, 124)]), "w": 3.0},
	]
	# the farmsteads: southern row faces the field, northern row the street
	houses = [
		{"pos": Vector2(-62, -12), "size": Vector2(8, 6), "rot": 0.05, "ruin": 0.55},
		{"pos": Vector2(-36, -12), "size": Vector2(9, 7), "rot": 0.0, "ruin": 0.35},
		{"pos": Vector2(-13, -13), "size": Vector2(8, 6), "rot": 0.08, "ruin": 0.5},
		{"pos": Vector2(18, -12), "size": Vector2(9, 7), "rot": -0.05, "ruin": 0.3},
		{"pos": Vector2(42, -13), "size": Vector2(8, 6), "rot": 0.0, "ruin": 0.6},
		{"pos": Vector2(66, -11), "size": Vector2(7, 6), "rot": 0.1, "ruin": 0.75},
		{"pos": Vector2(-56, -48), "size": Vector2(9, 7), "rot": 0.0, "ruin": 0.4},
		{"pos": Vector2(-26, -48), "size": Vector2(8, 6), "rot": 0.05, "ruin": 0.45},
		{"pos": Vector2(14, -50), "size": Vector2(13, 9), "rot": 0.0, "ruin": 0.2},
		{"pos": Vector2(44, -48), "size": Vector2(8, 6), "rot": -0.1, "ruin": 0.5},
	]
	sheds = [
		{"pos": Vector2(-66, 0), "size": Vector2(6, 5), "rot": 0.05},
		{"pos": Vector2(-24, 1), "size": Vector2(5, 4), "rot": -0.1},
		{"pos": Vector2(30, 0), "size": Vector2(6, 5), "rot": 0.0},
		{"pos": Vector2(58, 1), "size": Vector2(5, 4), "rot": 0.15},
		{"pos": Vector2(-44, -62), "size": Vector2(6, 5), "rot": 0.0},
		{"pos": Vector2(32, -63), "size": Vector2(6, 5), "rot": -0.05},
	]
	# yard fences of the southern row (open towards the street)
	fences = []
	for h in [Vector2(-62, -12), Vector2(-36, -12), Vector2(-13, -13), Vector2(18, -12), Vector2(42, -13)]:
		fences.append(PackedVector2Array([Vector2(h.x - 10, -24), Vector2(h.x - 10, 6), Vector2(h.x + 3, 7)]))
	for h in [Vector2(-56, -48), Vector2(-26, -48), Vector2(44, -48)]:
		fences.append(PackedVector2Array([Vector2(h.x - 9, -38), Vector2(h.x - 9, -64), Vector2(h.x + 9, -64)]))
	poles = [Vector2(-80, -36), Vector2(-40, -35), Vector2(5, -36), Vector2(50, -36), Vector2(90, -34), Vector2(6, 30), Vector2(7, 70)]
	bales = [Vector2(-90, 30), Vector2(-86, 32), Vector2(-88, 35), Vector2(60, 46)]
	wrecks = [{"pos": Vector2(-8, 34), "rot": 0.4, "model": "bmp1"}]
	burnt = [Vector3(-8, 34, 5), Vector3(66, -11, 6), Vector3(-62, -12, 4)]
	smoke_columns = [Vector2(66, -11)]
	# enemy field fortification at the southern edge
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var front := MapDef.traversed(PackedVector2Array([Vector2(-26, 6), Vector2(-8, 4), Vector2(8, 4), Vector2(24, 6)]), 4.0, 1.0)
	trenches = [front]
	bunkers = [
		{"pos": Vector2(-44, 5), "face": Vector2(0.15, 1.0), "kind": "mg"},
	]
	sandbags = [
		{"pos": Vector2(0, 8), "rot": 0.0, "len": 4.0},
		{"pos": Vector2(2, -26), "rot": 0.0, "len": 4.0},       # crossroads
		{"pos": Vector2(36, -5), "rot": 0.2, "len": 3.0},
	]
	wire = [
		PackedVector2Array([Vector2(-58, 14), Vector2(-30, 15), Vector2(-6, 14)]),
		PackedVector2Array([Vector2(6, 14), Vector2(30, 15), Vector2(52, 13)]),
	]
	minefields = [
		{"pts": PackedVector2Array([Vector2(-2, 26), Vector2(0, 16)]), "w": 7.0, "density": 0.05, "type": "at"},     # the road into the village
		{"pts": PackedVector2Array([Vector2(-50, 22), Vector2(-20, 22)]), "w": 5.0, "density": 0.035, "type": "ap"},
		{"pts": PackedVector2Array([Vector2(20, 22), Vector2(48, 21)]), "w": 5.0, "density": 0.035, "type": "ap"},
	]
	ew_stations = [Vector2(10, -84)]
	ew_decoys = [Vector2(-70, -70)]
	ew_backups = [Vector2(40, -88)]
	bushes = []
	# gardens behind the southern yards and along the fences
	for x in range(-96, 80, 7):
		if absf(x) < 8:
			continue
		bushes.append(Vector3(x + rng.randf_range(-2, 2), -2.0 + rng.randf_range(-3, 3), rng.randf_range(1.0, 1.8)))
	for i in 30:
		var p := Vector2(rng.randf_range(-120, 120), rng.randf_range(20, 90))
		if absf(p.x - 1) < 6:
			continue
		bushes.append(Vector3(p.x, p.y, rng.randf_range(1.0, 2.2)))
	# gully (east): scrub along it
	for i in 16:
		var k := float(i) / 15.0
		var p := _gully(k)
		bushes.append(Vector3(p.x + rng.randf_range(-3, 3), p.y + rng.randf_range(-3, 3), rng.randf_range(1.3, 2.4)))
	craters = [Vector3(-30, 40, 2.6), Vector3(14, 52, 3.0), Vector3(-10, 60, 2.4), Vector3(36, 30, 2.6), Vector3(-52, 46, 2.2), Vector3(24, 70, 2.4)]
	var tries := 0
	while craters.size() < 70 and tries < 600:
		tries += 1
		var c := Vector3(rng.randf_range(-120, 120), rng.randf_range(16, 92), rng.randf_range(0.9, 2.2))
		if absf(c.x - 1) < 5:
			continue
		craters.append(c)

	player_entry = Vector3(4, 0, 128)
	foot_spawn = Vector3(10, 0, 125)
	# on the field road behind the tree line: vehicles cannot get into the trees,
	# and a carrier pushed out to the front edge is the ATGM's first target
	dismount_points = [Vector3(-30, 0, 123), Vector3(0, 0, 123), Vector3(30, 0, 123), Vector3(-70, 0, 123), Vector3(70, 0, 123)]
	medevac_entry = Vector3(0, 0, 128)
	rally_point = Vector3(0, 0, 118)
	enemy_retreat = Vector3(4, 0, -126)
	objective_rect = Rect2(-46, -56, 92, 52)
	capture_rect = Rect2(-72, -70, 144, 82)
	camera_start = Vector3(0, 0, 96)
	mortar_zone = Rect2(-90, 10, 180, 72)
	photo_center = Vector3(0, 0, -22)
	photo_size = 175.0
	photo_height = 125.0
	camo = [Vector3(-8, 4, 4.0), Vector3(8, 4, 4.0), Vector3(-44, 5, 4.0)]
	objective = {"type": "hold"}
	secondary = [{"type": "pows", "n": 1}, {"type": "evac_all"}]

	# men placed inside a house take its windows (Buildings.garrison)
	enemy_teams = [
		{"name": "Окоп", "roles": ["rifleman", "mg", "rifleman"],
			"slots": [Vector2(-14, 5), Vector2(0, 4), Vector2(14, 5)], "alt": [Vector2(-22, 6), Vector2(20, 6)],
			"fallback": [Vector2(-13, -13), Vector2(18, -12), Vector2(2, -26)]},
		{"name": "ДЗОТ", "roles": ["mg", "rifleman"], "bunker": 0,
			"slots": [Vector2(-44, 5), Vector2(-45, 4)], "alt": [],
			"fallback": [Vector2(-36, -12), Vector2(-36, -11)]},
		{"name": "Садиба-Захід", "roles": ["rifleman", "mg", "rifleman"],
			"slots": [Vector2(-38, -10), Vector2(-34, -10), Vector2(-39, -13)], "alt": [],
			"fallback": [Vector2(-26, -48), Vector2(-24, -47)]},
		{"name": "Садиба-Центр", "roles": ["leader", "rifleman", "grenadier"],
			"slots": [Vector2(-15, -11), Vector2(-11, -11), Vector2(-13, -15)], "alt": [],
			"fallback": [Vector2(14, -50), Vector2(12, -49)]},
		{"name": "Садиба-Схід", "roles": ["rifleman", "at", "rifleman"],
			"slots": [Vector2(16, -10), Vector2(20, -10), Vector2(21, -14)], "alt": [],
			"fallback": [Vector2(44, -48), Vector2(14, -50)]},
		{"name": "Цегляна хата", "roles": ["mg", "rifleman", "rifleman", "at"],
			"slots": [Vector2(10, -47), Vector2(18, -47), Vector2(8, -52), Vector2(20, -53)], "alt": [],
			"fallback": [Vector2(4, -90), Vector2(10, -92)]},
		{"name": "ПТРК", "roles": ["atgm", "rifleman"],
			"slots": [Vector2(44, -4), Vector2(46, -3)], "alt": [Vector2(56, -6)],
			"fallback": [Vector2(44, -48), Vector2(46, -47)]},
		{"name": "Резерв", "roles": ["rifleman", "rifleman", "mg"], "reserve": true,
			"slots": [Vector2(-28, -47), Vector2(-24, -47), Vector2(-26, -50)], "alt": [],
			"fallback": [Vector2(-56, -48), Vector2(-54, -47)]},
	]
	intel = {
		"age": "знімок зроблено 5 год тому",
		"estimate": "20–26 осіб",
		"lines": [
			"Противник обладнав крайні садиби південного ряду: стрільба з вікон, проломи в стінах можливі.",
			"На південному краї — короткий окоп через дорогу й кулеметний ДЗОТ на західному фланзі; перед ними дріт.",
			"Дорога в хутір ймовірно замінована протитанковими мінами; поле перед хутором пристріляне мінометом.",
			"Цегляна хата на північному ряду проглядає всю вулицю й перехрестя.",
			"Розрахунок ПТРК у дворі східної садиби — техніку в полі буде уражено.",
			"Підходи: старий сад і городи на заході, неглибока балка на сході.",
			"Резерв противника (до двох груп, можливо з БМП) стоїть за хутором — після втрати позиції чекайте контратаку з півночі. Закріпіться в будинках і окопі, зберіть набої.",
			"Будинок займати й зачищати: «Тримати» / «Штурм» з ПКМ по будинку. Граната — у вікно чи двері, вхід через двері або пролом.",
		],
		"markers": [
			{"pos": Vector2(0, 4), "label": "ОКОП", "r": 14.0},
			{"pos": Vector2(-44, 5), "label": "ДЗОТ?", "r": 6.0},
			{"pos": Vector2(-36, -12), "label": "САДИБА", "r": 8.0},
			{"pos": Vector2(-13, -13), "label": "САДИБА", "r": 8.0},
			{"pos": Vector2(18, -12), "label": "САДИБА", "r": 8.0},
			{"pos": Vector2(14, -50), "label": "ЦЕГЛЯНА ХАТА", "r": 10.0},
			{"pos": Vector2(45, -4), "label": "ПТРК?", "r": 7.0},
			{"pos": Vector2(10, -84), "label": "РЕБ?", "r": 9.0},
		],
	}


## The village stands a little higher; the eastern gully leads up to the last yards.
func extra_height(x: float, z: float) -> float:
	var h := clampf(-z * 0.01, -0.9, 0.9)
	var best := INF
	for i in 20:
		best = minf(best, Vector2(x, z).distance_to(_gully(float(i) / 19.0)))
	h -= 2.2 * exp(-pow(best / 6.5, 2.0))
	return h


func _gully(k: float) -> Vector2:
	var pts := [Vector2(100, 96), Vector2(92, 60), Vector2(84, 24), Vector2(74, -6)]
	var f := clampf(k, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return (pts[i] as Vector2).lerp(pts[i + 1], f - i)
