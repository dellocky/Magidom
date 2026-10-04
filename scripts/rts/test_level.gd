extends Node3D

const UnitScene = preload("res://units/hawkRider/hawk_rider_unit.tscn")
const CameraRig = preload("res://scripts/rts/rts_camera.gd")
const Controller = preload("res://scripts/rts/rts_controller.gd")
const HUD = preload("res://ui/test_level_hud.tscn")
const Units = preload("res://scripts/rts/game_units.gd")

var units: Node3D
var rig: Node3D
var hud: CanvasLayer
var controller: Node
var _spawn_counts: Array[int] = [0, 0]
const TEAM_LIMIT: int = 24


func _ready() -> void:
	units = Node3D.new()
	units.name = "Units"
	add_child(units)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	hud = HUD.instantiate()
	add_child(hud)
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
	hud.show_message("Both teams are under your control. Select a Hawk Rider to begin.")


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
	_spawn_counts[team] += 1
	unit.name = "%sHawkRider%d" % ["Friendly" if team == 0 else "Enemy", _spawn_counts[team]]
	unit.position = position_found
	unit.rotation.y = -PI / 2.0 if team == 0 else PI / 2.0
	units.add_child(unit)
	return unit


func _return_to_menu() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
