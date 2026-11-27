extends MapDef
## Training ground "ПОЛІГОН": a small, forgiving map for the step-by-step
## tutorial. One rifle squad, a weak enemy post in the field and a short
## trench to clear. No enemy mortar, FPV, ATGM or EW; no time pressure.


func setup() -> void:
	Environments.apply(self, "steppe")
	id = "training"
	title = "ПОЛІГОН"
	subtitle = "Навчання командира"
	terrain_type = "Навчальний полігон"
	task_text = "Навчитися керувати дроном і підрозділом: рух, розвідка, підтримка, штурм, евакуація пораненого, зачистка окопу."
	terrain_desc = "Невеликий полігон 220×220 м: посадка на півдні, поле з вирвами, руїни, пост противника в полі й короткий окоп біля північної посадки."
	size = 220.0
	seed = 777
	relief = 0.5
	time_limit = 60.0 * 60.0

	treelines = [
		{"rect": Rect2(-110, 88, 100, 9), "density": 0.85, "dead": 0.1},    # our tree line, gap for the track
		{"rect": Rect2(8, 88, 102, 9), "density": 0.85, "dead": 0.1},
		{"rect": Rect2(-110, -104, 220, 10), "density": 0.9, "dead": 0.2},  # north
		{"rect": Rect2(-108, -90, 8, 170), "density": 0.75, "dead": 0.25},  # west belt
		{"rect": Rect2(60, -20, 14, 12), "density": 0.7, "dead": 0.3},      # grove east
	]
	roads = [
		{"pts": PackedVector2Array([Vector2(0, 112), Vector2(-1, 70), Vector2(-6, 10), Vector2(-10, -60), Vector2(-12, -112)]), "w": 3.5},
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# enemy post in the field and a short trench at the north tree line
	var post := MapDef.traversed(PackedVector2Array([Vector2(4, -34), Vector2(22, -34)]), 4.0, 0.8)
	var trench := MapDef.traversed(PackedVector2Array([Vector2(-62, -66), Vector2(-42, -70), Vector2(-22, -66)]), 4.0, 1.0)
	var comm := MapDef.meander(PackedVector2Array([Vector2(-42, -70), Vector2(-43, -80)]), rng, 3.0, 0.4)
	trenches = [post, trench, comm]
	dugout_at_end(comm)
	sandbags = [{"pos": Vector2(13, -31.8), "rot": 0.0, "len": 4.0}]
	houses = [{"pos": Vector2(-18, 44), "size": Vector2(8, 6), "rot": 0.15, "ruin": 0.6}]
	sheds = [{"pos": Vector2(24, 30), "size": Vector2(6, 5), "rot": -0.1}]
	fences = [PackedVector2Array([Vector2(-26, 38), Vector2(-26, 52), Vector2(-10, 54)])]
	wrecks = [{"pos": Vector2(30, -4), "rot": 1.2, "model": "bmp1"}]
	burnt = [Vector3(30, -4, 5)]
	camo = [Vector3(13, -34, 6.0), Vector3(-42, -68, 12.0)]
	bushes = []
	for i in 26:
		var p := Vector2(rng.randf_range(-100, 100), rng.randf_range(-90, 80))
		if absf(p.x) < 6 or (p.y < -25 and p.y > -80 and p.x > -70 and p.x < 30):
			continue
		bushes.append(Vector3(p.x, p.y, rng.randf_range(1.2, 2.6)))
	craters = [Vector3(-8, 20, 2.8), Vector3(10, 8, 2.4), Vector3(-4, -6, 3.0), Vector3(16, -14, 2.6), Vector3(-30, -20, 2.4)]
	for i in 50:
		var c := Vector3(rng.randf_range(-100, 100), rng.randf_range(-95, 80), rng.randf_range(0.9, 2.0))
		if absf(c.x) < 5 or (c.z < -26 and c.z > -82 and c.x > -70 and c.x < 30):
			continue
		craters.append(c)

	player_entry = Vector3(0, 0, 108)
	foot_spawn = Vector3(0, 0, 104)
	dismount_points = [Vector3(0, 0, 76)]
	medevac_entry = Vector3(4, 0, 108)
	rally_point = Vector3(0, 0, 100)
	enemy_retreat = Vector3(-10, 0, -108)
	objective_rect = Rect2(-66, -76, 48, 14)
	capture_rect = Rect2(-70, -84, 100, 60)
	camera_start = Vector3(0, 0, 80)
	photo_center = Vector3(-10, 0, -6)
	photo_size = 170.0
	photo_height = 120.0
	objective = {"type": "training"}
	# a forgiving opponent: shoots poorly, notices late, breaks easily
	diff_override = {"enemy_acc": 0.3, "enemy_detect": 0.35, "enemy_morale": 0.55, "atgm_acc": 1.0,
		"mortar": 0, "fpv": 0, "thin": false, "bleed": 4.0, "budget": 0}
	fixed_loadout = {"rifle_squad": 1, "medevac": 1, "mortar": 2, "smoke": 2}
	enemy_no_retreat = true

	enemy_teams = [
		{"name": "Пост", "roles": ["rifleman", "rifleman"],
			"slots": [Vector2(10, -34), Vector2(17, -34)], "alt": [], "fallback": []},
		{"name": "Окоп", "roles": ["rifleman", "rifleman"],
			"slots": [Vector2(-50, -68), Vector2(-34, -68)], "alt": [], "fallback": []},
	]
	intel = {
		"age": "навчальні дані",
		"estimate": "4 особи",
		"lines": [
			"Пост противника посеред поля: 2 особи за мішками з піском.",
			"Короткий окоп біля північної посадки: 2 особи, бліндаж.",
			"Противник слабо підготовлений, мінометів, FPV і РЕБ немає.",
		],
		"markers": [
			{"pos": Vector2(13, -34), "label": "ПОСТ", "r": 8.0},
			{"pos": Vector2(-42, -68), "label": "ОКОП", "r": 12.0},
			{"pos": Vector2(-18, 44), "label": "РУЇНИ", "r": 6.0},
		],
	}
