class_name PrisonerSystem
extends Node
## Enemy soldiers who are beaten, cut off and face our troops at close range
## may surrender. A soldier from the nearest squad escorts them to the rear.

var prisoners: Array = []
var captured := 0
var _t := 0.0


## Called from SoldierAI for enemy soldiers.
func consider(u) -> void:
	if u.surrendered or not u.is_active() or u.side != 1:
		return
	var broken: bool = u.morale < 25.0 or u.broken or (u.health == Soldier.H.WOUNDED and u.morale < 45.0)
	if not broken:
		return
	var p: Vector3 = u.global_position
	var foes := 0
	var close := false
	for f in W.units:
		if f.side != 0 or not f.is_active():
			continue
		var d: float = f.global_position.distance_to(p)
		if d < 16.0:
			foes += 1
			if d < 11.0 and W.grid.visibility(f.eye_point(), u.aim_point()) > 0.2:
				close = true
	if not close or foes < 2:
		return
	for a in W.units:
		if a.side == 1 and a != u and a.is_active() and a.global_position.distance_to(p) < 10.0:
			return
	if randf() < 0.22:
		surrender(u)


func surrender(u) -> void:
	u.surrendered = true
	u.ew_carrier = false
	u.stop()
	u.target = null
	u.fire_ok = false
	u.action = ""
	u.marked = false
	if u.bunker != null:
		u.bunker.release_occupant(u)
	u.model.hands_up = true
	u.revealed = 999.0
	u.ever_seen = true
	prisoners.append(u)
	Events.msg(Loc.t("Противник здається в полон!"), "good")
	# escort from the nearest friendly squad that can spare a man
	var best = null
	var bd := 45.0
	for f in W.units:
		if f.side != 0 or not f.is_active() or f.role == "crew_medic" or f.solo == "escort" or f.squad == null:
			continue
		if f.squad.active_count() < 4:
			continue
		var d: float = f.global_position.distance_to(u.global_position)
		if f.role in ["leader", "mg", "at", "medic", "atgm"]:
			d += 20.0   # keep key specialists in the fight
		if d < bd:
			bd = d
			best = f
	if best != null:
		best.solo = "escort"
		best.escort = u
		best.follow_ahead = null
		u.escort = best
		best.squad.radio("order", Loc.t("%s конвоює полоненого в тил.") % best.display_name(), "info")
	u.move_to(W.mission.def.rally_point, false)


func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("prisoners", t0)


func _process_body(delta: float) -> void:
	if not W.running():
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	var rally: Vector3 = W.mission.def.rally_point
	var i := prisoners.size() - 1
	while i >= 0:
		var u = prisoners[i]
		if not is_instance_valid(u) or u.health >= Soldier.H.INCAP:
			_release_escort(u)
			prisoners.remove_at(i)
			i -= 1
			continue
		if u.global_position.distance_to(rally) < 7.0:
			u.captured = true
			u.evacuated = true
			u.model.visible = false
			captured += 1
			_release_escort(u)
			prisoners.remove_at(i)
			Events.msg(Loc.t("Полоненого доставлено в тил."), "good")
			if W.blog:
				W.blog.add("enemy", Loc.t("Полоненого доставлено в тил"), null)
			i -= 1
			continue
		if not u.moving:
			u.move_to(rally, false)
		var e = u.escort
		if e != null and is_instance_valid(e) and e.is_active():
			# re-route the escort only when he has stopped, or every 3 s while he
			# walks: a new route every half second started him back at a cell
			# centre behind him, and on the wire (half speed) he only shuffled
			var since: float = W.time - float(e.get_meta("esc_t", -99.0))
			if e.global_position.distance_to(u.global_position) > 4.0 and (not e.moving or (since > 3.0 and e.slot.distance_to(u.global_position) > 4.0)):
				var back: Vector3 = u.global_position + (u.global_position - rally).normalized() * 2.5
				e.slot = W.grid.free_point(back)
				e.move_to(e.slot, false)
				e.set_meta("esc_t", W.time)
		i -= 1


func _release_escort(u) -> void:
	if u == null or not is_instance_valid(u):
		return
	var e = u.escort
	if e != null and is_instance_valid(e):
		e.solo = ""
		e.escort = null
		if e.squad != null:
			e.slot = e.squad.center()
			e.move_to(e.slot, true)
	u.escort = null
