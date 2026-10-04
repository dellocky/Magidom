extends SceneTree
## Read-only asset diagnostics: run with --headless --script res://tests/inspect_hawk.gd.

func _initialize() -> void:
	call_deferred("inspect")

func inspect() -> void:
	var model: Node3D = load("res://units/hawkRider/hawk_rider.tscn").instantiate()
	root.add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.play("finger")
	player.advance(1.82)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		print(node.get_path(), " aabb=", node.get_aabb(), " transform=", node.global_transform)
	print("Arrow key constants: ", KEY_LEFT, " ", KEY_UP, " ", KEY_RIGHT, " ", KEY_DOWN)
	model.free()
	quit()
