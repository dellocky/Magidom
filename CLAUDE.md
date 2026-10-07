# Magidom

An RTS game built in Godot 4.

## Unit spawning convention

Units are spawned from script by instantiating the unit's own scene file. Keep
this one pattern everywhere:

- Each playable unit is defined by a single-scene source of truth at
  `units/<unit>/<unit>_unit.tscn` (e.g.
  `res://units/hawkRider/hawk_rider_unit.tscn`). That scene's root is a
  `Node3D` carrying the unit script (`scripts/rts/rts_unit.gd`), with a
  `Visual` child (the instanced model) and its pick/collision body.
- To spawn a unit, `preload()` that unit scene once (a `const`), then call
  `instantiate()` per copy, configure `team` / `vision_system`, and
  `add_child()` it into a single `units` container node.
  `scripts/rts/test_level.gd`'s `spawn_unit()` is the reference implementation:
  preload at the top, one clear `spawn_unit(team)` function used by both the
  initial spawns and the HUD's `spawn_requested` signal.

Goals: keep unit logic/data living in the unit's scene (not hand-built in
code), and keep spawning routed through one obvious function per level rather
than scattered instantiation calls.