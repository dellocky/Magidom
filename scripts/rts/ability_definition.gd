extends Resource
## Balance data is shared; cast timers and targets always belong to the unit.

@export var display_name: String = "Lightning Bolt"
@export_multiline var description: String = ""
@export_multiline var lore: String = ""
@export var animation: StringName = &"finger"
@export var damage_type: StringName = &"BAM"
@export var damage: float = 500.0
@export var range_units: float = 600.0
@export var mana_cost: float = 0.0
@export var cooldown: float = 0.0
@export var duration: float = 3.6
@export var release_time: float = 1.82
@export var channel: bool = false
@export var canDamageBuildings: bool = false
## Cast on self with no ground/target pick (used by the Martyr's Human Baneling).
@export var self_cast: bool = false
## hud_glyph.gd draw kind for the ability slot ("whack", "baneling", ...).
@export var glyph: String = ""
@export var radius_units: float = 50.0
@export var growth_per_second: float = 0.25
@export var maximum_radius_bonus: float = 5.0


## Base Melter field tuning. `damage` is applied once per lightning strike.
@export_range(0.0, 0.95, 0.01) var slow_fraction: float = 0.10
@export var strike_radius_units: float = 50.0
@export var baseline_volley_frequency: float = 1.0
@export var baseline_strikes_per_volley: float = 1.0

## Strike throughput is measured against this fixed radius, not radius_units.
const REFERENCE_RADIUS_UNITS: float = 50.0


func radius_at(seconds: float) -> float:
	return radius_units * (1.0 + minf(maxf(seconds, 0.0) * growth_per_second, maximum_radius_bonus))


func rate_scale(effective_radius_units: float) -> float:
	if not is_finite(effective_radius_units) or effective_radius_units <= 0.0:
		return 0.0
	return effective_radius_units / REFERENCE_RADIUS_UNITS


func volley_frequency_at(effective_radius_units: float) -> float:
	return maxf(baseline_volley_frequency, 0.0) * rate_scale(effective_radius_units)


func strikes_per_volley_at(effective_radius_units: float) -> float:
	return maxf(baseline_strikes_per_volley, 0.0) * rate_scale(effective_radius_units)
