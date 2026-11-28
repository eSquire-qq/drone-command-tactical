class_name Campaign
extends RefCounted
## Campaign: a sequence of missions fought by ONE persistent unit.
## * Personnel carry over: names, roles, experience, ranks, wounds, deaths.
## * Killed soldiers are gone for good; evacuated wounded miss the next
##   mission; casualties left on a lost field are missing in action.
## * Vehicles lost in battle leave the motor pool.
## * Supply points (earned by results) buy support assets and recruits.
## Saved to user://campaign.json after every change.

const SAVE_PATH_REAL := "user://campaign.json"
const SAVE_PATH_TEST := "user://campaign_autotest.json"
var SAVE_PATH: String = SAVE_PATH_TEST if "--autotest" in OS.get_cmdline_user_args() else SAVE_PATH_REAL
const NAME_UK := "Операція «Світанок»"
static var NAME = NAME_UK   # the current language (Loc.localize_all)
const RECRUIT_COST := 15
## Experience matters everywhere: accuracy (skill), steadiness under fire
## (morale, supp = suppression taken), toughness (hp, survive = lower chance a
## disabling hit kills), drill (reload, speed) and trench fighting (cqb =
## time spent at a corner, cqb_nade = chance to grenade an unknown corner,
## close = extra accuracy at point-blank range).
const RANKS_UK := [
	{"xp": 0, "name": "Новобранець", "short": "НБ", "skill": -0.05, "morale": -5.0, "hp": 0.0, "survive": 0.0,
		"supp": 1.15, "reload": 1.15, "speed": 0.97, "cqb": 1.3, "cqb_nade": 0.35, "close": 0.0, "grit": 0.92, "disc": 0.9, "recover": 0.9},
	{"xp": 2, "name": "Солдат", "short": "СЛ", "skill": 0.0, "morale": 0.0, "hp": 0.0, "survive": 0.0,
		"supp": 1.0, "reload": 1.0, "speed": 1.0, "cqb": 1.0, "cqb_nade": 0.45, "close": 0.0, "grit": 1.0, "disc": 1.0, "recover": 1.0},
	{"xp": 5, "name": "Досвідчений", "short": "ДС", "skill": 0.08, "morale": 6.0, "hp": 10.0, "survive": 0.05,
		"supp": 0.87, "reload": 0.88, "speed": 1.03, "cqb": 0.8, "cqb_nade": 0.6, "close": 0.1, "grit": 1.07, "disc": 1.08, "recover": 1.1},
	{"xp": 9, "name": "Ветеран", "short": "ВТ", "skill": 0.16, "morale": 12.0, "hp": 20.0, "survive": 0.1,
		"supp": 0.75, "reload": 0.78, "speed": 1.06, "cqb": 0.6, "cqb_nade": 0.75, "close": 0.2, "grit": 1.15, "disc": 1.15, "recover": 1.22},
]
static var RANKS = RANKS_UK   # the current language (Loc.localize_all)

var active := false
var step := 0                 # index into Game.CAMPAIGN_STEPS of the next mission
var supply := 0
var units: Array = []         # {id, kind, name, short, members:[soldier ids]}
var soldiers := {}            # id -> {id, name, role, xp, missions, kills, status, recover}
var pool := {}                # vehicle type -> count
var history: Array = []       # {step, title, result, score, kia, wia, evac, pows, vlost}
var failed := false
var difficulty := "normal"
var flags := {}               # campaign consequences; flags["next"] = what the last battle left for the next one
var repair := {}              # vehicle type -> count in repair (miss the next battle)
var load_error := ""
var _next_id := 1


# ------------------------------------------------------------------ lifecycle
func start_new(p_difficulty: String = "normal") -> void:
	difficulty = p_difficulty
	active = true
	failed = false
	step = 0
	supply = 420 + int(Game.DIFFICULTY[difficulty]["budget"]) / 2
	units.clear()
	soldiers.clear()
	history.clear()
	flags = {}
	repair = {}
	_next_id = 1
	pool = {"bmp2": 1, "bmp1": 1, "m113": 1, "medevac": 1}
	var used := {}
	_add_unit("rifle_squad", Loc.t("1-ше відділення"), Loc.t("В-1"), used)
	_add_unit("rifle_squad", Loc.t("2-ге відділення"), Loc.t("В-2"), used)
	_add_unit("assault_group", Loc.t("Штурмова група"), Loc.t("Ш-1"), used)
	save()


func abandon() -> void:
	active = false
	units.clear()
	soldiers.clear()
	history.clear()
	for p in [SAVE_PATH, SAVE_PATH + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _add_unit(kind: String, uname: String, short: String, used: Dictionary) -> void:
	var u := {"id": "u%d" % (units.size() + 1), "kind": kind, "name": uname, "short": short, "members": []}
	for r in Game.CATALOG[kind]["roles"]:
		var s := _new_soldier(r, used, randi_range(0, 3))
		u["members"].append(s["id"])
	units.append(u)


func _new_soldier(role: String, used: Dictionary, xp: int) -> Dictionary:
	var pool_names: Array = Db.SURNAMES
	var nm := ""
	for i in 40:
		nm = pool_names[randi() % pool_names.size()]
		if not used.has(nm):
			break
	used[nm] = true
	var id := "s%d" % _next_id
	_next_id += 1
	var s := {"id": id, "name": nm, "role": role, "xp": xp, "missions": 0, "kills": 0, "status": "ready", "recover": 0}
	soldiers[id] = s
	return s


# ------------------------------------------------------------------ queries
static func rank_of(xp: int) -> Dictionary:
	var r: Dictionary = RANKS[0]
	for k in RANKS:
		if xp >= int(k["xp"]):
			r = k
	return r


func ready_members(unit: Dictionary) -> Array:
	var out: Array = []
	for id in unit["members"]:
		var s: Dictionary = soldiers[id]
		if s["status"] == "ready":
			out.append(s)
	return out


func unit_by_kind_index(kind: String, idx: int):
	var i := 0
	for u in units:
		if u["kind"] == kind:
			if i == idx:
				return u
			i += 1
	return null


## Vehicles of a type that can go to battle now (not in repair).
func pool_ready(vt: String) -> int:
	return maxi(0, int(pool.get(vt, 0)) - int(repair.get(vt, 0)))


func count_units(kind: String) -> int:
	var c := 0
	for u in units:
		if u["kind"] == kind and ready_members(u).size() > 0:
			c += 1
	return c


func current_step() -> Dictionary:
	if step >= Game.CAMPAIGN_STEPS.size():
		return {}
	return Game.CAMPAIGN_STEPS[step]


func next_mission_playable() -> bool:
	var st := current_step()
	if st.is_empty():
		return false
	return Game.mission_available(st["mission"])


func missing_count() -> int:
	var c := 0
	for u in units:
		for id in u["members"]:
			if soldiers[id]["status"] in ["kia", "mia"]:
				c += 1
	return c


## Replace dead / missing soldiers with recruits, as far as supply allows.
func replenish() -> int:
	var used := {}
	for id in soldiers.keys():
		used[soldiers[id]["name"]] = true
	var added := 0
	for u in units:
		var members: Array = u["members"]
		for i in members.size():
			var s: Dictionary = soldiers[members[i]]
			if s["status"] in ["kia", "mia"] and supply >= RECRUIT_COST:
				supply -= RECRUIT_COST
				var nw := _new_soldier(s["role"], used, 0)
				members[i] = nw["id"]
				added += 1
	save()
	return added


# ------------------------------------------------------------------ after a mission
## Applies the result of a fought mission. `fallen` maps soldier id -> outcome
## ("ok", "wounded", "evacuated", "incap", "kia", "pow_taken") and `kills`.
func apply_result(r: Dictionary, outcomes: Dictionary, vehicles_lost: Array) -> Dictionary:
	var report := {"promotions": [], "kia": [], "mia": [], "recovering": [], "supply": 0, "vehicles": vehicles_lost.duplicate()}
	# vehicles repaired during this battle are back
	var back: Array = []
	for vt in repair.keys():
		if int(repair[vt]) > 0:
			back.append(Game.CATALOG[vt]["name"] if Game.CATALOG.has(vt) else vt)
	repair = {}
	if not back.is_empty():
		report["repaired"] = back
	# wounded from earlier missions heal
	for id in soldiers.keys():
		var s: Dictionary = soldiers[id]
		if s["status"] == "recovering":
			s["recover"] = int(s["recover"]) - 1
			if int(s["recover"]) <= 0:
				s["status"] = "ready"
	# the field is ours after a won battle (a raid or a recon too): the men down are found
	var held: bool = r.get("captured", false) or r.get("success", false)
	for id in outcomes.keys():
		if not soldiers.has(id):
			continue
		var s: Dictionary = soldiers[id]
		var o: Dictionary = outcomes[id]
		var before := rank_of(int(s["xp"]))
		match o["state"]:
			"kia":
				s["status"] = "kia"
				report["kia"].append(Loc.person(s["name"]))
				continue
			"incap":
				if held:
					s["status"] = "recovering"
					s["recover"] = 2
					report["recovering"].append(Loc.person(s["name"]))
				else:
					s["status"] = "mia"
					report["mia"].append(Loc.person(s["name"]))
					continue
			"evacuated":
				s["status"] = "recovering"
				s["recover"] = 1
				report["recovering"].append(Loc.person(s["name"]))
			"wounded":
				s["status"] = "ready"
			_:
				s["status"] = "ready"
		var mem := apply_memory(s, o, bool(r.get("success", false)))
		if mem != "":
			report.get_or_add("memory", []).append(mem)
		s["missions"] = int(s["missions"]) + 1
		s["kills"] = int(s["kills"]) + int(o.get("kills", 0))
		s["xp"] = int(s["xp"]) + 1 + mini(2, int(o.get("kills", 0))) + (1 if r.get("success", false) else 0)
		var after := rank_of(int(s["xp"]))
		if after["name"] != before["name"]:
			report["promotions"].append("%s → %s" % [Loc.person(s["name"]), after["name"]])
	for vt in vehicles_lost:
		pool[vt] = maxi(0, int(pool.get(vt, 0)) - 1)
	for vt in r.get("vehicles_damaged", []):
		if int(repair.get(vt, 0)) < int(pool.get(vt, 0)):
			repair[vt] = int(repair.get(vt, 0)) + 1
			report.get_or_add("in_repair", []).append(Game.CATALOG[vt]["name"] if Game.CATALOG.has(vt) else vt)
	_cohesion(r, outcomes, report)
	flags["next"] = consequences(r)
	report["next"] = flags["next"]
	var gain := 120 + int(r.get("score", 0)) * 3 + (150 if r.get("success", false) else 0)
	supply += gain
	report["supply"] = gain
	history.append({"step": step, "title": r.get("map", ""), "success": r.get("success", false), "score": r.get("score", 0),
		"kia": report["kia"].size(), "mia": report["mia"].size(), "pows": r.get("prisoners", 0), "vlost": vehicles_lost.size()})
	if r.get("success", false):
		step += 1
	var alive := 0
	for u in units:
		for id in u["members"]:
			if soldiers[id]["status"] in ["ready", "recovering"]:
				alive += 1
	if alive == 0 and supply < RECRUIT_COST:
		failed = true
	save()
	return report


## Unit cohesion: losing the commander or experienced men shakes a unit for
## the next battles; it comes back with time (faster after a win).
func _cohesion(r: Dictionary, outcomes: Dictionary, report: Dictionary) -> void:
	for u in units:
		var c: float = float(u.get("cohesion", 1.0))
		c = minf(1.0, c + AIConfig.CQ_COH_REGEN * (1.4 if r.get("success", false) else 1.0))
		var why: Array = []
		for id in u["members"]:
			if not outcomes.has(id) or not soldiers.has(id):
				continue
			var o: Dictionary = outcomes[id]
			var s: Dictionary = soldiers[id]
			if not (s["status"] in ["kia", "mia"]):
				continue
			if String(o.get("role", s["role"])) == "leader":
				c -= AIConfig.CQ_COH_LEADER
				why.append(Loc.t("командир %s") % Loc.person(s["name"]))
			elif int(s["xp"]) >= int(RANKS[2]["xp"]):
				c -= AIConfig.CQ_COH_VETERAN
				why.append("%s %s" % [rank_of(int(s["xp"]))["name"].to_lower(), s["name"]])
		u["cohesion"] = clampf(c, AIConfig.CQ_COH_MIN, 1.0)
		if not why.is_empty():
			report.get_or_add("cohesion", []).append(Loc.t("%s втратило: %s — згуртованість %d%%") % [u["name"], ", ".join(why), int(u["cohesion"] * 100.0)])


## What the battle leaves for the next one: how fresh the intel is and how
## strong the enemy will be. Each number comes with the reasons, shown to the
## player in the report and in the next briefing.
static func consequences(r: Dictionary) -> Dictionary:
	var success: bool = r.get("success", false)
	var total: float = maxf(1.0, float(r.get("enemy_total", 1)))
	var pows: int = int(r.get("prisoners", 0))
	var limit: float = maxf(60.0, float(r.get("time_limit", 1500.0)))
	var t: float = float(r.get("time", 0.0))
	var recon: float = clampf(float(r.get("recon", 0.0)), 0.0, 1.0)
	var q := AIConfig.CQ_INTEL_BASE + AIConfig.CQ_INTEL_RECON * recon
	var wi: Array = [Loc.t("розвідано %d%% сил противника") % int(recon * 100.0)]
	if pows > 0:
		q += AIConfig.CQ_INTEL_POW * mini(pows, 3)
		wi.append(Loc.t("полонені дали свідчення (%d)") % pows)
	if success and t < limit * 0.5:
		q += AIConfig.CQ_INTEL_FAST
		wi.append(Loc.t("швидкий наступ — противник не встиг перегрупуватись"))
	var dl: int = int(r.get("drones_lost", 0))
	if dl > 0:
		q -= AIConfig.CQ_INTEL_DRONE * mini(dl, 2)
		wi.append(Loc.t("втрачено дрон — менше знімків"))
	if not success:
		q -= AIConfig.CQ_INTEL_FAILED
		wi.append(Loc.t("противник бачив наступ і змінив позиції"))
	var k := 1.0
	var we: Array = []
	var esc: float = float(r.get("enemy_escaped", 0)) / total
	if esc > 0.05:
		k += AIConfig.CQ_ENEMY_ESCAPED * esc
		we.append(Loc.t("%d бійців противника відійшли живими й підсилили наступну позицію") % int(r.get("enemy_escaped", 0)))
	if pows > 0:
		k -= AIConfig.CQ_ENEMY_POW * mini(pows, 4)
		we.append(Loc.t("полонені — мінус люди й дух противника"))
	var out_frac: float = float(int(r.get("enemy_dead", 0)) + int(r.get("enemy_wia", 0)) + pows) / total
	if success and out_frac >= 0.7:
		k -= AIConfig.CQ_ENEMY_ROUT
		we.append(Loc.t("гарнізон розгромлено (%d%%) — противнику бракує людей") % int(out_frac * 100.0))
	if not success:
		k += AIConfig.CQ_ENEMY_FAILED
		we.append(Loc.t("після невдалого штурму противник підтягнув резерви"))
	elif t > limit * 0.8:
		k += AIConfig.CQ_ENEMY_SLOW
		we.append(Loc.t("бій затягнувся — противник встиг підготуватися"))
	return {"intel_q": clampf(q, 0.1, 0.95), "enemy_k": clampf(k, AIConfig.CQ_ENEMY_MIN, AIConfig.CQ_ENEMY_MAX),
		"why_intel": wi, "why_enemy": we}


static func intel_word(q: float) -> String:
	if q >= 0.75:
		return Loc.t("свіжі й точні")
	if q >= 0.5:
		return Loc.t("достатні")
	if q >= 0.3:
		return Loc.t("застарілі")
	return Loc.t("уривчасті")


static func enemy_word(k: float) -> String:
	if k >= 1.15:
		return Loc.t("посилений")
	if k > 1.03:
		return Loc.t("трохи посилений")
	if k <= 0.88:
		return Loc.t("ослаблений")
	if k < 0.97:
		return Loc.t("трохи ослаблений")
	return Loc.t("як очікувалось")


## Applies the last battle's consequences to the mission about to be fought
## (idempotent: works from the map's original intel).
func prepare_mission(def: MapDef) -> void:
	var nx: Dictionary = flags.get("next", {})
	if not def.has_meta("intel0"):
		def.set_meta("intel0", def.intel.duplicate(true))
	var intel: Dictionary = (def.get_meta("intel0") as Dictionary).duplicate(true)
	if nx.is_empty():
		def.intel = intel
		return
	var q: float = float(nx["intel_q"])
	var k: float = float(nx["enemy_k"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (step + 1) + history.size()
	intel["age"] = Loc.t("знімок зроблено %d год тому") % int(round(lerpf(14.0, 1.0, q)))
	# headcount as the staff estimates it: the real number, blurred by poor intel
	var n := 0
	for t in def.enemy_teams:
		n += (t["roles"] as Array).size()
	n = int(round(n * k))
	var spread := int(round(n * (1.0 - q) * 0.35)) + 1
	intel["estimate"] = Loc.t("%d–%d осіб") % [maxi(1, n - spread + rng.randi_range(-1, 1)), n + spread + rng.randi_range(0, 2)]
	# markers: poor intel misplaces them and misses some
	var marks: Array = []
	for m in intel.get("markers", []):
		if q < 0.5 and rng.randf() > q + 0.35:
			continue
		var mm: Dictionary = m.duplicate()
		var err := (1.0 - q) * 18.0
		mm["pos"] = (m["pos"] as Vector2) + Vector2(rng.randf_range(-err, err), rng.randf_range(-err, err))
		mm["r"] = float(m["r"]) * (1.0 + (1.0 - q) * 0.6)
		marks.append(mm)
	intel["markers"] = marks
	var lines: Array = intel.get("lines", [])
	if k >= 1.03:
		lines.insert(0, Loc.t("Після попереднього бою противник %s: очікуйте більше людей, мін і FPV.") % enemy_word(k))
	elif k <= 0.97:
		lines.insert(0, Loc.t("Після попереднього бою противник %s: людей і засобів у нього менше.") % enemy_word(k))
	if q >= 0.7:
		lines.append(Loc.t("Відомі з попереднього бою укріплення позначено на карті."))
	elif q < 0.3:
		lines.append(Loc.t("Свіжої розвідки немає — позиції противника можуть бути інакшими."))
	intel["lines"] = lines
	def.intel = intel
## a short memory line for the report. Returns that line ("" if nothing).
## The memory keeps Ukrainian keys (the save does not depend on the language);
## they are translated where shown (tr_list).
static func apply_memory(s: Dictionary, o: Dictionary, success: bool) -> String:
	var strain: float = float(s.get("strain", 0.0)) * AIConfig.MEM_CARRY
	var notes: Array = []
	var mem: Array = s.get("memory", [])
	if o.get("wounded", false) or o["state"] in ["wounded", "incap", "evacuated"]:
		strain += AIConfig.MEM_WOUND
		notes.append("поранення")   # i18n-key
	if float(o.get("pinned_s", 0.0)) >= AIConfig.MEM_LONG_FIRE_T:
		strain += AIConfig.MEM_LONG_FIRE
		notes.append("тривалий обстріл")   # i18n-key
		if o["state"] == "ok" and not o.get("panicked", false):
			var gb: float = minf(AIConfig.MEM_HARDEN_MAX, float(s.get("grit_bonus", 0.0)) + AIConfig.MEM_HARDEN)
			if gb > float(s.get("grit_bonus", 0.0)):
				s["grit_bonus"] = gb
				notes.append("загартований")   # i18n-key
	var lost: int = mini(2, int(o.get("comrades_lost", 0)))
	if lost > 0:
		strain += AIConfig.MEM_COMRADE * lost
		notes.append("втрата товариша" if lost == 1 else "втрата товаришів")   # i18n-key
	if o.get("panicked", false):
		strain += AIConfig.MEM_PANIC
		notes.append("паніка")   # i18n-key
	if success and o["state"] == "ok":
		strain += AIConfig.MEM_SUCCESS
		notes.append("успіх")
	s["strain"] = clampf(strain, 0.0, 100.0)
	for n in notes:
		if n != "успіх":
			mem.append(n)
	while mem.size() > 6:
		mem.remove_at(0)
	s["memory"] = mem
	if notes.is_empty():
		return ""
	return Loc.t("%s: %s (напруга %d)") % [Loc.person(s["name"]), ", ".join(tr_list(notes)), int(s["strain"])]


## Translated copies of memory keys.
static func tr_list(a: Array) -> Array:
	var out: Array = []
	for x in a:
		out.append(Loc.t(String(x)))
	return out


## Strain as words for the roster.
static func strain_label(v: float) -> String:
	if v >= 50.0:
		return Loc.t("виснажений")
	if v >= 25.0:
		return Loc.t("напружений")
	if v >= 8.0:
		return Loc.t("втомлений")
	return Loc.t("у формі")


# ------------------------------------------------------------------ persistence
## Save format version. Bump it when the meaning of a field changes and add a
## step to _migrate(); new optional fields need no bump (missing keys get
## defaults on load).
const SAVE_VERSION := 2


func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "active": active, "step": step, "supply": supply, "units": units,
		"soldiers": soldiers, "pool": pool, "history": history, "failed": failed, "next_id": _next_id,
		"difficulty": difficulty, "flags": flags, "repair": repair}


## Writes to a temp file first and keeps the previous save as .bak, so a
## crash during writing never leaves the player without a campaign.
func save() -> void:
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Campaign: cannot write %s" % tmp)
		return
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	var abs_path := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(abs_path, abs_path + ".bak")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_path)


## Loads the save; a damaged file falls back to the backup. Returns false
## when neither could be read (the campaign stays inactive).
func load_saved() -> bool:
	for path in [SAVE_PATH, SAVE_PATH + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var d = JSON.parse_string(f.get_as_text())
		var err := _validate(d)
		if err == "":
			_apply(_migrate(d))
			load_error = ""
			return true
		load_error = "%s: %s" % [path.get_file(), err]
		push_warning("Campaign save rejected — " + load_error)
	return false


func _validate(d) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return Loc.t("не JSON-об'єкт")
	if int(d.get("version", 1)) > SAVE_VERSION:
		return Loc.t("збереження з новішої версії гри")
	for k in [["units", TYPE_ARRAY], ["soldiers", TYPE_DICTIONARY], ["pool", TYPE_DICTIONARY], ["history", TYPE_ARRAY]]:
		if d.has(k[0]) and typeof(d[k[0]]) != k[1]:
			return Loc.t("поле %s має неправильний тип") % k[0]
	var sold: Dictionary = d.get("soldiers", {})
	for u in d.get("units", []):
		if typeof(u) != TYPE_DICTIONARY or not u.has("kind") or not Game.CATALOG.has(String(u["kind"])):
			return Loc.t("пошкоджений підрозділ")
		for id in u.get("members", []):
			if not sold.has(id) or typeof(sold[id]) != TYPE_DICTIONARY:
				return Loc.t("немає бійця %s") % str(id)
	return ""


func _migrate(d: Dictionary) -> Dictionary:
	if int(d.get("version", 1)) < 2:
		d["flags"] = {}
	d["version"] = SAVE_VERSION
	return d


func _apply(d: Dictionary) -> void:
	active = bool(d.get("active", false))
	step = clampi(int(d.get("step", 0)), 0, Game.CAMPAIGN_STEPS.size())
	supply = maxi(0, int(d.get("supply", 0)))
	units = d.get("units", [])
	soldiers = d.get("soldiers", {})
	pool = d.get("pool", {})
	history = d.get("history", [])
	failed = bool(d.get("failed", false))
	difficulty = String(d.get("difficulty", "normal"))
	if not Game.DIFFICULTY.has(difficulty):
		difficulty = "normal"
	flags = d.get("flags", {}) if typeof(d.get("flags", {})) == TYPE_DICTIONARY else {}
	repair = d.get("repair", {}) if typeof(d.get("repair", {})) == TYPE_DICTIONARY else {}
	for vt in repair.keys():
		repair[vt] = maxi(0, int(repair[vt]))
	if flags.has("next") and typeof(flags["next"]) == TYPE_DICTIONARY:
		var nx: Dictionary = flags["next"]
		nx["intel_q"] = clampf(float(nx.get("intel_q", 0.5)), 0.1, 0.95)
		nx["enemy_k"] = clampf(float(nx.get("enemy_k", 1.0)), AIConfig.CQ_ENEMY_MIN, AIConfig.CQ_ENEMY_MAX)
	else:
		flags.erase("next")
	for u in units:
		u["cohesion"] = clampf(float(u.get("cohesion", 1.0)), AIConfig.CQ_COH_MIN, 1.0)
	_next_id = int(d.get("next_id", soldiers.size() + 1))
	# JSON numbers come back as floats
	for id in soldiers.keys():
		var s: Dictionary = soldiers[id]
		for k in ["xp", "missions", "kills", "recover"]:
			s[k] = maxi(0, int(s.get(k, 0)))
		s["strain"] = clampf(float(s.get("strain", 0.0)), 0.0, 100.0)
		s["grit_bonus"] = clampf(float(s.get("grit_bonus", 0.0)), 0.0, AIConfig.MEM_HARDEN_MAX)
		if typeof(s.get("memory", [])) != TYPE_ARRAY:
			s["memory"] = []
		if not (String(s.get("status", "ready")) in ["ready", "recovering", "kia", "mia"]):
			s["status"] = "ready"
	for k in pool.keys():
		pool[k] = maxi(0, int(pool[k]))
