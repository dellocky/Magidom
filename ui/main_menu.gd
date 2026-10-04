extends Control
## Magic RTS main menu: navy atmosphere, an arcane seal, and blue cursor light.

@onready var background: ColorRect = $Background
@onready var overlay: ColorRect = $Overlay
@onready var arcane_seal: ColorRect = $ArcaneSeal
@onready var content: MarginContainer = $Content
@onready var menu_column: VBoxContainer = $Content/MenuColumn
@onready var play_button: Button = $Content/MenuColumn/PlayButton
@onready var options_button: Button = $Content/MenuColumn/OptionsButton
@onready var quit_button: Button = $Content/MenuColumn/QuitButton
@onready var title: Label = $Content/MenuColumn/Title
@onready var subtitle: Label = $Content/MenuColumn/Subtitle
@onready var seal_caption: VBoxContainer = $SealCaption
@onready var navigation_hint: Label = $Footer/Row/NavigationHint

var _buttons: Array[Button] = []
var _button_tweens: Dictionary[Button, Tween] = {}
var _entrance_tween: Tween
var _mouse_smooth := Vector2(0.72, 0.48)


func _ready() -> void:
	_buttons = [play_button, options_button, quit_button]
	play_button.pressed.connect(_on_play_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	for button: Button in _buttons:
		button.mouse_entered.connect(_update_button.bind(button))
		button.mouse_exited.connect(_update_button.bind(button))
		button.focus_entered.connect(_update_button.bind(button))
		button.focus_exited.connect(_update_button.bind(button))

	_update_aspect()
	get_viewport().size_changed.connect(_update_aspect)
	play_button.grab_focus()
	menu_column.modulate.a = 0.0
	await get_tree().process_frame
	_play_entrance()


func _update_aspect() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var aspect := viewport_size.x / viewport_size.y
	background.material.set_shader_parameter("aspect", aspect)
	overlay.material.set_shader_parameter("aspect", aspect)

	var compact := viewport_size.y < 680.0
	var narrow := viewport_size.x < 900.0
	var menu_width := clampf(viewport_size.x * 0.35, 320.0, 460.0)
	menu_width = minf(menu_width, viewport_size.x * 0.85)
	content.offset_right = menu_width
	content.anchor_top = 0.16 if compact else 0.19
	content.anchor_bottom = 0.86
	menu_column.add_theme_constant_override("separation", 8 if compact else 12)
	title.add_theme_font_size_override("font_size", int(clampf(menu_width * 0.16, 32.0, 74.0)))
	subtitle.add_theme_font_size_override("font_size", 11 if menu_width < 380.0 else 14)
	$Content/MenuColumn/Spacer.custom_minimum_size.y = 8.0 if compact else 18.0
	for button: Button in _buttons:
		button.custom_minimum_size.y = 50.0 if compact else 60.0
		button.add_theme_font_size_override("font_size", 18 if compact else 21)

	# Keep the seal circular; in narrow windows it becomes quiet background art.
	var seal_size := minf(viewport_size.y * 0.86, viewport_size.x * 0.53)
	arcane_seal.offset_left = -seal_size * 0.5
	arcane_seal.offset_top = -seal_size * 0.5
	arcane_seal.offset_right = seal_size * 0.5
	arcane_seal.offset_bottom = seal_size * 0.5
	arcane_seal.modulate.a = 0.22 if narrow else 1.0
	seal_caption.visible = not narrow
	navigation_hint.visible = viewport_size.x >= 640.0


func _process(delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var mouse_target := get_viewport().get_mouse_position() / viewport_size
	mouse_target = mouse_target.clamp(Vector2.ZERO, Vector2.ONE)
	_mouse_smooth = _mouse_smooth.lerp(mouse_target, 1.0 - exp(-10.0 * delta))
	background.material.set_shader_parameter("mouse", _mouse_smooth)


func _play_entrance() -> void:
	if _entrance_tween:
		_entrance_tween.kill()
	_entrance_tween = create_tween()
	_entrance_tween.tween_property(menu_column, "modulate:a", 1.0, 0.65) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _update_button(button: Button) -> void:
	if _button_tweens.has(button):
		_button_tweens[button].kill()
	var active := button.has_focus() or button.is_hovered()
	var tint := Color.WHITE if active else Color(0.88, 0.93, 1.0)
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "modulate", tint, 0.14)
	_button_tweens[button] = tween


func _on_play_pressed() -> void:
	var game_scene := "res://scenes/testLevel.tscn"
	if ResourceLoader.exists(game_scene):
		get_tree().change_scene_to_file(game_scene)
	else:
		print("Play pressed — no game scene yet at ", game_scene)


func _on_options_pressed() -> void:
	print("Options menu not implemented yet")


func _on_quit_pressed() -> void:
	get_tree().quit()
