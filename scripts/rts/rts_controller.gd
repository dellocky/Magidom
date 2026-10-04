extends Node

const Units = preload("res://scripts/rts/game_units.gd")
const FX = preload("res://effects/combat_fx.gd")
var rig: Node3D
var hud: CanvasLayer
var level: Node3D
var selected: Array = []
var targeting: String = ""
var _dragging: bool = false
var _start := Vector2.ZERO
var _additive: bool = false
var _preview: MeshInstance3D
var _range_preview: MeshInstance3D


func _ready() -> void:
	hud.melter_requested.connect(begin_targeting.bind("melter"))
	hud.bolt_requested.connect(begin_targeting.bind("attack"))
	hud.stop_requested.connect(stop_selected)


func _process(_delta: float) -> void:
	var remaining: Array = selected.filter(func(unit): return is_instance_valid(unit) and unit.is_alive())
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
		if not selected.is_empty():
			_range_preview.global_position = selected[0].global_position + Vector3.UP * 0.075
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
		elif event.is_action_pressed("ui_cancel"):
			cancel_targeting()
			_cancel_drag()
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
	selected = units.duplicate()
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
			if unit != null: found.append(unit)
	else:
		var rect := Rect2(_start, point - _start).abs()
		for unit: Node3D in get_tree().get_nodes_in_group("rts_units"):
			var anchor := unit.global_position + Vector3.UP
			if not rig.camera.is_position_behind(anchor) and rect.has_point(rig.camera.unproject_position(anchor)):
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


func pick_unit(screen: Vector2) -> Node3D:
	var ray: Vector3 = rig.camera.project_ray_normal(screen)
	var origin: Vector3 = rig.camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + ray * 300.0, 2)
	var result: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null
	var unit: Node3D = result.collider.get_parent()
	return unit if unit.is_alive() else null


func ground_hit(screen: Vector2) -> Variant:
	var origin: Vector3 = rig.camera.project_ray_origin(screen)
	var ray: Vector3 = rig.camera.project_ray_normal(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + ray * 300.0, 1)
	var result: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	return result.position if not result.is_empty() else null


func command_at(screen: Vector2) -> void:
	if selected.is_empty():
		hud.show_message("Select a Hawk Rider first.")
		return
	var target := pick_unit(screen)
	var point: Variant = ground_hit(screen)
	if point == null: return
	var movers: Array = []
	var accepted: int = 0
	for unit in selected:
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
		hud.show_message("No ready caster: check cooldown, mana and cast lock. S interrupts Base Melter.")
	elif target != null:
		hud.show_message("Lightning Bolt — opposing teams only.")


static func formation_offset(index: int, count: int) -> Vector3:
	var columns := ceili(sqrt(float(count)))
	var rows := ceili(float(count) / columns)
	return Vector3((index % columns - (columns - 1) * 0.5) * 4.2, 0, (floorf(float(index) / columns) - (rows - 1) * 0.5) * 4.2)


func begin_targeting(mode: String) -> void:
	cancel_targeting()
	if selected.is_empty():
		hud.show_message("Select a Hawk Rider first.")
		return
	if not selected.any(func(unit): return unit.can_cast_melter() if mode == "melter" else unit.can_cast_bolt()):
		hud.show_message("No ready caster: check cooldown, mana and cast lock. S interrupts Base Melter.")
		return
	targeting = mode
	hud.set_targeting(mode)
	if mode == "melter":
		_preview = FX.ring(level, Color(0.45, 0.72, 1), Units.to_metres(selected[0].melter.radius_units))
		_range_preview = FX.ring(level, Color(0.3, 0.5, 0.7, 0.35), Units.to_metres(selected[0].melter.range_units))
		hud.show_message("Base Melter: click ground inside the range ring. RMB / Esc cancels.")
	else:
		hud.show_message("Lightning Bolt: click an opposing unit. RMB / Esc cancels.")


func _confirm_target(screen: Vector2) -> void:
	var count: int = 0
	if targeting == "melter":
		var point: Variant = ground_hit(screen)
		if point == null: return
		for unit in selected:
			if unit.issue_cast_melter(point): count += 1
	else:
		var target := pick_unit(screen)
		for unit in selected:
			if unit.issue_attack(target): count += 1
	if count > 0:
		cancel_targeting()
	else:
		hud.show_message("No eligible caster: check team, range, mana, cooldown and cast lock.")


func stop_selected() -> void:
	cancel_targeting()
	var stopped: int = 0
	for unit in selected:
		if unit.issue_stop(): stopped += 1
	hud.show_message("Stopped %d unit(s). Lightning Bolt cannot be interrupted." % stopped)


func cancel_targeting() -> void:
	targeting = ""
	if is_instance_valid(_preview): _preview.queue_free()
	if is_instance_valid(_range_preview): _range_preview.queue_free()
	_preview = null
	_range_preview = null
	hud.set_targeting("")


func _cancel_drag() -> void:
	_dragging = false
	hud.set_marquee(Rect2(), false)
