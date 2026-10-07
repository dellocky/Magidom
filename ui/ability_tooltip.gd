extends PanelContainer
## Dota-2 style spell tooltip: a coloured name header, a column of stat rows, then
## a wrapped description and a dimmed flavour/lore paragraph. The HUD owns its
## position (it has no anchors of its own) and calls show_ability/show_global.

const WIDTH := 264.0
const ACCENT := Color(0.38, 0.82, 1.0)

var _content: VBoxContainer
var _rows: VBoxContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = WIDTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.11, 0.97)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.35, 0.52, 0.72, 0.95)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 10
	add_theme_stylebox_override("panel", sb)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 5)
	add_child(_content)


func show_ability(ability: Resource, accent: Color, sub: String) -> void:
	_reset()
	content_add(_make_name(str(ability.get("display_name")), accent, sub))
	_rows = _make_rows()
	content_add(_rows)
	if ability.get("damage") != null:
		_add_row("Damage", _num(ability.get("damage")))
	if ability.get("range_units") != null:
		_add_row("Cast range", _num(ability.get("range_units")))
	if ability.get("mana_cost") != null and float(ability.get("mana_cost")) > 0.0:
		_add_row("Mana", _num(ability.get("mana_cost")))
	if ability.get("cooldown") != null:
		_add_row("Cooldown", _secs(ability.get("cooldown")) + "s")
	if bool(ability.get("channel")):
		if ability.get("duration") != null:
			_add_row("Duration", _secs(ability.get("duration")) + "s")
		if ability.get("radius_units") != null:
			_add_row("Field radius", _num(ability.get("radius_units")))
		if ability.get("slow_fraction") != null:
			_add_row("Slow", _pct(ability.get("slow_fraction")))
	_add_article(str(ability.get("description")), str(ability.get("lore")))


func show_global(spell: Resource, accent: Color) -> void:
	_reset()
	content_add(_make_name(str(spell.get("display_name")), accent, "global"))
	_rows = _make_rows()
	content_add(_rows)
	if spell.get("mana_cost") != null:
		_add_row("Mana", _num(spell.get("mana_cost")))
	if spell.get("cooldown") != null:
		_add_row("Cooldown", _secs(spell.get("cooldown")) + "s")
	if spell.get("aoe_radius_units") != null:
		_add_row("Area", _num(spell.get("aoe_radius_units")))
	if spell.get("duration") != null:
		_add_row("Duration", _secs(spell.get("duration")) + "s")
	if spell.get("move_speed_bonus_fraction") != null:
		_add_row("Move speed", _signed_pct(spell.get("move_speed_bonus_fraction")))
	if spell.get("hp_drain_fraction_per_second") != null:
		_add_row("Health drain", "-" + _pct(spell.get("hp_drain_fraction_per_second")) + "/s")
	_add_article(str(spell.get("description")), str(spell.get("lore")))


# -------------------------------------------------------------------- helpers

func _reset() -> void:
	if _content != null:
		_content.visible = false
		_content.queue_free()
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 5)
	add_child(_content)
	_rows = null


func content_add(c: Control) -> void:
	_content.add_child(c)


func _make_name(text: String, accent: Color, sub: String) -> Control:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	var n := _make_label(text, 15, accent)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	if sub != "":
		var s := _make_label(sub, 11, Color(0.6, 0.7, 0.8))
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(s)
	return h


func _make_rows() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	return v


func _add_row(key: String, value: String) -> void:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	var k := _make_label(key, 12, Color(0.6, 0.7, 0.8))
	h.add_child(k)
	var v := _make_label(value, 12, Color(1, 1, 1))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	_rows.add_child(h)


func _add_article(description: String, lore: String) -> void:
	if description != "":
		content_add(_make_par(description, Color(0.85, 0.90, 0.95)))
	if lore != "":
		var sep := HSeparator.new()
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content_add(sep)
		content_add(_make_par(lore, Color(0.58, 0.72, 0.82)))


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _make_par(text: String, color: Color) -> Label:
	var l := _make_label(text, 12, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 22.0
	return l


func _num(v: Variant) -> String:
	return str(int(roundf(float(v))))


func _secs(v: Variant) -> String:
	var f := float(v)
	if f == floorf(f):
		return str(int(f))
	return "%.1f" % f


func _pct(v: Variant) -> String:
	return "%d%%" % int(roundf(float(v) * 100.0))


func _signed_pct(v: Variant) -> String:
	var f := float(v) * 100.0
	return "%+d%%" % int(roundf(f))