@tool
class_name Environments
extends RefCounted
## Shared environment presets: one lighting / colour family for every map so
## new terrains look like the same game. A preset only overrides palette keys;
## anything missing falls back to MapDef's default palette ("steppe").

const PRESETS := {
	"steppe": {},
	# open field in late summer: drier grass, harder light, longer views
	"field": {
		"ground": [
			Color(0.45, 0.46, 0.25), Color(0.60, 0.53, 0.32), Color(0.30, 0.25, 0.18), Color(0.47, 0.40, 0.29),
			Color(0.32, 0.30, 0.19), Color(0.34, 0.27, 0.19), Color(0.27, 0.22, 0.17), Color(0.42, 0.34, 0.24),
			Color(0.44, 0.41, 0.30), Color(0.17, 0.15, 0.13)],
		"grass": [Color(0.50, 0.50, 0.26), Color(0.62, 0.56, 0.32), Color(0.42, 0.44, 0.22)],
		"crown": [Color(0.26, 0.32, 0.15), Color(0.33, 0.37, 0.17), Color(0.44, 0.40, 0.18), Color(0.48, 0.35, 0.15), Color(0.23, 0.29, 0.14)],
		"spoil": Color(0.64, 0.47, 0.29),   # freshly dug clay on the hill
		"sun_energy": 1.35,
		"sun_rot": Vector3(-48, -28, 0),
		"fog_density": 0.0011,
	},
	# dense forest: darker greens, softer light, thicker haze
	"forest": {
		"crown": [Color(0.17, 0.26, 0.12), Color(0.21, 0.30, 0.13), Color(0.26, 0.31, 0.13), Color(0.32, 0.28, 0.12), Color(0.15, 0.22, 0.11)],
		"sun_energy": 1.1,
		"ambient": 0.5,
		"fog_density": 0.0015,
	},
	# village / town outskirts: same family, a touch of dust
	"village": {"fog_density": 0.0018},
	"urban": {"fog": Color(0.64, 0.64, 0.62), "fog_density": 0.0022, "ambient": 0.58},
	# winter: snow on the ground, bare grey-brown trees, low overcast light
	"winter": {
		"ground": [
			Color(0.86, 0.88, 0.90), Color(0.80, 0.82, 0.85), Color(0.46, 0.43, 0.40), Color(0.60, 0.58, 0.56),
			Color(0.74, 0.76, 0.78), Color(0.32, 0.29, 0.26), Color(0.30, 0.27, 0.25), Color(0.52, 0.49, 0.46),
			Color(0.82, 0.82, 0.83), Color(0.22, 0.21, 0.20)],
		"slope": Color(0.70, 0.72, 0.74),
		"spoil": Color(0.58, 0.56, 0.53),
		"strata": [Color(0.30, 0.27, 0.24), Color(0.50, 0.45, 0.40), Color(0.42, 0.38, 0.34), Color(0.36, 0.32, 0.29)],
		"crown": [Color(0.22, 0.20, 0.18), Color(0.27, 0.24, 0.21), Color(0.19, 0.18, 0.17), Color(0.31, 0.29, 0.26), Color(0.25, 0.22, 0.20)],
		"trunk": Color(0.15, 0.13, 0.12),
		"dead_trunk": Color(0.2, 0.18, 0.17),
		"grass": [Color(0.55, 0.50, 0.40), Color(0.62, 0.58, 0.50), Color(0.48, 0.44, 0.36)],
		"sun": Color(0.92, 0.94, 1.0),
		"sun_energy": 0.75,
		"sun_rot": Vector3(-30, -40, 0),
		"sky_top": Color(0.58, 0.62, 0.66),
		"sky_horizon": Color(0.82, 0.83, 0.84),
		"fog": Color(0.80, 0.82, 0.84),
		"fog_density": 0.0008,
		"ambient": 0.75,
	},
}


static func apply(def: MapDef, preset: String) -> void:
	def.environment = preset
	var p: Dictionary = PRESETS.get(preset, {})
	for k in p.keys():
		def.palette[k] = p[k]
