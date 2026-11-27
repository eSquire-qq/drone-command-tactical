class_name Tutorial
extends PanelContainer
## Contextual hints: a short card the first time the player meets a
## mechanic. Each hint is shown once (remembered in settings), never pauses
## the game, and can be switched off in the settings.

const HINTS_UK := {
	"camera": ["КАМЕРА ДРОНА", "WASD — політ дрона (з інерцією), Q/E — поворот, PgUp/PgDn — висота.\nКолесо миші — оптичний зум: дрон лишається на місці. F — супровід вибраного, H — огляд."],
	"select": ["НАКАЗИ", "ПКМ по місцевості — наказ вибраному. Режими: 1 рух, 2 штурм, 3 утримувати, 8 зачистка окопу.\nCtrl+ЛКМ або подвійний клік — окремий боєць. Бійці самі обирають укриття й ціль."],
	"spotted": ["ПРОТИВНИКА ВИЯВЛЕНО", "Червоні ромби — противник, якого бачить дрон або бійці. ПКМ по ньому — позначити ціль:\nпозначені цілі обстрілюються в першу чергу і доступні для FPV-дрона."],
	"contact": ["ШТУРМ ПЕРЕБІЖКАМИ", "Під час наказу «Штурм» відділення ділиться навпіл: одна група прикриває вогнем, друга перебігає.\nПід щільним вогнем краще спершу подавити противника."],
	"suppressed": ["ПІД ВОГНЕМ (⚠)", "Придушені бійці лягають і майже не стріляють, мораль падає. Допоможе дим (6 / C),\nміномет (Z) або обхід через укриття — лісосмуги, балку, вирви."],
	"support": ["ЗАСОБИ ПІДТРИМКИ", "Z — міномет: заявка ~12 с, великий розкид. X — FPV-дрон: точний, але його можуть збити або заглушити.\nC — димова завіса. Засоби купуються в плануванні."],
	"ew": ["РЕБ ПРОТИВНИКА", "Що ближче і нижче дрон до позиції, то гірший зв'язок: шум у відео, а при критичному рівні дрон може впасти.\nЗум не впливає на зв'язок — спостерігайте здалеку з наближенням."],
	"drone_lost": ["ДРОН ВТРАЧЕНО", "Бій триває за останніми наказами — ви чуєте лише радіо. Якщо у плануванні було взято запасний дрон,\nзапустіть його кнопкою на екрані: він прилетить приблизно за 90 с."],
	"wounded": ["ВАЖКЕ ПОРАНЕННЯ", "Помаранчевий хрест — боєць не може рухатися, біля нього таймер до смерті від ран.\nЛКМ по пораненому і 7 — виклик евакуації. Медик відділення надасть першу допомогу, якщо безпечно."],
	"trench": ["БІЙ В ОКОПІ", "Режим 8 «Зачистка»: ПКМ по точці в окопі — бійці йдуть траншеєю колоною,\nза поворот спершу кидають гранату або прострілюють кут."],
	"mines": ["МІННЕ ПОЛЕ", "Виявлені міни позначено червоними хрестиками; маршрути їх оминають.\nПротивник залишає проходи для себе — шукайте їх дроном."],
	"prisoner": ["ПОЛОНЕНИЙ", "Оточений противник зі зламаною мораллю здається. Боєць конвоює його в тил —\nце підвищує оцінку операції."],
}
static var HINTS = HINTS_UK   # the current language (Loc.localize_all)

var queue: Array = []
var shown_t := 0.0
var title_l: Label
var body_l: Label
var _check_t := 0.0
var _start_t := 0.0
var _hl: Control          # pulsing frames around the HUD controls the hint talks about
var _hl_targets: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIK.pin(self, 0.5, 0.0, 0, 48, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)
	custom_minimum_size = Vector2(620, 0)
	var vb := VBoxContainer.new()
	add_child(vb)
	title_l = UIK.label("", 15, UIK.ACCENT)
	vb.add_child(title_l)
	body_l = UIK.label("", 14, UIK.TEXT)
	body_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_l.custom_minimum_size.x = 600
	vb.add_child(body_l)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(hb)
	hb.add_child(UIK.button(Loc.t("Вимкнути підказки"), _disable, 0))
	hb.add_child(UIK.button(Loc.t("Зрозуміло"), _close, 120))
	visible = false
	_hl = Control.new()
	_hl.name = "HintHighlight"
	_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hl.top_level = true
	_hl.draw.connect(_draw_highlight)
	add_child(_hl)
	Events.enemy_spotted.connect(func(_u): trigger("spotted"))
	Events.selection_changed.connect(_on_selection)
	Events.unit_state_changed.connect(_on_state)


func _seen() -> Array:
	if not Game.settings.has("hints_seen"):
		Game.settings["hints_seen"] = []
	return Game.settings["hints_seen"]


func trigger(key: String) -> void:
	if not Game.settings.get("hints", true) or not HINTS.has(key):
		return
	if W.mission and W.mission.def and W.mission.def.objective.get("type", "") == "training":
		return   # the training mission has its own step-by-step panel
	if key in _seen() or key in queue:
		return
	queue.append(key)


func _on_selection() -> void:
	if not W.command.selection.is_empty():
		trigger("select")


func _on_state(u, _old: int, new_state: int) -> void:
	if u.side == 0 and new_state == Soldier.H.INCAP:
		trigger("wounded")


func _process(delta: float) -> void:
	var dt := delta / maxf(Engine.time_scale, 0.01)
	if W.mission == null or not W.running():
		return
	_start_t += dt
	if _start_t > 1.5:
		trigger("camera")
	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = 0.5
		_watch()
	_hl.visible = visible and not _hl_targets.is_empty()
	if _hl.visible:
		_hl.position = Vector2.ZERO
		_hl.size = get_viewport_rect().size
		_hl.queue_redraw()
	if visible:
		shown_t += dt
		if shown_t > 16.0:
			_close()
	elif not queue.is_empty():
		_show(queue.pop_front())


## Polls game state for first-time situations.
func _watch() -> void:
	for sq in W.mission.friendly_squads:
		if sq.order == "assault" and sq.contact_mode:
			trigger("contact")
	for u in W.units:
		if u.side == 0 and u.is_active():
			if u.suppression > 60.0:
				trigger("suppressed")
			if u.in_trench() and W.mission.def.capture_rect.has_point(Vector2(u.global_position.x, u.global_position.z)):
				trigger("trench")
		elif u.side == 1 and u.surrendered:
			trigger("prisoner")
	if W.ew:
		if W.ew.link < EwSystem.DEGRADED:
			trigger("ew")
		if W.ew.drone_down:
			trigger("drone_lost")
	if W.mines:
		for m in W.mines.mines:
			if m["revealed"]:
				trigger("mines")
				break
	if "spotted" in _seen() and W.time > 40.0:
		trigger("support")


func _show(key: String) -> void:
	var h: Array = HINTS[key]
	title_l.text = Loc.t("ПІДКАЗКА • ") + String(h[0])
	body_l.text = h[1]
	visible = true
	shown_t = 0.0
	_hl_targets = _targets(key)
	_seen().append(key)
	Game.save_settings()
	W.sfx.ui("click")


## HUD controls a hint refers to (outlined while the hint is on screen).
func _targets(key: String) -> Array:
	var hud = get_parent()
	if hud == null or not ("mode_buttons" in hud):
		return []
	match key:
		"select": return hud.mode_buttons.values()
		"contact": return [hud.mode_buttons.get("assault")]
		"trench": return [hud.mode_buttons.get("clear")]
		"suppressed": return [hud.cmd_buttons.get("smoke"), hud.sup_buttons.get("smoke"), hud.sup_buttons.get("mortar")]
		"support": return hud.sup_buttons.values()
		"spotted": return [hud.sup_buttons.get("fpv")]
		"wounded": return [hud.cmd_buttons.get("evac")]
		"ew": return [hud.tele_label]
		"drone_lost": return [hud.bo_launch]
	return []


func _draw_highlight() -> void:
	var a := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008)
	var col := Color(UIK.ACCENT, a)
	var inv := _hl.get_global_transform_with_canvas().affine_inverse()
	for c in _hl_targets:
		if c is Control and is_instance_valid(c) and c.is_visible_in_tree():
			var r: Rect2 = c.get_global_rect()
			r = Rect2(inv * r.position, r.size).grow(3.0)
			_hl.draw_rect(r, col, false, 3.0)


func _close() -> void:
	visible = false


func _disable() -> void:
	Game.settings["hints"] = false
	Game.save_settings()
	queue.clear()
	visible = false
