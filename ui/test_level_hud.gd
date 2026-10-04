extends CanvasLayer
## Test arena HUD: spawn panels with a shared Hawk Rider portrait, header with
## menu button, bottom selection/spell panel, projected unit bars and marquee.
## Built entirely in code; every real panel is MOUSE_FILTER_STOP while the
## full-screen root/overlay ignore the mouse (no click-through blocker).

signal spawn_requested(team: int)
signal melter_requested()
signal bolt_requested()
signal stop_requested()
signal menu_requested()

const THEME_PATH := "res://ui/main_menu_theme.tres"
const OVERLAY_SCRIPT := "res://ui/selection_overlay.gd"
const HAWK_SCENE := "res://units/hawkRider/hawk_rider.tscn"

const FRIENDLY := Color(0.38, 0.82, 1.0)
const ENEMY := Color(1.0, 0.47, 0.40)
const MANA := Color(0.50, 0.44, 1.0)
const PANEL_BG := Color(0.02, 0.05, 0.10, 0.90)
const PANEL_EDGE := Color(0.15, 0.29, 0.43, 0.95)
const TEXT := Color(0.80, 0.87, 0.94)
const TEXT_DIM := Color(0.55, 0.66, 0.78)

const STATE_NAMES := ["Idle", "Moving", "Chasing", "Lightning Bolt", "Base Melter", "Dead"]
const STATE_BOLT := 3
const STATE_CHANNEL := 4

var _root: Control
var _overlay: Control
var _selected: Array = []
var _targeting := ""
var _blockers: Array[Control] = []

var _header: PanelContainer
var _left_panel: PanelContainer
var _right_panel: PanelContainer
var _bottom: PanelContainer
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween

var _portrait_vp: SubViewport
var _portrait_rects: Array[TextureRect] = []
var _portrait_labels: Array[Label] = []

var _title: Label
var _subtitle: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _mana_bar: ProgressBar
var _mana_label: Label
var _stats_label: Label
var _cast_bar: ProgressBar
var _cast_label: Label
var _hint: Label
var _bolt_btn: Button
var _melter_btn: Button
var _stop_btn: Button
var _header_title: Label
var _header_sub: Label
var _layout_sig: Array = []


func _ready() -> void:
	layer = 10
	_build()
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout_deferred)
	_apply_layout_deferred()
	set_selection([])
	_start_portrait()


# ---------------------------------------------------------------- public API

func set_selection(units: Array) -> void:
	_selected = units.duplicate()
	_refresh()


func show_message(text: String) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_panel.visible = true
	_place_toast()
	await get_tree().process_frame
	_place_toast()
	_toast_panel.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func() -> void: _toast_panel.visible = false)


func set_targeting(mode: String) -> void:
	_targeting = mode
	_bolt_btn.set_pressed_no_signal(mode == "attack")
	_melter_btn.set_pressed_no_signal(mode == "melter")
	_refresh()


func set_marquee(rect: Rect2, active: bool) -> void:
	if _overlay == null:
		return
	_overlay.set("marquee_rect", rect)
	_overlay.set("marquee_active", active)


func pointer_over_ui(point: Vector2) -> bool:
	for c in _blockers:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(point):
			return true
	return false


# -------------------------------------------------------------------- build

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(THEME_PATH):
		_root.theme = load(THEME_PATH)
	add_child(_root)

	_overlay = Control.new()
	_overlay.name = "SelectionOverlay"
	if ResourceLoader.exists(OVERLAY_SCRIPT):
		_overlay.set_script(load(OVERLAY_SCRIPT))
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_overlay)

	_build_header()
	_build_spawn_panel(0)
	_build_spawn_panel(1)
	_build_bottom()
	_build_toast()


func _panel(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_EDGE
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.border_color = accent
	sb.shadow_color = Color(0.03, 0.2, 0.45, 0.18)
	sb.shadow_size = 6
	sb.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", sb)
	_root.add_child(p)
	_blockers.append(p)
	return p


func _label(text: String, size: int, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _box(bg: Color, border: Color, bw: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_content_margin_all(4)
	return sb


func _style_button(b: Button, accent: Color) -> void:
	b.add_theme_stylebox_override("normal", _box(Color(0.03, 0.08, 0.15, 0.92), PANEL_EDGE))
	b.add_theme_stylebox_override("hover", _box(Color(0.06, 0.17, 0.29, 0.97), accent.darkened(0.15)))
	b.add_theme_stylebox_override("pressed", _box(Color(0.07, 0.22, 0.36, 1.0), accent, 2))
	b.add_theme_stylebox_override("hover_pressed", _box(Color(0.08, 0.26, 0.40, 1.0), accent, 2))
	b.add_theme_stylebox_override("disabled", _box(Color(0.025, 0.05, 0.09, 0.7), Color(0.10, 0.17, 0.25, 0.8)))
	var focus := _box(Color(0, 0, 0, 0), accent.lightened(0.3))
	focus.draw_center = false
	b.add_theme_stylebox_override("focus", focus)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _build_header() -> void:
	_header = _panel(PANEL_EDGE.lightened(0.2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_header.add_child(row)
	_header_title = _label("TEST ARENA", 15, FRIENDLY)
	_header_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_header_title)
	_header_sub = _label("Hawk Rider sandbox", 12, TEXT_DIM)
	_header_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_header_sub)
	var menu := Button.new()
	menu.text = "Menu"
	menu.custom_minimum_size = Vector2(64, 28)
	menu.add_theme_font_size_override("font_size", 13)
	_style_button(menu, FRIENDLY)
	menu.pressed.connect(func() -> void: menu_requested.emit())
	row.add_child(menu)


func _build_spawn_panel(team: int) -> void:
	var col := ENEMY if team == 1 else FRIENDLY
	var panel := _panel(col)
	if team == 0:
		_left_panel = panel
	else:
		_right_panel = panel
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(88, 104)
	btn.tooltip_text = "Spawn %s Hawk Rider" % ("enemy" if team == 1 else "friendly")
	_style_button(btn, col)
	btn.pressed.connect(func() -> void: spawn_requested.emit(team))
	panel.add_child(btn)

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	v.add_theme_constant_override("separation", 0)
	btn.add_child(v)

	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(76, 76)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tr)
	_portrait_rects.append(tr)

	var name_l := _label("Hawk Rider", 11, TEXT)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var team_l := _label("+ Enemy" if team == 1 else "+ Friendly", 11, col)
	team_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(team_l)
	_portrait_labels.append(team_l)


func _meter(color: Color) -> Array:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	bar.custom_minimum_size = Vector2(60, 15)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _box(Color(0.04, 0.08, 0.14, 0.95), Color(0.12, 0.2, 0.3), 1))
	var fill := _box(color.darkened(0.15), color.lightened(0.1), 0)
	bar.add_theme_stylebox_override("fill", fill)
	var l := _label("", 11, Color(0.95, 0.98, 1.0))
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.02, 0.05, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	bar.add_child(l)
	return [bar, l]


func _spell_button(text: String, accent: Color, cb: Callable, toggle: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(104, 50)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 13)
	_style_button(b, accent)
	b.pressed.connect(cb)
	return b


func _build_bottom() -> void:
	_bottom = _panel(FRIENDLY)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	_bottom.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	# Left: info + stats
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	row.add_child(info)
	_title = _label("Nothing selected", 17, TEXT)
	_title.clip_text = true
	info.add_child(_title)
	_subtitle = _label("", 12, TEXT_DIM)
	_subtitle.clip_text = true
	info.add_child(_subtitle)
	var hp := _meter(FRIENDLY)
	_hp_bar = hp[0]
	_hp_label = hp[1]
	info.add_child(_hp_bar)
	var mn := _meter(MANA)
	_mana_bar = mn[0]
	_mana_label = mn[1]
	info.add_child(_mana_bar)
	_stats_label = _label("", 12, TEXT)
	_stats_label.clip_text = true
	info.add_child(_stats_label)

	row.add_child(VSeparator.new())

	# Right: spells
	var spells := VBoxContainer.new()
	spells.custom_minimum_size.x = 330
	spells.add_theme_constant_override("separation", 4)
	row.add_child(spells)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	spells.add_child(buttons)
	_bolt_btn = _spell_button("Lightning Bolt\nRMB", FRIENDLY, _on_bolt_pressed, true)
	_melter_btn = _spell_button("Base Melter\nQ", FRIENDLY, _on_melter_pressed, true)
	_stop_btn = _spell_button("Stop\nS", ENEMY, _on_stop_pressed, false)
	_bolt_btn.tooltip_text = "Lightning Bolt: right-click an enemy unit"
	_melter_btn.tooltip_text = "Base Melter: choose a ground target (Q)"
	_stop_btn.tooltip_text = "Stop movement and Base Melter (S)"
	buttons.add_child(_bolt_btn)
	buttons.add_child(_melter_btn)
	buttons.add_child(_stop_btn)
	var cast := _meter(Color(0.95, 0.8, 0.35))
	_cast_bar = cast[0]
	_cast_label = cast[1]
	spells.add_child(_cast_bar)
	_hint = _label("LMB select / drag   RMB move or attack   Q Melter   S Stop", 10, TEXT_DIM)
	_hint.clip_text = true
	spells.add_child(_hint)
	var cam_hint := _label("Camera: arrows / MMB pan   wheel zoom   F focus", 10, TEXT_DIM)
	cam_hint.clip_text = true
	spells.add_child(cam_hint)


func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _box(Color(0.05, 0.10, 0.18, 0.93), Color(0.95, 0.8, 0.35, 0.9))
	sb.set_content_margin_all(7)
	_toast_panel.add_theme_stylebox_override("panel", sb)
	_toast_label = _label("", 14, Color(1.0, 0.93, 0.7))
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_panel.add_child(_toast_label)
	_toast_panel.visible = false
	_root.add_child(_toast_panel)


# ------------------------------------------------------------------- layout

func _apply_layout_deferred() -> void:
	# Containers have not settled their minimum sizes on the first frame, so
	# lay out again after they have.
	_apply_layout()
	await get_tree().process_frame
	if is_inside_tree():
		_apply_layout()


## Explicit top-left placement from the viewport size and each panel's real
## combined minimum size (no anchor-preset guesswork).
func _place_panel(p: Control, x: float, y: float, width: float = -1.0) -> void:
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var min_size := p.get_combined_minimum_size()
	var w := width if width > 0.0 else min_size.x
	p.position = Vector2(x, y)
	p.size = Vector2(w, min_size.y)


func _place_panels() -> void:
	var vs := get_viewport().get_visible_rect().size
	var m := 8.0
	for p in [_header, _left_panel, _right_panel, _bottom]:
		(p as Control).reset_size()
	var hs := _header.get_combined_minimum_size()
	_place_panel(_header, (vs.x - hs.x) * 0.5, m)
	var ls := _left_panel.get_combined_minimum_size()
	_place_panel(_left_panel, m, (vs.y - ls.y) * 0.5)
	var rs := _right_panel.get_combined_minimum_size()
	_place_panel(_right_panel, vs.x - rs.x - m, (vs.y - rs.y) * 0.5)
	var bw := minf(vs.x - 2.0 * m, 880.0)
	var bh := _bottom.get_combined_minimum_size().y
	_place_panel(_bottom, (vs.x - bw) * 0.5, vs.y - bh - m, bw)
	_place_toast()


func _place_toast() -> void:
	var vs := get_viewport().get_visible_rect().size
	var w := minf(vs.x - 32.0, 460.0)
	_toast_label.custom_minimum_size.x = w - 16.0
	_toast_panel.reset_size()
	_place_panel(_toast_panel, (vs.x - w) * 0.5, 52.0, w)

func _apply_layout() -> void:
	if _root == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var compact := vs.y < 680.0 or vs.x < 900.0
	var portrait := 60 if compact else 76
	for tr in _portrait_rects:
		tr.custom_minimum_size = Vector2(portrait, portrait)
	for b in [_left_panel, _right_panel]:
		(b.get_child(0) as Control).custom_minimum_size = Vector2(80 if compact else 88, portrait + 28)
	_header_sub.visible = vs.x >= 640.0
	_place_panels()
	_overlay.set("bar_width", 46.0 if compact else 56.0)


# ---------------------------------------------------------------- portrait

func _start_portrait() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not ResourceLoader.exists(HAWK_SCENE):
		return
	var scene := load(HAWK_SCENE) as PackedScene
	if scene == null:
		return
	_portrait_vp = SubViewport.new()
	_portrait_vp.size = Vector2i(192, 192)
	_portrait_vp.own_world_3d = true
	_portrait_vp.transparent_bg = true
	_portrait_vp.msaa_3d = Viewport.MSAA_4X
	_portrait_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_portrait_vp)

	var model := scene.instantiate()
	_portrait_vp.add_child(model)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.83, 1.0)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_portrait_vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -150, 0)
	key.light_color = Color(1, 0.9, 0.78)
	key.light_energy = 1.8
	_portrait_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_color = Color(0.55, 0.7, 1.0)
	fill.light_energy = 0.65
	_portrait_vp.add_child(fill)

	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.current = true
	_portrait_vp.add_child(cam)
	cam.look_at_from_position(Vector3(-2.5, 1.85, -4.3), Vector3(0, 0.85, 0))

	var player: AnimationPlayer = null
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		player = found[0]
		if player.has_animation("idle"):
			player.play("idle")
			player.seek(0.9, true)
			player.pause()

	var tex := _portrait_vp.get_texture()
	for tr in _portrait_rects:
		tr.texture = tex

	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_portrait_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	# Static portrait: stop animation/processing of the model.
	if player != null:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	model.process_mode = Node.PROCESS_MODE_DISABLED


# ---------------------------------------------------------------- runtime

func _process(_delta: float) -> void:
	_refresh()
	# Re-place panels whenever the viewport or any panel's minimum size changes
	# (covers the first frames, before containers have settled).
	var sig := [get_viewport().get_visible_rect().size, _header.get_combined_minimum_size(),
		_left_panel.get_combined_minimum_size(), _bottom.get_combined_minimum_size()]
	if sig != _layout_sig:
		_layout_sig = sig
		_apply_layout()


func _alive(u: Variant) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	if u.has_method("is_alive"):
		return bool(u.call("is_alive"))
	return true


func _num(v: Variant) -> String:
	return str(int(roundf(float(v))))


func _refresh_spell_button(button: Button, units: Array, spell_key: String, spell_name: String, shortcut: String) -> void:
	var ready := false
	var remaining := INF
	for unit in units:
		ready = ready or bool(unit.call("can_cast_" + spell_key))
		remaining = minf(remaining, float(unit.get(spell_key + "_cooldown_remaining")))
	button.disabled = not ready
	var status := shortcut
	if not units.is_empty():
		if remaining > 0.0:
			status = "%ds" % ceili(remaining)
		elif not ready:
			status = "Unavailable"
	button.text = "%s\n%s" % [spell_name, status]


func _refresh() -> void:
	if _title == null:
		return
	var alive: Array = []
	for u in _selected:
		if _alive(u):
			alive.append(u)

	var has := not alive.is_empty()
	_refresh_spell_button(_bolt_btn, alive, "bolt", "Lightning Bolt", "RMB")
	_refresh_spell_button(_melter_btn, alive, "melter", "Base Melter", "Q")
	_stop_btn.disabled = not has

	if not has:
		_title.text = "Nothing selected"
		_title.add_theme_color_override("font_color", TEXT)
		_subtitle.text = "Click or drag a box to select a Hawk Rider."
		_hp_bar.value = 0.0
		_mana_bar.value = 0.0
		_hp_label.text = "Health"
		_mana_label.text = "Mana"
		_stats_label.text = "Spawn units with the side panels. Right-click to move."
		_cast_bar.value = 0.0
		_cast_label.text = ""
		return

	var lead = alive[0]
	var n := alive.size()
	var teams := {}
	var hp := 0.0
	var max_hp := 0.0
	var mn := 0.0
	var max_mn := 0.0
	var cast_unit = null
	for u in alive:
		teams[int(u.get("team"))] = true
		var st = u.get("stats")
		hp += float(u.get("health"))
		mn += float(u.get("mana"))
		if st != null:
			max_hp += float(st.get("max_health"))
			max_mn += float(st.get("max_mana"))
		var s := int(u.get("state"))
		if cast_unit == null and (s == STATE_BOLT or s == STATE_CHANNEL):
			cast_unit = u

	var team_name := "Mixed teams"
	var col := TEXT
	if teams.size() == 1:
		if teams.has(1):
			team_name = "Enemy"
			col = ENEMY
		else:
			team_name = "Friendly"
			col = FRIENDLY
	var uname := str(lead.get("unit_name"))
	if uname == "":
		uname = "Hawk Rider"
	_title.text = uname if n == 1 else "%s  x%d" % [uname, n]
	_title.add_theme_color_override("font_color", col)
	if n == 1:
		var si := clampi(int(lead.get("state")), 0, STATE_NAMES.size() - 1)
		_subtitle.text = "%s  |  %s" % [team_name, STATE_NAMES[si]]
	else:
		_subtitle.text = "%d selected  |  %s" % [n, team_name]

	var total := " (total)" if n > 1 else ""
	_hp_bar.max_value = maxf(max_hp, 1.0)
	_hp_bar.value = clampf(hp, 0.0, maxf(max_hp, 1.0))
	_hp_label.text = "Health%s  %s / %s" % [total, _num(ceilf(hp)), _num(max_hp)]
	_mana_bar.max_value = maxf(max_mn, 1.0)
	_mana_bar.value = clampf(mn, 0.0, maxf(max_mn, 1.0))
	_mana_label.text = "Mana%s  %s / %s" % [total, _num(mn), _num(max_mn)]
	var lst = lead.get("stats")
	if lst != null:
		_stats_label.text = "Move %s u/s   Damage %s   Armor %s" % [
			_num(lst.get("move_speed")), _num(lst.get("attack_damage")), _num(lst.get("armor"))]
	else:
		_stats_label.text = ""

	if cast_unit != null:
		var s2 := int(cast_unit.get("state"))
		var spell = cast_unit.get("bolt") if s2 == STATE_BOLT else cast_unit.get("melter")
		var dur := 0.0
		if spell != null:
			dur = float(spell.get("duration"))
		var el := float(cast_unit.get("cast_elapsed"))
		var nm := "Lightning Bolt" if s2 == STATE_BOLT else "Base Melter"
		_cast_bar.max_value = maxf(dur, 0.01)
		_cast_bar.value = clampf(el, 0.0, maxf(dur, 0.01))
		_cast_label.text = "%s  %.1f / %.1fs" % [nm, minf(el, dur), dur]
	else:
		_cast_bar.value = 0.0
		var hint := ""
		if _targeting == "melter":
			hint = "Click ground to place Base Melter (Esc cancels)"
		elif _targeting == "attack":
			hint = "Click an opposing unit (Esc cancels)"
		_cast_label.text = hint


func _on_bolt_pressed() -> void:
	bolt_requested.emit()
	_bolt_btn.set_pressed_no_signal(_targeting == "attack")


func _on_melter_pressed() -> void:
	melter_requested.emit()
	_melter_btn.set_pressed_no_signal(_targeting == "melter")


func _on_stop_pressed() -> void:
	stop_requested.emit()
