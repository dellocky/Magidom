extends Node3D

@export var move_speed: float = 12.0
@export var edge_pan_margin: float = 24.0
var _position_log_timer: float = 0.0

func _ready() -> void:
	$Camera3D.look_at(Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	print("Camera position: ", $Camera3D.global_position)

func _process(delta: float) -> void:
	var direction := Vector2(
		Input.get_axis("camera_left", "camera_right"),
		Input.get_axis("camera_down", "camera_up")
	)
	var viewport := get_viewport()
	var viewport_size := viewport.get_visible_rect().size
	var mouse_position := viewport.get_mouse_position()
	if mouse_position.x <= edge_pan_margin:
		direction.x -= 1.0
	elif mouse_position.x >= viewport_size.x - edge_pan_margin:
		direction.x += 1.0
	if mouse_position.y <= edge_pan_margin:
		direction.y += 1.0
	elif mouse_position.y >= viewport_size.y - edge_pan_margin:
		direction.y -= 1.0

	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var camera_right: Vector3 = $Camera3D.global_basis.x
	var camera_up: Vector3 = $Camera3D.global_basis.y
	camera_right.z = 0.0
	camera_up.z = 0.0
	var movement := camera_right.normalized() * direction.x + camera_up.normalized() * direction.y
	position += movement * move_speed * delta

	if direction.length_squared() > 0.0:
		_position_log_timer += delta
	if _position_log_timer >= 0.2:
		_position_log_timer = 0.0
		print("Camera position: ", $Camera3D.global_position)
	elif direction.length_squared() == 0.0:
		_position_log_timer = 0.0
