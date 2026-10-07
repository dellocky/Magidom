extends Node3D

const UnitScene = preload("res://units/hawkRider/hawk_rider_unit.tscn")
const CameraRig = preload("res://scripts/rts/rts_camera.gd")
const Controller = preload("res://scripts/rts/rts_controller.gd")
const Vision = preload("res://scripts/rts/vision_system.gd")
const Units = preload("res://scripts/rts/game_units.gd")

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
	hud.menu_requested.connect(_return_to_menu)
	spawn_unit(0)
	spawn_unit(1)
	vision_system.refresh_mask()
	vision_system.refresh_unit_visibility()
	hud.show_message("Select your team's Hawk Riders. Allies share vision." if fog_enabled else "Debug view: both teams are under your control.")


func _process(_delta: float) -> void:
	if vision_system == null:
		return
	vision_system.player_team = player_team
	vision_system.fog_enabled = fog_enabled
	_floor_material.set_shader_parameter("fog_enabled", fog_enabled)


func spawn_unit(team: int) -> Node3D:
	var living: Array = get_tree().get_nodes_in_group("rts_units").filter(func(unit): return unit.team == team)
	if living.size() >= TEAM_LIMIT:
		hud.show_message("Sandbox limit: %d living units per team." % TEAM_LIMIT)
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
	var unit: Node3D = UnitScene.instantiate()
	unit.team = team
	unit.vision_system = vision_system
	_spawn_counts[team] += 1
	unit.name = "%sHawkRider%d" % ["Friendly" if team == 0 else "Enemy", _spawn_counts[team]]
	unit.position = position_found
	unit.rotation.y = -PI / 2.0 if team == 0 else PI / 2.0
	units.add_child(unit)
	vision_system.register_unit(unit)
	return unit


func _return_to_menu() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
