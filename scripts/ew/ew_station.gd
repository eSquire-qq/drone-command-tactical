class_name EwStation
extends Node3D
## Enemy electronic-warfare post (РЕБ/РЕР): antenna mast + shelter.
## Jams our recon drone and FPV links within `radius`. Destructible.

var side := 1
var radius := 95.0
var hp := 130.0
var decoy := false
var destroyed := false
var ever_seen := false
var marked := false
var title := "РЕБ"
var model: Node3D


func setup(rng: RandomNumberGenerator) -> void:
	model = MapModels.ew_station(rng)
	add_child(model)
	var led = MF.part(model, MF.box(0.08, 0.08, 0.08), MF.glow(Color(1, 0.3, 0.2), 4.0), Vector3(-0.5, 7.05, 0), Vector3.ZERO, Vector3.ONE, false)
	var tw = create_tween().set_loops()
	tw.tween_property(led, "visible", false, 0.6)
	tw.tween_property(led, "visible", true, 0.6)


func aim_point() -> Vector3:
	return global_position + Vector3(0, 0.8, 0)


## Dug-in and covered: area fire (mortar, HE, grenades) only matters on a
## near-direct hit; FPV / ATGM (kind "direct") hit it properly.
func take_damage(amount: float, _source, kind: String = "direct", dist: float = 0.0) -> void:
	if destroyed:
		return
	if kind != "direct" and kind != "fpv" and kind != "at":
		amount *= 0.6 if dist < 1.2 else 0.04
	hp -= amount
	if hp <= 0.0:
		destroyed = true
		marked = false
		W.fx.explosion(global_position + Vector3(0, 0.8, 0), 3.5)
		if not decoy:
			W.fx.burning(global_position + Vector3(0, 0.5, 0), false)
		var tw = create_tween()
		tw.tween_property(model, "rotation", Vector3(0.0, 0.0, 1.3), 0.8)
		tw.parallel().tween_property(model, "position", Vector3(0, -0.3, 0), 0.8)
		if W.ew:
			W.ew.on_station_destroyed(self)
