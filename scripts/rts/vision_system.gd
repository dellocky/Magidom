extends Node
## Exact circular team sight for gameplay; a shared current/explored mask for rendering.

signal refreshed

const Units = preload("res://scripts/rts/game_units.gd")
const MASK_SIZE := 128
const MASK_INTERVAL := 0.1

var player_team: int = 0
var fog_enabled: bool = true
var map_bounds := Rect2(-50.0, -50.0, 100.0, 100.0)
var visibility_texture: ImageTexture
var _current: Image
var _explored: Image
var _mask: Image
var _registered: Array[Node3D] = []
var _elapsed := 0.0
var _mask_team := -1
var _was_enabled := true


func _ready() -> void:
	# Run after unit movement, so display visibility follows the latest positions.
	process_priority = 100
	_current = Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_L8)
	_explored = Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_L8)
	_mask = Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBA8)
	_current.fill(Color.BLACK)
	_explored.fill(Color.BLACK)
	_mask.fill(Color(0, 0, 0, 1))
	visibility_texture = ImageTexture.create_from_image(_mask)
	_mask_team = player_team


func register_unit(unit: Node3D) -> void:
	if unit not in _registered:
		_registered.append(unit)
	_apply_unit_visibility(unit)
	_elapsed = MASK_INTERVAL


func living_units() -> Array[Node]:
	return get_tree().get_nodes_in_group("rts_units")


func controls(unit: Node3D) -> bool:
	return is_instance_valid(unit) and unit.is_alive() and (not fog_enabled or unit.team == player_team)


func can_see_point(team: int, point: Vector3) -> bool:
	if not fog_enabled:
		return true
	var p := Vector2(point.x, point.z)
	for source in living_units():
		if not source.is_alive() or source.team != team:
			continue
		var radius := Units.to_metres(maxf(source.stats.vision_range, 0.0))
		if radius <= 0.0:
			continue
		if p.distance_squared_to(Vector2(source.global_position.x, source.global_position.z)) <= radius * radius:
			return true
	return false


func can_see_unit(team: int, unit: Node3D) -> bool:
	if not is_instance_valid(unit):
		return false
	return not fog_enabled or unit.team == team or can_see_point(team, unit.global_position)


func world_to_uv(point: Vector3) -> Vector2:
	return (Vector2(point.x, point.z) - map_bounds.position) / map_bounds.size


func is_explored(point: Vector3) -> bool:
	if _explored == null:
		return false
	var uv := world_to_uv(point)
	if uv.x < 0 or uv.y < 0 or uv.x > 1 or uv.y > 1:
		return false
	return _explored.get_pixel(clampi(int(uv.x * MASK_SIZE), 0, MASK_SIZE - 1), clampi(int(uv.y * MASK_SIZE), 0, MASK_SIZE - 1)).r > 0.5


func _process(delta: float) -> void:
	refresh_unit_visibility()
	_elapsed += delta
	if _elapsed >= MASK_INTERVAL or _was_enabled != fog_enabled or _mask_team != player_team:
		_elapsed = 0.0
		refresh_mask()


func refresh_unit_visibility() -> void:
	# Keep dying units registered until freed; they no longer grant sight but must still hide.
	_registered = _registered.filter(func(unit): return is_instance_valid(unit) and unit.is_inside_tree())
	for unit in _registered:
		_apply_unit_visibility(unit)


func _apply_unit_visibility(unit: Node3D) -> void:
	if is_instance_valid(unit) and unit.has_method("set_fog_hidden"):
		unit.set_fog_hidden(not can_see_unit(player_team, unit))


func refresh_mask() -> void:
	if _mask == null:
		return
	if _mask_team != player_team:
		# Do not inherit the other team's exploration history.
		_explored.fill(Color.BLACK)
		_mask_team = player_team
	_current.fill(Color.BLACK)
	# Debug reveal does not permanently explore the map.
	if fog_enabled:
		for source in living_units():
			if source.is_alive() and source.team == player_team:
				_paint_sight(source.global_position, Units.to_metres(maxf(source.stats.vision_range, 0.0)))
	for y in MASK_SIZE:
		for x in MASK_SIZE:
			var now := _current.get_pixel(x, y).r
			var seen := maxf(_explored.get_pixel(x, y).r, now)
			_explored.set_pixel(x, y, Color(seen, seen, seen))
			_mask.set_pixel(x, y, Color(now if fog_enabled else 1.0, seen, 0, 1))
	visibility_texture.update(_mask)
	_was_enabled = fog_enabled
	refreshed.emit()


func _paint_sight(point: Vector3, radius: float) -> void:
	if radius <= 0.0:
		return
	var center := Vector2(point.x, point.z)
	var cell := map_bounds.size / float(MASK_SIZE)
	var first_y := maxi(0, ceili((center.y - radius - map_bounds.position.y) / cell.y - 0.5))
	var last_y := mini(MASK_SIZE - 1, floori((center.y + radius - map_bounds.position.y) / cell.y - 0.5))
	for y in range(first_y, last_y + 1):
		var dy := map_bounds.position.y + (y + 0.5) * cell.y - center.y
		var half_width := sqrt(maxf(radius * radius - dy * dy, 0.0))
		var first_x := maxi(0, ceili((center.x - half_width - map_bounds.position.x) / cell.x - 0.5))
		var last_x := mini(MASK_SIZE - 1, floori((center.x + half_width - map_bounds.position.x) / cell.x - 0.5))
		if last_x >= first_x:
			_current.fill_rect(Rect2i(first_x, y, last_x - first_x + 1, 1), Color.WHITE)
