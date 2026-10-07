extends SceneTree

const Units = preload("res://scripts/rts/game_units.gd")
const Controller = preload("res://scripts/rts/rts_controller.gd")
const FX = preload("res://effects/combat_fx.gd")
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


class FakeVision extends Node:
	var fog_enabled: bool = true
	var player_team: int = 0
	var seen: Dictionary = {}

	func can_see_unit(_team: int, unit: Node3D) -> bool:
		return bool(seen.get(unit, false))

	func can_see_point(_team: int, _point: Vector3) -> bool:
		return true


func spawn(team: int, point: Vector3, vision: Node = null) -> Node3D:
	var unit: Node3D = UnitScene.instantiate()
	unit.vision_system = vision
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
	check(ability.radius_at(0) == 50 and ability.radius_at(20) == 300 and ability.radius_at(24) == 300, "radius ramp cap")
	check(not ability.has_method("damage_integral") and not ability.has_method("damage_at"), "continuous damage helpers removed")
	check(ability.damage == 40.0 and ability.damage_type == &"ELECTRICAL", "Flat 40 electrical per strike")
	check(ability.slow_fraction == 0.1 and ability.strike_radius_units == 50.0, "slow and strike radius tuning")
	check(ability.baseline_volley_frequency == 1.0 and ability.baseline_strikes_per_volley == 1.0, "baseline one volley, one strike")
	check(is_equal_approx(ability.volley_frequency_at(300), 6.0) and is_equal_approx(ability.strikes_per_volley_at(300), 6.0), "q scaling at 300 units")
	check(ability.volley_frequency_at(0) == 0.0 and ability.strikes_per_volley_at(-5.0) == 0.0 and ability.volley_frequency_at(NAN) == 0.0, "invalid radius guarded")
	check(not friendly.issue_cast_melter(Vector3(47, 0.5, 47)), "reject out of range channel")
	check(not friendly.issue_cast_melter(Vector3(8.01, 0.5, 0)), "reject Melter just beyond 300 units")
	check(friendly.melter_cooldown_remaining == 0.0 and friendly.mana == 200.0, "rejected casts spend no cooldown or mana")
	var offset_victim := spawn(1, Vector3(8, 0.5, 3))
	var victims: Array = [durable, offset_victim]
	durable.health = 5000
	offset_victim.health = 5000
	var points: Array = []
	friendly.melter_strike.connect(func(p: Vector3, _hits: int) -> void: points.append(p))
	var before: Vector3 = friendly.global_position
	friendly.seed_melter_rng(11)
	check(friendly.issue_cast_melter(durable.global_position), "start channel at 300-unit range boundary")
	check(friendly.melter_cooldown_remaining == 30.0, "Melter cooldown starts with channel")
	check(ally.can_cast_melter() and ally.melter_cooldown_remaining == 0.0, "Melter cooldown is per unit")
	check(friendly.player.current_animation == "staff_twirl", "channel loops twirl")
	check(not friendly.issue_move(Vector3.ZERO) and not friendly.issue_attack(durable), "channel rejects other actions")
	friendly.advance_simulation(0.04)
	check(friendly.melter_strike_count == 0 and durable.health == 5000, "no ambient field damage")
	check(durable.get_effective_move_speed() == 90.0 and ally.get_effective_move_speed() == 100.0, "10% slow on opponents only")
	check(friendly.get_effective_move_speed() == 100.0, "caster not slowed")
	friendly.advance_simulation(0.96)
	check(friendly.melter_volley_count >= 1 and friendly.melter_strike_count >= 1, "volleys begin within one second")
	friendly.advance_simulation(3.0)
	var expected: float = 0.0
	for p: Vector3 in points:
		check(Vector2(p.x - 8.0, p.z).length() <= Units.to_metres(ability.radius_at(4.0)) + 0.001, "strike centers lie inside the field")
		if Vector2(p.x - 8.0, p.z).length() <= 2.5 + 0.0001:
			expected += 40.0
	check(is_equal_approx(5000 - durable.health, expected) and expected > -1.0, "center target takes exactly the strikes within 50 units")
	var expected_offset: float = 0.0
	for p: Vector3 in points:
		if Vector2(p.x - 8.0, p.z - 3.0).length() <= 2.5 + 0.0001:
			expected_offset += 40.0
	check(is_equal_approx(5000 - offset_victim.health, expected_offset), "offset target hit boundary matches strike positions")
	check(durable.last_damage.is_empty() or durable.last_damage.flags.canDamageBuildings, "building flag in damage packet")
	check(friendly.global_position == before, "caster stationary through twirl")
	check(friendly.melter_cooldown_remaining == 26.0, "Melter cooldown ticks during channel")
	# Strongest slow wins; equal slows do not stack.
	ally.global_position = Vector3(0, 0.5, 0)
	var strong: Resource = ally.melter.duplicate()
	strong.slow_fraction = 0.25
	ally.melter = strong
	check(ally.issue_cast_melter(durable.global_position), "second caster overlaps field")
	check(durable.get_effective_move_speed() == 75.0, "strongest slow wins, no stacking")
	ally.issue_stop()
	check(durable.get_effective_move_speed() == 90.0, "slow removal when one field ends")
	ally.melter = strong.duplicate()
	ally.melter.slow_fraction = 0.1
	ally.melter_cooldown_remaining = 0.0
	ally.issue_cast_melter(durable.global_position)
	check(durable.get_effective_move_speed() == 90.0, "equal overlapping slows do not stack")
	ally.issue_stop()
	ally.global_position = Vector3(-15, 0.5, 0)
	check(friendly.issue_stop() and friendly.state == 0, "S interrupts channel")
	check(durable.get_effective_move_speed() == 100.0, "slow removed on interrupt")
	var count_after_stop: int = friendly.melter_strike_count
	var hp_after_stop: float = durable.health
	friendly.advance_simulation(5.0)
	check(friendly.melter_strike_count == count_after_stop and durable.health == hp_after_stop, "no deferred strikes after stop")
	check(friendly.melter_cooldown_remaining == 21.0, "interruption does not refund cooldown")
	check(not friendly.issue_cast_melter(durable.global_position), "Melter rejects recast on cooldown")
	check(friendly.player.current_animation == "idle", "idle after stop")
	friendly.advance_simulation(friendly.melter_cooldown_remaining - 0.01)
	check(not friendly.issue_cast_melter(durable.global_position), "Melter stays blocked until full cooldown")
	friendly.advance_simulation(0.02)
	check(friendly.issue_cast_melter(durable.global_position), "Melter recasts after cooldown")
	# Determinism: identical seed gives identical strikes for small and large frames.
	friendly.issue_stop()
	var run_results: Array = []
	for large in [false, true]:
		friendly.melter_cooldown_remaining = 0.0
		for v: Node3D in victims:
			v.health = 5000
		points.clear()
		var strikes_before: int = friendly.melter_strike_count
		friendly.seed_melter_rng(5)
		check(friendly.issue_cast_melter(Vector3(8, 0.5, 0)), "start determinism channel")
		if large:
			friendly.advance_simulation(6.0)
		else:
			for i in 600: friendly.advance_simulation(0.01)
		run_results.append({"points": points.duplicate(), "count": friendly.melter_strike_count - strikes_before,
			"hp": [durable.health, offset_victim.health]})
		friendly.issue_stop()
	check(run_results[0].count > 0 and run_results[0].count == run_results[1].count, "same strike count for small and large deltas")
	check(run_results[0].points == run_results[1].points, "same seeded strike positions for small and large deltas")
	check(run_results[0].hp == run_results[1].hp, "same damage for small and large deltas")
	# Growth and external modifiers raise throughput, including during a running channel.
	var windows: Array = []
	for mode in ["plain", "modified"]:
		friendly.melter_cooldown_remaining = 0.0
		friendly.issue_cast_melter(Vector3(8, 0.5, 0))
		if mode == "modified":
			check(friendly.set_aoe_modifier(&"test", 2.0) and friendly.effective_melter_radius_units(0.0) == 100.0, "AoE modifier doubles radius")
		var s0: int = friendly.melter_strike_count
		friendly.advance_simulation(2.0)
		windows.append(friendly.melter_strike_count - s0)
		if mode == "plain":
			friendly.advance_simulation(14.0)
			var s1: int = friendly.melter_strike_count
			friendly.advance_simulation(2.0)
			windows.append(friendly.melter_strike_count - s1)
		else:
			check(durable.get_effective_move_speed() == 90.0, "modified field still slows")
			friendly.clear_aoe_modifier(&"test")
			check(friendly.effective_melter_radius_units(0.0) == 50.0, "AoE modifier cleared")
			check(not friendly.set_aoe_modifier(&"bad", -1.0) and not friendly.set_aoe_modifier(&"bad", NAN), "invalid modifiers rejected")
		friendly.issue_stop()
	check(windows[1] > windows[0] * 3, "strike throughput grows with radius")
	check(windows[2] > windows[0] * 1.5, "external AoE modifier raises throughput")
	# Full channel clips at its duration and leaves nothing behind.
	friendly.melter_cooldown_remaining = 0.0
	check(friendly.issue_cast_melter(Vector3(8, 0.5, 0)), "start full channel")
	friendly.advance_simulation(24.0)
	check(friendly.state == 0, "duration clipped and channel exits")
	check(friendly.melter_cooldown_remaining == 6.0, "full channel leaves six seconds of cooldown")
	check(durable.get_effective_move_speed() == 100.0, "no slow after channel end")
	var finished_count: int = friendly.melter_strike_count
	friendly.advance_simulation(3.0)
	check(friendly.melter_strike_count == finished_count, "no strikes after channel ends")
	check(not friendly.issue_cast_melter(durable.global_position), "completed channel cannot immediately recast")
	# Death of a caster mid-channel clears the field and pending strikes.
	var victim2 := spawn(1, Vector3(-10, 0.5, 0))
	ally.melter = friendly.melter
	ally.melter_cooldown_remaining = 0.0
	ally.global_position = Vector3(-15, 0.5, 0)
	check(ally.issue_cast_melter(victim2.global_position), "caster begins channel")
	ally.advance_simulation(2.0)
	check(victim2.get_effective_move_speed() == 90.0, "victim slowed by living caster")
	ally.receive_damage(victim2, 9999, &"BAM")
	var dead_count: int = ally.melter_strike_count
	ally.advance_simulation(5.0)
	check(ally.state == 5 and ally.melter_strike_count == dead_count, "dead caster fires no deferred strikes")
	check(victim2.get_effective_move_speed() == 100.0, "dead caster leaves no slow")
	victim2.free()
	# Fog hooks use a fake vision service.
	var fv := FakeVision.new()
	arena.add_child(fv)
	var fa := spawn(0, Vector3(-30, 0.5, 30), fv)
	var fe := spawn(1, Vector3(-20, 0.5, 30), fv)
	fv.seen[fe] = false
	check(fa.is_opponent(fe) and not fa.can_target(fe), "hostility is separate from sight")
	check(not fa.issue_attack(fe), "cannot attack unseen unit")
	fv.seen[fe] = true
	check(fa.issue_attack(fe) and fa.state == 2, "can attack seen unit")
	fv.seen[fe] = false
	fa.advance_simulation(0.01)
	check(fa.state == 0 and fa.attack_target == null, "chase stops when target leaves sight")
	fa.bolt_cooldown_remaining = 0.0
	fv.seen[fe] = true
	fa.issue_attack(fe)
	fa.advance_simulation(0.01)
	check(fa.state == 3, "bolt started on seen target")
	fv.seen[fe] = false
	fa.advance_simulation(2.0)
	check(fe.health == 500 and fa.release_count == 1, "bolt does not release onto unseen target")
	fv.fog_enabled = false
	check(fa.can_target(fe), "fog off removes sight restriction")
	fv.fog_enabled = true
	fa.advance_simulation(5.0)
	var aoe: Resource = fa.melter.duplicate()
	aoe.growth_per_second = 0.0
	aoe.baseline_volley_frequency = 10.0
	fa.melter = aoe
	fa.seed_melter_rng(3)
	check(fa.issue_cast_melter(fe.global_position), "cast ground AoE at unseen unit")
	fa.advance_simulation(1.0)
	check(fe.health == 500.0 - 40.0 * fa.melter_strike_count and fa.melter_strike_count >= 9, "ground AoE hits unseen enemies")
	fa.issue_stop()
	var layer: int = (fe.get_node("PickBody") as CollisionObject3D).collision_layer
	fe.set_fog_hidden(true)
	check(not fe.visible and (fe.get_node("PickBody") as CollisionObject3D).collision_layer == 0 and fe.is_alive(), "hidden unit has no pick layer")
	fe.set_fog_hidden(false)
	check(fe.visible and (fe.get_node("PickBody") as CollisionObject3D).collision_layer == layer, "pick layer restored")
	fa.set_vision_range(500.0)
	check(fa.stats.vision_range == 500.0 and fe.stats.vision_range == 1000.0, "vision range is unit specific")
	check(load("res://units/hawkRider/hawk_rider_stats.tres").vision_range == 1000.0, "shared stat template unchanged")
	var bare := spawn(0, Vector3(30, 0.5, 30))
	bare.bolt = null
	bare.melter = null
	check(not bare.can_cast_bolt() and not bare.can_cast_melter() and not bare.issue_cast_melter(Vector3(30, 0.5, 30)), "missing abilities cannot cast")
	bare.issue_move(Vector3(35, 0.5, 30))
	bare.advance_simulation(0.5)
	check(bare.effective_melter_radius_units(1.0) == 0.0, "no Melter radius without ability")
	for extra in [bare, fa, fe, fv]: extra.free()
	# Strike FX budget (visual only).
	var fx_made: int = 0
	var fx_nodes: Array = []
	for i in 12:
		var node: Node3D = FX.strike(arena, Vector3(i, 0, 0))
		if node != null:
			fx_made += 1
			fx_nodes.append(node)
	check(fx_made > 0 and fx_made <= FX.STRIKE_PER_FRAME, "strike FX obey per-frame budget")
	check(FX.strike(arena, Vector3.ZERO, 2.5, func() -> bool: return false) == null, "strike FX skipped when hidden")
	for node: Node3D in fx_nodes: node.free()
	check(FX._strike_active == 0, "strike FX release active budget on free")
	for other in [ally, durable, offset_victim]: other.free()
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
