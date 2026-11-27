class_name GrenadeLogic
extends RefCounted
## The single place that decides whether a soldier throws a hand grenade or
## fires an under-barrel grenade. Every grenade in the game goes through
## try_throw(): stock, cooldown, state, information, range, friendly safety,
## whether it is worth it, keeping the last grenade for the trench, and the
## squad's own coordination (one grenade per spot, a few per squad per minute).
## Parameters: AIConfig.NADE_*.


## kind: "hand" or "gl". reason: "aimed" (visible target), "blind" (known
## enemy out of sight), "corner" (trench corner with a known enemy behind it).
## info_age: seconds since the target position was confirmed.
## Returns true if the grenade is committed (stock taken, spot claimed).
static func try_throw(s, pos: Vector3, kind: String, reason: String, info_age: float, target_cover: float) -> bool:
	var why := check(s, pos, kind, reason, info_age, target_cover)
	if why != "":
		return false
	commit(s, pos, kind)
	return true


## "" when allowed, otherwise the reason (used by tests / debugging).
static func check(s, pos: Vector3, kind: String, reason: String, info_age: float, target_cover: float) -> String:
	var stock: int = s.grenades if kind == "hand" else s.gl_rounds
	if stock <= 0:
		return Loc.t("немає")
	if s.grenade_cd > 0.0 or s.action != "":
		return Loc.t("перезарядка")
	if s.supp_level >= AIConfig.NADE_MAX_LEVEL:
		return Loc.t("притиснутий")
	if reason != "aimed" and info_age > AIConfig.NADE_INFO_AGE:
		return Loc.t("застаріла розвідка")
	var d: float = s.global_position.distance_to(pos)
	var rng: Vector2 = AIConfig.NADE_RANGE_HAND if kind == "hand" else AIConfig.NADE_RANGE_GL
	if reason == "corner":
		rng = AIConfig.NADE_RANGE_CORNER
	if d < rng.x or d > rng.y:
		return Loc.t("дистанція")
	if not s.blast_safe(pos, AIConfig.NADE_SAFE_HAND if kind == "hand" else AIConfig.NADE_SAFE_GL):
		return Loc.t("свої поруч")
	# worth it? A grenade is for men behind cover or bunched up — a lone man in
	# the open is shot, not bombed
	if reason == "aimed" and target_cover < AIConfig.NADE_MIN_COVER and _enemies_near(s, pos, 4.5) < 2:
		return Loc.t("недоцільно")
	# the last hand grenade is kept for the trench / close fight
	if kind == "hand" and stock == 1 and not _close_fight(s, d):
		return Loc.t("останню бережуть")
	# squad coordination: one grenade per spot at a time, a few per window
	var sq = s.squad
	var key := _key(pos)
	if sq.nade_claims.has(key) and W.time - float(sq.nade_claims[key]) < AIConfig.NADE_CLAIM_TIME:
		return Loc.t("вже кинули сюди")
	var recent := 0
	for t in sq.nade_log:
		if W.time - float(t) < AIConfig.NADE_WINDOW:
			recent += 1
	if recent >= AIConfig.NADE_PER_WINDOW:
		return Loc.t("ліміт відділення")
	return ""


static func commit(s, pos: Vector3, kind: String) -> void:
	if kind == "hand":
		s.grenades -= 1
		s.grenade_cd = randf_range(AIConfig.NADE_CD.x, AIConfig.NADE_CD.y)
	else:
		s.gl_rounds -= 1
		s.grenade_cd = randf_range(AIConfig.NADE_CD.x * 0.7, AIConfig.NADE_CD.y * 0.7)
	s.nades_used += 1
	var sq = s.squad
	sq.nade_claims[_key(pos)] = W.time
	sq.nade_log.append(W.time)
	while sq.nade_log.size() > 12:
		sq.nade_log.pop_front()


static func _key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / AIConfig.NADE_CLAIM_CELL)), int(floor(p.z / AIConfig.NADE_CLAIM_CELL)))


static func _enemies_near(s, pos: Vector3, r: float) -> int:
	var n := 0
	for e in s.squad.known.keys():
		if W.is_alive_target(e) and (s.squad.known[e]["pos"] as Vector3).distance_to(pos) < r:
			n += 1
	return n


static func _close_fight(s, d: float) -> bool:
	if d <= AIConfig.NADE_LAST_DIST:
		return true
	return s.in_trench() and (s.squad.order == "clear" or s.solo == "clear")
