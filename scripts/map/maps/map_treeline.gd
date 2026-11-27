extends MapDef
## Mission 1 — "ПОСАДКА": enemy strongpoint along a shelled tree line,
## open field in front, ruined farmstead on the west flank, dirt road east.


func setup() -> void:
	id = "treeline"
	title = "ПОСАДКА"
	subtitle = "Опорний пункт противника в лісосмузі"
	terrain_type = "Лісосмуга / поле"
	task_text = "Висунутися до лісосмуги, знищити або витіснити противника та захопити його позиції."
	terrain_desc = "Район 300×300 м. Відкрите поле ~70 м перед ворожою лісосмугою, посіченою обстрілами. " + \
		"Захід: балка з чагарником і поперечна лісосмуга — прихований підхід до флангу. " + \
		"Схід: дорога, хутір і ще одна поперечна посадка. Перед окопами — мінні загородження з проходами."
	size = 300.0
	seed = 4127
	relief = 0.85
	time_limit = 30.0 * 60.0

	treelines = [
		{"rect": Rect2(-120, -50, 165, 17), "density": 1.0, "dead": 0.3},    # enemy tree line
		{"rect": Rect2(54, -47, 76, 13), "density": 0.9, "dead": 0.4},
		{"rect": Rect2(-138, 51, 176, 9), "density": 0.85, "dead": 0.12},   # our tree line
		{"rect": Rect2(56, 52, 70, 8), "density": 0.8, "dead": 0.15},
		{"rect": Rect2(-146, 110, 190, 8), "density": 0.8, "dead": 0.1},    # far south
		{"rect": Rect2(54, 110, 92, 8), "density": 0.8, "dead": 0.1},
		{"rect": Rect2(-104, -24, 10, 75), "density": 0.85, "dead": 0.3},   # west cross tree line (covered approach)
		{"rect": Rect2(86, -30, 9, 82), "density": 0.8, "dead": 0.3},       # east cross tree line
		{"rect": Rect2(-146, -114, 292, 13), "density": 0.95, "dead": 0.2},  # enemy rear
		{"rect": Rect2(53, -100, 8, 52), "density": 0.75, "dead": 0.25},    # belt along the road, enemy side
		{"rect": Rect2(-30, -100, 70, 9), "density": 0.85, "dead": 0.2},    # between the lines, enemy depth
		{"rect": Rect2(-128, 6, 14, 14), "density": 0.7, "dead": 0.4},      # grove at the west farmstead
		{"rect": Rect2(96, 26, 16, 10), "density": 0.7, "dead": 0.3},       # grove at the east farmstead
	]
	roads = [
		{"pts": PackedVector2Array([Vector2(48, 152), Vector2(46, 100), Vector2(46, 45), Vector2(50, 5), Vector2(48, -40), Vector2(45, -100), Vector2(40, -152)]), "w": 5.0},
		{"pts": PackedVector2Array([Vector2(150, 62), Vector2(46, 64), Vector2(12, 64.5), Vector2(-30, 65), Vector2(-152, 63)]), "w": 3.6},
		{"pts": PackedVector2Array([Vector2(-152, -73), Vector2(-40, -76), Vector2(46, -74), Vector2(152, -70)]), "w": 3.6},
		{"pts": PackedVector2Array([Vector2(46, 20), Vector2(80, 18), Vector2(104, 12), Vector2(152, 10)]), "w": 3.0},
		{"pts": PackedVector2Array([Vector2(-49, 64), Vector2(-50, 30), Vector2(-48, 14)]), "w": 2.6},
	]
	# An old, lived-in position along the tree line (drone footage reference):
	# fire trench with short traverses, firing cells pushed forward, meandering
	# communication trenches, a second line and a rear trench under the trees,
	# log-roofed dugouts at the ends of short spurs. Spoil is grassed over.
	var trng := RandomNumberGenerator.new()
	trng.seed = seed + 5
	var main := MapDef.traversed(PackedVector2Array([Vector2(-86, -27.5), Vector2(-66, -27.5), Vector2(-58, -30), Vector2(-48, -27),
		Vector2(-28, -27.5), Vector2(-3, -29), Vector2(12, -27.5), Vector2(22, -31), Vector2(40, -31)]), 4.5, 1.2)
	var second := MapDef.traversed(PackedVector2Array([Vector2(-44, -40), Vector2(-24, -39.5), Vector2(-5, -41), Vector2(16, -39.5), Vector2(24, -38)]), 4.0, 1.0)
	var rear := MapDef.traversed(PackedVector2Array([Vector2(-32, -53), Vector2(-8, -53), Vector2(16, -54)]), 5.0, 0.9)
	trenches = [
		main,
		PackedVector2Array([Vector2(-58, -30), Vector2(-54, -33.5)]),                      # to MG bunker
		MapDef.meander(PackedVector2Array([Vector2(-3, -29), Vector2(-4, -36), Vector2(-5, -41)]), trng, 3.5, 0.6),   # comm to dugout
		PackedVector2Array([Vector2(-5, -45), Vector2(-3, -53)]),                          # dugout to rear
		MapDef.meander(PackedVector2Array([Vector2(22, -31), Vector2(24, -38), Vector2(20, -46), Vector2(16, -54)]), trng, 4.0, 0.7),
		rear,
		second,
		MapDef.meander(PackedVector2Array([Vector2(-48, -27), Vector2(-46, -34), Vector2(-44, -40)]), trng, 3.5, 0.6),
		PackedVector2Array([Vector2(-32, -36.5), Vector2(-28, -37), Vector2(-27, -40.3)]), # ATGM pit west
		PackedVector2Array([Vector2(11, -36), Vector2(15, -35.5), Vector2(15, -40)]),      # ATGM pit east
		PackedVector2Array([Vector2(40, -31), Vector2(38.5, -34)]),                        # to east MG bunker
		MapDef.traversed(PackedVector2Array([Vector2(60, -29), Vector2(68, -32), Vector2(76, -29)]), 4.0, 0.9),   # east outpost
		MapDef.meander(PackedVector2Array([Vector2(-66, -27.5), Vector2(-62, -40), Vector2(-44, -40)]), trng, 4.0, 0.8),   # west flank to 2nd line
	]
	# dugouts at the ends of short spurs behind the lines
	for sp in [[Vector2(-34, -42), Vector2(-34.5, -46)], [Vector2(6, -42), Vector2(7, -46)], [Vector2(-20, -56), Vector2(-20.5, -60)],
			[Vector2(4, -56), Vector2(4.5, -60)], [Vector2(-75, -27.5), Vector2(-76, -33)], [Vector2(68, -32), Vector2(68.5, -36)]]:
		var spur := PackedVector2Array(sp)
		trenches.append(spur)
		dugout_at_end(spur)
	bunkers = [
		{"pos": Vector2(-53, -35.5), "face": Vector2(0.55, 1.0), "kind": "mg"},
		{"pos": Vector2(-5, -43), "face": Vector2(0, 1), "kind": "dugout"},
		{"pos": Vector2(38, -35.5), "face": Vector2(-0.35, 1.0), "kind": "mg"},
	]
	sandbags = [
		{"pos": Vector2(32.5, -26.2), "rot": 0.25, "len": 4.0},
		{"pos": Vector2(-13, -27.6), "rot": -0.2, "len": 3.0},
		{"pos": Vector2(-43, -27.3), "rot": 0.2, "len": 3.0},
		{"pos": Vector2(-51, -32.0), "rot": 0.5, "len": 3.0},
		{"pos": Vector2(-30, -35.0), "rot": 0.05, "len": 3.0},
		{"pos": Vector2(13, -34.3), "rot": -0.05, "len": 3.0},
		{"pos": Vector2(-34, -40.6), "rot": 0.15, "len": 2.5},
		{"pos": Vector2(6, -40.6), "rot": -0.1, "len": 2.5},
	]
	wire = [
		PackedVector2Array([Vector2(-52, -20), Vector2(-38, -21.5), Vector2(-24, -20.5)]),
		PackedVector2Array([Vector2(-12, -20.5), Vector2(6, -21.5), Vector2(24, -20.0), Vector2(36, -21.5)]),
		PackedVector2Array([Vector2(-66, -22), Vector2(-56, -21)]),
	]
	houses = [
		{"pos": Vector2(-50, 9), "size": Vector2(9, 6.5), "rot": 0.18, "ruin": 0.55},
		{"pos": Vector2(-36, 20), "size": Vector2(6, 5), "rot": -0.12, "ruin": 0.75},
		{"pos": Vector2(102, 22), "size": Vector2(8, 6), "rot": 0.1, "ruin": 0.5},
		{"pos": Vector2(116, 8), "size": Vector2(7, 6), "rot": -0.2, "ruin": 0.7},
		{"pos": Vector2(-120, 18), "size": Vector2(8, 6), "rot": 0.3, "ruin": 0.8},
	]
	sheds = [
		{"pos": Vector2(37, 7), "size": Vector2(7, 5), "rot": -0.08},
		{"pos": Vector2(108, -4), "size": Vector2(9, 6), "rot": 0.05},
	]
	fences = [
		PackedVector2Array([Vector2(-58, 2), Vector2(-42, 0), Vector2(-40, 14)]),
		PackedVector2Array([Vector2(-58, 2), Vector2(-60, 18), Vector2(-44, 22)]),
	]
	bales = [Vector2(10, 14), Vector2(13, 15.5), Vector2(11.5, 17.5), Vector2(-18, 33), Vector2(-15.5, 34.5), Vector2(22, -6)]
	for z in range(146, -150, -17):
		poles.append(Vector2(43.0 + sin(z * 0.1) * 0.6, float(z)))
	wrecks = [
		{"pos": Vector2(49.2, -8), "rot": 2.6, "model": "bmp1"},
		{"pos": Vector2(18, 27), "rot": -0.7, "model": "m113"},
	]
	burnt = [Vector3(49, -8, 6), Vector3(18, 27, 5), Vector3(-50, 9, 7)]
	ew_stations = [Vector2(-21, -51), Vector2(15, -50.5)]
	ew_decoys = [Vector2(-62, -52)]
	ew_backups = [Vector2(-6, -68), Vector2(32, -66)]
	minefields = [
		{"pts": PackedVector2Array([Vector2(-62, -17), Vector2(-46, -18), Vector2(-26, -16.5)]), "w": 6.0, "density": 0.055, "type": "ap"},
		{"pts": PackedVector2Array([Vector2(-6, -16.5), Vector2(18, -17.5), Vector2(36, -16.5)]), "w": 6.0, "density": 0.055, "type": "ap"},
		{"pts": PackedVector2Array([Vector2(-30, 3), Vector2(-6, 1), Vector2(16, 4)]), "w": 10.0, "density": 0.02, "type": "at"},
		{"pts": PackedVector2Array([Vector2(48.5, -16), Vector2(49.5, -4)]), "w": 5.0, "density": 0.07, "type": "at"},
		{"pts": PackedVector2Array([Vector2(16, -9), Vector2(38, -11)]), "w": 8.0, "density": 0.018, "type": "at"},
		{"pts": PackedVector2Array([Vector2(-88, -15), Vector2(-74, -17)]), "w": 5.0, "density": 0.05, "type": "ap"},
		{"pts": PackedVector2Array([Vector2(60, -19), Vector2(76, -20)]), "w": 5.0, "density": 0.05, "type": "ap"},
	]
	smoke_columns = [Vector2(49.2, -8), Vector2(-62, -40)]
	bushes = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# the western gully is overgrown: concealed approach
	for z in range(44, -14, -5):
		bushes.append(Vector3(-76.0 + rng.randf_range(-3, 3), float(z), rng.randf_range(2.0, 3.5)))
	for i in 40:
		var p := Vector2(rng.randf_range(-145, 145), rng.randf_range(-100, 105))
		if absf(p.x - 48) < 6 or (p.y > -60 and p.y < -12 and absf(p.x) < 90):
			continue
		bushes.append(Vector3(p.x, p.y, rng.randf_range(1.2, 3.0)))
	for i in 26:
		var p := Vector2(rng.randf_range(-74, 74), rng.randf_range(-12, 46))
		if absf(p.x - 48) < 6:
			continue
		bushes.append(Vector3(p.x, p.y, rng.randf_range(1.2, 3.0)))
	for i in range(0, main.size(), 2):
		bushes.append(Vector3(main[i].x + rng.randf_range(-1.5, 1.5), main[i].y - 3.6, rng.randf_range(0.7, 1.1)))
	craters = []
	var big := [Vector3(-20, -10, 3.2), Vector3(8, -14, 2.8), Vector3(-34, 6, 3.0), Vector3(26, 12, 2.6),
		Vector3(0, 24, 3.4), Vector3(-6, -2, 2.4), Vector3(34, -12, 2.4), Vector3(-44, -12, 2.6)]
	craters.append_array(big)
	var tries := 0
	while craters.size() < 110 and tries < 900:
		tries += 1
		var c := Vector3(rng.randf_range(-145, 145), rng.randf_range(-105, 105), rng.randf_range(0.9, 2.2))
		if absf(c.x - 48) < 5:
			continue
		if c.z > -60 and c.z < -22 and c.x < 80 and c.x > -90:
			continue   # keep trench line readable
		craters.append(c)

	player_entry = Vector3(48, 0, 145)
	dismount_points = [Vector3(-24, 0, 67), Vector3(2, 0, 67), Vector3(26, 0, 67), Vector3(-44, 0, 67), Vector3(-96, 0, 66), Vector3(90, 0, 67)]
	foot_spawn = Vector3(10, 0, 128)
	medevac_entry = Vector3(47.5, 0, 145)
	rally_point = Vector3(5, 0, 75)
	enemy_retreat = Vector3(-6, 0, -142)
	objective_rect = Rect2(-62, -44, 106, 22)
	capture_rect = Rect2(-90, -50, 170, 30)
	camera_start = Vector3(10, 0, 75)
	mortar_zone = Rect2(-70, -24, 140, 59)
	secondary = [{"type": "ew"}, {"type": "evac_all"}]
	photo_size = 120.0
	photo_center = Vector3(-8, 0, -32)
	photo_height = 105.0

	enemy_teams = [
		{"name": "Захід", "roles": ["rifleman", "mg", "rifleman"],
			"slots": [Vector2(-48, -27), Vector2(-43, -29), Vector2(-38, -31)],
			"alt": [Vector2(-33, -29), Vector2(-53, -28.5), Vector2(-28, -27)],
			"fallback": [Vector2(-32, -53), Vector2(-26, -54.5), Vector2(-20, -56)]},
		{"name": "Центр", "roles": ["leader", "rifleman", "at", "rifleman"],
			"slots": [Vector2(-18, -31), Vector2(-13, -29), Vector2(-8, -27), Vector2(-3, -29)],
			"alt": [Vector2(2, -31), Vector2(-23, -29), Vector2(7, -29)],
			"fallback": [Vector2(-14, -54.5), Vector2(-8, -53), Vector2(-2, -54.5), Vector2(4, -56)]},
		{"name": "Схід", "roles": ["mg", "rifleman", "grenadier"],
			"slots": [Vector2(32, -28), Vector2(27, -29.5), Vector2(22, -31)],
			"alt": [Vector2(12, -27), Vector2(17, -29), Vector2(24, -38)],
			"fallback": [Vector2(10, -55), Vector2(16, -54), Vector2(20, -46)]},
		{"name": "ДЗОТ", "roles": ["mg", "rifleman"], "bunker": 0,
			"slots": [Vector2(-53, -35.2), Vector2(-54.2, -36)], "alt": [],
			"fallback": [Vector2(-32, -53), Vector2(-26, -54.5)]},
		{"name": "Резерв", "roles": ["rifleman", "rifleman", "mg", "at"], "bunker": 1, "reserve": true,
			"slots": [Vector2(-5, -43), Vector2(-4, -43.6), Vector2(-6, -43.6), Vector2(-5, -44.2)], "alt": [],
			"fallback": [Vector2(-8, -53), Vector2(-2, -54.5), Vector2(4, -56), Vector2(-14, -54.5)]},
		{"name": "Друга лінія", "roles": ["leader", "rifleman", "at", "mg"],
			"slots": [Vector2(-24, -39.5), Vector2(-14, -42), Vector2(6, -42), Vector2(16, -39.5)],
			"alt": [Vector2(-34, -42), Vector2(-5, -41), Vector2(24, -38)],
			"fallback": [Vector2(-20, -56), Vector2(-8, -53), Vector2(4, -56), Vector2(16, -54)]},
		{"name": "ПТРК-Захід", "roles": ["atgm", "rifleman"],
			"slots": [Vector2(-30, -36.6), Vector2(-28, -37)], "alt": [Vector2(-34, -42)],
			"fallback": [Vector2(-26, -54.5), Vector2(-32, -53)]},
		{"name": "ПТРК-Схід", "roles": ["atgm", "rifleman"],
			"slots": [Vector2(13, -35.8), Vector2(15, -35.6)], "alt": [Vector2(16, -39.5)],
			"fallback": [Vector2(10, -55), Vector2(16, -54)]},
		{"name": "ДЗОТ-Схід", "roles": ["mg", "rifleman"], "bunker": 2,
			"slots": [Vector2(38, -35.2), Vector2(37, -36)], "alt": [],
			"fallback": [Vector2(16, -54), Vector2(20, -46)]},
		{"name": "Фланг-Захід", "roles": ["rifleman", "mg", "rifleman"],
			"slots": [Vector2(-76, -30), Vector2(-70, -28.7), Vector2(-82, -28.6)], "alt": [Vector2(-66, -27.5)],
			"fallback": [Vector2(-32, -53), Vector2(-44, -40)]},
		{"name": "Схід-Застава", "roles": ["rifleman", "at"],
			"slots": [Vector2(68, -32), Vector2(72, -30.5)], "alt": [Vector2(62, -29.6)],
			"fallback": [Vector2(16, -54), Vector2(24, -38)]},
	]
	intel = {
		"age": "знімок зроблено 6 год тому",
		"estimate": "15–20 осіб",
		"lines": [
			"Окопи повного профілю вздовж південного краю лісосмуги.",
			"Ймовірна кулеметна точка (ДЗОТ) на західному фланзі.",
			"У центрі лісосмуги — ймовірний бліндаж (можливий резерв).",
			"Перед окопами — колючий дріт і мінні загородження. Ймовірний прохід у центрі (противник ходить ним сам).",
			"Фланги прикриті окремими окопами; західна балка та поперечні посадки дають прихований підхід.",
			"Друга лінія окопів у глибині лісосмуги, тилова траншея за нею.",
			"Ймовірні розрахунки ПТРК — небезпечно для техніки на відкритій місцевості.",
			"Противник застосовує FPV-дрони по техніці та скупченнях піхоти.",
			"Працює РЕБ: низько підлетіти дроном до лісосмуги неможливо. РЕР пеленгує дрони, що довго висять у зоні РЕБ.",
		],
		"markers": [
			{"pos": Vector2(-53, -35), "label": "ДЗОТ / КУЛЕМЕТ?", "r": 6.0},
			{"pos": Vector2(-5, -43), "label": "БЛІНДАЖ?", "r": 6.0},
			{"pos": Vector2(-12, -29), "label": "ОКОП 3–5 ОС.", "r": 11.0},
			{"pos": Vector2(-42, -29), "label": "ОКОП", "r": 8.0},
			{"pos": Vector2(28, -29), "label": "ВОГН. ТОЧКА?", "r": 7.0},
			{"pos": Vector2(-29, -37), "label": "ПТРК?", "r": 6.0},
			{"pos": Vector2(-10, -41), "label": "2-А ЛІНІЯ", "r": 12.0},
			{"pos": Vector2(-18, -52), "label": "РЕБ?", "r": 7.0},
		],
	}


func extra_height(x: float, z: float) -> float:
	# gentle rise towards the north (enemy holds slightly higher ground)
	var h := clampf(-z * 0.012, -1.4, 1.4) + sin(x * 0.03) * 0.25
	# western gully (balka): covered approach to the enemy's west flank
	if z > -18.0 and z < 50.0:
		var k := clampf(minf(z + 18.0, 50.0 - z) / 10.0, 0.0, 1.0)
		h -= 1.9 * k * exp(-pow((x + 76.0) / 6.5, 2.0))
	return h
