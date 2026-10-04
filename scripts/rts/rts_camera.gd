extends Node3D

const Units = preload("res://scripts/rts/game_units.gd")
var camera: Camera3D
var hud: CanvasLayer
var distance: float = 30.0
var target_position := Vector3(0, 0.5, 0)
var _dragging: bool = false
var _drag_anchor := Vector3.ZERO


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.fov = 50.0
	camera.far = 250.0
	add_child(camera)
	position = target_position
	_update_camera()


func _process(delta: float) -> void:
	var viewport := get_viewport()
	var size := viewport.get_visible_rect().size
	var mouse := viewport.get_mouse_position()
	var focused := DisplayServer.window_is_focused()
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or not focused:
		_dragging = false
	if focused:
		var direction := Vector2(Input.get_axis("camera_left", "camera_right"), Input.get_axis("camera_up", "camera_down"))
		var over_ui: bool = is_instance_valid(hud) and hud.pointer_over_ui(mouse)
		if not _dragging and not over_ui and Rect2(Vector2.ZERO, size).has_point(mouse):
			if mouse.x < 14: direction.x -= 1
			if mouse.x > size.x - 14: direction.x += 1
			if mouse.y < 14: direction.y -= 1
			if mouse.y > size.y - 14: direction.y += 1
		if direction.length_squared() > 1.0:
			direction = direction.normalized()
		target_position += Vector3(direction.x, 0, direction.y) * distance * 0.65 * delta
		target_position = Units.clamp_to_arena(target_position)
	position = position.lerp(target_position, 1.0 - exp(-14.0 * delta))
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = clampf(distance * 0.88, 10.0, 75.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = clampf(distance / 0.88, 10.0, 75.0)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			_drag_anchor = ground_point(event.position)
	elif event is InputEventMouseMotion and _dragging:
		var point := ground_point(event.position)
		target_position = Units.clamp_to_arena(target_position + _drag_anchor - point)
		position = target_position


func focus_units(units: Array) -> void:
	var centre := Vector3.ZERO
	var count: int = 0
	for unit in units:
		if is_instance_valid(unit):
			centre += unit.global_position
			count += 1
	if count > 0:
		target_position = Units.clamp_to_arena(centre / count)


func ground_point(screen: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	var hit: Variant = Plane(Vector3.UP, Units.FLOOR_Y).intersects_ray(origin, ray)
	return hit if hit != null else target_position


func _update_camera() -> void:
	camera.position = Vector3(0, distance * 0.82, distance * 0.57)
	camera.look_at(global_position, Vector3.UP)
