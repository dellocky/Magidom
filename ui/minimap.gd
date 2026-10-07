extends Control
## The arena footprint and team markers share the world's visibility mask and XZ mapping.

const Units = preload("res://scripts/rts/game_units.gd")
const FRIENDLY := Color("#3987e5")
const ENEMY := Color("#d95926")
const INK := Color("#dce7f2")
const SURFACE := Color("#101a24")
const MAP_SHADER = preload("res://ui/minimap.gdshader")

var vision_system: Node
var _terrain: ColorRect
var _frame: Rect2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Allied units share vision. Circles: allies. Diamonds: enemies in sight."
	_terrain = ColorRect.new()
	_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain.material = ShaderMaterial.new()
	_terrain.material.shader = MAP_SHADER
	add_child(_terrain)
	# Markers drawn by this Control must appear above the terrain child.
	_terrain.show_behind_parent = true


func _process(_delta: float) -> void:
	_frame = Rect2(Vector2(8, 24), Vector2(maxf(size.x - 16, 1), maxf(size.y - 49, 1)))
	var edge := minf(_frame.size.x, _frame.size.y)
	_frame.position.x += (_frame.size.x - edge) * 0.5
	_frame.size = Vector2(edge, edge)
	_terrain.position = _frame.position
	_terrain.size = _frame.size
	if is_instance_valid(vision_system):
		var bounds: Rect2 = vision_system.map_bounds
		_terrain.material.set_shader_parameter("visibility_mask", vision_system.visibility_texture)
		_terrain.material.set_shader_parameter("map_bounds", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
		_terrain.material.set_shader_parameter("fog_enabled", vision_system.fog_enabled)
	queue_redraw()


func _draw() -> void:
	# Leave the terrain window transparent; its child draws behind our markers.
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0b111a"), false, 2.0)
	draw_rect(Rect2(0, 0, size.x, 23), SURFACE)
	draw_rect(Rect2(0, size.y - 24, size.x, 24), SURFACE)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(9, 16), "BATTLEFIELD", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
	draw_rect(_frame, Color("#354556"), false, 1.0)
	var key_y := size.y - 12
	draw_circle(Vector2(12, key_y), 3.5, FRIENDLY)
	draw_string(font, Vector2(20, key_y + 4), "Ally", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK)
	_diamond(Vector2(72, key_y), 4.0, ENEMY)
	draw_string(font, Vector2(81, key_y + 4), "Enemy", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, INK)
	if not is_instance_valid(vision_system):
		return
	for unit in vision_system.living_units():
		if not unit.is_alive() or not vision_system.can_see_unit(vision_system.player_team, unit):
			continue
		var uv: Vector2 = vision_system.world_to_uv(unit.global_position)
		if uv.x < 0 or uv.x > 1 or uv.y < 0 or uv.y > 1:
			continue
		var point := _frame.position + uv * _frame.size
		if unit.selected:
			draw_circle(point, 6.0, INK, false, 1.5, true)
		draw_circle(point, 4.7, Color("#080e14"))
		if unit.team == vision_system.player_team:
			draw_circle(point, 3.5, FRIENDLY, true, -1, true)
		else:
			_diamond(point, 4.2, ENEMY)


func _diamond(point: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([point + Vector2(0, -radius), point + Vector2(radius, 0), point + Vector2(0, radius), point + Vector2(-radius, 0)]), color)
