extends "res://scripts/rts/rts_unit.gd"
## Melee "baneling" unit. Reuses the base RTS state machine: the inherited BOLT
## state is the whack auto-attack and CHANNEL is unused. The "Human Baneling"
## spell replaces the melter channel entirely via `self_cast` -- arming it swaps
## the move animation to a "silly run" and detonates the martyr on enemy contact.

## Enemy centre distance (gameplay units) that triggers the baneling blast.
const CONTACT_RANGE_UNITS: float = 40.0
## Cosmetic whack impact radius (gameplay units), drawn on hit.
const WHACK_FX_RADIUS_UNITS: float = 12.0

var baneling_armed: bool = false


func _ready() -> void:
	add_to_group("rts_units")
	stats = stats.duplicate() as Stats
	var pick := get_node_or_null("PickBody") as CollisionObject3D
	if pick != null:
		_pick_layer_original = pick.collision_layer
	health = stats.max_health
	mana = stats.max_mana
	player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_fix_loop_modes()
	var team_color := Color(0.18, 0.72, 1.0) if team == 0 else Color(1.0, 0.28, 0.24)
	FX.ring(self, team_color, 1.8).position.y = 0.045
	_selection_ring = FX.ring(self, Color(0.4, 1.0, 0.55), SELECTION_RING_RADIUS)
	_selection_ring.position.y = 0.06
	_selection_ring.visible = selected
	_play(&"idle")


## If the merged .glb ever imports without a post-import script, enforce the loop
## modes here so idle/run/sillyrun still cycle and slap stays one-shot.
func _fix_loop_modes() -> void:
	if player == null:
		return
	var looping := {&"idle": true, &"run": true, &"sillyrun": true}
	for clip in player.get_animation_list():
		var animation := player.get_animation(clip)
		animation.loop_mode = Animation.LOOP_LINEAR if looping.has(clip) else Animation.LOOP_NONE


func idle_clip() -> StringName:
	return &"sillyrun" if baneling_armed else &"idle"


func move_clip() -> StringName:
	return &"sillyrun" if baneling_armed else &"run"


func _play(clip: StringName) -> void:
	if not is_instance_valid(player):
		return
	player.play(clip, 0.12 if clip in [&"idle", &"run", &"sillyrun"] else 0.0)
	player.advance(0.0)
	_flap_phase = 0.0


func _set_state(next: State) -> void:
	state = next
	cast_elapsed = 0.0
	_released = false
	match state:
		State.IDLE:
			_play(idle_clip())
		State.MOVING, State.CHASING:
			_play(move_clip())
		State.BOLT:
			_play(bolt.animation)
		State.CHANNEL:
			_play(melter.animation)
		State.DEAD:
			if is_instance_valid(player):
				player.stop()


## Basic attacks never lock out a new command, unlike the Hawk Rider's spells.
func accepts_orders() -> bool:
	return is_alive()


func issue_stop() -> bool:
	if not accepts_orders():
		return false
	attack_target = null
	_set_state(State.IDLE)
	return true


## Whack (auto-attack) is unavailable while the baneling charge is armed.
func can_cast_bolt() -> bool:
	return not baneling_armed and super.can_cast_bolt()


## Arming "Human Baneling" replaces the melter channel and cannot be undone.
func can_cast_melter() -> bool:
	return not baneling_armed and melter != null and accepts_orders() and melter_cooldown_remaining <= 0.0 and mana >= melter.mana_cost


func issue_cast_melter(_point: Vector3) -> bool:
	if not can_cast_melter():
		return false
	mana -= melter.mana_cost
	baneling_armed = true
	melter_cooldown_remaining = melter.cooldown
	if state == State.BOLT:
		if not can_target(attack_target):
			attack_target = null
		_set_state(State.CHASING if attack_target != null else State.IDLE)
	else:
		_refresh_move_animation()
	return true


## Retarget immediately, even during a swing or its cooldown. The chase waits
## for Whack to be ready; once armed, it instead runs all the way to contact.
func issue_attack(target: Node3D) -> bool:
	if not accepts_orders() or not can_target(target):
		return false
	if not baneling_armed and (bolt == null or mana < bolt.mana_cost):
		return false
	attack_target = target
	_set_state(State.CHASING)
	return true


func _refresh_move_animation() -> void:
	match state:
		State.IDLE:
			_play(idle_clip())
		State.MOVING, State.CHASING:
			_play(move_clip())


func advance_simulation(delta: float) -> void:
	if not is_alive() or delta <= 0.0:
		return
	bolt_cooldown_remaining = maxf(0.0, bolt_cooldown_remaining - delta)
	melter_cooldown_remaining = maxf(0.0, melter_cooldown_remaining - delta)
	if frenzy_remaining > 0.0:
		frenzy_remaining = maxf(0.0, frenzy_remaining - delta)
		if frenzy_drain_fraction > 0.0:
			_drain_health(stats.max_health * frenzy_drain_fraction * delta)
		if frenzy_remaining <= 0.0:
			frenzy_move_bonus = 0.0
			frenzy_drain_fraction = 0.0
	if baneling_armed:
		_check_baneling_contact()
		if not is_alive():
			return
	match state:
		State.MOVING:
			if _move_toward(destination, delta):
				_set_state(State.IDLE)
		State.CHASING:
			if not can_target(attack_target):
				attack_target = null
				_set_state(State.IDLE)
			elif baneling_armed:
				# Close to contact; the blast fires in _check_baneling_contact.
				_move_toward(attack_target.global_position, delta)
			elif _horizontal_distance(global_position, attack_target.global_position) <= Units.to_metres(bolt.range_units):
				if can_cast_bolt():
					mana -= bolt.mana_cost
					bolt_cooldown_remaining = bolt.cooldown
					_face(attack_target.global_position, 1.0)
					_set_state(State.BOLT)
			else:
				_move_toward(attack_target.global_position, delta)
	if is_instance_valid(player):
		player.advance(_movement_animation_delta(delta))
	if state == State.BOLT:
		_advance_whack()


func _advance_whack() -> void:
	if bolt == null or not is_instance_valid(player):
		_set_state(State.IDLE)
		return
	cast_elapsed = player.current_animation_position
	if not _released and cast_elapsed >= bolt.release_time:
		_release_whack()
	if cast_elapsed >= player.get_animation(bolt.animation).length - 0.0001:
		_set_state(State.CHASING if can_target(attack_target) else State.IDLE)


## Whack lands a little above the enemy's centre, with a small impact burst.
func _release_whack() -> void:
	_released = true
	release_count += 1
	if can_target(attack_target):
		var hit := attack_target.global_position + Vector3.UP * 1.1
		if effects_enabled:
			FX.strike(get_parent(), hit, Units.to_metres(WHACK_FX_RADIUS_UNITS), Callable(self, "fx_point_visible").bind(hit))
		attack_target.receive_damage(self, bolt.damage, bolt.damage_type, {"canDamageBuildings": bolt.canDamageBuildings})
	bolt_released.emit()


## While armed, ignore the usual separation push so the martyr can reach contact.
func _move_toward(point: Vector3, delta: float) -> bool:
	if baneling_armed:
		return _move_toward_plain(point, delta)
	return super._move_toward(point, delta)


func _move_toward_plain(point: Vector3, delta: float) -> bool:
	point = Units.clamp_to_arena(point)
	var offset := point - global_position
	offset.y = 0.0
	if offset.length() < 0.12:
		return true
	var direction := offset.normalized()
	global_position = Units.clamp_to_arena(global_position + direction * minf(Units.to_metres(get_effective_move_speed()) * delta, offset.length()))
	_face(global_position + direction, minf(delta * 10.0, 1.0))
	return false


func _nearest_enemy(max_units: float) -> Node3D:
	var best: Node3D
	var best_distance := max_units
	for other: Node3D in get_tree().get_nodes_in_group("rts_units"):
		if not can_target(other):
			continue
		var d := Units.to_units(_horizontal_distance(global_position, other.global_position))
		if d <= best_distance:
			best_distance = d
			best = other
	return best


func _check_baneling_contact() -> void:
	if not baneling_armed or not is_alive():
		return
	if _nearest_enemy(CONTACT_RANGE_UNITS) != null:
		_explode()


## Self-detonation: full AoE damage around the martyr, then death.
func _explode() -> void:
	baneling_armed = false
	if melter == null:
		_die()
		return
	var origin := global_position
	var radius_u := melter.radius_units
	for other: Node3D in get_tree().get_nodes_in_group("rts_units"):
		if not is_opponent(other):
			continue
		if Units.to_units(_horizontal_distance(other.global_position, origin)) <= radius_u + 1e-4:
			other.receive_damage(self, melter.damage, melter.damage_type, {"canDamageBuildings": melter.canDamageBuildings})
	if effects_enabled:
		FX.strike(get_parent(), origin + Vector3.UP * 0.2, Units.to_metres(radius_u), Callable(self, "fx_point_visible").bind(origin))
	_die()