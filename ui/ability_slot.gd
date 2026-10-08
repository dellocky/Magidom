extends Button
## One square ability slot: glyph, hotkey, and a top-down cooldown overlay with
## seconds. Empty slots are inert (disabled, no hotkey). Text stays empty so the
## Button's own text never competes with the overlays.

const GLYPH := preload("res://ui/hud_glyph.gd")

var glyph: Control
var hotkey_label: Label
var cooldown_overlay: ColorRect
var cooldown_label: Label

var hotkey := ""
var empty_slot := false
var installed := true
var cooldown_remaining := 0.0
var cooldown_fraction := 0.0
var cooldown_text := ""
var accent := Color(0.38, 0.82, 1.0)


func _init() -> void:
	clip_contents = true
	glyph = GLYPH.new()
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 9)
	add_child(glyph)
	cooldown_overlay = ColorRect.new()
	cooldown_overlay.color = Color(0.0, 0.0, 0.0, 0.66)
	cooldown_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cooldown_overlay.visible = false
	add_child(cooldown_overlay)
	cooldown_label = _make_label(16)
	cooldown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cooldown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(cooldown_label)
	hotkey_label = _make_label(10)
	hotkey_label.position = Vector2(3, 0)
	hotkey_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	add_child(hotkey_label)
	resized.connect(_layout_overlay)


func setup(kind: String, key: String, accent_color: Color, is_empty: bool = false) -> void:
	empty_slot = is_empty
	hotkey = key
	accent = accent_color
	glyph.kind = "empty" if is_empty else kind
	glyph.color = Color(0.30, 0.38, 0.48, 0.7) if is_empty else accent_color
	hotkey_label.text = key
	if is_empty:
		disabled = true
		toggle_mode = false


## Swap the drawn glyph kind at runtime (e.g. "bolt" -> "whack" for the Martyr).
func set_glyph_kind(kind: String) -> void:
	glyph.kind = kind


func apply_state(is_installed: bool, ready: bool, remaining: float, total: float) -> void:
	if empty_slot:
		return
	installed = is_installed
	cooldown_remaining = maxf(remaining, 0.0) if is_installed else 0.0
	if cooldown_remaining > 0.0:
		cooldown_fraction = clampf(cooldown_remaining / total, 0.0, 1.0) if total > 0.0 else 1.0
		cooldown_text = str(ceili(cooldown_remaining))
	else:
		cooldown_fraction = 0.0
		cooldown_text = ""
	disabled = not (is_installed and ready)
	glyph.modulate = Color(1, 1, 1, 0.45 if disabled else 1.0)
	cooldown_overlay.visible = cooldown_fraction > 0.0
	cooldown_label.text = cooldown_text
	_layout_overlay()


func _layout_overlay() -> void:
	cooldown_overlay.position = Vector2.ZERO
	cooldown_overlay.size = Vector2(size.x, size.y * cooldown_fraction)


func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0.02, 0.05, 0.95))
	l.add_theme_constant_override("outline_size", 3)
	return l
