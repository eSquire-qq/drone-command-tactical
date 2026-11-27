@tool
class_name MapLibrary
extends RefCounted
## Builds the library of ready-made map objects (res://maps/objects/<група>/
## <назва>.tscn) and the template of a new map (res://maps/templates/).
## Run once after changing the table: `-- --make-library`.
## In the editor: drag a file from the FileSystem onto the map, or use the
## «Об'єкти карти» dock (addons/map_editor).

const DIR := "res://maps/objects"
const TEMPLATE := "res://maps/templates/Нова карта.tscn"


## [group, name, node class, properties, curve points (lines) or slot list (teams)]
static func table() -> Array:
	return [
		["1 Рослинність", "Дерево", "MapTreeline", {"size": Vector2(4, 4), "density": 1.0, "dead": 0.0}],
		["1 Рослинність", "Сухе дерево", "MapTreeline", {"size": Vector2(4, 4), "density": 1.0, "dead": 1.0}],
		["1 Рослинність", "Кущ", "MapBush", {"radius": 2.0}],
		["1 Рослинність", "Великий кущ", "MapBush", {"radius": 3.5}],
		["1 Рослинність", "Гай", "MapTreeline", {"size": Vector2(14, 12), "density": 0.7, "dead": 0.3}],
		["1 Рослинність", "Посадка 60 м", "MapTreeline", {"size": Vector2(60, 10), "density": 0.85, "dead": 0.2}],
		["1 Рослинність", "Ліс 40×40", "MapTreeline", {"size": Vector2(40, 40), "density": 0.9, "dead": 0.15}],
		["1 Рослинність", "Сосновий ліс 40×40", "MapTreeline", {"size": Vector2(40, 40), "density": 0.35, "dead": 0.08, "kind": "pine", "sight_block": 0.2}],
		["1 Рослинність", "Мішаний ліс 40×40", "MapTreeline", {"size": Vector2(40, 40), "density": 0.4, "dead": 0.1, "kind": "mixed", "sight_block": 0.25}],
		["1 Рослинність", "Сосна", "MapTreeline", {"size": Vector2(4, 4), "density": 1.0, "dead": 0.0, "kind": "pine"}],
		["2 Рельєф", "Пагорб", "MapHill", {"radius_x": 25.0, "radius_z": 20.0, "height": 4.0}],
		["2 Рельєф", "Западина", "MapHill", {"radius_x": 15.0, "radius_z": 15.0, "height": -2.0}],
		["2 Рельєф", "Балка", "MapRidge", {"width": 7.0, "height": -2.5}, [Vector3(0, 0, 0), Vector3(0, 0, -30), Vector3(6, 0, -60)]],
		["2 Рельєф", "Вал", "MapRidge", {"width": 5.0, "height": 1.5}, [Vector3(-20, 0, 0), Vector3(20, 0, 0)]],
		["2 Рельєф", "Вирва мала", "MapCrater", {"radius": 1.2}],
		["2 Рельєф", "Вирва велика", "MapCrater", {"radius": 3.0}],
		["2 Рельєф", "Згарище", "MapBurnt", {"radius": 5.0}],
		["3 Окопи й дороги", "Окоп (з траверсами)", "MapTrench", {"style": "traversed"}, [Vector3(-12, 0, 0), Vector3(0, 0, -1), Vector3(12, 0, 0)]],
		["3 Окопи й дороги", "Окоп прямий", "MapTrench", {"style": "plain"}, [Vector3(-10, 0, 0), Vector3(10, 0, 0)]],
		["3 Окопи й дороги", "Хід сполучення", "MapTrench", {"style": "meander", "bay": 3.0, "amp": 0.5}, [Vector3(0, 0, 0), Vector3(0, 0, -15)]],
		["3 Окопи й дороги", "Окоп з бліндажем", "MapTrench", {"style": "traversed", "dugout_at_end": true}, [Vector3(-12, 0, 0), Vector3(8, 0, 0)]],
		["3 Окопи й дороги", "Бліндаж", "MapDugout", {}],
		["3 Окопи й дороги", "Дорога", "MapRoad", {"width": 3.5}, [Vector3(0, 0, 30), Vector3(0, 0, -30)]],
		["3 Окопи й дороги", "Польова дорога", "MapRoad", {"width": 2.5}, [Vector3(-25, 0, 0), Vector3(25, 0, 3)]],
		["4 Споруди й укриття", "Будинок (руїна)", "MapHouse", {"size": Vector2(8, 6), "ruin": 0.6}],
		["4 Споруди й укриття", "Будинок (майже цілий)", "MapHouse", {"size": Vector2(9, 7), "ruin": 0.1}],
		["4 Споруди й укриття", "Сарай", "MapShed", {"size": Vector2(6, 5)}],
		["4 Споруди й укриття", "Багатоповерхівка 4 пов.", "MapApartment", {"size": Vector2(24, 12), "floors": 4, "ruin": 0.3}],
		["4 Споруди й укриття", "Багатоповерхівка 9 пов.", "MapApartment", {"size": Vector2(30, 12), "floors": 9, "ruin": 0.2}],
		["4 Споруди й укриття", "Гаражі", "MapShed", {"size": Vector2(14, 6)}],
		["4 Споруди й укриття", "Згоріла автівка", "MapCar", {}],
		["4 Споруди й укриття", "Мішки з піском", "MapSandbags", {"length": 4.0}],
		["4 Споруди й укриття", "Тюк сіна", "MapBale", {}],
		["4 Споруди й укриття", "Стовп", "MapPole", {}],
		["4 Споруди й укриття", "Підбита БМП-1", "MapWreck", {"model": "bmp1"}],
		["4 Споруди й укриття", "Підбитий M113", "MapWreck", {"model": "m113"}],
		["4 Споруди й укриття", "Паркан", "MapFence", {}, [Vector3(-8, 0, 0), Vector3(8, 0, 0)]],
		["5 Загородження", "Колючий дріт", "MapWire", {}, [Vector3(-15, 0, 0), Vector3(15, 0, 0)]],
		["5 Загородження", "Зуби дракона", "MapTeeth", {"rows": 2}, [Vector3(-12, 0, 0), Vector3(12, 0, 0)]],
		["5 Загородження", "Бетонні блоки", "MapBlocks", {"kind": "concrete"}, [Vector3(-6, 0, 0), Vector3(6, 0, 0)]],
		["5 Загородження", "Барикада", "MapBlocks", {"kind": "barricade"}, [Vector3(-5, 0, 0), Vector3(5, 0, 0)]],
		["5 Загородження", "Мінне поле ПП", "MapMinefield", {"mine_type": "ap", "width": 6.0, "density": 0.05}, [Vector3(-15, 0, 0), Vector3(15, 0, 0)]],
		["5 Загородження", "Мінне поле ПТ", "MapMinefield", {"mine_type": "at", "width": 9.0, "density": 0.03}, [Vector3(-10, 0, 0), Vector3(10, 0, 0)]],
		["6 Противник", "Загін стрільців", "MapEnemyTeam", {"team_name": "Загін", "roles": PackedStringArray(["leader", "rifleman", "rifleman", "mg"])},
			[["slot", Vector3(-4, 0, 0)], ["slot", Vector3(-1.5, 0, -0.5)], ["slot", Vector3(1.5, 0, -0.5)], ["slot", Vector3(4, 0, 0)],
			["alt", Vector3(-7, 0, 1)], ["fallback", Vector3(0, 0, -15)]]],
		["6 Противник", "Кулеметний розрахунок", "MapEnemyTeam", {"team_name": "Кулемет", "roles": PackedStringArray(["mg", "rifleman"])},
			[["slot", Vector3(0, 0, 0)], ["slot", Vector3(1.5, 0, 0.5)], ["fallback", Vector3(0, 0, -12)]]],
		["6 Противник", "Розрахунок ПТРК", "MapEnemyTeam", {"team_name": "ПТРК", "roles": PackedStringArray(["atgm", "rifleman"])},
			[["slot", Vector3(0, 0, 0)], ["slot", Vector3(2, 0, 0.5)], ["alt", Vector3(-6, 0, 2)], ["fallback", Vector3(0, 0, -12)]]],
		["6 Противник", "Позиція бійця", "MapSlot", {"kind": "slot"}],
		["6 Противник", "ДЗОТ", "MapBunker", {"kind": "mg"}],
		["6 Противник", "Бліндаж противника", "MapBunker", {"kind": "dugout"}],
		["6 Противник", "Станція РЕБ", "MapEW", {"kind": "station"}],
		["6 Противник", "Макет РЕБ", "MapEW", {"kind": "decoy"}],
		["6 Противник", "Маскування позиції", "MapCamo", {"radius": 4.0}],
		["7 Місія", "Вʼїзд техніки", "MapMarker", {"kind": "player_entry"}],
		["7 Місія", "Поява піхоти", "MapMarker", {"kind": "foot_spawn"}],
		["7 Місія", "Точка висадки", "MapMarker", {"kind": "dismount"}],
		["7 Місія", "Вʼїзд евакуації", "MapMarker", {"kind": "medevac_entry"}],
		["7 Місія", "Точка збору", "MapMarker", {"kind": "rally_point"}],
		["7 Місія", "Район висадки (вибір на брифінгу)", "MapMarker", {"kind": "deploy_option", "label": "Новий район"}],
		["7 Місія", "Зона вільного вибору висадки", "MapArea", {"kind": "deploy_zone", "size": Vector2(80, 30)}],
		["7 Місія", "Відхід противника", "MapMarker", {"kind": "enemy_retreat"}],
		["7 Місія", "Камера на старті", "MapMarker", {"kind": "camera_start"}],
		["7 Місія", "Центр знімка", "MapMarker", {"kind": "photo_center"}],
		["7 Місія", "Ціль", "MapArea", {"kind": "objective", "size": Vector2(40, 16)}],
		["7 Місія", "Зона захоплення", "MapArea", {"kind": "capture", "size": Vector2(60, 40)}],
		["7 Місія", "Пристріляна зона", "MapArea", {"kind": "mortar_zone", "size": Vector2(80, 50)}],
		["7 Місія", "Позначка розвідки", "MapIntelMarker", {"label": "ПОСТ", "radius": 8.0}],
	]


static func make_node(cls: String) -> Node3D:
	match cls:
		"MapTreeline": return MapTreeline.new()
		"MapBush": return MapBush.new()
		"MapHill": return MapHill.new()
		"MapRidge": return MapRidge.new()
		"MapCrater": return MapCrater.new()
		"MapBurnt": return MapBurnt.new()
		"MapTrench": return MapTrench.new()
		"MapDugout": return MapDugout.new()
		"MapRoad": return MapRoad.new()
		"MapHouse": return MapHouse.new()
		"MapShed": return MapShed.new()
		"MapApartment": return MapApartment.new()
		"MapCar": return MapCar.new()
		"MapBlocks": return MapBlocks.new()
		"MapSandbags": return MapSandbags.new()
		"MapBale": return MapBale.new()
		"MapPole": return MapPole.new()
		"MapWreck": return MapWreck.new()
		"MapFence": return MapFence.new()
		"MapWire": return MapWire.new()
		"MapTeeth": return MapTeeth.new()
		"MapMinefield": return MapMinefield.new()
		"MapEnemyTeam": return MapEnemyTeam.new()
		"MapSlot": return MapSlot.new()
		"MapBunker": return MapBunker.new()
		"MapEW": return MapEW.new()
		"MapCamo": return MapCamo.new()
		"MapMarker": return MapMarker.new()
		"MapArea": return MapArea.new()
		"MapIntelMarker": return MapIntelMarker.new()
	return null


## One library item as a node tree (used for the files and by the dock).
static func build(item: Array) -> Node3D:
	var n := make_node(item[2])
	n.name = item[1]
	var props: Dictionary = item[3]
	for k in props.keys():
		n.set(k, props[k])
	if item.size() > 4:
		if n is Path3D:
			var c := Curve3D.new()
			c.resource_local_to_scene = true   # every placed copy has its own line
			for p in item[4]:
				c.add_point(p)
			n.curve = c
		elif n is MapEnemyTeam:
			var names := {"slot": "Позиція", "alt": "Запасна", "fallback": "Відхід"}
			for sd in item[4]:
				var sl := MapSlot.new()
				sl.kind = sd[0]
				sl.name = names[sd[0]]
				sl.position = sd[1]
				n.add_child(sl, true)
				sl.owner = n
	return n


static func make_all() -> void:
	var count := 0
	for item in table():
		var dir: String = DIR.path_join(item[0])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var n := build(item)
		var ps := PackedScene.new()
		ps.pack(n)
		var path: String = dir.path_join(String(item[1]) + ".tscn")
		var err := ResourceSaver.save(ps, path)
		if err != OK:
			push_error("library: %s %s" % [path, error_string(err)])
		count += 1
		n.free()
	_make_template()
	print("[LIBRARY] %d objects in %s, template %s" % [count, DIR, TEMPLATE])


## A small playable map to copy: ground, a tree line, one enemy post with a
## trench, all mission markers.
static func _make_template() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMPLATE.get_base_dir()))
	var root := MapScene.new()
	root.name = "НоваКарта"
	root.map_id = "nova"
	root.title = "НОВА КАРТА"
	root.subtitle = "Шаблон"
	root.terrain_desc = "Поле 160×160 м з посадкою на півночі."
	root.task_text = "Захопити пост противника біля посадки."
	root.intel_estimate = "4–6 осіб"
	root.intel_lines = PackedStringArray(["Пост противника біля північної посадки."])
	var groups := {}
	for g in ["Рослинність", "Рельєф", "Окопи й дороги", "Споруди", "Противник", "Місія"]:
		var gn := Node3D.new()
		gn.name = g
		root.add_child(gn)
		gn.owner = root
		groups[g] = gn
	var place := func(group: String, item_name: String, pos: Vector3, rot: float = 0.0) -> Node3D:
		for it in table():
			if it[1] == item_name:
				var n := build(it)
				n.position = pos
				n.rotation.y = rot
				groups[group].add_child(n, true)
				n.owner = root
				for c in MapScene._all(n):
					c.owner = root
				return n
		return null
	place.call("Рослинність", "Посадка 60 м", Vector3(-40, 0, -70))
	place.call("Рослинність", "Посадка 60 м", Vector3(40, 0, -70))
	place.call("Рослинність", "Посадка 60 м", Vector3(-45, 0, 70))
	place.call("Рослинність", "Посадка 60 м", Vector3(45, 0, 70))
	place.call("Рослинність", "Кущ", Vector3(-20, 0, 10))
	place.call("Рельєф", "Вирва велика", Vector3(10, 0, 0))
	place.call("Окопи й дороги", "Дорога", Vector3(0, 0, 50))
	place.call("Окопи й дороги", "Окоп (з траверсами)", Vector3(0, 0, -45))
	place.call("Противник", "Загін стрільців", Vector3(0, 0, -45))
	place.call("Місія", "Вʼїзд техніки", Vector3(0, 0, 76))
	place.call("Місія", "Поява піхоти", Vector3(3, 0, 74))
	place.call("Місія", "Точка висадки", Vector3(0, 0, 55))
	place.call("Місія", "Вʼїзд евакуації", Vector3(-3, 0, 76))
	place.call("Місія", "Точка збору", Vector3(0, 0, 66))
	place.call("Місія", "Відхід противника", Vector3(0, 0, -76))
	place.call("Місія", "Камера на старті", Vector3(0, 0, 50))
	place.call("Місія", "Центр знімка", Vector3(0, 0, -30))
	place.call("Місія", "Ціль", Vector3(0, 0, -45))
	place.call("Місія", "Зона захоплення", Vector3(0, 0, -45))
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, TEMPLATE)
	root.free()
