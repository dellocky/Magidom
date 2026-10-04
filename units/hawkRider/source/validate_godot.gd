extends SceneTree


func _initialize() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var packed := load("res://units/hawkRider/hawk_rider.tscn") as PackedScene
	assert(packed != null, "Unit scene failed to load")
	var unit := packed.instantiate()
	root.add_child(unit)
	var player := unit.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(player != null, "No AnimationPlayer")
	var expected := {"idle": 2.4, "move": 1.6, "finger": 3.6, "staff_twirl": 4.8}
	var bones := 0
	for node in unit.find_children("*", "Skeleton3D", true, false):
		bones += node.get_bone_count()
	print("HAWK_RIDER skeleton bones=", bones, " clips=", player.get_animation_list())
	for clip in expected:
		assert(player.has_animation(clip), "Missing clip: " + clip)
		var anim := player.get_animation(clip)
		assert(absf(anim.length - expected[clip]) < 0.001, "Incorrect duration")
		assert(anim.loop_mode == (Animation.LOOP_NONE if clip == "finger" else Animation.LOOP_LINEAR), "Incorrect loop mode")
		var target_root := player.get_node(player.root_node)
		for track in range(anim.get_track_count()):
			var path := anim.track_get_path(track)
			assert(target_root.has_node(NodePath(path.get_concatenated_names())), "Broken track " + str(path))
		player.play(clip)
		player.advance(0.0)
		for sample in range(25):
			player.seek(anim.length * sample / 24.0, true)
		print("PASS ", clip, " seconds=", anim.length, " tracks=", anim.get_track_count(), " loop=", anim.loop_mode)
	print("HAWK_RIDER_VALIDATION_PASS")
	unit.queue_free()
	quit(0)
