class_name CommandController
extends Node
## Player input -> orders. Selection (click / box / Tab), move orders with
## order modes, target marking, support tool targeting, evacuation, pause.

var selection: Array = []      # Squad / Vehicle
var sel_wounded: Array = []    # Soldier
var mode = "move"             # move / assault / hold
var tool = ""                 # "" / mortar / fpv / smoke
var hover_point = null
var hover_obj = null
var drag_start = Vector2.ZERO
var dragging = false
var lmb_down = false
var box_rect = Rect2()
var order_markers: Array = []
var _dbl := false
var _ctrl := false
var _alt := false  # {pos, t, kind}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func cam() -> Camera3D:
	return get_viewport().get_camera_3d()


func primary_selection():
	return selection[0] if selection.size() > 0 else null


func reveal(e, secs: float, src: String = Loc.t("бійці"), quality: float = 1.0) -> void:
	if W.intel:
		W.intel.observe(e, src, quality)
	if e is Vehicle:
		e.revealed = maxf(e.revealed, secs)
		if not e.ever_seen:
			e.ever_seen = true
			Events.msg(Loc.t("Виявлено ворожу техніку: %s!") % e.vname, "alert")
			if W.blog:
				W.blog.add("contact", Loc.t("Виявлено ворожу техніку: %s") % e.vname, e.global_position)
		return
	if e is Soldier:
		var was: bool = e.revealed > 0.0
		e.revealed = maxf(e.revealed, secs)
		e.last_seen_pos = e.global_position
		e.last_seen_t = W.time
		if not e.ever_seen:
			e.ever_seen = true
			Events.enemy_spotted.emit(e)
		if not was and e.bunker != null and not e.bunker.ever_seen:
			e.bunker.ever_seen = true


# ------------------------------------------------------------------ picking
func screen_of(p: Vector3):
	var c = cam()
	if c == null or c.is_position_behind(p):
		return null
	return c.unproject_position(p)


func ground_at(mp: Vector2):
	var c = cam()
	if c == null or W.grid == null:
		return null
	return W.grid.raycast(c.project_ray_origin(mp), c.project_ray_normal(mp))


func pick(mp: Vector2, want_enemy: bool = false):
	var best = null
	var best_d = 22.0
	for u in W.units:
		if u.health == Soldier.H.DEAD or u.evacuated or u.vehicle != null or u.on_board:
			continue
		if u.side == 1 and (not want_enemy or not u.model.visible):
			continue
		if u.side == 0 and want_enemy:
			continue
		var sp = screen_of(u.global_position + Vector3(0, 1.0, 0))
		if sp == null:
			continue
		var d: float = (sp as Vector2).distance_to(mp)
		if d < best_d:
			best_d = d
			best = u
	for v in W.vehicles:
		if v.offmap or v.state == "destroyed":
			continue
		if (v.side == 1) != want_enemy:
			continue
		if v.side == 1 and not v.visible:
			continue
		var sp = screen_of(v.global_position + Vector3(0, 1.2, 0))
		if sp == null:
			continue
		var edge = screen_of(v.global_position + Vector3(0, 1.2, 0) + cam().global_basis.x * 3.0)
		var rad = 30.0
		if edge != null:
			rad = maxf(22.0, (edge as Vector2).distance_to(sp))
		var d: float = (sp as Vector2).distance_to(mp)
		if d < rad and d < best_d + 10.0:
			best_d = d
			best = v
	if want_enemy and W.ew:
		for st in W.ew.stations:
			if st.destroyed or not st.ever_seen:
				continue
			var ssp = screen_of(st.global_position + Vector3(0, 1.5, 0))
			if ssp != null and (ssp as Vector2).distance_to(mp) < 28.0 and (ssp as Vector2).distance_to(mp) < best_d + 8.0:
				best_d = (ssp as Vector2).distance_to(mp)
				best = st
	if want_enemy:
		for b in W.bunkers:
			if b.destroyed or not b.ever_seen:
				continue
			var sp = screen_of(b.global_position + Vector3(0, 1.0, 0))
			if sp == null:
				continue
			var d: float = (sp as Vector2).distance_to(mp)
			if d < 30.0 and d < best_d + 8.0:
				best_d = d
				best = b
	return best


# ------------------------------------------------------------------ input
var rmb_down := false
var rmb_start := Vector2.ZERO
var rmb_drag := false
var rline_start = null   # ground point where a right-drag (line order) began


func _unhandled_input(event: InputEvent) -> void:
	if W.mission == null or not (W.mission.phase == MissionManager.Phase.DEPLOY or W.mission.phase == MissionManager.Phase.COMBAT):
		return
	if W.ew and W.ew.drone_down:
		if event is InputEventKey and event.pressed and not event.echo and Game.action_for(event.physical_keycode) == "pause":
			toggle_pause()
		return   # no video, no target designation
	if event is InputEventMouseMotion:
		_motion(event.position)
	elif event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				lmb_down = true
				dragging = false
				drag_start = mb.position
				_dbl = mb.double_click
				_ctrl = mb.ctrl_pressed
				_alt = mb.alt_pressed
			elif lmb_down:
				_lmb_release(mb.position, mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				rmb_down = true
				rmb_drag = false
				rmb_start = mb.position
				rline_start = ground_at(mb.position) if not selection.is_empty() and tool == "" else null
			elif rmb_down:
				_rmb_release(mb.position, mb.shift_pressed)
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event.physical_keycode, event.shift_pressed)


## Drags keep working when the mouse passes over a panel or the minimap.
func _input(event: InputEvent) -> void:
	if not (lmb_down or rmb_down):
		return
	if event is InputEventMouseMotion:
		_motion(event.position)
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and lmb_down and dragging:
			_lmb_release(event.position, event.shift_pressed)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and rmb_down and rmb_drag:
			_rmb_release(event.position, event.shift_pressed)
			get_viewport().set_input_as_handled()


func _motion(mp: Vector2) -> void:
	hover_point = ground_at(mp)
	if lmb_down and drag_start.distance_to(mp) > 8.0:
		dragging = true
		box_rect = Rect2(drag_start, Vector2.ZERO).expand(mp)
	if rmb_down and rmb_start.distance_to(mp) > 12.0 and rline_start != null:
		rmb_drag = true


func _lmb_release(mp: Vector2, shift: bool) -> void:
	lmb_down = false
	if dragging:
		dragging = false
		_box_select(box_rect, shift, _alt)
		box_rect = Rect2()
	else:
		_left_click_rts(mp, shift)


func _rmb_release(mp: Vector2, shift: bool) -> void:
	rmb_down = false
	if rmb_drag and rline_start != null:
		var end = ground_at(mp)
		if end != null:
			_order_line(rline_start, end)
			_after_order(shift)
	else:
		_right_click_rts(mp, shift)
	rmb_drag = false
	rline_start = null


## RTS scheme, left button: select (a support tool is applied with it too).
func _left_click_rts(mp: Vector2, shift: bool) -> void:
	if tool != "":
		_apply_tool(mp)
		return
	var obj = pick(mp)
	if obj != null and ((obj is Soldier and obj.side == 0) or (obj is Vehicle and obj.side == 0)):
		_left_click(mp, shift)   # the same selection rules as before
		return
	if not shift:
		clear_selection()


## RTS scheme, right button: an order to the selection — the ground (in the
## current order mode), an enemy (mark it and fire at it), or cancel a tool.
func _right_click_rts(mp: Vector2, shift: bool) -> void:
	if tool != "":
		set_tool("")
		return
	var e = pick(mp, true)
	if e != null:
		e.marked = not e.marked if selection.is_empty() else true
		W.sfx.ui("click")
		if e.marked:
			Events.msg(Loc.t("Ціль позначено: %s") % _target_name(e), "warn")
			for o in selection:
				if o is Vehicle and o.state != "destroyed":
					o.target = e
		return
	if selection.is_empty():
		return
	var gp = ground_at(mp)
	if gp == null:
		return
	_order_at(gp)
	_after_order(shift)


## One-shot order modes: after an order the mode returns to «рух» (Shift or
## the setting keep it).
func _after_order(shift: bool) -> void:
	if shift or bool(Game.settings.get("sticky_mode", false)):
		return
	if mode != "move":
		mode = "move"
		Events.selection_changed.emit()


func _key(k: int, _shift: bool) -> void:
	match Game.action_for(k):
		"move":
			set_mode("move")
		"assault":
			set_mode("assault")
		"hold":
			set_mode("hold")
		"clear":
			set_mode("clear")
		"suppress":
			set_mode("suppress")
		"face":
			cmd_face_cycle()
		"follow_veh":
			cmd_follow_vehicle()
		"bound":
			set_mode("bound")
		"retreat":
			cmd_retreat()
		"mount":
			cmd_mount_toggle()
		"smoke":
			cmd_smoke()
		"evac":
			cmd_evac()
		"resupply":
			cmd_resupply()
		"mortar":
			set_tool("mortar")
		"fpv":
			set_tool("fpv")
		"smoke_barrage":
			set_tool("smoke")
		"next":
			cycle_selection()
		"pause":
			toggle_pause()
	match k:
		KEY_BRACKETRIGHT, KEY_EQUAL:
			set_speed(2.0)
		KEY_BRACKETLEFT, KEY_MINUS:
			set_speed(1.0)
		KEY_ESCAPE:
			if tool != "":
				set_tool("")
			else:
				clear_selection()


func _left_click(mp: Vector2, shift: bool) -> void:
	if tool != "":
		_apply_tool(mp)
		return
	var obj = pick(mp)
	if obj != null:
		W.sfx.ui("click")
		if obj is Soldier and obj.side == 0:
			if obj.health == Soldier.H.INCAP or (obj.health == Soldier.H.WOUNDED and not shift and obj.role == "crew_medic"):
				sel_wounded = [obj]
				_set_selection([])
				return
			if obj.role == "crew_medic":
				return
			if obj.health == Soldier.H.WOUNDED and Input.is_physical_key_pressed(KEY_ALT):
				sel_wounded = [obj]
				_set_selection([])
				return
			if _ctrl or _dbl:
				_toggle_or_set(obj, shift)   # one soldier, not the whole squad
				return
			var sq = obj.squad
			_toggle_or_set(sq, shift)
			return
		if obj is Vehicle and obj.side == 0:
			if obj.is_medevac:
				_set_selection([obj])
				return
			_toggle_or_set(obj, shift)
			return
	var gp = ground_at(mp)
	if gp == null:
		return
	if selection.is_empty():
		return
	_order_at(gp)


func _toggle_or_set(o, shift: bool) -> void:
	sel_wounded.clear()
	if shift:
		var s = selection.duplicate()
		if s.has(o):
			s.erase(o)
		else:
			s.append(o)
		_set_selection(s)
	else:
		_set_selection([o])


func _target_name(e) -> String:
	if e is Soldier:
		return String(e.rdata["name"]).to_lower()
	if e is Bunker:
		return e.title.to_lower()
	if e is EwStation:
		return Loc.t("станція РЕБ")
	if e is Vehicle:
		return e.vname
	return Loc.t("ціль")


func _box_select(r: Rect2, shift: bool, individuals: bool = false) -> void:
	var s: Array = selection.duplicate() if shift else []
	if individuals:
		for u in W.units:
			if u.side != 0 or not u.is_active() or u.role == "crew_medic":
				continue
			var up = screen_of(u.global_position + Vector3(0, 1, 0))
			if up != null and r.has_point(up) and not s.has(u):
				s.append(u)
		sel_wounded.clear()
		_set_selection(s)
		return
	for sq in W.squads:
		if sq.side != 0:
			continue
		for m in sq.active_members():
			var sp = screen_of(m.global_position + Vector3(0, 1, 0))
			if sp != null and r.has_point(sp):
				if not s.has(sq):
					s.append(sq)
				break
	for v in W.vehicles:
		if v.side != 0 or v.offmap or v.state == "destroyed" or v.is_medevac:
			continue
		var sp = screen_of(v.global_position + Vector3(0, 1, 0))
		if sp != null and r.has_point(sp) and not s.has(v):
			s.append(v)
	sel_wounded.clear()
	_set_selection(s)


func _set_selection(s: Array) -> void:
	for o in selection:
		_mark_selected(o, false)
	selection = s
	for o in selection:
		_mark_selected(o, true)
	Events.selection_changed.emit()


func _mark_selected(o, on: bool) -> void:
	if not is_instance_valid(o):
		return
	if o is Squad:
		o.selected = on
		for m in o.members:
			m.selected = on
	elif o is Vehicle or o is Soldier:
		o.selected = on


func clear_selection() -> void:
	sel_wounded.clear()
	_set_selection([])


func cycle_selection() -> void:
	var all: Array = []
	for sq in W.squads:
		if sq.side == 0 and (sq.active_count() > 0 or sq.mounted):
			all.append(sq)
	for v in W.vehicles:
		if v.side == 0 and not v.offmap and v.state != "destroyed" and not v.is_medevac:
			all.append(v)
	if all.is_empty():
		return
	var cur = primary_selection()
	var i = all.find(cur)
	var nxt = all[(i + 1) % all.size()]
	_set_selection([nxt])
	W.cam.follow = nxt
	W.sfx.ui("click")


func select_object(o) -> void:
	sel_wounded.clear()
	_set_selection([o])


# ------------------------------------------------------------------ orders
func set_mode(m: String) -> void:
	mode = m
	tool = ""
	W.sfx.ui("click")
	Events.selection_changed.emit()


## Selection split into "units": squads, vehicles and one group made of all
## individually selected soldiers.
func _order_units() -> Array:
	var units: Array = []
	var solos: Array = []
	for o in selection:
		if o is Soldier:
			solos.append(o)
		else:
			units.append(o)
	if not solos.is_empty():
		units.append(solos)
	return units


func _order_at(gp: Vector3) -> void:
	var units = _order_units()
	var n = units.size()
	var c = Vector3.ZERO
	for o in units:
		c += _center(o)
	c /= maxf(n, 1)
	var dir = gp - c
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.5 else Vector3(0, 0, -1)
	var right = Vector3(-dir.z, 0, dir.x)
	var i = 0
	for o in units:
		var off = right * (i - (n - 1) * 0.5) * 22.0
		var p: Vector3 = W.grid.clamp_in(gp + off, 3.0)
		_order_one(o, p, null)
		i += 1
	order_markers.append({"pos": gp, "t": 1.5, "kind": mode})
	W.sfx.ui("radio")


func _order_line(a: Vector3, b: Vector3) -> void:
	var units = _order_units()
	var n = units.size()
	var i = 0
	for o in units:
		var k0 = float(i) / n
		var k1 = float(i + 1) / n
		_order_one(o, a.lerp(b, k0), a.lerp(b, k1))
		i += 1
	order_markers.append({"pos": a.lerp(b, 0.5), "t": 1.5, "kind": mode})
	W.sfx.ui("radio")


func _order_one(o, p: Vector3, line_end) -> void:
	if o is Array:
		if mode == "suppress":
			for u in o:
				if u.is_active():
					u.squad.order_suppress(p)
					break
			return
		_order_soldiers(o, p, line_end)
	elif o is Squad:
		if o.active_count() == 0 and not o.mounted:
			return
		if mode == "suppress":
			o.order_suppress(p)
		else:
			o.issue_order(mode, p, line_end)
	elif o is Vehicle:
		if o.state == "destroyed":
			return
		if mode == "suppress":
			o.order_suppress(p)
			return
		if o.state == "immobile":
			Events.msg(Loc.t("%s знерухомлена — рух неможливий") % o.vname, "warn")
			return
		if mode == "assault":
			o.order_assault(p)
		else:
			o.order_move(p)


func _order_soldiers(list: Array, p: Vector3, line_end) -> void:
	var act: Array = []
	for u in list:
		if u.is_active():
			act.append(u)
	if act.is_empty():
		return
	var tp = W.grid.snap_to_trench(p) if mode == "clear" else null
	if tp != null:
		p = tp
		for u in act:
			u.solo = "clear"
		Squad.clear_column(act, p)
		return
	var c = _center(act)
	var dir = p - c
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.5 else Vector3(0, 0, -1)
	var slots: Array = act[0].squad.formation_slots(p, dir, act.size(), line_end, 3.2)
	var taken: Array = []
	for i in act.size():
		var u = act[i]
		var sp: Vector3 = slots[i]
		if mode == "hold":
			sp = W.grid.find_cover(sp, 4.0, u.squad.nearest_threat(sp), taken)
			taken.append(sp)
		u.solo = mode
		u.slot = sp
		u.can_advance = true
		u.pinned_t = 0.0
		u.broken = false if u.morale > 20.0 else u.broken
		u.move_to(sp, true)


func _center(o) -> Vector3:
	if o is Array:
		var c = Vector3.ZERO
		for u in o:
			c += u.global_position
		return c / maxf(o.size(), 1)
	if o is Squad:
		return o.center()
	return o.global_position


## Vehicles: front / side / rear to the enemy (cycles; "" = free).
func cmd_face(m: String) -> void:
	for o in selection:
		if o is Vehicle and o.state != "destroyed":
			o.set_face(m)
	W.sfx.ui("click")
	Events.selection_changed.emit()


func cmd_face_cycle() -> void:
	var cur := ""
	for o in selection:
		if o is Vehicle:
			cur = o.face_mode
			break
	var order := ["", "front", "side", "rear"]
	cmd_face(order[(order.find(cur) + 1) % order.size()])


## Selected squads walk behind a vehicle in two files: the selected vehicle,
## else the squad's own one, else the nearest.
func cmd_follow_vehicle() -> void:
	var veh = null
	for o in selection:
		if o is Vehicle and o.state != "destroyed" and not o.is_medevac:
			veh = o
			break
	var n := 0
	for o in selection:
		var sq = o if o is Squad else (o.squad if o is Soldier else null)
		if sq == null or sq.mounted:
			continue
		var v = veh
		if v == null and sq.vehicle != null and is_instance_valid(sq.vehicle) and sq.vehicle.state != "destroyed" and not sq.vehicle.offmap:
			v = sq.vehicle
		if v == null:
			var bd := INF
			for vv in W.vehicles:
				if vv.side == 0 and vv.state != "destroyed" and not vv.offmap and not vv.is_medevac:
					var d: float = vv.global_position.distance_to(sq.center())
					if d < bd:
						bd = d
						v = vv
		if v != null:
			sq.follow_vehicle(v)
			n += 1
	if n == 0:
		Events.msg(Loc.t("Виберіть відділення (і, за бажання, машину), за якою йти."), "warn")
	W.sfx.ui("radio")


## What the next order would do, for the preview: per unit its centre and
## the points its men / it would take. line_end = right-drag line.
func preview(gp: Vector3, line_end = null) -> Array:
	var out: Array = []
	var units = _order_units()
	var n: int = units.size()
	if n == 0:
		return out
	if line_end != null:
		for i in n:
			var a: Vector3 = gp.lerp(line_end, float(i) / n)
			var b: Vector3 = gp.lerp(line_end, float(i + 1) / n)
			out.append(_preview_one(units[i], a, b))
		return out
	var c := Vector3.ZERO
	for o in units:
		c += _center(o)
	c /= maxf(n, 1)
	var dir := gp - c
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.5 else Vector3(0, 0, -1)
	var right := Vector3(-dir.z, 0, dir.x)
	for i in n:
		var p: Vector3 = W.grid.clamp_in(gp + right * (i - (n - 1) * 0.5) * 22.0, 3.0)
		out.append(_preview_one(units[i], p, null))
	return out


func _preview_one(o, p: Vector3, line_end) -> Dictionary:
	var from := _center(o)
	var d := {"from": from, "to": p, "slots": [], "vehicle": o is Vehicle}
	if o is Vehicle:
		d["slots"] = [W.grid.free_point(p, true)]
		return d
	var list: Array = o.active_members() if o is Squad else o
	if list.is_empty() or (o is Squad and o.mounted):
		d["slots"] = [p]
		return d
	if mode == "suppress":
		return d
	var b = Buildings.at(p)
	if b != null:
		# the preview runs every frame: facing only, the line-of-sight check is
		# left to the order itself
		var sq = list[0].squad
		for w in Buildings.pick_posts(b, list.size(), [], sq._look_dir_point(b) if sq else b["center"]):
			d["slots"].append(w["post"])
		return d
	var dir := p - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.5 else Vector3(0, 0, -1)
	var sq = o if o is Squad else list[0].squad
	d["slots"] = sq.formation_slots(p, dir, list.size(), line_end, 3.6)
	return d


func cmd_retreat() -> void:
	for o in selection:
		if o is Squad:
			o.issue_order("retreat", o.rally)
		elif o is Vehicle and o.state != "destroyed":
			o.order_move(W.mission.def.rally_point + Vector3(randf_range(-10, 10), 0, 4))
		elif o is Soldier and o.is_active():
			o.solo = "retreat"
			o.slot = W.grid.free_point(o.squad.rally + Vector3(randf_range(-6, 6), 0, randf_range(-3, 3)))
			o.move_to(o.slot, true)
	if not selection.is_empty():
		Events.msg(Loc.t("Наказ на відхід до району збору."), "warn")
		W.sfx.ui("radio")


func cmd_mount_toggle() -> void:
	for o in selection:
		if o is Soldier:
			var v = o.squad.vehicle
			if v != null and is_instance_valid(v) and v.state != "destroyed" and o.is_active():
				o.solo = "mount"
				o.slot = v.rear_point()
				o.move_to(o.slot, true)
			continue
		var sq = o if o is Squad else (o.squad if o is Vehicle else null)
		if sq == null:
			continue
		if sq.mounted and sq.vehicle != null:
			sq.vehicle.dismount()
		elif sq.vehicle != null and is_instance_valid(sq.vehicle) and sq.vehicle.state != "destroyed":
			sq.order_mount()
			Events.msg(Loc.t("%s: посадка в %s") % [sq.short, sq.vehicle.vname], "info")
		else:
			Events.msg(Loc.t("%s: немає транспорту") % sq.short, "warn")
	W.sfx.ui("click")


func cmd_smoke() -> void:
	for o in selection:
		if o is Vehicle and o.state != "destroyed":
			if o.smoke_charges > 0:
				o.smoke_charges -= 1
				W.combat.deploy_smoke(o.global_position + o.forward() * 5.0, 8.0, 30.0)
				o.radio("vehicle", Loc.t("поставлено димову завісу!"), "info")
			else:
				Events.msg(Loc.t("%s: димових гранат немає") % o.vname, "warn")
		if o is Squad:
			if o.throw_smoke():
				Events.msg(Loc.t("%s: ставимо димову завісу") % o.short, "info")
			else:
				Events.msg(Loc.t("%s: димові гранати відсутні") % o.short, "warn")
		elif o is Soldier and o.is_active() and o.smokes > 0 and o.action == "":
			var tp = o.squad.nearest_threat(o.global_position)
			var dir = Vector3(0, 0, -1)
			if tp != null:
				dir = ((tp as Vector3) - o.global_position)
				dir.y = 0.0
				dir = dir.normalized()
			o.smokes -= 1
			o.start_action("smoke", 1.1, o.global_position + dir * 12.0)


func cmd_evac() -> void:
	var targets: Array = []
	if not sel_wounded.is_empty():
		targets = sel_wounded.duplicate()
	else:
		for o in selection:
			if o is Squad:
				for m in o.members:
					if W.evac.is_valid_patient(m):
						targets.append(m)
			elif o is Soldier and W.evac.is_valid_patient(o):
				targets.append(o)
	if targets.is_empty():
		Events.msg(Loc.t("Немає поранених для евакуації у вибраних підрозділах"), "info")
		return
	for u in targets:
		W.evac.request(u)
	W.sfx.ui("radio")


## Selected squads walk to the nearest of our vehicles with a stock and top
## up their magazines and grenades (aboard: from their own vehicle).
func cmd_resupply() -> void:
	var any := false
	var none := false
	for o in selection:
		var sq = o if o is Squad else (o.squad if o is Vehicle else null)
		if sq == null or not (sq is Squad) or sq.side != 0:
			continue
		if sq.order_resupply():
			any = true
		else:
			none = true
	if none and not any:
		Events.msg(Loc.t("Немає нашої машини з боєкомплектом поблизу"), "warn")
		return
	if any:
		W.sfx.ui("radio")


func set_tool(t: String) -> void:
	if t == "":
		tool = ""
		Events.selection_changed.emit()
		return
	if int(W.mission.support.get(t, 0)) <= 0:
		Events.msg(Loc.t("Засіб недоступний (вичерпано або не залучено)"), "warn")
		return
	tool = t
	W.sfx.ui("click")
	Events.selection_changed.emit()


func _apply_tool(mp: Vector2) -> void:
	var gp = ground_at(mp)
	match tool:
		"mortar":
			if gp == null:
				return
			if W.mission.use_support("mortar"):
				var eta: float = W.combat.mortar_strike(gp, 4, 11.0, 0)
				Events.msg(Loc.t("Мінометний розрахунок: заявку прийнято, перша міна ~%d с. Розкид великий!") % int(eta), "info")
				if W.blog:
					W.blog.add("support", Loc.t("Мінометний наліт"), gp)
				order_markers.append({"pos": gp, "t": 6.0, "kind": "mortar"})
		"smoke":
			if gp == null:
				return
			if W.mission.use_support("smoke"):
				W.combat.smoke_barrage(gp)
				Events.msg(Loc.t("Димова завіса: заявку прийнято"), "info")
				if W.blog:
					W.blog.add("support", Loc.t("Димова завіса"), gp)
				order_markers.append({"pos": gp, "t": 4.0, "kind": "smoke"})
		"fpv":
			var e = pick(mp, true)
			var tgt = e if e != null else gp
			if tgt == null:
				return
			if W.mission.use_support("fpv"):
				var half: float = W.mission.def.size * 0.5
				var start: Vector3 = Vector3(randf_range(-30, 30), 25, half + 45)
				W.combat.fpv_strike(tgt, start)
				if W.blog:
					W.blog.add("support", Loc.t("FPV-удар"), tgt if tgt is Vector3 else tgt.global_position)
				if e != null:
					e.marked = true
	W.sfx.ui("radio")
	tool = ""
	Events.selection_changed.emit()


func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	Events.msg(Loc.t("ПАУЗА — можна віддавати накази") if get_tree().paused else Loc.t("Продовження"), "info")


func set_speed(s: float) -> void:
	Engine.time_scale = s
	Events.msg(Loc.t("Швидкість x%d") % int(s), "info")


func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("command", t0)


func _process_body(delta: float) -> void:
	var i = order_markers.size() - 1
	while i >= 0:
		order_markers[i]["t"] -= delta
		if order_markers[i]["t"] <= 0.0:
			order_markers.remove_at(i)
		i -= 1
	# drop dead selections
	var changed = false
	for o in selection.duplicate():
		if o is Squad and o.active_count() == 0 and not o.mounted:
			selection.erase(o)
			changed = true
		elif o is Vehicle and (o.state == "destroyed" or o.offmap):
			selection.erase(o)
			changed = true
		elif o is Soldier and not o.is_active():
			o.selected = false
			selection.erase(o)
			changed = true
	for u in sel_wounded.duplicate():
		if u.health == Soldier.H.DEAD or u.evacuated or u.on_board:
			sel_wounded.erase(u)
			changed = true
	if changed:
		Events.selection_changed.emit()
