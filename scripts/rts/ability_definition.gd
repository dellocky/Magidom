extends Resource
## Balance data is shared; cast timers and targets always belong to the unit.

@export var display_name: String = "Lightning Bolt"
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
@export var radius_units: float = 50.0
@export var growth_per_second: float = 0.25
@export var maximum_damage_bonus: float = 1.0
@export var maximum_radius_bonus: float = 5.0


func damage_at(seconds: float) -> float:
	return damage * (1.0 + minf(maxf(seconds, 0.0) * growth_per_second, maximum_damage_bonus))


func radius_at(seconds: float) -> float:
	return radius_units * (1.0 + minf(maxf(seconds, 0.0) * growth_per_second, maximum_radius_bonus))


func damage_integral(seconds: float) -> float:
	var t := clampf(seconds, 0.0, duration)
	if growth_per_second <= 0.0:
		return damage * t
	var ramp := minf(t, maximum_damage_bonus / growth_per_second)
	return damage * (ramp + 0.5 * growth_per_second * ramp * ramp + (t - ramp) * (1.0 + maximum_damage_bonus))
