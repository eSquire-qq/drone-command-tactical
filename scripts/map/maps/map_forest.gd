extends MapDef
## Forest — «ЛІСОВИЙ МАСИВ», 420×420 m pine forest on the flank of the
## offensive. Sight under the trees is 20–35 m; the vehicles move only along
## the forest roads and the two firebreaks.
##  * south: our forest road (start); the deployment point is picked on the
##    briefing photo — the centre or either firebreak;
##  * the enemy forward screen: a listening post in the forest, a trench line
##    under the trees across the centre, an MG trench across the east
##    firebreak (closed by an abatis further south), a bunker at the junction
##    of the west firebreak and the forest road (AT mines on the firebreak);
##  * the felling in the west — an open patch plotted by the enemy mortars;
##  * the objective: the forester's clearing in the north — the forester's
##    house (held from its windows), sheds, a trench at the clearing's edge,
##    dugouts; the reserve in dugouts further north.


func setup() -> void:
	Environments.apply(self, "forest")
	id = "forest"
	title = "ЛІСОВИЙ МАСИВ"
	subtitle = "Бій у сосновому лісі"
	terrain_type = "Сосновий ліс, просіки, поляна"
	task_text = "Рейд у лісовий масив: знищити склад боєприпасів противника на поляні з лісництвом і його станцію РЕБ у глибині. Захоплювати поляну не обов'язково."
	terrain_desc = "Район 420×420 м, суцільний сосновий ліс: огляд під деревами 20–35 м, дрон бачить крізь крони погано. " + \
		"Техніка — лише лісовими дорогами й двома просіками (захід і схід). На заході — вирубка: відкрите місце, ймовірно пристріляне. " + \
		"На півночі — поляна з лісництвом, сараями й бліндажами."
	size = 420.0
	seed = 6631
	relief = 0.7
	time_limit = 40.0 * 60.0
	budget_bonus = 350   # a harder operation: more points for the force
	extra_max = {"rifle_squad": 1, "assault_group": 1}

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# the forest: everything but the clearing (x -45..45, z -95..-30) and the
	# felling (x -165..-105, z 40..95); firebreaks and roads cut through it
	var pine := {"density": 0.36, "dead": 0.08, "kind": "pine", "vis": 0.2}
	var young := {"density": 0.45, "dead": 0.06, "kind": "mixed", "vis": 0.28}   # denser mixed growth near our road
	for r in [Rect2(-210, -210, 420, 115), Rect2(-210, -95, 165, 65), Rect2(45, -95, 165, 65), Rect2(-210, -30, 420, 70),
			Rect2(-210, 40, 45, 55), Rect2(-105, 40, 315, 55), Rect2(-210, 95, 420, 75)]:
		var t := pine.duplicate()
		t["rect"] = r
		treelines.append(t)
	var y := young.duplicate()
	y["rect"] = Rect2(-210, 170, 420, 40)
	treelines.append(y)
	# a few lone pines left on the felling and dead trees on its edge
	for i in 7:
		var c := Vector2(rng.randf_range(-160, -110), rng.randf_range(46, 90))
		treelines.append({"rect": Rect2(c.x - 2, c.y - 2, 4, 4), "density": 0.9, "dead": 0.6, "kind": "pine"})
	roads = [
		{"pts": PackedVector2Array([Vector2(0, 209), Vector2(0, 196)]), "w": 5.0},                                   # entry
		{"pts": PackedVector2Array([Vector2(-200, 196), Vector2(-100, 197), Vector2(0, 196), Vector2(100, 197), Vector2(200, 196)]), "w": 4.5},  # our forest road
		{"pts": PackedVector2Array([Vector2(-100, 197), Vector2(-100, 100), Vector2(-101, 0), Vector2(-100, -205)]), "w": 7.0},   # west firebreak
		{"pts": PackedVector2Array([Vector2(100, 197), Vector2(100, 100), Vector2(99, 0), Vector2(100, -205)]), "w": 7.0},       # east firebreak
		{"pts": PackedVector2Array([Vector2(-205, 2), Vector2(-100, 0), Vector2(0, 2), Vector2(100, 0), Vector2(205, 2)]), "w": 4.5},  # forest road E-W
		{"pts": PackedVector2Array([Vector2(0, 2), Vector2(2, -40), Vector2(0, -62), Vector2(-2, -110), Vector2(0, -205)]), "w": 4.0},  # to the forester's
		{"pts": PackedVector2Array([Vector2(0, 196), Vector2(-4, 150), Vector2(4, 100), Vector2(0, 60)]), "w": 3.0},     # a footpath north from our road
	]
	# the forester's clearing
	houses = [{"pos": Vector2(0, -64), "size": Vector2(12, 8), "rot": 0.0, "ruin": 0.25}]
	sheds = [
		{"pos": Vector2(-24, -52), "size": Vector2(8, 5), "rot": 0.1},
		{"pos": Vector2(22, -78), "size": Vector2(10, 6), "rot": -0.05},
		{"pos": Vector2(26, -50), "size": Vector2(6, 5), "rot": 0.2},
	]
	fences = [PackedVector2Array([Vector2(-14, -48), Vector2(-14, -76), Vector2(14, -76), Vector2(14, -48)])]
	bales = [Vector2(-32, -70), Vector2(-30, -73), Vector2(34, -64)]   # stacked firewood
	poles = [Vector2(4, -40), Vector2(3, -20), Vector2(2, 20)]
	cars = [{"pos": Vector2(8, -58), "rot": 0.6}]
	wrecks = [{"pos": Vector2(100, 120), "rot": 0.1, "model": "bmp1"}]   # burnt on the east firebreak
	# the enemy positions under the trees
	var post := MapDef.meander(PackedVector2Array([Vector2(-7, 92), Vector2(7, 90)]), rng, 3.0, 0.4)
	var line := MapDef.traversed(PackedVector2Array([Vector2(-62, 25), Vector2(-20, 21), Vector2(20, 21), Vector2(62, 25)]), 4.5, 1.0)
	var mg_line := MapDef.traversed(PackedVector2Array([Vector2(86, 45), Vector2(114, 43)]), 4.0, 0.8)
	var edge := MapDef.traversed(PackedVector2Array([Vector2(-34, -33), Vector2(0, -31), Vector2(34, -33)]), 4.0, 0.8)
	trenches = [post, line, mg_line, edge]
	dugout_at_end(line)
	dugout_at_end(mg_line)
	dugouts.append({"pos": Vector2(-30, -88), "rot": 0.0, "size": Vector2(4.0, 3.2)})
	dugouts.append({"pos": Vector2(0, -132), "rot": 0.0, "size": Vector2(4.0, 3.2)})
	dugouts.append({"pos": Vector2(14, -134), "rot": 0.0, "size": Vector2(3.6, 3.0)})
	bunkers = [
		{"pos": Vector2(-92, 10), "face": Vector2(-0.6, 0.8), "kind": "mg"},   # the junction of the west firebreak and the forest road
		{"pos": Vector2(24, -90), "face": Vector2(0, -1), "kind": "depot"},    # the raid target: ammunition behind the forester's sheds
	]
	sandbags = [{"pos": Vector2(-108, 6), "rot": 0.0, "len": 4.0}]
	camo = []
	for p in [Vector2(0, 91), Vector2(-40, 23), Vector2(0, 21), Vector2(40, 23), Vector2(100, 44), Vector2(-92, 10)]:
		camo.append(Vector3(p.x, p.y, 4.0))
	blocks = [{"pts": PackedVector2Array([Vector2(94, 72), Vector2(106, 72)]), "kind": "barricade"}]   # abatis across the east firebreak
	wire = [PackedVector2Array([Vector2(-58, 32), Vector2(-20, 29), Vector2(20, 29), Vector2(58, 32)])]
	minefields = [
		{"pts": PackedVector2Array([Vector2(-100, 70), Vector2(-100, 44)]), "w": 7.0, "density": 0.05, "type": "at"},   # the west firebreak
		{"pts": PackedVector2Array([Vector2(-50, 38), Vector2(0, 36), Vector2(50, 38)]), "w": 6.0, "density": 0.02, "type": "ap"},
	]
	craters = [Vector3(-130, 70, 2.6), Vector3(-120, 55, 2.2), Vector3(-150, 80, 2.4), Vector3(0, -45, 2.0), Vector3(-100, 30, 2.2)]
	for i in 40:
		craters.append(Vector3(rng.randf_range(-190, 190), rng.randf_range(-190, 160), rng.randf_range(0.8, 1.8)))
	bushes = []
	for i in 40:
		bushes.append(Vector3(rng.randf_range(-170, -100), rng.randf_range(42, 94), rng.randf_range(0.8, 1.4)))   # brush on the felling
	burnt = [Vector3(100, 120, 6), Vector3(-130, 70, 8)]
	ew_stations = [Vector2(30, -165)]
	ew_decoys = [Vector2(-60, -150)]
	ew_backups = []   # the raid target: one station, no replacement

	player_entry = Vector3(0, 0, 207)
	foot_spawn = Vector3(6, 0, 204)
	dismount_points = [Vector3(0, 0, 196), Vector3(-20, 0, 196), Vector3(20, 0, 196), Vector3(-40, 0, 196), Vector3(40, 0, 196)]
	deploy_options = [
		{"name": "Центр", "pos": Vector2(0, 196), "axis": Vector2(1, 0), "desc": "стежкою на північ — прямо на секрет і траншею під деревами"},
		{"name": "Західна просіка", "pos": Vector2(-100, 150), "axis": Vector2(0, 1), "desc": "просікою до вирубки й ДЗОТа на перехресті; на просіці ПТ-міни"},
		{"name": "Східна просіка", "pos": Vector2(100, 150), "axis": Vector2(0, 1), "desc": "просікою повз згорілу БМП; далі засіка й кулемет у траншеї"},
	]
	deploy_zone = Rect2(-200, 186, 400, 18)
	medevac_entry = Vector3(-4, 0, 207)
	rally_point = Vector3(10, 0, 200)
	enemy_retreat = Vector3(0, 0, -205)
	objective_rect = Rect2(-45, -95, 90, 66)
	capture_rect = Rect2(-48, -98, 96, 72)
	camera_start = Vector3(0, 0, 180)
	mortar_zone = Rect2(-168, 38, 66, 60)   # the felling
	photo_center = Vector3(0, 0, 0)
	photo_size = 420.0
	photo_height = 260.0
	objective = {"type": "destroy", "bunkers": [1], "ew": true}
	secondary = [{"type": "no_vloss"}, {"type": "evac_all"}]

	enemy_teams = [
		{"name": "Секрет", "roles": ["rifleman", "rifleman"],
			"slots": [Vector2(-4, 91), Vector2(4, 90)], "alt": [],
			"fallback": [Vector2(-10, 22), Vector2(10, 22)]},
		{"name": "Траншея-Захід", "roles": ["mg", "rifleman", "rifleman"],
			"slots": [Vector2(-48, 23), Vector2(-34, 22), Vector2(-20, 21)], "alt": [Vector2(-56, 24)],
			"fallback": [Vector2(-20, -32), Vector2(-28, -33)]},
		{"name": "Траншея-Схід", "roles": ["rifleman", "grenadier", "at"],
			"slots": [Vector2(20, 21), Vector2(34, 22), Vector2(48, 23)], "alt": [Vector2(56, 24)],
			"fallback": [Vector2(20, -32), Vector2(28, -33)]},
		{"name": "Кулемет на просіці", "roles": ["mg", "rifleman"],
			"slots": [Vector2(96, 44), Vector2(106, 43)], "alt": [],
			"fallback": [Vector2(60, 24), Vector2(52, 23)]},
		{"name": "ДЗОТ на перехресті", "roles": ["mg", "at", "rifleman"], "bunker": 0,
			"slots": [Vector2(-92, 10), Vector2(-93, 9), Vector2(-108, 7)], "alt": [],
			"fallback": [Vector2(-48, 23), Vector2(-34, -33)]},
		{"name": "Лісництво", "roles": ["mg", "atgm", "rifleman"],
			"slots": [Vector2(-3, -62), Vector2(3, -62), Vector2(0, -66)], "alt": [],
			"fallback": [Vector2(0, -132), Vector2(14, -134)]},
		{"name": "Окоп на поляні", "roles": ["rifleman", "rifleman"],
			"slots": [Vector2(-14, -32), Vector2(14, -32)], "alt": [Vector2(-28, -33), Vector2(28, -33)],
			"fallback": [Vector2(0, -64), Vector2(-24, -52)]},
		{"name": "Сараї", "roles": ["mg", "rifleman", "grenadier"],
			"slots": [Vector2(-24, -49), Vector2(22, -74), Vector2(26, -47)], "alt": [Vector2(-28, -70)],
			"fallback": [Vector2(0, -64), Vector2(-30, -88)]},
		{"name": "Бліндаж на поляні", "roles": ["rifleman", "at"],
			"slots": [Vector2(-30, -86), Vector2(-27, -86)], "alt": [],
			"fallback": [Vector2(0, -132), Vector2(14, -134)]},
		{"name": "Резерв", "roles": ["rifleman", "rifleman", "mg"], "reserve": true,
			"slots": [Vector2(0, -132), Vector2(14, -134), Vector2(6, -136)], "alt": [],
			"fallback": [Vector2(0, -200), Vector2(6, -200)]},
	]
	intel = {
		"age": "знімок зроблено 5 год тому",
		"estimate": "24–28 осіб",
		"lines": [
			"Суцільний сосновий ліс: під деревами огляд 20–35 м, з дрона позиції під кронами видно погано. Техніка — лише дорогами й просіками.",
			"Перед траншеєю, ймовірно, секрет (2 особи) біля стежки.",
			"Траншея під деревами поперек масиву, перед нею дріт і протипіхотні міни, на кінці бліндаж.",
			"Західна просіка: ПТ-міни, на перехресті з лісовою дорогою — ДЗОТ із кулеметом. Поруч вирубка — відкрита й, імовірно, пристріляна.",
			"Східна просіка закрита засікою; за нею кулеметна траншея поперек просіки.",
			"Поляна з лісництвом: будинок (вогонь із вікон, можливо ПТРК), сараї з кулеметом, окоп на краю поляни, бліндаж. Резерв у бліндажах на півночі.",
			"Ціль рейду — склад боєприпасів за сараями лісництва (ящики під сіткою) і станція РЕБ на півночі. Склад горить від ПТРК, FPV, РПГ чи близьких мін; після вибуху там небезпечно. РЕБ — лише прямим влучанням (FPV, ПТРК).",
			"Район висадки обирається на знімку: центр або одна з просік.",
		],
		"markers": [
			{"pos": Vector2(0, 91), "label": "СЕКРЕТ?", "r": 10.0},
			{"pos": Vector2(0, 23), "label": "ТРАНШЕЯ", "r": 40.0},
			{"pos": Vector2(100, 44), "label": "КУЛЕМЕТ", "r": 14.0},
			{"pos": Vector2(-92, 10), "label": "ДЗОТ", "r": 12.0},
			{"pos": Vector2(24, -90), "label": "СКЛАД БК?", "r": 12.0},
			{"pos": Vector2(0, -62), "label": "ЛІСНИЦТВО", "r": 30.0},
			{"pos": Vector2(6, -134), "label": "РЕЗЕРВ?", "r": 16.0},
			{"pos": Vector2(30, -165), "label": "РЕБ?", "r": 12.0},
		],
	}
