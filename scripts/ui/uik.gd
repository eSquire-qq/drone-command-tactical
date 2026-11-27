class_name UIK
extends RefCounted
## UI kit: palette, theme and small widget helpers for the military HUD look.

const TEXT := Color(0.80, 0.93, 0.82)
const DIM := Color(0.52, 0.62, 0.55)
const ACCENT := Color(1.0, 0.76, 0.30)
const ALERT := Color(1.0, 0.36, 0.26)
const GOOD := Color(0.45, 0.95, 0.55)
const FRIEND := Color(0.35, 0.72, 1.0)
const ENEMY := Color(1.0, 0.30, 0.24)
const WOUND := Color(1.0, 0.82, 0.22)
const INCAP := Color(1.0, 0.50, 0.12)
const LINE := Color(0.45, 0.75, 0.55, 0.45)
const FONT_BONUS := 2
const BG := Color(0.035, 0.055, 0.045, 0.84)

static var _theme: Theme
static var font: Font


static func theme() -> Theme:
	if _theme:
		return _theme
	var th := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Lucida Console", "DejaVu Sans Mono", "Courier New", "monospace"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font = f
	th.default_font = f
	th.default_font_size = 16
	var panel := _sb(BG, LINE, 1, 8)
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("panel", "Panel", panel)
	th.set_stylebox("normal", "Button", _sb(Color(0.06, 0.10, 0.08, 0.92), Color(0.45, 0.75, 0.55, 0.55), 1, 6))
	th.set_stylebox("hover", "Button", _sb(Color(0.10, 0.18, 0.13, 0.95), Color(0.6, 0.95, 0.7, 0.9), 1, 6))
	th.set_stylebox("pressed", "Button", _sb(Color(0.35, 0.27, 0.08, 0.95), ACCENT, 1, 6))
	th.set_stylebox("hover_pressed", "Button", _sb(Color(0.40, 0.31, 0.10, 0.95), ACCENT, 1, 6))
	th.set_stylebox("disabled", "Button", _sb(Color(0.05, 0.06, 0.06, 0.8), Color(0.3, 0.35, 0.32, 0.4), 1, 6))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color(0.95, 1.0, 0.95))
	th.set_color("font_pressed_color", "Button", Color(1.0, 0.92, 0.7))
	th.set_color("font_hover_pressed_color", "Button", Color(1.0, 0.92, 0.7))
	th.set_color("font_disabled_color", "Button", Color(0.4, 0.45, 0.42))
	th.set_color("font_color", "Label", TEXT)
	th.set_color("default_color", "RichTextLabel", TEXT)
	th.set_font("normal_font", "RichTextLabel", f)
	var bold := FontVariation.new()
	bold.base_font = f
	bold.variation_embolden = 0.8
	th.set_font("bold_font", "RichTextLabel", bold)
	th.set_stylebox("background", "ProgressBar", _sb(Color(0.05, 0.07, 0.06, 0.9), Color(0.3, 0.45, 0.35, 0.6), 1, 0))
	th.set_stylebox("fill", "ProgressBar", _sb(Color(0.40, 0.80, 0.50, 0.9), Color(0, 0, 0, 0), 0, 0))
	# tooltips in the same style as the panels
	th.set_stylebox("panel", "TooltipPanel", _sb(Color(0.03, 0.05, 0.04, 0.96), ACCENT.darkened(0.3), 1, 8))
	th.set_color("font_color", "TooltipLabel", TEXT)
	th.set_font_size("font_size", "TooltipLabel", 15)
	var vsep := StyleBoxLine.new()
	vsep.color = Color(LINE, 0.35)
	vsep.vertical = true
	vsep.thickness = 1
	th.set_stylebox("separator", "VSeparator", vsep)
	th.set_constant("separation", "VSeparator", 12)
	th.set_constant("separation", "HBoxContainer", 6)
	th.set_constant("separation", "VBoxContainer", 4)
	_theme = th
	return th


static func _sb(bg: Color, border: Color, bw: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(margin)
	s.set_corner_radius_all(3 if margin > 0 else 0)
	s.corner_detail = 3
	return s


static func label(text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size + FONT_BONUS)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func rich(min_w: int = 0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size.x = min_w
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, cb: Callable, min_w: int = 0, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 30)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func hex(c: Color) -> String:
	return c.to_html(false)


static func bar(v: float, n: int = 10) -> String:
	var k := clampi(int(round(v * n)), 0, n)
	return "■".repeat(k) + "□".repeat(n - k)


static func mmss(t: float) -> String:
	var s := int(t)
	return "%02d:%02d" % [s / 60, s % 60]


## Pins a control to an anchor point (0..1) with a pixel offset; grow
## directions decide which way it expands from its minimum size.
static func pin(c: Control, ax: float, ay: float, ox: float, oy: float,
		gx: int = Control.GROW_DIRECTION_END, gy: int = Control.GROW_DIRECTION_END) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_right = ox
	c.offset_top = oy
	c.offset_bottom = oy
	c.grow_horizontal = gx
	c.grow_vertical = gy
