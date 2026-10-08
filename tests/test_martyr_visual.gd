extends SceneTree
## Run with --headless --script res://tests/test_martyr_visual.gd.

const ModelScene = preload("res://units/martyr/martyr.tscn")
const UnitScene = preload("res://units/martyr/martyr_unit.tscn")
const CLIPS := ["idle", "run", "slap", "sillyrun"]
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)


func run() -> void:
	inspect(ModelScene.instantiate(), "preview")
	var unit := UnitScene.instantiate()
	unit.effects_enabled = false
	inspect(unit, "unit")
	print("Martyr visual: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func inspect(model: Node3D, label: String) -> void:
	root.add_child(model)
	model.set_physics_process(false)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton: Skeleton3D
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		skeleton = skeletons[0] as Skeleton3D
	check(player != null and skeleton != null, label + " has an animation player and skeleton")
	if player == null or skeleton == null:
		model.free()
		return
	var hips := -1
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_name(bone).ends_with("Hips"):
			hips = bone
	check(hips >= 0, label + " has the Hips bone")
	if hips < 0:
		model.free()
		return
	var meshes := skeleton.find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty(), label + " has skinned geometry")
	for node in meshes:
		var mesh := node as MeshInstance3D
		check(mesh.visible and mesh.mesh != null and mesh.mesh.get_surface_count() > 0,
			label + " mesh is visible and nonempty")
	check(player.autoplay == "idle", label + " autoplays idle")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var rest := skeleton.get_bone_rest(hips).origin
	print(label, " hips=", skeleton.get_bone_name(hips), " rest=", rest)
	for clip: String in CLIPS:
		check(player.has_animation(clip), label + " has " + clip)
		if not player.has_animation(clip):
			continue
		var animation := player.get_animation(clip)
		var loop_mode := Animation.LOOP_NONE if clip == "slap" else Animation.LOOP_LINEAR
		check(animation.loop_mode == loop_mode, label + " loop mode: " + clip)
		var hip_tracks := 0
		var rotation_tracks := 0
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			if animation.track_get_type(track) == Animation.TYPE_POSITION_3D \
					and path.get_subname_count() == 1 \
					and path.get_subname(0) == skeleton.get_bone_name(hips):
				hip_tracks += 1
			if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				rotation_tracks += 1
		check(hip_tracks == 1, label + " retains authored hip bounce: " + clip)
		check(rotation_tracks > 0, label + " retains bone rotation animation: " + clip)
		player.stop()
		player.play(clip, 0.0)
		var max_drift := 0.0
		var hands_overhead := true
		var head := skeleton.find_bone("mixamorig_Head")
		var left_hand := skeleton.find_bone("mixamorig_LeftHand")
		var right_hand := skeleton.find_bone("mixamorig_RightHand")
		check(head >= 0 and left_hand >= 0 and right_hand >= 0, label + " preserves hand/head bones")
		for sample in 31:
			player.seek(animation.length * float(sample) / 30.0, true)
			max_drift = maxf(max_drift, skeleton.get_bone_pose_position(hips).distance_to(rest))
			if clip == "sillyrun" and head >= 0 and left_hand >= 0 and right_hand >= 0:
				var head_y := skeleton.get_bone_global_pose(head).origin.y
				hands_overhead = hands_overhead and skeleton.get_bone_global_pose(left_hand).origin.y > head_y + 0.10
				hands_overhead = hands_overhead and skeleton.get_bone_global_pose(right_hand).origin.y > head_y + 0.10
		check(max_drift < 0.10, label + " hip motion stays within 10 cm: " + clip)
		if clip == "sillyrun":
			check(hands_overhead, label + " keeps both hands overhead throughout sillyrun")
		if clip != "slap":
			var closed := true
			for track in animation.get_track_count():
				var keys := animation.track_get_key_count(track)
				if keys < 2:
					continue
				if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
					var first: Quaternion = animation.track_get_key_value(track, 0)
					var last: Quaternion = animation.track_get_key_value(track, keys - 1)
					closed = closed and first.angle_to(last) < 0.001
				elif animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
					var first: Vector3 = animation.track_get_key_value(track, 0)
					var last: Vector3 = animation.track_get_key_value(track, keys - 1)
					closed = closed and first.distance_to(last) < 0.001
			check(closed, label + " loop closes without a pose jump: " + clip)
		else:
			var whack := load("res://units/martyr/whack.tres")
			check(absf(animation.length - whack.duration) < 0.01, label + " slap preserves attack duration")
			player.seek(whack.release_time, true)
			var hand := skeleton.get_bone_global_pose(right_hand).origin
			check(hand.z > 0.20 and hand.y > 0.75, label + " slap reaches forward at damage time")
		print("  ", clip, " length=", animation.length, " hip drift=", max_drift)
	model.free()
