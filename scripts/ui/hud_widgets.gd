class_name HudWidgets
extends RefCounted
## Custom-drawn HUD widgets: compact command buttons with a hotkey badge and
## an optional counter, and unit cards with real (drawn) strength bars.


## Square command button: hotkey badge top-left, caption at the bottom,
## optional counter top-right (support assets). Dims when disabled.
class CmdButton extends Button:
	var key_text := ""
	var caption := ""
	var count := -1

	func _init(p_key: String, p_caption: String, tip: String) -> void:
		key_text = p_key
		caption = p_caption
		tooltip_text = tip
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(70, 46)
		text = ""

	func set_count(n: int) -> void:
		if n != count:
			count = n
			queue_redraw()

	func _draw() -> void:
		var f: Font = UIK.font if UIK.font else get_theme_default_font()
		var a := 0.38 if disabled else 1.0
		var on := button_pressed
		var cap_col := Color(1.0, 0.92, 0.72, a) if on else Color(UIK.TEXT, a)
		var key_col := Color(UIK.ACCENT, 0.95 * a)
		draw_string(f, Vector2(6, 15), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, key_col)
		draw_string(f, Vector2(0, size.y - 9), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, cap_col)
		if count >= 0:
			var ct := "×%d" % count
			var cc := Color(UIK.GOOD, a) if count > 0 else Color(UIK.DIM, 0.6)
			draw_string(f, Vector2(0, 15), ct, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, 12, cc)


## Unit card for the roster: name, drawn strength bar, status tag and a stripe
## on the left when selected.
class UnitCard extends Button:
	var title := ""
	var frac := 1.0
	var tag := ""
	var tag_col := UIK.DIM
	var sub := ""

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		toggle_mode = true
		custom_minimum_size = Vector2(250, 42)
		text = ""

	func set_state(p_title: String, p_frac: float, p_sub: String, p_tag: String, p_tag_col: Color) -> void:
		if p_title == title and is_equal_approx(p_frac, frac) and p_tag == tag and p_sub == sub:
			return
		title = p_title
		frac = p_frac
		sub = p_sub
		tag = p_tag
		tag_col = p_tag_col
		queue_redraw()

	func _draw() -> void:
		var f: Font = UIK.font if UIK.font else get_theme_default_font()
		var a := 0.4 if disabled else 1.0
		if button_pressed:
			draw_rect(Rect2(0, 0, 3, size.y), UIK.ACCENT)
		draw_string(f, Vector2(10, 17), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(UIK.TEXT, a))
		if sub != "":
			draw_string(f, Vector2(0, 17), sub, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8, 13, Color(UIK.DIM, a))
		# second row: strength bar, status chip on its right
		var y := size.y - 13.0
		var right := size.x - 8.0
		if tag != "":
			var tw := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var r := Rect2(right - tw - 8, y - 4, tw + 8, 14)
			draw_rect(r, Color(tag_col, 0.16 * a))
			draw_string(f, Vector2(r.position.x + 4, r.position.y + 11), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(tag_col, a))
			right = r.position.x - 8.0
		var bw := right - 10.0
		draw_rect(Rect2(10, y, bw, 5), Color(1, 1, 1, 0.08 * a))
		var c := UIK.GOOD if frac > 0.6 else (UIK.WOUND if frac > 0.3 else UIK.ALERT)
		if frac > 0.0:
			draw_rect(Rect2(10, y, bw * clampf(frac, 0.0, 1.0), 5), Color(c, 0.85 * a))


## A titled group of buttons for the command bar.
static func group(title: String) -> Array:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	var l := UIK.label(title, 9, UIK.DIM)
	vb.add_child(l)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	vb.add_child(hb)
	return [vb, hb]


## Bar for rich text: coloured filled part and a dim remainder.
static func rbar(v: float, n: int, col: Color) -> String:
	var k := clampi(int(round(v * n)), 0, n)
	return "[color=#%s]%s[/color][color=#2c3a33]%s[/color]" % [UIK.hex(col), "█".repeat(k), "█".repeat(n - k)]
