extends Node3D
## Entry point: creates the independent systems, registers them in W,
## builds the map and hands control to the UI / mission flow.


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preview-map="):
			_preview_map(a.substr(14))
			return
		if a == "--make-library":
			MapLibrary.make_all()
			get_tree().quit()
			return
	W.reset()
	get_tree().paused = false
	randomize()
	# tests: `--seed=N` makes the battle start the same way every time
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed(int(a.substr(7)))

	var fx := FxSystem.new()
	fx.name = "Fx"
	add_child(fx)
	W.fx = fx
	var sfx := Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	W.sfx = sfx

	var map := MapManager.new()
	map.name = "Map"
	add_child(map)
	W.map = map

	var combat := CombatSystem.new()
	combat.name = "Combat"
	add_child(combat)
	W.combat = combat
	var damage := DamageSystem.new()
	damage.name = "Damage"
	add_child(damage)
	W.damage = damage
	var evac := EvacuationSystem.new()
	evac.name = "Evac"
	add_child(evac)
	W.evac = evac
	var enemy := EnemyAI.new()
	enemy.name = "EnemyAI"
	add_child(enemy)
	W.enemy_ai = enemy
	var radio := RadioSystem.new()
	radio.name = "RadioSystem"
	add_child(radio)
	W.radio = radio
	var blog := BattleLog.new()
	blog.name = "BattleLog"
	add_child(blog)
	W.blog = blog
	var intel := IntelSystem.new()
	intel.name = "Intel"
	add_child(intel)
	W.intel = intel
	var mission := MissionManager.new()
	mission.name = "Mission"
	add_child(mission)
	W.mission = mission
	var cam := DroneCamera.new()
	cam.name = "DroneCamera"
	add_child(cam)
	W.cam = cam
	var cmd := CommandController.new()
	cmd.name = "Command"
	add_child(cmd)
	W.command = cmd
	var ui := UIManager.new()
	ui.name = "UI"
	add_child(ui)
	W.ui = ui

	var def := Game.make_map_def()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--convert-map="):
			MapConvert.convert(def, a.substr(14))
			get_tree().quit()
			return
		if a.begins_with("--verify-map="):
			var diffs := MapConvert.diff(def, Game.map_def(a.substr(13)))
			print("[VERIFY] %s vs %s: %s" % [def.id, a.substr(13), "OK — identical" if diffs.is_empty() else "%d differences" % diffs.size()])
			for d in diffs:
				print("[VERIFY]   ", d)
			get_tree().quit()
			return
	Game.roll_weather(def.id)
	var t_build := Time.get_ticks_msec()
	map.build(def)
	if Game.is_test_run():
		print("[MAP] %s built in %d ms" % [def.id, Time.get_ticks_msec() - t_build])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--export-map="):
			MapExport.run(map, a.substr(13))
			get_tree().quit()
			return
	var ew := EwSystem.new()
	ew.name = "EW"
	add_child(ew)
	W.ew = ew
	ew.setup(def)
	var mines := MineSystem.new()
	mines.name = "Mines"
	add_child(mines)
	W.mines = mines
	mines.setup(def)
	var field := Battlefield.new()
	field.name = "Battlefield"
	add_child(field)
	W.field = field
	field.setup(def)
	var pris := PrisonerSystem.new()
	pris.name = "Prisoners"
	add_child(pris)
	W.prisoners = pris
	mission.setup(def)
	cam.bounds = def.size * 0.5 - 4.0
	cam.set_cinematic(def.photo_center)
	ui.begin()
	fx.prewarm()


## Debug: the map scene as the Godot editor shows it (ground preview, object
## markers), saved as PNGs: `-- --preview-map=res://maps/x.tscn [--shots=dir]`.
func _preview_map(path: String) -> void:
	MapScene.preview_in_game = true
	var root: MapScene = (load(path) as PackedScene).instantiate()
	add_child(root)
	var t0 := Time.get_ticks_msec()
	root.rebuild_preview()
	print("[PREVIEW] ground built in %d ms" % (Time.get_ticks_msec() - t0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.27, 0.3)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var cam := Camera3D.new()
	add_child(cam)
	var dir := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			dir = a.substr(8)
	var views := [[Vector3(0, root.size * 0.75, root.size * 0.55), Vector3.ZERO, "overview"],
		[Vector3(0, 45, 10), Vector3(0, 0, -40), "close"]]
	for v in views:
		cam.look_at_from_position(v[0], v[1])
		for i in 8:
			await get_tree().process_frame
		var p: String = dir.path_join("preview_%s_%s.png" % [root.map_id, v[2]])
		get_viewport().get_texture().get_image().save_png(p)
		print("[PREVIEW] ", ProjectSettings.globalize_path(p))
	get_tree().quit()
