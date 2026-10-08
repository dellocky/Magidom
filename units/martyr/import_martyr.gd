@tool
extends EditorScenePostImport


func _post_import(scene: Node) -> Object:
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player:
		for clip in player.get_animation_list():
			var animation := player.get_animation(clip)
			_make_in_place(player, animation)
			animation.loop_mode = Animation.LOOP_LINEAR if clip in ["idle", "run", "sillyrun"] else Animation.LOOP_NONE
		player.autoplay = "idle"
	return scene


func _make_in_place(player: AnimationPlayer, animation: Animation) -> void:
	var animation_root := player.get_node(player.root_node)
	for track in range(animation.get_track_count() - 1, -1, -1):
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var path := animation.track_get_path(track)
		if path.get_subname_count() != 1:
			continue
		var skeleton := animation_root.get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D
		if skeleton == null:
			continue
		var bone_name := String(path.get_subname(0))
		var bone := skeleton.find_bone(bone_name)
		if bone < 0 or not bone_name.ends_with("Hips"):
			continue
		# Keep authored breathing/bounce, but reject the legacy export's root
		# motion (hundreds of metres). World travel belongs to the RTS unit.
		var rest := skeleton.get_bone_rest(bone).origin
		var valid := true
		for key in animation.track_get_key_count(track):
			var position: Vector3 = animation.track_get_key_value(track, key)
			var delta := position - rest
			if not position.is_finite() or absf(delta.x) > 0.08 or absf(delta.z) > 0.08 or absf(delta.y) > 0.10:
				valid = false
				break
		if not valid:
			push_warning("Martyr: discarded out-of-bounds hip motion in " + String(animation.resource_name))
			skeleton.set_bone_pose_position(bone, rest)
			animation.remove_track(track)
