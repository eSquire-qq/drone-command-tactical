class_name MapExport
extends RefCounted
## Dumps a built map for safekeeping: height field (EXR, metres), natural
## ground before trenches, ground types, tactical cells and the MapDef data
## as JSON. Run: `-- --map=<id> --export-map=<absolute dir>`.


static func run(map: MapManager, dir: String) -> void:
	var g: TerrainGrid = map.grid
	DirAccess.make_dir_recursive_absolute(dir)
	var id: String = map.def.id.get_file().get_basename().replace(":", "_")
	var hi := Image.create(g.n, g.n, false, Image.FORMAT_RF)
	var nat := Image.create(g.n, g.n, false, Image.FORMAT_RF)
	var gt := Image.create(g.n, g.n, false, Image.FORMAT_L8)
	for z in g.n:
		for x in g.n:
			var i := z * g.n + x
			hi.set_pixel(x, z, Color(g.heights[i], 0, 0))
			nat.set_pixel(x, z, Color(g.nat[i] if not g.nat.is_empty() else g.heights[i], 0, 0))
			gt.set_pixel(x, z, Color8(g.gtype[i], g.gtype[i], g.gtype[i]))
	hi.save_exr(dir + "/%s_heights.exr" % id, true)
	nat.save_exr(dir + "/%s_natural.exr" % id, true)
	gt.save_png(dir + "/%s_ground_types.png" % id)
	var cells := Image.create(g.cn, g.cn, false, Image.FORMAT_RGBA8)
	for z in g.cn:
		for x in g.cn:
			var i := z * g.cn + x
			cells.set_pixel(x, z, Color(g.cover[i], g.foliage[i], clampf(g.obstacle[i] / 3.0, 0, 1), 1.0 if g.inf_solid[i] != 0 else 0.5 if g.veh_solid[i] != 0 else 0.0))
	cells.save_png(dir + "/%s_cells_cover_foliage_obst_solid.png" % id)
	var d := {"id": id, "title": map.def.title, "size": g.size, "res": g.res, "seed": map.def.seed, "relief": map.def.relief,
		"height_min": Array(g.heights).min(), "height_max": Array(g.heights).max()}
	for k in ["treelines", "bushes", "roads", "trenches", "craters", "houses", "sheds", "fences", "bales", "poles", "wrecks", "bunkers",
			"sandbags", "wire", "burnt", "smoke_columns", "ew_stations", "ew_decoys", "ew_backups", "dugouts", "teeth", "camo", "minefields",
			"enemy_teams", "dismount_points", "player_entry", "rally_point", "enemy_retreat", "objective_rect", "capture_rect", "medevac_entry", "foot_spawn"]:
		d[k] = var_to_str(map.def.get(k))
	var f := FileAccess.open(dir + "/%s_mapdef.json" % id, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  "))
	print("[MAPEXPORT] ", id, " -> ", dir)
