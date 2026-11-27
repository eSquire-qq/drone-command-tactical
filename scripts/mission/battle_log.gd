class_name BattleLog
extends Node
## After Action Review data: a timeline of key events, the routes of our
## squads, where men went down, evacuations, drone losses, and the decision
## analysis at the end of the mission. Only what the commander could know is
## kept (contacts come from IntelSystem, not from the true enemy positions).

const MAX_EVENTS := 400
const ROUTE_STEP := 8.0          # s between route samples
const PINNED_LONG := 60.0        # s pinned in one place before the review flags it

# kind -> colour key used by the review screen
const KINDS := ["info", "contact", "order", "support", "loss", "enemy", "evac", "drone", "end"]

var events: Array = []           # {t, kind, text, pos}
var routes := {}                 # squad short -> PackedVector3Array
var casualties: Array = []       # {t, pos, kia: bool, name, squad, cause}
var evacs: Array = []            # {t, pos, n}
var contact_marks := {}          # enemy -> {pos, kind, confirmed}
var drone_losses: Array = []     # {t, pos, crit_time}
var orders: Array = []           # {t, squad, kind, pos, known}
var down_t := {}                 # soldier -> time he went down (incap)
var evac_req_t := {}             # soldier -> time evacuation was requested
var pinned := {}                 # squad -> {since, pos, worst}
var crit_time := 0.0             # s the drone spent in the critical EW zone (since last loss)
var degraded_time := 0.0
var _route_t := 0.0
var _enemy_down_batch := 0
var _enemy_down_t := -99.0
var _first_contact := false


func _ready() -> void:
	Events.unit_state_changed.connect(_on_state)
	Events.phase_changed.connect(func(p): if p == MissionManager.Phase.COMBAT: add("info", Loc.t("Висадку завершено, підрозділи на вихідних рубежах")))


func now() -> float:
	return W.mission.t if W.mission else 0.0


func add(kind: String, text: String, pos = null) -> void:
	if events.size() >= MAX_EVENTS:
		return
	events.append({"t": now(), "kind": kind, "text": text, "pos": pos})


# ------------------------------------------------------------------ hooks
func contact(e, pos: Vector3, kind: String, confirmed: bool, src: String) -> void:
	var m: Dictionary = contact_marks.get(e, {})
	if m.is_empty() and not _first_contact:
		_first_contact = true
		add("contact", Loc.t("Перший контакт: %s (%s)") % [Loc.t(kind), src], pos)
	m["pos"] = pos
	m["kind"] = kind
	m["confirmed"] = m.get("confirmed", false) or confirmed
	contact_marks[e] = m


func order(sq, kind: String, pos: Vector3) -> void:
	# the same order repeated (re-clicks, bot re-issues) is one decision
	for i in range(orders.size() - 1, -1, -1):
		var o: Dictionary = orders[i]
		if now() - float(o["t"]) > 30.0:
			break
		if o["squad"] == sq.short and o["kind"] == kind and (o["pos"] as Vector3).distance_to(pos) < 20.0:
			return
	var known := 0
	if W.intel:
		for e in W.intel.contacts.keys():
			var c: Dictionary = W.intel.contacts[e]
			if int(c["status"]) <= IntelSystem.S.LAST_KNOWN and (c["pos"] as Vector3).distance_to(pos) < 60.0:
				known += 1
	orders.append({"t": now(), "squad": sq.short, "kind": kind, "pos": pos, "known": known})
	var names := {"assault": Loc.t("штурм"), "clear": Loc.t("зачистку"), "retreat": Loc.t("відхід")}
	add("order", Loc.t("%s: наказ на %s (розвідданих у районі: %d)") % [sq.short, names.get(kind, kind), known], pos)


func evac_requested(u) -> void:
	if not evac_req_t.has(u):
		evac_req_t[u] = now()


func evacuated(n: int, pos: Vector3) -> void:
	evacs.append({"t": now(), "pos": pos, "n": n})
	add("evac", Loc.t("Евакуйовано %d поранених") % n, pos)


func drone_lost(pos: Vector3) -> void:
	drone_losses.append({"t": now(), "pos": pos, "crit_time": crit_time})
	add("drone", Loc.t("Дрон втрачено (РЕБ)") if crit_time < 10.0 else Loc.t("Дрон втрачено (РЕБ), у критичній зоні %d с") % int(crit_time), pos)
	crit_time = 0.0


func _on_state(u, old: int, h: int) -> void:
	if W.mission == null or W.mission.phase == MissionManager.Phase.ENDED:
		return
	if u.side == 0:
		if h >= Soldier.H.INCAP and old < Soldier.H.INCAP:
			down_t[u] = now()
			var kia: bool = h == Soldier.H.DEAD
			casualties.append({"t": now(), "pos": u.global_position, "kia": kia, "name": u.display_name(), "squad": u.squad.short if u.squad else "", "cause": u.down_by})
			add("loss", "%s: %s — %s" % [u.squad.short if u.squad else "", Loc.t("загинув") if kia else Loc.t("важко поранений"), u.display_name()], u.global_position)
		elif h == Soldier.H.DEAD and old == Soldier.H.INCAP:
			for c in casualties:
				if c["name"] == u.display_name() and not c["kia"]:
					c["kia"] = true
					c["died_t"] = now()
			add("loss", Loc.t("%s помер від ран") % u.display_name(), u.global_position)
	elif h >= Soldier.H.INCAP and old < Soldier.H.INCAP:
		# aggregate enemy losses into one line per 10 s
		if now() - _enemy_down_t > 10.0 or _enemy_down_batch == 0:
			_enemy_down_t = now()
			_enemy_down_batch = 1
			add("enemy", Loc.t("Противника уражено"), u.global_position)
		else:
			_enemy_down_batch += 1
			var ev: Dictionary = events[events.size() - 1] if not events.is_empty() else {}
			if ev.get("kind", "") == "enemy":
				ev["text"] = Loc.t("Противника уражено: %d") % _enemy_down_batch


func _process(delta: float) -> void:
	if W.mission == null or not W.running():
		return
	if W.ew and not W.ew.drone_down:
		if W.ew.link < EwSystem.CRITICAL:
			crit_time += delta
		if W.ew.link < EwSystem.DEGRADED:
			degraded_time += delta
	_route_t -= delta
	if _route_t > 0.0:
		return
	_route_t = ROUTE_STEP
	for sq in W.mission.friendly_squads:
		if sq.active_count() <= 0 or sq.mounted:
			continue
		var c: Vector3 = sq.center()
		var r: PackedVector3Array = routes.get(sq.short, PackedVector3Array())
		if r.is_empty() or r[r.size() - 1].distance_to(c) > 3.0:
			r.append(c)
			routes[sq.short] = r
		# pinned in one place?
		var p: Dictionary = pinned.get(sq, {})
		if sq.avg_level() >= 2.0:
			if p.is_empty() or (p["pos"] as Vector3).distance_to(c) > 6.0:
				p = {"since": now(), "pos": c, "worst": p.get("worst", 0.0)}
			p["worst"] = maxf(float(p["worst"]), now() - float(p["since"]))
		elif not p.is_empty():
			p["since"] = now()
			p["pos"] = c
		pinned[sq] = p


# ------------------------------------------------------------------ review
## Decision analysis: [{good: bool, text}] — judged on what the commander knew
## when he decided, not only on the outcome.
func analyze(r: Dictionary) -> Array:
	var out: Array = []
	var good_assaults := {}
	# assaults and recon
	for o in orders:
		if o["kind"] != "assault" and o["kind"] != "clear":
			continue
		var lost := 0
		for c in casualties:
			if c["squad"] == o["squad"] and float(c["t"]) >= float(o["t"]) and float(c["t"]) - float(o["t"]) < 90.0:
				lost += 1
		if int(o["known"]) == 0 and lost >= 2:
			out.append({"good": false, "text": Loc.t("%s о %s: штурм розпочато без розвідданих у районі цілі — за 90 с вибуло %d бійців. Спершу варто було оглянути позицію дроном.") % [o["squad"], UIK.mmss(o["t"]), lost]})
		elif int(o["known"]) >= 2 and lost <= 1:
			var g: Dictionary = good_assaults.get(o["squad"], {"n": 0, "lost": 0, "t": o["t"]})
			g["n"] += 1
			g["lost"] += lost
			good_assaults[o["squad"]] = g
	for k in good_assaults.keys():
		var g: Dictionary = good_assaults[k]
		if int(g["n"]) == 1:
			out.append({"good": true, "text": Loc.t("%s о %s: штурм за розвідданими, втрати %d.") % [k, UIK.mmss(g["t"]), g["lost"]]})
		else:
			out.append({"good": true, "text": Loc.t("%s: %d штурмових дій за розвідданими (перша о %s), втрати %d.") % [k, g["n"], UIK.mmss(g["t"]), g["lost"]]})
	# drone
	for d in drone_losses:
		if float(d["crit_time"]) >= 10.0:
			out.append({"good": false, "text": Loc.t("Дрон втрачено о %s після %d с у критичній зоні РЕБ — спостереження варто вести здалеку, з оптичним зумом.") % [UIK.mmss(d["t"]), int(d["crit_time"])]})
		else:
			out.append({"good": false, "text": Loc.t("Дрон втрачено о %s майже одразу після входу в зону сильних перешкод — тримайте запас дистанції від відомих станцій РЕБ, стежте за індикатором зв'язку.") % UIK.mmss(d["t"])})
	if drone_losses.is_empty() and degraded_time < 30.0:
		out.append({"good": true, "text": Loc.t("Дрон тримався поза зоною сильних перешкод РЕБ (%d с у зоні погіршеного зв'язку).") % int(degraded_time)})
	# pinned without changing position
	for sq in pinned.keys():
		var w: float = float(pinned[sq].get("worst", 0.0))
		if w >= PINNED_LONG:
			out.append({"good": false, "text": Loc.t("%s ~%d с лишалось притиснутим на одному місці — допомогли б дим, мінометний вогонь або зміна позиції.") % [sq.short, int(w)]})
	# evacuation
	var delays: Array = []
	var bled := 0
	for u in down_t.keys():
		if evac_req_t.has(u):
			delays.append(float(evac_req_t[u]) - float(down_t[u]))
		elif is_instance_valid(u) and u.health == Soldier.H.DEAD and u.down_by != "" :
			for c in casualties:
				if c["name"] == u.display_name() and c.has("died_t"):
					bled += 1
	if not delays.is_empty():
		var avg := 0.0
		for d in delays:
			avg += d
		avg /= delays.size()
		if avg > 90.0:
			out.append({"good": false, "text": Loc.t("Евакуацію викликали в середньому через %d с після поранення — це скорочує шанси вижити.") % int(avg)})
		else:
			out.append({"good": true, "text": Loc.t("Евакуацію викликали швидко (у середньому через %d с).") % int(avg)})
	if bled > 0:
		out.append({"good": false, "text": Loc.t("%d поранених померли від ран, не дочекавшись евакуації.") % bled})
	# friendly fire
	var ff := 0
	for c in casualties:
		if String(c["cause"]) == "своїми":
			ff += 1
	if ff > 0:
		out.append({"good": false, "text": Loc.t("%d бійців уражено власним вогнем — перевіряйте положення своїх перед мінометним налітом.") % ff})
	# unused support while pinned
	var any_pinned := false
	for sq in pinned.keys():
		if float(pinned[sq].get("worst", 0.0)) >= 30.0:
			any_pinned = true
	var su: Dictionary = r.get("support_left", {})
	var left := int(su.get("mortar", 0)) + int(su.get("smoke", 0))
	if any_pinned and left > 0:
		out.append({"good": false, "text": Loc.t("Відділення були притиснуті, а міномет / дим лишилися невикористаними (%d).") % left})
	if out.is_empty():
		out.append({"good": true, "text": Loc.t("Суттєвих помилок не виявлено.")})
	return out
