class_name SettingsPanel
extends VBoxContainer
## All settings in one panel: graphics, sound, interface and CONTROLS (order
## mode, camera speed, key bindings). Used by the main menu and
## by the in-battle settings window (HUD ⚙). Changes apply at once and are
## saved (Game.apply_settings / save_settings).

var _listen := ""             # action waiting for a key
var _key_btns := {}


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var st: Dictionary = Game.settings
	_head(Loc.t("МОВА / LANGUAGE"))
	add_child(_choice("", Loc.LANGS, Loc.lang(), _set_lang))
	if not _in_menu():
		add_child(UIK.label(Loc.t("Частина тексту зміниться після виходу в меню."), 14, UIK.DIM))
	_head(Loc.t("КЕРУВАННЯ"))
	add_child(UIK.label(Loc.t("Миша: ЛКМ — вибір / рамка, ПКМ — наказ, ПКМ із протягуванням — рубіж, ПКМ по ворогу — ціль"), 15, UIK.DIM))
	add_child(_check(Loc.t("Режим наказу (штурм, зачистка…) лишається після наказу"), bool(st.get("sticky_mode", false)),
		func(on): _set_opt("sticky_mode", on)))
	add_child(_check(Loc.t("Показувати, куди піде підрозділ і де стане кожен боєць"), bool(st.get("move_preview", true)),
		func(on): _set_opt("move_preview", on)))
	add_child(_slider(Loc.t("Швидкість камери"), 0.4, 2.5, float(st.get("cam_speed", 1.0)), func(v): _set_opt("cam_speed", v)))
	add_child(_slider(Loc.t("Швидкість повороту (Q / E)"), 0.4, 2.5, float(st.get("cam_turn", 1.0)), func(v): _set_opt("cam_turn", v)))
	add_child(_check(Loc.t("Прокрутка камери біля країв екрана"), st["edge_scroll"], func(on):
		Game.settings["edge_scroll"] = on
		Game.apply_settings()))
	_head(Loc.t("КЛАВІШІ (клацніть і натисніть нову; Esc — скасувати)"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	add_child(grid)
	for a in Game.KEY_ACTIONS:
		var l := UIK.label(a[1], 16, UIK.TEXT)
		l.custom_minimum_size.x = 260
		grid.add_child(l)
		var b := UIK.button(OS.get_keycode_string(Game.key_for(a[0])), _listen_for.bind(a[0]), 150)
		b.custom_minimum_size.y = 30
		grid.add_child(b)
		_key_btns[a[0]] = b
	add_child(UIK.button(Loc.t("Типові клавіші"), func():
		Game.settings["keys"] = {}
		Game.save_settings()
		_refresh_keys(), 240))
	add_child(UIK.label(Loc.t("Камера: WASD / стрілки — політ, Q / E — поворот, PgUp / PgDn — висота, колесо — зум, СКМ — нахил."), 14, UIK.DIM))
	_head(Loc.t("ГРАФІКА"))
	var qh := HBoxContainer.new()
	add_child(qh)
	var qdesc := UIK.label("", 14, UIK.DIM)
	qdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	qdesc.custom_minimum_size.x = 480
	var qbtns := {}
	var pick_q := func(k: String) -> void:
		Game.settings["quality"] = k
		Game.apply_settings()
		for key in qbtns.keys():
			qbtns[key].button_pressed = key == k
		qdesc.text = Game.QUALITY[k]["desc"]
	for k in Game.QUALITY_ORDER:
		var b := UIK.button(Game.QUALITY[k]["name"], pick_q.bind(k), 150)
		b.toggle_mode = true
		b.custom_minimum_size.y = 36
		qh.add_child(b)
		qbtns[k] = b
	add_child(qdesc)
	pick_q.call(String(st.get("quality", "high")))
	add_child(_check(Loc.t("Повноекранний режим"), st["fullscreen"], func(on):
		Game.settings["fullscreen"] = on
		Game.apply_settings()))
	add_child(_check(Loc.t("Ефект відео з дрона (шум, віньєтка)"), st["drone_fx"], func(on):
		Game.settings["drone_fx"] = on
		Game.apply_settings()))
	add_child(_slider(Loc.t("Масштаб інтерфейсу"), 0.9, 1.4, st["ui_scale"], func(v):
		Game.settings["ui_scale"] = v
		Game.apply_settings()))
	_head(Loc.t("ЗВУК"))
	add_child(_slider(Loc.t("Загальна гучність"), 0.0, 1.0, st["volume"], func(v): _set_opt("volume", v)))
	add_child(_slider(Loc.t("Бойові звуки"), 0.0, 1.0, st.get("vol_sfx", 1.0), func(v): _set_opt("vol_sfx", v)))
	add_child(_slider(Loc.t("Оточення і техніка"), 0.0, 1.0, st.get("vol_amb", 0.8), func(v): _set_opt("vol_amb", v)))
	add_child(_slider(Loc.t("Інтерфейс і радіо"), 0.0, 1.0, st.get("vol_ui", 0.8), func(v): _set_opt("vol_ui", v)))
	_head(Loc.t("ПІДКАЗКИ"))
	add_child(_check(Loc.t("Підказки навчання"), st.get("hints", true), func(on): _set_opt("hints", on)))
	add_child(UIK.button(Loc.t("Показати всі підказки знову"), func():
		Game.settings["hints_seen"] = []
		Game.settings["hints"] = true
		Game.save_settings(), 360))


func _head(t: String) -> void:
	var l := UIK.label(t, 15, UIK.ACCENT)
	add_child(l)


func _in_menu() -> bool:
	return W.ui != null and W.ui.screen is MainMenu


func _set_lang(code: String) -> void:
	if code == Loc.lang():
		return
	Game.settings["lang"] = code
	Game.save_settings()
	Loc.apply(code)
	if _in_menu():
		W.ui.call_deferred("relang_menu")   # rebuild the menu in the new language


func _set_opt(key: String, v) -> void:
	Game.settings[key] = v
	Game.apply_settings()
	Game.save_settings()


func _listen_for(action: String) -> void:
	_listen = action
	_key_btns[action].text = Loc.t("натисніть…")


func _refresh_keys() -> void:
	for a in _key_btns.keys():
		_key_btns[a].text = OS.get_keycode_string(Game.key_for(a))


func _input(event: InputEvent) -> void:
	if _listen == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var k: int = event.physical_keycode
	if k != KEY_ESCAPE:
		if k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_PAGEUP, KEY_PAGEDOWN, KEY_SHIFT, KEY_CTRL, KEY_ALT]:
			_key_btns[_listen].text = Loc.t("зайнято камерою")
			_listen = ""
			return
		var keys: Dictionary = Game.settings.get("keys", {})
		# a key can do one thing: the action that had it gets this one's old key
		var old := Game.key_for(_listen)
		for a in Game.KEY_ACTIONS:
			if a[0] != _listen and Game.key_for(a[0]) == k:
				keys[a[0]] = old
		keys[_listen] = k
		Game.settings["keys"] = keys
		Game.save_settings()
	_listen = ""
	_refresh_keys()


func _choice(label: String, opts: Array, cur: String, cb: Callable) -> Control:
	var hb := HBoxContainer.new()
	var l := UIK.label(label, 17, UIK.TEXT)
	l.custom_minimum_size.x = 80
	hb.add_child(l)
	var g := ButtonGroup.new()
	for o in opts:
		var b := UIK.button(o[1], func(): cb.call(o[0]), 0)
		b.toggle_mode = true
		b.button_group = g
		b.button_pressed = o[0] == cur
		b.custom_minimum_size.y = 32
		hb.add_child(b)
	return hb


func _slider(label: String, mn: float, mx: float, val: float, cb: Callable) -> Control:
	var hb := HBoxContainer.new()
	var l := UIK.label(label, 17, UIK.TEXT)
	l.custom_minimum_size.x = 280
	hb.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = 0.05
	s.value = val
	s.custom_minimum_size = Vector2(240, 28)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(cb)
	hb.add_child(s)
	return hb


func _check(label: String, val: bool, cb: Callable) -> Control:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = val
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 17)
	c.toggled.connect(cb)
	return c
