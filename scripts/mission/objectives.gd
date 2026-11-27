class_name Objectives
extends RefCounted
## Mission tasks, shared by all maps. The map declares them in MapDef:
##   objective = {"type": "capture"}                       — clear and hold capture_rect (default)
##   objective = {"type": "destroy", "bunkers": [0, 2], "ew": true}
##                                                          — destroy the listed bunkers (and all real РЕБ)
##   objective = {"type": "recon"}                          — spot every bunker and РЕБ station with the drone
##   secondary = [{"type": ..., "title": ...}]             — optional tasks, a small score bonus each:
##       "ew"        destroy all real РЕБ stations
##       "bunkers"   destroy all bunkers
##       "no_vloss"  lose no combat vehicles
##       "evac_all"  every seriously wounded soldier evacuated
##       "pows"      take at least `n` prisoners
##       "casualties" no more than `n` killed
## MissionManager keeps the timer, the capture logic and the score; this class
## only answers "is the main task done?" and "which optional tasks are done?".

const SECONDARY_BONUS := 3.0
const TITLES_UK := {
	"capture": "Захопити та утримати опорний пункт",
	"destroy": "Знищити визначені цілі",
	"recon": "Розвідати всі вогневі точки та станції РЕБ",
	"training": "Пройти навчання командира",
	"ew": "Знищити станції РЕБ противника",
	"bunkers": "Знищити всі ДЗОТи та бліндажі",
	"no_vloss": "Не втратити бойову техніку",
	"evac_all": "Евакуювати всіх важкопоранених",
	"pows": "Взяти полонених",
	"casualties": "Обмежити безповоротні втрати",
}
static var TITLES = TITLES_UK   # the current language (Loc.localize_all)

var def: MapDef


func _init(p_def: MapDef) -> void:
	def = p_def


func type() -> String:
	return String(def.objective.get("type", "capture"))


static func title_of(o: Dictionary) -> String:
	if o.has("title"):
		return String(o["title"])
	var t := String(TITLES.get(String(o.get("type", "")), ""))
	match String(o.get("type", "")):
		"pows":
			t += Loc.t(" (не менше %d)") % int(o.get("n", 1))
		"casualties":
			t += Loc.t(" (не більше %d загиблих)") % int(o.get("n", 3))
	return t


func primary_title() -> String:
	return title_of(def.objective) if not def.objective.is_empty() else TITLES["capture"]


## Short text for the HUD top bar.
func hud_text() -> String:
	match type():
		"destroy":
			return Loc.t("знищити цілі (%d/%d)") % [_destroyed_targets(), _targets().size()]
		"recon":
			var p := _recon_progress()
			return Loc.t("розвідка (%d/%d)") % [p.x, p.y]
		"training":
			return Loc.t("навчання")
	return Loc.t("захопити опорний пункт")


## True when a destroy / recon task is complete. A capture task is handled by
## MissionManager's hold timer instead.
func primary_done() -> bool:
	match type():
		"destroy":
			return _targets().size() > 0 and _destroyed_targets() == _targets().size()
		"recon":
			var p := _recon_progress()
			return p.y > 0 and p.x >= p.y
	return false


func _targets() -> Array:
	var out: Array = []
	for i in def.objective.get("bunkers", []):
		if int(i) < W.bunkers.size():
			out.append(W.bunkers[int(i)])
	if def.objective.get("ew", false) and W.ew:
		for st in W.ew.stations:
			if not st.decoy:
				out.append(st)
	return out


func _destroyed_targets() -> int:
	var c := 0
	for t in _targets():
		if t.destroyed:
			c += 1
	return c


func _recon_progress() -> Vector2i:
	var seen := 0
	var total := 0
	for b in W.bunkers:
		total += 1
		if b.ever_seen:
			seen += 1
	if W.ew:
		for st in W.ew.stations:
			if not st.decoy:
				total += 1
				if st.ever_seen:
					seen += 1
	return Vector2i(seen, total)


## Evaluates the optional tasks for the report: [{title, done}].
func evaluate_secondary(r: Dictionary) -> Array:
	var out: Array = []
	for o in def.secondary:
		var done := false
		match String(o.get("type", "")):
			"ew":
				done = W.ew != null and W.ew.alive_stations().is_empty()
			"bunkers":
				done = true
				for b in W.bunkers:
					if not b.destroyed:
						done = false
			"no_vloss":
				done = int(r.get("vehicles_lost", 0)) == 0
			"evac_all":
				done = int(r.get("wia_left", 0)) == 0
			"pows":
				done = int(r.get("prisoners", 0)) >= int(o.get("n", 1))
			"casualties":
				done = int(r.get("kia", 0)) <= int(o.get("n", 3))
		out.append({"title": title_of(o), "done": done})
	return out
