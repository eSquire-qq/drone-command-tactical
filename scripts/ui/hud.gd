class_name HUD
extends Control
## In-mission HUD: drone status bar, mission info, roster, selection details,
## command & support panels, message log, minimap, pause indicator.

var markers: Markers
var minimap: Minimap
var rec_label: Label
var obj_label: RichTextLabel
var tele_label: Label
var roster_box: VBoxContainer
var roster_buttons = {}
var sel_text: RichTextLabel
var log_box: VBoxContainer
var mode_buttons = {}
var face_buttons = {}
var inf_group: VBoxContainer
var veh_group: VBoxContainer
var settings_win: Control
var cmd_buttons = {}
var sup_buttons = {}
var hint_label: Label
var pause_label: Label
var speed_btn: Button
var _t = 0.0
var _slow_t = 0.0
var sel_meta: Array = []
var ew_label: Label
var blackout: Control
var bo_status: Label
var bo_launch: Button
var bo_fast: Button
var hide_on_blackout: Array = []
var reticle: Control
var pause_btn: Button
var training: Training
const SIDE_W := 340       # left bottom panel (selection) width
const MINIMAP_W := 246    # minimap panel width incl. padding


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	markers = Markers.new()
	add_child(markers)
	_build_top()
	_build_roster()
	_build_log()
	_build_selection()
	_build_commands()
	_build_minimap()
	hide_on_blackout = [roster_box.get_parent(), sel_panel, cmd_panel, hint_label, minimap.get_parent()]
	_build_blackout()
	var tut := Tutorial.new()
	tut.name = "Tutorial"
	add_child(tut)
	if W.mission.def.objective.get("type", "") == "training":
		training = Training.new()
		training.name = "Training"
		add_child(training)
	# center reticle
	var ret = Reticle.new()
	reticle = ret
	UIK.pin(ret, 0.5, 0.5, 0, 0)
	ret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ret)
	pause_label = UIK.label(Loc.t("‖  ТАКТИЧНА ПАУЗА  ·  SPACE — ПРОДОВЖИТИ"), 20, UIK.ACCENT)
	pause_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	pause_label.add_theme_constant_override("outline_size", 6)
	UIK.pin(pause_label, 0.5, 0.3, 0, 0, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	pause_label.visible = false
	ew_label = UIK.label("", 17, UIK.ALERT)
	UIK.pin(ew_label, 0.5, 0.0, 0, 46, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	ew_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	ew_label.add_theme_constant_override("outline_size", 5)
	ew_label.visible = false
	add_child(ew_label)
	add_child(pause_label)
	Events.message.connect(_on_message)
	Events.selection_changed.connect(_refresh_buttons)


# ------------------------------------------------------------------ layout
func _build_top() -> void:
	var bar = UIK.panel()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.035, 0.03, 0.72)
	sb.border_color = Color(UIK.LINE, 0.35)
	sb.border_width_bottom = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	bar.add_theme_stylebox_override("panel", sb)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 34
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	bar.add_child(hb)
	rec_label = UIK.label("", 13, UIK.TEXT)
	rec_label.custom_minimum_size.x = 210
	hb.add_child(rec_label)
	obj_label = UIK.rich()
	obj_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	obj_label.size_flags_stretch_ratio = 1.4
	obj_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	obj_label.fit_content = false
	obj_label.custom_minimum_size = Vector2(0, 24)
	obj_label.clip_contents = true
	hb.add_child(obj_label)
	tele_label = UIK.label("", 12, UIK.DIM)
	tele_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tele_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tele_label.size_flags_stretch_ratio = 0.75   # the task / contacts line is wider in English
	tele_label.clip_text = true
	tele_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb.add_child(tele_label)
	hb.add_child(VSeparator.new())
	# time controls live in the top bar, away from the orders
	pause_btn = UIK.button("‖", W.command.toggle_pause, 34, Loc.t("Тактична пауза (Space)"))
	speed_btn = UIK.button("x1", _toggle_speed, 40, Loc.t("Швидкість гри ( [ / ] )"))
	var end_btn := UIK.button(Loc.t("ВИЙТИ"), _abort, 70, Loc.t("Завершити місію"))
	var radio_btn := UIK.button(Loc.t("РАДІО"), func() -> void: radio_panel.toggle(), 64, Loc.t("Радіожурнал: усі доповіді підрозділів (R)"))
	var set_btn := UIK.button("⚙", toggle_settings, 34, Loc.t("Налаштування: керування, клавіші, графіка, звук (F10)"))
	for b in [radio_btn, set_btn, pause_btn, speed_btn, end_btn]:
		b.custom_minimum_size.y = 26
		b.add_theme_font_size_override("font_size", 13)
		hb.add_child(b)


func _soft_panel() -> PanelContainer:
	var p = UIK.panel()
	var sb: StyleBoxFlat = (p.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	sb.bg_color = Color(0.03, 0.045, 0.04, 0.62)
	sb.border_color = Color(0, 0, 0, 0)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _build_roster() -> void:
	var p := _soft_panel()
	p.position = Vector2(10, 44)
	add_child(p)
	roster_box = VBoxContainer.new()
	roster_box.add_theme_constant_override("separation", 4)
	p.add_child(roster_box)
	roster_box.add_child(UIK.label(Loc.t("ПІДРОЗДІЛИ  ·  Tab"), 10, UIK.DIM))


var log_panel: PanelContainer
var radio_panel: RadioPanel


func _build_log() -> void:
	log_panel = _soft_panel()
	UIK.pin(log_panel, 1.0, 0.0, -10, 44, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	log_panel.custom_minimum_size = Vector2(430, 0)
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.visible = false
	add_child(log_panel)
	log_box = VBoxContainer.new()
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_box.add_theme_constant_override("separation", 2)
	log_panel.add_child(log_box)
	radio_panel = RadioPanel.new()
	add_child(radio_panel)


var sel_panel: PanelContainer
var help_panel: PanelContainer
var cmd_panel: PanelContainer


func _layout_commands() -> void:
	var left := 10.0
	if sel_panel.visible:
		left = sel_panel.position.x + sel_panel.size.x + 12.0
	var mm: Control = minimap.get_parent()
	var right: float = (mm.position.x if mm.visible else size.x - 10.0) - 12.0
	var avail := maxf(right - left, 100.0)
	var ps := cmd_panel.get_combined_minimum_size()
	cmd_panel.size = ps
	var k := clampf(avail / ps.x, 0.55, 1.0)
	cmd_panel.scale = Vector2(k, k)
	cmd_panel.position = Vector2(left + (avail - ps.x * k) * 0.5, size.y - 10.0 - ps.y * k)
	var hs := hint_label.get_combined_minimum_size()
	hint_label.size = hs
	hint_label.position = Vector2(left + (avail - hs.x) * 0.5, cmd_panel.position.y - hs.y - 2.0)


func _build_selection() -> void:
	sel_panel = UIK.panel()
	UIK.pin(sel_panel, 0.0, 1.0, 10, -10, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	sel_panel.custom_minimum_size = Vector2(SIDE_W, 0)
	sel_panel.visible = false
	add_child(sel_panel)
	sel_text = UIK.rich(SIDE_W - 20)
	sel_text.mouse_filter = Control.MOUSE_FILTER_STOP
	sel_text.meta_underlined = false
	sel_text.meta_clicked.connect(_on_member_clicked)
	sel_panel.add_child(sel_text)
	# full controls reference: F1
	help_panel = UIK.panel()
	UIK.pin(help_panel, 0.5, 0.45, 0, 0, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	help_panel.visible = false
	add_child(help_panel)
	var ht = UIK.rich(760)
	var a := UIK.hex(UIK.ACCENT)
	ht.text = (Loc.t("[color=#%s][b]КЕРУВАННЯ[/b][/color]   (F1 — закрити)\n\n") % a
		+ Loc.t("[color=#%s]Дрон[/color]       WASD — політ, Q/E — поворот, PgUp/PgDn — висота, колесо — зум\n") % a
		+ Loc.t("           F — супровід вибраних, H — загальний огляд\n")
		+ Loc.t("[color=#%s]Вибір[/color]      ЛКМ — підрозділ / техніка, рамка ЛКМ — кілька (Alt — бійці), Tab — наступний\n") % a
		+ Loc.t("           Ctrl+ЛКМ або 2×клік — один боєць; ЛКМ по порожньому — зняти вибір\n")
		+ Loc.t("[color=#%s]Накази[/color]     ПКМ по місцевості — наказ; ПКМ із протягуванням — рубіж; ПКМ по ворогу — вогонь по цілі\n") % a
		+ Loc.t("           Піхота: 1 рух · 2 штурм · 3 тримати · 8 зачистка · N перебіжки · G подавлення · B за технікою\n")
		+ Loc.t("           Техніка: 1 рух · 2 штурм · G подавлення · V лобом / бортом / кормою; 4 відхід · 5 десант · 6 дим · 7 евакуація\n")
		+ Loc.t("           Режим наказу діє на один наказ (Shift — залишити); клавіші й камера — ⚙ / F10\n")
		+ Loc.t("[color=#%s]Підтримка[/color]  Z міномет · X FPV · C димова завіса, далі ЛКМ по цілі (ПКМ — скасувати)\n") % a
		+ Loc.t("[color=#%s]Зв'язок[/color]    R — радіожурнал (доповіді надходять із затримкою; під РЕБ — уривками)\n") % a
		+ Loc.t("[color=#%s]Час[/color]        Space — тактична пауза, [ / ] — швидкість") % a)
	help_panel.add_child(ht)


func _build_commands() -> void:
	# the bar sits in the gap between the left panel and the minimap; its
	# position and scale are recomputed every frame (_layout_commands), so it
	# fits any window size and UI scale without covering either of them
	hint_label = UIK.label("", 13, UIK.ACCENT)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint_label.add_theme_constant_override("outline_size", 5)
	add_child(hint_label)
	var p = UIK.panel()
	cmd_panel = p
	add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	p.add_child(row)
	# infantry and vehicles get their own command groups; each shows when
	# the selection has such units (both for a mixed selection)
	var units_col := VBoxContainer.new()
	units_col.add_theme_constant_override("separation", 4)
	row.add_child(units_col)
	inf_group = VBoxContainer.new()
	units_col.add_child(inf_group)
	var gi := HudWidgets.group(Loc.t("ПІХОТА  —  наказ: ПКМ по місцевості"))
	inf_group.add_child(gi[0])
	for m in [["move", "move", Loc.t("РУХ"), Loc.t("Переміщення в точку. ПКМ із протягуванням — рубіж із напрямком.")],
			["assault", "assault", Loc.t("ШТУРМ"), Loc.t("Висування перебіжками з вогневим прикриттям; по будинку — зачистка будівлі")],
			["hold", "hold", Loc.t("ТРИМАТИ"), Loc.t("Зайняти укриття в точці та вести вогонь; по будинку — зайняти будівлю")],
			["clear", "clear", Loc.t("ЗАЧИСТКА"), Loc.t("Зачистити окоп до точки або будівлю")],
			["bound", "bound", Loc.t("ПЕРЕБІЖКИ"), Loc.t("Рух перебіжками: одна підгрупа біжить ~12 м, друга прикриває вогнем, далі навпаки")],
			["suppress", "suppress", Loc.t("ПОДАВЛ."), Loc.t("Вогонь на подавлення по точці ~30 с (де противник або може бути)")]]:
		var bt := HudWidgets.CmdButton.new(_kname(m[1]), m[2], m[3])
		bt.toggle_mode = true
		bt.pressed.connect(W.command.set_mode.bind(m[0]))
		gi[1].add_child(bt)
		mode_buttons[m[0]] = bt
	for c in [["follow_veh", "follow_veh", Loc.t("ЗА ТЕХН."), W.command.cmd_follow_vehicle, Loc.t("Рух двома колонами за машиною: техніка прикриває піхоту й тримає її крок. Виберіть відділення (і машину)")],
			["retreat", "retreat", Loc.t("ВІДХІД"), W.command.cmd_retreat, Loc.t("Відійти до району збору")],
			["mount", "mount", Loc.t("ВИСАДКА@кнопка"), W.command.cmd_mount_toggle, Loc.t("Висадка / посадка десанту")],
			["smoke", "smoke", Loc.t("ДИМ"), W.command.cmd_smoke, Loc.t("Відділення ставить димову завісу ручними гранатами")],
			["evac", "evac", Loc.t("ЕВАКУАЦІЯ@кнопка"), W.command.cmd_evac, Loc.t("Викликати евакуацію поранених вибраного підрозділу")],
			["resupply", "resupply", Loc.t("НАБОЇ"), W.command.cmd_resupply, Loc.t("Відділення йде до найближчої нашої БМП / M113 і поповнює магазини й гранати з її запасу. На «Тримати» біля машини поповнюються самі")]]:
		var bt := HudWidgets.CmdButton.new(_kname(c[1]), c[2], c[4])
		bt.pressed.connect(c[3])
		gi[1].add_child(bt)
		cmd_buttons[c[0]] = bt
	veh_group = VBoxContainer.new()
	units_col.add_child(veh_group)
	var gv := HudWidgets.group(Loc.t("ТЕХНІКА  —  наказ: ПКМ по місцевості"))
	veh_group.add_child(gv[0])
	for m in [["move", "move", Loc.t("РУХ"), Loc.t("Переміщення в точку")],
			["assault", "assault", Loc.t("ШТУРМ"), Loc.t("Повільне висування з вогнем на ходу, без відходу після влучання")],
			["suppress", "suppress", Loc.t("ПОДАВЛ."), Loc.t("Вогонь на подавлення по точці ~30 с")]]:
		var bt := HudWidgets.CmdButton.new(_kname(m[1]), m[2], m[3])
		bt.toggle_mode = true
		bt.pressed.connect(W.command.set_mode.bind(m[0]))
		gv[1].add_child(bt)
		mode_buttons["veh_" + m[0]] = bt
	for f in [["front", Loc.t("ЛОБОМ"), Loc.t("Тримати лобову броню до противника (найміцніша)")],
			["side", Loc.t("БОРТОМ"), Loc.t("Стати бортом до противника (напр., щоб прикрити піхоту за машиною) — борт уразливіший")],
			["rear", Loc.t("КОРМОЮ"), Loc.t("Стати кормою до противника (десант виходить з кормових дверей у бік від вогню) — корма найслабша")]]:
		var bt := HudWidgets.CmdButton.new(_kname("face") if f[0] == "front" else "", f[1], f[2] + Loc.t(". Ще раз — вільно."))
		bt.toggle_mode = true
		bt.pressed.connect(func() -> void:
			W.command.cmd_face("" if _face_of_selection() == f[0] else f[0]))
		gv[1].add_child(bt)
		face_buttons[f[0]] = bt
	for c in [["veh_retreat", "retreat", Loc.t("ВІДХІД"), W.command.cmd_retreat, Loc.t("Відійти до району збору")],
			["veh_mount", "mount", Loc.t("ДЕСАНТ"), W.command.cmd_mount_toggle, Loc.t("Висадити / прийняти десант")],
			["veh_smoke", "smoke", Loc.t("ДИМ"), W.command.cmd_smoke, Loc.t("Поставити димову завісу перед машиною")]]:
		var bt := HudWidgets.CmdButton.new(_kname(c[1]), c[2], c[4])
		bt.pressed.connect(c[3])
		gv[1].add_child(bt)
		cmd_buttons[c[0]] = bt
	row.add_child(VSeparator.new())
	var g3 := HudWidgets.group(Loc.t("ПІДТРИМКА  —  ЛКМ по цілі"))
	row.add_child(g3[0])
	for s in [["mortar", "Z", Loc.t("МІНОМЕТ"), Loc.t("Мінометний наліт по області (~12 с, розкид)")],
			["fpv", "X", "FPV", Loc.t("FPV-дрон по позначеній цілі")],
			["smoke", "C", Loc.t("ДИМ.ЗАВ."), Loc.t("Димові снаряди: закривають огляд ~45 с")]]:
		var b := HudWidgets.CmdButton.new(_kname({"mortar": "mortar", "fpv": "fpv", "smoke": "smoke_barrage"}[s[0]]), s[2], s[3])
		b.toggle_mode = true
		b.pressed.connect(W.command.set_tool.bind(s[0]))
		g3[1].add_child(b)
		sup_buttons[s[0]] = b


func _kname(action: String) -> String:
	return OS.get_keycode_string(Game.key_for(action))


func _face_of_selection() -> String:
	for o in W.command.selection:
		if o is Vehicle:
			return o.face_mode
	return ""


## Settings during the battle (⚙ / F10): the game pauses while it is open.
func toggle_settings() -> void:
	if settings_win and is_instance_valid(settings_win):
		settings_win.queue_free()
		settings_win = null
		get_tree().paused = _paused_before
		_rebuild_key_captions()
		return
	_paused_before = get_tree().paused
	get_tree().paused = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	settings_win = dim
	var p := UIK.panel()
	UIK.pin(p, 0.5, 0.5, 0, 0, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	dim.add_child(p)
	var vb := VBoxContainer.new()
	p.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t := UIK.label(Loc.t("НАЛАШТУВАННЯ  (гра на паузі)"), 20, UIK.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIK.button(Loc.t("ЗАКРИТИ  ✕"), toggle_settings, 130))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(720, minf(640.0, size.y - 140.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var sp := SettingsPanel.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(sp)


var _paused_before := false


func _rebuild_key_captions() -> void:
	for k in mode_buttons.keys():
		var act: String = String(k).trim_prefix("veh_")
		mode_buttons[k].key_text = _kname(act)
		mode_buttons[k].queue_redraw()
	for k in cmd_buttons.keys():
		var act2: String = {"veh_retreat": "retreat", "veh_mount": "mount", "veh_smoke": "smoke"}.get(k, k)
		cmd_buttons[k].key_text = _kname(act2)
		cmd_buttons[k].queue_redraw()
	if face_buttons.has("front"):
		face_buttons["front"].key_text = _kname("face")
		face_buttons["front"].queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and Game.action_for(event.physical_keycode) == "settings":
		toggle_settings()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and Game.action_for(event.physical_keycode) == "help":
		help_panel.visible = not help_panel.visible
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and Game.action_for(event.physical_keycode) == "radio" and not event.ctrl_pressed:
		radio_panel.toggle()
		get_viewport().set_input_as_handled()


func _build_blackout() -> void:
	blackout = Control.new()
	blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blackout.mouse_filter = Control.MOUSE_FILTER_STOP
	blackout.visible = false
	add_child(blackout)
	move_child(blackout, 1)
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.02, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blackout.add_child(bg)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blackout.add_child(center)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	center.add_child(vb)
	var t = UIK.label(Loc.t("НЕМАЄ СИГНАЛУ"), 46, UIK.ALERT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var t2 = UIK.label(Loc.t("Зв'язок з БПЛА втрачено (РЕБ противника). Підрозділи діють за останніми наказами —\nви бачите лише радіоповідомлення."), 17, UIK.TEXT)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t2)
	bo_status = UIK.label("", 18, UIK.ACCENT)
	bo_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(bo_status)
	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	bo_launch = UIK.button(Loc.t("ЗАПУСТИТИ ЗАПАСНИЙ ДРОН"), func(): W.ew.launch_spare(), 300)
	bo_launch.custom_minimum_size.y = 44
	hb.add_child(bo_launch)
	bo_fast = UIK.button(Loc.t("ПРИСКОРИТИ ЧАС x4"), func(): W.command.set_speed(1.0 if Engine.time_scale > 1.5 else 4.0), 220)
	bo_fast.custom_minimum_size.y = 44
	hb.add_child(bo_fast)
	hb.add_child(UIK.button(Loc.t("ЗАВЕРШИТИ МІСІЮ"), _abort, 200))


func _update_blackout() -> void:
	var down: bool = W.ew != null and W.ew.drone_down
	blackout.visible = down
	reticle.visible = not down
	for c in hide_on_blackout:
		c.visible = not down
	sel_panel.visible = not down and sel_text.text != ""
	if not down:
		return
	if W.ew.relaunch_t >= 0.0:
		bo_status.text = Loc.t("Запасний дрон у дорозі: %d с") % int(ceil(W.ew.relaunch_t))
	elif W.ew.spares > 0:
		bo_status.text = Loc.t("Запасних дронів: %d") % W.ew.spares
	else:
		bo_status.text = Loc.t("Запасних дронів немає — бій завершиться без спостереження.")
	bo_launch.disabled = not W.ew.can_relaunch()
	bo_fast.text = Loc.t("ЗВИЧАЙНА ШВИДКІСТЬ") if Engine.time_scale > 1.5 else Loc.t("ПРИСКОРИТИ ЧАС x4")


func _build_minimap() -> void:
	var p = UIK.panel()
	UIK.pin(p, 1.0, 1.0, -10, -10, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN)
	add_child(p)
	minimap = Minimap.new()
	minimap.def = W.mission.def
	p.add_child(minimap)


func _toggle_speed() -> void:
	W.command.set_speed(2.0 if Engine.time_scale < 1.5 else 1.0)


func _abort() -> void:
	W.mission.end_mission("abort")


# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("hud", t0)


func _process_body(delta: float) -> void:
	if not visible:
		return
	_layout_commands()
	var lw := clampf((size.x - 700.0) * 0.5 - 20.0, 240.0, 430.0)
	if absf(log_panel.custom_minimum_size.x - lw) > 1.0:
		log_panel.custom_minimum_size.x = lw
		for l in log_box.get_children():
			(l as Control).custom_minimum_size.x = lw - 20.0
		log_panel.reset_size()
	# keep the log pinned to the right edge whatever its width
	log_panel.offset_right = -10.0
	log_panel.offset_left = -10.0 - log_panel.size.x
	# if a hint / training card is on screen and the log would run under it,
	# the log moves down below the card
	var top := 44.0
	var lx := size.x - 10.0 - log_panel.size.x
	for n in [get_node_or_null("Tutorial"), training]:
		if n != null and n.visible and n.position.x + n.size.x > lx - 8.0:
			top = maxf(top, n.position.y + n.size.y + 8.0)
	log_panel.offset_top = top
	if radio_panel.visible:
		var mm: Control = minimap.get_parent()
		var bottom: float = (mm.position.y if mm.visible else size.y - 10.0) - 10.0
		var rw := maxf(lw, 340.0)
		radio_panel.position = Vector2(size.x - 10.0 - rw, top)
		radio_panel.size = Vector2(rw, clampf(bottom - top, 160.0, 420.0))
	_t += delta
	var rec = "●" if fmod(_t, 1.0) < 0.55 else "○"
	var mt: float = W.mission.t
	rec_label.text = "%s REC  T+%s   %s %s%s" % [rec, UIK.mmss(mt), Game.wx("icon"), Game.wx("name"),
		(Loc.t("   вітер ") + W.field.wind_text()) if W.field else ""]
	rec_label.add_theme_color_override("font_color", UIK.ALERT if fmod(_t, 1.0) < 0.55 else UIK.TEXT)
	var c = W.cam
	var hdg = int(fposmod(-rad_to_deg(c.yaw), 360.0))
	var alt = c.cam.global_position.y - W.grid.height_at(c.cam.global_position.x, c.cam.global_position.z)
	var lk: float = W.ew.link if W.ew else 1.0
	tele_label.text = Loc.t("ВИС %d м · %d м/с · КУРС %03d° · x%.1f · %d м · ЗВ'ЯЗОК %s %d%%") % [
		int(alt), int(round(c.speed)), hdg, c.zoom, int(c.dist), UIK.bar(lk, 5), int(lk * 100)]
	reticle.queue_redraw()
	tele_label.add_theme_color_override("font_color", UIK.DIM if lk >= EwSystem.DEGRADED else (UIK.WOUND if lk > 0.35 else UIK.ALERT))
	_update_blackout()
	ew_label.visible = lk < EwSystem.DEGRADED and fmod(_t, 1.0) < 0.7 and not W.ew.drone_down
	if W.ew and W.ew.rer > 0.35 and lk < EwSystem.DEGRADED:
		ew_label.text = Loc.t("⚠ РЕБ: ПОДАВЛЕННЯ СИГНАЛУ • РЕР ПЕЛЕНГУЄ ДРОН %d%%") % int(W.ew.rer * 100)
	else:
		ew_label.text = Loc.t("⚠ РЕБ: ПОДАВЛЕННЯ СИГНАЛУ — наберіть висоту або відійдіть")
	if W.ew and W.ew.crash_risk_ui > 0.0 and not W.ew.drone_down:
		ew_label.text = Loc.t("⚠ КРИТИЧНИЙ ЗВ'ЯЗОК — РИЗИК ПАДІННЯ ДРОНА! ВІДВЕДІТЬ ДРОН")
		ew_label.visible = true
	pause_label.visible = get_tree().paused
	speed_btn.text = "x%d" % int(Engine.time_scale)
	pause_btn.text = "▶" if get_tree().paused else "‖"
	_slow_t -= delta
	if _slow_t <= 0.0:
		_slow_t = 0.25
		_update_objective()
		_update_roster()
		_update_selection()
		_update_support()
	# fade log
	for l in log_box.get_children():
		var lb = l as Label
		var age: float = Time.get_ticks_msec() / 1000.0 - float(lb.get_meta("t"))
		if age > 12.0:
			lb.modulate.a = clampf(1.0 - (age - 12.0) / 3.0, 0.0, 1.0)
			if age > 15.0:
				lb.queue_free()
	log_panel.visible = log_box.get_child_count() > 0 and not radio_panel.visible


func _update_objective() -> void:
	var m = W.mission
	var phase_txt = Loc.t("ВИСАДКА") if m.phase == MissionManager.Phase.DEPLOY else Loc.t("БІЙ")
	var n: Array = W.intel.counts() if W.intel else [0, 0, 0, 0, 0, 0]
	var tl: float = m.time_left()
	var tcol = UIK.hex(UIK.ALERT if tl < 120.0 else UIK.TEXT)
	var s = Loc.t("[center][color=#%s]%s[/color]  │  ЗАВДАННЯ: %s  │  [color=#%s]%s[/color]  │  КОНТАКТИ: [color=#%s]◆%d ◇%d ?%d[/color]") % [
		UIK.hex(UIK.ACCENT), phase_txt, m.objectives.hud_text(), tcol, UIK.mmss(tl), UIK.hex(UIK.ENEMY), n[0], n[1], n[2] + n[3]]
	if m.status_text != "":
		var scol := UIK.GOOD
		if m.hold_phase and (m.hold_lost_t > 0.0 or m.enemies_in_zone() > 0):
			scol = UIK.ALERT
		elif m.hold_phase and m.counter_sent > 0:
			scol = UIK.WOUND
		s += "  │  [color=#%s]%s[/color]" % [UIK.hex(scol), m.status_text]
	s += "[/center]"
	obj_label.text = s


func _update_roster() -> void:
	var items: Array = []
	for sq in W.squads:
		if sq.side == 0 and sq.kind != "medevac":
			items.append(sq)
	for v in W.vehicles:
		if v.side == 0 and not v.is_medevac and not v.offmap:
			items.append(v)
	for o in items:
		if not roster_buttons.has(o):
			var b := HudWidgets.UnitCard.new()
			b.pressed.connect(W.command.select_object.bind(o))
			roster_box.add_child(b)
			roster_buttons[o] = b
	for o in roster_buttons.keys():
		var b: HudWidgets.UnitCard = roster_buttons[o]
		if not is_instance_valid(o):
			continue
		if o is Squad:
			var n: int = o.members.size()
			var act: int = o.active_count()
			var wia = 0
			for mm in o.members:
				if mm.health == Soldier.H.WOUNDED or mm.health == Soldier.H.INCAP:
					wia += 1
			var waiting := true
			for mm in o.members:
				if not mm.on_board:
					waiting = false
			var tag := ""
			var tcol := UIK.DIM
			var away: bool = o.mounted or waiting
			if o.mounted:
				tag = Loc.t("ДЕСАНТ")
				tcol = UIK.FRIEND
			elif waiting:
				tag = Loc.t("У КОЛОНІ")
			elif wia > 0:
				tag = Loc.t("+%d ПОРАН.") % wia
				tcol = UIK.WOUND
			var alive: int = n if away else act
			b.set_state(o.short, float(alive) / maxf(n, 1), "%d/%d" % [alive, n], tag, tcol)
			b.disabled = act == 0 and not away
			b.button_pressed = o.selected
		else:
			var hpk: float = o.hp / o.max_hp
			var dead: bool = o.state == "destroyed"
			b.set_state(o.vname, 0.0 if dead else hpk, "" if dead else "%d%%" % int(hpk * 100), Loc.t("ЗНИЩЕНО") if dead else "", UIK.ALERT)
			b.disabled = dead
			b.button_pressed = o.selected


## Limited stores of the squad: grenades, launcher rounds, AT rockets, ATGM.
## Rounds left, compact: dim when plenty, amber when saving, red when empty.
func _ammo_tag(m) -> String:
	var r: int = m.rounds_left()
	if r < 0:
		return ""
	var col := UIK.DIM if not m.ammo_low() else (UIK.WOUND if r > 0 else UIK.ALERT)
	return " [color=#%s]·%d[/color]" % [UIK.hex(col), r]


## Why he is not shooting, in combat only.
func _reason_tag(m) -> String:
	var r: String = m.fire_reason()
	if r == "":
		return ""
	return "  [color=#%s]⊘ %s[/color]" % [UIK.hex(UIK.WOUND), r]


func _ammo_line(sq) -> String:
	var g := 0
	var g0 := 0
	var gl := 0
	var gl0 := 0
	var rk := 0
	var sm := 0
	for m in sq.members:
		if m.health >= Soldier.H.DEAD or m.evacuated:
			continue
		g += m.grenades
		g0 += m.nades_start
		gl += m.gl_rounds
		gl0 += m.gl_start
		rk += m.rockets
		sm += m.smokes
	var dim := UIK.hex(UIK.DIM)
	var parts: Array = [Loc.t("[color=#%s]Гранати[/color] %s") % [dim, _stock(g, g0)]]
	if gl0 > 0:
		parts.append(Loc.t("[color=#%s]ВОГ[/color] %s") % [dim, _stock(gl, gl0)])
	parts.append(Loc.t("[color=#%s]РПГ[/color] %d") % [dim, rk])
	parts.append(Loc.t("[color=#%s]Дим[/color] %d") % [dim, sm])
	return "  ".join(parts) + "\n"


func _stock(n: int, n0: int) -> String:
	var col := UIK.GOOD if n * 2 > n0 else (UIK.WOUND if n > 0 else UIK.ALERT)
	return "[color=#%s]%d[/color]/%d" % [UIK.hex(col), n, n0]


func _rank(m) -> String:
	return (m.rank_short + " ") if m.rank_short != "" else ""


## Psychological state tag: hidden when calm (unless `always`).
func _psych_tag(m, always: bool = false) -> String:
	var st: int = m.psych_state()
	if st == Soldier.PS.CALM and not always:
		return ""
	var col := UIK.DIM
	match st:
		Soldier.PS.ALERT:
			col = UIK.TEXT
		Soldier.PS.STRESSED:
			col = UIK.WOUND
		Soldier.PS.SUPPRESSED:
			col = UIK.INCAP if m.supp_level >= 3 else UIK.WOUND
		Soldier.PS.PANICKED:
			col = UIK.ALERT
		Soldier.PS.RECOVERING:
			col = Color(0.55, 0.8, 0.95)
	var name: String = AIConfig.PSY_NAMES[st] if always else AIConfig.PSY_SHORT[st]
	if st == Soldier.PS.SUPPRESSED and not always:
		name = ["", "", Loc.t("▲ під вогнем"), Loc.t("▲▲ притиснутий")][m.supp_level]
	return " [color=#%s]%s[/color]" % [UIK.hex(col), name]


func _health_tag(m) -> String:
	match m.health:
		Soldier.H.HEALTHY:
			return Loc.t("[color=#%s]ЗДОР.[/color]") % UIK.hex(UIK.GOOD)
		Soldier.H.WOUNDED:
			return Loc.t("[color=#%s]ПОРАН.[/color]") % UIK.hex(UIK.WOUND)
		Soldier.H.INCAP:
			return Loc.t("[color=#%s]НЕДІЄЗД. %s[/color]") % [UIK.hex(UIK.INCAP), UIK.mmss(m.bleed)]
	return Loc.t("[color=#888888]ЗАГИН.[/color]")


func _update_selection() -> void:
	var cmd = W.command
	var s = ""
	sel_meta.clear()
	if not cmd.sel_wounded.is_empty():
		var u = cmd.sel_wounded[0]
		s = Loc.t("[b]ПОРАНЕНИЙ[/b]\n%s (%s)\nСтан: %s\n") % [u.display_name(), u.squad.short if u.squad else "", _health_tag(u)]
		s += Loc.t("Евакуація: %s\n") % (Loc.t("позначено") if u.evac_marked else Loc.t("не викликано"))
		s += Loc.t("Медична допомога: %s\n\n") % (Loc.t("надано") if u.aided else Loc.t("немає"))
		s += Loc.t("[color=#%s]Натисніть 7 / ЕВАКУАЦІЯ, щоб викликати машину.[/color]\nДоступно машин: %d") % [UIK.hex(UIK.ACCENT), W.evac.available()]
	elif cmd.selection.is_empty():
		s = ""   # nothing selected: the panel hides (F1 shows the controls)
	elif false:
		s = Loc.t("[color=#%s]Нічого не вибрано.[/color]\n\nЛКМ: підрозділ / техніка\nCtrl+ЛКМ, 2×клік: один боєць\nРамка ЛКМ (Alt: бійці)\nПКМ по місцевості: наказ\nПКМ із протягуванням: рубіж\nПКМ по ворогу: позначити ціль\nЛКМ по пораненому, 7: евакуація\nF супровід, H огляд, Space пауза") % UIK.hex(UIK.DIM)
	else:
		var o = cmd.selection[0]
		if o is Squad:
			var ord = {"move": Loc.t("рух"), "assault": Loc.t("штурм"), "hold": Loc.t("утримання"), "retreat": Loc.t("відхід"), "mount": Loc.t("посадка"), "mounted": Loc.t("у машині"), "defend": Loc.t("оборона"), "clear": Loc.t("зачистка окопу"), "escort": Loc.t("конвой"), "occupy": Loc.t("у будівлі"), "clear_bld": Loc.t("зачистка будівлі")}
			var lead = o.leader()
			s = Loc.t("[b]%s[/b]   [color=#%s]наказ: %s[/color]\n") % [o.sname, UIK.hex(UIK.ACCENT), ord.get(o.order, o.order)]
			var mo: float = o.avg_morale() / 100.0
			var su: float = o.avg_suppression() / 100.0
			s += Loc.t("[color=#%s]Мораль[/color] %s   [color=#%s]Подавлення[/color] %s\n") % [UIK.hex(UIK.DIM), HudWidgets.rbar(mo, 7, UIK.GOOD if mo > 0.5 else UIK.WOUND), UIK.hex(UIK.DIM), HudWidgets.rbar(su, 7, UIK.ALERT if su > 0.5 else UIK.WOUND)]
			s += _ammo_line(o)
			if o.mounted and o.vehicle:
				s += Loc.t("У машині: %s\n") % o.vehicle.vname
			for m in o.members:
				if m.evacuated:
					s += Loc.t("[color=#888888]%s %-9s евакуйовано[/color]\n") % [m.rdata["short"], m.uname]
					continue
				var act = "" if m.health >= Soldier.H.INCAP else Loc.t(String(m.ai.state))
				var sup := ""
				if m.health < Soldier.H.INCAP:
					sup = _psych_tag(m)
				if m.is_active():
					sel_meta.append(m)
					s += "[url=%d]%s%s %-9s[/url] %s%s %s%s%s\n" % [sel_meta.size() - 1, _rank(m), m.rdata["short"], m.uname, _health_tag(m), _ammo_tag(m), act, sup,
						_reason_tag(m) if o.threat_level() > 0 else ""]
				else:
					s += "%s %-9s %s %s%s\n" % [m.rdata["short"], m.uname, _health_tag(m), act, sup]
			if o.leaderless_t > 0.0 and o.active_count() > 0:
				s += Loc.t("[color=#%s]⏳ Командир вибув — відділення без командування ще ~%d с[/color]\n") % [UIK.hex(UIK.ALERT), int(ceil(o.leaderless_t))]
			elif o.acting != null and is_instance_valid(o.acting) and o.acting.is_active():
				s += Loc.t("[color=#%s]Командує %s[/color]\n") % [UIK.hex(UIK.WOUND), o.acting.display_name()]
			if lead == null and o.active_count() > 0:
				s += Loc.t("[color=#%s]Командир вибув — керує старший[/color]\n") % UIK.hex(UIK.WOUND)
			if cmd.selection.size() > 1:
				s += Loc.t("\n+ ще %d підрозділ(и) у вибраному") % (cmd.selection.size() - 1)
			s += Loc.t("[color=#%s]Клік по бійцю — лише він\nShift+клік — додати до вибраних[/color]") % UIK.hex(UIK.DIM)
		elif o is Soldier:
			var ord2 = {"move": Loc.t("рух"), "assault": Loc.t("штурм"), "hold": Loc.t("утримання"), "retreat": Loc.t("відхід"), "mount": Loc.t("посадка"), "clear": Loc.t("зачистка"), "escort": Loc.t("конвой"), "occupy": Loc.t("у будівлі"), "clear_bld": Loc.t("зачистка будівлі")}
			s = Loc.t("[b]ВИБРАНО БІЙЦІВ: %d[/b]  [color=#%s](окремо від відділення)[/color]\n") % [cmd.selection.size(), UIK.hex(UIK.DIM)]
			for u in cmd.selection:
				if not (u is Soldier):
					continue
				sel_meta.append(u)
				s += "[url=%d]%s %-9s[/url] %s %s [color=#%s]%s / %s[/color]\n" % [sel_meta.size() - 1, u.rdata["short"], u.uname, u.squad.short, _health_tag(u), UIK.hex(UIK.ACCENT), ord2.get(u.solo, Loc.t("з відділенням")), Loc.t(String(u.ai.state))]
				if u.health < Soldier.H.INCAP:
					s += Loc.t("   стан:%s%s\n") % [_psych_tag(u, true), (Loc.t("  [color=#%s]пам'ять: %s[/color]") % [UIK.hex(UIK.DIM), ", ".join(Campaign.tr_list(u.memory.slice(-3)))]) if not u.memory.is_empty() else ""]
			s += Loc.t("\n[color=#%s]Наказ усьому відділенню поверне бійців до строю.[/color]") % UIK.hex(UIK.DIM)
		elif o is Vehicle:
			var st = {"ok": Loc.t("справна"), "damaged": Loc.t("пошкоджена"), "immobile": Loc.t("знерухомлена"), "destroyed": Loc.t("знищена")}
			s = "[b]%s[/b]   [color=#%s]%s[/color]\n" % [o.vname, UIK.hex(UIK.ACCENT), o.order_label]
			s += Loc.t("Стан: %s   Міцність %s %d%%\n") % [st[o.state], HudWidgets.rbar(o.hp / o.max_hp, 10, UIK.GOOD if o.hp / o.max_hp > 0.5 else UIK.ALERT), int(o.hp / o.max_hp * 100)]
			s += Loc.t("Десант: %d / %d\n") % [o.passengers.size(), o.capacity()]
			if o.stock_rounds0 > 0:
				s += Loc.t("Боєкомплект для піхоти: набої %s, гранати %s\n") % [_stock(o.stock_rounds, o.stock_rounds0), _stock(o.stock_nades, o.stock_nades0)]
			for wd in o.weapons:
				s += Loc.t("Озброєння: %s (%d)\n") % [wd["w"]["name"], wd["mag"]]
			if o.target != null and W.is_alive_target(o.target):
				s += Loc.t("[color=#%s]Веде вогонь по цілі[/color]\n") % UIK.hex(UIK.ALERT)
			if o.squad:
				s += Loc.t("Приписаний підрозділ: %s") % o.squad.short
	sel_text.text = s
	sel_panel.visible = s != ""


func _update_support() -> void:
	var m = W.mission
	for k in sup_buttons.keys():
		var b: HudWidgets.CmdButton = sup_buttons[k]
		b.set_count(int(m.support[k]))
		b.disabled = int(m.support[k]) <= 0
		b.button_pressed = W.command.tool == k
	var cmd = W.command
	var has_sq = false
	var has_mount = false
	for o in cmd.selection:
		if o is Squad:
			has_sq = true
			if o.vehicle != null:
				has_mount = true
		elif o is Vehicle and o.squad != null:
			has_mount = true
		elif o is Soldier:
			has_sq = true
			if o.squad.vehicle != null:
				has_mount = true
	var has_veh := false
	var has_inf := false
	for o in cmd.selection:
		if o is Vehicle:
			has_veh = true
		else:
			has_inf = true
	inf_group.visible = has_inf or not has_veh
	veh_group.visible = has_veh
	var fm := _face_of_selection()
	for k in face_buttons.keys():
		face_buttons[k].button_pressed = fm == k
	cmd_buttons["follow_veh"].disabled = not has_inf
	cmd_buttons["retreat"].disabled = cmd.selection.is_empty()
	cmd_buttons["mount"].disabled = not has_mount
	var mounted = false
	for o in cmd.selection:
		var sq = o if o is Squad else (o.squad if o is Vehicle else null)
		if sq != null and sq.mounted:
			mounted = true
	var mb: HudWidgets.CmdButton = cmd_buttons["mount"]
	var want := Loc.t("ВИСАДКА") if mounted or not has_mount else Loc.t("ПОСАДКА@десант")
	if mb.caption != want:
		mb.caption = want
		mb.queue_redraw()
	cmd_buttons["smoke"].disabled = not has_sq
	cmd_buttons["evac"].disabled = not has_sq and cmd.sel_wounded.is_empty()
	cmd_buttons["resupply"].disabled = not has_sq
	for k in mode_buttons.keys():
		mode_buttons[k].disabled = cmd.selection.is_empty()
	var order_btn := Loc.t("ПКМ")
	if cmd.tool != "":
		hint_label.text = Loc.t("ВИБІР ЦІЛІ: ЛКМ — застосувати, ПКМ / Esc — скасувати")
	elif not cmd.selection.is_empty():
		var mn = {"move": Loc.t("РУХ"), "assault": Loc.t("ШТУРМ"), "hold": Loc.t("УТРИМУВАТИ"), "clear": Loc.t("ЗАЧИСТКА ОКОПУ (по точці в окопі) або БУДІВЛІ (по будинку)"),
			"bound": Loc.t("ПЕРЕБІЖКИ"), "suppress": Loc.t("ПОДАВЛЕННЯ (по точці, ~30 с)")}
		hint_label.text = Loc.t("Режим наказу: %s — %s по місцевості%s") % [mn.get(cmd.mode, cmd.mode), order_btn,
			"" if cmd.mode == "move" or bool(Game.settings.get("sticky_mode", false)) else Loc.t("  (один наказ; Shift — залишити)")]
	else:
		hint_label.text = Loc.t("Виберіть підрозділ: ЛКМ по бійцях або Tab   ·   F1 — керування   ·   ⚙ — налаштування")


func _on_member_clicked(meta) -> void:
	var i = int(str(meta))
	if i < 0 or i >= sel_meta.size():
		return
	var u = sel_meta[i]
	if not is_instance_valid(u) or not u.is_active():
		return
	var cmd = W.command
	if Input.is_physical_key_pressed(KEY_SHIFT) and cmd.selection.size() > 0 and cmd.selection[0] is Soldier:
		var sl: Array = cmd.selection.duplicate()
		if sl.has(u):
			sl.erase(u)
		else:
			sl.append(u)
		cmd.sel_wounded.clear()
		cmd._set_selection(sl)
	else:
		cmd.select_object(u)
	W.sfx.ui("click")


func _refresh_buttons() -> void:
	for k in mode_buttons.keys():
		mode_buttons[k].button_pressed = W.command.mode == String(k).trim_prefix("veh_")
	_slow_t = 0.0


func _on_message(text: String, kind: String) -> void:
	var col = UIK.TEXT
	match kind:
		"warn":
			col = UIK.WOUND
		"alert":
			col = UIK.ALERT
		"good":
			col = UIK.GOOD
	var l = UIK.label("%s  %s" % [UIK.mmss(W.mission.t if W.mission else 0.0), text], 12, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = log_panel.custom_minimum_size.x - 20.0
	l.set_meta("t", Time.get_ticks_msec() / 1000.0)
	log_box.add_child(l)
	log_panel.visible = true
	while log_box.get_child_count() > 6:
		var old = log_box.get_child(0)
		log_box.remove_child(old)
		old.queue_free()
	if kind == "alert":
		W.sfx.ui("radio")


class Reticle extends Control:
	## Drone sight: optical zoom scale (the drone does not move when zooming),
	## flight vector and autopilot / follow status.
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _draw() -> void:
		var c := Color(0.8, 0.95, 0.85, 0.35)
		var cam = W.cam
		if cam == null:
			return
		var f: Font = UIK.font if UIK.font else get_theme_default_font()
		var g: float = clampf(1.0 / sqrt(cam.zoom), 0.45, 1.0)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(d * 10.0 * g, d * 26.0 * g, c, 1.0)
		draw_arc(Vector2.ZERO, 40.0, -0.3, 0.3, 6, c, 1.0)
		draw_arc(Vector2.ZERO, 40.0, PI - 0.3, PI + 0.3, 6, c, 1.0)
		# optical zoom scale (log) to the right of the sight
		var x0 := 70.0
		var top := -70.0
		var bot := 70.0
		draw_line(Vector2(x0, top), Vector2(x0, bot), c, 1.0)
		for z in [1.0, 2.0, 4.0, 6.0, 10.0]:
			var y: float = lerpf(bot, top, log(z) / log(10.0))
			draw_line(Vector2(x0, y), Vector2(x0 + 6, y), c, 1.0)
			draw_string(f, Vector2(x0 + 9, y + 4), "x%d" % int(z), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c)
		var yz: float = lerpf(bot, top, log(cam.zoom) / log(10.0))
		var zc := Color(1.0, 0.8, 0.35, 0.9)
		draw_colored_polygon(PackedVector2Array([Vector2(x0 - 2, yz), Vector2(x0 - 10, yz - 5), Vector2(x0 - 10, yz + 5)]), zc)
		if cam.zoom_flash > 0.0:
			draw_string(f, Vector2(-70, 62), Loc.t("ОПТИЧНИЙ ЗУМ x%.1f — дрон на місці") % cam.zoom, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, zc)
		# flight vector: where the drone itself is moving
		if cam.speed > 0.4:
			var fwd := Vector2(-sin(cam.yaw), -cos(cam.yaw))
			var right := Vector2(cos(cam.yaw), -sin(cam.yaw))
			var v := Vector2(cam.vel.x, cam.vel.z)
			var local := Vector2(v.dot(right), -v.dot(fwd))
			var tip := local.normalized() * clampf(18.0 + cam.speed * 3.0, 18.0, 60.0)
			var vc := Color(0.45, 0.85, 1.0, 0.8)
			draw_line(Vector2.ZERO, tip, vc, 2.0)
			draw_circle(tip, 3.0, vc)
			draw_string(f, tip + Vector2(6, -4), Loc.t("%d м/с") % int(round(cam.speed)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, vc)
		var mode := ""
		if cam.follow != null:
			mode = Loc.t("СУПРОВІД")
		elif cam.autopilot != null:
			mode = Loc.t("АВТОПІЛОТ → ТОЧКА")
		if mode != "":
			draw_string(f, Vector2(-40, -52), mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.45, 0.85, 1.0, 0.85))
