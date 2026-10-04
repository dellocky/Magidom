extends SceneTree

const Units = preload("res://scripts/rts/game_units.gd")
const Controller = preload("res://scripts/rts/rts_controller.gd")
const UnitScene = preload("res://units/hawkRider/hawk_rider_unit.tscn")
var checks: int = 0
var failures: int = 0
var arena: Node3D


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
	unit.effects_enabled = false
	arena.add_child(unit)
	unit.set_physics_process(false)
	return unit


func run() -> void:
	arena = Node3D.new()
	root.add_child(arena)
	check(Units.to_metres(100) == 5.0, "100 units/s is 5m/s")
	check(Units.to_metres(50) >= 1.75, "50-unit radius covers full hawk wingspan")
	check(Units.clamp_to_arena(Vector3(99, 4, -99)) == Vector3(47, 0.5, -47), "arena bounds")
	check(InputMap.action_get_events("camera_left")[0].physical_keycode == KEY_LEFT, "camera left key")
	check(InputMap.action_get_events("camera_up")[0].physical_keycode == KEY_UP, "camera up key")
	check(InputMap.action_get_events("camera_right")[0].physical_keycode == KEY_RIGHT, "camera right key")
	check(InputMap.action_get_events("camera_down")[0].physical_keycode == KEY_DOWN, "camera down key")
	var friendly := spawn(0, Vector3(-8, 0.5, 0))
	var enemy := spawn(1, Vector3(8, 0.5, 0))
	var ally := spawn(0, Vector3(-15, 0.5, 0))
	check(friendly.unit_name == "Hawk Rider", "UI display name")
	check(friendly.stats.move_speed == 100 and friendly.stats.attack_damage == 999 and friendly.stats.armor == 1, "combat stats")
	check(friendly.health == 500 and friendly.mana == 200, "health and mana stats")
	check(friendly.bolt.cooldown == 60.0 and friendly.melter.cooldown == 30.0, "spell cooldown balance")
	check(friendly.melter.range_units == 300.0, "Base Melter cast range halved")
	check(friendly.can_cast_bolt() and friendly.can_cast_melter(), "spells initially ready")
	check(not friendly.issue_attack(ally), "reject friendly target")
	check(ally.receive_damage(friendly, 100, &"BAM") == 0, "central friendly fire guard")
	check(enemy.receive_damage(friendly, 0, &"BAM") == 0, "zero damage")
	check(friendly.issue_attack(enemy), "accept hostile attack")
	friendly.advance_simulation(0.01)
	check(friendly.state == 3, "attack enters Bolt")
	check(friendly.bolt_cooldown_remaining == 60.0, "Bolt cooldown starts when casting begins")
	check(ally.can_cast_bolt() and ally.bolt_cooldown_remaining == 0.0, "Bolt cooldown is per unit")
	check(not friendly.issue_move(Vector3.ZERO), "Bolt ignores move")
	check(not friendly.issue_stop(), "Bolt ignores stop")
	check(not friendly.issue_cast_melter(Vector3.ZERO), "Bolt ignores another spell")
	friendly.advance_simulation(1.7)
	check(enemy.health == 500, "no early damage")
	friendly.advance_simulation(0.2)
	check(enemy.health == 0, "500 BAM kills 500 health despite armor")
	check(enemy.last_damage.type == &"BAM", "BAM flag propagated")
	check(friendly.release_count == 1, "single release across threshold")
	check(friendly.state == 3, "cast remains locked after victim dies")
	friendly.advance_simulation(2.0)
	check(friendly.release_count == 1 and friendly.state == 0, "cast recovers idle, no duplicate release")
	check(ally.health == 500, "instance health independent")
	var stale := spawn(1, Vector3(10, 0.5, 0))
	check(is_equal_approx(friendly.bolt_cooldown_remaining, 56.1), "Bolt cooldown ticks during cast")
	check(not friendly.issue_attack(stale), "Bolt rejects recast on cooldown")
	check(friendly.can_cast_melter(), "Bolt cooldown does not block Melter")
	check(friendly.issue_move(friendly.global_position), "cooldown does not block movement")
	friendly.advance_simulation(friendly.bolt_cooldown_remaining)
	check(friendly.can_cast_bolt(), "Bolt ready after cooldown expires")
	friendly.issue_attack(stale)
	friendly.advance_simulation(0.01)
	stale.free()
	friendly.advance_simulation(4.0)
	check(friendly.state == 0, "freed cast target fizzles safely even across full animation")
	check(friendly.bolt_cooldown_remaining > 0.0, "fizzled Bolt keeps cooldown")
	friendly.advance_simulation(friendly.bolt_cooldown_remaining)
	var durable := spawn(1, Vector3(8, 0.5, 0))
	durable.health = 5000
	check(friendly.issue_attack(durable), "accept ready autoattack")
	friendly.advance_simulation(0.01)
	friendly.advance_simulation(3.6)
	check(durable.health == 4500, "first autoattack lands")
	var releases: int = friendly.release_count
	friendly.advance_simulation(friendly.bolt_cooldown_remaining - 0.01)
	check(friendly.state == 2 and friendly.release_count == releases, "autoattack waits through cooldown")
	friendly.advance_simulation(0.02)
	check(friendly.state == 3 and friendly.bolt_cooldown_remaining == 60.0, "autoattack resumes when cooldown expires")
	friendly.advance_simulation(3.6)
	check(durable.health == 4000, "ordered autoattack repeats only after cooldown")
	friendly.issue_stop()
	friendly.global_position = Vector3(-7, 0.5, 0)
	var ability: Resource = friendly.melter
	check(ability.canDamageBuildings, "building flag on Base Melter")
	check(ability.damage_at(0) == 40 and ability.damage_at(4) == 80 and ability.damage_at(24) == 80, "damage ramp cap")
	check(ability.radius_at(0) == 50 and ability.radius_at(20) == 300 and ability.radius_at(24) == 300, "radius ramp cap")
	check(is_equal_approx(ability.damage_integral(24), 1840), "exact damage integral")
	check(not friendly.issue_cast_melter(Vector3(47, 0.5, 47)), "reject out of range channel")
	check(not friendly.issue_cast_melter(Vector3(8.01, 0.5, 0)), "reject Melter just beyond 300 units")
	check(friendly.melter_cooldown_remaining == 0.0 and friendly.mana == 200.0, "rejected casts spend no cooldown or mana")
	var before: Vector3 = friendly.global_position
	check(friendly.issue_cast_melter(durable.global_position), "start channel at 300-unit range boundary")
	check(friendly.melter_cooldown_remaining == 30.0, "Melter cooldown starts with channel")
	check(ally.can_cast_melter() and ally.melter_cooldown_remaining == 0.0, "Melter cooldown is per unit")
	check(friendly.player.current_animation == "staff_twirl", "channel loops twirl")
	check(not friendly.issue_move(Vector3.ZERO) and not friendly.issue_attack(durable), "channel rejects other actions")
	friendly.advance_simulation(4.0)
	check(is_equal_approx(durable.health, 3760), "integrated damage first 4s is 240")
	check(friendly.global_position == before, "caster stationary through twirl")
	check(durable.last_damage.flags.canDamageBuildings, "building flag in damage packet")
	check(friendly.melter_cooldown_remaining == 26.0, "Melter cooldown ticks during channel")
	check(friendly.issue_stop() and friendly.state == 0, "S interrupts channel")
	check(friendly.melter_cooldown_remaining == 26.0, "interruption does not refund cooldown")
	check(not friendly.issue_cast_melter(durable.global_position), "Melter rejects recast on cooldown")
	friendly.advance_simulation(1.0)
	check(is_equal_approx(durable.health, 3760), "no damage after stop")
	check(friendly.player.current_animation == "idle", "idle after stop")
	friendly.advance_simulation(friendly.melter_cooldown_remaining - 0.01)
	check(not friendly.issue_cast_melter(durable.global_position), "Melter stays blocked until full cooldown")
	friendly.advance_simulation(0.02)
	check(friendly.issue_cast_melter(durable.global_position), "Melter recasts after cooldown")
	friendly.advance_simulation(24.0)
	check(friendly.state == 0 and is_equal_approx(durable.health, 1920), "duration clipped and channel exits")
	check(friendly.melter_cooldown_remaining == 6.0, "full channel leaves six seconds of cooldown")
	check(not friendly.issue_cast_melter(durable.global_position), "completed channel cannot immediately recast")
	friendly.advance_simulation(6.0)
	# Compare small frames with a large step, including radius-entry timing.
	var edge := spawn(1, Vector3(13, 0.5, 0))
	edge.health = 5000
	check(friendly.issue_cast_melter(Vector3(8, 0.5, 0)), "start small-step channel")
	for i in 600: friendly.advance_simulation(0.01)
	var small_damage: float = 5000 - edge.health
	check(small_damage > 0.0, "expanding radius damages edge target")
	friendly.issue_stop()
	friendly.advance_simulation(friendly.melter_cooldown_remaining)
	edge.health = 5000
	check(friendly.issue_cast_melter(Vector3(8, 0.5, 0)), "start large-step channel")
	friendly.advance_simulation(6.0)
	check(absf((5000 - edge.health) - small_damage) < 0.02, "damage independent of simulation frame size")
	check(ally.health == 500, "vortex cannot damage same team")
	friendly.issue_stop()
	for other in [ally, durable, edge]: other.free()
	friendly.global_position = Vector3(0, 0.5, 0)
	friendly.issue_move(Vector3(20, 0.5, 0))
	friendly.advance_simulation(1.0)
	check(absf(friendly.global_position.x - 5.0) < 0.001, "movement speed 100u/s")
	for i in 20: friendly.advance_simulation(0.5)
	check(friendly.state == 0 and friendly.player.current_animation == "idle", "arrival returns idle")
	for i in 9:
		for j in i:
			check(Controller.formation_offset(i, 9).distance_to(Controller.formation_offset(j, 9)) > 4.0, "formation spacing")
	check(load("res://scenes/testLevel.tscn") != null, "test level loads")
	check(load("res://ui/main_menu.tscn") != null, "main menu loads")
	var audio = load("res://audio/synth_audio.gd")
	for kind in ["flap", "blast", "channel", "charge"]:
		var stream: AudioStreamWAV = audio.stream(kind)
		check(stream.data.size() > 1000, "nonempty synth audio " + kind)
	print("RTS_TESTS: ", checks - failures, "/", checks, " passed")
	arena.free()
	quit(0 if failures == 0 else 1)
