# Drone Command: Tactical

A real-time tactical game about commanding a small combined-arms unit through
the eyes of a reconnaissance drone. You plan the force, pick where the column
goes in, and give orders to squads and vehicles. The soldiers decide for
themselves how to stay alive: they choose their cover and targets, react to
fire, carry the wounded and fall back.

The game is in development, heading for a Steam demo. It is playable in
Ukrainian and English.

![engine](https://img.shields.io/badge/Godot-4.7-478cbf) ![lang](https://img.shields.io/badge/GDScript-100%25-blue)

## What is in the game

- **Six maps.** A training ground, a tree line, an open height, a farmstead,
  a pine forest, and a 560 m winter city district. There is also a linear
  campaign where losses, experience and the enemy's response carry over
  between battles.
- **The drone.** It flies with inertia and has an optical zoom. Enemy jamming
  can cut the link, and you can launch a spare drone.
- **Your soldiers.** They are individuals with suppression, morale, stress,
  ammunition and personal reaction times. They pick cover against the known
  threat, clear trenches and buildings, and evacuate casualties.
- **The enemy.** A commander that shifts forces to threatened sectors,
  withdraws under smoke with a rearguard, flies a recon drone that guides its
  mortar and FPV drones, and brings up reinforcements, armour included.
- **Fog of war.** Your men only fire at what they have seen. The briefing
  shows an aerial photo, and its intel can be stale.
- **Destruction.** Craters change the terrain, walls get breached and trees
  are felled.

## Running it

1. Install **Godot 4.7** (the standard build, not .NET).
2. Open `project.godot`, wait for the first import, then press **F5**.

Exported builds are made from *Project → Export* with the `Windows Desktop`
and `macOS` presets.

## Project layout

| Folder | What is inside |
| --- | --- |
| `scripts/core` | the world registry (`W`), events, game settings, balance data, campaign, localisation (`Loc`) |
| `scripts/units`, `scripts/ai` | soldiers, squads, soldier AI, the enemy commander, the shared AI tuning (`AIConfig`) |
| `scripts/vehicles`, `scripts/combat` | vehicles, fire, damage, effects, FPV and recon drones, mines |
| `scripts/map` | map data, map builder, terrain grid, line of sight, navigation, map scripts (`maps/`) |
| `scripts/map/editor`, `addons/map_editor` | the in-editor map tools (the «Карта» main screen tab) |
| `scripts/mission`, `scripts/evac`, `scripts/ew` | mission flow, objectives, intel, radio, buildings, evacuation, electronic warfare |
| `scripts/ui` | menus, briefing, planning, HUD, markers, minimap, after-action report |
| `scripts/debug` | automated tests and the balance bot |
| `maps` | the official maps as editable scenes, plus baked terrain heights |
| `locale` | translations (`en.po`, keyed by the Ukrainian text) |
| `tools` | Python helpers: translation (`i18n.py`) and the soak test (`soak.py`) |
| `docs` | design notes, the roadmap, the demo plan, guides (in Ukrainian) |

## Testing

Everything runs headless from the command line (`godot --headless --path . -- <args>`):

- `--balance=smart --map=<id>`: the balance bot plays a battle and prints the result.
- `--map=training --aitest=<name>`: controlled AI scenarios (cover, fire,
  react, leader, assault, building, controls…), listed in
  `scripts/debug/ai_tests.gd`.
- `--autotest [--map=<id>]`: a full automated mission, with optional
  screenshots via `--shots=<dir>`.
- `python tools/soak.py`: every map in both languages, several runs each. It
  writes a report with script errors, stuck units, endless battles, frame time
  and memory. Set `GODOT` to point at the editor binary.

## Translations

The Ukrainian text in the code is the translation key: `Loc.t("Текст")`. To
add or update English, run `python -X utf8 tools/i18n.py pot`, translate the
entries listed in `locale/todo_en.txt`, then run `apply`. See
`docs/LOCALIZATION.md`.

## Maps

Maps are Godot scenes (`maps/*.tscn`) built from map nodes. You can edit them
in the «Карта» tab with real models, a library of objects and the relief tools.
See `docs/MAP_EDITOR.md`.

## License

All rights reserved. See `LICENSE`.
