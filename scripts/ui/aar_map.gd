class_name AARMap
extends Control
## After Action Review map: the battlefield as the commander knew it — terrain
## outline, our squad routes, KNOWN enemy positions (from intel, not truth),
## where our men went down, evacuations and drone losses.

var def: MapDef
var blog: BattleLog
const SQUAD_COLS := [Color(0.35, 0.72, 1.0), Color(0.45, 0.95, 0.55), Color(1.0, 0.76, 0.30), Color(0.85, 0.55, 1.0), Color(0.4, 0.95, 0.95), Color(1.0, 0.6, 0.75)]


func _init(p_def: MapDef, p_blog: BattleLog) -> void:
	def = p_def
	blog = p_blog
	custom_minimum_size = Vector2(420, 420)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _side() -> float:
	return minf(size.x, size.y)


func w2m(p: Vector3) -> Vector2:
	var half := def.size * 0.5
	var s := _side()
	var off := Vector2((size.x - s) * 0.5, 0)
	return off + Vector2((p.x + half) / def.size * s, (p.z + half) / def.size * s)


func v2m(p: Vector2) -> Vector2:
	return w2m(Vector3(p.x, 0, p.y))


func _rect(r: Rect2) -> Rect2:
	var a := v2m(r.position)
	var b := v2m(r.end)
	return Rect2(a, b - a)


func _draw() -> void:
	if def == null:
		return
	var s := _side()
	var f := get_theme_default_font()
	draw_rect(Rect2(Vector2((size.x - s) * 0.5, 0), Vector2(s, s)), Color(0.07, 0.10, 0.08, 0.95))
	for t in def.treelines:
		draw_rect(_rect(t["rect"]), Color(0.16, 0.30, 0.17, 0.85))
	for rd in def.roads:
		var pts: PackedVector2Array = rd["pts"]
		for i in pts.size() - 1:
			draw_line(v2m(pts[i]), v2m(pts[i + 1]), Color(0.42, 0.38, 0.30, 0.8), 2.0)
	for tr in def.trenches:
		var pts: PackedVector2Array = tr
		for i in pts.size() - 1:
			draw_line(v2m(pts[i]), v2m(pts[i + 1]), Color(0.55, 0.45, 0.32), 1.6)
	if def.objective_rect.size != Vector2.ZERO:
		draw_rect(_rect(def.objective_rect), Color(UIK.ACCENT, 0.9), false, 1.5)
	# fresh craters and destroyed cover: how the ground changed in the fight
	if W.field:
		for c in W.field.craters:
			draw_circle(w2m(c["pos"]), maxf(1.5, float(c["r"]) * s / def.size), Color(0.45, 0.36, 0.25, 0.75))
		for p in W.field.pieces:
			if int(p["state"]) == 2:
				var q := w2m(p["pos"])
				draw_line(q + Vector2(-3, -3), q + Vector2(3, 3), Color(0.78, 0.66, 0.45), 1.2)
				draw_line(q + Vector2(-3, 3), q + Vector2(3, -3), Color(0.78, 0.66, 0.45), 1.2)
	if blog == null:
		return
	# routes
	var i := 0
	for k in blog.routes.keys():
		var r: PackedVector3Array = blog.routes[k]
		var col: Color = SQUAD_COLS[i % SQUAD_COLS.size()]
		i += 1
		for j in r.size() - 1:
			draw_line(w2m(r[j]), w2m(r[j + 1]), col, 2.0)
		if r.size() > 0:
			draw_circle(w2m(r[0]), 3.0, col)
			var e := w2m(r[r.size() - 1])
			draw_string(f, e + Vector2(5, -4), String(k), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	# known enemy positions
	for e in blog.contact_marks.keys():
		var m: Dictionary = blog.contact_marks[e]
		var p := w2m(m["pos"])
		if m["confirmed"]:
			var d := 4.0
			draw_polyline(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0), p + Vector2(0, -d)]), UIK.ENEMY, 1.5)
		else:
			draw_string(f, p + Vector2(-3, 4), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UIK.WOUND, 0.85))
	# casualties
	for c in blog.casualties:
		var p := w2m(c["pos"])
		if c["kia"]:
			var d := 3.5
			draw_line(p + Vector2(-d, -d), p + Vector2(d, d), UIK.ALERT, 2.0)
			draw_line(p + Vector2(-d, d), p + Vector2(d, -d), UIK.ALERT, 2.0)
		else:
			draw_line(p + Vector2(-4, 0), p + Vector2(4, 0), UIK.WOUND, 2.0)
			draw_line(p + Vector2(0, -4), p + Vector2(0, 4), UIK.WOUND, 2.0)
	for ev in blog.evacs:
		var p := w2m(ev["pos"])
		draw_arc(p, 6.0, 0, TAU, 14, UIK.GOOD, 1.5)
		draw_string(f, p + Vector2(8, 4), "%d" % int(ev["n"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIK.GOOD)
	for d in blog.drone_losses:
		var p := w2m(d["pos"])
		draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), UIK.INCAP, false, 1.5)
		draw_string(f, p + Vector2(7, 4), Loc.t("дрон"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIK.INCAP)
