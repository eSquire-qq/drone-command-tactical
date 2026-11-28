class_name Bunker
extends Node3D
## Destructible fortification (MG nest or dugout) that shelters occupants.

var kind = "mg"
var side = 1
var hp = 260.0
var destroyed = false
var damaged = false
var max_hp = 260.0
var occupants: Array = []
var face = Vector3(0, 0, 1)
var revealed = 0.0     # seconds the player still sees it marked
var ever_seen = false
var marked = false
var model: Node3D
var title = "ДЗОТ"


func setup(p_kind: String, p_face: Vector3, rng: RandomNumberGenerator) -> void:
	kind = p_kind
	face = p_face.normalized()
	title = {"mg": Loc.t("ДЗОТ"), "dugout": Loc.t("БЛІНДАЖ"), "depot": Loc.t("СКЛАД БК")}.get(kind, Loc.t("ДЗОТ"))
	hp = {"mg": 260.0, "dugout": 320.0, "depot": AIConfig.DEPOT_HP}.get(kind, 260.0)
	max_hp = hp
	model = Props.depot(rng) if kind == "depot" else Props.bunker(kind, rng)
	add_child(model)
	rotation.y = MF.yaw_facing(face)


func aim_point() -> Vector3:
	return global_position + Vector3(0, 0.9, 0)


func is_revealed() -> bool:
	return ever_seen and not destroyed


func _process(delta: float) -> void:
	if not Prof.on:
		_process_body(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_body(delta)
	Prof.add("bunker", t0)


func _process_body(delta: float) -> void:
	if revealed > 0.0:
		revealed -= delta


func take_damage(amount: float, source) -> void:
	if destroyed:
		return
	hp -= amount
	if hp <= 0.0:
		_destroy(source)
	elif not damaged and hp < max_hp * AIConfig.BUNKER_DAMAGED_HP:
		_damage()


## Half the logs and earth gone: still a shelter, but a worse one.
func _damage() -> void:
	damaged = true
	model.rotation = Vector3(randf_range(-0.06, 0.06), 0, randf_range(-0.06, 0.06))
	model.scale = Vector3(1.0, 0.85, 1.0)
	for c in model.get_children():
		if c is MeshInstance3D:
			var m: StandardMaterial3D = c.material_override
			if m:
				c.material_override = MF.mat(m.albedo_color.darkened(0.25))
	var c2 = W.grid.cidx(global_position.x, global_position.z)
	W.grid.cover[c2] = minf(W.grid.cover[c2], 0.88 * AIConfig.BUNKER_DAMAGED_PROT)
	W.fx.scorch(global_position, 3.0)
	if W.field:
		W.field.stats["damaged"] += 1
	if W.blog:
		W.blog.add("field", Loc.t("%s пошкоджено") % title, global_position)


func _destroy(source) -> void:
	destroyed = true
	marked = false
	W.fx.explosion(global_position + Vector3(0, 0.8, 0), 5.0)
	W.fx.burning(global_position + Vector3(0, 0.6, 0), false)
	W.sfx.play("explosion", global_position, 4.0)
	# collapse
	var tw = create_tween()
	tw.tween_property(model, "scale", Vector3(1.05, 0.35, 1.05), 0.6)
	for c in model.get_children():
		if c is MeshInstance3D:
			var m: StandardMaterial3D = c.material_override
			if m:
				c.material_override = MF.mat(m.albedo_color.darkened(0.55))
	for u in occupants.duplicate():
		if u.health == Soldier.H.DEAD:
			continue
		u.bunker = null
		u.bunker_deep = false
		var r = randf()
		if r < 0.6:
			W.damage.set_health(u, Soldier.H.DEAD, source, "bunker")
		elif r < 0.9:
			W.damage.set_health(u, Soldier.H.INCAP, source, "bunker")
		else:
			W.damage.apply(u, 70.0, source, true)
	occupants.clear()
	if side == 1:
		Events.msg(Loc.t("%s знищено!") % title, "good")
	if kind == "depot":
		_cook_off(source)
	var c = W.grid.cidx(global_position.x, global_position.z)
	W.grid.cover[c] = 0.5


## The ammunition goes up: a big blast at once, then rounds cooking off for
## a few seconds — dangerous to anybody standing close.
func _cook_off(source) -> void:
	if W.blog:
		W.blog.add("field", Loc.t("Склад БК вибухнув"), global_position)
	var p := global_position + Vector3(0, 0.6, 0)
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if W.running():
			W.combat.explosion(p, AIConfig.DEPOT_BLAST_R, AIConfig.DEPOT_BLAST, source)
			W.fx.explosion(p + Vector3(0, 1.0, 0), 9.0)
			if W.cam:
				W.cam.shake(p, 1.6))
	for k in 6:
		get_tree().create_timer(1.2 + k * randf_range(0.6, 1.3)).timeout.connect(func() -> void:
			if W.running():
				var q := p + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
				W.combat.explosion(q, 3.0, 40.0, source)
				W.sfx.play("explosion", q, 2.0))


func release_occupant(u) -> void:
	occupants.erase(u)
	u.bunker = null
	u.bunker_deep = false
