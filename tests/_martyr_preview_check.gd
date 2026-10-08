extends "res://units/hawkRider/preview.gd"

func _ready() -> void:
	super._ready()
	select_unit(1)
	await get_tree().process_frame
	for index in 4:
		play_clip(index)
		_player.advance(0.0)
		_player.seek(0.4 if index == 2 else 0.2, true)
		_player.pause()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "C:/Users/gavin/AppData/Local/Temp/martyr_%s.png" % _clips[index]
		get_viewport().get_texture().get_image().save_png(path)
		print("MARTYR_PREVIEW_CHECK ", _clips[index], " ", path)
	play_clip(3)
