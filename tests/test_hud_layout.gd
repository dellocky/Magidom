extends SceneTree
## Headless: godot --headless --path . --script res://tests/test_hud_layout.gd

var _fail := 0

func _check(c: bool, msg: String) -> void:
	if not c:
		_fail += 1
		printerr("FAIL: ", msg)

func _init() -> void:
	var hud = load("res://ui/test_level_hud.tscn").instantiate()
	root.add_child(hud)
	for size in [Vector2i(640, 480), Vector2i(800, 600), Vector2i(1152, 648), Vector2i(1920, 1080)]:
		root.content_scale_size = size
		root.size = size
		for i in 40:
			await process_frame
			if hud.get_viewport().get_visible_rect().size == Vector2(size) and i > 6:
				break
		if size == Vector2i(640, 480):
			continue  # warm-up: headless root viewport ignores the first resize
		var vs: Vector2 = hud.get_viewport().get_visible_rect().size
		_check(vs == Vector2(size), "viewport size %s != %s" % [vs, size])
		var rects := {}
		for n in ["_header", "_left_panel", "_right_panel", "_bottom"]:
			var c: Control = hud.get(n)
			var r := c.get_global_rect()
			rects[n] = r
			_check(Rect2(Vector2.ZERO, vs).encloses(r), "%s inside %s: %s" % [n, size, r])
		var b: Rect2 = rects["_bottom"]
		_check(absf((b.position.x + b.size.x * 0.5) - vs.x * 0.5) < 2.0, "bottom centred %s %s" % [size, b])
		_check(b.size.y <= 165.0, "bottom height %s" % b.size.y)
		_check(absf(b.end.y - (vs.y - 8.0)) < 2.0, "bottom at bottom edge")
		_check(rects["_left_panel"].position.x == 8.0, "left x")
		_check(absf(rects["_right_panel"].end.x - (vs.x - 8.0)) < 2.0, "right x")
		for n in ["_header", "_left_panel", "_right_panel"]:
			_check(not rects[n].intersects(b), "%s overlaps bottom at %s" % [n, size])
		_check(not rects["_header"].intersects(rects["_left_panel"]), "header/left")
		_check(hud.pointer_over_ui(b.get_center()), "pointer blocked in bottom")
		_check(not hud.pointer_over_ui(Vector2(vs.x * 0.5, vs.y * 0.4)), "world open")
		hud.show_message("A very long message that should wrap rather than extend beyond the viewport width. ".repeat(4))
		for i in 3:
			await process_frame
		var t: Rect2 = hud._toast_panel.get_global_rect()
		_check(Rect2(Vector2.ZERO, vs).encloses(t), "toast inside %s: %s" % [size, t])
		print(size, " bottom=", b, " toast=", t)
	var unit_scene = load("res://units/hawkRider/hawk_rider_unit.tscn")
	var caster = unit_scene.instantiate()
	var ally = unit_scene.instantiate()
	for unit in [caster, ally]:
		unit.effects_enabled = false
		root.add_child(unit)
		unit.set_physics_process(false)
	hud.set_selection([caster])
	_check(not hud._bolt_btn.disabled and not hud._melter_btn.disabled, "ready spell buttons enabled")
	_check(caster.issue_cast_melter(caster.global_position), "start channel for HUD test")
	hud._refresh()
	_check(hud._melter_btn.disabled and hud._melter_btn.text.ends_with("30s"), "channel shows cooldown immediately")
	_check(hud._bolt_btn.disabled, "other spell unavailable during channel")
	caster.issue_stop()
	caster.bolt_cooldown_remaining = 60.0
	hud._refresh()
	_check(hud._bolt_btn.disabled and hud._bolt_btn.text.ends_with("60s"), "Bolt cooldown countdown")
	_check(hud._melter_btn.disabled and hud._melter_btn.text.ends_with("30s"), "Melter cooldown survives interruption in HUD")
	hud.set_selection([caster, ally])
	_check(not hud._bolt_btn.disabled and not hud._melter_btn.disabled, "ready selected ally enables spell buttons")
	_check(hud._bolt_btn.text.ends_with("RMB") and hud._melter_btn.text.ends_with("Q"), "ready group shows shortcuts")
	hud.set_selection([caster])
	caster.advance_simulation(30.0)
	hud._refresh()
	_check(hud._bolt_btn.disabled and hud._bolt_btn.text.ends_with("30s"), "Bolt countdown ticks")
	_check(not hud._melter_btn.disabled, "Melter button reenabled at expiry")
	caster.advance_simulation(30.0)
	hud._refresh()
	_check(not hud._bolt_btn.disabled, "Bolt button reenabled at expiry")
	hud.set_selection([])
	_check(hud._bolt_btn.disabled and hud._melter_btn.disabled, "no selection disables spells")
	caster.free()
	ally.free()
	print("hud layout failures: ", _fail)
	quit(1 if _fail > 0 else 0)
