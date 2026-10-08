extends Node3D
## Animation preview: pick a unit from the dropdown, then switch clips with the
## number keys (Space pauses). Model scenes and their clip lists live in UNITS.

const UNITS := [
	{
		"name": "Hawk Rider",
		"scene": "res://units/hawkRider/hawk_rider.tscn",
		"clips": ["idle", "move", "finger", "staff_twirl"],
	},
	{
		"name": "Martyr",
		"scene": "res://units/martyr/martyr.tscn",
		"clips": ["idle", "run", "slap", "sillyrun"],
	},
]

@export var starting_unit: int = 0

@onready var _caption: Label = $CanvasLayer/Caption

var _unit_index: int = 0
var _clips: Array = []
var _model: Node3D
var _player: AnimationPlayer
var _dropdown: OptionButton


func _ready() -> void:
	$Camera3D.look_at(Vector3(0, 0.85, 0))
	var starter := get_node_or_null("HawkRider")
	if starter != null:
		starter.queue_free()
	_build_controls()
	select_unit(clampi(starting_unit, 0, UNITS.size() - 1))


func _build_controls() -> void:
	_dropdown = OptionButton.new()
	_dropdown.focus_mode = Control.FOCUS_NONE
	for unit: Dictionary in UNITS:
		_dropdown.add_item(str(unit["name"]))
	_dropdown.position = Vector2(24, 100)
	_dropdown.custom_minimum_size = Vector2(188, 0)
	_dropdown.item_selected.connect(func(index: int) -> void: select_unit(index))
	var layer := $CanvasLayer
	layer.add_child(_dropdown)
	var hint := Label.new()
	hint.text = "1..9  pick clip      Space  pause"
	hint.position = Vector2(24, 132)
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.62, 0.72, 0.84))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hint)


func select_unit(index: int) -> void:
	_unit_index = clampi(index, 0, UNITS.size() - 1)
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = null
	_player = null
	_clips = []
	var unit: Dictionary = UNITS[_unit_index]
	var scene := load(str(unit["scene"])) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	_model.name = str(unit["name"]).replace(" ", "")
	_model.position = Vector3.ZERO
	add_child(_model)
	_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_clips = (unit["clips"] as Array).duplicate()
	if _dropdown != null:
		_dropdown.select(_unit_index)
	play_clip(0)


func play_clip(index: int) -> void:
	if _clips.is_empty():
		return
	index = clampi(index, 0, _clips.size() - 1)
	var clip: StringName = _clips[index]
	if _player != null and _player.has_animation(clip):
		_player.play(clip, 0.2)
	var keys := ""
	for i in _clips.size():
		keys += "%d %s    " % [i + 1, _clips[i]]
	_caption.text = "%s  |  %s\n%s   Space Pause" % [str(UNITS[_unit_index]["name"]), clip, keys]


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var index: int = event.keycode - int(KEY_1)
			if index < _clips.size():
				play_clip(index)
		elif event.keycode == KEY_SPACE:
			if _player != null:
				if _player.is_playing():
					_player.pause()
				else:
					_player.play()
