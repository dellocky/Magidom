extends Node3D
## The gameplay body stays still during casts; baked animation moves only its visual child.

signal died(unit: Node3D)
signal damaged(amount: float, damage_type: StringName, flags: Dictionary)
signal bolt_released
signal melter_strike(point: Vector3, hits: int)
signal vision_range_changed(units: float)

const Units = preload("res://scripts/rts/game_units.gd")
const Stats = preload("res://scripts/rts/unit_stats.gd")
const Ability = preload("res://scripts/rts/ability_definition.gd")
const FX = preload("res://effects/combat_fx.gd")
const Audio = preload("res://audio/synth_audio.gd")
enum State { IDLE, MOVING, CHASING, BOLT, CHANNEL, DEAD }

## Melter schedule runs on a fixed internal grid so results never depend on frame size.
const SCHEDULE_STEP: float = 0.05
const CREDIT_EPSILON: float = 1e-9
const MIN_AOE_MULTIPLIER: float = 0.01
const MAX_AOE_MULTIPLIER: float = 100.0

@export_enum("Friendly", "Enemy") var team: int = 0
@export var stats: Stats = preload("res://units/hawkRider/hawk_rider_stats.tres")
@export var bolt: Ability = preload("res://units/hawkRider/lightning_bolt.tres")
@export var melter: Ability = preload("res://units/hawkRider/base_melter.tres")

var unit_name: String:
	get: return stats.display_name
var health: float
var mana: float
var selected: bool = false:
	set(value):
		selected = value
		if is_instance_valid(_selection_ring):
			_selection_ring.visible = value
var state: State = State.IDLE
var cast_elapsed: float = 0.0
var bolt_cooldown_remaining: float = 0.0
var melter_cooldown_remaining: float = 0.0
var destination := Vector3.ZERO
var attack_target: Node3D
var channel_point := Vector3.ZERO
var release_count: int = 0
var last_damage: Dictionary = {}
var effects_enabled: bool = true
## Assigned by the level BEFORE add_child. Null means no fog (standalone tests).
## Needs: can_see_unit(team, unit), can_see_point(team, point), player_team, fog_enabled.
var vision_system: Node
var melter_strike_count: int = 0
var melter_volley_count: int = 0
var player: AnimationPlayer
var staff_tip: Marker3D
var _selection_ring: MeshInstance3D
var _charge: Node3D
var _vortex: Node3D
var _released: bool = false
var _flap_phase: float = 0.0
var _fog_hidden: bool = false
var _pick_layer_original: int = 1
var _aoe_modifiers: Dictionary = {}
var _melter_rng := RandomNumberGenerator.new()
var _sched_steps: int = 0
var _sched_tail_done: bool = false
var _volley_credit: float = 0.0
var _strike_credit: float = 0.0
var _flap_sound: AudioStreamPlayer3D
var _charge_sound: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("rts_units")
	stats = stats.duplicate() as Stats  # per-unit; the shared resource stays the template
	_melter_rng.randomize()
	var pick := get_node_or_null("PickBody") as CollisionObject3D
	if pick != null:
		_pick_layer_original = pick.collision_layer
	health = stats.max_health
	mana = stats.max_mana
	player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_setup_staff_tip()
	var team_color := Color(0.18, 0.72, 1.0) if team == 0 else Color(1.0, 0.28, 0.24)
	FX.ring(self, team_color, 1.8).position.y = 0.045
	_selection_ring = FX.ring(self, Color(0.4, 1.0, 0.55), 2.15)
	_selection_ring.position.y = 0.06
	_selection_ring.visible = selected
	_flap_sound = AudioStreamPlayer3D.new()
	_flap_sound.stream = Audio.stream("flap")
	_flap_sound.volume_db = -17.0
	_flap_sound.max_distance = 65.0
	add_child(_flap_sound)
	_charge_sound = AudioStreamPlayer3D.new()
	_charge_sound.stream = Audio.stream("charge")
	_charge_sound.volume_db = -13.0
	_charge_sound.max_distance = 85.0
	add_child(_charge_sound)
	_play(&"idle")


func _setup_staff_tip() -> void:
	var staff := find_child("staff", true, false) as MeshInstance3D
	staff_tip = Marker3D.new()
	staff_tip.name = "StaffTip"
	if staff == null:
		add_child(staff_tip)
		staff_tip.position = Vector3(0, 2.0, -0.4)
		push_warning("Hawk Rider staff missing; using fallback effect anchor")
		return
	staff.add_child(staff_tip)
	# Mesh coordinates are baked in the source pose: the decorated head is +Y,+Z.
	var axis := Vector3(-0.02, 0.77, 0.64).normalized()
	var vertices: PackedVector3Array = staff.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var extreme: float = -INF
	for vertex in vertices:
		extreme = maxf(extreme, vertex.dot(axis))
	var tip := Vector3.ZERO
	var count: int = 0
	for vertex in vertices:
		if vertex.dot(axis) >= extreme - 0.035:
			tip += vertex
			count += 1
	staff_tip.position = tip / maxf(count, 1)


func is_alive() -> bool:
	return state != State.DEAD and health > 0.0


func accepts_orders() -> bool:
	return is_alive() and state != State.BOLT and state != State.CHANNEL


func can_cast_bolt() -> bool:
	return bolt != null and accepts_orders() and bolt_cooldown_remaining <= 0.0 and mana >= bolt.mana_cost


func can_cast_melter() -> bool:
	return melter != null and accepts_orders() and melter_cooldown_remaining <= 0.0 and mana >= melter.mana_cost


func is_opponent(other: Variant) -> bool:
	return is_instance_valid(other) and other != self and other.is_alive() and other.team != team


## Hostile AND currently visible to this unit's side (when fog applies).
func can_target(other: Variant) -> bool:
	return is_opponent(other) and _has_sight_of(other)


func _fog_active() -> bool:
	return is_instance_valid(vision_system) and bool(vision_system.fog_enabled)


func _has_sight_of(other: Node3D) -> bool:
	if not _fog_active():
		return true
	return bool(vision_system.can_see_unit(team, other))


## Visibility of a world point for the local player's FX (never uses unit.visible).
func fx_point_visible(point: Vector3) -> bool:
	if not _fog_active():
		return true
	return bool(vision_system.can_see_point(int(vision_system.player_team), point))


func _channel_fx_visible() -> bool:
	return fx_point_visible(channel_point)


func _beam_fx_visible(tip: Variant, hit: Vector3) -> bool:
	if not fx_point_visible(hit):
		return false
	return not is_instance_valid(tip) or fx_point_visible((tip as Node3D).global_position)


func set_vision_range(units: float) -> void:
	stats.vision_range = maxf(units, 1.0)
	vision_range_changed.emit(stats.vision_range)


## Presentation only: the simulation keeps running while hidden.
func set_fog_hidden(value: bool) -> void:
	if value == _fog_hidden:
		return
	_fog_hidden = value
	visible = not value
	var pick := get_node_or_null("PickBody") as CollisionObject3D
	if pick != null:
		if value:
			_pick_layer_original = pick.collision_layer
			pick.collision_layer = 0
		else:
			pick.collision_layer = _pick_layer_original
	if value:
		if is_instance_valid(_flap_sound):
			_flap_sound.stop()
		if is_instance_valid(_charge_sound):
			_charge_sound.stop()
	elif state == State.BOLT and not _released and effects_enabled and is_instance_valid(_charge_sound):
		_charge_sound.play()


func is_fog_hidden() -> bool:
	return _fog_hidden


# ------------------------------------------------------- speed and Melter AoE

## Strongest slow among opposing active Melter fields covering this unit.
func get_move_slow_fraction() -> float:
	var slow: float = 0.0
	if not is_alive():
		return 0.0
	for other: Node3D in get_tree().get_nodes_in_group("rts_units"):
		if other == self or not is_instance_valid(other) or other.state != State.CHANNEL or not is_opponent(other):
			continue
		if other.melter == null:
			continue
		var reach: float = other.effective_melter_radius_units(other.cast_elapsed)
		if Units.to_units(_horizontal_distance(global_position, other.channel_point)) <= reach:
			slow = maxf(slow, other.melter.slow_fraction)
	return clampf(slow, 0.0, 0.95)


## Units per second, including slows. Movement and the HUD both use this.
func get_effective_move_speed() -> float:
	return stats.move_speed * (1.0 - get_move_slow_fraction())


func set_aoe_modifier(source: Variant, multiplier: float) -> bool:
	if source == null or not is_finite(multiplier) or multiplier <= 0.0:
		return false
	_aoe_modifiers[source] = clampf(multiplier, MIN_AOE_MULTIPLIER, MAX_AOE_MULTIPLIER)
	_refresh_melter_visuals()
	return true


func clear_aoe_modifier(source: Variant) -> void:
	_aoe_modifiers.erase(source)
	_refresh_melter_visuals()


func get_aoe_multiplier() -> float:
	var product: float = 1.0
	for key: Variant in _aoe_modifiers.keys():
		if typeof(key) == TYPE_OBJECT and not is_instance_valid(key):
			_aoe_modifiers.erase(key)
			continue
		product *= float(_aoe_modifiers[key])
	return clampf(product, MIN_AOE_MULTIPLIER, MAX_AOE_MULTIPLIER)


## Melter radius in gameplay units after modifiers, `seconds` into the channel.
func effective_melter_radius_units(seconds: float) -> float:
	if melter == null:
		return 0.0
	return melter.radius_at(seconds) * get_aoe_multiplier()


func seed_melter_rng(value: int) -> void:
	_melter_rng.seed = value


func _refresh_melter_visuals() -> void:
	if state == State.CHANNEL and is_instance_valid(_vortex):
		_vortex.set_radius(Units.to_metres(effective_melter_radius_units(cast_elapsed)))


func issue_move(point: Vector3) -> bool:
	if not accepts_orders():
		return false
	attack_target = null
	destination = Units.clamp_to_arena(point)
	_set_state(State.MOVING)
	return true


func issue_attack(target: Node3D) -> bool:
	if not can_cast_bolt() or not can_target(target):
		return false
	attack_target = target
	_set_state(State.CHASING)
	return true


func issue_stop() -> bool:
	if not is_alive() or state == State.BOLT:
		return false
	attack_target = null
	_set_state(State.IDLE)
	return true


func issue_cast_melter(point: Vector3) -> bool:
	point = Units.clamp_to_arena(point)
	if not can_cast_melter():
		return false
	if _horizontal_distance(global_position, point) > Units.to_metres(melter.range_units):
		return false
	attack_target = null
	channel_point = point
	mana -= melter.mana_cost
	melter_cooldown_remaining = melter.cooldown
	_face(point, 1.0)
	_set_state(State.CHANNEL)
	return true


func receive_damage(source: Node3D, amount: float, damage_type: StringName, flags: Dictionary = {}) -> float:
	if not is_alive() or not is_instance_valid(source) or source.team == team or amount <= 0.0:
		return 0.0
	# Armor is recorded for future physical damage rules; BAM is exactly the spell's damage.
	var applied := minf(health, amount)
	health -= applied
	last_damage = {"amount": applied, "type": damage_type, "flags": flags.duplicate()}
	damaged.emit(applied, damage_type, flags)
	if health <= 0.0:
		_set_state(State.DEAD)
		remove_from_group("rts_units")
		selected = false
		$PickBody/CollisionShape3D.set_deferred("disabled", true)
		died.emit(self)
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.45)
		tween.tween_callback(queue_free)
	return applied


func _physics_process(delta: float) -> void:
	advance_simulation(delta)


func advance_simulation(delta: float) -> void:
	if not is_alive() or delta <= 0.0:
		return
	bolt_cooldown_remaining = maxf(0.0, bolt_cooldown_remaining - delta)
	melter_cooldown_remaining = maxf(0.0, melter_cooldown_remaining - delta)
	match state:
		State.MOVING:
			if _move_toward(destination, delta):
				_set_state(State.IDLE)
		State.CHASING:
			if bolt == null or not can_target(attack_target):
				attack_target = null
				_set_state(State.IDLE)
			elif _horizontal_distance(global_position, attack_target.global_position) <= Units.to_metres(bolt.range_units):
				if can_cast_bolt():
					mana -= bolt.mana_cost
					bolt_cooldown_remaining = bolt.cooldown
					_face(attack_target.global_position, 1.0)
					_set_state(State.BOLT)
				elif mana < bolt.mana_cost:
					_set_state(State.IDLE)
			else:
				_move_toward(attack_target.global_position, delta)
	player.advance(delta)
	if state == State.BOLT:
		cast_elapsed = player.current_animation_position
		if not _released and cast_elapsed >= bolt.release_time:
			_release_bolt()
		if is_instance_valid(_charge):
			_charge.set_charge(clampf(cast_elapsed / bolt.release_time, 0.0, 1.0) if not _released else maxf(0.0, 1.0 - (cast_elapsed - bolt.release_time) / 0.3))
		if cast_elapsed >= player.get_animation(bolt.animation).length - 0.0001:
			_set_state(State.CHASING if can_target(attack_target) else State.IDLE)
	elif state == State.CHANNEL:
		_advance_channel(delta)
	elif state in [State.IDLE, State.MOVING, State.CHASING]:
		var period: float = 1.2 if state == State.IDLE else 0.8
		_flap_phase += delta
		if _flap_phase >= period:
			_flap_phase = fmod(_flap_phase, period)
			if effects_enabled and not _fog_hidden:
				_flap_sound.play()


func _release_bolt() -> void:
	_released = true
	release_count += 1
	_charge_sound.stop()
	if can_target(attack_target):
		var hit: Vector3 = attack_target.global_position + Vector3.UP * 1.3
		if effects_enabled:
			FX.beam(get_parent(), staff_tip, hit, Callable(self, "_beam_fx_visible").bind(staff_tip, hit))
		attack_target.receive_damage(self, bolt.damage, bolt.damage_type, {"canDamageBuildings": bolt.canDamageBuildings})
	bolt_released.emit()


func _advance_channel(delta: float) -> void:
	if melter == null:
		_set_state(State.IDLE)
		return
	cast_elapsed = minf(cast_elapsed + delta, melter.duration)
	_run_melter_schedule(cast_elapsed)
	if state != State.CHANNEL:
		return
	if is_instance_valid(_vortex):
		_vortex.set_radius(Units.to_metres(effective_melter_radius_units(cast_elapsed)))
	if cast_elapsed >= melter.duration:
		_set_state(State.IDLE)


## Catches up every internal step ending at or before `until`; never skips strikes.
func _run_melter_schedule(until: float) -> void:
	while state == State.CHANNEL and (_sched_steps + 1) * SCHEDULE_STEP <= until + 1e-6:
		_sched_steps += 1
		_melter_step(SCHEDULE_STEP, _sched_steps * SCHEDULE_STEP)
	if state == State.CHANNEL and not _sched_tail_done and until >= melter.duration - 1e-9:
		_sched_tail_done = true
		var tail: float = melter.duration - _sched_steps * SCHEDULE_STEP
		if tail > 1e-6:
			_melter_step(tail, melter.duration)


func _melter_step(dt: float, sim_time: float) -> void:
	var radius_u: float = effective_melter_radius_units(sim_time)
	_volley_credit += melter.volley_frequency_at(radius_u) * dt
	while state == State.CHANNEL and _volley_credit >= 1.0 - CREDIT_EPSILON:
		_volley_credit -= 1.0
		melter_volley_count += 1
		_strike_credit += melter.strikes_per_volley_at(radius_u)
		var count: int = int(floor(_strike_credit + CREDIT_EPSILON))
		_strike_credit -= count
		for i in count:
			if state != State.CHANNEL:
				return
			_melter_strike(radius_u)


func _melter_strike(radius_u: float) -> void:
	var distance: float = Units.to_metres(radius_u) * sqrt(_melter_rng.randf())
	var angle: float = _melter_rng.randf() * TAU
	var point: Vector3 = channel_point + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	var reach: float = maxf(melter.strike_radius_units, 0.0)
	var hits: int = 0
	for other: Node3D in get_tree().get_nodes_in_group("rts_units"):
		if not is_opponent(other):
			continue
		if Units.to_units(_horizontal_distance(other.global_position, point)) > reach + 1e-4:
			continue
		other.receive_damage(self, melter.damage, melter.damage_type, {"canDamageBuildings": melter.canDamageBuildings})
		hits += 1
	melter_strike_count += 1
	if effects_enabled:
		FX.strike(get_parent(), point + Vector3.UP * 0.05, Units.to_metres(reach), Callable(self, "fx_point_visible").bind(point))
	melter_strike.emit(point, hits)


func _set_state(next: State) -> void:
	if state == State.CHANNEL and next != State.CHANNEL:
		if is_instance_valid(_vortex):
			_vortex.finish()
		_vortex = null
	if state == State.BOLT and next != State.BOLT:
		if is_instance_valid(_charge):
			_charge.queue_free()
		_charge = null
		_charge_sound.stop()
	state = next
	cast_elapsed = 0.0
	_sched_steps = 0
	_sched_tail_done = false
	_volley_credit = 0.0
	_strike_credit = 0.0
	match state:
		State.IDLE: _play(&"idle")
		State.MOVING, State.CHASING: _play(&"move")
		State.BOLT:
			_released = false
			_play(bolt.animation)
			if effects_enabled:
				_charge = FX.charge(staff_tip)
				if not _fog_hidden:
					_charge_sound.play()
		State.CHANNEL:
			_play(melter.animation)
			if effects_enabled:
				_vortex = FX.vortex(get_parent(), channel_point + Vector3.UP * 0.075, Callable(self, "_channel_fx_visible"))
				_vortex.set_radius(Units.to_metres(effective_melter_radius_units(0.0)))
		State.DEAD:
			player.stop()
			_flap_sound.stop()


func _play(clip: StringName) -> void:
	player.play(clip, 0.12 if clip in [&"idle", &"move"] else 0.0)
	player.advance(0.0)
	_flap_phase = 0.0


func _move_toward(point: Vector3, delta: float) -> bool:
	point = Units.clamp_to_arena(point)
	var offset := point - global_position
	offset.y = 0.0
	if offset.length() < 0.12:
		return true
	var direction := offset.normalized()
	var avoidance := Vector3.ZERO
	for other: Node3D in get_tree().get_nodes_in_group("rts_units"):
		if other == self:
			continue
		var away := global_position - other.global_position
		away.y = 0.0
		var separation := away.length()
		if separation > 0.001 and separation < 2.6:
			avoidance += away / separation * (1.0 - separation / 2.6)
	var travel := (direction + avoidance * 0.8).normalized()
	global_position = Units.clamp_to_arena(global_position + travel * minf(Units.to_metres(get_effective_move_speed()) * delta, offset.length()))
	_face(global_position + travel, minf(delta * 10.0, 1.0))
	return false


func _face(point: Vector3, weight: float) -> void:
	var offset := point - global_position
	if offset.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(-offset.x, -offset.z), weight)


static func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _exit_tree() -> void:
	if is_instance_valid(_vortex):
		_vortex.queue_free()
