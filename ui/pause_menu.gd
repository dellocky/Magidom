extends CanvasLayer
## Escape menu. process_mode is ALWAYS so it stays alive — and can close itself —
## while the tree is paused. Offers Main Menu / Options and, when dev_options, a
## test-scene Dev Options block (faction select + infinite mana/money).

const THEME_PATH := "res://ui/main_menu_theme.tres"

## Show the Dev Options block. On for the test arena, off elsewhere.
@export var dev_options: bool = true

var _panel: PanelContainer
var _faction_opt: OptionButton
var _mana_toggle: CheckButton
var _money_toggle: CheckButton
var _options_note: Label
var _open := false
var _just_opened := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _build() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	if ResourceLoader.exists(THEME_PATH):
		root.theme = load(THEME_PATH)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.07, 0.13, 0.97)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.35, 0.52, 0.72, 0.9)
	sb.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(280, 0)
	_panel.add_child(v)

	var title := _label("PAUSED", 20, Color(0.38, 0.82, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(_sep())

	v.add_child(_button("Resume", close))
	v.add_child(_button("Main Menu", _to_main_menu))
	v.add_child(_button("Options", _toggle_options))
	_options_note = _label("No options yet.", 12, Color(0.6, 0.7, 0.8))
	_options_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_options_note.visible = false
	v.add_child(_options_note)

	if dev_options:
		v.add_child(_sep())
		var dev := _label("Dev options", 13, Color(0.95, 0.8, 0.35))
		v.add_child(dev)

		var frow := HBoxContainer.new()
		frow.add_theme_constant_override("separation", 10)
		frow.add_child(_label("Faction", 14, Color(0.8, 0.87, 0.94)))
		_faction_opt = OptionButton.new()
		_faction_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_faction_opt.item_selected.connect(_on_faction_selected)
		frow.add_child(_faction_opt)
		v.add_child(frow)

		_mana_toggle = CheckButton.new()
		_mana_toggle.text = "Infinite mana"
		_mana_toggle.toggled.connect(_on_mana_toggled)
		v.add_child(_mana_toggle)

		_money_toggle = CheckButton.new()
		_money_toggle.text = "Infinite money"
		_money_toggle.toggled.connect(_on_money_toggled)
		v.add_child(_money_toggle)


func open() -> void:
	_sync_dev()
	_open = true
	_just_opened = true
	visible = true
	get_tree().paused = true


func close() -> void:
	if not _open:
		return
	_open = false
	get_tree().paused = false
	visible = false


func is_open() -> bool:
	return _open


func _process(_delta: float) -> void:
	# Swallow the Esc that just opened the menu so it cannot also close it.
	_just_opened = false


func _unhandled_input(event: InputEvent) -> void:
	if not _open or _just_opened:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("ui_cancel"):
		close()


# -------------------------------------------------------------------- dev state

func _state() -> Node:
	return get_node_or_null("/root/GameState")


func _sync_dev() -> void:
	var gs := _state()
	if gs == null or not dev_options:
		return
	_faction_opt.clear()
	var idx := 0
	for f: Resource in gs.factions:
		_faction_opt.add_item(str(f.get("display_name")))
		if f == gs.faction:
			idx = _faction_opt.item_count - 1
	_faction_opt.select(idx)
	_mana_toggle.set_pressed_no_signal(bool(gs.infinite_mana))
	_money_toggle.set_pressed_no_signal(bool(gs.infinite_money))


func _on_faction_selected(i: int) -> void:
	var gs := _state()
	if gs == null or i < 0 or i >= gs.factions.size():
		return
	gs.set_faction(gs.factions[i].get("id"))


func _on_mana_toggled(pressed: bool) -> void:
	var gs := _state()
	if gs != null:
		gs.set_infinite_mana(pressed)


func _on_money_toggled(pressed: bool) -> void:
	var gs := _state()
	if gs != null:
		gs.set_infinite_money(pressed)


func _to_main_menu() -> void:
	_open = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _toggle_options() -> void:
	_options_note.visible = not _options_note.visible


# -------------------------------------------------------------------- helpers

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 15)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _sep() -> HSeparator:
	var s := HSeparator.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s