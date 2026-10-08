extends Node

const LevelScene = preload("res://scenes/testLevel.tscn")
var level: Node3D
var failures: int = 0


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("LIVE_SMOKE FAIL: " + description)
	else:
		print("LIVE_SMOKE PASS: " + description)


func click_world(point: Vector3) -> void:
	var screen: Vector2 = level.rig.camera.unproject_position(point)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.position = screen
		event.global_position = screen
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame


func start_whack(unit: Node3D, enemy: Node3D) -> void:
	unit.position = Vector3(-3, 0.5, 0)
	enemy.position = Vector3(0, 0.5, 0)
	unit.bolt_cooldown_remaining = 0.0
	await get_tree().physics_frame
	await click_world(enemy.get_selection_ring_position())
	for frame in 5:
		await get_tree().physics_frame
	check(unit.state == unit.State.BOLT, "RMB enters Whack")


func _ready() -> void:
	get_node("/root/GameState").set_faction(&"warlocks")
	level = LevelScene.instantiate()
	level.fog_enabled = false
	add_child(level)
	await get_tree().process_frame
	var unit: Node3D = level.units.get_child(0)
	var enemy: Node3D = level.units.get_child(1)
	level.rig.set_process(false)
	level.controller.set_selection([unit])
	check(unit.unit_name == "Martyr", "level spawns Martyr scene through faction")
	await start_whack(unit, enemy)
	await click_world(Vector3(-9, 0.5, -5))
	check(unit.state == unit.State.MOVING, "RMB ground overrides Whack")
	await start_whack(unit, enemy)
	level.hud.stop_requested.emit()
	check(unit.state == unit.State.IDLE, "HUD Stop overrides Whack")
	await start_whack(unit, enemy)
	var second_enemy: Node3D = level.spawn_unit(1)
	second_enemy.position = Vector3(6, 0.5, 3)
	await click_world(second_enemy.get_selection_ring_position())
	check(unit.attack_target == second_enemy and unit.state == unit.State.CHASING, "RMB enemy retargets during Whack cooldown")
	await start_whack(unit, enemy)
	level.hud.melter_requested.emit()
	check(unit.baneling_armed and unit.player.current_animation == "sillyrun", "Suicide button interrupts Whack and plays sillyrun")
	check(unit.is_alive() and unit.state == unit.State.CHASING, "Suicide leaves Martyr alive and chasing outside contact")
	level.hud.stop_requested.emit()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/gavin/AppData/Local/Temp/magidom-martyr-armed-019d5ee9.png")
	check(unit.is_alive() and unit.baneling_armed, "armed Martyr survives at melee range while stopped")
	var enemy_health: float = enemy.health
	await click_world(enemy.get_selection_ring_position())
	for frame in 120:
		if not is_instance_valid(unit) or not unit.is_alive():
			break
		await get_tree().physics_frame
	check(not is_instance_valid(unit) or not unit.is_alive(), "armed RMB charge detonates on contact")
	check(enemy.health == enemy_health - 200.0, "contact blast deals exactly 200 damage")
	await get_tree().create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/gavin/AppData/Local/Temp/magidom-martyr-blast-019d5ee9.png")
	print("LIVE_SMOKE: ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
