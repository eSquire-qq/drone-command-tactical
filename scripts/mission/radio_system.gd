class_name RadioSystem
extends Node
## Radio net: reports from our squads and crews reach the commander with a
## delay and not always intact. A report is created by a real event; it is
## delivered after a delay that grows with distance to the command post,
## enemy jamming at the sender and the sender's state (pinned men, no
## commander). Under heavy jamming parts of the message are lost; a pinned or
## leaderless squad may misjudge numbers. All numbers — AIConfig.RADIO_*.
##
## Delivered reports go to the HUD message feed (Events.message) and to the
## full mission log `entries`, shown in the RADIO LOG panel and the report.

const TYPES_UK := {
	"contact": "КОНТАКТ", "fire": "ПІД ВОГНЕМ", "suppressed": "ПРИДУШЕНІ", "casualty": "ВТРАТИ",
	"vehicle": "ТЕХНІКА", "evac": "ЕВАКУАЦІЯ", "ammo": "БОЄПРИПАСИ", "retreat": "ВІДХІД ПРОТИВНИКА",
	"target": "ЦІЛЬ УРАЖЕНО", "regroup": "ПЕРЕГРУПУВАННЯ", "drone": "ДРОН", "order": "ВИКОНАННЯ", "support": "ПІДТРИМКА",
}
static var TYPES = TYPES_UK   # the current language (Loc.localize_all)
## filter groups for the panel
const FILTERS_UK := {
	"all": ["УСІ", []],
	"alarm": ["ТРИВОГИ", ["fire", "suppressed", "casualty", "vehicle"]],
	"contact": ["КОНТАКТИ", ["contact", "retreat", "target"]],
	"evac": ["ЕВАКУАЦІЯ", ["evac", "casualty"]],
}
static var FILTERS = FILTERS_UK   # the current language (Loc.localize_all)

var pending: Array = []    # {due, sent, sender, type, text, kind, pos, rel}
var entries: Array = []    # delivered: {sent, t, sender, type, text, kind, delay, rel}
var _seq := 0
var _false_t := AIConfig.RADIO_FALSE_EVERY
var false_reports := 0


## Few false reports: a nervous squad near foliage reports movement where
## there is nobody. Always marked "непевно" and never put on the map as fact.
func _false_reports() -> void:
	for sq in W.mission.friendly_squads:
		if sq.active_count() <= 0 or sq.mounted or sq.kind == "medevac":
			continue
		var chance: float = AIConfig.RADIO_FALSE_CHANCE * (1.0 + sq.avg_level())
		if randf() > chance:
			continue
		var c: Vector3 = sq.center()
		var spot := c + Vector3(randf_range(-1, 1), 0, randf_range(-1.0, -0.3)).normalized() * randf_range(50.0, 110.0)
		if W.grid and W.grid.foliage_at(spot) < 0.3:
			continue
		var real := false
		for u in W.units:
			if u.side == 1 and u.is_active() and u.global_position.distance_to(spot) < 25.0:
				real = true
				break
		if real:
			continue
		false_reports += 1
		_seq += 1
		pending.append({"due": now() + 1.5 + randf() * 2.0, "sent": now(), "sender": sq.short, "type": "contact",
			"text": Loc.t("%s: підозрілий рух у посадці, %s, ~%d м. Не підтверджено.") % [sq.short, bearing(c, spot), int(round(c.distance_to(spot) / 10.0) * 10.0)],
			"kind": "info", "pos": spot, "rel": "непевно", "seq": _seq})


func now() -> float:
	return W.mission.t if W.mission else 0.0


## A report from `sender` (Squad / Vehicle / null for staff and support).
## rel: "точно" / "приблизно" / "непевно" / "перешкоди" — set here when null.
func report(sender, type: String, text: String, kind: String = "info", pos = null, jam_override: float = -1.0) -> void:
	var name := ""
	var p: Vector3 = Vector3.ZERO
	var has_p := false
	if sender is Squad:
		name = sender.short
		p = sender.center()
		has_p = true
	elif sender is Vehicle:
		name = sender.vname
		p = sender.global_position
		has_p = true
	if pos is Vector3:
		p = pos
		has_p = true
	var delay := AIConfig.RADIO_BASE + randf() * AIConfig.RADIO_JITTER
	var rel := "точно"
	var jam := 0.0
	if has_p:
		if W.mission and W.mission.def:
			delay += clampf(p.distance_to(W.mission.def.player_entry) / 100.0, 0.0, 2.0) * AIConfig.RADIO_PER_100M
		if jam_override >= 0.0:
			jam = jam_override
		elif W.ew:
			jam = W.ew.jam_at(p)
		delay += jam * AIConfig.RADIO_JAM_DELAY
	if sender is Squad:
		var lvl: float = sender.avg_level()
		if lvl >= 2.5:
			delay += AIConfig.RADIO_PINNED_DELAY
			rel = "приблизно"
		var ld = sender.leader()
		if ld == null or ld.role != "leader":
			delay += AIConfig.RADIO_NO_LEADER_DELAY
			if rel == "точно":
				rel = "приблизно"
	# urgent calls get priority on the net
	if kind == "alert":
		delay *= 0.7
	if jam > AIConfig.RADIO_GARBLE_JAM:
		rel = "перешкоди"
		text = garble(text, (jam - AIConfig.RADIO_GARBLE_JAM) / (1.0 - AIConfig.RADIO_GARBLE_JAM))
	var full := ("%s: %s" % [name, text]) if name != "" else text
	_seq += 1
	pending.append({"due": now() + delay, "sent": now(), "sender": name, "type": type, "text": full, "kind": kind, "pos": p if has_p else null, "rel": rel, "seq": _seq})


## Staff / support messages: no radio delay (they come from our own net).
func staff(type: String, text: String, kind: String = "info") -> void:
	_deliver({"due": now(), "sent": now(), "sender": "", "type": type, "text": text, "kind": kind, "pos": null, "rel": "точно"})


## Part of the words lost to static.
static func garble(text: String, amount: float) -> String:
	var words := text.split(" ")
	var out: PackedStringArray = []
	var lost := 0
	for i in words.size():
		# keep the first word (call sign) and numbers readable more often
		var keep_p := 1.0 - clampf(amount, 0.0, 1.0) * 0.55
		if i > 0 and randf() > keep_p and lost < words.size() / 2:
			if out.is_empty() or out[out.size() - 1] != "…":
				out.append("…")
			lost += 1
		else:
			out.append(words[i])
	return " ".join(out)


## Number as the men on the ground would estimate it.
static func estimate(n: int, reliable: bool) -> String:
	if reliable:
		return str(n)
	if n <= 1:
		return "1–2"
	var lo := maxi(1, n - 1 - int(randf() < 0.4))
	return "%d–%d" % [lo, n + 1 + int(randf() < 0.3)]


static func bearing(from: Vector3, to: Vector3) -> String:
	var d := to - from
	# map: -z is north
	var a := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
	var names := [Loc.t("північ"), Loc.t("північний схід"), Loc.t("схід"), Loc.t("південний схід"), Loc.t("південь"), Loc.t("південний захід"), Loc.t("захід"), Loc.t("північний захід")]
	return names[int(round(a / 45.0)) % 8]


func _process(delta: float) -> void:
	if W.mission and W.running():
		_false_t -= delta
		if _false_t <= 0.0:
			_false_t = AIConfig.RADIO_FALSE_EVERY
			_false_reports()
	if pending.is_empty():
		return
	var t := now()
	var i := 0
	while i < pending.size():
		if float(pending[i]["due"]) <= t or (W.mission and W.mission.phase == MissionManager.Phase.ENDED):
			_deliver(pending[i])
			pending.remove_at(i)
		else:
			i += 1


func _deliver(m: Dictionary) -> void:
	var delay: float = now() - float(m["sent"])
	var e := {"sent": m["sent"], "t": now(), "sender": m["sender"], "type": m["type"], "text": m["text"], "kind": m["kind"], "delay": delay, "rel": m["rel"]}
	if entries.size() < AIConfig.RADIO_MAX_LOG:
		entries.append(e)
	var shown: String = m["text"]
	if m["rel"] == "перешкоди":
		shown = "📻 " + shown
	elif m["rel"] == "непевно":
		shown += Loc.t(" (непевно)")
	Events.msg(shown, m["kind"])
	Events.radio_entry.emit(e)
