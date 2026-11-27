class_name Training
extends PanelContainer
## Step-by-step training on the "ПОЛІГОН" map. A card at the top of the screen
## explains one thing at a time; the game checks by itself when the player has
## done it (no "next" clicking), outlines the HUD buttons involved and shows a
## marker on the ground where the order should go. Nothing pauses on its own;
## every step can be skipped.

const DONE_HOLD := 1.4    # seconds the "✓ done" state stays before the next step

var steps: Array = []
var idx := -1
var done_t := -1.0
var title_l: Label
var count_l: Label
var body_l: Label
var status_l: Label
var next_btn: Button
var bar: ProgressBar
var hl: Control
var hl_targets: Array = []
var marker: Node3D
var marker_label: Label3D

# progress trackers
var cam_start := Vector3.ZERO
var yaw_start := 0.0
var max_zoom := 1.0
var saw_pause := false
var wounded = null
var info_ok := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIK.pin(self, 0.5, 0.0, 0, 48, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	custom_minimum_size = Vector2(660, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	count_l = UIK.label("", 13, UIK.DIM)
	top.add_child(count_l)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(UIK.button(Loc.t("Пропустити крок"), _skip, 0, Loc.t("Перейти до наступного кроку")))
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	vb.add_child(bar)
	title_l = UIK.label("", 21, UIK.ACCENT)
	vb.add_child(title_l)
	body_l = UIK.label("", 15, UIK.TEXT)
	body_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_l.custom_minimum_size.x = 640
	vb.add_child(body_l)
	var bottom := HBoxContainer.new()
	vb.add_child(bottom)
	status_l = UIK.label("", 14, UIK.DIM)
	status_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(status_l)
	next_btn = UIK.button(Loc.t("ДАЛІ  ▸"), func(): info_ok = true, 140)
	bottom.add_child(next_btn)
	hl = Control.new()
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hl.top_level = true
	hl.draw.connect(_draw_hl)
	add_child(hl)
	_build_marker()
	_make_steps()
	cam_start = W.cam.cam.global_position
	yaw_start = W.cam.yaw
	_go(0)


# ------------------------------------------------------------------ steps
func _squad():
	var l: Array = W.mission.friendly_squads
	return l[0] if l.size() > 0 else null


func _team(name: String):
	for sq in W.enemy_ai.squads:
		if sq.team_name == name:
			return sq
	return null


func _team_down(name: String) -> bool:
	var sq = _team(name)
	if sq == null:
		return true
	for m in sq.members:
		if m.is_active() and not m.surrendered and not m.captured:
			return false
	return true


func _team_seen(name: String) -> bool:
	var sq = _team(name)
	if sq == null:
		return false
	for m in sq.members:
		if m.model.visible or m.marked:
			return true
	return false


func _hud():
	return get_parent()


func _make_steps() -> void:
	var A := Vector3(-14, 0, 52)
	steps = [
		{"title": Loc.t("КОМАНДИР ЧЕРЕЗ ДРОН"),
			"text": Loc.t("Ви бачите бій очима розвідувального дрона «ОКО» і віддаєте накази. Бійці самі шукають укриття, обирають цілі й стріляють — ваша справа вирішувати, КУДИ і ЯК діяти.\nВідділення В-1 зараз висувається на вихідний рубіж."),
			"info": true},
		{"title": Loc.t("ПОЛІТ ДРОНА"),
			"text": Loc.t("Клавіші W A S D — політ дрона. Дрон має інерцію і реагує не миттєво, як справжній.\nПролетіть трохи вперед, у бік поля."),
			"check": func(): return Vector2(W.cam.cam.global_position.x - cam_start.x, W.cam.cam.global_position.z - cam_start.z).length() > 22.0,
			"status": Loc.t("Очікую: пролетіть ~20 м")},
		{"title": Loc.t("ПОВОРОТ"),
			"text": Loc.t("Q та E — поворот дрона, PgUp / PgDn — висота. Поверніть дрон, щоб оглянути місцевість."),
			"check": func(): return absf(angle_difference(W.cam.yaw, yaw_start)) > 0.5,
			"enter": func(): yaw_start = W.cam.yaw,
			"status": Loc.t("Очікую: поверніть дрон на ~30°")},
		{"title": Loc.t("ОПТИЧНИЙ ЗУМ"),
			"text": Loc.t("Колесо миші — оптичний зум до x10. Сам дрон при цьому лишається на місці: так можна роздивитися противника здалеку, не підлітаючи під його РЕБ і вогонь.\nНаблизьте зображення хоча б до x3."),
			"check": func(): return max_zoom >= 3.0,
			"status": Loc.t("Очікую: зум x3")},
		{"title": Loc.t("ВИБІР ПІДРОЗДІЛУ"),
			"text": Loc.t("Клацніть лівою кнопкою по «В-1» у списку підрозділів зліва вгорі або по будь-якому бійцю на місцевості. Tab — перемикання між підрозділами."),
			"targets": func(): return _hud().roster_buttons.values(),
			"check": func(): return _squad() != null and _squad() in W.command.selection and not _squad().mounted and _squad().active_count() > 0,
			"status": Loc.t("Очікую: вибране відділення В-1")},
		{"title": Loc.t("НАКАЗ НА РУХ"),
			"text": Loc.t("Режим «1 РУХ» уже ввімкнено. Клацніть ПРАВОЮ кнопкою по руїнах, позначених жовтим маркером «А», — відділення піде туди й займе укриття."),
			"marker": A, "marker_text": Loc.t("А — РУЇНИ"),
			"targets": func(): return [_hud().mode_buttons.get("move")],
			"check": func(): return _squad() != null and _squad().order in ["move", "hold"] and Vector2(_squad().order_pos.x - A.x, _squad().order_pos.z - A.z).length() < 12.0,
			"status": Loc.t("Очікую: наказ на рух до точки А")},
		{"title": Loc.t("ТАКТИЧНА ПАУЗА"),
			"text": Loc.t("Пробіл — тактична пауза. На паузі можна спокійно оглянути поле бою й віддати накази, час стоїть.\nПоставте гру на паузу, а потім зніміть її."),
			"targets": func(): return [_hud().pause_btn],
			"enter": func(): saw_pause = false,
			"check": func(): return saw_pause and not get_tree().paused,
			"status": Loc.t("Очікую: пауза → продовжити")},
		{"title": Loc.t("ВИХІД НА РУБІЖ"),
			"text": Loc.t("Поки відділення рухається, час можна прискорити кнопкою «x1 / x2». Дочекайтеся, поки бійці зайдуть у руїни."),
			"marker": A, "marker_text": Loc.t("А — РУЇНИ"),
			"targets": func(): return [_hud().speed_btn],
			"check": func(): return _squad() != null and Vector2(_squad().center().x - A.x, _squad().center().z - A.z).length() < 11.0,
			"status": Loc.t("Очікую: відділення в точці А")},
		{"title": Loc.t("РОЗВІДКА"),
			"text": Loc.t("Попереду, приблизно за 80 м на північ, має бути пост противника. Пролетіть дроном уперед і роздивіться поле в зум. Противник замаскований — поки він не стріляє, його важко помітити.\nВиявлений противник позначається червоним ромбом."),
			"check": func(): return _team_seen(Loc.t("Пост")) or _team_down(Loc.t("Пост")),
			"status": Loc.t("Очікую: противника виявлено")},
		{"title": Loc.t("ПОЗНАЧИТИ ЦІЛЬ"),
			"text": Loc.t("Клацніть ПРАВОЮ кнопкою по червоному ромбу — ціль буде позначено. Бійці й техніка обстрілюють позначені цілі в першу чергу, а FPV-дрон б'є саме по них."),
			"check": func(): return _any_marked() or _team_down(Loc.t("Пост")),
			"status": Loc.t("Очікую: ціль позначено (ПКМ)")},
		{"title": Loc.t("МІНОМЕТ"),
			"text": Loc.t("Натисніть Z (або кнопку «МІНОМЕТ» внизу), потім клацніть лівою кнопкою по посту. Міни летять ~12 с і лягають з розкидом — не викликайте вогонь ближче 40 м до своїх."),
			"targets": func(): return [_hud().sup_buttons.get("mortar")],
			"check": func(): return int(W.mission.support_used.get("mortar", 0)) > 0 or _team_down(Loc.t("Пост")),
			"status": Loc.t("Очікую: виклик міномета")},
		{"title": Loc.t("ШТУРМ"),
			"text": Loc.t("Виберіть В-1, увімкніть «2 ШТУРМ» і клацніть ПРАВОЮ кнопкою по посту. Відділення піде перебіжками: одна група прикриває вогнем, друга біжить. Перед відкритим полем можна поставити дим — «6 ДИМ» або C."),
			"marker": Vector3(13, 0, -34), "marker_text": "ПОСТ",
			"targets": func(): return [_hud().mode_buttons.get("assault"), _hud().cmd_buttons.get("smoke")],
			"check": func(): return _team_down(Loc.t("Пост")),
			"status": Loc.t("Очікую: пост знищено або взято")},
		{"title": Loc.t("ПОРАНЕНИЙ"),
			"text": Loc.t("Снайпер! Один із бійців важко поранений (помаранчевий хрест і таймер). Медик відділення надасть першу допомогу, але врятує лише евакуація.\nКлацніть по пораненому, потім натисніть 7 або «ЕВАКУАЦІЯ»."),
			"enter": func(): _wound_someone(),
			"targets": func(): return [_hud().cmd_buttons.get("evac")],
			"check": func(): return wounded == null or not is_instance_valid(wounded) or wounded.evac_marked or wounded.evacuated,
			"status": Loc.t("Очікую: евакуацію викликано")},
		{"title": Loc.t("ЗАЧИСТКА ОКОПУ"),
			"text": Loc.t("Біля північної посадки — короткий окоп з двома бійцями противника. Виберіть В-1, увімкніть «8 ЗАЧИСТКА» і клацніть ПРАВОЮ кнопкою по окопу. Бійці зайдуть у траншею колоною і за кожен ріг спершу кинуть гранату."),
			"marker": Vector3(-42, 0, -68), "marker_text": Loc.t("ОКОП"),
			"targets": func(): return [_hud().mode_buttons.get("clear")],
			"check": func(): return _team_down(Loc.t("Окоп")),
			"status": Loc.t("Очікую: окоп зачищено")},
		{"title": Loc.t("НАВЧАННЯ ЗАВЕРШЕНО"),
			"text": Loc.t("Ви вмієте все головне. Ще кілька порад:\n• Ctrl+клік або подвійний клік — окремий боєць; рамка мишею — кілька.\n• F — дрон супроводжує вибраних, H — загальний огляд.\n• У бою бережіть людей: у кампанії загиблі вибувають назавжди, а поранені пропускають наступний бій."),
			"info": true, "finish": true},
	]


func _any_marked() -> bool:
	for u in W.units:
		if u.side == 1 and u.marked:
			return true
	return false


func _wound_someone() -> void:
	var sq = _squad()
	if sq == null:
		return
	for m in sq.members:
		if m.is_active() and m.role != "leader" and m.role != "medic":
			wounded = m
			W.damage.set_health(m, Soldier.H.INCAP, null, Loc.t("снайпер"))
			Events.msg(Loc.t("Снайпер! %s важко поранений.") % m.display_name(), "alert")
			return


# ------------------------------------------------------------------ flow
func _go(i: int) -> void:
	idx = i
	done_t = -1.0
	info_ok = false
	if idx >= steps.size():
		_finish()
		return
	var st: Dictionary = steps[idx]
	if st.has("enter"):
		(st["enter"] as Callable).call()
	count_l.text = Loc.t("НАВЧАННЯ • КРОК %d / %d") % [idx + 1, steps.size()]
	bar.max_value = steps.size()
	bar.value = idx
	title_l.text = String(st["title"])
	body_l.text = String(st["text"])
	status_l.text = String(st.get("status", ""))
	status_l.add_theme_color_override("font_color", UIK.DIM)
	next_btn.visible = st.get("info", false)
	next_btn.text = Loc.t("ЗАВЕРШИТИ НАВЧАННЯ") if st.get("finish", false) else Loc.t("ДАЛІ  ▸")
	next_btn.custom_minimum_size.x = 220 if st.get("finish", false) else 140
	hl_targets = (st["targets"] as Callable).call() if st.has("targets") else []
	if st.has("marker"):
		var p: Vector3 = st["marker"]
		marker.global_position = W.grid.ground(p)
		marker_label.text = String(st.get("marker_text", ""))
		marker.visible = true
	else:
		marker.visible = false
	W.sfx.ui("radio")
	if "--autotest" in OS.get_cmdline_user_args():
		print("[TRAINING] step %d/%d «%s» t=%d" % [idx + 1, steps.size(), title_l.text, int(W.time)])


func _skip() -> void:
	W.sfx.ui("click")
	_go(idx + 1)


func _finish() -> void:
	Game.settings["tutorial_done"] = true
	Game.save_settings()
	marker.visible = false
	W.mission.end_mission("completed")


func _process(delta: float) -> void:
	if idx < 0 or idx >= steps.size():
		return
	var dt := delta / maxf(Engine.time_scale, 0.01)
	if get_tree().paused:
		saw_pause = true
	max_zoom = maxf(max_zoom, W.cam.zoom)
	var st: Dictionary = steps[idx]
	if done_t >= 0.0:
		done_t += dt
		if done_t > DONE_HOLD:
			_go(idx + 1)
	elif st.get("info", false):
		if info_ok:
			if st.get("finish", false):
				_finish()
			else:
				_go(idx + 1)
	elif (st["check"] as Callable).call():
		done_t = 0.0
		status_l.text = Loc.t("✓ Виконано")
		status_l.add_theme_color_override("font_color", UIK.GOOD)
		W.sfx.ui("click")
	# target list may change (roster buttons appear late)
	if st.has("targets") and Engine.get_process_frames() % 30 == 0:
		hl_targets = (st["targets"] as Callable).call()
	hl.visible = not hl_targets.is_empty() and done_t < 0.0
	if hl.visible:
		hl.position = Vector2.ZERO
		hl.size = get_viewport_rect().size
		hl.queue_redraw()
	if marker.visible:
		var k := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.005)
		marker.scale = Vector3(k, 1.0, k)


func _draw_hl() -> void:
	var a := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008)
	var col := Color(UIK.ACCENT, a)
	var inv := hl.get_global_transform_with_canvas().affine_inverse()
	for c in hl_targets:
		if c is Control and is_instance_valid(c) and c.is_visible_in_tree():
			var r: Rect2 = c.get_global_rect()
			hl.draw_rect(Rect2(inv * r.position, r.size).grow(3.0), col, false, 3.0)


## Ground marker: a pulsing ring, a thin beam and a caption, visible from far.
func _build_marker() -> void:
	marker = Node3D.new()
	W.map.add_child(marker)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.2
	tm.outer_radius = 3.6
	tm.rings = 32
	tm.ring_segments = 6
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(UIK.ACCENT, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	ring.material_override = mat
	ring.position.y = 0.4
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(ring)
	var beam := MeshInstance3D.new()
	beam.mesh = MF.box(0.12, 9.0, 0.12)
	beam.material_override = mat
	beam.position.y = 4.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(beam)
	marker_label = Label3D.new()
	marker_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker_label.no_depth_test = true
	marker_label.fixed_size = true
	marker_label.pixel_size = 0.0012
	marker_label.font_size = 30
	marker_label.outline_size = 8
	marker_label.modulate = UIK.ACCENT
	if UIK.font:
		marker_label.font = UIK.font
	marker_label.position.y = 10.0
	marker.add_child(marker_label)
	marker.visible = false
