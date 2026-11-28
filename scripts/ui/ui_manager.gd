class_name UIManager
extends CanvasLayer
## Owns all UI layers and switches screens according to the mission phase.

var overlay_layer: CanvasLayer
var overlay: ColorRect
var root: Control
var hud: HUD
var screen: Control
var photo: Texture2D
var photo_info = {}


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 5
	add_sibling.call_deferred(overlay_layer)
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm = ShaderMaterial.new()
	sm.shader = load("res://shaders/drone_overlay.gdshader")
	overlay.material = sm
	overlay_layer.add_child(overlay)
	root = Control.new()
	root.theme = UIK.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	Events.phase_changed.connect(_on_phase)
	Events.mission_ended.connect(_on_end)


func begin() -> void:
	var def: MapDef = W.mission.def
	await _capture_photo(def)
	W.cam.set_cinematic(def.photo_center)
	Game.apply_settings()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--balance="):
			Game.mode = "quick"
			for a2 in args:
				if a2.begins_with("--difficulty="):
					Game.settings["difficulty"] = a2.substr(13)
			Game.loadout = {"recon_drone": 1, "rifle_squad": 2, "assault_group": 1, "bmp2": 1, "m113": 1, "medevac": 1, "mortar": 2, "fpv": 3, "smoke": 2}
			if not def.fixed_loadout.is_empty():
				Game.loadout = def.fixed_loadout.duplicate()   # the mission sets the force
			var cine := "--cinematic" in args
			if cine:
				# video: a few seconds of the briefing first, no tutorial cards
				Game.settings["hints"] = false
				show_briefing()
				await get_tree().create_timer(7.0).timeout
			if "--soak" in args:
				get_parent().add_child(SoakMonitor.new())
			_start_mission()
			var bb := BalanceBot.new()
			bb.plan = a.substr(10)
			get_parent().add_child(bb)
			if cine:
				get_parent().add_child(Cinematic.new())
			return
	for a in args:
		if a.begins_with("--aitest="):
			# controlled AI scenario: normal enemy, no scripted training
			def.diff_override = {}
			if a == "--aitest=hold" or a == "--aitest=destroy":
				# the map's own task (capture and hold) with a full company
				Game.loadout = {"bmp2": 1, "m113": 1, "rifle_squad": 2, "assault_group": 1, "medevac": 1, "mortar": 2, "fpv": 3, "smoke": 2}
			else:
				def.objective = {"type": "recon"}
				Game.loadout = {"bmp2": 1, "rifle_squad": 1}
			_start_mission()
			var t := AITests.new()
			t.scenario = a.substr(9)
			get_parent().add_child(t)
			return
	if "--autotest" in args:
		if not def.fixed_loadout.is_empty():
			Game.loadout = def.fixed_loadout.duplicate()
		if "--solo-bmp" in args:
			Game.loadout = {"rifle_squad": 1, "bmp2": 1, "medevac": 1}
		if "--campaign" in args:
			if not ("--campaign-cont" in args and Game.campaign.load_saved()):
				Game.campaign.start_new()
			Game.mode = "campaign"
			Game.loadout = Game.campaign_loadout()
			print("[AUTOTEST] campaign loadout ", Game.loadout, " supply ", Game.campaign.supply)
		if "--soak" in args:
			get_parent().add_child(SoakMonitor.new())
		_start_mission()
		var at := AutoTest.new()
		get_parent().add_child(at)
		return
	for a in args:
		if a.begins_with("--shots="):
			show_menu()
			var at := AutoTest.new()
			at.shot_dir = a.substr(8)
			get_parent().add_child(at)
			return
	match Game.start_screen:
		"campaign":
			show_menu()
			(screen as MainMenu)._show_campaign()
		"planning":
			show_planning()
		"briefing":
			show_briefing()
		_:
			show_menu()
	Game.start_screen = "menu"


func _capture_photo(def: MapDef) -> void:
	var sz = Vector2i(1020, 680)
	if DisplayServer.get_name() == "headless":
		photo = ImageTexture.create_from_image(Image.create(16, 16, false, Image.FORMAT_RGB8))
		photo_info = {"center": def.photo_center, "size": def.photo_size, "aspect": float(sz.x) / sz.y}
		return
	var sv = SubViewport.new()
	sv.size = sz
	sv.world_3d = get_viewport().find_world_3d()
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.msaa_3d = Viewport.MSAA_4X
	var c = Camera3D.new()
	c.projection = Camera3D.PROJECTION_ORTHOGONAL
	c.size = def.photo_size
	c.far = 600.0
	sv.add_child(c)
	add_child(sv)
	var center = def.photo_center
	c.global_position = Vector3(center.x, 200.0, center.z)
	c.look_at(Vector3(center.x, 0, center.z), Vector3(0, 0, -1))
	c.current = true
	W.photo_mode = true
	for i in 4:
		await RenderingServer.frame_post_draw
	var img = sv.get_texture().get_image()
	W.photo_mode = false
	photo = ImageTexture.create_from_image(img)
	photo_info = {"center": center, "size": c.size, "aspect": float(sz.x) / sz.y}
	sv.queue_free()


func _clear_screen() -> void:
	if screen and is_instance_valid(screen):
		screen.queue_free()
	screen = null


func show_menu() -> void:
	_clear_screen()
	var m := MainMenu.new()
	root.add_child(m)
	m.setup(_menu_start, _campaign_start, _training_start)
	screen = m
	W.mission.set_phase(MissionManager.Phase.BRIEFING)


## The language changed in the menu settings: rebuild the menu, back on the
## settings tab.
func relang_menu() -> void:
	show_menu()
	if screen is MainMenu:
		screen._show_settings()


func _menu_start() -> void:
	Game.mode = "quick"
	if Game.current_map != W.mission.def.id:
		_reload("briefing")
		return
	show_briefing()


## Start the next campaign mission (reloads if its map differs).
func _campaign_start() -> void:
	Game.mode = "campaign"
	var st: Dictionary = Game.campaign.current_step()
	if st.is_empty() or not Game.mission_available(st["mission"]):
		return
	Game.campaign.replenish()
	if Game.current_map != st["mission"] or W.mission.def.id != st["mission"]:
		Game.current_map = st["mission"]
		_reload("briefing")
		return
	show_briefing()


## Main menu → training ground (reloads the scene when another map is loaded).
func _training_start() -> void:
	Game.mode = "quick"
	if W.mission.def.id != "training":
		Game.current_map = "training"
		_reload("briefing")
		return
	show_briefing()


## A map with a fixed force (the training ground) skips the planning screen.
func _start_fixed() -> void:
	var keep: Dictionary = Game.loadout
	Game.loadout = W.mission.def.fixed_loadout.duplicate()
	_start_mission()
	Game.loadout = keep


func show_briefing() -> void:
	_clear_screen()
	var def: MapDef = W.mission.def
	if Game.mode == "campaign" and Game.campaign.active:
		Game.campaign.prepare_mission(def)
	elif def.has_meta("intel0"):
		def.intel = (def.get_meta("intel0") as Dictionary).duplicate(true)
	if not def.fixed_loadout.is_empty():
		screen = Screens.briefing(photo, photo_info, def, _start_fixed, _back_from_briefing,
			Loc.t("ПОЧАТИ НАВЧАННЯ  ▸") if def.objective.get("type", "") == "training" else Loc.t("РОЗПОЧАТИ МІСІЮ  ▸"))
	else:
		screen = Screens.briefing(photo, photo_info, def, show_planning, _back_from_briefing)
	root.add_child(screen)
	W.mission.set_phase(MissionManager.Phase.BRIEFING)


func show_planning() -> void:
	_clear_screen()
	var p = Screens.Planning.new()
	root.add_child(p)
	p.setup(photo, photo_info, W.mission.def, _start_mission, show_briefing)
	screen = p
	W.mission.set_phase(MissionManager.Phase.PLANNING)


func _start_mission() -> void:
	_clear_screen()
	hud = HUD.new()
	root.add_child(hud)
	hud.build()
	W.mission.start_mission()


func _on_phase(_p: int) -> void:
	pass


func _on_end(r: Dictionary) -> void:
	get_tree().paused = false
	if hud:
		hud.visible = false
	screen = Screens.results(r, _retry, _replan, _to_menu)
	root.add_child(screen)


## Back from the briefing: the battle has not started, the loaded map is still
## valid, so the menu is simply shown over it — no scene reload.
func _back_from_briefing() -> void:
	show_menu()
	if Game.mode == "campaign":
		(screen as MainMenu)._show_campaign()


func _to_menu() -> void:
	_reload("campaign" if Game.mode == "campaign" else "menu")


func _retry() -> void:
	_reload("briefing")


func _replan() -> void:
	_reload("planning")


## After a battle the map must be rebuilt: show a loading card first so the
## rebuild doesn't look like a freeze.
func _reload(next_screen: String) -> void:
	Game.start_screen = next_screen
	var card := ColorRect.new()
	card.color = Color(0.02, 0.03, 0.025, 0.96)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(card)
	var l := UIK.label(Loc.t("ЗАВАНТАЖЕННЯ МІСЦЕВОСТІ…"), 26, UIK.ACCENT)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.add_child(l)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().reload_current_scene()
