class_name Loc
extends RefCounted
## Localisation. The game text is written in Ukrainian and the Ukrainian text
## is the key: Loc.t("Текст") returns its translation for the current
## language (locale/en.po) or the text itself. Format after translating:
## Loc.t("Втрати: %d") % n. tools/i18n.py wraps literals and collects the
## strings for translators.

const LANGS := [["uk", "Українська"], ["en", "English"]]


static func t(s: String) -> String:
	if s == "":
		return s
	var r := String(TranslationServer.translate(s))
	# "текст@контекст": the same Ukrainian word with another meaning
	# (ПОСАДКА — a tree line or mounting up); the context is never shown
	if r == s and s.contains("@"):
		return s.get_slice("@", 0)
	return r


## Current language code ("uk" / "en").
static func lang() -> String:
	return TranslationServer.get_locale().substr(0, 2)


static func is_uk() -> bool:
	return lang() == "uk"


## The default language on the first launch: Ukrainian for uk / ru system
## locales, English otherwise.
static func system_default() -> String:
	var l := OS.get_locale_language()
	return "uk" if l in ["uk", "ru", "be"] else "en"


static func apply(code: String) -> void:
	TranslationServer.set_locale(code)
	localize_all()


## A deep copy with every text translated (dictionary keys stay).
static func deep(v):
	match typeof(v):
		TYPE_STRING:
			return t(v)
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(deep(x))
			return a
		TYPE_DICTIONARY:
			var d := {}
			for k in v.keys():
				d[k] = deep(v[k])
			return d
	return v


## The game's text tables for the current language (their originals are the
## *_UK constants).
static func localize_all() -> void:
	Game.CATALOG = deep(Game.CATALOG_UK)
	Game.DIFFICULTY = deep(Game.DIFFICULTY_UK)
	Game.WEATHER = deep(Game.WEATHER_UK)
	Game.CATEGORIES = deep(Game.CATEGORIES_UK)
	Game.MISSIONS = deep(Game.MISSIONS_UK)
	Game.CAMPAIGN_STEPS = deep(Game.CAMPAIGN_STEPS_UK)
	Game.KEY_ACTIONS = deep(Game.KEY_ACTIONS_UK)
	Db.VEHICLES = deep(Db.VEHICLES_UK)
	Db.ROLES = deep(Db.ROLES_UK)
	Db.WEAPONS = deep(Db.WEAPONS_UK)
	Campaign.NAME = deep(Campaign.NAME_UK)
	Campaign.RANKS = deep(Campaign.RANKS_UK)
	Objectives.TITLES = deep(Objectives.TITLES_UK)
	AIConfig.LEVEL_NAMES = deep(AIConfig.LEVEL_NAMES_UK)
	AIConfig.PSY_NAMES = deep(AIConfig.PSY_NAMES_UK)
	AIConfig.PSY_SHORT = deep(AIConfig.PSY_SHORT_UK)
	IntelSystem.NAMES = deep(IntelSystem.NAMES_UK)
	RadioSystem.TYPES = deep(RadioSystem.TYPES_UK)
	RadioSystem.FILTERS = deep(RadioSystem.FILTERS_UK)
	Tutorial.HINTS = deep(Tutorial.HINTS_UK)
	Vehicle.FACE_NAMES = deep(Vehicle.FACE_NAMES_UK)
	if W.mission and W.mission.def:
		localize_def(W.mission.def)


## enemy_teams are not here: a team's name is its identifier (the training
## and the tests find teams by it) and is never shown to the player.
const DEF_TEXT := ["title", "subtitle", "terrain_type", "terrain_desc", "task_text", "intel", "deploy_options"]


## A map's texts for the current language (the originals are kept on the def).
static func localize_def(def: MapDef) -> void:
	if not def.has_meta("uk_text"):
		var o := {}
		for k in DEF_TEXT:
			o[k] = def.get(k)
		def.set_meta("uk_text", o)
	var src: Dictionary = def.get_meta("uk_text")
	for k in DEF_TEXT:
		def.set(k, deep(src[k]))
	if def.has_meta("intel0"):
		def.set_meta("intel0", def.intel.duplicate(true))


## A person's name for the current language: Ukrainian names are
## transliterated (the official Ukrainian national system) in English.
static func person(s: String) -> String:
	if is_uk() or s == "":
		return s
	var out := ""
	for i in s.length():
		var c := s[i]
		var low := c.to_lower()
		var up := c != low
		var r: String
		var word_start := i == 0 or not _is_letter(s[i - 1])
		if TR_FIRST.has(low) and word_start:
			r = TR_FIRST[low]
		elif TR.has(low):
			r = TR[low]
		else:
			r = c
		if up and r.length() > 0:
			r = r.substr(0, 1).to_upper() + r.substr(1)
		out += r
	return out


static func _is_letter(c: String) -> bool:
	return c.to_lower() != c.to_upper()


const TR := {"а": "a", "б": "b", "в": "v", "г": "h", "ґ": "g", "д": "d", "е": "e", "є": "ie", "ж": "zh", "з": "z", "и": "y",
	"і": "i", "ї": "i", "й": "i", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t",
	"у": "u", "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch", "ь": "", "ю": "iu", "я": "ia", "'": "", "’": "",
	"ё": "io", "ы": "y", "э": "e", "ъ": ""}
## At the start of a word.
const TR_FIRST := {"є": "ye", "ї": "yi", "й": "y", "ю": "yu", "я": "ya"}
