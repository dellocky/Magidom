extends Node

const Units = preload("res://scripts/rts/game_units.gd")
const FX = preload("res://effects/combat_fx.gd")
var rig: Node3D
var hud: CanvasLayer
var level: Node3D
var selected: Array = []
var targeting: String = ""
var global_spell: Resource
var _dragging: bool = false
var _start := Vector2.ZERO
var _additive: bool = false
var _preview: MeshInstance3D
var _range_preview: MeshInstance3D
var _preview_caster: Node3D


func _ready() -> void:
	hud.melter_requested.connect(begin_targeting.bind("melter"))
	hud.bolt_requested.connect(begin_targeting.bind("attack"))
	hud.stop_requested.connect(stop_selected)
	hud.global_spell_requested.connect(_on_global_spell_requested)


func _process(_delta: float) -> void:
	var remaining: Array = selected.filter(func(unit): return _can_control(unit))
	if remaining.size() != selected.size():
		set_selection(remaining)
	if _dragging:
		if not DisplayServer.window_is_focused():
			_cancel_drag()
		else:
			hud.set_marquee(Rect2(_start, get_viewport().get_mouse_position() - _start).abs(), true)
	if is_instance_valid(_preview):
		_preview.global_position = Units.clamp_to_arena(rig.ground_point(get_viewport().get_mouse_position())) + Vector3.UP * 0.09
		_preview.visible = not hud.pointer_over_ui(get_viewport().get_mouse_position())
		if targeting == "global":
			pass  # Faction spells have no caster or range ring; the ring follows the cursor.
		elif _can_control(_preview_caster) and _preview_caster in selected and _preview_caster.melter != null:
			_range_preview.global_position = _preview_caster.global_position + Vector3.UP * 0.075
			_update_ring_radius(_preview, Units.to_metres(_preview_caster.effective_melter_radius_units(0.0)))
			_update_ring_radius(_range_preview, Units.to_metres(_preview_caster.melter.range_units))
		else:
			cancel_targeting()


func _input(event: InputEvent) -> void:
	# GUI may consume release over a panel; finalize only a drag that began in the world.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _dragging:
		_finish_selection(event.position)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("unit_stop"):
			stop_selected()
		elif event.is_action_pressed("unit_melter"):
			begin_targeting("melter")
		elif event.is_action_pressed("camera_focus"):
			rig.focus_units(selected)
	if not event is InputEventMouseButton or not event.pressed:
		return
	if hud.pointer_over_ui(event.position):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if not targeting.is_empty():
			cancel_targeting()
		else:
			command_at(event.position)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if not targeting.is_empty():
			_confirm_target(event.position)
		else:
			_start = event.position
			_additive = event.shift_pressed
			_dragging = true


func set_selection(units: Array) -> void:
	for unit in selected:
		if is_instance_valid(unit): unit.selected = false
	selected = units.filter(func(unit): return _can_control(unit))
	for unit in selected:
		unit.selected = true
	hud.set_selection(selected)


func _finish_selection(point: Vector2) -> void:
	_dragging = false
	hud.set_marquee(Rect2(), false)
	var found: Array = []
	if point.distance_to(_start) < 7.0:
		if not hud.pointer_over_ui(point):
			var unit := pick_unit(point)
			if _can_control(unit): found.append(unit)
	else:
		var rect := Rect2(_start, point - _start).abs()
		for unit: Node3D in get_tree().get_nodes_in_group("rts_units"):
			if _can_control(unit) and _selection_ring_overlaps_rect(unit, rect):
				found.append(unit)
	if _additive:
		var merged := selected.duplicate()
		for unit in found:
			if unit in merged and point.distance_to(_start) < 7.0:
				merged.erase(unit)
			elif unit not in merged:
				merged.append(unit)
		set_selection(merged)
	else:
		set_selection(found)


func _selection_ring_overlaps_rect(unit: Node3D, rect: Rect2) -> bool:
	var ring_position: Vector3 = unit.get_selection_ring_position()
	if rig.camera.is_position_behind(ring_position):
		return false
	var radius: float = unit.get_selection_ring_radius()
	var min_screen := Vector2(INF, INF)
	var max_screen := Vector2(-INF, -INF)
	for sample in 32:
		var angle: float = TAU * float(sample) / 32.0
		var ring_point := ring_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if rig.camera.is_position_behind(ring_point):
			continue
		var screen_point: Vector2 = rig.camera.unproject_position(ring_point)
		min_screen.x = minf(min_screen.x, screen_point.x)
		min_screen.y = minf(min_screen.y, screen_point.y)
		max_screen.x = maxf(max_screen.x, screen_point.x)
		max_screen.y = maxf(max_screen.y, screen_point.y)
	if min_screen.x == INF:
		return false
	return rect.intersects(Rect2(min_screen, max_screen - min_screen), true)


func pick_unit(screen: Vector2) -> Node3D:
	var origin: Vector3 = rig.camera.project_ray_origin(screen)
	var ray: Vector3 = rig.camera.project_ray_normal(screen)
	var closest_unit: Node3D
	var closest_distance_squared: float = INF
	for unit: Node3D in get_tree().get_nodes_in_group("rts_units"):
		if not unit.is_alive() or not _can_see(unit):
			continue
		var ring_position: Vector3 = unit.get_selection_ring_position()
		if rig.camera.is_position_behind(ring_position):
			continue
		var ring_plane := Plane(Vector3.UP, ring_position.y)
		var hit: Variant = ring_plane.intersects_ray(origin, ray)
		if hit == null:
			continue
		var offset := Vector2(hit.x - ring_position.x, hit.z - ring_position.z)
		var distance_squared: float = offset.length_squared()
		var ring_radius: float = unit.get_selection_ring_radius()
		if distance_squared <= ring_radius * ring_radius and distance_squared < closest_distance_squared:
			closest_unit = unit
			closest_distance_squared = distance_squared
	return closest_unit


func _can_control(unit: Variant) -> bool:
	if not is_instance_valid(unit) or not unit.is_alive():
		return false
	var vision: Node = level.get("vision_system") if is_instance_valid(level) else null
	return vision.controls(unit) if is_instance_valid(vision) else true


func _can_see(unit: Node3D) -> bool:
	var vision: Node = level.get("vision_system") if is_instance_valid(level) else null
	return vision.can_see_unit(vision.player_team, unit) if is_instance_valid(vision) else true


func ground_hit(screen: Vector2) -> Variant:
	var origin: Vector3 = rig.camera.project_ray_origin(screen)
	var ray: Vector3 = rig.camera.project_ray_normal(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + ray * 300.0, 1)
	var result: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	return result.position if not result.is_empty() else null


func command_at(screen: Vector2) -> void:
	if selected.is_empty():
		hud.play_deny()
		return
	var target := pick_unit(screen)
	var point: Variant = ground_hit(screen)
	if point == null: return
	var movers: Array = []
	var accepted: int = 0
	for unit in selected:
		if not _can_control(unit):
			continue
		if target != null and unit.team != target.team:
			if unit.issue_attack(target): accepted += 1
		elif unit.accepts_orders():
			movers.append(unit)
	for index in movers.size():
		var destination := Units.clamp_to_arena(point + formation_offset(index, movers.size()))
		if movers[index].issue_move(destination): accepted += 1
	if not movers.is_empty():
		FX.move_marker(level, Units.clamp_to_arena(point) + Vector3.UP * 0.09)
	if accepted == 0:
		hud.play_deny()


static func formation_offset(index: int, count: int) -> Vector3:
	var columns := ceili(sqrt(float(count)))
	var rows := ceili(float(count) / columns)
	return Vector3((index % columns - (columns - 1) * 0.5) * 4.2, 0, (floorf(float(index) / columns) - (rows - 1) * 0.5) * 4.2)


func begin_targeting(mode: String) -> void:
	cancel_targeting()
	if selected.is_empty():
		hud.play_deny()
		return
	# Self-cast spells (Martyr's Human Baneling) never need a target: fire at once.
	if mode == "melter":
		var casters: Array = selected.filter(func(unit): return _can_control(unit) and unit.melter != null and bool(unit.melter.get("self_cast")))
		if not casters.is_empty():
			var fired := 0
			for unit in casters:
				if unit.issue_cast_melter(unit.global_position):
					fired += 1
			if fired == 0:
				hud.play_deny()
			return
	var eligible: Array = selected.filter(func(unit): return _can_control(unit) and (unit.can_cast_melter() if mode == "melter" else unit.can_cast_bolt()))
	if eligible.is_empty():
		hud.play_deny()
		return
	targeting = mode
	hud.set_targeting(mode)
	if mode == "melter":
		_preview_caster = eligible[0]
		_preview = FX.ring(level, Color(0.45, 0.72, 1), Units.to_metres(eligible[0].effective_melter_radius_units(0.0)))
		_range_preview = FX.ring(level, Color(0.3, 0.5, 0.7, 0.35), Units.to_metres(eligible[0].melter.range_units))


func _on_global_spell_requested() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		hud.play_deny()
		return
	var spell: Resource = gs.current_global_spell()
	if spell == null:
		hud.play_deny()
		return
	begin_global_targeting(spell)


func begin_global_targeting(spell: Resource) -> void:
	cancel_targeting()
	global_spell = spell
	targeting = "global"
	_preview_caster = null
	hud.set_targeting("global")
	var radius: float = float(spell.get("aoe_radius_units"))
	_preview = FX.ring(level, Color(0.92, 0.62, 0.32), Units.to_metres(radius))


func _confirm_target(screen: Vector2) -> void:
	if targeting == "global":
		var point: Variant = ground_hit(screen)
		if point == null:
			return
		var gs := get_node_or_null("/root/GameState")
		if gs != null and gs.cast_global():
			level.cast_global_spell(point)
			cancel_targeting()
		else:
			hud.play_deny()
		return
	var count: int = 0
	if targeting == "melter":
		var point: Variant = ground_hit(screen)
		if point == null: return
		for unit in selected:
			if _can_control(unit) and unit.issue_cast_melter(point): count += 1
	else:
		var target := pick_unit(screen)
		for unit in selected:
			if _can_control(unit) and unit.issue_attack(target): count += 1
	if count > 0:
		cancel_targeting()
	else:
		hud.play_deny()


func stop_selected() -> void:
	cancel_targeting()
	for unit in selected:
		if _can_control(unit):
			unit.issue_stop()


func cancel_targeting() -> void:
	targeting = ""
	global_spell = null
	if is_instance_valid(_preview): _preview.queue_free()
	if is_instance_valid(_range_preview): _range_preview.queue_free()
	_preview = null
	_range_preview = null
	_preview_caster = null
	hud.set_targeting("")


func _update_ring_radius(ring: MeshInstance3D, radius: float) -> void:
	var diameter := 2.0 * (radius + 1.0)
	ring.mesh.size = Vector2(diameter, diameter)
	ring.material_override.set_shader_parameter("size_m", diameter)
	ring.material_override.set_shader_parameter("radius_m", radius)
	ring.material_override.set_shader_parameter("thickness_m", 0.09 + radius * 0.02)


func _cancel_drag() -> void:
	_dragging = false
	hud.set_marquee(Rect2(), false)
