extends SceneTree

const Vision = preload("res://scripts/rts/vision_system.gd")
const UnitScene = preload("res://units/hawkRider/hawk_rider_unit.tscn")
const Controller = preload("res://scripts/rts/rts_controller.gd")
var checks := 0
var failures := 0
var arena: Node3D
var vision: Node


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)


func spawn(team: int, point: Vector3) -> Node3D:
	var unit: Node3D = UnitScene.instantiate()
	unit.team = team
	unit.position = point
	unit.vision_system = vision
	unit.effects_enabled = false
	arena.add_child(unit)
	unit.set_physics_process(false)
	vision.register_unit(unit)
	return unit


func run() -> void:
	arena = Node3D.new()
	root.add_child(arena)
	vision = Vision.new()
	arena.add_child(vision)
	vision.set_process(false)
	var ally := spawn(0, Vector3(0, 0.5, 0))
	var enemy := spawn(1, Vector3(50, 0.5, 0))
	check(vision.can_see_unit(0, enemy), "1000-unit sight includes exact 50-metre boundary")
	enemy.position.x = 50.01
	check(not vision.can_see_unit(0, enemy), "outside sight boundary hidden")
	check(not vision.can_see_point(0, Vector3(70, 0.5, 0)), "enemy sight does not reveal player terrain")
	check(vision.controls(ally) and not vision.controls(enemy), "fog mode controls player team only")
	vision.refresh_unit_visibility()
	check(enemy.is_fog_hidden() and not enemy.visible and enemy.get_node("PickBody").collision_layer == 0, "hidden enemy has no visual or pick collider")
	check(not ally.issue_attack(enemy), "targeted orders reject hidden enemy")
	var scout := spawn(0, Vector3(45, 0.5, 0))
	scout.stats.vision_range = 200
	vision.refresh_unit_visibility()
	check(vision.can_see_unit(0, enemy) and enemy.visible, "allied scout reveals opponent")
	check(ally.stats.vision_range == 1000 and scout.stats.vision_range == 200, "vision stats are instance-specific")
	scout.position = Vector3(-45, 0.5, -45)
	check(not vision.can_see_unit(0, enemy), "moving scout removes shared sight")
	ally.stats.vision_range = 20
	vision.refresh_mask()
	check(vision.is_explored(ally.position), "current sight explores terrain")
	check(not vision.is_explored(Vector3(45, 0.5, 45)), "unvisited terrain remains black")
	ally.position = Vector3(-30, 0.5, 0)
	vision.refresh_mask()
	check(vision.is_explored(Vector3.ZERO) and not vision.can_see_point(0, Vector3.ZERO), "exploration persists without current sight")
	check(vision.world_to_uv(Vector3(-50, 0, -50)) == Vector2.ZERO and vision.world_to_uv(Vector3(50, 0, 50)) == Vector2.ONE, "shared minimap bounds map correctly")
	vision.fog_enabled = false
	vision.refresh_mask()
	vision.refresh_unit_visibility()
	check(vision.can_see_unit(0, enemy) and enemy.visible and vision.controls(enemy), "debug reveals enemies and restores sandbox controls")
	check(enemy.get_node("PickBody").collision_layer == 2, "debug restores pick collision")
	vision.fog_enabled = true
	vision.refresh_mask()
	check(not vision.is_explored(Vector3(45, 0.5, 45)), "debug reveal does not permanently explore map")
	vision.player_team = 1
	vision.refresh_mask()
	check(not vision.is_explored(Vector3(-45, 0.5, -45)), "changing player team does not inherit exploration")
	vision.player_team = 0
	ally.stats.vision_range = 1000
	ally.position = Vector3.ZERO
	enemy.position = Vector3(20, 0.5, 0)
	check(ally.issue_attack(enemy), "targeted order accepted in real shared sight")
	ally.advance_simulation(0.01)
	check(ally.state == 3, "visible target begins bolt")
	enemy.position.x = 70
	ally.advance_simulation(2.0)
	check(enemy.health == 500, "real vision revalidated at bolt release")
	ally.advance_simulation(3.0)
	check(ally.state == 0, "lost target is not tracked after bolt")
	# A scout's death removes vision immediately, even during its death animation.
	scout.position = Vector3(40, 0.5, 40)
	enemy.position = Vector3(42, 0.5, 40)
	check(vision.can_see_unit(0, enemy), "scout reveals before death")
	scout.receive_damage(enemy, 9999, &"BAM")
	vision.refresh_unit_visibility()
	check(not vision.can_see_unit(0, enemy) and enemy.is_fog_hidden(), "dead scout grants no sight")
	check(not vision.controls(scout), "dead allies cannot be controlled")
	scout.free()
	vision.refresh_unit_visibility()
	check(not vision.can_see_unit(0, enemy), "freed scout leaves no vision provider")
	arena.free()
	# Full-scene wiring: serialized HUD, fog service, shader and controller.
	var level: Node3D = load("res://scenes/testLevel.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	check(level.hud.get_minimap().vision_system == level.vision_system, "scene minimap shares vision service")
	check(level.hud.get_overlay().vision_system == level.vision_system, "world bars share vision service")
	var friendly: Node3D = level.units.get_child(0)
	var opponent: Node3D = level.units.get_child(1)
	level.controller.set_selection([friendly, opponent])
	check(level.controller.selected == [friendly], "controller filters enemy selection")
	level.fog_enabled = false
	await process_frame
	await process_frame
	level.controller.set_selection([friendly, opponent])
	check(level.controller.selected.size() == 2, "root debug toggle restores both-team selection")
	level.fog_enabled = true
	await process_frame
	await process_frame
	check(level.controller.selected == [friendly], "enabling fog prunes unauthorized selection")
	level.free()
	print("VISION_TESTS: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)
