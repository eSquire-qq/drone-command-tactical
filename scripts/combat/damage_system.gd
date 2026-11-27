class_name DamageSystem
extends Node
## Converts damage into individual health states (healthy / wounded /
## incapacitated / dead), handles morale effects and casualty messages.


func bullet_hit(u: Soldier, dmg: float, source) -> void:
	apply(u, dmg * randf_range(0.6, 1.5), source, false)


func apply(u: Soldier, dmg: float, source, explosive: bool) -> void:
	if u.health == Soldier.H.DEAD or u.evacuated:
		return
	if u.health == Soldier.H.INCAP:
		if dmg > 35.0 and randf() < 0.5:
			set_health(u, Soldier.H.DEAD, source, "hit")
		return
	u.hp -= dmg
	u.add_suppression(30.0, "wound")
	u.morale -= 8.0
	if u.hp <= 0.0:
		var kill_p = 0.36 + (0.12 if explosive else 0.0) + clampf((-u.hp) / 200.0, 0.0, 0.3) - u.vet_survive
		if randf() < kill_p:
			set_health(u, Soldier.H.DEAD, source, "hit")
		else:
			set_health(u, Soldier.H.INCAP, source, "hit")
	elif u.hp < 60.0 and u.health == Soldier.H.HEALTHY:
		set_health(u, Soldier.H.WOUNDED, source, "hit")


func _casualty_shock(u: Soldier) -> void:
	for m in W.units:
		if m == u or m.side != u.side or not m.is_active():
			continue
		var d: float = m.global_position.distance_to(u.global_position)
		if d < AIConfig.CASUALTY_SHOCK_R:
			m.add_suppression(AIConfig.CASUALTY_SHOCK * (1.0 - d / AIConfig.CASUALTY_SHOCK_R), "wound")


func set_health(u: Soldier, h: int, source, cause: String) -> void:
	var old = u.health
	if old == h or old == Soldier.H.DEAD:
		return
	u.health = h
	if h >= Soldier.H.INCAP and u.down_by == "":
		if source == null or not is_instance_valid(source):
			u.down_by = cause
		elif source is Soldier:
			u.down_by = "E:" + String(source.role) if source.side != u.side else "своїми"
		elif source is Vehicle:
			u.down_by = "техніка"
		else:
			u.down_by = Loc.t("засіб(%s)") % cause
	if h >= Soldier.H.WOUNDED:
		u.was_wounded = true
	match h:
		Soldier.H.WOUNDED:
			u.hp = minf(u.hp, 59.0)
		Soldier.H.INCAP:
			_casualty_shock(u)
			if u.side == 1 and W.intel:
				W.intel.neutralized(u)
			u.hp = 0.0
			u.bleed = randf_range(300.0, 450.0) * (float(Game.diff("bleed")) if u.side == 0 else 1.0)
			u.stop()
			u.target = null
			u.action = ""
			u.fire_ok = false
		Soldier.H.DEAD:
			if old < Soldier.H.INCAP:
				_casualty_shock(u)
				if u.side == 1 and W.intel:
					W.intel.neutralized(u)
			u.stop()
			u.target = null
			u.action = ""
			u.fire_ok = false
			u.marked = false
			u.death_cause = cause
			if u.carried:
				u.carried = false
	if u.bunker != null and h >= Soldier.H.INCAP:
		u.bunker.occupants.erase(u)
		u.bunker = null
	if h >= Soldier.H.INCAP and source != null and is_instance_valid(source) and "kills" in source:
		source.kills += 1
	_morale_effects(u, h)
	_announce(u, old, h, cause)
	Events.unit_state_changed.emit(u, old, h)


func _morale_effects(u: Soldier, h: int) -> void:
	if h < Soldier.H.INCAP:
		return
	var hit = 14.0 if h == Soldier.H.DEAD else 9.0
	for m in W.units:
		if m == u or m.side != u.side or not m.is_active():
			continue
		var d: float = m.global_position.distance_to(u.global_position)
		if d < 25.0:
			m.morale -= hit * (1.0 - d / 30.0)
			if m.squad == u.squad:
				m.morale -= 3.0
	if u.role == "leader" and u.squad != null:
		for m in u.squad.members:
			if m.is_active():
				m.morale -= 12.0
		if u.side == 0:
			u.squad.radio("casualty", Loc.t("командира виведено з ладу!"), "alert")
	# enemies get a boost when they put someone down
	for m in W.units:
		if m.side != u.side and m.is_active() and m.global_position.distance_to(u.global_position) < 60.0:
			m.morale = minf(m.max_morale, m.morale + 3.0)


func _sq_radio(u: Soldier, text: String, kind: String) -> void:
	if u.squad != null:
		u.squad.radio("casualty", text, kind)
	else:
		Events.msg("—: " + text, kind)


func _announce(u: Soldier, old: int, h: int, cause: String) -> void:
	if u.side != 0:
		if h == Soldier.H.DEAD and old != Soldier.H.INCAP and u.ever_seen:
			Events.msg(Loc.t("Противника знищено (%s)") % u.rdata["name"].to_lower(), "good")
		elif h == Soldier.H.INCAP and u.ever_seen:
			Events.msg(Loc.t("Противника уражено"), "good")
		return
	match h:
		Soldier.H.WOUNDED:
			_sq_radio(u, Loc.t("легке поранення — %s") % u.display_name(), "warn")
		Soldier.H.INCAP:
			_sq_radio(u, Loc.t("важке поранення — %s. Потрібна евакуація!") % u.display_name(), "alert")
		Soldier.H.DEAD:
			if cause == "bleed":
				_sq_radio(u, Loc.t("%s помер від ран") % u.display_name(), "alert")
			else:
				_sq_radio(u, Loc.t("загинув %s") % u.display_name(), "alert")
