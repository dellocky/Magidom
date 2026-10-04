extends SceneTree
## Headless smoke test for effects/combat_fx.gd and the synthesized audio.

const Fx = preload("res://effects/combat_fx.gd")


func _init() -> void:
	var root_node: Node3D = Node3D.new()
	get_root().add_child(root_node)
	var staff: Node3D = Node3D.new()
	root_node.add_child(staff)
	staff.position = Vector3(0, 3, 0)
	var made: Array[Node3D] = []
	var ch: Node3D = Fx.charge(staff)
	ch.call("set_charge", 1.0)
	var bm: Node3D = Fx.beam(root_node, staff, Vector3(20, 1, 5))
	var vx: Node3D = Fx.vortex(root_node, Vector3(5, 0.5, 5))
	vx.call("set_radius", 15.0)
	var mk: Node3D = Fx.move_marker(root_node, Vector3(1, 0.5, 1))
	var rg: MeshInstance3D = Fx.ring(root_node, Color.RED, 1.75)
	made.append_array([ch, bm, vx, mk])
	for i in 60:
		await process_frame
	var ok: bool = true
	ok = ok and is_instance_valid(ch) and is_instance_valid(vx) and rg != null
	print("after ~60 frames: beam valid=", is_instance_valid(bm), " marker valid=", is_instance_valid(mk))
	vx.call("finish")
	for i in 120:
		await process_frame
	print("vortex freed=", not is_instance_valid(vx))
	print("fx_check: ", "OK" if ok else "FAILED")
	quit(0 if ok else 1)
