class_name AutoTest
extends Node
## Debug harness.
##  `-- --autotest`         plays the mission automatically (headless OK).
##  `-- --shots=<dir>`      windowed run: briefing, planning, then combat,
##                          saving screenshots to <dir> for visual review.

var t := 0.0
var log_t := 0.0
var ordered := false
var evac_t := 0.0
var supports_done := false
var shot_dir := ""
var shot_plan: Array = []
var stage := 0
var pause_done := false
var pause_w := 0.0
var pause_real := -1.0
var stuck_t := 5.0
var stuck_pos := {}
var stuck_hits := {}
var zoom_tested := false
var zoom_reported := false
var zoom_p0 := Vector3.ZERO
var zoom_l0 := 0.0
var ew_tested := false
var ew_reported := false
var spare_checked := false
var clear_ordered := false
var clear_checked := false
var cqb_seen := {}
var pow_test := false
var pow_reported := false
var pow_unit = null
var solo_tested := false
var solo_check: Array = []
var done_hint_shot := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[AUTOTEST] started ", shot_dir)
	Events.message.connect(func(txt, kind): print("[MSG %s] %s" % [kind, txt]))
	Events.mission_ended.connect(_on_end)
	if shot_dir == "":
		Engine.time_scale = 4.0
	if "--profile" in OS.get_cmdline_user_args():
		Prof.on = true
		Engine.time_scale = 1.0


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var p := shot_dir.path_join(name + ".png")
	img.save_png(p)
	print("[SHOT] ", p)
	if not Loc.is_uk():
		_scan_cyrillic(get_tree().root, name)


## Not Ukrainian: report visible UI text that is still in Cyrillic.
var _cyr_seen := {}


func _scan_cyrillic(n: Node, shot: String) -> void:
	if n is CanvasItem and not n.is_visible_in_tree():
		return
	var txt := ""
	if n is RichTextLabel:
		txt = n.get_parsed_text()
	elif n is Label or n is Button:
		txt = n.text
	if txt != "":
		for line in txt.split("
"):
			var cyr := false
			for ch in line:
				if ch.unicode_at(0) >= 0x400 and ch.unicode_at(0) <= 0x4FF:
					cyr = true
					break
			if cyr and not _cyr_seen.has(line):
				_cyr_seen[line] = true
				print("[CYR] %s: %s" % [shot, line.strip_edges()])
	for c in n.get_children():
		_scan_cyrillic(c, shot)


func _process(delta: float) -> void:
	if Prof.on:
		var real_dt := delta / maxf(Engine.time_scale, 0.01)
		if real_dt > 0.04 and W.time > 2.0:
			print("[SPIKE] t=%.1f frame=%.0f ms" % [W.time, real_dt * 1000.0])
	t += delta
	if Prof.on and "--ui-cost" in OS.get_cmdline_user_args():
		_ui_cost()
	if shot_dir != "" and "--quickview" in OS.get_cmdline_user_args():
		_quickview()
		return
	if shot_dir != "":
		_shots_flow()
	if not W.running():
		return
	if not camp7_done and Game.mode == "campaign" and W.mission.phase == MissionManager.Phase.COMBAT:
		camp7_done = true
		_camp7_start()
	if W.mission.def.id == "training":
		_training_bot()
		return
	if "--deploy-check" in OS.get_cmdline_user_args():
		_deploy_check()
		return
	log_t -= delta
	if log_t <= 0.0:
		log_t = 10.0
		_report()
	# `--shot-at=<s>`: one picture of the battle at that time (windowed runs)
	for sa in OS.get_cmdline_user_args():
		if sa.begins_with("--shot-at=") and not shot_taken and W.time > float(sa.substr(10)) and DisplayServer.get_name() != "headless":
			shot_taken = true
			var pc: Vector3 = W.mission.def.photo_center
			W.cam.teleport_view(pc, W.mission.def.size * 0.55, 32.0, 0.25)
			(func() -> void:
				await get_tree().create_timer(1.2, true, false, true).timeout
				var pth := ProjectSettings.globalize_path("user://autoshot.png")
				get_viewport().get_texture().get_image().save_png(pth)
				print("[SHOT] ", pth)).call()
	# other maps: after the first rush, push each squad at the nearest enemy
	# (an enemy in a house means clearing that house)
	if ordered and W.mission.def.id != "treeline" and W.time > 240.0:
		mg_t -= delta
		if mg_t <= 0.0:
			mg_t = 25.0
			for sq in W.mission.friendly_squads:
				if sq.active_count() < 2 or sq.mounted or not (sq.order in ["hold", "move", "occupy"]):
					continue
				var bd := INF
				var bp = null
				for u in W.units:
					if u.side == 1 and u.is_active():
						var d: float = u.global_position.distance_to(sq.center())
						if d < bd:
							bd = d
							bp = u.global_position
				if bp != null:
					sq.issue_order("assault", bp)
	if W.mission.phase == MissionManager.Phase.COMBAT and not ordered:
		ordered = true
		var posts := 0
		for u in W.units:
			if u.side == 1 and u.post != null:
				posts += 1
		print("[AUTOTEST] enemies at windows: %d, buildings %d" % [posts, W.map.buildings.size()])
		if "--bld-debug" in OS.get_cmdline_user_args():
			for b in W.map.buildings:
				var occ := 0
				for w in b["windows"]:
					if w["occupant"] != null:
						occ += 1
				print("[BLD] %s at %s windows %d occupied %d inside_enemy %d" % [b["kind"], (b["center"] as Vector3).snapped(Vector3.ONE), b["windows"].size(), occ, Buildings.men_inside(b, 1).size()])
			for u in W.units:
				if u.side == 1 and Buildings.at(u.global_position) != null and u.post == null:
					print("[BLD] no post: %s %s y=%.1f" % [u.squad.team_name, u.global_position.snapped(Vector3.ONE * 0.1), u.global_position.y])
		var target := Vector3(-14, 0, -29)
		# own / template maps: storm the map's objective
		if W.mission.def.id != "treeline" and W.mission.def.objective_rect.size != Vector2.ZERO:
			var oc: Vector2 = W.mission.def.objective_rect.get_center()
			target = Vector3(oc.x + 10.0, 0, oc.y)
		if "--solo-bmp" in OS.get_cmdline_user_args():
			for v in W.mission.friendly_vehicles:
				v.order_move(Vector3(-10, 0, -12))
			print("[AUTOTEST] solo BMP push")
			return
		var i := 0
		for sq in W.mission.friendly_squads:
			sq.issue_order("assault", target + Vector3(i * 20 - 10, 0, 0))
			i += 1
		for v in W.mission.friendly_vehicles:
			v.order_move(Vector3(-5 + i * 10, 0, 20))
			i += 1
		print("[AUTOTEST] assault ordered")
	if ordered and not supports_done and W.time > 60.0:
		supports_done = true
		if W.mission.use_support("mortar"):
			W.combat.mortar_strike(Vector3(-15, 0, -29), 4, 7.0, 0)
		for b in W.bunkers:
			if not b.destroyed:
				b.ever_seen = true
				if W.mission.use_support("fpv"):
					W.combat.fpv_strike(b, Vector3(0, 25, 125))
				break
		if W.mission.use_support("smoke"):
			W.combat.smoke_barrage(Vector3(0, 0, -10))
	if ordered and not solo_tested and W.time > 30.0 and shot_dir == "":
		solo_tested = true
		var sq = W.mission.friendly_squads[W.mission.friendly_squads.size() - 1]
		var picks: Array = []
		for m in sq.members:
			if m.is_active() and picks.size() < 2:
				picks.append(m)
		W.command._set_selection(picks)
		W.command.mode = "hold"
		W.command._order_at(Vector3(20, 0, 30))
		solo_check = picks
		print("[AUTOTEST] solo order to ", picks.size(), " soldiers; squad order=", sq.order)
	if solo_check.size() > 0 and W.time > 45.0:
		for m in solo_check:
			print("[AUTOTEST] solo soldier solo=", m.solo, " dist_to_slot=", snappedf(m.global_position.distance_to(m.slot), 0.1), " squad_order=", m.squad.order)
		solo_check = []
	if not zoom_tested and W.time > 8.0 and shot_dir == "":
		zoom_tested = true
		zoom_p0 = W.cam.pos
		zoom_l0 = W.ew.link
		W.cam.zoom_t = 10.0
		print("[AUTOTEST] ZOOM probe start pos=", zoom_p0.snapped(Vector3.ONE), " link=", snappedf(zoom_l0, 0.01))
	if zoom_tested and not zoom_reported and W.time > 16.0:
		zoom_reported = true
		print("[AUTOTEST] ZOOM probe x%.1f: drone moved %.1f m, alt=%d, link %.2f -> %.2f, fov=%.1f" % [W.cam.zoom, W.cam.pos.distance_to(zoom_p0), int(W.cam.altitude()), zoom_l0, W.ew.link, W.cam.cam.fov])
		W.cam.zoom_t = 1.0
	if not ew_tested and W.time > 20.0 and shot_dir == "":
		ew_tested = true
		W.cam.cinematic = false
		W.cam.focus_t = Vector3(-10, 0, -36)
		W.cam.dist_t = 25.0
		print("[AUTOTEST] EW probe: trying to fly drone over the trench")
	if ew_tested and not ew_reported and W.time > 45.0:
		ew_reported = true
		var cp = W.cam.cam.global_position
		print("[AUTOTEST] EW probe: drone at z=%.0f alt=%.0f link=%.2f down=%s lost=%d" % [cp.z, cp.y, W.ew.link, W.ew.drone_down, W.ew.drones_lost])
		if W.ew.drone_down:
			W.ew.launch_spare()
			print("[AUTOTEST] spare launched, relaunch_t=", W.ew.relaunch_t)
	if ew_reported and not spare_checked and W.time > 125.0:
		spare_checked = true
		print("[AUTOTEST] after relaunch: down=%s input=%s spares=%d" % [W.ew.drone_down, W.cam.input_enabled, W.ew.spares])
	if not clear_ordered and W.time > 70.0 and W.mission.friendlies_in_zone() > 0:
		clear_ordered = true
		var sq = W.mission.friendly_squads[0]
		W.command.select_object(sq)
		W.command.mode = "clear"
		W.command._order_at(Vector3(-38, 0, -31))
		print("[AUTOTEST] CLEAR ordered for ", sq.short, " order=", sq.order)
	if clear_ordered and not clear_checked and W.time > 110.0:
		clear_checked = true
		var sq2 = W.mission.friendly_squads[0]
		var st := []
		for m in sq2.members:
			if m.is_active():
				st.append("%s:%s:tr=%s" % [m.rdata["short"], m.ai.state, m.in_trench()])
		print("[AUTOTEST] clear status order=", sq2.order, " ", st)
	for u in W.units:
		if u.side == 0 and u.is_active() and (u.ai.state == "граната за ріг" or u.ai.state == "прострілює кут" or u.ai.state == "граната наосліп"):
			cqb_seen[u.ai.state] = cqb_seen.get(u.ai.state, 0) + 1
		elif u.side == 1 and u.is_active() and (u.ai.state == "відхід по траншеї" or u.ai.state == "граната наосліп"):
			cqb_seen["E:" + u.ai.state] = cqb_seen.get("E:" + u.ai.state, 0) + 1
	if not pow_test and W.time > 180.0:
		pow_test = true
		var best = null
		var bn := 99
		for u in W.units:
			if u.side == 1 and u.is_active() and u.bunker == null:
				var n := 0
				for a in W.units:
					if a.side == 1 and a != u and a.is_active() and a.global_position.distance_to(u.global_position) < 10.0:
						n += 1
				if n < bn:
					bn = n
					best = u
		if best != null:
			best.morale = 5.0
			var k := 0
			for f in W.units:
				if f.side == 0 and f.is_active() and f.role != "crew_medic" and k < 3:
					f.global_position = W.grid.free_point(best.global_position + Vector3(4 + k, 0, 4))
					f.stop()
					k += 1
			pow_unit = best
			print("[AUTOTEST] POW test on enemy with allies near=", bn)
	if pow_unit != null and not pow_reported and W.time > 200.0:
		pow_reported = true
		print("[AUTOTEST] POW surrendered=", pow_unit.surrendered, " health=", pow_unit.health, " captured=", pow_unit.captured, " escort=", pow_unit.escort != null, " moving=", pow_unit.moving, " path=", pow_unit.path.size(), " d_rally=", int(pow_unit.global_position.distance_to(W.mission.def.rally_point)), " pos=", pow_unit.global_position.snapped(Vector3.ONE))
	# playtest: pause must freeze the battle clock
	if not pause_done and W.time > 50.0 and shot_dir == "":
		pause_done = true
		pause_w = W.time
		get_tree().paused = true
		pause_real = 0.0
	if get_tree().paused and pause_real >= 0.0:
		pause_real += delta
		if pause_real > 1.0:
			get_tree().paused = false
			print("[PLAYTEST] pause: battle clock moved %.2f s while paused (expect 0)" % (W.time - pause_w))
			pause_real = -1.0
	# playtest: stuck soldiers (moving order but no progress)
	stuck_t -= delta
	if stuck_t <= 0.0:
		stuck_t = 5.0
		for u in W.units:
			if u.side != 0 or not u.is_active() or not u.moving:
				stuck_pos.erase(u)
				continue
			var prev = stuck_pos.get(u, null)
			if prev != null and (prev as Vector3).distance_to(u.global_position) < 0.3 and u.cqb_wait <= 0.0 and u.action == "":
				stuck_hits[u.uname] = stuck_hits.get(u.uname, 0) + 1
				var fa = u.follow_ahead
				var fs := ""
				if fa != null and is_instance_valid(fa):
					fs = " ahead=%s d=%.1f mv=%s cqbw=%.1f act=%s ai=%s pi=%d/%d prog_t=%.1f" % [fa.uname, u.global_position.distance_to(fa.global_position), fa.moving,
						fa.cqb_wait, fa.action, fa.ai.state, fa.path_i, fa.path.size(), fa._prog_t]
				var wp_s := ""
				if u.path_i < u.path.size():
					var wp: Vector3 = u.path[u.path_i]
					wp_s = " wp_d=%.2f wp_tr=%.2f me_tr=%.2f spd=%.2f cur=%.2f noclamp=%.1f can_adv=%s" % [Vector2(wp.x - u.global_position.x, wp.z - u.global_position.z).length(),
						W.grid.trench_d(wp.x, wp.z), W.grid.trench_d(u.global_position.x, u.global_position.z), u._speed(), u.cur_speed, u._noclamp_t, u.can_advance]
				print("[STUCK] t=%d %s %s pos=%s order=%s ai=%s follow=%s trench=%s path=%d/%d%s%s" % [int(W.time), u.squad.short, u.uname,
					u.global_position.snapped(Vector3.ONE * 0.1), u.squad.order, u.ai.state, u.follow_ahead != null, u.in_trench(), u.path_i, u.path.size(), fs, wp_s])
			stuck_pos[u] = u.global_position
	evac_t -= delta
	if evac_t <= 0.0:
		evac_t = 5.0
		for u in W.units:
			if W.evac.is_valid_patient(u) and u.health == Soldier.H.INCAP:
				W.evac.request(u)
	if "--campaign" in OS.get_cmdline_user_args() and W.time > 240.0 and W.mission.phase != MissionManager.Phase.ENDED:
		W.mission.end_mission("abort")
	if W.time > 900.0 and W.mission.phase != MissionManager.Phase.ENDED:
		W.mission.end_mission("timeout")


var qv_views := [[Vector3(-14, 0, -29), 16.0, 38.0, 0.5], [Vector3(-48, 0, -28), 26.0, 50.0, -0.6], [Vector3(-5, 0, -40), 30.0, 70.0, 0.2], [Vector3(0, 0, 0), 330.0, 60.0, 0.0]]


func _quickview() -> void:
	var i := int(t / 2.0) - 1
	if i < 0:
		return
	if i >= qv_views.size():
		get_tree().quit()
		return
	if W.mission.def.id == "field" and qv_views[0][0] != Vector3(0, 0, -35):
		qv_views = [[Vector3(0, 0, -35), 170.0, 22.0, 0.0], [Vector3(82, 0, 20), 80.0, 40.0, 0.7],
			[Vector3(4, 0, -34), 40.0, 45.0, 0.2], [Vector3(0, 0, 0), 330.0, 60.0, 0.0]]
	var v: Array = qv_views[i]
	W.photo_mode = true
	if not qv_done.has(i) and fmod(t, 2.0) < 0.3:
		W.cam.teleport_view(v[0], v[1], v[2], v[3])
	if fmod(t, 2.0) > 1.6 and not qv_done.has(i):
		qv_done[i] = true
		_shot("qv_%d" % i)


var qv_done := {}


func _shots_flow() -> void:
	if stage >= 2 and stage < 8 and W.mission.phase == MissionManager.Phase.ENDED:
		stage = 8
	match stage:
		0:
			if t > 3.0:
				_shot("00_menu")
				W.ui.screen._show_missions()
				stage = 11
		11:
			if t > 4.0:
				_shot("00b_missions")
				W.ui.screen._show_campaign()
				stage = 12
		12:
			if t > 5.0:
				_shot("00c_campaign")
				W.ui.screen._show_training()
				await get_tree().process_frame
				await get_tree().process_frame
				_shot("00d_training")
				W.ui.show_briefing()
				stage = 10
		10:
			if t > 6.5:
				_shot("01_briefing")
				var t_ms := Time.get_ticks_msec()
				W.ui._back_from_briefing()
				print("[SHOTS] briefing -> menu: %d ms" % (Time.get_ticks_msec() - t_ms))
				stage = 13
		13:
			if t > 7.5:
				_shot("01b_back_menu")
				W.ui.show_briefing()
				W.ui.show_planning()
				stage = 1
		1:
			if t > 8.5:
				_shot("02_planning")
				if not W.mission.def.fixed_loadout.is_empty():
					W.ui._start_fixed()
				else:
					W.ui._start_mission()
				Engine.time_scale = 2.0
				stage = 2
		2:
			if t > 12.0:
				_shot("03_deploy")
				stage = 3
		3:
			if W.time > 40.0:
				W.cam.focus_on(Vector3(-15, 0, -28), 60.0)
				stage = 4
		4:
			if W.time > 44.0:
				_shot("04_enemy_trench")
				var tut = W.ui.hud.get_node_or_null("Tutorial")
				if tut:
					tut._show("support")   # hint with highlighted HUD buttons for 05
				var sq = W.mission.friendly_squads[0]
				W.command.select_object(sq)
				W.cam.follow = sq
				W.cam.dist_t = 38.0
				stage = 5
		5:
			if W.time > 47.0 and not done_hint_shot:
				done_hint_shot = true
				var tut2 = W.ui.hud.get_node_or_null("Tutorial")
				print("[SHOTS] hint visible=", tut2.visible if tut2 else null, " targets=", tut2._hl_targets.size() if tut2 else -1)
				_shot("04b_hint")
			if W.time > 70.0:
				_shot("05_squad_close")
				W.cam.follow = null
				W.cam.focus_on(Vector3(-10, 0, -5), 120.0)
				stage = 6
		6:
			if W.time > 100.0:
				_shot("06_battle_wide")
				W.cam.dist_t = 30.0
				W.cam.pitch_t = deg_to_rad(30.0)
				W.cam.focus_t = Vector3(-20, 0, -30)
				stage = 7
		7:
			if W.time > 112.0:
				_shot("07_trench_low")
				W.ui.hud.radio_panel.toggle()
				stage = 8
				_radio_open_t = W.time
		8:
			if _radio_open_t > 0.0 and W.time > _radio_open_t + 1.0:
				_shot("07b_radio_log")
				W.ui.hud.radio_panel.toggle()
				_radio_open_t = -1.0
			if W.mission.phase == MissionManager.Phase.ENDED and t > 0:
				stage = 9
				t = 0.0
		9:
			if t > 1.0:
				_shot("08_results")
				if W.blog:
					for ev in W.blog.events:
						print("[AAR] %s %s %s" % [UIK.mmss(float(ev["t"])), ev["kind"], ev["text"]])
					for a in W.mission.result.get("analysis", []):
						print("[AAR-ANALYSIS] %s %s" % ["+" if a["good"] else "!", a["text"]])
				stage = 30
				t = 0.0
		30:
			# test 6: every review tab renders
			var tabs := ["ХРОНОЛОГІЯ", "КАРТА", "АНАЛІЗ", "РАДІО"]
			var k := int(t / 1.0)
			if k >= 1 and k <= 4 and _aar_tab != k:
				_aar_tab = k
				var b := _find_button(W.ui.screen, tabs[k - 1])
				if b:
					b.emit_signal("pressed")
					b.button_pressed = true
			elif k >= 1 and k <= 4 and fmod(t, 1.0) > 0.6 and _aar_shot != k:
				_aar_shot = k
				_shot("09_aar_%d" % k)
			elif k > 4:
				get_tree().quit()


var _radio_open_t := -1.0
var _aar_tab := 0
var _aar_shot := 0


func _find_button(n: Node, text: String) -> Button:
	if n is Button and n.text == text:
		return n
	for c in n.get_children():
		var b := _find_button(c, text)
		if b:
			return b
	return null


var prof_frames := 0
var _worst_frame := 0.0


func _physics_process(_d: float) -> void:
	pass


func _report() -> void:
	if Prof.on:
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		print("[RENDER] t=%.0f cpu_render=%.2f ms gpu=%.2f ms process=%.2f ms draws=%d prims=%dk objs=%d vram=%dMB mem=%dMB" % [
			W.time, RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576,
			OS.get_static_memory_usage() / 1048576])
		print("[VRAM] textures=%dMB buffers=%dMB" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576])
		var fr := Engine.get_process_frames() - prof_frames
		prof_frames = Engine.get_process_frames()
		print("[PROF] t=%.0f fps=%d units=%d %s" % [W.time, Engine.get_frames_per_second(), W.units.size(), Prof.report(maxi(fr, 1))])
	var f := [0, 0, 0, 0]
	var e := [0, 0, 0, 0]
	for u in W.units:
		if u.side == 0:
			f[u.health] += 1
		else:
			e[u.health] += 1
	print("[AUTOTEST] t=%.0f phase=%d F(h/w/i/d)=%s E=%s evac=%d alert=%d cap=%.1f fps=%d" % [
		W.time, W.mission.phase, f, e, W.evac.evacuated.size(), W.enemy_ai.alert, W.mission.capture, Engine.get_frames_per_second()])


# ------------------------------------------------------------------ test 7: campaign consequences
var camp7_done := false


## Rules on made-up results, then what this mission got from the last one.
func _camp7_start() -> void:
	var fast_win := {"success": true, "enemy_total": 30, "enemy_dead": 20, "enemy_wia": 4, "prisoners": 3, "enemy_escaped": 1,
		"time": 500.0, "time_limit": 1800.0, "recon": 0.8, "drones_lost": 0}
	var bad_loss := {"success": false, "enemy_total": 30, "enemy_dead": 5, "enemy_wia": 2, "prisoners": 0, "enemy_escaped": 8,
		"time": 1700.0, "time_limit": 1800.0, "recon": 0.25, "drones_lost": 2}
	for pair in [["швидка перемога", fast_win], ["невдалий штурм", bad_loss]]:
		var c: Dictionary = Campaign.consequences(pair[1])
		print("[CAMP7] RULE %s: розвіддані %.2f (%s), противник ×%.2f (%s)" % [pair[0], c["intel_q"], Campaign.intel_word(c["intel_q"]),
			c["enemy_k"], Campaign.enemy_word(c["enemy_k"])])
		print("[CAMP7]   intel: ", "; ".join(c["why_intel"]))
		print("[CAMP7]   enemy: ", "; ".join(c["why_enemy"]))
	# cohesion: a unit that lost its commander and a veteran
	var tc := Campaign.new()
	tc.units = [{"name": "Тест-відділення", "members": ["a", "b", "c"]}]
	tc.soldiers = {"a": {"name": "Коваль", "role": "leader", "xp": 6, "status": "kia"},
		"b": {"name": "Ткач", "role": "rifleman", "xp": 10, "status": "kia"}, "c": {"name": "Сич", "role": "rifleman", "xp": 1, "status": "ready"}}
	var rep := {}
	tc._cohesion({"success": false}, {"a": {"state": "kia", "role": "leader"}, "b": {"state": "kia"}, "c": {"state": "ok"}}, rep)
	var c_after: float = tc.units[0]["cohesion"]
	tc._cohesion({"success": true}, {}, {})
	print("[CAMP7] RULE cohesion: %s; next battle morale x%.2f discipline x%.2f; after a win %.2f" % [rep.get("cohesion", []),
		0.8 + 0.2 * c_after, 0.85 + 0.15 * c_after, float(tc.units[0]["cohesion"])])
	var c2 = Game.campaign
	var nx: Dictionary = c2.flags.get("next", {})
	var n0 := 0
	for t2 in W.mission.def.enemy_teams:
		n0 += (t2["roles"] as Array).size()
	var seen := 0
	for b in W.bunkers:
		if b.side == 1 and b.ever_seen:
			seen += 1
	print("[CAMP7] MISSION step=%d next=%s" % [c2.step, "немає (перший бій)" if nx.is_empty() else "q=%.2f k=%.2f" % [nx["intel_q"], nx["enemy_k"]]])
	print("[CAMP7]   enemy on map %d (planned %d, campaign change %+d), mortar rounds %d, FPV %d, bunkers known at start %d/%d" % [
		W.enemy_ai.start_count, n0, W.enemy_ai.campaign_delta, W.enemy_ai.mortar_rounds, W.enemy_ai.fpv_count, seen, W.bunkers.size()])
	var d0: Dictionary = W.mission.def.intel.duplicate(true)
	c2.prepare_mission(W.mission.def)
	var d1: Dictionary = W.mission.def.intel
	print("[CAMP7]   briefing: «%s» → «%s»; estimate «%s» → «%s»; markers %d → %d" % [d0.get("age", ""), d1.get("age", ""),
		d0.get("estimate", ""), d1.get("estimate", ""), (d0.get("markers", []) as Array).size(), (d1.get("markers", []) as Array).size()])
	var vl: Array = []
	for vt in ["bmp2", "bmp1", "m113", "medevac"]:
		vl.append("%s %d/%d" % [vt, c2.pool_ready(vt), int(c2.pool.get(vt, 0))])
	print("[CAMP7]   vehicles ready/pool: ", ", ".join(vl), "  loadout ", Game.loadout)
	for u in c2.units:
		print("[CAMP7]   %s cohesion %.2f" % [u["name"], float(u.get("cohesion", 1.0))])
	for u in W.units:
		if u.side == 0 and u.role == "leader" and u.squad:
			print("[CAMP7]   %s leader morale %.0f discipline %.2f" % [u.squad.short, u.max_morale, u.discipline])


func _on_end(r: Dictionary) -> void:
	print("[AUTOTEST] RESULT ", r)
	if r.has("campaign"):
		print("[CAMPMEM] report memory: ", r["campaign"].get("memory", []))
		var cr: Dictionary = r["campaign"]
		print("[CAMP7] END recon %.2f escaped %d pows %d time %d/%d → next %s" % [float(r.get("recon", 0)), int(r.get("enemy_escaped", 0)),
			int(r.get("prisoners", 0)), int(r["time"]), int(r.get("time_limit", 0)), cr.get("next", {})])
		print("[CAMP7] END in repair %s, repaired %s, cohesion %s" % [cr.get("in_repair", []), cr.get("repaired", []), cr.get("cohesion", [])])
		for u in W.units:
			if u.side == 0 and u.camp_id != "":
				print("[CAMPMEM] in-mission %s strain=%.0f base_stress=%.1f max_morale=%.0f grit=%.2f pinned_s=%.0f panicked=%s" % [
					u.uname, u.strain, u.base_stress, u.max_morale, u.grit, u.pinned_s, u.panicked])
		for cs in Game.campaign.soldiers.values():
			print("[CAMPMEM] saved %s %s strain=%.0f grit_bonus=%.2f memory=%s label=%s" % [cs["name"], cs["status"], float(cs.get("strain", 0.0)),
				float(cs.get("grit_bonus", 0.0)), cs.get("memory", []), Campaign.strain_label(float(cs.get("strain", 0.0)))])
		var mm := MainMenu.new()
		get_parent().add_child(mm)
		mm.setup(Callable(), Callable())
		mm._show_campaign()
		print("[PLAYTEST] campaign tab built ok, step=", Game.campaign.step, " supply=", Game.campaign.supply, " missing=", Game.campaign.missing_count())
		var added := Game.campaign.replenish()
		print("[PLAYTEST] replenish: recruits=", added, " supply=", Game.campaign.supply, " next loadout=", Game.campaign_loadout())
	var keys := ["kia", "wia", "evacuated", "vehicles_lost", "enemy_dead", "prisoners", "score", "grade"]
	var missing: Array = []
	for k in keys:
		if not r.has(k):
			missing.append(k)
	print("[PLAYTEST] report fields missing: ", missing, " | stuck samples (>=2 means stuck ≥10 s): ", stuck_hits)
	# windowed campaign run: pictures of the report and of the next briefing
	if r.has("campaign") and DisplayServer.get_name() != "headless" and shot_dir == "":
		for c in get_parent().get_children():
			if c is MainMenu:
				c.queue_free()
		Engine.time_scale = 1.0
		await get_tree().create_timer(1.5, true, false, true).timeout
		var dir := ProjectSettings.globalize_path("user://")
		get_viewport().get_texture().get_image().save_png(dir + "camp7_results.png")
		W.ui.show_briefing()
		await get_tree().create_timer(1.5, true, false, true).timeout
		get_viewport().get_texture().get_image().save_png(dir + "camp7_briefing.png")
		print("[SHOT] ", dir, "camp7_results.png / camp7_briefing.png")
	if shot_dir == "":
		get_tree().quit()


## Plays the training mission like a player would, one step at a time.
var tb_step := -1
var mg_t := 0.0
var shot_taken := false
var tb_t := 0.0


func _training_bot() -> void:
	var tr = W.ui.hud.training if W.ui.hud else null
	if tr == null:
		return
	if tr.idx != tb_step:
		tb_step = tr.idx
		tb_t = 0.0
	tb_t += get_process_delta_time()
	if tb_t < 1.0 or tr.done_t >= 0.0:
		return
	var sq = W.mission.friendly_squads[0]
	var post := Vector3(13, 0, -34)
	match tr.idx:
		0, 14:
			tr.info_ok = true
		1:
			W.cam.teleport_view(Vector3(0, 0, 40), 80.0, 45.0, 0.0)
		2:
			W.cam.teleport_view(Vector3(0, 0, 40), 80.0, 45.0, 1.0)
		3:
			W.cam.zoom_t = 4.0
		4:
			W.cam.zoom_t = 1.0
			if not sq.mounted and sq.active_count() > 0:
				W.command.select_object(sq)
		5:
			W.command.select_object(sq)
			W.command.mode = "move"
			W.command._order_at(W.grid.ground(Vector3(-14, 0, 52)))
		6:
			if tb_t < 1.5:
				get_tree().paused = true
			else:
				get_tree().paused = false
		7:
			Engine.time_scale = 3.0
		8:
			W.cam.teleport_view(Vector3(10, 0, -10), 60.0, 45.0, 0.0)
		9:
			for m in tr._team("Пост").members:
				if m.is_active():
					m.marked = true
					break
		10:
			if W.mission.use_support("mortar"):
				W.combat.mortar_strike(post, 4, 11.0, 0)
		11:
			if sq.order != "assault":
				sq.issue_order("assault", post)
			if tb_t > 240.0:
				tr._skip()
		12:
			if tr.wounded and is_instance_valid(tr.wounded) and not tr.wounded.evac_marked:
				W.evac.request(tr.wounded)
		13:
			if sq.order != "clear":
				sq.issue_order("clear", Vector3(-42, 0, -68))
			if tb_t > 300.0:
				tr._skip()


## `--deploy-check [--deploy=N]`: the column goes to the deployment point
## chosen on the briefing; prints where every vehicle / squad is, then quits.
var _dc_t := 0.0


func _deploy_check() -> void:
	_dc_t += get_process_delta_time()
	if _dc_t < 20.0 and W.time < 240.0:
		return
	_dc_t = 0.0
	var dep: Dictionary = Game.deploy_for(W.mission.def)
	var p: Vector2 = dep.get("pos", Vector2.ZERO)
	var line := "[DEPLOY] t=%.0f «%s» (%.0f, %.0f):" % [W.time, dep.get("name", "?"), p.x, p.y]
	for v in W.mission.friendly_vehicles:
		line += "  %s %.0f м%s" % [v.vname, Vector2(v.global_position.x, v.global_position.z).distance_to(p), " offmap" if v.offmap else ""]
	for sq in W.mission.friendly_squads:
		var c: Vector3 = sq.center()
		line += "  %s %.0f м%s" % [sq.short, Vector2(c.x, c.z).distance_to(p), " в машині" if sq.mounted else ""]
	print(line)
	if W.time >= 240.0:
		get_tree().quit()


## `--profile --ui-cost`: switch parts of the interface off for 30 s each and
## print the average CPU process time per frame in every window.
var _uc_phase := -1
var _uc_sum := 0.0
var _uc_n := 0
const UC_PHASES := ["normal", "no markers", "no minimap", "hud not updating", "no hud at all", "normal again"]


func _ui_cost() -> void:
	if W.ui == null or W.ui.hud == null or W.time < 60.0:
		return
	var ph := clampi(int((W.time - 60.0) / 30.0), 0, UC_PHASES.size())
	if ph != _uc_phase:
		if _uc_phase >= 0 and _uc_n > 0:
			print("[UICOST] %-18s process %.2f ms, fps %d" % [UC_PHASES[_uc_phase], _uc_sum / _uc_n, Engine.get_frames_per_second()])
		_uc_phase = ph
		_uc_sum = 0.0
		_uc_n = 0
		var h = W.ui.hud
		h.markers.visible = ph != 1 and ph != 4
		h.minimap.get_parent().visible = ph != 2 and ph != 4
		h.set_process(ph != 3 and ph != 4)
		h.visible = ph != 4
		if ph >= UC_PHASES.size():
			get_tree().quit()
	_uc_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_uc_n += 1
