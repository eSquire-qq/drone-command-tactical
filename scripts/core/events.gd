extends Node
## Global event bus. Systems talk to each other through these signals
## instead of holding hard references where possible.

signal message(text: String, kind: String)
signal unit_state_changed(unit, old_state: int, new_state: int)
signal enemy_spotted(unit)
signal vehicle_destroyed(vehicle)
signal squad_help_requested(squad)
signal selection_changed()
signal phase_changed(phase: int)
signal mission_ended(result: Dictionary)
signal radio_entry(entry: Dictionary)
## The deployment point picked on the briefing photo changed (Game.deploy).
signal deploy_changed


func msg(text: String, kind: String = "info") -> void:
	message.emit(text, kind)
