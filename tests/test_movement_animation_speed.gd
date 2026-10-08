extends SceneTree

const SCENES := [
	preload("res://units/hawkRider/hawk_rider_unit.tscn"),
	preload("res://units/martyr/martyr_unit.tscn"),
]
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	for scene: PackedScene in SCENES:
		var unit = scene.instantiate()
		unit.effects_enabled = false
		root.add_child(unit)
		unit.set_physics_process(false)
		unit.destination = Vector3(40, 0, 0)
		unit._set_state(unit.State.MOVING)
		unit.advance_simulation(0.05)
		check(is_equal_approx(unit.player.current_animation_position, 0.05), "Normal movement playback")
		unit.apply_frenzy(1.0, 0.0, 10.0)
		unit._set_state(unit.State.MOVING)
		unit.player.seek(0.0, true)
		unit.advance_simulation(0.05)
		check(is_equal_approx(unit.player.current_animation_position, 0.1), "Double speed doubles movement playback")
		unit._set_state(unit.State.IDLE)
		unit.advance_simulation(0.05)
		check(is_equal_approx(unit.player.current_animation_position, 0.05), "Idle remains unchanged")
		unit.state = unit.State.BOLT
		check(is_equal_approx(unit._movement_animation_delta(0.05), 0.05), "Attack timing remains unchanged")
		unit.frenzy_move_bonus = 0.0
		unit.stats.move_speed *= 0.5
		unit.state = unit.State.CHASING
		check(is_equal_approx(unit._movement_animation_delta(0.05), 0.025), "Reduced speed slows chase playback")
		if unit.has_method("move_clip"):
			unit.baneling_armed = true
			unit._set_state(unit.State.MOVING)
			unit.advance_simulation(0.05)
			check(unit.player.current_animation == "sillyrun" and is_equal_approx(unit.player.current_animation_position, 0.025), "Silly run scales too")
		unit.free()
	print("Movement animation speed: ", failures, " failures")
	quit(0 if failures == 0 else 1)
