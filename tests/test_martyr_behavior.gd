extends SceneTree

const Units = preload("res://scripts/rts/game_units.gd")
const UnitScene = preload("res://units/martyr/martyr_unit.tscn")
var checks: int = 0
var failures: int = 0
var units: Node3D


class FakeVision extends Node:
	var fog_enabled: bool = true
	var player_team: int = 0

	func can_see_unit(_team: int, _unit: Node3D) -> bool:
		return false


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)


func spawn(team: int, point: Vector3 = Vector3(0, 0.5, 0), vision: Node = null) -> Node3D:
	var unit: Node3D = UnitScene.instantiate()
	unit.team = team
	unit.vision_system = vision
	unit.position = point
	unit.effects_enabled = false
	units.add_child(unit)
	unit.set_physics_process(false)
	return unit


func clear_units() -> void:
	for unit in units.get_children():
		unit.free()


func step(unit: Node3D, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.00001:
		var delta := minf(remaining, 0.01)
		unit.advance_simulation(delta)
		remaining -= delta


func test_interruptions() -> void:
	for after_release in [false, true]:
		for command in ["move", "stop", "retarget", "arm"]:
			clear_units()
			var unit := spawn(0)
			var enemy := spawn(1, Vector3(3, 0.5, 0))
			var next_enemy := spawn(1, Vector3(-3, 0.5, 0))
			var health_before: float = enemy.health
			var label := "%s %s release" % [command, "after" if after_release else "before"]
			check(unit.issue_attack(enemy), label + ": accepts initial attack")
			step(unit, 0.45 if after_release else 0.1)
			check(unit.state == unit.State.BOLT and unit.accepts_orders(), label + ": whack accepts orders")
			var hits: int = 1 if after_release else 0
			check(unit.release_count == hits, label + ": expected hit count before interruption")
			var cooldown: float = unit.bolt_cooldown_remaining
			match command:
				"move":
					check(unit.issue_move(Vector3(-20, 0.5, -20)), label + ": move overrides attack")
					check(unit.state == unit.State.MOVING and unit.attack_target == null, label + ": moves without target")
				"stop":
					check(unit.issue_stop(), label + ": stop overrides attack")
					check(unit.state == unit.State.IDLE and unit.attack_target == null, label + ": clears attack")
				"retarget":
					check(unit.issue_attack(next_enemy), label + ": retarget accepted during cooldown")
					check(unit.state == unit.State.CHASING and unit.attack_target == next_enemy, label + ": new target selected")
				"arm":
					check(unit.issue_cast_melter(unit.global_position), label + ": Suicide overrides attack")
					check(unit.baneling_armed and unit.state == unit.State.CHASING, label + ": armed chase")
					check(unit.player.current_animation == "sillyrun", label + ": switches to silly run immediately")
					check(not unit.can_cast_bolt(), label + ": no whack while armed")
			check(is_equal_approx(unit.bolt_cooldown_remaining, cooldown), label + ": no cooldown refund")
			if command == "arm":
				step(unit, 0.01)
				check(unit.is_alive() and unit.global_position.x > 0.0, label + ": closes distance instead of instant blast")
				unit.issue_stop()
			if command == "retarget":
				step(unit, cooldown * 0.5)
				check(unit.release_count == hits, label + ": waits for cooldown")
				step(unit, cooldown * 0.5 + unit.bolt.release_time + 0.05)
				check(unit.release_count == hits + 1, label + ": exactly one new hit")
				check(is_equal_approx(next_enemy.health, next_enemy.stats.max_health - unit.bolt.damage), label + ": new target takes hit")
				unit.issue_stop()
			step(unit, 3.0)
			check(is_equal_approx(enemy.health, health_before - hits * unit.bolt.damage), label + ": no delayed hit on old target")
			check(unit.release_count == hits + (1 if command == "retarget" else 0), label + ": no duplicate release")


func test_arming_orders() -> void:
	clear_units()
	var unit := spawn(0)
	var enemy := spawn(1, Vector3(15, 0.5, 0))
	unit.melter = unit.melter.duplicate()
	unit.melter.mana_cost = 3.0
	unit.mana = 5.0
	var point := Vector3(20, 0.5, 0)
	unit.issue_move(point)
	check(unit.issue_cast_melter(Vector3.ZERO), "arm during movement")
	check(unit.state == unit.State.MOVING and unit.destination == point, "arming preserves move destination")
	check(unit.player.current_animation == "sillyrun", "armed movement uses silly run")
	check(unit.mana == 2.0 and unit.melter_cooldown_remaining == unit.melter.cooldown, "arming spends mana and starts cooldown")
	check(not unit.issue_cast_melter(Vector3.ZERO) and unit.mana == 2.0, "cannot arm or spend mana twice")
	step(unit, 0.1)
	check(unit.is_alive() and unit.global_position.x > 0.0, "armed move advances safely with distant enemy")
	check(unit.issue_stop() and unit.baneling_armed, "Stop leaves Suicide armed")
	var stopped_at: Vector3 = unit.global_position
	step(unit, 1.0)
	check(unit.global_position == stopped_at and unit.is_alive(), "armed Stop stays still without auto-seeking")
	check(unit.issue_attack(enemy), "armed unit accepts attack order")
	check(unit.attack_target == enemy and unit.state == unit.State.CHASING, "armed attack chases enemy")
	check(unit.issue_move(point), "armed chase can be replaced by movement")
	step(unit, 3.0)
	check(not unit.is_alive() and not unit.baneling_armed, "armed movement explodes on enemy contact")
	check(unit.release_count == 0, "armed unit never whacks")
	check(enemy.health == enemy.stats.max_health - unit.melter.damage, "contact applies blast damage")
	check(not unit.issue_move(point) and not unit.issue_stop() and not unit.issue_attack(enemy), "dead Martyr rejects orders")

	clear_units()
	unit = spawn(0)
	enemy = spawn(1, Vector3(10, 0.5, 0))
	unit.issue_attack(enemy)
	unit.issue_cast_melter(Vector3.ZERO)
	check(unit.state == unit.State.CHASING and unit.attack_target == enemy, "arming preserves existing chase")
	step(unit, 2.0)
	check(not unit.is_alive() and unit.release_count == 0, "armed chase detonates without attacking")

	clear_units()
	unit = spawn(0)
	enemy = spawn(1, Vector3(3, 0.5, 0))
	unit.issue_attack(enemy)
	step(unit, 0.1)
	enemy.free()
	check(unit.issue_cast_melter(Vector3.ZERO), "can arm after whack target disappears")
	check(unit.state == unit.State.IDLE and unit.attack_target == null and unit.baneling_armed, "lost target leaves armed idle")
	check(unit.player.current_animation == "sillyrun", "lost target still switches to silly run")


func test_contact_range() -> void:
	clear_units()
	var unit := spawn(0)
	var enemy := spawn(1, Vector3(10, 0.5, 0))
	var ally := spawn(0, Vector3(1, 0.5, 0))
	var dead_enemy := spawn(1, Vector3(1, 0.5, 0))
	dead_enemy.health = 0.0
	check(unit.issue_cast_melter(Vector3.ZERO), "arm while idle")
	step(unit, 1.0)
	check(unit.is_alive() and unit.baneling_armed, "distant enemy, ally and dead enemy do not trigger blast")
	check(unit.global_position == Vector3(0, 0.5, 0), "arming does not invent a movement order")
	enemy.position.x = Units.to_metres(unit.CONTACT_RANGE_UNITS + 2.0)
	step(unit, 0.01)
	check(unit.is_alive(), "42 gameplay units is outside contact range")
	var blast_neighbor := spawn(1, Vector3(2.4, 0.5, 0))
	var outside_blast := spawn(1, Vector3(2.6, 0.5, 0))
	enemy.position.x = Units.to_metres(unit.CONTACT_RANGE_UNITS)
	step(unit, 0.01)
	check(not unit.is_alive(), "40 gameplay units is contact, not 40 metres")
	check(enemy.health == enemy.stats.max_health - unit.melter.damage, "contact victim takes blast damage")
	check(blast_neighbor.health == blast_neighbor.stats.max_health - unit.melter.damage, "nearby enemy inside 50-unit blast takes damage")
	check(outside_blast.health == outside_blast.stats.max_health, "enemy beyond blast is untouched")
	check(ally.health == ally.stats.max_health, "blast does not hurt allies")
	var remaining_health: float = enemy.health
	step(unit, 1.0)
	check(enemy.health == remaining_health, "blast occurs only once")

	clear_units()
	var vision := FakeVision.new()
	root.add_child(vision)
	unit = spawn(0, Vector3(0, 0.5, 0), vision)
	spawn(1, Vector3(1, 0.5, 0))
	unit.issue_cast_melter(Vector3.ZERO)
	step(unit, 0.01)
	check(unit.is_alive(), "contact preserves existing visibility rules")
	clear_units()
	vision.free()


func run() -> void:
	units = Node3D.new()
	units.name = "Units"
	root.add_child(units)
	test_interruptions()
	test_arming_orders()
	test_contact_range()
	clear_units()
	units.free()
	print("Martyr behavior: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
