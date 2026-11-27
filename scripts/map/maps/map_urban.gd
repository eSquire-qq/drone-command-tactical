extends MapDef
## City district — «КВАРТАЛ», winter, 560×560 m (after drone footage of a
## burnt-out district under snow).
##  * the south: our forest across the map, snowy fields left and right, a
##    tree belt in the centre that leads from our forest to the city — an
##    enemy outpost and a machine-gun trench inside it; the fields near the
##    city are mined, wired and plotted by the enemy mortars;
##  * forests along both flanks and behind the city — a long, covered way
##    round the fields (forest tracks for the vehicles);
##  * the city: the private sector at its edge, then the FRONT ROW — long
##    burnt-out nine-storey blocks the enemy does NOT hold: the player takes
##    them and fights from their windows; 80–90 m further — the enemy line:
##    three ten-storey towers with a checkpoint between them (the objective),
##    the big dark block on the right with its low annex, the long block on
##    the left; at the top — the school complex (enemy reserve), the private
##    sector all around.
## The deployment point is picked on the briefing photo (deploy_options /
## deploy_zone).


func setup() -> void:
	Environments.apply(self, "winter")
	id = "urban"
	title = "КВАРТАЛ"
	subtitle = "Зимовий бій за міський квартал"
	terrain_type = "Ліс, поля, посадка, міська забудова, зима"
	task_text = "Вийти до міста, зайняти будинки переднього ряду й, ведучи бій з їхніх вікон, захопити центр кварталу — три вежі та блокпост між ними."
	terrain_desc = "Район 560×560 м під снігом. На півдні — наш ліс, далі поля зліва й справа і посадка по центру, що веде до міста; " + \
		"поля біля міста заміновані й пристріляні. Уздовж флангів і за містом — ліс із лісовими дорогами. " + \
		"Місто: приватний сектор на околиці, передній ряд обгорілих дев'ятиповерхівок (противника в них немає — їх можна зайняти), " + \
		"за 80–90 м — рубіж противника: три вежі з блокпостом, великий темний будинок праворуч, довгий будинок ліворуч; угорі — школа."
	size = 560.0
	seed = 9177
	relief = 0.35
	time_limit = 55.0 * 60.0
	budget_bonus = 550   # a harder operation: more points for the force
	extra_max = {"rifle_squad": 1, "assault_group": 1, "m113": 1, "fpv": 2, "smoke": 2}

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	treelines = [
		{"rect": Rect2(-280, 214, 560, 62), "density": 0.75, "dead": 0.5},      # our forest: the whole south edge
		{"rect": Rect2(-280, -276, 54, 490), "density": 0.8, "dead": 0.5},     # left flank forest
		{"rect": Rect2(226, -276, 54, 490), "density": 0.8, "dead": 0.5},      # right flank forest
		{"rect": Rect2(-226, -276, 452, 40), "density": 0.7, "dead": 0.55},     # behind the city
		{"rect": Rect2(-14, 96, 28, 118), "density": 0.85, "dead": 0.55},       # THE BELT: from our forest to the city
		{"rect": Rect2(-10, 80, 20, 16), "density": 0.5, "dead": 0.7},          # its end, thinning out at the city edge
		{"rect": Rect2(-226, 96, 22, 60), "density": 0.6, "dead": 0.6},         # forest tongues towards the city
		{"rect": Rect2(204, 100, 22, 56), "density": 0.6, "dead": 0.6},
		{"rect": Rect2(-222, 14, 34, 40), "density": 0.45, "dead": 0.7},        # groves at the city's flanks
		{"rect": Rect2(192, 62, 34, 30), "density": 0.45, "dead": 0.7},
		# yards inside the city
		{"rect": Rect2(-118, -6, 30, 14), "density": 0.35, "dead": 0.8},
		{"rect": Rect2(78, -70, 30, 14), "density": 0.35, "dead": 0.8},
		{"rect": Rect2(-50, -104, 26, 12), "density": 0.35, "dead": 0.8},
		{"rect": Rect2(-150, -100, 26, 14), "density": 0.35, "dead": 0.8},
	]
	for i in 26:   # lone bare trees in the city (kept off the buildings by the map builder)
		var c := Vector2(rng.randf_range(-200, 200), rng.randf_range(-225, 70))
		treelines.append({"rect": Rect2(c.x - 2, c.y - 2, 4, 4), "density": 0.9, "dead": 0.8})
	for i in 14:   # and in the fields
		var c2 := Vector2(rng.randf_range(-210, 210), rng.randf_range(100, 205))
		if absf(c2.x) < 25:
			continue
		treelines.append({"rect": Rect2(c2.x - 2, c2.y - 2, 4, 4), "density": 0.9, "dead": 0.85})

	apartments = [
		# FRONT ROW — empty: the player's positions
		{"pos": Vector2(-130, 40), "size": Vector2(64, 12), "rot": -0.1, "floors": 9, "ruin": 0.75},
		{"pos": Vector2(-48, 46), "size": Vector2(40, 12), "rot": 0.04, "floors": 5, "ruin": 0.6},
		{"pos": Vector2(52, 42), "size": Vector2(56, 12), "rot": -0.06, "floors": 9, "ruin": 0.7},
		{"pos": Vector2(165, 30), "size": Vector2(16, 44), "rot": 0.0, "floors": 3, "ruin": 0.4},        # the low annex of the big block
		# THE ENEMY LINE
		{"pos": Vector2(-70, -30), "size": Vector2(14, 14), "rot": 0.12, "floors": 10, "ruin": 0.7},     # towers
		{"pos": Vector2(-15, -45), "size": Vector2(14, 14), "rot": -0.05, "floors": 10, "ruin": 0.6},
		{"pos": Vector2(40, -28), "size": Vector2(14, 14), "rot": 0.08, "floors": 10, "ruin": 0.65},
		{"pos": Vector2(130, -25), "size": Vector2(72, 14), "rot": 0.0, "floors": 9, "ruin": 0.55},      # the big dark block
		{"pos": Vector2(-160, -48), "size": Vector2(12, 56), "rot": 0.0, "floors": 9, "ruin": 0.6},      # the long block on the left
		# the rear (empty) and the school complex (reserve)
		{"pos": Vector2(-95, -120), "size": Vector2(56, 12), "rot": 0.08, "floors": 9, "ruin": 0.55},
		{"pos": Vector2(105, -118), "size": Vector2(50, 12), "rot": -0.04, "floors": 9, "ruin": 0.5},
		{"pos": Vector2(10, -168), "size": Vector2(48, 16), "rot": 0.0, "floors": 3, "ruin": 0.4},       # school
		{"pos": Vector2(-28, -150), "size": Vector2(14, 28), "rot": 0.0, "floors": 3, "ruin": 0.45},     # its wings
		{"pos": Vector2(48, -150), "size": Vector2(14, 28), "rot": 0.0, "floors": 3, "ruin": 0.5},
	]
	# the private sector: the city edge, the flanks and behind the school
	houses = []
	fences = []
	var plots: Array = []
	for x in range(-206, 210, 20):
		plots.append(Vector2(x, 86))
	for x in range(-200, 204, 22):
		plots.append(Vector2(x, -212))
	for z in [-10.0, -60.0, -100.0, -140.0, -180.0]:
		plots.append(Vector2(-204, z))
		plots.append(Vector2(204, z + 6))
	for p in plots:
		if absf(p.x) < 26 and p.y > 0:
			continue   # where the belt comes out
		if absf(p.x) < 9:
			continue   # the street
		var hp: Vector2 = p + Vector2(rng.randf_range(-3, 3), rng.randf_range(-2, 2))
		houses.append({"pos": hp, "size": Vector2(rng.randf_range(6.5, 9.0), rng.randf_range(5.5, 7.0)), "rot": rng.randf_range(-0.2, 0.2),
			"ruin": rng.randf_range(0.5, 0.95)})
		if rng.randf() < 0.5:
			fences.append(PackedVector2Array([hp + Vector2(-9, -7), hp + Vector2(-9, 8), hp + Vector2(8, 8)]))
	sheds = [
		{"pos": Vector2(-108, 10), "size": Vector2(16, 6), "rot": 0.0},     # garages
		{"pos": Vector2(95, 8), "size": Vector2(16, 6), "rot": 0.0},
		{"pos": Vector2(-40, -92), "size": Vector2(14, 6), "rot": 0.0},
		{"pos": Vector2(150, -80), "size": Vector2(16, 6), "rot": 0.0},
	]
	roads = [
		{"pts": PackedVector2Array([Vector2(30, 279), Vector2(30, 252)]), "w": 5.0},                                   # entry
		{"pts": PackedVector2Array([Vector2(-250, 252), Vector2(0, 250), Vector2(250, 252)]), "w": 4.0},               # forest track along our line
		{"pts": PackedVector2Array([Vector2(-246, 252), Vector2(-248, 120), Vector2(-244, 0), Vector2(-246, -200)]), "w": 4.0},   # flank forest tracks
		{"pts": PackedVector2Array([Vector2(246, 252), Vector2(248, 120), Vector2(244, 0), Vector2(246, -200)]), "w": 4.0},
		{"pts": PackedVector2Array([Vector2(24, 250), Vector2(22, 150), Vector2(18, 96), Vector2(10, 72), Vector2(4, 0), Vector2(2, -100), Vector2(2, -236)]), "w": 5.0},  # field track along the belt and on through the city
		{"pts": PackedVector2Array([Vector2(-244, 72), Vector2(0, 72), Vector2(244, 72)]), "w": 6.0},    # city streets
		{"pts": PackedVector2Array([Vector2(-226, 10), Vector2(0, 8), Vector2(226, 10)]), "w": 6.0},
		{"pts": PackedVector2Array([Vector2(-226, -82), Vector2(0, -84), Vector2(226, -82)]), "w": 6.0},
		{"pts": PackedVector2Array([Vector2(-226, -196), Vector2(0, -196), Vector2(226, -196)]), "w": 5.0},
	]
	cars = [
		{"pos": Vector2(22, 180), "rot": 0.2}, {"pos": Vector2(-30, 72), "rot": 1.4}, {"pos": Vector2(60, 73), "rot": -1.7},
		{"pos": Vector2(-120, 72), "rot": 1.6}, {"pos": Vector2(140, 71), "rot": -1.4}, {"pos": Vector2(-70, 9), "rot": 0.1},
		{"pos": Vector2(80, 10), "rot": 3.0}, {"pos": Vector2(4, -20), "rot": 0.4}, {"pos": Vector2(-4, -70), "rot": 2.6},
		{"pos": Vector2(120, -83), "rot": 1.5}, {"pos": Vector2(-150, -84), "rot": 1.7}, {"pos": Vector2(30, -196), "rot": 1.5},
	]
	# the checkpoint between the towers; barricades on the cross streets
	blocks = [
		{"pts": PackedVector2Array([Vector2(-26, -8), Vector2(-6, -8)]), "kind": "concrete"},
		{"pts": PackedVector2Array([Vector2(6, -8), Vector2(18, -8)]), "kind": "concrete"},
		{"pts": PackedVector2Array([Vector2(-200, 10), Vector2(-186, 10)]), "kind": "barricade"},
		{"pts": PackedVector2Array([Vector2(186, 10), Vector2(200, 10)]), "kind": "barricade"},
		{"pts": PackedVector2Array([Vector2(-6, -84), Vector2(10, -84)]), "kind": "barricade"},
	]
	sandbags = [{"pos": Vector2(-16, -12), "rot": 0.0, "len": 5.0}, {"pos": Vector2(12, -12), "rot": 0.0, "len": 4.0}]
	# enemy positions inside the belt
	var outpost := MapDef.meander(PackedVector2Array([Vector2(-2, 178), Vector2(0, 166)]), rng, 3.0, 0.4)
	var belt_line := MapDef.traversed(PackedVector2Array([Vector2(-12, 120), Vector2(0, 118), Vector2(12, 120)]), 4.0, 0.8)
	trenches = [outpost, belt_line]
	dugout_at_end(belt_line)
	# the fields near the city are closed: wire and anti-personnel mines left and right of the belt
	wire = [
		PackedVector2Array([Vector2(-200, 116), Vector2(-110, 118), Vector2(-20, 116)]),
		PackedVector2Array([Vector2(20, 116), Vector2(110, 118), Vector2(200, 116)]),
	]
	minefields = [
		{"pts": PackedVector2Array([Vector2(-190, 108), Vector2(-100, 110), Vector2(-20, 108)]), "w": 8.0, "density": 0.03, "type": "ap"},
		{"pts": PackedVector2Array([Vector2(20, 108), Vector2(100, 110), Vector2(190, 108)]), "w": 8.0, "density": 0.03, "type": "ap"},
		{"pts": PackedVector2Array([Vector2(20, 100), Vector2(17, 88)]), "w": 8.0, "density": 0.05, "type": "at"},     # the track at the city edge
	]
	poles = [Vector2(28, 230), Vector2(27, 190), Vector2(25, 150), Vector2(22, 110), Vector2(-8, -30), Vector2(8, -100), Vector2(8, -150)]
	burnt = [Vector3(-70, -30, 9), Vector3(40, -28, 8), Vector3(-130, 40, 8), Vector3(130, -25, 9), Vector3(52, 42, 7), Vector3(0, 118, 5)]
	smoke_columns = [Vector2(-70, -30), Vector2(130, -25), Vector2(-130, 40)]
	ew_stations = [Vector2(4, -215)]
	ew_decoys = [Vector2(-120, -200)]
	ew_backups = [Vector2(110, -200)]
	bushes = []
	for i in 70:
		var p := Vector2(rng.randf_range(-215, 215), rng.randf_range(-225, 205))
		if absf(p.x) < 18 and p.y > 90:
			continue
		bushes.append(Vector3(p.x, p.y, rng.randf_range(0.9, 1.6)))
	for i in 30:   # undergrowth inside the belt
		bushes.append(Vector3(rng.randf_range(-11, 11), rng.randf_range(100, 210), rng.randf_range(1.0, 1.8)))
	craters = [Vector3(-60, 160, 2.6), Vector3(70, 150, 2.4), Vector3(-110, 125, 2.4), Vector3(90, 128, 2.6), Vector3(-6, -24, 2.2),
		Vector3(30, -60, 2.4), Vector3(-40, 20, 2.4), Vector3(100, 30, 2.2)]
	for i in 80:
		var c := Vector3(rng.randf_range(-215, 215), rng.randf_range(-220, 205), rng.randf_range(0.8, 2.0))
		if absf(c.x) < 6:
			continue
		craters.append(c)

	player_entry = Vector3(30, 0, 276)
	foot_spawn = Vector3(36, 0, 272)
	# the layout of the dismount points around the chosen deployment point
	dismount_points = [Vector3(0, 0, 250), Vector3(-22, 0, 251), Vector3(22, 0, 251), Vector3(-44, 0, 251), Vector3(44, 0, 251)]
	deploy_options = [
		{"name": "Посадка", "pos": Vector2(0, 250.6), "axis": Vector2(1, 0), "desc": "по центру, вздовж посадки — найкоротший шлях, але через секрет і траншею"},
		{"name": "Лівий фланг", "pos": Vector2(-246, 140), "axis": Vector2(0, 1), "desc": "лісом уздовж лівого флангу — до крайньої дев'ятиповерхівки зліва"},
		{"name": "Правий фланг", "pos": Vector2(246, 140), "axis": Vector2(0, 1), "desc": "лісом уздовж правого флангу — до прибудови, під вогнем великого будинку"},
	]
	deploy_zone = Rect2(-250, 200, 500, 60)
	medevac_entry = Vector3(26, 0, 276)
	rally_point = Vector3(10, 0, 262)
	enemy_retreat = Vector3(2, 0, -270)
	objective_rect = Rect2(-90, -60, 150, 62)
	capture_rect = Rect2(-92, -62, 154, 66)
	camera_start = Vector3(0, 0, 225)
	mortar_zone = Rect2(-226, 96, 452, 70)
	photo_center = Vector3(0, 0, 0)
	photo_size = 560.0
	photo_height = 320.0
	objective = {"type": "capture"}
	secondary = [{"type": "pows", "n": 1}, {"type": "no_vloss"}]

	# men placed inside a block take its windows, the upper floors first (Buildings.garrison)
	enemy_teams = [
		{"name": "Секрет у посадці", "roles": ["rifleman", "rifleman"],
			"slots": [Vector2(-1, 175), Vector2(0, 168)], "alt": [],
			"fallback": [Vector2(-4, 120), Vector2(4, 119)]},
		{"name": "Траншея в посадці", "roles": ["mg", "rifleman", "rifleman"],
			"slots": [Vector2(-6, 119), Vector2(0, 118), Vector2(6, 119)], "alt": [Vector2(-10, 120), Vector2(10, 120)],
			"fallback": [Vector2(-16, -12), Vector2(12, -12)]},
		{"name": "Вежа-Захід", "roles": ["mg", "rifleman", "at"],
			"slots": [Vector2(-73, -27), Vector2(-67, -27), Vector2(-70, -33)], "alt": [],
			"fallback": [Vector2(-160, -48), Vector2(-95, -120)]},
		{"name": "Вежа-Центр", "roles": ["rifleman", "mg", "grenadier"],
			"slots": [Vector2(-18, -42), Vector2(-12, -42), Vector2(-15, -48)], "alt": [],
			"fallback": [Vector2(10, -168), Vector2(4, -168)]},
		{"name": "Вежа-Схід", "roles": ["rifleman", "rifleman", "at"],
			"slots": [Vector2(37, -25), Vector2(43, -25), Vector2(40, -31)], "alt": [],
			"fallback": [Vector2(130, -25), Vector2(105, -118)]},
		{"name": "Блокпост", "roles": ["rifleman", "rifleman"],
			"slots": [Vector2(-16, -13), Vector2(12, -13)], "alt": [Vector2(-10, -13)],
			"fallback": [Vector2(-15, -45), Vector2(40, -28)]},
		{"name": "Великий будинок", "roles": ["mg", "atgm", "rifleman", "rifleman"],
			"slots": [Vector2(105, -22), Vector2(120, -22), Vector2(138, -22), Vector2(155, -22)], "alt": [],
			"fallback": [Vector2(105, -118), Vector2(110, -118)]},
		{"name": "Лівий довгий будинок", "roles": ["mg", "rifleman"],
			"slots": [Vector2(-158, -30), Vector2(-158, -55)], "alt": [],
			"fallback": [Vector2(-95, -120), Vector2(-100, -120)]},
		{"name": "Резерв", "roles": ["rifleman", "rifleman", "mg"], "reserve": true,
			"slots": [Vector2(0, -168), Vector2(10, -168), Vector2(20, -168)], "alt": [],
			"fallback": [Vector2(2, -240), Vector2(8, -240)]},
	]
	intel = {
		"age": "знімок зроблено 3 год тому",
		"estimate": "23–28 осіб",
		"lines": [
			"Від нашого лісу до міста — поля; по центру посадка. Поля біля міста під дротом і замінованими смугами, пристріляні мінометами.",
			"У посадці — секрет противника (2 особи) і траншея з кулеметом біля самого міста, поруч бліндаж.",
			"Передній ряд дев'ятиповерхівок і приватний сектор на околиці — противника не виявлено. Їх можна зайняти й вести бій з вікон.",
			"Рубіж противника — за 80–90 м: три вежі з блокпостом між ними (ЦІЛЬ), великий темний будинок праворуч (ймовірно ПТРК), довгий будинок ліворуч.",
			"Школа з двома крилами на півночі — ймовірний резерв. Дев'ятиповерхівки за вежами, ймовірно, порожні.",
			"Уздовж флангів і за містом — ліс із лісовими дорогами: довший, але прихований шлях. Район висадки обирається на знімку.",
			"Під'їзди — з південного боку будинків. «Тримати» з ПКМ по будинку — зайняти вікна, «Штурм» — зачистити.",
		],
		"markers": [
			{"pos": Vector2(0, 172), "label": "СЕКРЕТ?", "r": 10.0},
			{"pos": Vector2(0, 119), "label": "ТРАНШЕЯ, КУЛЕМЕТ", "r": 13.0},
			{"pos": Vector2(-70, -30), "label": "ВЕЖА", "r": 11.0},
			{"pos": Vector2(-15, -45), "label": "ВЕЖА", "r": 11.0},
			{"pos": Vector2(40, -28), "label": "ВЕЖА", "r": 11.0},
			{"pos": Vector2(-2, -12), "label": "БЛОКПОСТ", "r": 12.0},
			{"pos": Vector2(130, -25), "label": "ВЕЛИКИЙ БУДИНОК", "r": 38.0},
			{"pos": Vector2(-160, -48), "label": "ДОВГИЙ БУДИНОК", "r": 28.0},
			{"pos": Vector2(10, -160), "label": "ШКОЛА — РЕЗЕРВ?", "r": 30.0},
		],
	}
