class_name Screens
extends RefCounted
## Builders for the full-screen phases: briefing (aerial photo + intel),
## planning (force composition & budget), results (after-action report).


static func _backdrop(root: Control) -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.025, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)


static func _frame(root: Control, title: String, sub: String) -> VBoxContainer:
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	root.add_child(margin)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	var hb = HBoxContainer.new()
	vb.add_child(hb)
	hb.add_child(UIK.label(Loc.t("■ ДРОН-1 «ОКО»  ▸  "), 14, UIK.ALERT))
	var tl := UIK.label(title, 22, UIK.ACCENT)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_stretch_ratio = 1.6
	tl.clip_text = true
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb.add_child(tl)
	var sl := UIK.label(sub, 13, UIK.DIM)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sl.clip_text = true
	sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb.add_child(sl)
	var line = ColorRect.new()
	line.color = UIK.LINE
	line.custom_minimum_size.y = 1
	vb.add_child(line)
	return vb


## Vertical scroll area that takes the free height and never pushes the
## buttons below it off screen.
static func scroll(content: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	sc.set_deferred("scroll_vertical", 0)
	return sc


## Scroll area for a centred panel: as tall as its content, but never taller
## than the screen allows (keeps the panel's buttons visible).
static func fit_scroll(content: Control, root: Control, reserve: float) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(content)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fit := func() -> void:
		if is_instance_valid(sc) and is_instance_valid(root):
			sc.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, maxf(root.size.y - reserve, 120.0))
	root.resized.connect(fit)
	content.minimum_size_changed.connect(fit)
	fit.call_deferred()
	return sc


# ------------------------------------------------------------------ briefing
static func briefing(photo: Texture2D, photo_info: Dictionary, def: MapDef, on_next: Callable, on_menu: Callable = Callable(), next_label: String = Loc.t("ДАЛІ  ▸  ПЛАНУВАННЯ СИЛ")) -> Control:
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop(root)
	var head := Loc.t("БОЙОВЕ РОЗПОРЯДЖЕННЯ — «%s»") % def.title
	if Game.mode == "campaign":
		head = Loc.t("%s — КРОК %d: %s") % [Campaign.NAME.to_upper(), Game.campaign.step + 1, String(Game.campaign.current_step().get("title", "")).to_upper()]
	var vb = _frame(root, head, Loc.t("СКЛАДНІСТЬ: %s  •  РОЗВІДДАНІ: %s") % [Game.DIFFICULTY[Game.difficulty()]["name"], String(def.intel.get("age", ""))])
	var hb = HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.45
	hb.add_child(left)
	left.add_child(UIK.label(Loc.t("АЕРОФОТОЗНІМОК ПОЗИЦІЇ ПРОТИВНИКА"), 13, UIK.DIM))
	left.add_child(photo_view(photo, photo_info, def, Vector2(860, 572), true))
	if def.has_deploy_choice():
		left.add_child(deploy_label(def))
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size.x = 300
	right.add_theme_constant_override("separation", 12)
	hb.add_child(right)
	var t = UIK.rich()
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var a = UIK.hex(UIK.ACCENT)
	var task := def.task_text
	if Game.mode == "campaign":
		task = String(Game.campaign.current_step().get("task", task)) + "\n" + def.task_text
	var s = Loc.t("[color=#%s][b]ЗАВДАННЯ[/b][/color]\n%s\n") % [a, task]
	if not def.secondary.is_empty():
		s += Loc.t("[color=#%s]Додаткові завдання (+%d до оцінки кожне):[/color]\n") % [UIK.hex(UIK.DIM), int(Objectives.SECONDARY_BONUS)]
		for o in def.secondary:
			s += "  • %s\n" % Objectives.title_of(o)
	s += "\n"
	if Game.mode == "campaign" and Game.campaign.flags.has("next"):
		s += consequences_bbcode(Game.campaign.flags["next"], Loc.t("НАСЛІДКИ ПОПЕРЕДНЬОГО БОЮ")) + "\n"
	s += Loc.t("[color=#%s][b]ПРОТИВНИК[/b][/color]\nОрієнтовна чисельність: [color=#%s]%s[/color]\n") % [a, UIK.hex(UIK.ENEMY), def.intel.get("estimate", "?")]
	for line in def.intel.get("lines", []):
		s += "• %s\n" % line
	s += Loc.t("[color=#%s]Увага: дані можуть бути неповними або застарілими.[/color]\n\n") % UIK.hex(UIK.WOUND)
	s += Loc.t("[color=#%s][b]МІСЦЕВІСТЬ[/b][/color]\nТип: %s\n%s\n\n") % [a, def.terrain_type, def.terrain_desc]
	var wd: Dictionary = Game.WEATHER[Game.weather]
	s += Loc.t("[color=#%s][b]ПОГОДА[/b][/color]\n%s %s — %s\n\n") % [a, wd["icon"], wd["name"], wd["desc"]]
	if not def.fixed_loadout.is_empty():
		s += Loc.t("[color=#%s][b]УМОВИ[/b][/color]\nБез обмеження часу. Кожен крок пояснює підказка вгорі екрана; будь-який крок можна пропустити.\n\n") % a
		var names: Array = []
		for k in def.fixed_loadout.keys():
			if Game.CATALOG.has(k):
				names.append("%s ×%d" % [Game.CATALOG[k]["name"], int(def.fixed_loadout[k])])
		s += Loc.t("[color=#%s][b]ВАШІ СИЛИ[/b][/color]\n%s") % [a, ", ".join(names)]
	else:
		s += Loc.t("[color=#%s][b]УМОВИ[/b][/color]\nЧас на виконання: %d хв. %s: %d од.\n") % [a, int(def.time_limit / 60.0), Loc.t("Постачання кампанії") if Game.mode == "campaign" else Loc.t("Бюджет ресурсів"), Game.budget()]
		if def.budget_bonus > 0:
			s += Loc.t("[color=#%s]Складна операція: +%d од. %s[/color]\n") % [UIK.hex(UIK.GOOD), def.budget_bonus if Game.mode != "campaign" else Game.mission_grant(),
				Loc.t("на сили й підтримку") if Game.mode != "campaign" else Loc.t("постачання на цю операцію")]
		s += Loc.t("Захоплення: очистити зону цілі від противника та закріпитися (≥2 бійці в зоні об'єкта).\n\n")
		s += Loc.t("[color=#%s][b]ДОСТУПНІ СИЛИ[/b][/color]\nПіхота, БМП-1/БМП-2/M113, евакуаційна M113, міномет, FPV-дрони, димові снаряди.") % a
	t.text = s
	right.add_child(scroll(t))
	var bh = HBoxContainer.new()
	right.add_child(bh)
	if on_menu.is_valid():
		var bm = UIK.button(Loc.t("◂ ГОЛОВНЕ МЕНЮ"), on_menu, 200)
		bm.custom_minimum_size.y = 44
		bh.add_child(bm)
	var b = UIK.button(next_label, on_next, 200)
	b.custom_minimum_size.y = 44
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 17)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(b)
	return root


## "Висадка: …" line under the photo; follows the choice made on any photo.
static func deploy_label(def: MapDef) -> Label:
	var l := UIK.label("", 14, UIK.ACCENT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var upd := func() -> void:
		var d: Dictionary = Game.deploy_for(def)
		var desc := ""
		for o in def.deploy_options:
			if o["name"] == d.get("name", "") and String(o.get("desc", "")) != "":
				desc = " — " + String(o["desc"])
		l.text = Loc.t("▣ Район висадки: %s%s   (клацніть синю точку%s на знімку, щоб змінити)") % [d.get("name", "?"), desc,
			Loc.t(" або будь-яке місце в синій рамці") if def.deploy_zone.has_area() else ""]
	upd.call()
	Events.deploy_changed.connect(upd)
	l.tree_exiting.connect(func() -> void: Events.deploy_changed.disconnect(upd))
	return l


static func photo_view(photo: Texture2D, info: Dictionary, def: MapDef, sz: Vector2, pick: bool = false) -> Control:
	var arc := AspectRatioContainer.new()
	arc.ratio = sz.x / sz.y
	arc.stretch_mode = AspectRatioContainer.STRETCH_FIT
	arc.alignment_vertical = AspectRatioContainer.ALIGNMENT_BEGIN
	arc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arc.custom_minimum_size = sz * 0.35
	var holder = Control.new()
	arc.add_child(holder)
	var tr = TextureRect.new()
	tr.texture = photo
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sm = ShaderMaterial.new()
	sm.shader = load("res://shaders/photo.gdshader")
	tr.material = sm
	holder.add_child(tr)
	var ov = PhotoOverlay.new()
	ov.info = info
	ov.def = def
	ov.pick = pick and def.has_deploy_choice()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(ov)
	holder.resized.connect(ov.queue_redraw)
	return arc


class PhotoOverlay extends Control:
	var info: Dictionary
	var def: MapDef
	var pick := false   # the player picks the deployment point here
	var hover := -1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP if pick else Control.MOUSE_FILTER_IGNORE
		Events.deploy_changed.connect(queue_redraw)
		tree_exiting.connect(func() -> void: Events.deploy_changed.disconnect(queue_redraw))

	func w2p(p: Vector2) -> Vector2:
		var c: Vector3 = info["center"]
		var vh: float = info["size"]
		var vw: float = vh * info["aspect"]
		return Vector2((p.x - c.x) / vw + 0.5, (p.y - c.z) / vh + 0.5) * size

	func p2w(q: Vector2) -> Vector2:
		var c: Vector3 = info["center"]
		var vh: float = info["size"]
		var vw: float = vh * info["aspect"]
		var n := q / size - Vector2(0.5, 0.5)
		return Vector2(c.x + n.x * vw, c.z + n.y * vh)

	func _option_at(q: Vector2) -> int:
		var best := -1
		var bd := 26.0
		for i in def.deploy_options.size():
			var d := w2p(def.deploy_options[i]["pos"]).distance_to(q)
			if d < bd:
				bd = d
				best = i
		return best

	func _gui_input(e: InputEvent) -> void:
		if not pick:
			return
		if e is InputEventMouseMotion:
			var h := _option_at(e.position)
			if h != hover:
				hover = h
				queue_redraw()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var i := _option_at(e.position)
			if i >= 0:
				Game.deploy = Game.deploy_of(def, i)
			elif def.deploy_zone.has_point(p2w(e.position)):
				Game.deploy = {"map": def.id, "pos": p2w(e.position), "name": Loc.t("Обрана точка")}
			else:
				return
			W.sfx.ui("click")
			Events.deploy_changed.emit()
			accept_event()

	func _draw_deploy(f: Font) -> void:
		var blue := Color(0.35, 0.72, 1.0, 0.95)
		if def.deploy_zone.has_area():
			var a := w2p(def.deploy_zone.position)
			var b := w2p(def.deploy_zone.end)
			var r := Rect2(a, b - a)
			draw_rect(r, Color(0.35, 0.72, 1.0, 0.07), true)
			draw_rect(r, Color(0.35, 0.72, 1.0, 0.55), false, 1.5)
		var cur: Dictionary = Game.deploy_for(def)
		var cp: Vector2 = cur.get("pos", Vector2.INF)
		var entry := w2p(Vector2(def.player_entry.x, def.player_entry.z))
		for i in def.deploy_options.size():
			var o: Dictionary = def.deploy_options[i]
			var p := w2p(o["pos"])
			var sel: bool = o["pos"].distance_to(cp) < 0.5
			var rr := 9.0 if sel or i == hover else 7.0
			draw_circle(p, rr, Color(0.35, 0.72, 1.0, 0.9 if sel else 0.35))
			draw_arc(p, rr, 0, TAU, 20, blue, 2.0)
			draw_string(f, p + Vector2(12, 5), "%d  %s" % [i + 1, o["name"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 14 if sel else 13,
				Color.WHITE if sel or i == hover else Color(0.75, 0.88, 1.0, 0.85))
		if cp != Vector2.INF:
			var p := w2p(cp)
			# column route (dashed) from the entry to the chosen point
			var n := int(entry.distance_to(p) / 12.0)
			for k in n:
				if k % 2 == 0:
					draw_line(entry.lerp(p, float(k) / n), entry.lerp(p, float(k + 1) / n), Color(0.35, 0.72, 1.0, 0.7), 2.0)
			draw_arc(p, 14, 0, TAU, 24, Color.WHITE, 2.0)
			draw_line(p + Vector2(-18, 0), p + Vector2(-9, 0), Color.WHITE, 2.0)
			draw_line(p + Vector2(18, 0), p + Vector2(9, 0), Color.WHITE, 2.0)
			draw_line(p + Vector2(0, -18), p + Vector2(0, -9), Color.WHITE, 2.0)
			draw_line(p + Vector2(0, 18), p + Vector2(0, 9), Color.WHITE, 2.0)

	func _draw() -> void:
		var f: Font = UIK.font if UIK.font else get_theme_default_font()
		var red = Color(1.0, 0.25, 0.2, 0.95)
		for m in def.intel.get("markers", []):
			var p = w2p(m["pos"])
			var vh: float = info["size"]
			var r: float = float(m["r"]) / vh * size.y
			draw_arc(p, r, 0, TAU, 32, red, 2.0)
			draw_string(f, p + Vector2(r + 4, -r * 0.4), m["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, red)
		if def.has_deploy_choice():
			_draw_deploy(f)
		# grid + scale bar + north arrow + stamp
		var g = Color(1, 1, 1, 0.12)
		for i in range(1, 6):
			draw_line(Vector2(size.x * i / 6.0, 0), Vector2(size.x * i / 6.0, size.y), g, 1.0)
			draw_line(Vector2(0, size.y * i / 6.0), Vector2(size.x, size.y * i / 6.0), g, 1.0)
		var bar_m := 20.0 if float(info["size"]) < 200.0 else 50.0 if float(info["size"]) < 400.0 else 100.0
		var px20: float = bar_m / float(info["size"]) * size.y
		var base = Vector2(20, size.y - 24)
		draw_line(base, base + Vector2(px20, 0), Color.WHITE, 2.0)
		draw_string(f, base + Vector2(0, -6), Loc.t("%d м") % int(bar_m), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		draw_string(f, Vector2(size.x - 40, 30), Loc.t("Пн"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		draw_line(Vector2(size.x - 30, 60), Vector2(size.x - 30, 36), Color.WHITE, 2.0)
		draw_string(f, Vector2(12, 22), Loc.t("IMG-0417  ЗНІМОК ДРОНА  ") + String(def.intel.get("age", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.3), false, 1.0)


# ------------------------------------------------------------------ planning
class Planning extends Control:
	var lo = {}
	var counts = {}
	var summary: RichTextLabel
	var start_btn: Button
	var on_start: Callable
	var on_back: Callable

	func setup(photo: Texture2D, info: Dictionary, def: MapDef, p_start: Callable, p_back: Callable) -> void:
		on_start = p_start
		on_back = p_back
		lo = Game.campaign_loadout() if Game.mode == "campaign" else Game.loadout.duplicate()
		for k in lo.keys():
			lo[k] = mini(int(lo[k]), Game.item_max(k))
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		Screens._backdrop(self)
		var vb = Screens._frame(self, Loc.t("ПЛАНУВАННЯ — СКЛАД ЗВЕДЕНОГО ЗАГОНУ"), Loc.t("МІСІЯ «%s»") % def.title)
		var hb = HBoxContainer.new()
		hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hb.add_theme_constant_override("separation", 18)
		vb.add_child(hb)
		# left: photo + intel summary
		var left = VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.size_flags_stretch_ratio = 0.9
		hb.add_child(left)
		left.add_child(UIK.label(Loc.t("РОЗВІДКА"), 13, UIK.DIM))
		var pv := Screens.photo_view(photo, info, def, Vector2(480, 320), true)
		pv.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left.add_child(pv)
		if def.has_deploy_choice():
			left.add_child(Screens.deploy_label(def))
		var it = UIK.rich(0)
		var s = Loc.t("Противник: [color=#%s]%s[/color]\n") % [UIK.hex(UIK.ENEMY), def.intel.get("estimate", "?")]
		for line in def.intel.get("lines", []):
			s += "• %s\n" % line
		it.text = s
		var it_sc := Screens.scroll(it)
		it_sc.size_flags_stretch_ratio = 1.1
		left.add_child(it_sc)
		# center: catalog
		var mid = VBoxContainer.new()
		var mid_sc := Screens.scroll(mid)
		mid_sc.size_flags_stretch_ratio = 1.3
		hb.add_child(mid_sc)
		for cat in Game.CATEGORIES:
			mid.add_child(UIK.label(cat[1], 13, UIK.ACCENT))
			for key in Game.CATALOG.keys():
				var item: Dictionary = Game.CATALOG[key]
				if item["cat"] != cat[0]:
					continue
				mid.add_child(_row(key, item))
			var gap = Control.new()
			gap.custom_minimum_size.y = 6
			mid.add_child(gap)
		# right: summary
		var right = VBoxContainer.new()
		right.custom_minimum_size.x = 320
		hb.add_child(right)
		right.add_child(UIK.label(Loc.t("ПІДСУМОК"), 13, UIK.DIM))
		summary = UIK.rich(300)
		right.add_child(Screens.scroll(summary))
		var hb2 = HBoxContainer.new()
		right.add_child(hb2)
		hb2.add_child(UIK.button(Loc.t("◂ БРИФІНГ"), on_back, 120))
		start_btn = UIK.button(Loc.t("ПОЧАТИ ВИСАДКУ  ▸"), _start, 240)
		start_btn.custom_minimum_size.y = 44
		start_btn.add_theme_font_size_override("font_size", 17)
		hb2.add_child(start_btn)
		_refresh()

	func _row(key: String, item: Dictionary) -> Control:
		var p = UIK.panel()
		var hb = HBoxContainer.new()
		p.add_child(hb)
		var info = UIK.rich(200)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var price := Loc.t("%d од.") % Game.item_cost(key)
		if Game.mode == "campaign" and Game.item_cost(key) == 0:
			price = Loc.t("у підрозділі: %d") % Game.item_max(key)
		info.text = "[b]%s[/b]  [color=#%s]%s[/color]\n[color=#%s]%s[/color]" % [item["name"], UIK.hex(UIK.ACCENT), price, UIK.hex(UIK.DIM), item["desc"]]
		hb.add_child(info)
		var minus = UIK.button("−", _change.bind(key, -1), 34)
		hb.add_child(minus)
		var cnt = UIK.label("0", 18, UIK.TEXT)
		cnt.custom_minimum_size.x = 30
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb.add_child(cnt)
		counts[key] = cnt
		hb.add_child(UIK.button("+", _change.bind(key, 1), 34))
		return p

	func _change(key: String, d: int) -> void:
		var v = int(lo.get(key, 0)) + d
		v = clampi(v, 0, Game.item_max(key))
		lo[key] = v
		W.sfx.ui("click")
		_refresh()

	func _refresh() -> void:
		for k in counts.keys():
			counts[k].text = str(int(lo.get(k, 0)))
		var cost = Game.loadout_cost(lo)
		var inf = 0
		var cap = 0
		var squads = 0
		for k in ["rifle_squad", "assault_group"]:
			squads += int(lo.get(k, 0))
			inf += int(lo.get(k, 0)) * (Game.CATALOG[k]["roles"] as Array).size()
		for k in ["bmp1", "bmp2", "m113"]:
			cap += int(lo.get(k, 0)) * int(Db.VEHICLES[k]["cap"])
		var veh = int(lo.get("bmp1", 0)) + int(lo.get("bmp2", 0)) + int(lo.get("m113", 0))
		var bud: int = Game.budget()
		var left = bud - cost
		var c_left = UIK.GOOD if left >= 0 else UIK.ALERT
		var s = Loc.t("%s      %d од.\nЗалучено:    [color=#%s]%d од.[/color]\nЗалишок:     [color=#%s]%d од.[/color]\n%s\n\n") % [
			Loc.t("Постачання:") if Game.mode == "campaign" else Loc.t("Бюджет:"), bud, UIK.hex(UIK.ACCENT), cost, UIK.hex(c_left), left, UIK.bar(clampf(float(cost) / maxf(bud, 1), 0, 1), 24)]
		if W.mission.def.budget_bonus > 0:
			s += Loc.t("[color=#%s]Складна операція: %s +%d од.%s[/color]\n\n") % [UIK.hex(UIK.GOOD), Loc.t("постачання") if Game.mode == "campaign" else Loc.t("бюджет"),
				Game.mission_grant() if Game.mode == "campaign" else W.mission.def.budget_bonus,
				"" if W.mission.def.extra_max.is_empty() or Game.mode == "campaign" else Loc.t(", більше підрозділів і засобів")]
		if Game.mode == "campaign":
			s += Loc.t("[color=#%s]Кампанія: свої підрозділи й техніка не коштують очок, але обмежені тим, що вціліло. Постачання витрачається на засоби підтримки.[/color]\n\n") % UIK.hex(UIK.DIM)
		s += Loc.t("Особовий склад: %d (%d підрозділ.)\n") % [inf, squads]
		s += Loc.t("Бойова техніка: %d, місць для десанту: %d\n") % [veh, cap]
		s += Loc.t("Евакуаційних машин: %d\n") % int(lo.get("medevac", 0))
		s += Loc.t("Підтримка: міномет ×%d, FPV ×%d, дим ×%d\n\n") % [int(lo.get("mortar", 0)), int(lo.get("fpv", 0)), int(lo.get("smoke", 0))]
		var warn: Array = []
		var ok = true
		if squads == 0:
			warn.append(Loc.t("[color=#%s]✖ Потрібен хоча б один піхотний підрозділ.[/color]") % UIK.hex(UIK.ALERT))
			ok = false
		if left < 0:
			warn.append(Loc.t("[color=#%s]✖ Перевищено бюджет.[/color]") % UIK.hex(UIK.ALERT))
			ok = false
		if inf > cap and squads > 0:
			warn.append(Loc.t("[color=#%s]▲ Частина піхоти висуватиметься пішки.[/color]") % UIK.hex(UIK.WOUND))
		if int(lo.get("medevac", 0)) == 0:
			warn.append(Loc.t("[color=#%s]▲ Без евакуаційної машини поранених не вивезти.[/color]") % UIK.hex(UIK.WOUND))
		if int(lo.get("fpv", 0)) == 0 and int(lo.get("bmp1", 0)) == 0:
			warn.append(Loc.t("[color=#%s]▲ Мало засобів проти укріплень (ДЗОТ).[/color]") % UIK.hex(UIK.WOUND))
		s += "\n".join(warn)
		summary.text = s
		start_btn.disabled = not ok

	func _start() -> void:
		Game.loadout = lo.duplicate()
		on_start.call()


# ------------------------------------------------------------------ results
const AAR_COLORS := {"info": Color(0.52, 0.62, 0.55), "contact": Color(1.0, 0.82, 0.22), "order": Color(0.35, 0.72, 1.0),
	"support": Color(1.0, 0.76, 0.30), "loss": Color(1.0, 0.36, 0.26), "enemy": Color(0.45, 0.95, 0.55), "evac": Color(0.45, 0.95, 0.55),
	"drone": Color(1.0, 0.50, 0.12), "field": Color(0.78, 0.66, 0.45), "end": Color(0.80, 0.93, 0.82)}


## Intel freshness and enemy strength the last battle left, with the reasons.
static func consequences_bbcode(nx: Dictionary, head: String) -> String:
	var q: float = float(nx.get("intel_q", 0.5))
	var k: float = float(nx.get("enemy_k", 1.0))
	var qc: Color = UIK.GOOD if q >= 0.6 else (UIK.WOUND if q >= 0.35 else UIK.ALERT)
	var kc: Color = UIK.GOOD if k < 0.97 else (UIK.TEXT if k <= 1.03 else UIK.ALERT)
	var s := "[color=#%s][b]%s[/b][/color]\n" % [UIK.hex(UIK.ACCENT), head]
	s += Loc.t("Розвіддані: [color=#%s]%s (%d%%)[/color] — %s\n") % [UIK.hex(qc), Campaign.intel_word(q), int(q * 100.0), "; ".join(nx.get("why_intel", []))]
	s += Loc.t("Противник: [color=#%s]%s (×%.2f)[/color]") % [UIK.hex(kc), Campaign.enemy_word(k), k]
	var we: Array = nx.get("why_enemy", [])
	if not we.is_empty():
		s += " — " + "; ".join(we)
	return s + "\n"


static func _timeline_text(blog: BattleLog) -> String:
	if blog.events.is_empty():
		return Loc.t("[color=#%s]Подій не зафіксовано.[/color]") % UIK.hex(UIK.DIM)
	var s := ""
	for ev in blog.events:
		var c: Color = AAR_COLORS.get(String(ev["kind"]), UIK.TEXT)
		s += "[color=#%s]%s[/color]   [color=#%s]%s[/color]\n" % [UIK.hex(UIK.DIM), UIK.mmss(float(ev["t"])), UIK.hex(c), String(ev["text"])]
	return s


static func _analysis_text(items: Array) -> String:
	var s := Loc.t("[color=#%s][b]АНАЛІЗ РІШЕНЬ[/b] — з урахуванням того, що командир знав на момент рішення[/color]\n\n") % UIK.hex(UIK.ACCENT)
	for it in items:
		if it["good"]:
			s += "[color=#%s]✔[/color]  %s\n\n" % [UIK.hex(UIK.GOOD), String(it["text"])]
		else:
			s += "[color=#%s]⚠[/color]  %s\n\n" % [UIK.hex(UIK.WOUND), String(it["text"])]
	return s


static func results(r: Dictionary, on_retry: Callable, on_replan: Callable, on_menu: Callable) -> Control:
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop(root)
	var vb = _frame(root, Loc.t("ПІДСУМКИ ОПЕРАЦІЇ — «%s»") % r["map"], Loc.t("СКЛАДНІСТЬ: %s  •  %s  •  ЧАС ОПЕРАЦІЇ %s") % [Game.DIFFICULTY[r.get("difficulty", "normal")]["name"], String(r.get("weather", "")), UIK.mmss(r["time"])])
	var center = CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(center)
	var p = UIK.panel()
	p.custom_minimum_size = Vector2(760, 0)
	center.add_child(p)
	var inner = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	p.add_child(inner)
	var ok: bool = r["success"]
	var head = UIK.label(Loc.t("ЗАВДАННЯ ВИКОНАНО") if ok else Loc.t("ЗАВДАННЯ НЕ ВИКОНАНО"), 30, UIK.GOOD if ok else UIK.ALERT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(head)
	var reasons = {"captured": Loc.t("Позицію противника захоплено та утримано."), "completed": Loc.t("Основне завдання виконано."), "wiped": Loc.t("Підрозділи втратили боєздатність."),
		"timeout": Loc.t("Час на виконання завдання вичерпано."), "abort": Loc.t("Операцію припинено за рішенням командира.")}
	var rs = UIK.label(reasons.get(r["reason"], ""), 15, UIK.DIM)
	rs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(rs)
	var t = UIK.rich(720)
	var g = UIK.hex(UIK.GOOD)
	var al = UIK.hex(UIK.ALERT)
	var w = UIK.hex(UIK.WOUND)
	var s = "[table=2]"
	s += _row2(String(r.get("objective", Loc.t("Позицію захоплено"))), Loc.t("[color=#%s]ВИКОНАНО[/color]") % g if r["success"] else Loc.t("[color=#%s]НЕ ВИКОНАНО[/color]") % al)
	for o in r.get("secondary", []):
		s += _row2(Loc.t("Додатково: ") + String(o["title"]), Loc.t("[color=#%s]ТАК (+%d)[/color]") % [g, int(Objectives.SECONDARY_BONUS)] if o["done"] else Loc.t("[color=#%s]ні[/color]") % UIK.hex(UIK.DIM))
	s += _row2(Loc.t("Особовий склад (залучено)"), str(r["personnel"]))
	s += _row2(Loc.t("Загиблі"), "[color=#%s]%d[/color]" % [al, r["kia"]])
	s += _row2(Loc.t("Поранені (усього)"), "[color=#%s]%d[/color]" % [w, r["wia"]])
	s += _row2(Loc.t("Евакуйовано"), "[color=#%s]%d[/color]" % [g, r["evacuated"]])
	s += _row2(Loc.t("Поранені, не евакуйовані"), str(r["wia_left"]))
	s += _row2(Loc.t("Втрати техніки"), Loc.t("%d з %d %s") % [r["vehicles_lost"], r["vehicles_total"], ("(" + ", ".join(r["vehicles_list"]) + ")") if r["vehicles_lost"] > 0 else ""])
	s += _row2(Loc.t("Противник: знищено / уражено / відійшло"), Loc.t("%d / %d / %d  (з %d)") % [r["enemy_dead"], r["enemy_wia"], r["enemy_escaped"], r["enemy_total"]])
	s += _row2(Loc.t("Взято в полон"), "[color=#%s]%d[/color]" % [g, r.get("prisoners", 0)])
	s += _row2(Loc.t("Підриви на мінах"), str(r.get("mines", 0)))
	s += _row2(Loc.t("Втрачено розвід. дронів (РЕБ)"), str(r.get("drones_lost", 0)))
	var su: Dictionary = r["support_used"]
	s += _row2(Loc.t("Використано засобів"), Loc.t("міномет ×%d, FPV ×%d, дим ×%d") % [su["mortar"], su["fpv"], su["smoke"]])
	s += _row2(Loc.t("Бійців впадали в паніку"), str(int(r.get("panicked", 0))))
	s += _row2(Loc.t("Витрачено набоїв / гранат"), "%d / %d" % [int(r.get("rounds", 0)), int(r.get("grenades_used", 0))])
	s += _row2(Loc.t("Ресурси: залучено / використано"), Loc.t("%d / %d од.") % [r["cost_total"], r["cost_used"]])
	s += "[/table]"
	t.text = s
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.add_child(t)
	var pages: Array = []
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	inner.add_child(tabs)
	var summary := Screens.fit_scroll(body, root, 380.0)
	inner.add_child(summary)
	pages.append(summary)
	if W.blog:
		var tl := UIK.rich(720)
		tl.text = _timeline_text(W.blog)
		var tlb := VBoxContainer.new()
		tlb.add_child(tl)
		var tls := Screens.fit_scroll(tlb, root, 380.0)
		inner.add_child(tls)
		pages.append(tls)
		var mapbox := VBoxContainer.new()
		mapbox.add_theme_constant_override("separation", 6)
		var amap := AARMap.new(W.mission.def if W.mission else null, W.blog)
		mapbox.add_child(amap)
		var lg := UIK.label(Loc.t("━ маршрути відділень   ◇ відомі позиції противника   ? непідтверджені   ✕ загиблі   + поранені   ○ евакуація   □ втрата дрона"), 11, UIK.DIM)
		lg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mapbox.add_child(lg)
		var fitmap := func() -> void:
			if is_instance_valid(amap) and is_instance_valid(root):
				var side := clampf(root.size.y - 420.0, 220.0, 520.0)
				amap.custom_minimum_size = Vector2(side, side)
		root.resized.connect(fitmap)
		fitmap.call_deferred()
		inner.add_child(mapbox)
		pages.append(mapbox)
		var an := UIK.rich(720)
		an.text = _analysis_text(r.get("analysis", []))
		var anb := VBoxContainer.new()
		anb.add_child(an)
		var ans := Screens.fit_scroll(anb, root, 380.0)
		inner.add_child(ans)
		pages.append(ans)
	if W.radio:
		var rl := UIK.rich(720)
		rl.text = RadioPanel.entries_bbcode(W.radio.entries, "all")
		var rlb := VBoxContainer.new()
		rlb.add_child(rl)
		var rls := Screens.fit_scroll(rlb, root, 380.0)
		inner.add_child(rls)
		pages.append(rls)
	var names := [Loc.t("ПІДСУМОК"), Loc.t("ХРОНОЛОГІЯ"), Loc.t("КАРТА"), Loc.t("АНАЛІЗ"), Loc.t("РАДІО")]
	var btns: Array = []
	var group := ButtonGroup.new()
	for k in pages.size():
		var b := UIK.button(names[k], Callable(), 130)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = k == 0
		btns.append(b)
		tabs.add_child(b)
		var idx := k
		b.pressed.connect(func() -> void:
			for j in pages.size():
				pages[j].visible = j == idx)
		pages[k].visible = k == 0
	if pages.size() < 2:
		tabs.visible = false
	var sc = UIK.label(Loc.t("ЗАГАЛЬНА ОЦІНКА: %d / 100 — %s") % [r["score"], r["grade"]], 22, UIK.ACCENT)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(sc)
	var cr: Dictionary = r.get("campaign", {})
	if not cr.is_empty():
		var ct = UIK.rich(720)
		var cs := Loc.t("[color=#%s][b]НАСЛІДКИ ДЛЯ КАМПАНІЇ[/b][/color]\n") % UIK.hex(UIK.ACCENT)
		cs += Loc.t("Постачання: +%d од. (усього %d)\n") % [cr["supply"], Game.campaign.supply]
		if cr["kia"].size() > 0:
			cs += Loc.t("[color=#%s]Загинули (вибувають назавжди): %s[/color]\n") % [al, ", ".join(cr["kia"])]
		if cr["mia"].size() > 0:
			cs += Loc.t("[color=#%s]Зникли безвісти (залишились на полі бою): %s[/color]\n") % [al, ", ".join(cr["mia"])]
		if cr["recovering"].size() > 0:
			cs += Loc.t("[color=#%s]На лікуванні, пропустять наступний бій: %s[/color]\n") % [w, ", ".join(cr["recovering"])]
		if cr["promotions"].size() > 0:
			cs += Loc.t("[color=#%s]Підвищення: %s[/color]\n") % [g, ", ".join(cr["promotions"])]
		if cr["vehicles"].size() > 0:
			cs += Loc.t("[color=#%s]Втрачено техніку з автопарку: %d од.[/color]\n") % [al, cr["vehicles"].size()]
		if cr.get("in_repair", []).size() > 0:
			cs += Loc.t("[color=#%s]У ремонті, пропустить наступний бій: %s[/color]\n") % [w, ", ".join(cr["in_repair"])]
		if cr.get("repaired", []).size() > 0:
			cs += Loc.t("[color=#%s]Повернулась з ремонту: %s[/color]\n") % [g, ", ".join(cr["repaired"])]
		for line in cr.get("cohesion", []):
			cs += "[color=#%s]%s[/color]\n" % [w, line]
		if cr.get("memory", []).size() > 0:
			cs += Loc.t("[color=#%s]Що бій залишив у бійцях:[/color] %s\n") % [UIK.hex(UIK.DIM), "; ".join(cr["memory"])]
		if cr.has("next"):
			cs += "\n" + consequences_bbcode(cr["next"], Loc.t("ЩО ЦЕЙ БІЙ ЗАЛИШИВ НА НАСТУПНИЙ")) + "\n"
		cs += Loc.t("Наступний крок кампанії відкрито.") if r["success"] else Loc.t("Позицію не взято — крок кампанії доведеться повторити.")
		ct.text = cs
		body.add_child(ct)
	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_child(hb)
	if not cr.is_empty():
		hb.add_child(UIK.button(Loc.t("ДО КАМПАНІЇ"), on_menu, 220))
		return root
	hb.add_child(UIK.button(Loc.t("ПОВТОРИТИ МІСІЮ"), on_retry, 220))
	hb.add_child(UIK.button(Loc.t("ЗМІНИТИ СКЛАД СИЛ"), on_replan, 220))
	hb.add_child(UIK.button(Loc.t("ГОЛОВНЕ МЕНЮ"), on_menu, 200))
	return root


static func _row2(a: String, b: String) -> String:
	return "[cell][color=#%s]%s[/color]   [/cell][cell]%s[/cell]" % [UIK.hex(UIK.DIM), a, b]
