extends Node3D

const UnitScene = preload("res://units/hawkRider/hawk_rider_unit.tscn")
const CameraRig = preload("res://scripts/rts/rts_camera.gd")
const Controller = preload("res://scripts/rts/rts_controller.gd")
const Vision = preload("res://scripts/rts/vision_system.gd")
const Units = preload("res://scripts/rts/game_units.gd")
const FX = preload("res://effects/combat_fx.gd")
const PauseMenu = preload("res://ui/pause_menu.gd")

@export_enum("Friendly", "Enemy") var player_team: int = 0
## Disable to reveal the entire arena and control both teams for sandbox testing.
@export var fog_enabled: bool = true

var vision_system: Node
var _floor_material: ShaderMaterial
var units: Node3D
var rig: Node3D
var hud: CanvasLayer
var controller: Node
var _spawn_counts: Array[int] = [0, 0]
var _pause_menu: CanvasLayer
const TEAM_LIMIT: int = 24


func _ready() -> void:
	vision_system = Vision.new()
	vision_system.name = "VisionSystem"
	vision_system.player_team = player_team
	vision_system.fog_enabled = fog_enabled
	# The minimap and fog use the actual floor footprint, including its outer border.
	var floor_mesh: MeshInstance3D = $MeshInstance3D
	var bounds := floor_mesh.get_aabb()
	var corner: Vector3 = floor_mesh.to_global(bounds.position)
	var opposite: Vector3 = floor_mesh.to_global(bounds.end)
	vision_system.map_bounds = Rect2(Vector2(corner.x, corner.z), Vector2(opposite.x - corner.x, opposite.z - corner.z)).abs()
	add_child(vision_system)
	_floor_material = floor_mesh.get_active_material(0).duplicate() as ShaderMaterial
	floor_mesh.material_override = _floor_material
	_floor_material.set_shader_parameter("visibility_mask", vision_system.visibility_texture)
	var map: Rect2 = vision_system.map_bounds
	_floor_material.set_shader_parameter("map_bounds", Vector4(map.position.x, map.position.y, map.size.x, map.size.y))
	_floor_material.set_shader_parameter("fog_enabled", fog_enabled)
	units = Node3D.new()
	units.name = "Units"
	add_child(units)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	hud = $HUD
	hud.set_vision_system(vision_system)
	rig.hud = hud
	controller = Controller.new()
	controller.name = "RTSController"
	controller.level = self
	controller.rig = rig
	controller.hud = hud
	add_child(controller)
	hud.spawn_requested.connect(spawn_unit)
	_pause_menu = PauseMenu.new()
	_pause_menu.name = "PauseMenu"
	add_child(_pause_menu)
	spawn_unit(0)
	spawn_unit(1)
	vision_system.refresh_mask()
	vision_system.refresh_unit_visibility()


func _process(_delta: float) -> void:
	if vision_system == null:
		return
	vision_system.player_team = player_team
	vision_system.fog_enabled = fog_enabled
	_floor_material.set_shader_parameter("fog_enabled", fog_enabled)


func spawn_unit(team: int) -> Node3D:
	var living: Array = get_tree().get_nodes_in_group("rts_units").filter(func(unit): return unit.team == team)
	if living.size() >= TEAM_LIMIT:
		hud.play_deny()
		return null
	var origin := Vector3(-8.0 if team == 0 else 8.0, Units.FLOOR_Y, 0)
	var position_found := origin
	for index in 180:
		var ring := ceili(sqrt(float(index)))
		var angle := index * 2.399963
		var candidate := Units.clamp_to_arena(origin + Vector3(cos(angle), 0, sin(angle)) * ring * 3.5)
		var occupied := false
		for other: Node3D in get_tree().get_nodes_in_group("rts_units"):
			if other.global_position.distance_to(candidate) < 3.6:
				occupied = true
				break
		if not occupied:
			position_found = candidate
			break
	var scene: PackedScene = UnitScene
	var display := "Hawk Rider"
	if team == 0:
		var gs := get_node_or_null("/root/GameState")
		if gs != null and gs.faction != null:
			var us: PackedScene = gs.faction.get("unit_scene")
			if us == null:
				hud.play_deny()
				return null
			scene = us
			display = str(gs.faction.get("unit_display_name"))
			if display == "":
				display = "Allied unit"
	var unit: Node3D = scene.instantiate()
	unit.team = team
	unit.vision_system = vision_system
	_spawn_counts[team] += 1
	unit.name = "%s%s%d" % ["Friendly" if team == 0 else "Enemy", display.replace(" ", ""), _spawn_counts[team]]
	unit.position = position_found
	unit.rotation.y = -PI / 2.0 if team == 0 else PI / 2.0
	units.add_child(unit)
	vision_system.register_unit(unit)
	return unit


func cast_global_spell(point: Vector3) -> void:
	var gs := get_node_or_null("/root/GameState")
	var spell: Resource = gs.current_global_spell() if gs != null else null
	if spell == null:
		return
	var radius_u := float(spell.get("aoe_radius_units"))
	var centre := Vector3(point.x, Units.FLOOR_Y + 0.05, point.z)
	var duration := float(spell.get("duration"))
	var bonus := float(spell.get("move_speed_bonus_fraction"))
	var drain := float(spell.get("hp_drain_fraction_per_second"))
	for unit: Node3D in get_tree().get_nodes_in_group("rts_units"):
		if int(unit.team) != player_team or not unit.has_method("apply_frenzy"):
			continue
		var d := Vector2(unit.global_position.x - centre.x, unit.global_position.z - centre.z).length()
		if Units.to_units(d) <= radius_u:
			unit.apply_frenzy(bonus, drain, duration)
	# Placement ring: bloom, rise, then fade out on the ground target.
	var ring := FX.ring(self, Color(0.92, 0.62, 0.32), Units.to_metres(radius_u))
	ring.position = centre
	var fade_out := func(v: float) -> void:
		if is_instance_valid(ring):
			ring.material_override.set_shader_parameter("fade", v)
	var tween := create_tween()
	tween.tween_property(ring, "position:y", centre.y + 0.45, 0.55)
	tween.parallel().tween_method(fade_out, 1.0, 0.0, 0.55)
	tween.tween_callback(ring.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if controller != null and not String(controller.targeting).is_empty():
		controller.cancel_targeting()
		return
	if _pause_menu != null:
		_pause_menu.open()
