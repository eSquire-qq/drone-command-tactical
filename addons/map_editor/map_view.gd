@tool
extends HSplitContainer
## «Карта» — the map editor screen (a main-screen tab next to 2D / 3D).
## It shows the open map through its own camera that moves like the game's
## drone camera, and edits it with the mouse:
##   camera  — WASD / arrows or right-drag: move; wheel: zoom; Q / E: turn;
##             middle-drag: turn and tilt; H: whole map; F: to the selected object
##   palette — pick an object on the left, then click on the ground (as many
##             times as you like); lines (trench, road, wire…): click the
##             points one by one, Enter / right click finishes
##   editing — click an object to select it (Inspector shows its settings),
##             drag it to move, R / Shift+wheel to turn, Delete to remove;
##             a selected line shows its points: drag them, Shift+click on
##             the ground adds a point at the end, right click on a point
##             removes it. Ctrl+Z undoes everything.

var plugin: EditorPlugin
var palette: VBoxContainer
var status: Label
var hint: Label
var svc: SubViewportContainer
var sv: SubViewport
var cam: Camera3D
var ghost: MeshInstance3D
var handles: Node3D

# camera rig (map coordinates of the scene root)
var target := Vector3.ZERO
var yaw := 0.0
var pitch := deg_to_rad(55.0)
var dist := 120.0
var _keys := {}

# tools
var mode := "select"          # select / place / line
var item: Array = []          # library item being placed / drawn
var line_node: MapPath = null # line being drawn
var drag_node: Node3D = null
var drag_from := Vector3.ZERO
var drag_point := -1          # dragged point of the selected line
var drag_point_from := Vector3.ZERO
var _rmb_pan := false
var _mmb_turn := false
var _moved := false
var _item_btns: Array = []


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split_offset = 250
	# ---- left: palette
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	add_child(left)
	var tools := HFlowContainer.new()
	left.add_child(tools)
	tools.add_child(_btn("Нова карта…", _new_map, "Створити нову карту з шаблону в maps/custom/ і відкрити її"))
	tools.add_child(_btn("Вся карта (H)", _frame_map, "Показати всю карту"))
	tools.add_child(_btn("Перебудувати землю", _rebuild, "Перебудувати землю зараз"))
	tools.add_child(_btn("Підписи", _toggle_labels, "Показати / сховати підписи"))
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 220
	status.modulate = Color(1.0, 0.85, 0.5)
	left.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	palette = VBoxContainer.new()
	palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(palette)
	var group := ""
	var flow: HFlowContainer = null
	for it in MapLibrary.table():
		if it[0] != group:
			group = it[0]
			var gl := Label.new()
			gl.text = String(group).substr(2).to_upper()
			gl.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
			palette.add_child(gl)
			flow = HFlowContainer.new()
			palette.add_child(flow)
		var b := _btn(it[1], choose.bind(it), "Клацніть, потім клацайте по землі на карті")
		b.toggle_mode = true
		flow.add_child(b)
		_item_btns.append([b, it])
	# ---- right: the view
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Камера: WASD / стрілки або права кнопка — рух · колесо — ближче/далі · Q/E — поворот · середня кнопка — нахил · H — вся карта · F — до вибраного.   " + \
		"Об'єкти: виберіть ліворуч і клацайте по землі · клік по об'єкту — вибрати · тягнути — перемістити · R — повернути · Delete — видалити · Ctrl+Z — скасувати · Esc — вийти з режиму."
	hint.modulate = Color(0.8, 0.8, 0.8)
	right.add_child(hint)
	svc = SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.focus_mode = Control.FOCUS_ALL
	svc.mouse_filter = Control.MOUSE_FILTER_STOP
	right.add_child(svc)
	sv = SubViewport.new()
	sv.handle_input_locally = false
	sv.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	sv.msaa_3d = Viewport.MSAA_2X
	svc.add_child(sv)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.2
	cam.far = 3000.0
	sv.add_child(cam)
	ghost = MeshInstance3D.new()
	var gm := TorusMesh.new()
	gm.inner_radius = 0.8
	gm.outer_radius = 1.2
	ghost.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(1.0, 0.85, 0.2)
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.no_depth_test = true
	ghost.material_override = gmat
	ghost.visible = false
	sv.add_child(ghost)
	handles = Node3D.new()
	sv.add_child(handles)
	svc.gui_input.connect(_on_input)
	svc.set_drag_forwarding(Callable(), _can_drop_data, _drop_data)
	svc.mouse_exited.connect(func() -> void: ghost.visible = false)
	set_process(true)
	_set_status("Відкрийте карту (сцену з коренем MapScene) або натисніть «Нова карта…».")


func _btn(text: String, cb: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


## Undo the last action of the open map (same as Ctrl+Z).
func _undo() -> void:
	var ur := EditorInterface.get_editor_undo_redo()
	var r := root()
	if r:
		ur.get_history_undo_redo(ur.get_object_history_id(r)).undo()


func _set_status(t: String) -> void:
	if status:
		status.text = t


func root() -> MapScene:
	return EditorInterface.get_edited_scene_root() as MapScene


# ------------------------------------------------------------------ camera
func on_scene_changed() -> void:
	var r := root()
	if r:
		_frame_map()
		_set_status("Карта «%s». Виберіть об'єкт ліворуч і клацайте по землі." % r.title)
	_cancel_mode()


func _frame_map() -> void:
	var r := root()
	if r == null:
		return
	target = Vector3.ZERO
	yaw = 0.0
	pitch = deg_to_rad(58.0)
	dist = r.size * 1.05
	svc.grab_focus()


func _focus_selected() -> void:
	var s := _selected()
	if s:
		var l: Vector3 = root().to_local(s.global_position)
		target = Vector3(l.x, 0, l.z)
		dist = minf(dist, 40.0)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var r := root()
	var vp := EditorInterface.get_editor_viewport_3d(0)
	if vp and sv.world_3d != vp.world_3d:
		sv.world_3d = vp.world_3d
	if r == null:
		return
	# keys (only while the view has focus)
	if svc.has_focus():
		var mv := Vector2.ZERO
		if _key(KEY_W) or _key(KEY_UP):
			mv.y -= 1.0
		if _key(KEY_S) or _key(KEY_DOWN):
			mv.y += 1.0
		if _key(KEY_A) or _key(KEY_LEFT):
			mv.x -= 1.0
		if _key(KEY_D) or _key(KEY_RIGHT):
			mv.x += 1.0
		if mv != Vector2.ZERO:
			var sp := dist * 0.9 * delta * (2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
			var f := Vector3(-sin(yaw), 0, -cos(yaw))
			var rt := Vector3(cos(yaw), 0, -sin(yaw))
			target += (rt * mv.x - f * mv.y) * sp
		if _key(KEY_Q):
			yaw += 1.6 * delta
		if _key(KEY_E):
			yaw -= 1.6 * delta
	var h := r.size * 0.5
	target.x = clampf(target.x, -h, h)
	target.z = clampf(target.z, -h, h)
	target.y = r.height_at(target.x, target.z)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var tg: Vector3 = r.to_global(target)
	cam.global_transform = Transform3D(Basis(), tg + off).looking_at(tg, Vector3.UP)
	_update_handles()


func _key(k: int) -> bool:
	return Input.is_key_pressed(k)


## The ground point under the mouse (map coordinates), or null.
func _ground_at(mp: Vector2):
	var r := root()
	if r == null:
		return null
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 3000.0)
	var hit := sv.world_3d.direct_space_state.intersect_ray(q) if sv.world_3d else {}
	var p: Vector3
	if hit.is_empty():
		if absf(dir.y) < 0.001:
			return null
		var t := (r.global_position.y - from.y) / dir.y
		if t < 0.0:
			return null
		p = from + dir * t
	else:
		p = hit["position"]
	var l := r.to_local(p)
	if absf(l.x) > r.size * 0.5 or absf(l.z) > r.size * 0.5:
		return null
	return Vector3(l.x, r.height_at(l.x, l.z), l.z)


# ------------------------------------------------------------------ input
func _on_input(ev: InputEvent) -> void:
	var r := root()
	if r == null:
		return
	if ev is InputEventMouseButton:
		svc.grab_focus()
		var mb := ev as InputEventMouseButton
		var mp := mb.position
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					var k := 0.88 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88
					if mb.shift_pressed and _selected():
						_rotate_selected(15.0 if k < 1.0 else -15.0)
					else:
						dist = clampf(dist * k, 8.0, r.size * 1.6)
				accept_event()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					_moved = false
					_rmb_pan = true
				else:
					_rmb_pan = false
					if not _moved:
						_right_click(mp)
				accept_event()
			MOUSE_BUTTON_MIDDLE:
				_mmb_turn = mb.pressed
				accept_event()
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_left_down(mp, mb)
				else:
					_left_up()
				accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _rmb_pan:
			_moved = _moved or mm.relative.length() > 2.0
			var k := dist * 0.0022
			var f := Vector3(-sin(yaw), 0, -cos(yaw))
			var rt := Vector3(cos(yaw), 0, -sin(yaw))
			target += (-rt * mm.relative.x + f * mm.relative.y) * k
		elif _mmb_turn:
			yaw -= mm.relative.x * 0.006
			pitch = clampf(pitch + mm.relative.y * 0.005, deg_to_rad(15.0), deg_to_rad(89.0))
		_mouse_move(mm.position)
		accept_event()
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		var kk := ev as InputEventKey
		match kk.keycode:
			KEY_ESCAPE:
				_finish_line()
				_cancel_mode()
			KEY_ENTER, KEY_KP_ENTER:
				_finish_line()
			KEY_BACKSPACE:
				_undo_last_point()
			KEY_DELETE:
				_delete_selected()
			KEY_R:
				_rotate_selected(-15.0 if kk.shift_pressed else 15.0)
			KEY_H:
				_frame_map()
			KEY_F:
				_focus_selected()
			_:
				return
		accept_event()


func _mouse_move(mp: Vector2) -> void:
	var g = _ground_at(mp)
	ghost.visible = g != null and (mode == "place" or mode == "line")
	if g != null:
		ghost.global_position = root().to_global(g) + Vector3(0, 0.3, 0)
	if drag_node and g != null:
		var r := root()
		var gp: Vector3 = r.to_global(g)
		drag_node.global_position = Vector3(gp.x, gp.y, gp.z)
		_moved = true
	elif drag_point >= 0 and g != null:
		var ln := _selected() as MapPath
		if ln:
			ln.curve.set_point_position(drag_point, ln.to_local(root().to_global(g)) * Vector3(1, 0, 1))
			_moved = true


func _left_down(mp: Vector2, mb: InputEventMouseButton) -> void:
	var g = _ground_at(mp)
	var r := root()
	match mode:
		"place":
			if g != null:
				_place(item, g)
			return
		"line":
			if g != null:
				_line_point(g)
			return
	# select mode: a point of the selected line?
	var ln := _selected() as MapPath
	if ln:
		var pi := _point_under(ln, mp)
		if pi >= 0:
			drag_point = pi
			drag_point_from = ln.curve.get_point_position(pi)
			_moved = false
			return
		if mb.shift_pressed and g != null:
			_append_point(ln, g)
			return
	var n := _pick(mp, g)
	_select(n)
	if n and not (n is MapPath):
		drag_node = n
		drag_from = n.position
		_moved = false


func _left_up() -> void:
	var ur := plugin.get_undo_redo()
	if drag_node:
		if _moved:
			var to := drag_node.position
			drag_node.position = drag_from
			ur.create_action("Перемістити «%s»" % drag_node.name)
			ur.add_do_property(drag_node, "position", to)
			ur.add_undo_property(drag_node, "position", drag_from)
			ur.commit_action()
		drag_node = null
	if drag_point >= 0:
		var ln := _selected() as MapPath
		if ln and _moved:
			var to := ln.curve.get_point_position(drag_point)
			ln.curve.set_point_position(drag_point, drag_point_from)
			ur.create_action("Перемістити точку лінії")
			ur.add_do_method(ln.curve, "set_point_position", drag_point, to)
			ur.add_undo_method(ln.curve, "set_point_position", drag_point, drag_point_from)
			ur.commit_action()
		drag_point = -1


func _right_click(mp: Vector2) -> void:
	if mode == "line":
		_finish_line()
		return
	if mode == "place":
		_cancel_mode()
		return
	# right click on a point of the selected line removes it
	var ln := _selected() as MapPath
	if ln:
		var pi := _point_under(ln, mp)
		if pi >= 0 and ln.curve.point_count > 2:
			var p := ln.curve.get_point_position(pi)
			var ur := plugin.get_undo_redo()
			ur.create_action("Видалити точку лінії")
			ur.add_do_method(ln.curve, "remove_point", pi)
			ur.add_undo_method(ln.curve, "add_point", p, Vector3.ZERO, Vector3.ZERO, pi)
			ur.commit_action()


# ------------------------------------------------------------------ palette / placing
func choose(it: Array) -> void:
	_finish_line()
	item = it
	var n := MapLibrary.make_node(it[2])
	var is_line := n is MapPath
	n.free()
	mode = "line" if is_line else "place"
	for bi in _item_btns:
		bi[0].set_pressed_no_signal(bi[1] == it)
	if is_line:
		_set_status("«%s»: клацайте точки лінії по землі. Enter або права кнопка — завершити, Backspace — прибрати останню точку, Esc — вийти." % it[1])
	else:
		_set_status("«%s»: клацайте по землі, щоб поставити (можна кілька). Права кнопка або Esc — завершити." % it[1])
	svc.grab_focus()


func _cancel_mode() -> void:
	mode = "select"
	item = []
	line_node = null
	if ghost:
		ghost.visible = false
	for bi in _item_btns:
		bi[0].set_pressed_no_signal(false)
	if root():
		_set_status("Режим вибору: клацніть обʼєкт, щоб змінити; тягніть, щоб перемістити.")


## The folder of a library group inside the map (made on first use).
func _folder_for(r: MapScene, group: String, ur: EditorUndoRedoManager) -> Node3D:
	var nm := String(group).substr(2)
	var f := r.get_node_or_null(NodePath(nm)) as Node3D
	if f:
		return f
	f = Node3D.new()
	f.name = nm
	ur.add_do_method(r, "add_child", f, true)
	ur.add_do_method(f, "set_owner", r)
	ur.add_do_reference(f)
	ur.add_undo_method(r, "remove_child", f)
	return f


func _add_node(n: Node3D, parent: Node3D, label: String) -> void:
	var r := root()
	var ur := plugin.get_undo_redo()
	ur.create_action(label)
	if parent == null:
		parent = _folder_for(r, item[0], ur)
	ur.add_do_method(parent, "add_child", n, true)
	ur.add_do_method(n, "set_owner", r)
	for c in MapScene._all(n):
		ur.add_do_method(c, "set_owner", r)
	ur.add_do_reference(n)
	ur.add_undo_method(parent, "remove_child", n)
	ur.commit_action()
	r.on_child_moved(n)


func _place(it: Array, g: Vector3) -> void:
	var r := root()
	var n := MapLibrary.build(it)
	var parent: Node3D = null
	var sel := _selected()
	if n is MapSlot and sel and (sel is MapEnemyTeam or sel.get_parent() is MapEnemyTeam):
		parent = sel if sel is MapEnemyTeam else sel.get_parent()
	# nature looks better a little varied
	if n is MapTreeline or n is MapBush or n is MapCrater or n is MapBale or n is MapWreck:
		n.rotation.y = randf() * TAU if not (n is MapTreeline) else 0.0
	var gp: Vector3 = r.to_global(g)
	if parent:
		n.position = parent.global_transform.affine_inverse() * gp
	else:
		var f := r.get_node_or_null(NodePath(String(it[0]).substr(2))) as Node3D
		n.position = (f.global_transform.affine_inverse() * gp) if f else g
	_add_node(n, parent, "Поставити «%s»" % it[1])
	_set_status("Поставлено «%s». Клацайте ще, або права кнопка / Esc — завершити." % it[1])


func _line_point(g: Vector3) -> void:
	var r := root()
	if line_node == null or not is_instance_valid(line_node) or not line_node.is_inside_tree():
		var n := MapLibrary.build(item) as MapPath
		n.curve = Curve3D.new()
		n.position = Vector3.ZERO
		var f := r.get_node_or_null(NodePath(String(item[0]).substr(2))) as Node3D
		var local: Vector3 = (f.global_transform.affine_inverse() * r.to_global(g)) if f else g
		n.curve.add_point(local * Vector3(1, 0, 1))
		_add_node(n, null, "Почати лінію «%s»" % item[1])
		line_node = n
		_select(n)
		_set_status("«%s»: перша точка є. Клацайте далі; Enter / права кнопка — завершити." % item[1])
		return
	_append_point(line_node, g)


func _append_point(ln: MapPath, g: Vector3) -> void:
	var p := ln.to_local(root().to_global(g)) * Vector3(1, 0, 1)
	var ur := plugin.get_undo_redo()
	ur.create_action("Додати точку лінії")
	ur.add_do_method(ln.curve, "add_point", p)
	ur.add_undo_method(ln.curve, "remove_point", ln.curve.point_count)
	ur.commit_action()


func _undo_last_point() -> void:
	if mode == "line" and line_node and line_node.curve.point_count > 1:
		_undo()


func _finish_line() -> void:
	if line_node and is_instance_valid(line_node):
		if line_node.curve.point_count < 2:
			# a line needs two points: drop the unfinished one
			_undo()
			_set_status("Лінія потребує щонайменше двох точок — прибрано.")
		else:
			_set_status("Лінію «%s» завершено (%d точок). Клацніть новий початок або Esc." % [line_node.name, line_node.curve.point_count])
	line_node = null


# ------------------------------------------------------------------ selection / editing
func _selected() -> Node3D:
	var s := EditorInterface.get_selection().get_selected_nodes()
	if s.size() == 1 and s[0] is Node3D and root() and root().is_ancestor_of(s[0]):
		return s[0]
	return null


func _select(n) -> void:
	var sel := EditorInterface.get_selection()
	sel.clear()
	if n:
		sel.add_node(n)
		EditorInterface.edit_node(n)
		_set_status("Вибрано «%s» — налаштування праворуч в Inspector. Тягніть — перемістити, R — повернути, Delete — видалити.%s" % [n.name,
			"  Лінія: тягніть жовті точки, Shift+клік — нова точка в кінці, права кнопка на точці — видалити." if n is MapPath else ""])


## The object under the mouse: nearest marker on screen, or the area /
## tree line / line the ground point falls into.
func _pick(mp: Vector2, g) -> Node3D:
	var r := root()
	var best: Node3D = null
	var bd := 22.0
	for n in MapScene._all(r):
		if n is MapNode:
			if cam.is_position_behind(n.global_position):
				continue
			var d := cam.unproject_position(n.global_position + Vector3(0, 0.8, 0)).distance_to(mp)
			if d < bd:
				bd = d
				best = n
		elif n is MapPath and n.curve:
			for i in n.curve.point_count - 1:
				var a: Vector3 = n.global_transform * n.curve.get_point_position(i)
				var b: Vector3 = n.global_transform * n.curve.get_point_position(i + 1)
				a.y = r.preview_height_global(a.x, a.z)
				b.y = r.preview_height_global(b.x, b.z)
				if cam.is_position_behind(a) or cam.is_position_behind(b):
					continue
				var d := Geometry2D.get_closest_point_to_segment(mp, cam.unproject_position(a), cam.unproject_position(b)).distance_to(mp)
				if d < bd:
					bd = d
					best = n
	if best or g == null:
		return best
	# inside a big object (house, tree line, zone)?
	for n in MapScene._all(r):
		if (n is MapHouse or n is MapShed or n is MapTreeline or n is MapArea) and "size" in n:
			var l: Vector3 = r.to_local(n.global_position)
			var d := Vector2(g.x - l.x, g.z - l.z).rotated(n.rotation.y if not (n is MapTreeline or n is MapArea) else 0.0)
			var sz: Vector2 = n.size
			if absf(d.x) <= sz.x * 0.5 and absf(d.y) <= sz.y * 0.5:
				return n
	return null


func _point_under(ln: MapPath, mp: Vector2) -> int:
	for i in ln.curve.point_count:
		var p: Vector3 = ln.global_transform * ln.curve.get_point_position(i)
		p.y = root().preview_height_global(p.x, p.z) + 0.3
		if not cam.is_position_behind(p) and cam.unproject_position(p).distance_to(mp) < 12.0:
			return i
	return -1


func _rotate_selected(deg: float) -> void:
	var s := _selected()
	if s == null or s is MapPath:
		return
	var ur := plugin.get_undo_redo()
	ur.create_action("Повернути «%s»" % s.name)
	ur.add_do_property(s, "rotation", s.rotation + Vector3(0, deg_to_rad(deg), 0))
	ur.add_undo_property(s, "rotation", s.rotation)
	ur.commit_action()


func _delete_selected() -> void:
	var s := _selected()
	var r := root()
	if s == null or s == r:
		return
	var parent := s.get_parent()
	var idx := s.get_index()
	var ur := plugin.get_undo_redo()
	ur.create_action("Видалити «%s»" % s.name)
	ur.add_do_method(parent, "remove_child", s)
	ur.add_undo_method(parent, "add_child", s, true)
	ur.add_undo_method(parent, "move_child", s, idx)
	ur.add_undo_method(s, "set_owner", r)
	for c in MapScene._all(s):
		ur.add_undo_method(c, "set_owner", r)
	ur.add_undo_reference(s)
	ur.commit_action()
	EditorInterface.get_selection().clear()
	r.on_child_moved(s)
	_set_status("Видалено «%s» (Ctrl+Z — повернути)." % s.name)


## Yellow balls on the points of the selected line.
func _update_handles() -> void:
	var ln := _selected() as MapPath
	var want := ln.curve.point_count if ln and ln.curve else 0
	while handles.get_child_count() < want:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.6
		sm.height = 1.2
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.2)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		m.material_override = mat
		handles.add_child(m)
	for i in handles.get_child_count():
		var h := handles.get_child(i) as MeshInstance3D
		h.visible = i < want
		if i < want:
			var p: Vector3 = ln.global_transform * ln.curve.get_point_position(i)
			p.y = root().preview_height_global(p.x, p.z) + 0.3
			h.global_position = p
			h.scale = Vector3.ONE * clampf(dist / 80.0, 0.5, 3.0)


# ------------------------------------------------------------------ drag & drop from the FileSystem
func _can_drop_data(_at: Vector2, data) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("type", "") == "files" and root() != null


func _drop_data(at: Vector2, data) -> void:
	var g = _ground_at(at)
	if g == null:
		return
	for f in data["files"]:
		if String(f).ends_with(".tscn"):
			var n = (load(f) as PackedScene).instantiate()
			if n is Node3D:
				n.scene_file_path = ""
				var r := root()
				n.position = g
				var ur := plugin.get_undo_redo()
				ur.create_action("Поставити «%s»" % n.name)
				ur.add_do_method(r, "add_child", n, true)
				ur.add_do_method(n, "set_owner", r)
				for c in MapScene._all(n):
					ur.add_do_method(c, "set_owner", r)
				ur.add_do_reference(n)
				ur.add_undo_method(r, "remove_child", n)
				ur.commit_action()
				r.on_child_moved(n)
				_select(n)


# ------------------------------------------------------------------ tools
func _rebuild() -> void:
	if root():
		root().rebuild_preview()
		_set_status("Землю перебудовано.")


func _toggle_labels() -> void:
	if root():
		root().show_labels = not root().show_labels


func _new_map() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Нова карта"
	var vb := VBoxContainer.new()
	var l := Label.new()
	l.text = "Імʼя файлу (латиницею, без пробілів):"
	vb.add_child(l)
	var e := LineEdit.new()
	e.text = "moya_karta"
	e.custom_minimum_size.x = 260
	vb.add_child(e)
	dlg.add_child(vb)
	dlg.ok_button_text = "Створити"
	dlg.confirmed.connect(func() -> void:
		var nm := e.text.strip_edges().replace(" ", "_")
		if nm == "":
			return
		var path := "res://maps/custom/%s.tscn" % nm
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://maps/custom"))
		if not FileAccess.file_exists(path):
			var inst: MapScene = (load(MapLibrary.TEMPLATE) as PackedScene).instantiate()
			inst.map_id = nm
			inst.title = nm.to_upper()
			inst.name = nm.capitalize().replace(" ", "")
			var ps := PackedScene.new()
			ps.pack(inst)
			ResourceSaver.save(ps, path)
			inst.free()
			EditorInterface.get_resource_filesystem().scan()
		EditorInterface.open_scene_from_path(path)
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	EditorInterface.get_base_control().add_child(dlg)
	dlg.popup_centered()


# ------------------------------------------------------------------ self test (MAPVIEW_SELFTEST=1)
func selftest() -> void:
	var r := root()
	var out := ProjectSettings.globalize_path("user://")
	for i in 90:
		await get_tree().process_frame
	_frame_map()
	for i in 20:
		await get_tree().process_frame
	sv.get_texture().get_image().save_png(out + "mapview_1.png")
	var count0 := MapScene._all(r).size()
	var by_name := {}
	for it in MapLibrary.table():
		by_name[it[1]] = it
	choose(by_name["Дерево"])
	for p in [Vector3(20, 0, 10), Vector3(24, 0, 12), Vector3(28, 0, 9)]:
		_place(item, p)
	choose(by_name["Будинок (руїна)"])
	_place(item, Vector3(-20, 0, 20))
	var house := _selected_after_place("Будинок (руїна)")
	choose(by_name["Окоп (з траверсами)"])
	for p in [Vector3(-30, 0, -10), Vector3(-15, 0, -12), Vector3(0, 0, -10)]:
		_line_point(p)
	_finish_line()
	choose(by_name["Дорога"])
	for p in [Vector3(40, 0, 70), Vector3(35, 0, 20), Vector3(45, 0, -30)]:
		_line_point(p)
	_finish_line()
	_cancel_mode()
	var count1 := MapScene._all(r).size()
	# select, move, rotate, delete, undo
	_select(house)
	var p0 := house.position
	house.position = p0 + Vector3(6, 0, 0)
	drag_node = house
	drag_from = p0
	_moved = true
	_left_up()
	_rotate_selected(30.0)
	var moved_ok := house.position.distance_to(p0 + Vector3(6, 0, 0)) < 0.01
	var rot_ok := absf(house.rotation.y - deg_to_rad(30.0)) < 0.01
	_delete_selected()
	var deleted := not house.is_inside_tree()
	_undo()
	var restored := house.is_inside_tree()
	print("[MAPVIEW] nodes %d -> %d; moved %s, turned %s, deleted %s, undo restored %s" % [count0, count1, moved_ok, rot_ok, deleted, restored])
	# camera: zoom in on the new things
	target = Vector3(-5, 0, 0)
	dist = 70.0
	yaw = 0.3
	await get_tree().create_timer(4.0).timeout
	for i in 10:
		await get_tree().process_frame
	sv.get_texture().get_image().save_png(out + "mapview_2.png")
	print("[MAPVIEW] shots ", out, "mapview_1.png / mapview_2.png")
	get_tree().quit()


func _selected_after_place(nm: String) -> Node3D:
	for n in MapScene._all(root()):
		if n is Node3D and String(n.name).begins_with(nm):
			return n
	return null
