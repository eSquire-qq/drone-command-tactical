extends MapDef
## Open field — "ВИСОТА": an enemy strongpoint on a bare hill that overlooks
## ~120 m of open, shell-pocked field. Different from "Посадка":
##  * the enemy sits HIGHER and sees the whole field — approach by dead
##    ground (the eastern fold), smoke and suppression, not by tree cover;
##  * a forward outpost mid-field and a post at the pump station guard the
##    two covered approaches — the first fights happen far from the trenches;
##  * the only road climbs straight up the hill: AT mines and an ATGM on the
##    east shoulder punish vehicles that drive into the open;
##  * cover is scattered: craters, wrecks, a hay-bale row, an abandoned trench
##    of ours on the west, lone trees, a far tree line on the west edge.


func setup() -> void:
	Environments.apply(self, "field")
	id = "field"
	title = "ВИСОТА"
	subtitle = "Опорний пункт на голому пагорбі"
	terrain_type = "Відкрите поле"
	task_text = "Перетнути відкрите поле, подавити й знищити противника на висоті та захопити її вершину."
	terrain_desc = "Район 300×300 м. Голий пагорб висотою ~9 м з окопами по передньому схилу; перед ним ~120 м відкритого поля з вирвами. " + \
		"Схід: балка — неглибока прихована від висоти лощина до насосної станції. Захід: покинутий окоп, рядок тюків і далека посадка. " + \
		"Посеред поля — передова застава противника. Дорога веде просто на висоту."
	size = 300.0
	seed = 9031
	relief = 0.7
	time_limit = 30.0 * 60.0
	budget_bonus = 400   # a harder operation: more points for the force
	extra_max = {"rifle_squad": 1, "fpv": 1}

	treelines = [
		{"rect": Rect2(-150, 90, 300, 15), "density": 0.95, "dead": 0.12},    # our tree line (start), thick enough to hide the assembly area
		{"rect": Rect2(-150, -124, 300, 10), "density": 0.85, "dead": 0.25},  # enemy rear, behind the hill
		{"rect": Rect2(-145, -100, 9, 55), "density": 0.75, "dead": 0.35},    # far western tree line, broken
		{"rect": Rect2(-145, -30, 9, 58), "density": 0.75, "dead": 0.3},
		{"rect": Rect2(-145, 44, 9, 48), "density": 0.8, "dead": 0.2},
		{"rect": Rect2(-95, -102, 190, 9), "density": 0.9, "dead": 0.2},     # belt on the rear slope of the hill
		{"rect": Rect2(128, -100, 8, 66), "density": 0.8, "dead": 0.3},      # eastern windbreak, broken
		{"rect": Rect2(128, -16, 8, 100), "density": 0.8, "dead": 0.25},
		{"rect": Rect2(-92, 14, 11, 9), "density": 0.7, "dead": 0.35},       # grove west of the abandoned trench
		{"rect": Rect2(98, -40, 12, 10), "density": 0.7, "dead": 0.3},       # grove beyond the pump station
	]
	# lone trees and small clumps scattered over the field
	for c in [Vector2(-52, -6), Vector2(41, 16), Vector2(-22, 62), Vector2(62, 56), Vector2(-92, 8),
			Vector2(112, -32), Vector2(-102, -62), Vector2(88, -74), Vector2(-64, 70), Vector2(124, 40),
			Vector2(-118, 30), Vector2(-112, -20), Vector2(-80, -40), Vector2(70, -60), Vector2(104, 70),
			Vector2(-40, 80), Vector2(30, 76), Vector2(-120, 80), Vector2(116, -64), Vector2(60, 84)]:
		treelines.append({"rect": Rect2(c.x - 2.5, c.y - 2.5, 5, 5), "density": 0.55, "dead": 0.3})
	roads = [
		{"pts": PackedVector2Array([Vector2(-20, 152), Vector2(-21, 114), Vector2(-33, 106), Vector2(-27, 94), Vector2(-14, 50), Vector2(2, 10),
			Vector2(16, -14), Vector2(18, -60), Vector2(10, -100), Vector2(6, -152)]), "w": 4.5},
		{"pts": PackedVector2Array([Vector2(-152, 112), Vector2(-22, 111), Vector2(152, 113)]), "w": 3.4},
		{"pts": PackedVector2Array([Vector2(152, -10), Vector2(100, -12), Vector2(74, -14)]), "w": 3.0},
	]
	# A freshly dug strongpoint (drone footage reference): bare-clay spoil, a
	# sawtooth fire trench along the forward slope, a crest trench, star-shaped
	# branches to both flanks and to the rear, firing cells, log-roofed dugouts.
	var trng := RandomNumberGenerator.new()
	trng.seed = seed + 5
	var front := MapDef.traversed(PackedVector2Array([Vector2(-44, -36), Vector2(-34, -32.5), Vector2(-4, -33),
		Vector2(26, -31.5), Vector2(44, -38)]), 4.0, 1.4)
	var crest := MapDef.traversed(PackedVector2Array([Vector2(-28, -52), Vector2(-4, -52), Vector2(20, -52), Vector2(30, -54)]), 4.0, 1.2)
	var west_arm := MapDef.traversed(PackedVector2Array([Vector2(-28, -52), Vector2(-44, -58), Vector2(-58, -51)]), 3.8, 1.2)
	var east_arm := MapDef.traversed(PackedVector2Array([Vector2(30, -54), Vector2(46, -60), Vector2(58, -53)]), 3.8, 1.2)
	var outpost := MapDef.traversed(PackedVector2Array([Vector2(-5, 2), Vector2(13, 2)]), 3.5, 0.9)
	trenches = [
		front,
		crest,
		MapDef.traversed(PackedVector2Array([Vector2(-4, -33), Vector2(-4, -52)]), 3.5, 0.9),
		MapDef.traversed(PackedVector2Array([Vector2(26, -31.5), Vector2(24, -42), Vector2(20, -52)]), 3.5, 0.9),
		MapDef.traversed(PackedVector2Array([Vector2(-34, -32.5), Vector2(-30, -42), Vector2(-28, -52)]), 3.5, 0.9),
		PackedVector2Array([Vector2(-4, -52), Vector2(-1, -57)]),                          # to the dugout
		PackedVector2Array([Vector2(-44, -36), Vector2(-41, -39)]),                        # to west MG bunker
		PackedVector2Array([Vector2(44, -38), Vector2(41, -41)]),                          # to east MG bunker
		PackedVector2Array([Vector2(24, -42), Vector2(30, -44), Vector2(34, -45)]),        # ATGM pit, east shoulder
		PackedVector2Array([Vector2(-30, -42), Vector2(-24, -44), Vector2(-20, -45)]),     # ATGM pit, west shoulder
		west_arm,
		east_arm,
		outpost,
		MapDef.meander(PackedVector2Array([Vector2(-72, 30), Vector2(-60, 27), Vector2(-48, 30), Vector2(-36, 27)]), trng, 4.0, 0.7),  # abandoned trench (ours)
	]
	# rear arms of the star end in dugouts
	for anchors in [[Vector2(-4, -52), Vector2(-6, -70)], [Vector2(20, -52), Vector2(28, -67)], [Vector2(-28, -52), Vector2(-34, -66)],
			[Vector2(-58, -51), Vector2(-62, -58)], [Vector2(58, -53), Vector2(63, -59)]]:
		var arm := MapDef.traversed(PackedVector2Array(anchors), 3.6, 0.9)
		trenches.append(arm)
		dugout_at_end(arm)
	# anti-vehicle barrier: three rows of dragon teeth with one opening — at the
	# road, which is mined (vehicles are funnelled into the AT minefield)
	teeth = [
		{"pts": PackedVector2Array([Vector2(-74, -9), Vector2(-30, -8), Vector2(6, -9)]), "rows": 3},
		{"pts": PackedVector2Array([Vector2(26, -9), Vector2(58, -11)]), "rows": 3},
	]
	bunkers = [
		{"pos": Vector2(-40, -41), "face": Vector2(0.35, 1.0), "kind": "mg"},
		{"pos": Vector2(0, -60), "face": Vector2(0, 1), "kind": "dugout"},
		{"pos": Vector2(40, -43), "face": Vector2(-0.3, 1.0), "kind": "mg"},
	]
	sandbags = [
		{"pos": Vector2(4, -1.2), "rot": 0.0, "len": 4.0},
		{"pos": Vector2(-14, -30.0), "rot": -0.1, "len": 3.0},
		{"pos": Vector2(16, -32.8), "rot": 0.1, "len": 3.0},
		{"pos": Vector2(32, -43.6), "rot": -0.2, "len": 2.5},
		{"pos": Vector2(68, -9), "rot": 0.3, "len": 3.5},
		{"pos": Vector2(-60, 26), "rot": 0.0, "len": 3.0},
	]
	wire = [
		PackedVector2Array([Vector2(-50, -25), Vector2(-30, -24), Vector2(-10, -25)]),
		PackedVector2Array([Vector2(24, -25), Vector2(42, -24), Vector2(54, -27)]),
		PackedVector2Array([Vector2(-8, 8), Vector2(4, 7), Vector2(16, 8)]),
	]
	sheds = [{"pos": Vector2(73, -15), "size": Vector2(8, 6), "rot": 0.12}]   # pump station
	houses = [{"pos": Vector2(84, -22), "size": Vector2(5, 4), "rot": -0.2, "ruin": 0.85}]
	fences = [PackedVector2Array([Vector2(66, -20), Vector2(66, -8), Vector2(80, -6)])]
	for x in range(-44, -8, 3):
		bales.append(Vector2(float(x), 52.0 + sin(x * 0.4) * 0.8))
	for z in range(148, -150, -18):
		poles.append(Vector2(-6.0 + float(z) * 0.08, float(z)))
	wrecks = [
		{"pos": Vector2(-30, 32), "rot": 0.6, "model": "bmp1"},
		{"pos": Vector2(26, 42), "rot": -2.3, "model": "bmp2"},
		{"pos": Vector2(50, -4), "rot": 1.9, "model": "m113"},
		{"pos": Vector2(-10, -12), "rot": 2.9, "model": "bmp1"},
	]
	burnt = [Vector3(-30, 32, 6), Vector3(26, 42, 5), Vector3(50, -4, 5), Vector3(-10, -12, 6)]
	smoke_columns = [Vector2(-10, -12)]
	ew_stations = [Vector2(-14, -70), Vector2(20, -72)]
	ew_decoys = [Vector2(-50, -66)]
	ew_backups = [Vector2(0, -86), Vector2(40, -84)]
	minefields = [
		{"pts": PackedVector2Array([Vector2(-62, -20), Vector2(-30, -21), Vector2(6, -19)]), "w": 6.0, "density": 0.05, "type": "ap"},
		{"pts": PackedVector2Array([Vector2(26, -20), Vector2(60, -19)]), "w": 6.0, "density": 0.05, "type": "ap"},
		{"pts": PackedVector2Array([Vector2(8, -10), Vector2(18, -18), Vector2(20, -26)]), "w": 9.0, "density": 0.045, "type": "at"},   # road through the gap
		{"pts": PackedVector2Array([Vector2(-40, 4), Vector2(-16, 6)]), "w": 9.0, "density": 0.015, "type": "at"},
		{"pts": PackedVector2Array([Vector2(60, -26), Vector2(70, -30)]), "w": 5.0, "density": 0.05, "type": "ap"},   # balka exit
	]
	bushes = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# the eastern fold is overgrown with scrub — concealment, not only dead ground
	for i in 26:
		var k := float(i) / 25.0
		var p := _balka_point(k)
		bushes.append(Vector3(p.x + rng.randf_range(-4, 4), p.y + rng.randf_range(-3, 3), rng.randf_range(1.5, 3.0)))
		if i % 2 == 0 and k < 0.95:
			bushes.append(Vector3(p.x - 9.0 + rng.randf_range(-1.5, 1.5), p.y + rng.randf_range(-3, 3), rng.randf_range(1.2, 2.2)))   # scrub on the bank
	for i in 34:
		var p := Vector2(rng.randf_range(-140, 140), rng.randf_range(-100, 88))
		if (p.y > -70 and p.y < -15 and absf(p.x) < 60) or absf(p.x - _road_x(p.y)) < 5:
			continue
		bushes.append(Vector3(p.x, p.y, rng.randf_range(1.0, 2.2)))
	craters = [Vector3(-18, 14, 3.2), Vector3(14, 18, 3.0), Vector3(-2, 26, 3.4), Vector3(30, 4, 2.8),
		Vector3(-36, -8, 2.8), Vector3(36, -12, 2.6), Vector3(-6, -16, 2.4), Vector3(-48, 14, 3.0),
		Vector3(6, 44, 2.6), Vector3(-26, 48, 2.4), Vector3(48, 28, 2.8)]
	var tries := 0
	while craters.size() < 150 and tries < 1200:
		tries += 1
		var c := Vector3(rng.randf_range(-140, 140), rng.randf_range(-105, 88), rng.randf_range(0.9, 2.3))
		if absf(c.x - _road_x(c.z)) < 4:
			continue
		if c.z > -64 and c.z < -26 and absf(c.x) < 52:
			continue   # keep the trench system readable
		craters.append(c)

	player_entry = Vector3(-21, 0, 146)
	dismount_points = [Vector3(-40, 0, 113), Vector3(-10, 0, 113), Vector3(20, 0, 113), Vector3(-70, 0, 113), Vector3(92, 0, 113), Vector3(50, 0, 113)]
	foot_spawn = Vector3(-5, 0, 132)
	medevac_entry = Vector3(-21.5, 0, 146)
	rally_point = Vector3(-10, 0, 120)
	enemy_retreat = Vector3(8, 0, -142)
	objective_rect = Rect2(-42, -62, 84, 30)
	capture_rect = Rect2(-60, -76, 120, 50)
	camera_start = Vector3(-5, 0, 112)
	mortar_zone = Rect2(-75, -22, 150, 110)
	photo_size = 150.0
	photo_center = Vector3(4, 0, -26)
	photo_height = 125.0
	# camouflage nets and turf over every prepared position: still defenders are
	# hard to spot on the bare slope until they open fire
	for p in front:
		camo.append(Vector3(p.x, p.y, 3.0))
	for p in [Vector2(-40, -41), Vector2(40, -43), Vector2(0, -60), Vector2(32, -44.5), Vector2(-22, -44.5),
			Vector2(4, 1), Vector2(-2, 1.5), Vector2(10, 1.5), Vector2(69, -10.5)]:
		camo.append(Vector3(p.x, p.y, 3.5))
	for p in [Vector2(-28, -52), Vector2(-16, -55), Vector2(-4, -52), Vector2(8, -55), Vector2(20, -52), Vector2(30, -54)]:
		camo.append(Vector3(p.x, p.y, 3.0))
	objective = {"type": "capture"}
	secondary = [{"type": "no_vloss"}, {"type": "pows", "n": 1}]

	enemy_teams = [
		{"name": "Захід", "roles": ["rifleman", "mg", "rifleman"],
			"slots": [Vector2(-34, -32), Vector2(-29, -33.5), Vector2(-24, -35)],
			"alt": [Vector2(-39, -34), Vector2(-19, -33)],
			"fallback": [Vector2(-28, -52), Vector2(-22, -53.5), Vector2(-16, -55)]},
		{"name": "Центр", "roles": ["leader", "rifleman", "at", "rifleman"],
			"slots": [Vector2(-14, -31), Vector2(-9, -32.5), Vector2(-4, -34), Vector2(1, -32.5)],
			"alt": [Vector2(6, -31), Vector2(-19, -33)],
			"fallback": [Vector2(-10, -53.5), Vector2(-4, -52), Vector2(2, -53.5), Vector2(8, -55)]},
		{"name": "Схід", "roles": ["mg", "rifleman", "grenadier"],
			"slots": [Vector2(26, -31), Vector2(21, -32.5), Vector2(31, -33)],
			"alt": [Vector2(16, -34), Vector2(36, -35)],
			"fallback": [Vector2(14, -53.5), Vector2(20, -52), Vector2(25, -53)]},
		{"name": "ДЗОТ-Захід", "roles": ["mg", "rifleman"], "bunker": 0,
			"slots": [Vector2(-40, -40.7), Vector2(-41.2, -41.5)], "alt": [],
			"fallback": [Vector2(-28, -52), Vector2(-22, -53.5)]},
		{"name": "ДЗОТ-Схід", "roles": ["mg", "rifleman"], "bunker": 2,
			"slots": [Vector2(40, -42.7), Vector2(39, -43.5)], "alt": [],
			"fallback": [Vector2(20, -52), Vector2(25, -53)]},
		{"name": "Резерв", "roles": ["rifleman", "rifleman", "mg", "at"], "bunker": 1, "reserve": true,
			"slots": [Vector2(0, -60), Vector2(1, -60.6), Vector2(-1, -60.6), Vector2(0, -61.2)], "alt": [],
			"fallback": [Vector2(-4, -52), Vector2(8, -55), Vector2(-16, -55), Vector2(20, -52)]},
		{"name": "ПТРК", "roles": ["atgm", "rifleman"],
			"slots": [Vector2(32, -44.4), Vector2(34, -45)], "alt": [Vector2(24, -42)],
			"fallback": [Vector2(20, -52), Vector2(25, -53)]},
		{"name": "ПТРК-Захід", "roles": ["atgm", "rifleman"],
			"slots": [Vector2(-22, -44.4), Vector2(-20, -45)], "alt": [Vector2(-30, -42)],
			"fallback": [Vector2(-28, -52), Vector2(-16, -55)]},
		{"name": "Гребінь", "roles": ["leader", "rifleman", "mg", "rifleman"],
			"slots": [Vector2(-16, -55), Vector2(-4, -52), Vector2(8, -55), Vector2(20, -52)],
			"alt": [Vector2(-28, -52), Vector2(30, -54)],
			"fallback": [Vector2(-10, -68), Vector2(0, -70), Vector2(10, -68), Vector2(20, -70)]},
		{"name": "Застава", "roles": ["rifleman", "mg", "rifleman"],
			"slots": [Vector2(-2, 1.5), Vector2(4, 0), Vector2(10, 1.5)], "alt": [Vector2(-6, -16)],
			"fallback": [Vector2(-4, -34), Vector2(6, -31), Vector2(1, -32.5)]},
		{"name": "Насосна", "roles": ["rifleman", "at"],
			"slots": [Vector2(68, -10), Vector2(71, -11)], "alt": [Vector2(78, -18)],
			"fallback": [Vector2(36, -35), Vector2(44, -38)]},
	]
	intel = {
		"age": "знімок зроблено 4 год тому",
		"estimate": "25–30 осіб",
		"lines": [
			"Опорний пункт на висоті: окоп по передньому схилу, другий — по гребеню, ходи сполучення.",
			"Висота проглядає все поле — рух відкритим полем удень помітний здалеку.",
			"Посеред поля — передова застава (3–4 особи) у вирвах, прикрита дротом.",
			"Східна балка неглибока, але з висоти її майже не видно; на виході — насосна станція, ймовірний пост.",
			"Мінна смуга перед окопами; прохід у центрі, біля дороги, ймовірно заміновано протитанковими мінами.",
			"Кулеметні ДЗОТи на обох флангах висоти, бліндаж за гребенем (ймовірний резерв).",
			"Розрахунки ПТРК на обох плечах висоти контролюють дорогу й поле — техніку в полі буде уражено.",
			"Позиції замасковані: доки противник не стріляє, з поля його майже не видно — потрібна розвідка дроном.",
			"Працює РЕБ за гребенем; противник застосовує FPV-дрони і має заздалегідь пристріляне поле для міномета.",
		],
		"markers": [
			{"pos": Vector2(4, 1), "label": "ЗАСТАВА", "r": 9.0},
			{"pos": Vector2(-40, -41), "label": "ДЗОТ?", "r": 6.0},
			{"pos": Vector2(40, -43), "label": "ДЗОТ?", "r": 6.0},
			{"pos": Vector2(-8, -33), "label": "ОКОП 4–6 ОС.", "r": 14.0},
			{"pos": Vector2(33, -45), "label": "ПТРК?", "r": 6.0},
			{"pos": Vector2(71, -12), "label": "НАСОСНА — ПОСТ?", "r": 8.0},
			{"pos": Vector2(0, -59), "label": "БЛІНДАЖ?", "r": 6.0},
			{"pos": Vector2(2, -71), "label": "РЕБ?", "r": 10.0},
		],
	}


## Centre line of the eastern fold (balka), k = 0 at our side, 1 at the pump station.
func _balka_point(k: float) -> Vector2:
	var pts := [Vector2(94, 104), Vector2(90, 62), Vector2(82, 22), Vector2(74, -4)]
	var f := clampf(k, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return (pts[i] as Vector2).lerp(pts[i + 1], f - i)


func _road_x(z: float) -> float:
	if z > 50.0:
		return lerpf(-14.0, -22.0, (z - 50.0) / 50.0)
	if z > -14.0:
		return lerpf(16.0, -14.0, (z + 14.0) / 64.0)
	return 17.0


func extra_height(x: float, z: float) -> float:
	# the hill: ~7 m above the field, crest just behind the second trench
	var h := 9.5 * exp(-(pow(x / 60.0, 2.0) + pow((z + 54.0) / 42.0, 2.0)))
	# the field falls gently towards us
	h += clampf(-z * 0.006, -0.6, 0.6)
	# eastern fold: ~2.6 m deep, fading out at the pump station
	if x < 55.0 or x > 115.0 or z < -25.0 or z > 125.0:
		return h
	var best := INF
	var bk := 0.0
	for i in 24:
		var k := float(i) / 23.0
		var d := Vector2(x, z).distance_to(_balka_point(k))
		if d < best:
			best = d
			bk = k
	var fade := 1.0 - smoothstep(0.82, 1.0, bk)
	h -= 2.6 * fade * exp(-pow(best / 7.0, 2.0))
	# low western bank between the fold and the hill: this, not the depth
	# alone, makes the fold dead ground for observers on the hill
	# (the bank runs on to the pump station, so leaving the fold you meet the
	# post there first, not the whole front trench)
	if x < _balka_point(bk).x:
		h += 2.0 * (1.0 - smoothstep(0.93, 1.0, bk)) * exp(-pow((best - 9.0) / 3.4, 2.0))
	return h
