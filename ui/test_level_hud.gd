extends CanvasLayer
## Test arena HUD. Static scene nodes (test_level_hud.tscn): Root, SelectionOverlay,
## HeroPanel, ItemSlots (instance of item_slots.tscn) and Minimap (placeholder
## Control a minimap script can be attached to). Panel contents, spawn panes,
## the faction global-spell bar and the hover tooltip are built at runtime. Real
## panels are MOUSE_FILTER_STOP and registered in pointer_over_ui(); the
## full-screen root/overlay ignore the mouse.
##
## Top centre: faction global-spell slot + animated mana pool (0..1000) + money.
## Bottom strip: portrait | damage/armor/move stats (hover/focus popup) |
## [Bolt][Melter][empty][empty] + Stop, health, mana, cast bar.  Items and the
## minimap are independent components.

signal spawn_requested(team: int)
signal melter_requested()
signal bolt_requested()
signal stop_requested()
signal global_spell_requested()

const THEME_PATH := "res://ui/main_menu_theme.tres"
const OVERLAY_SCRIPT := "res://ui/selection_overlay.gd"
const ITEM_SLOTS_SCENE := "res://ui/item_slots.tscn"
const HAWK_SCENE := "res://units/hawkRider/hawk_rider.tscn"
const SLOT_SCRIPT := preload("res://ui/ability_slot.gd")
const GLYPH_SCRIPT := preload("res://ui/hud_glyph.gd")
const TOOLTIP_SCRIPT := preload("res://ui/ability_tooltip.gd")
const Audio = preload("res://audio/synth_audio.gd")

const FRIENDLY := Color(0.38, 0.82, 1.0)
const ENEMY := Color(1.0, 0.47, 0.40)
const HEALTH := Color(0.27, 0.80, 0.36)
const MANA := Color(0.28, 0.52, 1.0)
const PANEL_BG := Color(0.02, 0.05, 0.10, 0.90)
const PANEL_EDGE := Color(0.15, 0.29, 0.43, 0.95)
const TEXT := Color(0.80, 0.87, 0.94)
const TEXT_DIM := Color(0.55, 0.66, 0.78)
const GLYPH_DAMAGE := Color(1.0, 0.62, 0.35)
const GLYPH_ARMOR := Color(0.62, 0.78, 1.0)
const GLYPH_MOVE := Color(0.55, 0.92, 0.55)
const GLYPH_BOLT := Color(1.0, 0.92, 0.45)
const GLYPH_MELTER := Color(0.78, 0.55, 1.0)
const GLYPH_MANA := Color(0.55, 0.78, 1.0)

const STATE_NAMES := ["Idle", "Moving", "Chasing", "Lightning Bolt", "Base Melter", "Dead"]
const STATE_BOLT := 3
const STATE_CHANNEL := 4
const MARGIN := 8.0

## Editor/runtime toggle for the six-slot item component. The ItemSlots node's own
## `visible` is respected: layout never forces it visible, only this toggle does.
@export var show_items: bool = true:
	set = set_show_items

## Vision service (Node with can_see_unit / can_see_point / controls / player_team).
## Assigning it (or calling set_vision_system) forwards it to the overlay and minimap.
var vision_system: Node = null:
	set = set_vision_system

var _root: Control
var _overlay: Control
var _items: Control
var _minimap: Control
var _selected: Array = []
var _targeting := ""
var _blockers: Array[Control] = []

var _left_panel: PanelContainer
var _right_panel: PanelContainer
var _bottom: PanelContainer  # HeroPanel
var _global_panel: PanelContainer
var _global_btn: Button
var _global_spell_label: Label
var _global_mana_bar: ColorRect
var _global_mana_mat: ShaderMaterial
var _global_mana_label: Label
var _money_label: Label
var _tooltip: PanelContainer
var _deny_player: AudioStreamPlayer
var _ally_spawn_btn: Button
var _ally_spawn_name: Label

var _portrait_vp: SubViewport
var _portrait_rects: Array[TextureRect] = []
var _portrait_labels: Array[Label] = []

var _title: Label
var _subtitle: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _mana_bar: ProgressBar
var _mana_label: Label
var _cast_bar: ProgressBar
var _cast_label: Label
var _lead_label: Label
var _stats_panel: PanelContainer
var _stat_values := {}
var _stat_glyphs: Array[Control] = []
var _stats_popup: PanelContainer
var _stats_popup_label: Label
var _stats_hover := false
var _stats_focus := false
var _bolt_btn: Button
var _melter_btn: Button
var _empty_slots: Array[Button] = []
var _slot_row: HBoxContainer
var _stop_btn: Button
var _bars: Array[ProgressBar] = []
var _layout_sig: Array = []
var _tier := 2


func _ready() -> void:
	layer = 10
	_collect_scene_nodes()
	_build()
	if not show_items and _items != null:
		_items.visible = false
	_propagate_vision()
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout_deferred)
	_apply_layout_deferred()
	set_selection([])
	_start_portrait()
	var gs := _state_node()
	if gs != null:
		gs.faction_changed.connect(_on_faction_changed)
	_update_ally_spawn()
	_refresh_global()


# ---------------------------------------------------------------- public API

func set_selection(units: Array) -> void:
	_selected = units.duplicate()
	_refresh()


func set_show_items(value: bool) -> void:
	show_items = value
	if _items != null and is_node_ready():
		_items.visible = value
		_apply_layout()


## Forward the vision service to the selection overlay and minimap (whichever expose
## a `vision_system` property) and filter selection display by player sight.
func set_vision_system(service: Node) -> void:
	vision_system = service
	_propagate_vision()


## Player-wide session state (faction, global mana, money) from the autoload.
func _state_node() -> Node:
	return get_node_or_null("/root/GameState")


## Play the synthesized "mop-meep" deny sound. Replaces every on-screen popup:
## an invalid order just chirps instead of flashing text.
func play_deny() -> void:
	if _deny_player == null or _deny_player.stream == null:
		return
	_deny_player.play()


func set_targeting(mode: String) -> void:
	_targeting = mode
	_bolt_btn.set_pressed_no_signal(mode == "attack")
	_melter_btn.set_pressed_no_signal(mode == "melter")
	if _global_btn != null:
		_global_btn.set_pressed_no_signal(mode == "global")
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


## Scene-node accessors for the parent level.
func get_minimap() -> Control:
	return _minimap


func get_item_slots() -> Control:
	return _items


func get_overlay() -> Control:
	return _overlay


func _propagate_vision() -> void:
	for c in [_overlay, _minimap]:
		if c != null and _has_property(c, "vision_system"):
			c.set("vision_system", vision_system)


func _has_property(obj: Object, prop: String) -> bool:
	for p in obj.get_property_list():
		if p["name"] == prop:
			return true
	return false


# -------------------------------------------------------------------- build

func _collect_scene_nodes() -> void:
	_root = get_node_or_null("Root") as Control
	if _root == null:
		_root = Control.new()
		_root.name = "Root"
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_root)
	if _root.theme == null and ResourceLoader.exists(THEME_PATH):
		_root.theme = load(THEME_PATH)
	_overlay = _root.get_node_or_null("SelectionOverlay") as Control
	if _overlay == null:
		_overlay = Control.new()
		_overlay.name = "SelectionOverlay"
		if ResourceLoader.exists(OVERLAY_SCRIPT):
			_overlay.set_script(load(OVERLAY_SCRIPT))
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_root.add_child(_overlay)
	_bottom = _root.get_node_or_null("HeroPanel") as PanelContainer
	if _bottom == null:
		_bottom = PanelContainer.new()
		_bottom.name = "HeroPanel"
		_root.add_child(_bottom)
	_items = _root.get_node_or_null("ItemSlots") as Control
	if _items == null and ResourceLoader.exists(ITEM_SLOTS_SCENE):
		_items = (load(ITEM_SLOTS_SCENE) as PackedScene).instantiate() as Control
		_items.name = "ItemSlots"
		_root.add_child(_items)
	_minimap = _root.get_node_or_null("Minimap") as Control
	if _minimap == null:
		_minimap = Control.new()
		_minimap.name = "Minimap"
		_minimap.custom_minimum_size = Vector2(176, 176)
		_minimap.mouse_filter = Control.MOUSE_FILTER_STOP
		_root.add_child(_minimap)


func _build() -> void:
	_style_panel(_bottom, FRIENDLY)
	if _items != null:
		_items.mouse_filter = Control.MOUSE_FILTER_STOP
		_blockers.append(_items)
	_minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	_blockers.append(_minimap)
	_build_global_bar()
	_build_spawn_panel(0)
	_build_spawn_panel(1)
	_build_hero()
	_build_stats_popup()
	_build_tooltip()
	_build_deny()


func _style_panel(p: Control, accent: Color) -> void:
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.border_color = accent
	sb.shadow_color = Color(0.03, 0.2, 0.45, 0.18)
	sb.shadow_size = 6
	sb.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", sb)
	if not _blockers.has(p):
		_blockers.append(p)


func _panel(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	_root.add_child(p)
	_style_panel(p, accent)
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


func _build_global_bar() -> void:
	_global_panel = _panel(PANEL_EDGE.lightened(0.25))
	_global_panel.name = "GlobalBar"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_global_panel.add_child(v)

	# Faction global spell hotbar (single slot; grows as factions gain spells).
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	_global_btn = _ability_slot("buff", "1", GLYPH_MANA, _on_global_pressed)
	_global_btn.name = "GlobalSpellSlot"
	_global_btn.tooltip_text = ""
	row.add_child(_global_btn)
	_global_spell_label = _label("No global spell", 12, TEXT_DIM)
	_global_spell_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_global_spell_label.clip_text = true
	_global_spell_label.custom_minimum_size.x = 140
	row.add_child(_global_spell_label)

	# Global mana pool (0..1000), drawn with an animated shader fill.
	_global_mana_bar = ColorRect.new()
	_global_mana_bar.name = "GlobalManaBar"
	_global_mana_bar.custom_minimum_size = Vector2(246, 20)
	_global_mana_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_global_mana_mat = ShaderMaterial.new()
	_global_mana_mat.shader = load("res://ui/shaders/mana_bar.gdshader")
	_global_mana_mat.set_shader_parameter("core_color", MANA)
	_global_mana_mat.set_shader_parameter("hi_color", Color(0.5, 0.92, 1.0))
	_global_mana_mat.set_shader_parameter("fill", 0.5)
	_global_mana_bar.material = _global_mana_mat
	v.add_child(_global_mana_bar)
	_global_mana_label = _label("Mana 0 / 1000", 11, Color(1, 1, 1))
	_global_mana_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_global_mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_global_mana_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_global_mana_label.add_theme_color_override("font_outline_color", Color(0, 0.02, 0.05, 0.95))
	_global_mana_label.add_theme_constant_override("outline_size", 3)
	_global_mana_bar.add_child(_global_mana_label)

	_money_label = _label("Money 0", 11, Color(1.0, 0.85, 0.5))
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_money_label)

	_global_btn.mouse_entered.connect(_show_global_tooltip)
	_global_btn.mouse_exited.connect(_hide_tooltip)


func _build_tooltip() -> void:
	if _tooltip != null:
		return
	_tooltip = TOOLTIP_SCRIPT.new()
	_tooltip.visible = false
	_tooltip.z_index = 100
	_root.add_child(_tooltip)


func _build_deny() -> void:
	_deny_player = AudioStreamPlayer.new()
	_deny_player.stream = Audio.stream("mopmeep")
	_deny_player.volume_db = -5.0
	add_child(_deny_player)


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

	if team == 0:
		_ally_spawn_btn = btn
		_ally_spawn_name = name_l


func _meter(color: Color) -> Array:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	bar.custom_minimum_size = Vector2(60, 15)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override("background", _box(Color(0.04, 0.08, 0.14, 0.95), Color(0.12, 0.2, 0.3), 1))
	var fill := _box(color.darkened(0.2), color.lightened(0.1), 0)
	bar.add_theme_stylebox_override("fill", fill)
	var l := _label("", 11, Color(1, 1, 1))
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.02, 0.05, 0.95))
	l.add_theme_constant_override("outline_size", 4)
	l.clip_text = true
	bar.add_child(l)
	_bars.append(bar)
	return [bar, l]


func _ability_slot(kind: String, key: String, accent: Color, cb: Callable) -> Button:
	var b: Button = SLOT_SCRIPT.new()
	b.setup(kind, key, accent)
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(48, 48)
	_style_button(b, accent)
	b.pressed.connect(cb)
	return b


func _build_hero() -> void:
	var row := HBoxContainer.new()
	row.name = "HeroRow"
	row.add_theme_constant_override("separation", 10)
	_bottom.add_child(row)

	# Portrait
	var frame := PanelContainer.new()
	frame.name = "PortraitFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := _box(Color(0.03, 0.07, 0.12, 0.95), PANEL_EDGE.lightened(0.15))
	fsb.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", fsb)
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(104, 104)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(tr)
	_portrait_rects.append(tr)
	row.add_child(frame)

	# Stats (damage / armor / effective move speed)
	var sc := VBoxContainer.new()
	sc.add_theme_constant_override("separation", 2)
	row.add_child(sc)
	_lead_label = _label("Stats", 10, TEXT_DIM)
	_lead_label.clip_text = true
	sc.add_child(_lead_label)
	_stats_panel = PanelContainer.new()
	_stats_panel.name = "StatsPanel"
	_stats_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_stats_panel.focus_mode = Control.FOCUS_ALL
	_stats_panel.add_theme_stylebox_override("panel", _box(Color(0.03, 0.07, 0.12, 0.95), PANEL_EDGE))
	_stats_panel.mouse_entered.connect(func() -> void: _set_stats_hover(true))
	_stats_panel.mouse_exited.connect(_on_stats_mouse_exited)
	_stats_panel.focus_entered.connect(func() -> void: _stats_focus = true)
	_stats_panel.focus_exited.connect(func() -> void: _stats_focus = false)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 4)
	_stats_panel.add_child(rows)
	_stat_row(rows, "damage", GLYPH_DAMAGE)
	_stat_row(rows, "armor", GLYPH_ARMOR)
	_stat_row(rows, "move", GLYPH_MOVE)
	sc.add_child(_stats_panel)

	# Abilities above health / mana
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	_title = _label("Nothing selected", 15, TEXT)
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_subtitle = _label("", 11, TEXT_DIM)
	_subtitle.clip_text = true
	head.add_child(_subtitle)

	_slot_row = HBoxContainer.new()
	_slot_row.name = "AbilityRow"
	_slot_row.add_theme_constant_override("separation", 4)
	col.add_child(_slot_row)
	_bolt_btn = _ability_slot("bolt", "RMB", GLYPH_BOLT, _on_bolt_pressed)
	_melter_btn = _ability_slot("melter", "Q", GLYPH_MELTER, _on_melter_pressed)
	_bolt_btn.name = "BoltSlot"
	_melter_btn.name = "MelterSlot"
	_bolt_btn.tooltip_text = ""
	_melter_btn.tooltip_text = ""
	_bolt_btn.mouse_entered.connect(_show_bolt_tooltip)
	_bolt_btn.mouse_exited.connect(_hide_tooltip)
	_melter_btn.mouse_entered.connect(_show_melter_tooltip)
	_melter_btn.mouse_exited.connect(_hide_tooltip)
	_slot_row.add_child(_bolt_btn)
	_slot_row.add_child(_melter_btn)
	for i in 2:
		var e: Button = SLOT_SCRIPT.new()
		e.setup("empty", "", TEXT_DIM, true)
		e.name = "EmptySlot%d" % (i + 1)
		e.custom_minimum_size = Vector2(48, 48)
		e.tooltip_text = "Empty ability slot"
		_style_button(e, TEXT_DIM)
		_slot_row.add_child(e)
		_empty_slots.append(e)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(6, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_row.add_child(gap)
	_stop_btn = Button.new()
	_stop_btn.name = "StopButton"
	_stop_btn.text = "Stop\nS"
	_stop_btn.clip_text = true
	_stop_btn.custom_minimum_size = Vector2(46, 48)
	_stop_btn.add_theme_font_size_override("font_size", 11)
	_stop_btn.tooltip_text = "Stop movement and Base Melter (S)"
	_style_button(_stop_btn, ENEMY)
	_stop_btn.pressed.connect(_on_stop_pressed)
	_slot_row.add_child(_stop_btn)

	var hp := _meter(HEALTH)
	_hp_bar = hp[0]
	_hp_label = hp[1]
	col.add_child(_hp_bar)
	var mn := _meter(MANA)
	_mana_bar = mn[0]
	_mana_label = mn[1]
	col.add_child(_mana_bar)
	var cast := _meter(Color(0.95, 0.8, 0.35))
	_cast_bar = cast[0]
	_cast_label = cast[1]
	_cast_bar.custom_minimum_size.y = 12
	_cast_label.add_theme_font_size_override("font_size", 10)
	col.add_child(_cast_bar)


func _stat_row(parent: Control, key: String, color: Color) -> void:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	var g: Control = GLYPH_SCRIPT.new()
	g.kind = key
	g.color = color
	g.custom_minimum_size = Vector2(20, 20)
	h.add_child(g)
	_stat_glyphs.append(g)
	var v := _label("-", 15, Color(1, 1, 1))
	v.custom_minimum_size.x = 36
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(v)
	parent.add_child(h)
	_stat_values[key] = v


func _build_stats_popup() -> void:
	_stats_popup = PanelContainer.new()
	_stats_popup.name = "StatsPopup"
	_stats_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _box(Color(0.02, 0.05, 0.10, 0.97), FRIENDLY.darkened(0.2))
	sb.set_content_margin_all(8)
	_stats_popup.add_theme_stylebox_override("panel", sb)
	_stats_popup_label = _label("", 12, TEXT)
	_stats_popup.add_child(_stats_popup_label)
	_stats_popup.visible = false
	_root.add_child(_stats_popup)
	_blockers.append(_stats_popup)


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


func _minimap_side(vs: Vector2) -> float:
	var side := 128.0 if _tier == 0 else clampf(vs.y * 0.27, 160.0, 190.0)
	return maxf(side, _minimap.custom_minimum_size.x)


func _place_panels() -> void:
	var vs := get_viewport().get_visible_rect().size
	var m := MARGIN
	var panels: Array = [_global_panel, _left_panel, _right_panel, _bottom]
	if _items != null:
		panels.append(_items)
	for p in panels:
		(p as Control).reset_size()
	var gs := _global_panel.get_combined_minimum_size()
	_place_panel(_global_panel, (vs.x - gs.x) * 0.5, m)
	var ls := _left_panel.get_combined_minimum_size()
	_place_panel(_left_panel, m, (vs.y - ls.y) * 0.5)
	var rs := _right_panel.get_combined_minimum_size()
	_place_panel(_right_panel, vs.x - rs.x - m, (vs.y - rs.y) * 0.5)

	# Minimap reserves the bottom-right corner independently of the hero strip.
	var side := _minimap_side(vs)
	_minimap.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_minimap.position = Vector2(vs.x - side - m, vs.y - side - m)
	_minimap.size = Vector2(side, side)

	# Hero panel (+ items when shown) centred, but kept left of the minimap.
	var bs := _bottom.get_combined_minimum_size()
	var show_it := _items != null and _items.visible
	var isz := _items.get_combined_minimum_size() if show_it else Vector2.ZERO
	var gap := 8.0 if show_it else 0.0
	var total := bs.x + gap + isz.x
	var x0 := (vs.x - total) * 0.5
	x0 = minf(x0, vs.x - side - 2.0 * m - total)
	x0 = maxf(x0, m)
	_place_panel(_bottom, x0, vs.y - bs.y - m)
	if show_it:
		_place_panel(_items, x0 + bs.x + gap, vs.y - isz.y - m)
	_update_stats_popup()


func _apply_layout() -> void:
	if _root == null or _bottom == null or _hp_bar == null:
		return
	var vs := get_viewport().get_visible_rect().size
	_tier = 0 if (vs.x < 720.0 or vs.y < 520.0) else (1 if (vs.x < 1000.0 or vs.y < 600.0) else 2)
	var portrait: float = [64.0, 84.0, 104.0][_tier]
	var slot: float = [34.0, 42.0, 48.0][_tier]
	var item_slot: float = [24.0, 34.0, 40.0][_tier]
	var bar_h: float = [12.0, 14.0, 16.0][_tier]
	var spawn_portrait := 60 if _tier < 2 else 76
	for tr in _portrait_rects:
		tr.custom_minimum_size = Vector2(spawn_portrait, spawn_portrait)
	(_bottom.find_child("PortraitFrame", true, false).get_child(0) as Control).custom_minimum_size = Vector2(portrait, portrait)
	for b in [_left_panel, _right_panel]:
		(b.get_child(0) as Control).custom_minimum_size = Vector2(80 if _tier < 2 else 88, spawn_portrait + 28)
	for b in [_bolt_btn, _melter_btn] + _empty_slots:
		(b as Control).custom_minimum_size = Vector2(slot, slot)
	if _global_btn is Control:
		_global_btn.custom_minimum_size = Vector2(slot, slot)
	_stop_btn.custom_minimum_size = Vector2(slot - 2.0 if _tier == 0 else 46.0, slot)
	for bar in _bars:
		bar.custom_minimum_size.y = bar_h if bar != _cast_bar else maxf(bar_h - 4.0, 10.0)
	(_stat_values["damage"] as Control).custom_minimum_size.x = 30 if _tier == 0 else 36
	if _items != null:
		for s in _items.find_children("Slot*", "Panel", true, false):
			(s as Control).custom_minimum_size = Vector2(item_slot, item_slot)
	_place_panels()
	_overlay.set("bar_width", 46.0 if _tier < 2 else 56.0)


func _process(_delta: float) -> void:
	_refresh_global()
	_refresh()
	# Re-place panels whenever the viewport or any panel's minimum size changes
	# (covers the first frames, before containers have settled).
	var sig := [get_viewport().get_visible_rect().size, _global_panel.get_combined_minimum_size(),
		_left_panel.get_combined_minimum_size(), _bottom.get_combined_minimum_size(),
		_items != null and _items.visible]
	if sig != _layout_sig:
		_layout_sig = sig
		_apply_layout()


# ------------------------------------------------------------- stats popup

func _set_stats_hover(on: bool) -> void:
	_stats_hover = on


func _on_stats_mouse_exited() -> void:
	_stats_hover = false
	# A mouse click focuses the panel; drop that focus when the pointer leaves so
	# the popup does not stay open. Keyboard focus (Tab) is unaffected.
	if _stats_panel.has_focus():
		_stats_panel.release_focus()


func is_stats_popup_open() -> bool:
	return _stats_popup != null and _stats_popup.visible


func _update_stats_popup() -> void:
	if _stats_popup == null:
		return
	var open := (_stats_hover or _stats_focus) and _stats_panel.is_visible_in_tree()
	_stats_popup.visible = open
	if not open:
		return
	_stats_popup_label.text = _stats_popup_text()
	_stats_popup.reset_size()
	var vs := get_viewport().get_visible_rect().size
	var ps := _stats_popup.get_combined_minimum_size()
	var anchor := _stats_panel.get_global_rect()
	var pos := Vector2(anchor.position.x, anchor.position.y - ps.y - 6.0)
	if pos.y < 4.0:
		pos.y = minf(anchor.end.y + 6.0, vs.y - ps.y - 4.0)
	pos.x = clampf(pos.x, 4.0, maxf(vs.x - ps.x - 4.0, 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(vs.y - ps.y - 4.0, 4.0))
	_stats_popup.position = pos
	_stats_popup.size = ps


func _effective_move(unit: Object) -> float:
	var st = unit.get("stats")
	var base := float(st.get("move_speed")) if st != null else 0.0
	if unit.has_method("get_effective_move_speed"):
		return float(unit.call("get_effective_move_speed"))
	return base


func _stats_popup_text() -> String:
	var lead = _lead_unit()
	if lead == null:
		return "No unit selected"
	var st = lead.get("stats")
	if st == null:
		return "No stats available"
	var lines: Array[String] = []
	var n := _display_units().size()
	lines.append("%s%s" % [str(st.get("display_name")), "  (lead of %d selected)" % n if n > 1 else ""])
	lines.append("Damage: %s    Armor: %s" % [_num(st.get("attack_damage")), _num(st.get("armor"))])
	var base := float(st.get("move_speed"))
	var eff := _effective_move(lead)
	var slow := 0.0 if base <= 0.0 else clampf(1.0 - eff / base, 0.0, 1.0)
	lines.append("Move speed: %s base, %s effective" % [_num(base), _num(eff)])
	lines.append("Slow: %d%%" % int(roundf(slow * 100.0)))
	var vision = st.get("vision_range")
	if vision != null:
		lines.append("Vision: %s units (%.0f m)" % [_num(vision), float(vision) / 20.0])
	else:
		lines.append("Vision: n/a")
	lines.append("Health max: %s    Mana max: %s" % [_num(st.get("max_health")), _num(st.get("max_mana"))])
	var bolt = lead.get("bolt")
	if bolt != null:
		lines.append("Bolt: range %s, mana %s, cooldown %ss, damage %s" % [
			_num(bolt.get("range_units")), _num(bolt.get("mana_cost")), _num(bolt.get("cooldown")), _num(bolt.get("damage"))])
	else:
		lines.append("Bolt: not installed")
	var melter = lead.get("melter")
	if melter != null:
		var r0 := float(melter.get("radius_units"))
		var r1 := r0
		if melter.has_method("radius_at"):
			r1 = float(melter.call("radius_at", float(melter.get("duration"))))
		if lead.has_method("effective_melter_radius_units"):
			r0 = float(lead.call("effective_melter_radius_units", 0.0))
			r1 = float(lead.call("effective_melter_radius_units", float(melter.get("duration"))))
		lines.append("Melter: range %s, mana %s, cooldown %ss, radius %s -> %s" % [
			_num(melter.get("range_units")), _num(melter.get("mana_cost")), _num(melter.get("cooldown")), _num(r0), _num(r1)])
	else:
		lines.append("Melter: not installed")
	return "\n".join(lines)


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

func _alive(u: Variant) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	if u.has_method("is_alive"):
		return bool(u.call("is_alive"))
	return true


## Living selected units the player may currently see (fog-safe display set).
func _display_units() -> Array:
	var out: Array = []
	for u in _selected:
		if not _alive(u):
			continue
		if vision_system != null and is_instance_valid(vision_system) and vision_system.has_method("can_see_unit"):
			var pt = vision_system.get("player_team")
			if not bool(vision_system.call("can_see_unit", int(pt) if pt != null else 0, u)):
				continue
		out.append(u)
	return out


func _lead_unit() -> Variant:
	var d := _display_units()
	return d[0] if not d.is_empty() else null


func _num(v: Variant) -> String:
	return str(int(roundf(float(v))))


## Human-readable name for the cast in progress, falling back to the fixed table.
func _state_name(unit: Variant) -> String:
	if unit == null:
		return ""
	var s := int(unit.get("state"))
	if s == STATE_BOLT:
		var b = unit.get("bolt")
		if b != null:
			return str(b.get("display_name"))
	elif s == STATE_CHANNEL:
		var m = unit.get("melter")
		if m != null:
			return str(m.get("display_name"))
	return STATE_NAMES[clampi(s, 0, STATE_NAMES.size() - 1)]


## Pick the glyph kind for an ability slot from the lead unit's ability (falls back
## to the slot's default kind when the ability declares none).
func _update_slot_glyph(slot: Button, units: Array, key: String, fallback: String) -> void:
	var kind := fallback
	for unit in units:
		var ab = unit.get(key)
		if ab == null:
			continue
		var gv = ab.get("glyph")
		if gv != null and str(gv) != "":
			kind = str(gv)
			break
	slot.call("set_glyph_kind", kind)


func _refresh_slot(slot: Button, units: Array, key: String) -> void:
	var installed := 0
	var ready := false
	var remaining := INF
	var total := 0.0
	for unit in units:
		var ab = unit.get(key)
		if ab == null:
			continue
		installed += 1
		if unit.has_method("can_cast_" + key):
			ready = ready or bool(unit.call("can_cast_" + key))
		remaining = minf(remaining, float(unit.get(key + "_cooldown_remaining")))
		total = maxf(total, float(ab.get("cooldown")))
	slot.call("apply_state", installed > 0, ready, 0.0 if is_inf(remaining) else remaining, total)


func _refresh() -> void:
	if _title == null:
		return
	var alive := _display_units()

	var has := not alive.is_empty()
	_refresh_slot(_bolt_btn, alive, "bolt")
	_refresh_slot(_melter_btn, alive, "melter")
	_stop_btn.disabled = not has
	_update_stats_popup()

	if not has:
		_title.text = "Nothing selected"
		_title.add_theme_color_override("font_color", TEXT)
		_subtitle.text = ""
		_lead_label.text = "Stats"
		_hp_bar.value = 0.0
		_mana_bar.value = 0.0
		_hp_label.text = "Health"
		_mana_label.text = "Mana"
		for k in _stat_values:
			(_stat_values[k] as Label).text = "-"
			(_stat_values[k] as Label).remove_theme_color_override("font_color")
		_cast_bar.value = 0.0
		_cast_label.text = "Click or drag to select a Hawk Rider"
		return

	var lead = alive[0]
	_update_slot_glyph(_bolt_btn, alive, "bolt", "bolt")
	_update_slot_glyph(_melter_btn, alive, "melter", "melter")
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
		_subtitle.text = "%s | %s" % [team_name, _state_name(lead)]
	else:
		_subtitle.text = "%d selected | %s" % [n, team_name]

	var total := " (total)" if n > 1 else ""
	_hp_bar.max_value = maxf(max_hp, 1.0)
	_hp_bar.value = clampf(hp, 0.0, maxf(max_hp, 1.0))
	_hp_label.text = "Health%s  %s / %s" % [total, _num(ceilf(hp)), _num(max_hp)]
	_mana_bar.max_value = maxf(max_mn, 1.0)
	_mana_bar.value = clampf(mn, 0.0, maxf(max_mn, 1.0))
	_mana_label.text = "Mana%s  %s / %s" % [total, _num(mn), _num(max_mn)]

	var lst = lead.get("stats")
	_lead_label.text = "Lead unit" if n > 1 else "Stats"
	if lst != null:
		(_stat_values["damage"] as Label).text = _num(lst.get("attack_damage"))
		(_stat_values["armor"] as Label).text = _num(lst.get("armor"))
		var eff := _effective_move(lead)
		var mv := _stat_values["move"] as Label
		mv.text = _num(eff)
		if eff < float(lst.get("move_speed")) - 0.01:
			mv.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
		else:
			mv.remove_theme_color_override("font_color")
	else:
		for k in _stat_values:
			(_stat_values[k] as Label).text = "-"

	if cast_unit != null:
		var s2 := int(cast_unit.get("state"))
		var spell = cast_unit.get("bolt") if s2 == STATE_BOLT else cast_unit.get("melter")
		var dur := 0.0
		if spell != null:
			dur = float(spell.get("duration"))
		var el := float(cast_unit.get("cast_elapsed"))
		var nm := str(spell.get("display_name")) if spell != null else ("Lightning Bolt" if s2 == STATE_BOLT else "Base Melter")
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


# ------------------------------------------------------------ global spell bar

func _on_global_pressed() -> void:
	global_spell_requested.emit()
	_global_btn.set_pressed_no_signal(_targeting == "global")


func _set_mana_fill(f: float) -> void:
	if _global_mana_mat != null:
		_global_mana_mat.set_shader_parameter("fill", f)


func _format_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return "-" + out if n < 0 else out


## Sync the global spell slot, mana pool and money readout to the GameState
## autoload. Called every frame (cheap) so dev toggles and cast cooldowns stay live.
func _refresh_global() -> void:
	if _global_btn == null:
		return
	var gs := _state_node()
	if gs == null:
		_global_btn.apply_state(false, false, 0.0, 0.0)
		_global_spell_label.text = "No global spell"
		_set_mana_fill(0.0)
		_global_mana_label.text = "Mana 0 / 1,000"
		_money_label.text = "Money 0"
		return
	var spell: Resource = gs.current_global_spell()
	if spell == null:
		_global_btn.apply_state(false, false, 0.0, 0.0)
		_global_spell_label.text = "No global spell"
	else:
		_global_btn.apply_state(true, bool(gs.can_cast_global()), float(gs.global_cooldown_remaining), float(spell.get("cooldown")))
		_global_spell_label.text = "%s  (%s)" % [str(spell.get("display_name")), str(spell.get("key"))]
	var mx := maxf(float(gs.max_mana), 1.0)
	_set_mana_fill(clampf(float(gs.mana) / mx, 0.0, 1.0))
	_global_mana_label.text = "Mana %s / %s" % [
		"∞" if gs.infinite_mana else _format_int(int(roundf(gs.mana))),
		_format_int(int(mx))]
	_money_label.text = "Money %s" % ("∞" if gs.infinite_money else _format_int(int(gs.money)))


func _on_faction_changed(_faction: Resource) -> void:
	_update_ally_spawn()
	_refresh_global()


## Refresh the team-0 spawn button against the selected faction's unit_scene.
func _update_ally_spawn() -> void:
	if _ally_spawn_btn == null:
		return
	var gs := _state_node()
	if gs == null or gs.faction == null:
		_ally_spawn_btn.disabled = true
		_ally_spawn_name.text = "No allied unit"
		_ally_spawn_btn.tooltip_text = "No faction selected"
		return
	var faction: Resource = gs.faction
	var scene: PackedScene = faction.get("unit_scene")
	if scene == null:
		_ally_spawn_btn.disabled = true
		_ally_spawn_name.text = "No allied unit"
		_ally_spawn_btn.tooltip_text = "No allied unit for %s yet" % str(faction.get("display_name"))
		return
	_ally_spawn_btn.disabled = false
	var n := str(faction.get("unit_display_name"))
	if n == "":
		n = "Allied unit"
	_ally_spawn_name.text = n
	_ally_spawn_btn.tooltip_text = "Spawn friendly %s" % n


# ------------------------------------------------------------------ tooltips

func _show_bolt_tooltip() -> void:
	var lead = _lead_unit()
	if lead == null:
		return
	var ab = lead.get("bolt")
	if ab != null:
		_tooltip.show_ability(ab, GLYPH_BOLT, " (RMB on enemy)")
		_position_tooltip(_bolt_btn)


func _show_melter_tooltip() -> void:
	var lead = _lead_unit()
	if lead == null:
		return
	var ab = lead.get("melter")
	if ab != null:
		var sub := " (Q, self-cast)" if bool(ab.get("self_cast")) else " (Q, ground target)"
		_tooltip.show_ability(ab, GLYPH_MELTER, sub)
		_position_tooltip(_melter_btn)


func _show_global_tooltip() -> void:
	var gs := _state_node()
	if gs == null:
		return
	var spell: Resource = gs.current_global_spell()
	if spell == null:
		return
	_tooltip.show_global(spell, GLYPH_MANA)
	_position_tooltip(_global_btn)


func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false


func _position_tooltip(around: Control) -> void:
	if _tooltip == null:
		return
	_tooltip.reset_size()
	var ts := _tooltip.get_combined_minimum_size()
	var r := around.get_global_rect()
	var vs := get_viewport().get_visible_rect().size
	var gap := 8.0
	var pos := Vector2(r.end.x + gap, r.position.y + (r.size.y - ts.y) * 0.5)
	if pos.x + ts.x > vs.x - 6.0:
		pos.x = r.position.x - gap - ts.x
	pos.x = clampf(pos.x, 6.0, maxf(vs.x - ts.x - 6.0, 6.0))
	pos.y = clampf(pos.y, 6.0, maxf(vs.y - ts.y - 6.0, 6.0))
	_tooltip.position = pos
	_tooltip.size = ts
	_tooltip.visible = true
