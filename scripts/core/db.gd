class_name Db
extends RefCounted
## Balance data. Values are abstract game parameters, not real-world specs.

const WEAPONS_UK := {
	"rifle": {"name": "Автомат", "dmg": 42.0, "acc": 0.30, "range": 115.0, "interval": 0.28,
		"burst": [1, 3], "pause": [0.7, 1.5], "mag": 30, "mags": 7, "reload": 2.6, "supp": 7.0, "tracer": 3, "snd": "rifle", "kind": "bullet"},
	"assault": {"name": "Автомат (штурм.)", "dmg": 42.0, "acc": 0.36, "range": 95.0, "interval": 0.12,
		"burst": [2, 4], "pause": [0.6, 1.2], "mag": 30, "mags": 7, "reload": 2.3, "supp": 8.0, "tracer": 3, "snd": "rifle", "kind": "bullet"},
	"mg": {"name": "Кулемет", "dmg": 45.0, "acc": 0.15, "range": 145.0, "interval": 0.085,
		"burst": [6, 12], "pause": [0.9, 1.8], "mag": 100, "mags": 4, "reload": 5.5, "supp": 13.0, "tracer": 2, "snd": "mg", "kind": "bullet"},
	"veh_mg": {"name": "Спарений кулемет", "dmg": 45.0, "acc": 0.17, "range": 150.0, "interval": 0.09,
		"burst": [6, 10], "pause": [1.0, 2.0], "mag": 250, "reload": 6.0, "supp": 13.0, "tracer": 2, "snd": "mg", "kind": "bullet"},
	"hmg": {"name": "Великокаліберний кулемет", "dmg": 70.0, "acc": 0.17, "range": 160.0, "interval": 0.13,
		"burst": [4, 8], "pause": [1.0, 2.0], "mag": 100, "reload": 6.0, "supp": 20.0, "tracer": 2, "snd": "hmg", "kind": "bullet", "armor": 12.0},
	"cannon30": {"name": "30-мм гармата", "acc": 0.5, "range": 175.0, "interval": 0.33,
		"burst": [3, 5], "pause": [1.8, 2.8], "mag": 60, "reload": 6.0, "supp": 22.0, "snd": "cannon", "kind": "he",
		"radius": 2.6, "power": 55.0, "armor": 35.0, "bunker": 12.0},
	"gun73": {"name": "73-мм гармата", "acc": 0.45, "range": 160.0, "interval": 6.5,
		"burst": [1, 1], "pause": [6.5, 7.5], "mag": 40, "reload": 0.1, "supp": 30.0, "snd": "gun", "kind": "he",
		"radius": 4.0, "power": 100.0, "armor": 120.0, "bunker": 90.0},
}
static var WEAPONS = WEAPONS_UK   # the current language (Loc.localize_all)

const VEHICLES_UK := {
	"bmp1": {"name": "БМП-1", "hp": 320.0, "armor": 0.6, "speed": 7.0, "cap": 8, "weapons": ["gun73", "veh_mg"], "mobility": "tracked", "stock": [3000, 24]},
	"bmp2": {"name": "БМП-2", "hp": 340.0, "armor": 0.6, "speed": 7.0, "cap": 7, "weapons": ["cannon30", "veh_mg"], "mobility": "tracked", "stock": [3000, 24]},
	"m113": {"name": "M113", "hp": 260.0, "armor": 0.45, "speed": 7.5, "cap": 10, "weapons": ["hmg"], "mobility": "light", "stock": [4000, 30]},
	"medevac": {"name": "Евак. M113", "hp": 240.0, "armor": 0.45, "speed": 8.0, "cap": 4, "weapons": [], "mobility": "light"},
}
static var VEHICLES = VEHICLES_UK   # the current language (Loc.localize_all)

## Terrain mobility profiles (abstract): what each class of vehicle can cross.
##  max_slope — steepest ground (rise per metre) it can climb
##  crater    — craters with a radius from this size block it (m)
##  rough     — speed multiplier over craters / berms / broken ground
## Trenches with their parapets block every vehicle (crossing only where a
## road runs through the position).
const MOBILITY := {
	"tracked": {"max_slope": 0.55, "crater": 2.7, "rough": 0.55},
	"light": {"max_slope": 0.4, "crater": 2.0, "rough": 0.45},
}

const ROLES_UK := {
	"leader": {"name": "Командир", "short": "КВ", "weapon": "rifle", "grenades": 2, "rockets": 0, "smoke": 2, "skill": 1.1, "morale": 90.0},
	"rifleman": {"name": "Стрілець", "short": "СТ", "weapon": "rifle", "grenades": 2, "rockets": 0, "smoke": 1, "skill": 1.0, "morale": 75.0},
	"assault": {"name": "Штурмовик", "short": "ШТ", "weapon": "assault", "grenades": 4, "rockets": 0, "smoke": 1, "skill": 1.05, "morale": 88.0},
	"mg": {"name": "Кулеметник", "short": "КЛ", "weapon": "mg", "grenades": 1, "rockets": 0, "smoke": 0, "skill": 1.0, "morale": 78.0},
	"grenadier": {"name": "Гранатометник", "short": "ГР", "weapon": "rifle", "grenades": 2, "gl": 8, "rockets": 0, "smoke": 1, "skill": 1.0, "morale": 75.0},
	"at": {"name": "Протитанкіст", "short": "ПТ", "weapon": "rifle", "grenades": 1, "rockets": 3, "smoke": 0, "skill": 1.0, "morale": 75.0},
	"atgm": {"name": "Оператор ПТРК", "short": "ПК", "weapon": "rifle", "grenades": 1, "rockets": 0, "atgm": 4, "smoke": 0, "skill": 1.0, "morale": 82.0},
	"medic": {"name": "Медик", "short": "МД", "weapon": "rifle", "grenades": 1, "rockets": 0, "smoke": 2, "skill": 0.9, "morale": 75.0, "medic": true},
	"crew_medic": {"name": "Санітар", "short": "СН", "weapon": "", "grenades": 0, "rockets": 0, "smoke": 0, "skill": 0.8, "morale": 80.0, "medic": true},
}
static var ROLES = ROLES_UK   # the current language (Loc.localize_all)

const AT_ROCKET := {"range": 115.0, "acc": 0.62, "armor": 190.0, "radius": 3.0, "power": 75.0, "bunker": 140.0}
const ATGM := {"range": 185.0, "acc": 0.82, "armor": 300.0, "radius": 3.0, "power": 70.0, "bunker": 150.0, "speed": 38.0, "reload": 22.0}
const FPV_SPEED := 11.0
const GRENADE := {"range": 26.0, "radius": 5.5, "power": 85.0}
const GL := {"range": 80.0, "radius": 3.5, "power": 60.0}

const SURNAMES := ["Коваль", "Мельник", "Бондар", "Шевчук", "Ткач", "Кравець", "Лисенко", "Гончар",
	"Савчук", "Олійник", "Руденко", "Марченко", "Козак", "Поліщук", "Литвин", "Мороз", "Довбуш",
	"Ярема", "Сокіл", "Дорош", "Гуменюк", "Чорновол", "Білик", "Зайченко", "Панчук", "Вовк", "Сич"]
