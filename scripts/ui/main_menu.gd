class_name MainMenu
extends Control
## Main menu shown at launch, before the combat order (briefing).
## The live diorama orbits behind it.

var on_start: Callable
var on_campaign: Callable
var on_training: Callable
var reset_armed := false
var side_panel: PanelContainer
var side_box: VBoxContainer
var mission_btns := {}


func setup(p_start: Callable, p_campaign: Callable = Callable(), p_training: Callable = Callable()) -> void:
	on_start = p_start
	on_campaign = p_campaign
	on_training = p_training
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# darkening gradient on the left for readability
	var grad = TextureRect.new()
	var gt = GradientTexture2D.new()
	var g = Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.025, 0.93))
	g.set_color(1, Color(0.02, 0.03, 0.025, 0.0))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.anchor_right = 0.75
	grad.anchor_bottom = 1.0
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grad)
	var root = HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 50
	root.offset_top = 46
	root.offset_right = -50
	root.offset_bottom = -50
	root.add_theme_constant_override("separation", 40)
	add_child(root)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size.x = 380
	root.add_child(col)
	col.add_child(UIK.label(Loc.t("■ REC  ДРОН-1 «ОКО»"), 16, UIK.ALERT))
	col.add_child(UIK.label("DRONE COMMAND", 50, UIK.ACCENT))
	col.add_child(UIK.label(Loc.t("ТАКТИЧНЕ УПРАВЛІННЯ ПІДРОЗДІЛОМ"), 20, UIK.TEXT))
	var line = ColorRect.new()
	line.color = UIK.LINE
	line.custom_minimum_size = Vector2(380, 1)
	col.add_child(line)
	var gap = Control.new()
	gap.custom_minimum_size.y = 10
	col.add_child(gap)
	col.add_child(_big(Loc.t("НАВЧАННЯ"), _show_training))
	col.add_child(_big(Loc.t("КАМПАНІЯ"), _show_campaign))
	col.add_child(_big(Loc.t("ВИБІР МІСІЇ"), _show_missions))
	col.add_child(_big(Loc.t("КЕРУВАННЯ"), _show_controls))
	col.add_child(_big(Loc.t("НАЛАШТУВАННЯ"), _show_settings))
	col.add_child(_big(Loc.t("ВИХІД"), func(): get_tree().quit()))
	var sp = Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp)
	col.add_child(UIK.label(Loc.t("Демо %s • місія: «%s»") % [ProjectSettings.get_setting("application/config/version", ""), _mission_title(Game.current_map)], 14, UIK.DIM))
	side_panel = UIK.panel()
	side_panel.custom_minimum_size = Vector2(520, 0)
	side_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(side_panel)
	side_box = VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 10)
	side_panel.add_child(Screens.fit_scroll(side_box, self, 140.0))
	side_panel.visible = false   # opens on a tab, the battlefield stays visible


func _big(text: String, cb: Callable) -> Button:
	var b = UIK.button(text, cb, 360)
	b.custom_minimum_size.y = 48
	b.add_theme_font_size_override("font_size", 24)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.mouse_entered.connect(func(): W.sfx.ui("click"))
	return b


func _mission_title(id: String) -> String:
	return Game.map_def(id).title


func _start() -> void:
	W.sfx.ui("radio")
	on_start.call()


func _clear() -> void:
	side_panel.visible = true
	reset_armed = false
	for c in side_box.get_children():
		c.queue_free()


func _title(t: String) -> void:
	side_box.add_child(UIK.label(t, 22, UIK.ACCENT))


func _show_missions() -> void:
	_clear()
	_title(Loc.t("ВИБІР МІСІЇ — ОКРЕМИЙ БІЙ"))
	var i = 1
	var ids: Array = Game.MISSION_ORDER.duplicate()
	var custom := {}
	for cid in Game.custom_maps.keys():
		var cd: MapDef = Game.map_def(cid)
		custom[cid] = {"title": cd.title, "terrain": Loc.t("своя карта") + ((" • " + cd.terrain_type) if cd.terrain_type != "" else ""),
			"desc": cd.task_text if cd.task_text != "" else cd.terrain_desc}
		ids.append(cid)
	for id in ids:
		var m: Dictionary = Game.MISSIONS[id] if Game.MISSIONS.has(id) else custom[id]
		var ok: bool = Game.mission_available(id)
		var b = UIK.button("", _pick_mission.bind(id), 580)
		b.toggle_mode = true
		b.button_pressed = ok and id == Game.current_map
		b.disabled = not ok
		b.custom_minimum_size.y = 44
		b.add_theme_font_size_override("font_size", 19)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "  %d. «%s» — %s%s" % [i, m["title"], m["terrain"], "" if ok else Loc.t("   [У РОЗРОБЦІ]")]
		side_box.add_child(b)
		mission_btns[id] = b
		var info = UIK.rich(480)
		info.add_theme_font_size_override("normal_font_size", 16)
		var extra := ""
		if ok:
			var d: MapDef = Game.map_def(id)
			if d.fixed_loadout.is_empty():
				extra = Loc.t("\nЧас: %d хв • Бюджет: %d од. (залежить від складності)") % [int(d.time_limit / 60.0), Game.BUDGET]
			else:
				extra = Loc.t("\nЧас: %d хв • Сили визначено завданням") % int(d.time_limit / 60.0)
		info.text = "[color=#%s]%s%s[/color]" % [UIK.hex(UIK.TEXT if ok else UIK.DIM), m["desc"], extra]
		side_box.add_child(info)
		i += 1
	_difficulty_picker()
	_weather_picker()
	var go = UIK.button(Loc.t("РОЗПОЧАТИ МІСІЮ  ▸"), _start, 480)
	go.custom_minimum_size.y = 48
	go.add_theme_font_size_override("font_size", 20)
	side_box.add_child(go)


var diff_btns := {}
var diff_desc: Label


## Difficulty: three toggles + a one-line explanation of the selected one.
var wx_btns := {}
var wx_desc: Label


## Weather for a single mission: random or a fixed one; applied to the map at once.
func _weather_picker() -> void:
	side_box.add_child(UIK.label(Loc.t("ПОГОДА"), 15, UIK.ACCENT))
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 4)
	fl.add_theme_constant_override("v_separation", 4)
	side_box.add_child(fl)
	wx_btns.clear()
	for k in ["random"] + Game.WEATHER_ORDER:
		var nm: String = Loc.t("ВИПАДКОВА") if k == "random" else "%s %s" % [Game.WEATHER[k]["icon"], Game.WEATHER[k]["name"]]
		var b = UIK.button(nm, _pick_weather.bind(k), 0)
		b.toggle_mode = true
		b.custom_minimum_size.y = 34
		fl.add_child(b)
		wx_btns[k] = b
	wx_desc = UIK.label("", 14, UIK.DIM)
	wx_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wx_desc.custom_minimum_size.x = 480
	side_box.add_child(wx_desc)
	var cur := String(Game.settings.get("weather", "random"))
	for key in wx_btns.keys():
		wx_btns[key].button_pressed = key == cur
	_show_weather_desc(cur)


func _pick_weather(k: String) -> void:
	Game.set_weather_choice(k)
	for key in wx_btns.keys():
		wx_btns[key].button_pressed = key == k
	_show_weather_desc(k)


func _show_weather_desc(k: String) -> void:
	if wx_desc == null:
		return
	var w: Dictionary = Game.WEATHER[Game.weather]
	if k == "random":
		wx_desc.text = Loc.t("Погода визначається випадково. Зараз на карті: %s %s.") % [w["icon"], String(w["name"]).to_lower()]
	else:
		wx_desc.text = String(w["desc"])


func _difficulty_picker() -> void:
	side_box.add_child(UIK.label(Loc.t("СКЛАДНІСТЬ"), 15, UIK.ACCENT))
	var hb = HBoxContainer.new()
	side_box.add_child(hb)
	diff_btns.clear()
	for k in Game.DIFFICULTY_ORDER:
		var b = UIK.button(Game.DIFFICULTY[k]["name"], _pick_difficulty.bind(k), 150)
		b.toggle_mode = true
		b.custom_minimum_size.y = 40
		b.add_theme_font_size_override("font_size", 17)
		hb.add_child(b)
		diff_btns[k] = b
	diff_desc = UIK.label("", 14, UIK.DIM)
	diff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diff_desc.custom_minimum_size.x = 480
	side_box.add_child(diff_desc)
	_pick_difficulty(String(Game.settings.get("difficulty", "normal")))


func _pick_difficulty(k: String) -> void:
	Game.settings["difficulty"] = k
	Game.save_settings()
	for key in diff_btns.keys():
		diff_btns[key].button_pressed = key == k
	if diff_desc:
		diff_desc.text = Game.DIFFICULTY[k]["desc"]


func _pick_mission(id: String) -> void:
	if not Game.mission_available(id):
		return
	Game.current_map = id
	for k in mission_btns.keys():
		mission_btns[k].button_pressed = k == id


# ------------------------------------------------------------------ campaign tab
func _show_campaign() -> void:
	_clear()
	var c: Campaign = Game.campaign
	_title(Loc.t("КАМПАНІЯ: ") + Campaign.NAME.to_upper())
	var t = UIK.rich(480)
	t.add_theme_font_size_override("normal_font_size", 16)
	var a := UIK.hex(UIK.ACCENT)
	var dim := UIK.hex(UIK.DIM)
	if not c.active:
		t.text = Loc.t("Послідовні бойові завдання одного підрозділу.\n\n• Особовий склад переходить з бою в бій: імена, досвід, звання.\n• Загиблі вибувають назавжди; евакуйовані поранені пропускають наступний бій; полишені на полі бою — зниклі безвісти.\n• Знищена техніка зникає з автопарку.\n• Результат бою дає очки постачання: засоби підтримки та поповнення новобранцями.\n• Досвід: ветерани влучніші, витриваліші й рідше гинуть від поранень, менше піддаються придушенню, швидше перезаряджаються й рухаються, краще зачищають окопи (швидше працюють на поворотах, частіше кидають гранату за ріг).")
		side_box.add_child(t)
		_difficulty_picker()
		var b = UIK.button(Loc.t("ПОЧАТИ НОВУ КАМПАНІЮ  ▸"), _new_campaign, 480)
		b.custom_minimum_size.y = 48
		b.add_theme_font_size_override("font_size", 20)
		side_box.add_child(b)
		return
	var s2 := ""
	# progress
	for i in Game.CAMPAIGN_STEPS.size():
		var st: Dictionary = Game.CAMPAIGN_STEPS[i]
		var m: Dictionary = Game.MISSIONS[st["mission"]]
		var mark := "✔" if i < c.step else ("▶" if i == c.step else "·")
		var col := UIK.hex(UIK.GOOD) if i < c.step else (a if i == c.step else dim)
		var lock := "" if Game.mission_available(st["mission"]) else Loc.t("  [у розробці]")
		s2 += Loc.t("[color=#%s]%s Крок %d. %s — «%s»%s[/color]\n") % [col, mark, i + 1, st["title"], m["title"], lock]
	s2 += Loc.t("\nСкладність: [color=#%s]%s[/color] (незмінна до кінця кампанії)") % [a, Game.DIFFICULTY[c.difficulty]["name"]]
	if c.flags.has("next"):
		var nx: Dictionary = c.flags["next"]
		s2 += Loc.t("\nПісля останнього бою: розвіддані [color=#%s]%s[/color], противник [color=#%s]%s[/color]") % [a, Campaign.intel_word(float(nx["intel_q"])),
			a, Campaign.enemy_word(float(nx["enemy_k"]))]
	var rep: Array = []
	for vt in c.repair.keys():
		if int(c.repair[vt]) > 0:
			rep.append("%s ×%d" % [Game.CATALOG[vt]["name"] if Game.CATALOG.has(vt) else vt, int(c.repair[vt])])
	if not rep.is_empty():
		s2 += Loc.t("\n[color=#%s]У ремонті (пропустять бій): %s[/color]") % [UIK.hex(UIK.WOUND), ", ".join(rep)]
	s2 += Loc.t("\nПостачання: [color=#%s]%d од.[/color]   Автопарк: БМП-2 ×%d, БМП-1 ×%d, M113 ×%d, евак. ×%d\n") % [a, c.supply,
		int(c.pool.get("bmp2", 0)), int(c.pool.get("bmp1", 0)), int(c.pool.get("m113", 0)), int(c.pool.get("medevac", 0))]
	if c.missing_count() > 0:
		s2 += Loc.t("[color=#%s]Вакантних місць: %d — перед боєм поповнимо новобранцями по %d од.[/color]\n") % [UIK.hex(UIK.WOUND), c.missing_count(), Campaign.RECRUIT_COST]
	# roster
	for u in c.units:
		var ready := c.ready_members(u).size()
		var coh: float = float(u.get("cohesion", 1.0))
		var coh_s := "" if coh >= 0.99 else Loc.t("  [color=#%s]згуртованість %d%%[/color]") % [UIK.hex(UIK.WOUND), int(coh * 100.0)]
		s2 += Loc.t("\n[b]%s[/b]  [color=#%s]боєздатні %d/%d[/color]%s\n") % [Loc.t(u["name"]), dim, ready, u["members"].size(), coh_s]
		var line := ""
		for id in u["members"]:
			var sd: Dictionary = c.soldiers[id]
			var rk: Dictionary = Campaign.rank_of(int(sd["xp"]))
			var stc := UIK.hex(UIK.TEXT)
			var tag := ""
			match sd["status"]:
				"recovering":
					stc = UIK.hex(UIK.WOUND)
					tag = Loc.t(" (лікування)")
				"kia":
					stc = "777777"
					tag = Loc.t(" (загинув)")
				"mia":
					stc = "777777"
					tag = Loc.t(" (зник безвісти)")
			if sd["status"] in ["ready", "recovering"] and float(sd.get("strain", 0.0)) >= 8.0:
				var sv: float = float(sd["strain"])
				tag += " [color=#%s]· %s[/color]" % [UIK.hex(UIK.ALERT if sv >= 50.0 else UIK.WOUND), Campaign.strain_label(sv)]
			line += "[color=#%s]%s %s %s%s[/color]; " % [stc, rk["short"], Db.ROLES[sd["role"]]["short"], Loc.person(sd["name"]), tag]
		s2 += line + "\n"
	if c.history.size() > 0:
		s2 += Loc.t("\n[color=#%s]Журнал боїв:[/color]\n") % a
		for h in c.history:
			s2 += Loc.t("• %s — %s, оцінка %d, загиблі %d, полонені %d\n") % [h["title"], "успіх" if h["success"] else Loc.t("невдача"), int(h["score"]), int(h["kia"]), int(h["pows"])]
	t.text = s2
	side_box.add_child(t)
	var hb = HBoxContainer.new()
	side_box.add_child(hb)
	var next_ok := c.next_mission_playable() and not c.failed
	var nb = UIK.button(Loc.t("НАСТУПНА МІСІЯ  ▸") if next_ok else (Loc.t("КАМПАНІЮ ПРОВАЛЕНО") if c.failed else Loc.t("НАСТУПНА МІСІЯ У РОЗРОБЦІ")), _go_campaign, 380)
	nb.disabled = not next_ok
	nb.custom_minimum_size.y = 46
	nb.add_theme_font_size_override("font_size", 18)
	hb.add_child(nb)
	var rb = UIK.button(Loc.t("СКИНУТИ КАМПАНІЮ"), Callable(), 190)
	rb.custom_minimum_size.y = 46
	rb.pressed.connect(func():
		if reset_armed:
			Game.campaign.abandon()
			_show_campaign()
		else:
			reset_armed = true
			rb.text = Loc.t("ПІДТВЕРДИТИ СКИДАННЯ"))
	hb.add_child(rb)


func _new_campaign() -> void:
	Game.campaign.start_new(String(Game.settings.get("difficulty", "normal")))
	W.sfx.ui("radio")
	_show_campaign()


func _go_campaign() -> void:
	W.sfx.ui("radio")
	if on_campaign.is_valid():
		on_campaign.call()


func _show_training() -> void:
	_clear()
	_title(Loc.t("НАВЧАННЯ КОМАНДИРА"))
	var done: bool = Game.settings.get("tutorial_done", false)
	var t = UIK.rich(480)
	t.add_theme_font_size_override("normal_font_size", 16)
	var a := UIK.hex(UIK.ACCENT)
	t.text = (Loc.t("Полігон: одне відділення, слабкий противник, без мінометів, FPV і РЕБ противника, без ліміту часу.\n\n") +
		Loc.t("[color=#%s]Ви навчитеся:[/color]\n") +
		Loc.t("  • керувати дроном: політ, поворот, оптичний зум\n") +
		Loc.t("  • вибирати підрозділ і віддавати накази на рух\n") +
		Loc.t("  • ставити гру на тактичну паузу\n") +
		Loc.t("  • шукати противника дроном і позначати цілі\n") +
		Loc.t("  • викликати міномет і штурмувати позицію\n") +
		Loc.t("  • евакуювати пораненого\n") +
		Loc.t("  • зачищати окоп\n\n") +
		Loc.t("Кожен крок пояснює підказка вгорі екрана, кнопки, які треба натиснути, підсвічуються. ") +
		Loc.t("Займає 10–15 хвилин.")) % a
	side_box.add_child(t)
	if done:
		side_box.add_child(UIK.label(Loc.t("✓ Навчання вже пройдено — можна повторити будь-коли."), 15, UIK.GOOD))
	var b = UIK.button(Loc.t("ПОЧАТИ НАВЧАННЯ"), func():
		if on_training.is_valid():
			on_training.call(), 320)
	b.custom_minimum_size.y = 48
	b.add_theme_font_size_override("font_size", 20)
	side_box.add_child(b)


func _show_controls() -> void:
	_clear()
	_title(Loc.t("КЕРУВАННЯ"))
	var t = UIK.rich(480)
	t.add_theme_font_size_override("normal_font_size", 17)
	var a = UIK.hex(UIK.ACCENT)
	var rows = [
		[Loc.t("ЛКМ по підрозділу"), Loc.t("вибрати відділення / техніку (ЛКМ по порожньому — зняти вибір)")],
		[Loc.t("Ctrl+ЛКМ, подвійний клік"), Loc.t("вибрати одного бійця")],
		[Loc.t("Shift+ЛКМ"), Loc.t("додати до вибору")],
		[Loc.t("Рамка ЛКМ (Alt — бійці)"), Loc.t("вибір кількох підрозділів / бійців")],
		[Loc.t("ПКМ по місцевості"), Loc.t("наказ у поточному режимі (один наказ; Shift — залишити режим)")],
		[Loc.t("ПКМ із протягуванням"), Loc.t("розгортання на рубежі з напрямком")],
		[Loc.t("ПКМ по противнику"), Loc.t("позначити ціль, техніка б'є по ній")],
		["1 / 2 / 3 / 8", Loc.t("рух / штурм / утримувати / зачистка (окопу або будівлі)")],
		["N / G / B", Loc.t("піхота: перебіжками / подавлення / за технікою")],
		["V", Loc.t("техніка: лобом → бортом → кормою до противника → вільно")],
		["4 5 6 7", Loc.t("відхід, висадка/посадка, дим, евакуація")],
		[Loc.t("Z / X / C, далі ЛКМ"), Loc.t("міномет / FPV-дрон / димова завіса")],
		["⚙ / F10", Loc.t("налаштування в бою (клавіші, камера)")],
		["WASD / Q,E / PgUp,PgDn", Loc.t("політ дрона (з інерцією), поворот, висота")],
		[Loc.t("Колесо миші"), Loc.t("оптичний зум x1–x10 — дрон НЕ рухається")],
		[Loc.t("Shift+колесо, СКМ"), Loc.t("висота дрона; поворот і нахил камери")],
		["F / H / Tab", Loc.t("супровід / загальний огляд / наступний підрозділ")],
		["Space, [ ]", Loc.t("тактична пауза, швидкість гри")],
	]
	var s = ""
	for r in rows:
		s += "[color=#%s]%s[/color]\n    %s\n" % [a, r[0], r[1]]
	t.text = s
	side_box.add_child(t)


func _show_settings() -> void:
	_clear()
	_title(Loc.t("НАЛАШТУВАННЯ"))
	var sp := SettingsPanel.new()
	side_box.add_child(sp)


func _set_opt(key: String, v) -> void:
	Game.settings[key] = v
	Game.apply_settings()


func _slider(label: String, mn: float, mx: float, val: float, cb: Callable) -> Control:
	var hb = HBoxContainer.new()
	var l = UIK.label(label, 18, UIK.TEXT)
	l.custom_minimum_size.x = 280
	hb.add_child(l)
	var s = HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = 0.05
	s.value = val
	s.custom_minimum_size = Vector2(260, 28)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(cb)
	hb.add_child(s)
	return hb


func _check(label: String, val: bool, cb: Callable) -> Control:
	var c = CheckButton.new()
	c.text = label
	c.button_pressed = val
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 18)
	c.toggled.connect(cb)
	return c
