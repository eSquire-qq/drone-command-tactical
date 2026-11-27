class_name EwSystem
extends Node
## Electronic warfare.
## * Jammer stations (РЕБ) — big radius, dug-in and camouflaged: area fire
##   (mortar) barely scratches them; only a direct hit (FPV/ATGM) works.
##   One of them may be a decoy. A destroyed station is replaced by a backup.
## * Portable "trench" jammers carried by enemy infantry — small radius, they
##   keep the drone away from the trenches until the position is taken.
## * Our recon drone: the link degrades near jammers; under CRITICAL there is
##   a growing chance the drone simply falls. Then the player is blind —
##   units keep executing their last orders — until a spare drone arrives.
## * Enemy radio-recon (РЕР) direction-finds a drone loitering in the jammed
##   zone and answers with fire on our positions.

const DEGRADED := 0.6
const CRITICAL := 0.35
const RELAUNCH_TIME := 90.0
const TRENCH_EW_RADIUS := 38.0

var stations: Array = []
var backups: Array = []         # Vector2 spots for backup jammers
var backup_left := 1
var backup_queue: Array = []    # {t, pos}
var link := 1.0
var rer := 0.0
var rer_cd := 30.0
var glitch := 0.0
var _warn_t := -99.0
var drone_down := false
var spares := 0
var relaunch_t := -1.0
var drones_lost := 0
var immune := false     # video recording: the camera drone never crashes
var crash_risk_ui := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


var map_seed := 1


func setup(def: MapDef) -> void:
	map_seed = def.seed
	var rng = RandomNumberGenerator.new()
	rng.seed = def.seed + 77
	for p in def.ew_stations:
		_spawn_station(p, false, rng)
	for p in def.ew_decoys:
		_spawn_station(p, true, rng)
	backups = def.ew_backups.duplicate()


func _spawn_station(p: Vector2, decoy: bool, rng: RandomNumberGenerator) -> EwStation:
	var st = EwStation.new()
	W.map.add_child(st)
	st.setup(MapModels.obj_rng(map_seed, p))
	st.decoy = decoy
	st.global_position = W.grid.ground(Vector3(p.x, 0, p.y))
	st.rotation.y = rng.randf() * TAU
	stations.append(st)
	var c: int = W.grid.cidx(p.x, p.y)
	W.grid.veh_solid[c] = 1
	return st


func alive_stations() -> Array:
	var out: Array = []
	for st in stations:
		if not st.destroyed and not st.decoy:
			out.append(st)
	return out


## Jamming factor 0..1 at a point.
func jam_at(p: Vector3) -> float:
	var j = 0.0
	for st in stations:
		if st.destroyed or st.decoy:
			continue
		var d = Vector2(p.x - st.global_position.x, p.z - st.global_position.z).length()
		j = maxf(j, clampf(1.0 - d / st.radius, 0.0, 1.0))
	for u in W.units:
		if u.side != 1 or not u.ew_carrier or not u.is_active():
			continue
		var d = Vector2(p.x - u.global_position.x, p.z - u.global_position.z).length()
		if d < TRENCH_EW_RADIUS:
			j = maxf(j, (1.0 - d / TRENCH_EW_RADIUS) * 0.95)
	return j


## Link quality of a drone at p. Altitude helps, but not right over a jammer.
func signal_at(p: Vector3) -> float:
	var j = jam_at(p)
	if j <= 0.0:
		return 1.0
	var alt = p.y - W.grid.height_at(p.x, p.z)
	var alt_bonus = clampf((alt - 20.0) / 110.0, 0.0, 1.0)
	return clampf(1.0 - j * 1.55 + alt_bonus * 0.75 * j, 0.0, 1.0)


func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("ew", t0)


func _process_body(delta: float) -> void:
	var dt = delta / maxf(Engine.time_scale, 0.01)
	glitch = maxf(0.0, glitch - dt)
	if W.cam and W.cam.cam and not drone_down:
		link = signal_at(W.cam.cam.global_position)
	elif drone_down:
		link = 0.0
	if W.ui and W.ui.overlay and W.ui.overlay.material:
		var jam = clampf((DEGRADED - link) / DEGRADED, 0.0, 1.0)
		if not W.running():
			jam = 0.0
		W.ui.overlay.material.set_shader_parameter("jam", maxf(jam, glitch * 2.0))
	if not W.running() or get_tree().paused:
		return
	_update_backups()
	if drone_down:
		if relaunch_t >= 0.0:
			relaunch_t -= delta
			if relaunch_t <= 0.0:
				_restore_drone()
		return
	# crash risk in the critical zone
	crash_risk_ui = 0.0
	if link < CRITICAL and not immune:
		var hazard = (CRITICAL - link) * 1.3
		crash_risk_ui = clampf(hazard / 0.45, 0.0, 1.0)
		if randf() < 1.0 - exp(-hazard * delta):
			crash()
			return
		if W.time - _warn_t > 8.0 or _warn_t < 0.0:
			_warn_t = maxf(W.time, 0.01)
			Events.msg(Loc.t("КРИТИЧНИЙ РІВЕНЬ ЗВ'ЯЗКУ — дрон може впасти! Наберіть висоту або відведіть його."), "alert")
	# radio-recon
	rer_cd -= delta
	if link < DEGRADED:
		rer += delta * (1.0 - link) / 22.0
	else:
		rer = maxf(0.0, rer - delta / 40.0)
	if rer >= 1.0 and rer_cd <= 0.0:
		rer = 0.0
		rer_cd = 70.0
		if W.enemy_ai:
			W.enemy_ai.on_rer_fix()


# ------------------------------------------------------------------ drone loss
func crash() -> void:
	if drone_down:
		return
	drone_down = true
	drones_lost += 1
	glitch = 2.0
	rer = 0.0
	relaunch_t = -1.0
	if W.command:
		W.command.tool = ""
		W.command.clear_selection()
	if W.cam:
		W.cam.input_enabled = false
		W.cam.follow = null
	W.sfx.ui("radio")
	Events.msg(Loc.t("ЗВ'ЯЗОК З БПЛА ВТРАЧЕНО — дрон впав. Підрозділи діють за останніми наказами."), "alert")
	if W.blog:
		W.blog.drone_lost(W.cam.cam.global_position if W.cam and W.cam.cam else Vector3.ZERO)


func can_relaunch() -> bool:
	return drone_down and relaunch_t < 0.0 and spares > 0


func launch_spare() -> void:
	if not can_relaunch():
		return
	spares -= 1
	relaunch_t = RELAUNCH_TIME
	Events.msg(Loc.t("Запасний дрон злітає. Прибуття в район ~%d с.") % int(RELAUNCH_TIME), "info")


func _restore_drone() -> void:
	drone_down = false
	relaunch_t = -1.0
	glitch = 0.6
	if W.cam:
		W.cam.input_enabled = true
		W.cam.focus_on(W.mission.def.rally_point + Vector3(0, 0, -30), 110.0)
	Events.msg(Loc.t("Запасний дрон у районі. Зв'язок відновлено."), "good")
	if W.blog:
		W.blog.add("drone", Loc.t("Запасний дрон у районі"), null)
	W.sfx.ui("radio")


func blocked_warning() -> void:
	glitch = 0.45


# ------------------------------------------------------------------ jammers
func on_station_destroyed(st) -> void:
	if st.decoy:
		Events.msg(Loc.t("Уражено макет станції РЕБ — хибна ціль! Перешкоди не зменшились."), "warn")
		return
	Events.msg(Loc.t("Станцію РЕБ знищено — зв'язок з дронами покращився."), "good")
	if W.blog:
		W.blog.add("enemy", Loc.t("Станцію РЕБ знищено"), null)
	if backup_left > 0 and backups.size() > 0:
		backup_left -= 1
		var p: Vector2 = backups.pop_front()
		backup_queue.append({"t": W.time + randf_range(120.0, 180.0), "pos": p})


func _update_backups() -> void:
	var i = backup_queue.size() - 1
	while i >= 0:
		if W.time >= float(backup_queue[i]["t"]):
			var rng = RandomNumberGenerator.new()
			rng.randomize()
			var st = _spawn_station(backup_queue[i]["pos"], false, rng)
			st.radius = 75.0
			backup_queue.remove_at(i)
			if not drone_down:
				Events.msg(Loc.t("Фіксуємо нове джерело перешкод — противник розгорнув резервний РЕБ."), "warn")
		i -= 1


## Friendly FPV drones can lose their link inside the jammed zone.
func fpv_link_lost(p: Vector3) -> bool:
	var j = jam_at(p)
	return j > 0.2 and randf() < 0.035 * j
