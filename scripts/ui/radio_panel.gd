class_name RadioPanel
extends PanelContainer
## RADIO LOG: every report of the mission, scrollable, with a filter. Shows
## when the report was sent, how late it came and how reliable it is.

var filter := "all"
var text: RichTextLabel
var scroll: ScrollContainer
var _dirty := true
var _btns := {}


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.045, 0.04, 0.86)
	sb.border_color = Color(UIK.LINE, 0.5)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t := UIK.label(Loc.t("РАДІОЖУРНАЛ  ·  R"), 12, UIK.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := UIK.button("✕", func() -> void: toggle(), 26)
	x.custom_minimum_size.y = 22
	head.add_child(x)
	var fb := HBoxContainer.new()
	fb.add_theme_constant_override("separation", 4)
	vb.add_child(fb)
	var g := ButtonGroup.new()
	for k in RadioSystem.FILTERS.keys():
		var b := UIK.button(RadioSystem.FILTERS[k][0], _set_filter.bind(k), 0)
		b.toggle_mode = true
		b.button_group = g
		b.button_pressed = k == filter
		b.custom_minimum_size.y = 22
		b.add_theme_font_size_override("font_size", 11)
		fb.add_child(b)
		_btns[k] = b
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	text = UIK.rich(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 12)
	scroll.add_child(text)
	Events.radio_entry.connect(func(_e) -> void: _dirty = true)


func toggle() -> void:
	visible = not visible
	_dirty = true


func _set_filter(k: String) -> void:
	filter = k
	_dirty = true


func _process(_d: float) -> void:
	if not visible or not _dirty or W.radio == null:
		return
	_dirty = false
	var at_bottom: bool = scroll.scroll_vertical >= int(scroll.get_v_scroll_bar().max_value - scroll.size.y - 30.0)
	text.text = entries_bbcode(W.radio.entries, filter)
	if at_bottom:
		(func() -> void: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)).call_deferred()


static func entries_bbcode(entries: Array, flt: String) -> String:
	var types: Array = RadioSystem.FILTERS.get(flt, ["", []])[1]
	var s := ""
	var n := 0
	for e in entries:
		if not types.is_empty() and not (e["type"] in types):
			continue
		n += 1
		var col := UIK.TEXT
		match String(e["kind"]):
			"warn":
				col = UIK.WOUND
			"alert":
				col = UIK.ALERT
			"good":
				col = UIK.GOOD
		var tag: String = RadioSystem.TYPES.get(e["type"], "")
		var extra := ""
		if float(e["delay"]) >= 2.5:
			extra += Loc.t("  [color=#%s]⌛ +%d с[/color]") % [UIK.hex(UIK.DIM), int(e["delay"])]
		match String(e["rel"]):
			"приблизно":
				extra += Loc.t("  [color=#%s]≈ приблизно[/color]") % UIK.hex(UIK.DIM)
			"непевно":
				extra += Loc.t("  [color=#%s]? непевно[/color]") % UIK.hex(UIK.WOUND)
			"перешкоди":
				extra += Loc.t("  [color=#%s]~ перешкоди[/color]") % UIK.hex(UIK.INCAP)
		s += "[color=#%s]%s[/color] [color=#%s]%s[/color]  [color=#%s]%s[/color]%s\n" % [
			UIK.hex(UIK.DIM), UIK.mmss(float(e["sent"])), UIK.hex(Color(UIK.ACCENT, 0.8)), tag, UIK.hex(col), String(e["text"]), extra]
	if n == 0:
		s = Loc.t("[color=#%s]Повідомлень немає.[/color]") % UIK.hex(UIK.DIM)
	return s
