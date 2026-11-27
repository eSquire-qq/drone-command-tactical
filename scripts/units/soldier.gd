class_name Soldier
extends Node3D
## UnitController for one infantryman: state, movement, weapon handling,
## posture. Decisions are made by SoldierAI (shared by both sides).

enum H { HEALTHY, WOUNDED, INCAP, DEAD }
enum P { STAND, CROUCH, PRONE }

const EYE := [1.65, 1.05, 0.42]
const CHEST := [1.3, 0.82, 0.3]

var side = 0
var role = "rifleman"
var rdata: Dictionary = {}
var uname = ""
var squad = null
var model: SoldierModel
var ai: SoldierAI
var health = H.HEALTHY
var hp = 100.0
var morale = 75.0
var max_morale = 75.0
var suppression = 0.0
# suppression model (see AIConfig)
var supp_level := 0          # 0 calm .. 4 panic
var supp_heat := 0.0         # recent incoming fire intensity
var stress := 0.0            # long-term stress, fades slowly
var last_threat_t := -99.0
var support_k := 1.0         # recovery bonus from calm comrades / leader nearby
var grit := 1.0              # personal resistance to suppression
var discipline := 1.0        # will to obey orders under fire
var react_t := 0.0           # surprised: the AI keeps its last decision until this runs out
var recover_k := 1.0         # how fast he calms down (rank)
var base_stress := 0.0       # carried from earlier missions (campaign strain)
var memory: Array = []       # campaign memory lines (display)
var strain := 0.0
var pinned_s := 0.0          # s at level >= 3 this mission
var panicked := false        # reached panic this mission
var _hot_t := -99.0          # last time at level >= 2
var flinch_t := 0.0          # drops for a moment after a close blast
var cover_dash_t := 0.0      # running to nearby cover under fire: not interrupted
var area_target = null       # suppressive fire at a last known enemy position
var shots := 0               # rounds fired (tests / stats)
var nades_used := 0
var nades_start := 0
var gl_start := 0
var posture = P.STAND
var weapon: Dictionary = {}
var mags_left := -1           # spare magazines; -1 = not counted (vehicle crews, special weapons)
var _ammo_told := false
var mag = 0
var grenades = 0
var gl_rounds = 0
var rockets = 0
var smokes = 0
var skill = 1.0
var is_medic = false
var noncombat = false

# movement
var path = PackedVector3Array()
var path_i = 0
var moving = false
var run = true
var cur_speed = 0.0
var yaw = 0.0
var move_yaw = 0.0
var slot = Vector3.ZERO
var can_advance = true
var solo = ""
var ew_carrier = false      # carries a portable trench jammer
var surrendered = false
var escort = null
var captured = false
var camp_id = ""
var rank_short = ""
# experience modifiers (campaign ranks; 1.0 / 0.0 = an ordinary soldier)
var down_by = ""
var _prog_t = 0.0
var _col_wait_t := 0.0        # waiting behind a man in the column who has stopped
var _prog_d = INF
var _noclamp_t = 0.0
var vet_supp = 1.0
var vet_reload = 1.0
var vet_speed = 1.0
var vet_cqb = 1.0
var vet_nade = 0.45
var vet_close = 0.0
var vet_survive = 0.0


func apply_rank(rk: Dictionary) -> void:
	rank_short = rk["short"]
	skill *= 1.0 + float(rk["skill"])
	max_morale += float(rk["morale"])
	morale = max_morale
	hp = 100.0 + float(rk["hp"])
	vet_supp = float(rk["supp"])
	vet_reload = float(rk["reload"])
	vet_speed = float(rk["speed"])
	vet_cqb = float(rk["cqb"])
	vet_nade = float(rk["cqb_nade"])
	vet_close = float(rk["close"])
	vet_survive = float(rk["survive"])
	grit *= float(rk.get("grit", 1.0))
	discipline *= float(rk.get("disc", 1.0))
	recover_k = float(rk.get("recover", 1.0))


## Campaign memory: strain from earlier missions and hardening.
func apply_memory(cs: Dictionary) -> void:
	strain = float(cs.get("strain", 0.0))
	grit += float(cs.get("grit_bonus", 0.0))
	memory = cs.get("memory", []).duplicate()
	base_stress = strain * AIConfig.MEM_BASE_STRESS
	stress = base_stress
	max_morale = maxf(30.0, max_morale - strain * AIConfig.MEM_MORALE)
	morale = max_morale


## Campaign: a unit that lost its commander or veterans is shakier.
func apply_cohesion(c: float) -> void:
	if c >= 0.999:
		return
	max_morale *= 0.8 + 0.2 * c
	morale = max_morale
	discipline *= 0.85 + 0.15 * c


enum PS { CALM, ALERT, STRESSED, SUPPRESSED, PANICKED, RECOVERING }


## Psychological state shown to the player — derived from the suppression
## model (levels, stress, recent threat), not a separate simulation.
func psych_state() -> int:
	if supp_level >= 4:
		return PS.PANICKED
	if supp_level >= 2:
		return PS.SUPPRESSED
	if W.time - _hot_t < AIConfig.PSY_RECOVER_T and _hot_t > 0.0:
		return PS.RECOVERING
	if stress >= AIConfig.PSY_STRESSED:
		return PS.STRESSED
	if supp_level >= 1 or W.time - last_threat_t < AIConfig.PSY_ALERT_T:
		return PS.ALERT
	return PS.CALM
var prefer_trench = false
var follow_ahead = null      # column: the man in front during trench clearing
var cqb_wait = 0.0
var cqb_corner_t = 0.0          # individual order overriding the squad order
var team = 0
var escaping = false

# combat
var target = null
var target_vis = 0.0
var fire_ok = false
var fire_cd = 0.0
var burst_left = 0
var reloading = 0.0
var flash_t = 0.0
var action = ""
var action_t = 0.0
var action_dur = 0.0
var action_fired = false
var action_payload = null
var grenade_cd = 0.0
var rocket_cd = 0.0
var atgm = 0
var atgm_cd = 0.0
var pinned_t = 0.0

# status
var vehicle = null
var bunker = null
var post = null              # window post in a building (Buildings)
var post_pending = null      # window post he is walking to
var bunker_deep = false
var bleed = 0.0
var aided = false
var aid_by = null
var aid_target = null
var aid_since := 0.0         # when the walk to aid_target began
var aid_skip = null          # a casualty this man could not reach (not retried)
var evac_marked = false
var evac_walk = false
var evacuated = false
var carried = false
var on_board = false
var broken = false
var was_wounded = false
var revealed = 0.0
var detect = 0.0
var marked = false
var ever_seen = false
var last_seen_pos = Vector3.ZERO
var last_seen_t = -999.0
var selected = false
var kills = 0
var ring: MeshInstance3D
var ai_timer = 0.0
var death_cause = ""


func setup(p_side: int, p_role: String, p_squad, p_name: String) -> void:
	side = p_side
	role = p_role
	squad = p_squad
	uname = Loc.person(p_name)
	rdata = Db.ROLES[role]
	var wid: String = rdata["weapon"]
	weapon = Db.WEAPONS.get(wid, {})
	mags_left = int(weapon.get("mags", -1))
	if mags_left > 0 and p_side == 1:
		mags_left = int(round(mags_left * AIConfig.AMMO_DEFENDER_K))
	noncombat = weapon.is_empty()
	mag = int(weapon.get("mag", 0))
	grenades = int(rdata["grenades"])
	gl_rounds = int(rdata.get("gl", 0))
	nades_start = grenades
	gl_start = gl_rounds
	rockets = int(rdata["rockets"])
	atgm = int(rdata.get("atgm", 0))
	smokes = int(rdata["smoke"])
	skill = float(rdata["skill"]) * randf_range(0.85, 1.15)
	max_morale = float(rdata["morale"]) * randf_range(0.9, 1.1)
	morale = max_morale
	grit = randf_range(AIConfig.GRIT_RANGE.x, AIConfig.GRIT_RANGE.y)
	discipline = randf_range(AIConfig.DISCIPLINE_RANGE.x, AIConfig.DISCIPLINE_RANGE.y)
	if role == "leader" or role == "assault":
		discipline *= 1.1
	is_medic = rdata.get("medic", false)
	model = SoldierModel.new()
	add_child(model)
	model.build(side, role)
	ring = MeshInstance3D.new()
	ring.mesh = MF.torus(0.55, 0.7, 16, 3)
	ring.material_override = MF.glow(Color(0.3, 0.75, 1.0), 1.5)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.08
	ring.visible = false
	add_child(ring)
	ai = SoldierAI.new(self)
	ai_timer = randf() * 0.5


func display_name() -> String:
	return "%s %s" % [rdata["name"], uname] if uname != "" else String(rdata["name"])


func is_active() -> bool:
	return (health == H.HEALTHY or health == H.WOUNDED) and not evacuated and vehicle == null and not on_board and not surrendered


func in_trench() -> bool:
	return W.grid.in_channel(global_position)


func _lift() -> float:
	if bunker != null:
		return 0.0
	if posture == P.STAND and not moving and in_trench() and target != null:
		return 0.62   # up on the firing step
	return 0.0


func eye_point() -> Vector3:
	if post != null:
		return global_position + Vector3(0, AIConfig.BLD_EYE, 0)
	var h: float = EYE[posture]
	if bunker != null:
		h = 1.15
	elif posture == P.STAND and in_trench():
		h += 0.68   # firing step: eyes just over the parapet
	return global_position + Vector3(0, h, 0)


func aim_point() -> Vector3:
	var h: float = CHEST[posture]
	if post != null and health < H.INCAP:
		return global_position + Vector3(0, AIConfig.BLD_AIM, 0)
	if health == H.INCAP or health == H.DEAD:
		h = 0.2
	elif bunker != null:
		h = 0.95
	elif posture == P.STAND and in_trench():
		h += 0.9    # head and shoulders above the parapet
	return global_position + Vector3(0, h, 0)


func signature() -> float:
	var s: float = [1.0, 0.65, 0.32][posture]
	if moving:
		s *= 1.45
		# running across bare ground: nothing breaks up the silhouette
		var i: int = W.grid.cidx(global_position.x, global_position.z)
		if W.grid.cover[i] < 0.15 and W.grid.foliage[i] < 0.1:
			s *= 1.35
	if flash_t > 0.0:
		s *= 2.4
	if bunker != null:
		s *= 0.35
	elif not moving and W.grid.camo_at(global_position):
		s *= 0.4
	return s


func cover_value() -> float:
	if post != null and not moving:
		return AIConfig.BLD_WINDOW_COVER
	if bunker != null:
		return 0.88 * (AIConfig.BUNKER_DAMAGED_PROT if bunker.damaged else 1.0)
	var c: float = W.grid.cover_at(global_position)
	if moving:
		c *= 0.45
	var post: float = [0.0, 0.12, 0.32][posture]
	return clampf(c + post * (1.0 - c), 0.0, 0.92)


## Caught unawares: a short, personal reaction delay.
func surprise() -> void:
	var k: float = (1.15 - 0.15 * discipline) / maxf(vet_speed, 0.5)
	react_t = maxf(react_t, randf_range(AIConfig.REACT_MIN, AIConfig.REACT_MAX) * k)


## Fear from fire. kind: "bullet" (aimed at / hitting near me), "crack" (rounds
## passing close), "blast" (explosion), "wound". Gain grows with the intensity
## of recent fire, shrinks with suitable cover and personal grit.
func add_suppression(v: float, kind: String = "bullet") -> void:
	if health >= H.INCAP or v <= 0.0:
		return
	var c: float = cover_value()
	var prot: float = float(AIConfig.COVER_PROTECT.get(kind, 0.4))
	# bullets come in bursts of many rounds (scaled); a blast or a wound is one event
	var raw: float = v * (AIConfig.GAIN_SCALE if kind == "bullet" or kind == "crack" else 1.0)
	if W.time - last_threat_t > AIConfig.REACT_CALM_T:
		surprise()
	var gain: float = raw * (1.0 - c * prot) * vet_supp / grit * (1.0 + supp_heat / AIConfig.HEAT_GAIN_DIV)
	gain *= clampf(1.0 - suppression / AIConfig.SATURATION, 0.05, 1.0)
	supp_heat = minf(AIConfig.HEAT_MAX, supp_heat + raw)
	suppression = minf(100.0, suppression + gain)
	morale = maxf(0.0, morale - gain * AIConfig.MORALE_PER_SUPP)
	last_threat_t = W.time
	if kind == "blast" and gain > AIConfig.BLAST_FLINCH:
		flinch_t = randf_range(0.8, 1.6)
	_update_supp_level()


func _update_supp_level() -> void:
	var l := AIConfig.level_of(suppression)
	if suppression >= AIConfig.PANIC_SUPP and (stress > AIConfig.PANIC_STRESS or morale < AIConfig.PANIC_MORALE):
		l = 4
	supp_level = l


# ------------------------------------------------------------------ orders
func move_to(p: Vector3, p_run: bool = true) -> void:
	if post != null:
		var pb = Buildings.at(p)
		if pb != null and pb["id"] == post["b"]:
			stop()
			return   # sent somewhere in the same building: he keeps his window
		if Vector2(p.x - post["post"].x, p.z - post["post"].z).length() > 0.8:
			Buildings.release(self)
	if bunker != null and not bunker_deep:
		bunker.release_occupant(self)
	elif bunker != null and bunker_deep:
		bunker.release_occupant(self)
	path = W.grid.find_path_inf(global_position, p, prefer_trench)
	path_i = 0
	moving = path.size() > 0
	run = p_run


func stop() -> void:
	moving = false
	path = PackedVector3Array()
	path_i = 0


func arrived(tol: float = 2.5) -> bool:
	return not moving and Vector2(global_position.x - slot.x, global_position.z - slot.z).length() < tol


func start_action(kind: String, dur: float, payload = null, keep_path: bool = false) -> void:
	action = kind
	action_t = 0.0
	action_dur = dur
	action_fired = false
	action_payload = payload
	if not keep_path:
		stop()
	if kind == "grenade" or kind == "smoke":
		model.start_throw()


## No grenade where a comrade would be caught in the blast.
func blast_safe(p: Vector3, r: float = 7.0) -> bool:
	for u in W.units:
		if u != self and u.side == side and u.health < H.DEAD and not u.evacuated and u.vehicle == null and not u.on_board:
			if u.global_position.distance_to(p) < r:
				return false
	return true


func yaw_to(p: Vector3) -> float:
	var d = p - global_position
	return atan2(-d.x, -d.z)


# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("soldier", t0)


func _process_body(delta: float) -> void:
	if not W.running() and not W.photo_mode:
		_animate(delta, 0.0, false, false, 0.0)
		_update_visibility()
		return
	if health == H.DEAD:
		_animate(delta, 0.0, false, false, 0.0)
		_update_visibility()
		ring.visible = false
		return
	if vehicle != null or on_board or evacuated:
		_update_visibility()
		return
	_update_status(delta)
	if health == H.INCAP:
		_animate(delta, 0.0, false, false, 0.0)
		_update_visibility()
		ring.visible = false
		return
	ai_timer -= delta
	if ai_timer <= 0.0:
		var dt = 0.4 + randf() * 0.15
		ai_timer = dt
		var ta := Time.get_ticks_usec()
		ai.think(dt)
		if Prof.on:
			Prof.add("soldier.ai", ta)
	_update_action(delta)
	_update_weapon(delta)
	_update_move(delta)
	_update_facing(delta)
	_update_posture()
	_animate(delta, cur_speed, action == "aid", action == "rocket" or action == "atgm", _lift())
	_update_visibility()
	ring.visible = selected


## Animation level of detail: a man nobody can see (hidden by the fog of war)
## or far from the drone is animated less often, with the time saved up so the
## pose catches up smoothly. The game logic still runs every frame.
var _anim_acc := 0.0
var _anim_skip := 0


func _animate(delta: float, speed: float, aiding: bool, launching: bool, lift: float) -> void:
	_anim_acc += delta
	var every := 1
	if not model.visible:
		every = 8
	elif W.cam != null and W.cam.cam != null:
		var d2: float = W.cam.cam.global_position.distance_squared_to(global_position)
		if d2 > 200.0 * 200.0:
			every = 4
		elif d2 > 120.0 * 120.0:
			every = 2
	_anim_skip += 1
	if _anim_skip < every:
		return
	_anim_skip = 0
	model.animate(minf(_anim_acc, 0.25), speed, posture, health, aiding, launching, lift)
	_anim_acc = 0.0


func _update_status(delta: float) -> void:
	# suppression holds for a while after the last threat, then fades;
	# stress (built up under fire) slows the fade and keeps a floor
	supp_heat = maxf(0.0, supp_heat - AIConfig.HEAT_DECAY * delta)
	var hold: float = AIConfig.HOLD_BASE + AIConfig.HOLD_PER_LEVEL * supp_level
	if W.time - last_threat_t > hold:
		var dec: float = AIConfig.DECAY_BASE + (AIConfig.DECAY_COVER_BONUS if cover_value() >= 0.4 else 0.0)
		dec *= (1.0 - stress / 100.0 * AIConfig.STRESS_SLOWS) * support_k * recover_k
		suppression = maxf(minf(suppression, stress * AIConfig.STRESS_FLOOR), suppression - dec * delta)
	if supp_level >= 2:
		stress = minf(100.0, stress + AIConfig.STRESS_GAIN * suppression / 100.0 * delta)
	elif supp_level <= 1:
		stress = maxf(base_stress, stress - AIConfig.STRESS_DECAY * delta * recover_k)
	if supp_level >= 2 and health < H.INCAP:
		_hot_t = W.time
	if supp_level >= 3 and health < H.INCAP:
		pinned_s += delta
	if supp_level >= 4:
		panicked = true
	flinch_t -= delta
	cover_dash_t -= delta
	_update_supp_level()
	flash_t -= delta
	grenade_cd -= delta
	rocket_cd -= delta
	atgm_cd -= delta
	pinned_t -= delta
	if revealed > 0.0:
		revealed -= delta
	if health == H.INCAP:
		bleed -= delta
		if bleed <= 0.0:
			W.damage.set_health(self, H.DEAD, null, "bleed")
		return
	if suppression < 10.0:
		morale = minf(max_morale, morale + delta * 0.7)


func _update_visibility() -> void:
	if side == 0:
		model.visible = vehicle == null and not on_board and not evacuated
		return
	if W.photo_mode:
		model.visible = not bunker_deep
		return
	if surrendered:
		model.visible = not evacuated
		return
	var vis = revealed > 0.0 and not bunker_deep
	if health == H.DEAD:
		vis = ever_seen
	elif health == H.INCAP:
		vis = ever_seen and revealed > -20.0
	model.visible = vis and not evacuated


func _update_move(delta: float) -> void:
	if not moving or carried:
		cqb_wait = maxf(0.0, cqb_wait - delta)
		cur_speed = move_toward(cur_speed, 0.0, delta * 8.0)
		return
	if path_i >= path.size():
		moving = false
		return
	if cqb_wait > 0.0 or action != "":
		cqb_wait -= delta
		cur_speed = move_toward(cur_speed, 0.0, delta * 10.0)
		return
	if follow_ahead != null:
		if not is_instance_valid(follow_ahead) or not follow_ahead.is_active() or follow_ahead.solo != "" or follow_ahead.squad != squad:
			follow_ahead = null   # gone, or left the file (escorting a prisoner, a task of his own)
		elif global_position.distance_to(follow_ahead.global_position) < AIConfig.CLEAR_SPACING - 0.1:
			# keep the column interval whatever the man ahead is doing: when he
			# pauses at the end of a leg the file used to walk into his back,
			# and in a narrow trench the pushing froze the whole column
			var fa = follow_ahead
			if not fa.moving and fa.cqb_wait <= 0.0 and fa.action == "":
				_col_wait_t += delta
				if _col_wait_t > 6.0:
					follow_ahead = null   # he is staying there: leave the file, go on alone
					_col_wait_t = 0.0
			else:
				_col_wait_t = 0.0
			cur_speed = move_toward(cur_speed, 0.0, delta * 10.0)
			return
	# progress watchdog: a waypoint we cannot get closer to is skipped
	_noclamp_t -= delta
	var wp: Vector3 = path[path_i]
	var wd := Vector2(wp.x - global_position.x, wp.z - global_position.z).length()
	if wd < _prog_d - 0.05:
		_prog_d = wd
		_prog_t = 0.0
	else:
		_prog_t += delta
		if _prog_t > 2.5:
			_prog_t = 0.0
			_prog_d = INF
			_noclamp_t = 1.5
			if path_i >= path.size() - 1:
				# the last point cannot be reached (a wall, rubble, a body of
				# men): he is as close as he gets — the walk is over, so the AI
				# can decide what next instead of "walking" on the spot forever
				moving = false
				return
			path_i += 1
	cqb_corner_t -= delta
	if cqb_corner_t <= 0.0:
		cqb_corner_t = 0.25
		if _cqb_corner():
			return
	var p = global_position
	var tgt: Vector3 = path[path_i]
	var dx = tgt.x - p.x
	var dz = tgt.z - p.z
	var L = sqrt(dx * dx + dz * dz)
	if L < 0.35:
		_prog_d = INF
		_prog_t = 0.0
		path_i += 1
		if path_i >= path.size():
			moving = false
		return
	var sp = _speed()
	cur_speed = move_toward(cur_speed, sp, delta * 6.0)
	var step = minf(L, cur_speed * delta)
	p.x += dx / L * step
	p.z += dz / L * step
	p += _separation() * delta
	# inside the trench: stay between the revetted walls
	if _noclamp_t <= 0.0 and W.grid.trench_near[W.grid.cidx(p.x, p.z)] != 0 and W.grid.trench_d(tgt.x, tgt.z) < 0.5:
		var cl: Vector3 = W.grid.trench_closest(p.x, p.z)
		if cl.z < 1.2 and cl.z > 0.42:
			var c2 := Vector2(cl.x, cl.y)
			var q := c2 + (Vector2(p.x, p.z) - c2).normalized() * 0.42
			p.x = q.x
			p.z = q.y
	p.y = W.grid.height_at(p.x, p.z)
	global_position = p
	move_yaw = atan2(-dx, -dz)
	if side == 0 and W.mines:
		W.mines.check_soldier(self)


## Close-quarters drill at a trench corner: grenade or "slicing the pie".
func _cqb_corner() -> bool:
	if noncombat or broken or carried or surrendered:
		return false
	if not in_trench():
		return false
	var hot: bool = squad != null and (squad.threat_level() > 0 or squad.side == 1)
	if not hot and side == 0 and W.mission != null:
		hot = W.mission.def.capture_rect.has_point(Vector2(global_position.x, global_position.z))
	if not hot:
		return false
	var acc := 0.0
	var prev := global_position
	for j in range(path_i, mini(path.size() - 1, path_i + 6)):
		var c: Vector3 = path[j]
		acc += Vector2(c.x - prev.x, c.z - prev.z).length()
		if acc > 3.2:
			break
		var din := Vector2(c.x - prev.x, c.z - prev.z)
		var nx: Vector3 = path[j + 1]
		var dout := Vector2(nx.x - c.x, nx.z - c.z)
		prev = c
		if din.length() < 0.2 or dout.length() < 0.2:
			continue
		# gentle traverse bends (<~46°) are walked through; junctions and sharp
		# turns are real corners that hide the next bay
		if absf(din.angle_to(dout)) < 0.8 or W.grid.trench_d(c.x, c.z) > 0.6:
			continue
		var key := Vector2i(roundi(c.x * 0.7), roundi(c.z * 0.7))
		if squad.corners.has(key) and W.time - float(squad.corners[key]) < 35.0:
			return false
		squad.corners[key] = W.time
		var od := dout.normalized()
		var beyond := Vector3(c.x + od.x * 4.5, c.y, c.z + od.y * 4.5)
		var known_age := INF
		for e in squad.known.keys():
			if W.is_alive_target(e) and (squad.known[e]["pos"] as Vector3).distance_to(beyond) < 14.0:
				known_age = minf(known_age, W.time - float(squad.known[e]["t"]))
		yaw = atan2(-od.x, -od.y)
		# a grenade only if someone is known to be behind the corner; an empty
		# corner is checked by "slicing the pie" with a short burst
		var corner_ok: bool = known_age <= AIConfig.CORNER_INFO_AGE and \
			GrenadeLogic.check(self, beyond, "hand", "corner", 0.0, 0.7) == ""
		if corner_ok and randf() < 0.55 + vet_nade * 0.5:
			GrenadeLogic.commit(self, beyond, "hand")
			start_action("grenade", 1.1, beyond, true)
			cqb_wait = 1.6 * vet_cqb
			ai.state = "граната за ріг"
		else:
			W.combat.fire_at_point(self, Vector3(c.x + od.x * 7.0, c.y + 1.0, c.z + od.y * 7.0))
			cqb_wait = 0.7 * vet_cqb
			ai.state = "прострілює кут"
		return true
	return false


func _speed() -> float:
	var s = 3.4 if run else 1.6
	if posture == P.CROUCH:
		s *= 0.62
	elif posture == P.PRONE:
		s = 0.55
	if health == H.WOUNDED:
		s *= 0.65
	if in_trench():
		s *= 0.85
	if W.grid.inf_weight[W.grid.cidx(global_position.x, global_position.z)] > 2.0:
		s *= 0.45   # wire
	s *= vet_speed
	s *= float(Game.wx("move"))
	s *= float(AIConfig.LEVEL_SPEED[supp_level])
	return s


func _separation() -> Vector3:
	if squad == null:
		return Vector3.ZERO
	var push = Vector3.ZERO
	for m in squad.members:
		if m == self or not m.is_active():
			continue
		if m.follow_ahead == self:
			continue   # the man behind me in a column does not push me back
		var d: Vector3 = global_position - m.global_position
		d.y = 0.0
		var l = d.length()
		if l < 1.1 and l > 0.001:
			push += d / l * (1.1 - l) * 2.0
	return push


func _update_facing(delta: float) -> void:
	var want = yaw
	if bunker != null:
		want = MF.yaw_facing(bunker.face)
		if target != null and W.is_alive_target(target):
			var ty = yaw_to(target.global_position)
			if absf(angle_difference(want, ty)) < 1.1:
				want = ty
	elif target != null and W.is_alive_target(target) and (not moving or fire_ok):
		want = yaw_to(target.global_position)
	elif area_target != null and fire_ok and not moving:
		want = yaw_to(area_target)
	elif moving:
		want = move_yaw
	elif action == "aid" and aid_target != null and is_instance_valid(aid_target):
		want = yaw_to(aid_target.global_position)
	yaw = lerp_angle(yaw, want, clampf(delta * 6.0, 0.0, 1.0))
	rotation.y = yaw


func _update_posture() -> void:
	if moving:
		if posture == P.PRONE and pinned_t <= 0.0 and run:
			posture = P.CROUCH
		elif ai.want_posture != P.PRONE and posture == P.PRONE:
			posture = P.CROUCH
		elif ai.want_posture == P.STAND and posture == P.CROUCH and run:
			posture = P.STAND
		elif ai.want_posture == P.CROUCH and posture == P.STAND:
			posture = P.CROUCH
		return
	if action == "aid":
		posture = P.CROUCH
		return
	if flinch_t > 0.0:
		posture = P.CROUCH if in_trench() else P.PRONE   # ducks from a close blast
		return
	posture = ai.want_posture


func _update_weapon(delta: float) -> void:
	fire_cd -= delta
	reloading -= delta
	if action != "" or noncombat or broken:
		burst_left = 0
		return
	if not fire_ok:
		burst_left = 0
		return
	if not W.is_alive_target(target):
		if area_target != null and reloading <= 0.0 and fire_cd <= 0.0 and not ammo_low():
			if mag <= 0:
				_reload()
			else:
				_area_burst()
			return
		burst_left = 0
		return
	if target is Vehicle or target is Bunker:
		return   # small arms don't engage armour; AT handled by actions
	if reloading > 0.0 or fire_cd > 0.0:
		return
	if absf(angle_difference(yaw, yaw_to(target.global_position))) > 0.4:
		return
	if mag <= 0:
		_reload()
		return
	if burst_left <= 0:
		var b: Array = weapon["burst"]
		burst_left = randi_range(b[0], b[1])
		if ammo_low():
			burst_left = mini(burst_left, AIConfig.AMMO_LOW_BURST)
	W.combat.fire(self, target, weapon)
	shots += 1
	mag -= 1
	burst_left -= 1
	flash_t = 0.3
	model.do_kick()
	if burst_left <= 0:
		var pz: Array = weapon["pause"]
		fire_cd = randf_range(pz[0], pz[1]) * float(AIConfig.LEVEL_ROF[supp_level]) * (1.25 if moving else 1.0)
	else:
		fire_cd = float(weapon["interval"])


## A fresh magazine from the spares (none left: he cannot fire any more).
func _reload() -> void:
	if mags_left == 0:
		if not _ammo_told and side == 0 and squad != null:
			_ammo_told = true
			squad.radio("ammo", Loc.t("%s: немає набоїв!") % display_name(), "warn")
		return
	if mags_left > 0:
		mags_left -= 1
	reloading = float(weapon["reload"]) * vet_reload
	mag = int(weapon["mag"])


## Short of ammunition: one spare magazine or less (no suppressive fire,
## short bursts at visible targets only).
func ammo_low() -> bool:
	return mags_left >= 0 and mags_left <= AIConfig.AMMO_LOW_MAGS


func out_of_ammo() -> bool:
	return mags_left == 0 and mag <= 0


## Rounds left in all (loaded + spare), -1 when not counted.
func rounds_left() -> int:
	if mags_left < 0:
		return -1
	return mag + mags_left * int(weapon.get("mag", 0))


## Why he is not shooting right now ("" — he is, or has nothing to do).
func fire_reason() -> String:
	if health >= H.INCAP or noncombat or weapon.is_empty():
		return ""
	if out_of_ammo():
		return Loc.t("немає набоїв")
	if reloading > 0.0:
		return Loc.t("перезаряджає")
	if supp_level >= 3 or (supp_level >= 2 and not ai.peeking):
		return Loc.t("притиснутий")
	if action != "":
		return ""
	if not W.is_alive_target(target):
		if area_target != null:
			return "" if not ammo_low() else Loc.t("береже набої")
		if squad != null and squad.threat_level() > 0:
			return Loc.t("немає видимості")
		return Loc.t("ціль не виявлена")
	if global_position.distance_to(target.global_position) > float(weapon.get("range", 100.0)):
		return Loc.t("далеко")
	if not fire_ok and moving:
		return Loc.t("рухається")
	return ""


## Suppressive burst at the last known position of an enemy who ducked.
func _area_burst() -> void:
	var p: Vector3 = area_target
	if absf(angle_difference(yaw, yaw_to(p))) > 0.5:
		return
	var b: Array = weapon["burst"]
	var n := mini(randi_range(b[0], b[1]), mag)
	for i in n:
		W.combat.fire_area(self, p, weapon)
	mag -= n
	shots += n
	flash_t = 0.3
	model.do_kick()
	var pz: Array = weapon["pause"]
	fire_cd = randf_range(pz[0], pz[1]) * 1.4 * float(AIConfig.LEVEL_ROF[supp_level])


func _update_action(delta: float) -> void:
	if action == "":
		return
	action_t += delta
	if not action_fired and action_t >= action_dur * 0.55:
		action_fired = true
		_execute_action()
	if action_t >= action_dur:
		if action == "aid":
			_finish_aid()
		action = ""
		action_payload = null


func _execute_action() -> void:
	match action:
		"grenade":
			if action_payload is Vector3:
				W.combat.throw_grenade(self, action_payload)
		"gl":
			if action_payload is Vector3:
				W.combat.fire_gl(self, action_payload)
		"smoke":
			if action_payload is Vector3:
				W.combat.throw_smoke(self, action_payload)
		"atgm":
			if W.is_alive_target(action_payload):
				W.combat.fire_atgm(self, action_payload)
		"rocket":
			if W.is_alive_target(action_payload):
				W.combat.fire_rocket(self, action_payload)


func _finish_aid() -> void:
	var cand = action_payload
	if cand != null and is_instance_valid(cand) and cand.health == H.INCAP:
		cand.aided = true
		cand.bleed += 300.0 if is_medic else 180.0
		if side == 0:
			squad.radio("evac", Loc.t("надано першу допомогу (%s)") % cand.display_name(), "good")
	if cand != null and is_instance_valid(cand):
		cand.aid_by = null
	aid_target = null
