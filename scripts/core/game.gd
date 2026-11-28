extends Node
## Persistent game data: catalog of assets, the player's loadout, mission list
## and the result of the last mission. Survives scene reloads.

const BUDGET := 1300

const CATALOG_UK := {
	"rifle_squad": {"cat": "inf", "name": "Стрілецьке відділення", "cost": 110, "max": 3,
		"desc": "8 бійців: командир, 3 стрільці, кулеметник, гранатометник, протитанкіст, медик.",
		"roles": ["leader", "rifleman", "mg", "rifleman", "grenadier", "at", "rifleman", "medic"]},
	"assault_group": {"cat": "inf", "name": "Штурмова група", "cost": 140, "max": 2,
		"desc": "6 бійців. Більше гранат, вища стійкість. Сильні на близькій дистанції.",
		"roles": ["leader", "assault", "assault", "mg", "assault", "at"]},
	"bmp1": {"cat": "veh", "name": "БМП-1", "cost": 180, "max": 2,
		"desc": "73-мм гармата + кулемет. Перевозить 8 бійців."},
	"bmp2": {"cat": "veh", "name": "БМП-2", "cost": 240, "max": 2,
		"desc": "30-мм автоматична гармата + кулемет. Перевозить 7 бійців."},
	"m113": {"cat": "veh", "name": "M113", "cost": 150, "max": 2,
		"desc": "Великокаліберний кулемет. Перевозить 10 бійців. Легка броня."},
	"medevac": {"cat": "med", "name": "Евакуаційна M113", "cost": 80, "max": 2,
		"desc": "2 санітари, до 4 поранених за рейс. Повертається для нових рейсів."},
	"mortar": {"cat": "sup", "name": "Мінометний наліт", "cost": 50, "max": 4,
		"desc": "4 міни з інтервалом 6–10 с. Підліт ~12 с, великий розкид, можливі перельоти."},
	"fpv": {"cat": "sup", "name": "FPV-дрон", "cost": 45, "max": 5,
		"desc": "Точкове ураження цілі: техніка, ДЗОТ, вогнева точка."},
	"smoke": {"cat": "sup", "name": "Димова завіса", "cost": 25, "max": 4,
		"desc": "Димові снаряди. Закривають огляд противнику ~45 с."},
	"recon_drone": {"cat": "sup", "name": "Запасний розвід. дрон", "cost": 60, "max": 3,
		"desc": "Якщо основний дрон впаде (РЕБ), запасний прилетить у район за ~90 с."},
}
var CATALOG = CATALOG_UK   # the current language (Loc.localize_all)

## Difficulty presets. "normal" is the balance tested with the balance bot.
const DIFFICULTY_UK := {
	"easy": {"name": "ЛЕГКА", "desc": "Противник слабше стріляє й повільніше помічає, менше мін і FPV; у кожній групі противника на бійця менше; поранені довше тримаються; бюджет +250.",
		"enemy_acc": 0.6, "enemy_detect": 0.75, "enemy_morale": 0.85, "atgm_acc": 0.8, "mortar": 4, "fpv": 2,
		"thin": true, "bleed": 1.4, "budget": 250, "intel_age": 1.4,
		"reinf_after": -1.0, "reinf_men": 0, "reinf_veh_size": 9999.0, "recon_sorties": 1, "counter_k": 0.67, "counter_veh": false},
	"normal": {"name": "НОРМАЛЬНА", "desc": "Збалансований бій: грамотний план із розвідкою, обходом і підтримкою дає перемогу, атака «в лоб» дорого коштує.",
		"enemy_acc": 0.72, "enemy_detect": 1.0, "enemy_morale": 1.0, "atgm_acc": 1.0, "mortar": 7, "fpv": 4,
		"thin": false, "bleed": 1.0, "budget": 0, "intel_age": 1.0,
		"reinf_after": 480.0, "reinf_men": 4, "reinf_veh_size": 400.0, "recon_sorties": 2, "counter_k": 1.0, "counter_veh": false},
	"hard": {"name": "ВАЖКА", "desc": "Досвідчений противник: влучніший, пильніший, стійкіший; більше мінометних мін і FPV; поранені швидше гинуть; бюджет −150.",
		"enemy_acc": 0.95, "enemy_detect": 1.2, "enemy_morale": 1.15, "atgm_acc": 1.08, "mortar": 12, "fpv": 6,
		"thin": false, "bleed": 0.8, "budget": -150, "intel_age": 0.7,
		"reinf_after": 300.0, "reinf_men": 6, "reinf_veh_size": 300.0, "recon_sorties": 2, "counter_k": 1.34, "counter_veh": true},
}
var DIFFICULTY = DIFFICULTY_UK   # the current language (Loc.localize_all)
const DIFFICULTY_ORDER := ["easy", "normal", "hard"]

## Graphics presets. Measured on the first mission: most GPU time goes to the
## 4-cascade sun shadows, SSAO and vegetation; game logic is 2-5 ms per frame.
const QUALITY := {
	"low": {"name": "НИЗЬКА", "desc": "Для слабких ПК та вбудованої графіки: рендер 75% з FSR, без SSAO і світіння, прості тіні, трава лише поблизу.",
		"ssao": false, "glow": false, "splits": 2, "shadow_dist": 130.0, "soft": 0, "msaa": 0, "fxaa": true, "scale": 0.75,
		"grass": 60.0, "bush_shadow": false, "fx": 0.6, "fire_lights": 2},
	"medium": {"name": "СЕРЕДНЯ", "desc": "Баланс: без SSAO, 2 каскади тіней, згладжування FXAA.",
		"ssao": false, "glow": true, "splits": 2, "shadow_dist": 180.0, "soft": 1, "msaa": 0, "fxaa": true, "scale": 1.0,
		"grass": 110.0, "bush_shadow": false, "fx": 0.8, "fire_lights": 4},
	"high": {"name": "ВИСОКА", "desc": "Повна якість: SSAO, 4 каскади м'яких тіней, MSAA 2x.",
		"ssao": true, "glow": true, "splits": 4, "shadow_dist": 240.0, "soft": 3, "msaa": 2, "fxaa": false, "scale": 1.0,
		"grass": 170.0, "bush_shadow": true, "fx": 1.0, "fire_lights": 6},
}
const QUALITY_ORDER := ["low", "medium", "high"]

## Weather. Every preset changes the fight, not only the picture:
##  sight   — soldiers' and vehicles' observation range multiplier
##  fog_len — line of sight fades with distance (m, 0 = clear air): exp(-d / fog_len)
##  detect  — chance to notice a target; acc — long-range accuracy
##  move / veh — infantry / off-road vehicle speed (mud)
##  smoke   — how long smoke screens last; mortar — mortar dispersion
##  fpv_miss — chance an FPV drone misses (rain on the lens, gusts, no visual)
##  wind    — drone sway and tree motion
const WEATHER_UK := {
	"clear": {"name": "ЯСНО", "icon": "☀", "w": 35,
		"desc": "Далека видимість, точний вогонь. Противник теж бачить усе поле.",
		"sight": 1.0, "fog_len": 0.0, "detect": 1.0, "acc": 1.0, "move": 1.0, "veh": 1.0,
		"smoke": 1.0, "mortar": 1.0, "fpv_miss": 0.0, "wind": 1.0},
	"overcast": {"name": "ХМАРНО", "icon": "☁", "w": 25,
		"desc": "Тьмяне світло, видимість трохи гірша, дим тримається довше.",
		"sight": 0.95, "fog_len": 650.0, "detect": 0.92, "acc": 1.0, "move": 1.0, "veh": 1.0,
		"smoke": 1.15, "mortar": 1.0, "fpv_miss": 0.04, "wind": 1.3},
	"rain": {"name": "ДОЩ", "icon": "☂", "w": 15,
		"desc": "Видимість і виявлення нижчі, бруд сповільнює піхоту й техніку поза дорогами, дим швидко прибиває, FPV частіше промахуються.",
		"sight": 0.75, "fog_len": 210.0, "detect": 0.78, "acc": 0.88, "move": 0.86, "veh": 0.78,
		"smoke": 0.65, "mortar": 1.1, "fpv_miss": 0.2, "wind": 1.7},
	"fog": {"name": "ТУМАН", "icon": "≋", "w": 12,
		"desc": "Видно лише на кілька десятків метрів: можна непомітно підійти впритул, але й противник з'являється раптово. Далекий вогонь і FPV майже марні, дрон бачить погано.",
		"sight": 0.5, "fog_len": 55.0, "detect": 0.75, "acc": 0.9, "move": 1.0, "veh": 0.9,
		"smoke": 1.3, "mortar": 1.0, "fpv_miss": 0.35, "wind": 0.5},
	"wind": {"name": "СИЛЬНИЙ ВІТЕР", "icon": "≈", "w": 13,
		"desc": "Дрон сильно гойдає, мінометні міни розкидає ширше, дим зносить за лічені секунди, FPV ненадійні.",
		"sight": 0.95, "fog_len": 900.0, "detect": 0.95, "acc": 0.92, "move": 1.0, "veh": 1.0,
		"smoke": 0.45, "mortar": 1.5, "fpv_miss": 0.25, "wind": 3.0},
}
var WEATHER = WEATHER_UK   # the current language (Loc.localize_all)
const WEATHER_ORDER := ["clear", "overcast", "rain", "fog", "wind"]

const CATEGORIES_UK := [
	["inf", "ПІХОТА"], ["veh", "БОЙОВА ТЕХНІКА"], ["med", "МЕДИЧНА ЕВАКУАЦІЯ"], ["sup", "ЗАСОБИ ПІДТРИМКИ"],
]
var CATEGORIES = CATEGORIES_UK   # the current language (Loc.localize_all)

## Official maps: editor scenes (open them in Godot to edit). The original
## map scripts stay in scripts/map/maps/ as the reference (MAPS_SCRIPT,
## `--map=script:<id>`), a copy is in backup/maps_2026-11-26/.
const MAPS := {
	"treeline": "res://maps/treeline.tscn",
	"field": "res://maps/field.tscn",
	"training": "res://maps/training.tscn",
	"village": "res://maps/village.tscn",
	"urban": "res://maps/urban.tscn",
	"forest": "res://maps/forest.tscn",
	"recon": "res://maps/recon.tscn",
}
const MAPS_SCRIPT := {
	"treeline": "res://scripts/map/maps/map_treeline.gd",
	"field": "res://scripts/map/maps/map_field.gd",
	"training": "res://scripts/map/maps/map_training.gd",
	"village": "res://scripts/map/maps/map_village.gd",
	"urban": "res://scripts/map/maps/map_urban.gd",
	"forest": "res://scripts/map/maps/map_forest.gd",
	"recon": "res://scripts/map/maps/map_recon.gd",
}

## All missions, playable or not yet built. A mission is playable when its
## map script exists in MAPS.
const MISSIONS_UK := {
	"training": {"title": "ПОЛІГОН", "terrain": "Навчання",
		"desc": "Покрокове навчання: дрон, накази, підтримка, штурм, евакуація, зачистка окопу."},
	"treeline": {"title": "ПОСАДКА", "terrain": "Лісосмуга / поле",
		"desc": "Опорний пункт противника в лісосмузі: дві лінії окопів, ДЗОТи, мінні загородження, РЕБ."},
	"field": {"title": "ВИСОТА", "terrain": "Відкрите поле",
		"desc": "Опорний пункт на голому пагорбі над відкритим полем: передова застава, прихована балка, ПТРК, пристріляне поле."},
	"village": {"title": "ХУТІР", "terrain": "Сільська забудова",
		"desc": "Штурм хутора: подвір'я, паркани, підвали, вузькі вулиці та присадибні ділянки."},
	"forest": {"title": "ЛІСОВИЙ МАСИВ", "terrain": "Ліс",
		"desc": "Рейд у сосновий ліс: знищити склад боєприпасів біля лісництва й станцію РЕБ. Огляд 20–35 м, засідки, траншеї під деревами, просіки для техніки."},
	"recon": {"title": "СІРА ЗОНА", "terrain": "Розвідка дроном",
		"desc": "Коротка місія без штурму: знайти дроном пост, кулемет, окоп, мінометників, бліндаж і РЕБ противника. Дрон один — РЕБ і РЕР не прощають помилок."},
	"urban": {"title": "КВАРТАЛ", "terrain": "Міська забудова",
		"desc": "Зачистка міського кварталу: зруйновані багатоповерхівки, під'їзди, двори."},
}
var MISSIONS = MISSIONS_UK   # the current language (Loc.localize_all)
const MISSION_ORDER := ["recon", "treeline", "field", "village", "forest", "urban"]

## Campaign "Operation Dawn": the same unit fights these steps in order.
const CAMPAIGN_STEPS_UK := [
	{"mission": "treeline", "title": "Прорив першої лінії",
		"task": "Захопити опорний пункт у лісосмузі — плацдарм для подальшого наступу. Бережіть людей: усі втрати переходять у наступні бої."},
	{"mission": "field", "title": "Висота за полем",
		"task": "Противник закріпився на висоті, що проглядає весь наступ. Взяти її, не втративши техніку у відкритому полі."},
	{"mission": "village", "title": "Вихід до хутора",
		"task": "Розвинути успіх і вибити противника з хутора за лісосмугою."},
	{"mission": "forest", "title": "Лісовий масив",
		"task": "Рейд у лісовий масив на фланзі наступу: знищити склад боєприпасів і станцію РЕБ противника."},
	{"mission": "urban", "title": "Околиця міста",
		"task": "Закріпитися в крайньому кварталі міста."},
]
var CAMPAIGN_STEPS = CAMPAIGN_STEPS_UK   # the current language (Loc.localize_all)

var loadout := {"recon_drone": 1, "rifle_squad": 2, "bmp2": 1, "m113": 1, "medevac": 1, "mortar": 2, "fpv": 2, "smoke": 1}
var current_map := "treeline"
var weather := "clear"        # weather of the loaded mission (see WEATHER)
var last_result := {}
var start_screen := "menu"   # menu / briefing / planning
## Deployment point chosen on the briefing photo: {map, pos: Vector2, name}.
var deploy := {}
var mode := "quick"           # quick (single mission) / campaign
var campaign := Campaign.new()
var campaign_report := {}
var settings := {"volume": 0.8, "vol_sfx": 1.0, "vol_amb": 0.8, "vol_ui": 0.8, "ui_scale": 1.0, "fullscreen": false,
	"drone_fx": true, "edge_scroll": true, "hints": true, "hints_seen": [], "difficulty": "normal",
	"sticky_mode": false, "move_preview": true, "cam_speed": 1.0, "cam_turn": 1.0, "keys": {}}

## Rebindable command keys: [action, name, default key]. Camera keys (WASD,
## Q/E, PgUp/PgDn) are fixed.
const KEY_ACTIONS_UK := [
	["move", "Наказ: рух", KEY_1], ["assault", "Наказ: штурм", KEY_2], ["hold", "Наказ: утримувати", KEY_3],
	["clear", "Наказ: зачистка", KEY_8], ["retreat", "Відхід", KEY_4], ["mount", "Посадка / висадка", KEY_5],
	["smoke", "Димова граната", KEY_6], ["evac", "Евакуація", KEY_7],
	["resupply", "Поповнити набої", KEY_9],
	["suppress", "Техніка: подавлення", KEY_G], ["face", "Техніка: розворот", KEY_V],
	["follow_veh", "Піхота: за технікою", KEY_B], ["bound", "Піхота: перебіжками", KEY_N],
	["mortar", "Міномет", KEY_Z], ["fpv", "FPV-дрон", KEY_X], ["smoke_barrage", "Димова завіса", KEY_C],
	["next", "Наступний підрозділ", KEY_TAB], ["pause", "Тактична пауза", KEY_SPACE],
	["follow", "Камера: супровід", KEY_F], ["overview", "Камера: загальний огляд", KEY_H],
	["radio", "Радіожурнал", KEY_R], ["help", "Довідка", KEY_F1], ["settings", "Налаштування", KEY_F10],
]
var KEY_ACTIONS = KEY_ACTIONS_UK   # the current language (Loc.localize_all)


func key_for(action: String) -> int:
	var keys: Dictionary = settings.get("keys", {})
	if keys.has(action):
		return int(keys[action])
	for a in KEY_ACTIONS:
		if a[0] == action:
			return int(a[2])
	return 0


func action_for(keycode: int) -> String:
	for a in KEY_ACTIONS:
		if key_for(a[0]) == keycode:
			return a[0]
	return ""
const SETTINGS_PATH := "user://settings.json"


func _ready() -> void:
	campaign.load_saved()
	scan_custom_maps()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map=") and map_path(a.substr(6)) != "":
			current_map = a.substr(6)
	if FileAccess.file_exists(SETTINGS_PATH) and not is_test_run():
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		if typeof(d) == TYPE_DICTIONARY:
			for k in d.keys():
				settings[k] = d[k]
	if not settings.has("quality"):
		settings["quality"] = _auto_quality()
	if not settings.has("lang"):
		settings["lang"] = Loc.system_default()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality=") and QUALITY.has(a.substr(10)):
			settings["quality"] = a.substr(10)
		if a.begins_with("--weather="):
			settings["weather"] = a.substr(10)
		if a.begins_with("--ui-scale="):
			settings["ui_scale"] = clampf(float(a.substr(11)), 0.8, 1.6)
		if a.begins_with("--lang="):
			settings["lang"] = a.substr(7)
	Loc.apply(String(settings["lang"]))


## First launch: integrated graphics start on the low preset.
func _auto_quality() -> String:
	var t := RenderingServer.get_video_adapter_type()
	if t == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or t == RenderingDevice.DEVICE_TYPE_CPU:
		return "low"
	return "high"


## Weather parameter of the current mission.
func wx(key: String):
	return WEATHER.get(weather, WEATHER["clear"])[key]


## Decides the weather of the mission being loaded: the player's choice for a
## single mission, random in the campaign, always clear on the training ground
## and in automated tests (unless --weather= is given).
func roll_weather(map_id: String) -> void:
	var pick := String(settings.get("weather", "random"))
	if map_id == "training":
		pick = "clear"
	elif mode == "campaign":
		pick = "random"
	elif is_test_run() and not _arg_weather():
		pick = "clear"
	weather = pick if WEATHER.has(pick) else _random_weather()


func _arg_weather() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weather="):
			return true
	return false


func _random_weather() -> String:
	var total := 0
	for k in WEATHER_ORDER:
		total += int(WEATHER[k]["w"])
	var r := randi() % total
	for k in WEATHER_ORDER:
		r -= int(WEATHER[k]["w"])
		if r < 0:
			return k
	return "clear"


## Player picked the weather in the menu: applied at once to the loaded map.
func set_weather_choice(k: String) -> void:
	settings["weather"] = k
	save_settings()
	weather = k if WEATHER.has(k) else _random_weather()
	if W.map and W.map.has_method("apply_weather"):
		W.map.apply_weather()


func quality() -> Dictionary:
	return QUALITY.get(String(settings.get("quality", "high")), QUALITY["high"])


func apply_quality() -> void:
	var q := quality()
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_2X if int(q["msaa"]) == 2 else Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q["fxaa"] else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if float(q["scale"]) < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = float(q["scale"])
	RenderingServer.directional_soft_shadow_filter_set_quality(int(q["soft"]) as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality(int(q["soft"]) as RenderingServer.ShadowQuality)
	if W.map and W.map.has_method("apply_quality"):
		W.map.apply_quality(q)


func is_test_run() -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--autotest" or a.begins_with("--balance=") or a.begins_with("--shots="):
			return true
	return false


func save_settings() -> void:
	if is_test_run():
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "  "))


func _bus(name: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
	return i


func mission_available(id: String) -> bool:
	return map_path(id) != ""


func difficulty() -> String:
	if mode == "campaign" and campaign.active:
		return campaign.difficulty
	return String(settings.get("difficulty", "normal"))


## A parameter of the current difficulty preset.
func diff(key: String):
	if W.mission and W.mission.def and W.mission.def.diff_override.has(key):
		return W.mission.def.diff_override[key]
	var d: Dictionary = DIFFICULTY.get(difficulty(), DIFFICULTY["normal"])
	return d[key]


func budget() -> int:
	return campaign.supply + mission_grant() if mode == "campaign" else BUDGET + int(diff("budget")) + mission_bonus()


## Extra points the loaded mission gives for its difficulty.
func mission_bonus() -> int:
	return W.mission.def.budget_bonus if W.mission and W.mission.def else 0


## In a campaign: the operation's own supply (spent first, not kept).
func mission_grant() -> int:
	return mission_bonus() / 2 if mode == "campaign" else 0


## In a campaign the unit's own squads and the motor pool cost nothing but are
## limited to what the unit has; support assets are bought with supply.
func item_cost(key: String) -> int:
	if mode == "campaign" and CATALOG[key]["cat"] in ["inf", "veh", "med"]:
		return 0
	return int(CATALOG[key]["cost"])


func item_max(key: String) -> int:
	if mode == "campaign":
		var cat: String = CATALOG[key]["cat"]
		if cat == "inf":
			return campaign.count_units(key)
		if cat == "veh" or cat == "med":
			return campaign.pool_ready(key)
	var extra := 0
	if W.mission and W.mission.def:
		extra = int(W.mission.def.extra_max.get(key, 0))
	return int(CATALOG[key]["max"]) + extra


func campaign_loadout() -> Dictionary:
	var lo := {}
	for k in CATALOG.keys():
		var cat: String = CATALOG[k]["cat"]
		if cat in ["inf", "veh", "med"]:
			lo[k] = item_max(k)
		else:
			lo[k] = 0
	lo["recon_drone"] = 1 if campaign.supply >= item_cost("recon_drone") else 0
	return lo


func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings["volume"]), 0.001)))
	AudioServer.set_bus_volume_db(_bus("SFX"), linear_to_db(maxf(float(settings.get("vol_sfx", 1.0)), 0.001)))
	AudioServer.set_bus_volume_db(_bus("Ambient"), linear_to_db(maxf(float(settings.get("vol_amb", 0.8)), 0.001)))
	AudioServer.set_bus_volume_db(_bus("UI"), linear_to_db(maxf(float(settings.get("vol_ui", 0.8)), 0.001)))
	var win = get_window()
	if win:
		win.content_scale_factor = float(settings["ui_scale"])
		var fs: bool = settings["fullscreen"]
		var want = Window.MODE_FULLSCREEN if fs else Window.MODE_WINDOWED
		if win.mode != want and DisplayServer.get_name() != "headless":
			win.mode = want
	if W.ui and W.ui.overlay:
		W.ui.overlay.visible = settings["drone_fx"]
	if W.cam:
		W.cam.edge_scroll = settings["edge_scroll"]
	apply_quality()
	save_settings()


func loadout_cost(lo: Dictionary = loadout) -> int:
	var total = 0
	for k in lo.keys():
		total += item_cost(k) * int(lo[k])
	return total


## The deployment point for a map: the player's choice, `--deploy=N` in tests,
## or the first option / the map's own dismount layout.
func deploy_for(def: MapDef) -> Dictionary:
	if not def.has_deploy_choice():
		return {}
	if deploy.get("map", "") == def.id:
		return deploy
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--deploy=") and not def.deploy_options.is_empty():
			return deploy_of(def, clampi(int(a.substr(9)), 0, def.deploy_options.size() - 1))
	if not def.deploy_options.is_empty():
		return deploy_of(def, 0)
	return {"map": def.id, "pos": def.dismount_center(), "name": Loc.t("За планом")}


func deploy_of(def: MapDef, i: int) -> Dictionary:
	var o: Dictionary = def.deploy_options[i]
	return {"map": def.id, "pos": o["pos"], "name": o["name"], "axis": o.get("axis", Vector2(1, 0))}


func make_map_def() -> MapDef:
	return map_def(current_map)


## Maps made in the editor and dropped into res://maps/custom/ (id = file name).
var custom_maps := {}


func scan_custom_maps() -> void:
	custom_maps.clear()
	var dir := DirAccess.open("res://maps/custom")
	if dir == null:
		return
	for f in dir.get_files():
		f = f.trim_suffix(".remap")
		if f.ends_with(".tscn"):
			custom_maps["custom/" + f.get_basename()] = "res://maps/custom/" + f


func map_path(id: String) -> String:
	if MAPS.has(id):
		return MAPS[id]
	if id.begins_with("script:") and MAPS_SCRIPT.has(id.substr(7)):
		return MAPS_SCRIPT[id.substr(7)]
	return custom_maps.get(id, id if id.ends_with(".tscn") else "")


## The map description for a map id: a MapDef script or an editor scene.
func map_def(id: String) -> MapDef:
	var path := map_path(id)
	if path.ends_with(".tscn"):
		var ps: PackedScene = load(path)
		var root = ps.instantiate()
		var d: MapDef = root.to_mapdef()
		root.free()
		if id.begins_with("custom/"):
			d.id = id    # custom maps are known by their file
		Loc.localize_def(d)
		return d
	var scr = load(path)
	var def: MapDef = scr.new()
	def.setup()
	Loc.localize_def(def)
	return def


## F6 on a map scene in the editor: start a battle on it.
func play_scene_map(path: String) -> void:
	current_map = path
	mode = "quick"
	start_screen = "planning"
	(func() -> void: get_tree().change_scene_to_file("res://scenes/main.tscn")).call_deferred()
