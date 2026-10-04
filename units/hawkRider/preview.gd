extends Node3D

const CLIPS := ["idle", "move", "finger", "staff_twirl"]

@export_enum("idle", "move", "finger", "staff_twirl") var starting_clip: int = 0

@onready var player: AnimationPlayer = $HawkRider/Model/AnimationPlayer
@onready var caption: Label = $CanvasLayer/Caption


func _ready() -> void:
	$Camera3D.look_at(Vector3(0, 0.85, 0))
	play_clip(starting_clip)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			play_clip(event.keycode - KEY_1)
		elif event.keycode == KEY_SPACE:
			if player.is_playing():
				player.pause()
			else:
				player.play()


func play_clip(index: int) -> void:
	player.play(CLIPS[index], 0.2)
	caption.text = "Hawk Rider  |  %s\n1 Idle    2 Move    3 Finger    4 Staff twirl    Space Pause" % CLIPS[index]
