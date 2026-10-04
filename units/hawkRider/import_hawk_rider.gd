@tool
extends EditorScenePostImport


func _post_import(scene: Node) -> Object:
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player:
		for clip in player.get_animation_list():
			var animation := player.get_animation(clip)
			animation.loop_mode = Animation.LOOP_LINEAR if clip in ["idle", "move", "staff_twirl"] else Animation.LOOP_NONE
		player.autoplay = "idle"
	return scene
