extends Resource

@export var display_name: String = "Hawk Rider"
@export var move_speed: float = 100.0
@export var attack_damage: float = 999.0
@export var armor: float = 1.0
@export var max_health: float = 500.0
@export var max_mana: float = 200.0
@export_range(1.0, 10000.0, 1.0, "or_greater") var vision_range: float = 1000.0
