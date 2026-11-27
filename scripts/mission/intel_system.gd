class_name IntelSystem
extends Node
## THE COMMANDER'S FOG — what the commander KNOWS about the enemy, as opposed
## to where the enemy really is. Every enemy the player has any information
## about has a contact record: reported position (with error), when it was
## last confirmed, how reliable it is, who reported it. The markers, minimap
## and HUD draw contacts, never the true positions.
##
## Statuses (AIConfig.INTEL_*):
##   CONFIRMED  — seen right now / a moment ago by the drone or our soldiers
##   PROBABLE   — recent but not current, or a fuzzy sighting (bad video link)
##   LAST_KNOWN — only the last known position is left; may have moved away
##   UNVERIFIED — heard, not seen (gunfire), large position error
##   LOST       — too old to trust; fades out and is forgotten
##   DESTROYED  — seen going down (confirmed hit)
## Lifetimes depend on whether the target was moving, cover / foliage where it
## was seen, weather, difficulty.

enum S { CONFIRMED, PROBABLE, LAST_KNOWN, UNVERIFIED, LOST, DESTROYED }
const NAMES_UK := ["ПІДТВЕРДЖЕНО", "ІМОВІРНО", "ОСТАННЯ ВІДОМА", "НЕПЕРЕВІРЕНО", "КОНТАКТ ВТРАЧЕНО", "УРАЖЕНО"]
static var NAMES = NAMES_UK   # the current language (Loc.localize_all)

var contacts := {}       # enemy object -> record (Dictionary)
var _t := 0.0


## A sighting. quality 0..1: 1 = clear view (good video, close), lower =
## blurry / far / jammed. Below AIConfig.INTEL_CONFIRM_Q the position is only
## approximate and the contact is PROBABLE.
func observe(e, src: String, quality: float) -> void:
	if not is_instance_valid(e) or W.mission == null:
		return
	var c: Dictionary = contacts.get(e, {})
	var exact: bool = quality >= AIConfig.INTEL_CONFIRM_Q
	var err: float = 0.0 if exact else AIConfig.INTEL_FUZZ_MAX * (1.0 - quality)
	var p: Vector3 = e.global_position
	if err > 0.0:
		p += Vector3(randf_range(-err, err), 0, randf_range(-err, err)) * 0.7
		# a fuzzy re-sighting does not overwrite a better recent fix
		if not c.is_empty() and c["err"] < err and W.time - float(c["t"]) < 4.0:
			return
	var moving: bool = e is Soldier and e.moving or (e is Vehicle and e.moving)
	c["pos"] = p
	c["t"] = W.time
	c["err"] = err
	c["src"] = src
	c["moving"] = moving
	c["kind"] = _kind(e) if exact else c.get("kind", Loc.t("невідомо"))
	c["status"] = S.CONFIRMED if exact else S.PROBABLE
	c["first"] = c.get("first", W.time)
	contacts[e] = c
	if W.blog:
		W.blog.contact(e, p, c["kind"], exact, src)


## Gunfire heard by our troops: an unverified contact with a big error, unless
## we already know better.
func heard(e, pos: Vector3, src: String) -> void:
	if not is_instance_valid(e):
		return
	var c: Dictionary = contacts.get(e, {})
	if not c.is_empty() and c["status"] in [S.CONFIRMED, S.PROBABLE] and W.time - float(c["t"]) < 20.0:
		return
	var err: float = AIConfig.INTEL_HEARD_ERR
	contacts[e] = {"pos": pos + Vector3(randf_range(-err, err), 0, randf_range(-err, err)) * 0.6, "t": W.time, "err": err,
		"src": src, "moving": false, "kind": Loc.t("невідомо"), "status": S.UNVERIFIED, "first": c.get("first", W.time)}
	if W.blog:
		W.blog.contact(e, contacts[e]["pos"], Loc.t("постріли"), false, src)


## The target went down where we could see it.
func neutralized(e) -> void:
	var c: Dictionary = contacts.get(e, {})
	if c.is_empty():
		return
	if c["status"] == S.CONFIRMED or W.time - float(c["t"]) < 3.0:
		c["status"] = S.DESTROYED
		c["t"] = W.time
		c["pos"] = e.global_position


func _kind(e) -> String:
	if e is Vehicle:
		return "техніка"
	if e is Soldier:
		match e.role:
			"mg":
				return "кулемет"
			"atgm":
				return "ПТРК"
			"at":
				return Loc.t("гранатомет")
		return Loc.t("піхота")
	return Loc.t("ціль")


## How long a contact stays PROBABLE / LAST_KNOWN / LOST (seconds).
func lifetimes(c: Dictionary) -> Vector3:
	var k: float = float(Game.diff("intel_age")) * float(Game.wx("sight"))
	var p: Vector3 = c["pos"]
	if W.grid:
		k *= 1.0 - W.grid.foliage_at(p) * AIConfig.INTEL_FOLIAGE_CUT
	if c["moving"]:
		return Vector3(AIConfig.INTEL_PROBABLE_MOVING, AIConfig.INTEL_LAST_MOVING, AIConfig.INTEL_LOST_TIME) * k
	return Vector3(AIConfig.INTEL_PROBABLE_STATIC, AIConfig.INTEL_LAST_STATIC, AIConfig.INTEL_LOST_TIME) * k


## Confidence 0..1 for display (fades with age).
func confidence(c: Dictionary) -> float:
	var age: float = W.time - float(c["t"])
	var lt := lifetimes(c)
	match int(c["status"]):
		S.CONFIRMED:
			return 1.0
		S.PROBABLE:
			return clampf(0.85 - age / maxf(lt.x, 1.0) * 0.3, 0.4, 0.85)
		S.LAST_KNOWN:
			return clampf(0.5 - (age - lt.x) / maxf(lt.y, 1.0) * 0.3, 0.15, 0.5)
		S.UNVERIFIED:
			return clampf(0.35 - age / 60.0 * 0.2, 0.1, 0.35)
		S.LOST:
			return 0.1
	return 1.0


func _process(delta: float) -> void:
	if W.mission == null or not W.running():
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	for e in contacts.keys():
		var c: Dictionary = contacts[e]
		var st: int = c["status"]
		var age: float = W.time - float(c["t"])
		if st == S.DESTROYED:
			if age > AIConfig.INTEL_DESTROYED_SHOW:
				contacts.erase(e)
			continue
		var alive: bool = is_instance_valid(e) and W.is_alive_target(e)
		# still in view right now → stays confirmed
		if alive and e is Soldier and e.revealed > 0.0:
			c["t"] = W.time
			c["pos"] = e.global_position
			c["err"] = 0.0
			c["status"] = S.CONFIRMED
			c["moving"] = e.moving
			continue
		var lt := lifetimes(c)
		if st == S.UNVERIFIED:
			if age > lt.y * 0.5:
				c["status"] = S.LOST
				c["t"] = W.time
			continue
		if st == S.LOST:
			if age > lt.z:
				contacts.erase(e)
			continue
		if age < AIConfig.INTEL_CONFIRM_HOLD and st == S.CONFIRMED:
			continue
		if age < lt.x:
			c["status"] = S.PROBABLE
		elif age < lt.x + lt.y:
			c["status"] = S.LAST_KNOWN
		else:
			c["status"] = S.LOST
			c["t"] = W.time


## Counts per status for the HUD.
func counts() -> Array:
	var n := [0, 0, 0, 0, 0, 0]
	for e in contacts.keys():
		n[int(contacts[e]["status"])] += 1
	return n


func contact_of(e) -> Dictionary:
	return contacts.get(e, {})
