extends Node
## World registry: holds references to the running systems and the entity
## lists of the current mission. Reset on every mission load.

var map = null        # MapManager
var grid = null       # TerrainGrid
var combat = null     # CombatSystem
var damage = null     # DamageSystem
var fx = null         # FxSystem
var sfx = null        # Sfx
var evac = null       # EvacuationSystem
var mission = null    # MissionManager
var enemy_ai = null   # EnemyAI
var cam = null        # DroneCamera
var command = null    # CommandController
var ui = null         # UIManager
var ew = null         # EwSystem
var mines = null      # MineSystem
var prisoners = null  # PrisonerSystem
var intel = null      # IntelSystem (what the commander knows)
var blog = null       # BattleLog (after action review)
var radio = null      # RadioSystem (reports with delay)
var field = null      # Battlefield (craters, cover damage, smoke drift)

var units: Array = []
var vehicles: Array = []
var squads: Array = []
var bunkers: Array = []
var smoke_clouds: Array = []   # {pos: Vector3, r: float, end: float}
var time := 0.0
var photo_mode := false


func reset() -> void:
	units.clear()
	vehicles.clear()
	squads.clear()
	bunkers.clear()
	smoke_clouds.clear()
	time = 0.0
	photo_mode = false
	Engine.time_scale = 1.0


func is_alive_target(e) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	if e is Soldier:
		return (e.health == Soldier.H.HEALTHY or e.health == Soldier.H.WOUNDED) and not e.evacuated and e.vehicle == null and not e.surrendered
	if e is Vehicle:
		return e.state != "destroyed" and not e.offmap
	if e is Bunker or e is EwStation:
		return not e.destroyed
	return false


func opponents(side: int) -> Array:
	var out: Array = []
	for u in units:
		if u.side != side and is_alive_target(u):
			out.append(u)
	for v in vehicles:
		if v.side != side and is_alive_target(v):
			out.append(v)
	return out


func soldiers(side: int) -> Array:
	var out: Array = []
	for u in units:
		if u.side == side:
			out.append(u)
	return out


func running() -> bool:
	return mission != null and mission.running()


func update_smoke() -> void:
	var i := smoke_clouds.size() - 1
	while i >= 0:
		if smoke_clouds[i]["end"] < time:
			smoke_clouds.remove_at(i)
		i -= 1
