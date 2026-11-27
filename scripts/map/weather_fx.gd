class_name WeatherFx
extends RefCounted
## Visual side of the weather (Game.WEATHER): sky, light, haze / ground fog,
## wet ground, wind in the trees and rain that follows the drone camera.
## Applied at map build and again whenever the player changes the weather in
## the menu, so it always starts from the map's own baseline.

# per-weather look: grey = how far the sky goes to grey, sun / sat multipliers,
# haze = fog density multiplier, ground = ground-fog strength
const LOOK := {
	"clear":    {"grey": 0.0,  "sun": 1.0,  "sat": 1.0,  "haze": 1.0, "ground": 0.0, "wet": false},
	"overcast": {"grey": 0.6,  "sun": 0.55, "sat": 0.86, "haze": 2.2, "ground": 0.0, "wet": false},
	"rain":     {"grey": 0.85, "sun": 0.42, "sat": 0.78, "haze": 2.6, "ground": 0.0, "wet": true},
	"fog":      {"grey": 0.9,  "sun": 0.5,  "sat": 0.78, "haze": 3.0, "ground": 1.0, "wet": false},
	"wind":     {"grey": 0.25, "sun": 0.95, "sat": 0.95, "haze": 1.6, "ground": 0.0, "wet": false},
}


static func apply(map) -> void:
	var env: Environment = map.environment
	if env == null:
		return
	var psm := env.sky.sky_material as ProceduralSkyMaterial
	var base: Dictionary = map.weather_base
	if base.is_empty():
		base = {"fog": env.fog_density, "fog_col": env.fog_light_color, "sun": map.sun.light_energy,
			"sat": env.adjustment_saturation, "top": psm.sky_top_color, "hor": psm.sky_horizon_color}
		map.weather_base = base
	var look: Dictionary = LOOK.get(Game.weather, LOOK["clear"])
	var g: float = look["grey"]
	psm.sky_top_color = (base["top"] as Color).lerp(Color(0.50, 0.53, 0.56), g)
	psm.sky_horizon_color = (base["hor"] as Color).lerp(Color(0.68, 0.69, 0.70), g)
	psm.ground_horizon_color = psm.sky_horizon_color
	map.sun.light_energy = float(base["sun"]) * float(look["sun"])
	env.adjustment_saturation = float(base["sat"]) * float(look["sat"])
	env.fog_density = float(base["fog"]) * float(look["haze"])
	env.fog_light_color = (base["fog_col"] as Color).lerp(Color(0.74, 0.76, 0.77), g)
	# ground fog: thick near the ground, thinner up where the drone flies
	var gf: float = look["ground"]
	if gf > 0.0:
		env.fog_height = 7.0
		env.fog_height_density = 0.55 * gf
		env.fog_density = 0.007
		env.fog_sky_affect = 0.85
	else:
		env.fog_height = 0.0
		env.fog_height_density = 0.0
		env.fog_sky_affect = 0.4
	# wet ground darkens and gets a little sheen
	if map.terrain_mat:
		map.terrain_mat.albedo_color = Color(0.80, 0.82, 0.84) if look["wet"] else Color.WHITE
		map.terrain_mat.roughness = 0.72 if look["wet"] else 0.97
	# wind in the trees and grass
	var wk: float = clampf(float(Game.wx("wind")), 0.6, 3.0)
	if map.foliage_mat:
		map.foliage_mat.set_shader_parameter("sway", 0.035 * (0.6 + wk * 0.6))
	if map.grass_mat:
		map.grass_mat.set_shader_parameter("sway", 0.12 * (0.6 + wk * 0.5))
	# gameplay: sight fades with distance
	if W.grid:
		W.grid.fog_len = float(Game.wx("fog_len"))
	# rain
	if Game.weather == "rain":
		if map.rain == null:
			map.rain = Rain.new()
			map.add_child(map.rain)
		map.rain.setup()
		map.rain.visible = true
		map.rain.emitting = true
	elif map.rain != null:
		map.rain.emitting = false
		map.rain.visible = false


## Rain streaks in a box that follows the drone camera (cheap: one particle
## system, amount scales with the graphics quality).
class Rain extends GPUParticles3D:
	func setup() -> void:
		var q: Dictionary = Game.quality()
		amount = 6000 if q["ssao"] else (3500 if q["glow"] else 1800)
		lifetime = 1.0
		preprocess = 1.0
		local_coords = false
		visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(55, 1, 55)
		pm.direction = Vector3(0.18, -1.0, 0.06)
		pm.spread = 3.0
		pm.initial_velocity_min = 22.0
		pm.initial_velocity_max = 27.0
		pm.gravity = Vector3.ZERO
		process_material = pm
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.025, 0.85, 0.025)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.78, 0.82, 0.88, 0.32)
		mesh.material = mat
		draw_pass_1 = mesh

	func _process(_d: float) -> void:
		if W.cam and W.cam.cam:
			var c: Vector3 = W.cam.cam.global_position
			var look: Vector3 = -W.cam.cam.global_transform.basis.z
			# rain falls in the low layer above the ground the camera looks at,
			# not right in front of the lens
			var gy: float = W.grid.height_at(c.x, c.z) if W.grid else 0.0
			var t := 60.0
			if look.y < -0.1:
				t = clampf((c.y - gy) / -look.y, 10.0, 160.0)
			var p: Vector3 = c + look * t
			var top := minf(gy + 24.0, c.y - 6.0)
			global_position = Vector3(p.x, top, p.z)
