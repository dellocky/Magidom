extends Resource
## A faction-level player spell. Global spells are cast from anywhere (no cast
## range) and land as a ground-target AoE. The only effect shipped so far is the
## Warlock frenzy (move-speed buff + health burn); extend this for future spells.

@export var display_name: String = "Global Spell"
@export var icon_kind: String = "buff"
@export var key: String = "1"
@export_multiline var description: String = ""
@export_multiline var lore: String = ""
@export var mana_cost: float = 150.0
@export var cooldown: float = 15.0
@export_range(0.0, 10000.0) var aoe_radius_units: float = 500.0
@export var duration: float = 10.0
## Multiplier added to move speed while the buff holds (0.5 = +50%).
@export_range(-2.0, 5.0) var move_speed_bonus_fraction: float = 0.5
## Fraction of max health burned every second while the buff holds.
@export_range(0.0, 1.0) var hp_drain_fraction_per_second: float = 0.05