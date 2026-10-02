extends Control
## Main menu for Magidom — a magic MOBA.
## Arcane dark theme: shader-driven aurora backdrop, cinematic frame overlay,
## shimmering divider, and smoothed hover/focus micro-interactions.

@onready var background: ColorRect = $Background
@onready var overlay: ColorRect = $Overlay
@onready var menu_column: VBoxContainer = $Content/MenuColumn
@onready var play_button: Button = $Content/MenuColumn/PlayButton
@onready var options_button: Button = $Content/MenuColumn/OptionsButton
@onready var quit_button: Button = $Content/MenuColumn/QuitButton
@onready var title: Label = $Content/MenuColumn/Title

var _buttons: Array[Button] = []


func _ready() -> void:
	_buttons = [play_button, options_button, quit_button]

	play_button.pressed.connect(_on_play_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	for b: Button in _buttons:
		b.mouse_entered.connect(_on_button_hover.bind(b, true))
		b.mouse_exited.connect(_on_button_hover.bind(b, false))
		b.focus_entered.connect(_on_button_focus.bind(b, true))
		b.focus_exited.connect(_on_button_focus.bind(b, false))

	_update_aspect()
	get_viewport().size_changed.connect(_update_aspect)

	play_button.grab_focus()

	# Wait one frame so layout has settled, then run the entrance animation.
	await get_tree().process_frame
	_play_entrance()


func _update_aspect() -> void:
	var size: Vector2 = get_viewport_rect().size
	if size.y <= 0.0:
		return
	var aspect := size.x / size.y
	background.material.set_shader_parameter("aspect", aspect)
	overlay.material.set_shader_parameter("aspect", aspect)


func _process(_delta: float) -> void:
	# Feed the cursor into the backdrop shader's halo.
	var vp := get_viewport()
	var mouse := vp.get_mouse_position() / vp.get_visible_rect().size
	background.material.set_shader_parameter("mouse", mouse)

	# Gentle breathing on the title.
	title.modulate.a = 0.9 + 0.1 * sin(Time.get_ticks_msec() / 1000.0 * 2.2)


func _play_entrance() -> void:
	menu_column.pivot_offset = menu_column.size * 0.5
	menu_column.modulate.a = 0.0
	menu_column.scale = Vector2(0.95, 0.95)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(menu_column, "modulate:a", 1.0, 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(menu_column, "scale", Vector2.ONE, 0.7) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_button_hover(button: Button, entered: bool) -> void:
	if entered:
		_scale_button(button, Vector2(1.04, 1.04))
	elif not button.has_focus():
		_scale_button(button, Vector2.ONE)


func _on_button_focus(button: Button, focused: bool) -> void:
	if focused:
		_scale_button(button, Vector2(1.05, 1.05))
	elif not button.is_hovered():
		_scale_button(button, Vector2.ONE)


func _scale_button(button: Button, target: Vector2) -> void:
	button.pivot_offset = button.size * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target, 0.16)


func _on_play_pressed() -> void:
	var game_scene := "res://levels/game.tscn"
	if ResourceLoader.exists(game_scene):
		get_tree().change_scene_to_file(game_scene)
	else:
		print("Play pressed — no game scene yet at ", game_scene)


func _on_options_pressed() -> void:
	print("Options menu not implemented yet")


func _on_quit_pressed() -> void:
	get_tree().quit()