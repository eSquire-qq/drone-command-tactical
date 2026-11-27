class_name Cinematic
extends Node
## Camera "director" for recorded videos (`-- --balance=smart --cinematic`,
## run with Godot's --write-movie). The balance bot plays the mission; this
## node cuts between wide shots of the fight, a followed squad and the enemy
## position under attack, keeps the game speed watchable and closes the video
## on the results screen. The recon drone is immune to EW so the "cameraman"
## never crashes mid-recording.

const SHOT_LEN := 9.0       # seconds of video per shot
const GAME_SPEED := 3.0     # battle time runs this much faster than the video

var shot_t := 0.0
var shot_i := 0
var end_t := -1.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = 7
	Events.mission_ended.connect(func(_r): end_t = 0.0)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	if end_t >= 0.0:
		end_t += real
		if end_t > 9.0:
			get_tree().quit()
		return
	if not W.running():
		return
	Engine.time_scale = GAME_SPEED
	if W.ew:
		W.ew.immune = true
	shot_t -= real
	if shot_t <= 0.0:
		shot_t = SHOT_LEN
		_next_shot()
		shot_i += 1


func _friendlies() -> Array:
	var out: Array = []
	for u in W.units:
		if u.side == 0 and u.is_active():
			out.append(u)
	return out


func _enemies() -> Array:
	var out: Array = []
	for u in W.units:
		if u.side == 1 and u.is_active():
			out.append(u)
	return out


## Where the fight is: friendlies closest to the enemy, averaged.
func _front() -> Vector3:
	var f := _friendlies()
	var e := _enemies()
	if f.is_empty():
		return W.mission.def.objective_rect.get_center().x * Vector3.RIGHT + W.mission.def.objective_rect.get_center().y * Vector3.BACK
	if e.is_empty():
		return _avg(f)
	f.sort_custom(func(a, b): return _dist_to(a, e) < _dist_to(b, e))
	return _avg(f.slice(0, mini(6, f.size())))


func _dist_to(u, list: Array) -> float:
	var best := INF
	for o in list:
		best = minf(best, u.global_position.distance_to(o.global_position))
	return best


func _avg(list: Array) -> Vector3:
	var c := Vector3.ZERO
	for u in list:
		c += u.global_position
	return c / maxf(list.size(), 1)


func _next_shot() -> void:
	W.cam.follow = null
	var yaw := rng.randf_range(-0.5, 0.5)
	if W.mission.phase == MissionManager.Phase.DEPLOY:
		# the column arriving
		var vs: Array = []
		for v in W.mission.friendly_vehicles:
			if not v.offmap and v.state != "destroyed":
				vs.append(v)
		if shot_i % 2 == 0 and not vs.is_empty():
			var v = vs[rng.randi() % vs.size()]
			W.cam.teleport_view(v.global_position, 40.0, 34.0, yaw)
			W.cam.follow = v
		else:
			W.cam.teleport_view(W.mission.def.camera_start + Vector3(0, 0, -20), 130.0, 40.0, yaw)
		return
	match shot_i % 4:
		0:
			# wide: the whole action from behind our line
			W.cam.teleport_view(_front() + Vector3(0, 0, -15), 125.0, 42.0, yaw * 0.5)
		1, 3:
			# a squad in the thick of it, followed
			var best = null
			var bs := -INF
			for sq in W.mission.friendly_squads:
				if sq.active_count() <= 0 or sq.mounted:
					continue
				var s: float = float(sq.threat_level()) * 10.0 + sq.active_count() + rng.randf() * 3.0
				if s > bs:
					bs = s
					best = sq
			if best:
				W.command.select_object(best)
				W.cam.teleport_view(best.center(), 42.0, 38.0, yaw)
				W.cam.follow = best
			else:
				W.cam.teleport_view(_front(), 90.0, 40.0, yaw)
		2:
			# the enemy position under attack
			var e := _enemies()
			if e.is_empty():
				W.cam.teleport_view(_front(), 70.0, 40.0, yaw)
			else:
				var fr := _front()
				e.sort_custom(func(a, b): return a.global_position.distance_to(fr) < b.global_position.distance_to(fr))
				W.cam.teleport_view(_avg(e.slice(0, mini(4, e.size()))), 60.0, 36.0, yaw + 0.3)
