extends MapDef
## Mission "СІРА ЗОНА": a short reconnaissance mission. No assault: the drone
## has to find every enemy position in front of our line and bring the
## picture back. The enemy is dug in, camouflaged and covered by EW — the
## portable jammers keep the drone away from each team, a jammer station in
## the rear covers the depth, and radio-recon answers a drone that hangs in
## the jammed zone with mortar fire on our line. There is no spare drone:
## losing it fails the mission.


func setup() -> void:
	Environments.apply(self, "field")
	id = "recon"
	title = "СІРА ЗОНА"
	subtitle = "Розвідка переднього краю противника"
	terrain_type = "Поле / лісосмуги"
	task_text = "Розвідати дроном усі позиції противника перед нашим рубежем: пост, кулемет, окоп, мінометників, бліндаж і станцію РЕБ. Дрон один — не втратьте його в зоні РЕБ."
	terrain_desc = "Район 240×240 м. Наш рубіж — південна лісосмуга. Перед нею поле з гаєм і зруйнованою фермою, далі ворожий окоп під північною лісосмугою, у глибині — балка й бліндаж."
	size = 240.0
	seed = 5311
	relief = 0.7
	time_limit = 15.0 * 60.0

	treelines = [
		{"rect": Rect2(-120, 92, 240, 10), "density": 0.85, "dead": 0.15},   # our tree line
		{"rect": Rect2(-120, -66, 98, 12), "density": 0.95, "dead": 0.25},   # enemy tree line, west
		{"rect": Rect2(-8, -66, 128, 12), "density": 0.95, "dead": 0.25},    # enemy tree line, east (gap for the track)
		{"rect": Rect2(-120, -120, 240, 10), "density": 0.9, "dead": 0.2},   # far rear
		{"rect": Rect2(-74, -24, 20, 18), "density": 0.9, "dead": 0.3},      # grove in the field (the observation post)
		{"rect": Rect2(96, -54, 10, 120), "density": 0.75, "dead": 0.3},     # east cross belt
	]
	roads = [
		{"pts": PackedVector2Array([Vector2(-14, 122), Vector2(-12, 60), Vector2(-15, 0), Vector2(-15, -60), Vector2(-18, -122)]), "w": 3.4},
		{"pts": PackedVector2Array([Vector2(-15, 2), Vector2(20, 0), Vector2(44, -2), Vector2(70, 4)]), "w": 2.8},
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# the enemy trench under the north tree line, a dugout in the depth
	var main := MapDef.traversed(PackedVector2Array([Vector2(-56, -48), Vector2(-36, -50), Vector2(-20, -47.5), Vector2(-2, -49), Vector2(16, -47)]), 4.5, 1.1)
	var comm := MapDef.meander(PackedVector2Array([Vector2(-36, -50), Vector2(-40, -62), Vector2(-46, -76), Vector2(-52, -84)]), rng, 4.0, 0.7)
	trenches = [main, comm]
	dugout_at_end(comm)
	bunkers = [
		{"pos": Vector2(46, -6), "face": Vector2(-0.3, 1.0), "kind": "mg"},       # MG nest at the ruined farm
		{"pos": Vector2(-54, -87), "face": Vector2(0.2, 1.0), "kind": "dugout"},  # command dugout
	]
	sandbags = [
		{"pos": Vector2(-63, -8.5), "rot": 0.1, "len": 3.0},
		{"pos": Vector2(-28, -45.2), "rot": -0.1, "len": 3.0},
		{"pos": Vector2(4, -44.8), "rot": 0.15, "len": 3.0},
		{"pos": Vector2(58, -84), "rot": 0.4, "len": 3.0},
		{"pos": Vector2(66, -86), "rot": -0.3, "len": 3.0},
	]
	wire = [PackedVector2Array([Vector2(-52, -38), Vector2(-30, -39), Vector2(-8, -38), Vector2(12, -39.5)])]
	houses = [
		{"pos": Vector2(38, 2), "size": Vector2(9, 6.5), "rot": 0.12, "ruin": 0.7},
		{"pos": Vector2(56, 10), "size": Vector2(7, 5.5), "rot": -0.2, "ruin": 0.85},
	]
	sheds = [{"pos": Vector2(30, -10), "size": Vector2(8, 5), "rot": 0.05}]
	fences = [PackedVector2Array([Vector2(26, 12), Vector2(28, -16), Vector2(62, -18)])]
	bales = [Vector2(10, 40), Vector2(12.5, 41.5), Vector2(-40, 50)]
	wrecks = [{"pos": Vector2(-14, 24), "rot": 2.2, "model": "bmp1"}]
	burnt = [Vector3(-14, 24, 6), Vector3(38, 2, 7)]
	camo = [Vector3(-63, -13, 6.0), Vector3(46, -6, 5.0), Vector3(-20, -48, 14.0), Vector3(62, -84, 7.0), Vector3(-54, -87, 5.0), Vector3(4, -96, 5.0)]
	ew_stations = [Vector2(4, -96)]
	ew_decoys = [Vector2(80, -40)]
	ew_backups = []
	minefields = [
		{"pts": PackedVector2Array([Vector2(-52, -32), Vector2(-24, -33), Vector2(10, -31)]), "w": 6.0, "density": 0.05, "type": "ap"},
	]
	smoke_columns = [Vector2(-14, 24)]
	bushes = []
	for i in 46:
		var p := Vector2(rng.randf_range(-115, 115), rng.randf_range(-105, 88))
		if absf(p.x + 14) < 5:
			continue
		bushes.append(Vector3(p.x, p.y, rng.randf_range(1.2, 3.0)))
	# the rear gully is overgrown: the mortar crew hides there
	for x in range(44, 84, 5):
		bushes.append(Vector3(float(x), -80.0 + rng.randf_range(-4, 4), rng.randf_range(1.8, 3.2)))
	craters = [Vector3(-30, 40, 3.0), Vector3(4, 16, 2.6), Vector3(-44, -10, 2.8), Vector3(20, -24, 2.4)]
	var tries := 0
	while craters.size() < 70 and tries < 600:
		tries += 1
		var c := Vector3(rng.randf_range(-115, 115), rng.randf_range(-110, 88), rng.randf_range(0.9, 2.1))
		if absf(c.x + 14) < 4:
			continue
		if c.z > -56 and c.z < -40 and c.x > -60 and c.x < 20:
			continue   # keep the trench readable
		craters.append(c)

	player_entry = Vector3(-13, 0, 118)
	foot_spawn = Vector3(-6, 0, 112)
	dismount_points = [Vector3(-12, 0, 104)]
	medevac_entry = Vector3(-12, 0, 118)
	rally_point = Vector3(-10, 0, 106)
	enemy_retreat = Vector3(-18, 0, -116)
	objective_rect = Rect2(-60, -60, 80, 20)
	capture_rect = Rect2(-70, -66, 100, 32)
	camera_start = Vector3(-10, 0, 96)
	mortar_zone = Rect2(-80, 70, 160, 40)   # the enemy mortar knows our tree line
	photo_center = Vector3(-4, 0, -30)
	photo_size = 190.0
	photo_height = 130.0
	objective = {"type": "recon", "teams": true, "keep_drone": true}
	secondary = [{"type": "casualties", "n": 0}]
	fixed_loadout = {"rifle_squad": 1, "medevac": 1}
	diff_override = {"fpv": 0}   # the pressure is radio recon + mortar, not FPV
	reinforcements = [{"none": true}]
	enemy_no_retreat = true

	enemy_teams = [
		{"name": "Спостережний пост", "roles": ["rifleman", "rifleman"],
			"slots": [Vector2(-63, -11), Vector2(-61, -13)], "alt": [], "fallback": []},
		{"name": "Кулемет на фермі", "roles": ["mg", "rifleman"], "bunker": 0,
			"slots": [Vector2(46, -6.2), Vector2(45, -7)], "alt": [], "fallback": []},
		{"name": "Окоп", "roles": ["leader", "rifleman", "mg", "rifleman", "at"],
			"slots": [Vector2(-40, -49.5), Vector2(-28, -48), Vector2(-20, -47.5), Vector2(-8, -48.5), Vector2(4, -48)],
			"alt": [Vector2(-50, -48), Vector2(12, -47)], "fallback": []},
		{"name": "Мінометники", "roles": ["rifleman", "rifleman", "rifleman"],
			"slots": [Vector2(58, -86), Vector2(62, -84), Vector2(66, -87)], "alt": [], "fallback": []},
		{"name": "Бліндаж", "roles": ["leader", "rifleman"], "bunker": 1,
			"slots": [Vector2(-54, -87), Vector2(-53, -87.6)], "alt": [], "fallback": []},
	]
	intel = {
		"age": "знімок зроблено 14 год тому",
		"estimate": "12–16 осіб",
		"lines": [
			"Завдання — лише розвідка: знайти й підтвердити дроном усі позиції. Піхота лишається на нашому рубежі.",
			"Ймовірний спостережний пост у гаю посеред поля.",
			"На зруйнованій фермі на сході — ймовірне кулеметне гніздо.",
			"Окоп під північною лісосмугою, перед ним дріт і міни.",
			"У глибині — бліндаж, балка на сході (можливі мінометники).",
			"Станція РЕБ десь у глибині; кожна група має переносний РЕБ — дрон, що підлітає низько, втрачає зв'язок і може впасти.",
			"Запасного дрона немає. РЕР пеленгує дрон, що довго висить у зоні РЕБ, — противник відповідає мінометом по нашій лісосмузі.",
			"Підтверджує ціль лише чиста картинка: тримайтеся на відстані, набирайте висоту, використовуйте зум.",
		],
		"markers": [
			{"pos": Vector2(-62, -14), "label": "ПОСТ?", "r": 13.0},
			{"pos": Vector2(44, -2), "label": "ФЕРМА", "r": 14.0},
			{"pos": Vector2(-20, -48), "label": "ОКОП", "r": 18.0},
			{"pos": Vector2(60, -80), "label": "БАЛКА", "r": 16.0},
		],
	}


func extra_height(x: float, z: float) -> float:
	# a gentle rise to the enemy side, the rear gully in the east
	var h := clampf(-z * 0.01, -1.2, 1.2) + sin(x * 0.035) * 0.3
	if z < -70.0 and z > -96.0:
		var k := clampf(minf(z + 96.0, -70.0 - z) / 8.0, 0.0, 1.0)
		h -= 2.2 * k * exp(-pow((x - 62.0) / 16.0, 2.0))
	return h
