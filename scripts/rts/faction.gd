extends Resource
## One playable faction: identity, allied unit template, and player global spell.

@export var id: StringName = &""
@export var display_name: String = ""
@export var color: Color = Color(0.38, 0.82, 1.0)
@export_multiline var description: String = ""
## Allied unit spawned for this faction. Null while the faction has no unit yet.
@export var unit_scene: PackedScene
## Human-readable name for the allied unit shown on the spawn button.
@export var unit_display_name: String = ""
## Player global spell for this faction. Null while the faction has none yet.
@export var global_spell: Resource