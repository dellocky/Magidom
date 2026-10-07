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
		var screen := Rect2(Vector2.ZERO, vs)
		var rects := {}
		var nodes := {
			"header": hud._header, "left": hud._left_panel, "right": hud._right_panel,
			"hero": hud._bottom, "items": hud.get_item_slots(), "minimap": hud.get_minimap()}
		for n in nodes:
			var r: Rect2 = (nodes[n] as Control).get_global_rect()
			rects[n] = r
			_check(screen.encloses(r), "%s inside %s: %s" % [n, size, r])
		# Named serialized nodes.
		for p in ["Root", "Root/HeroPanel", "Root/ItemSlots", "Root/Minimap", "Root/SelectionOverlay"]:
			_check(hud.get_node_or_null(p) != null, "scene node " + p)
		var hero: Rect2 = rects["hero"]
		var mini: Rect2 = rects["minimap"]
		_check(mini.size.x >= 160.0 and mini.size.x == mini.size.y, "minimap square >=160: %s" % mini.size)
		_check(absf(mini.end.x - (vs.x - 8.0)) < 2.0 and absf(mini.end.y - (vs.y - 8.0)) < 2.0, "minimap bottom-right")
		_check(absf(hero.end.y - (vs.y - 8.0)) < 2.0, "hero at bottom edge")
		_check(hero.size.y <= 175.0, "hero height %s" % hero.size.y)
		_check(not hero.intersects(rects["items"]) and not hero.intersects(mini) and not rects["items"].intersects(mini), "hero/items/minimap disjoint at %s" % size)
		for n in ["header", "left", "right"]:
			for o in ["hero", "items", "minimap"]:
				_check(not rects[n].intersects(rects[o]), "%s overlaps %s at %s" % [n, o, size])
		_check(not rects["header"].intersects(rects["left"]), "header/left")
		_check(rects["left"].position.x == 8.0, "left x")
		_check(absf(rects["right"].end.x - (vs.x - 8.0)) < 2.0, "right x")

		# Hero internals: portrait | stats | abilities above bars; Stop outside slots.
		var portrait: Rect2 = hud._portrait_rects[2].get_global_rect()
		var stats: Rect2 = hud._stats_panel.get_global_rect()
		var slots: Array = [hud._bolt_btn, hud._melter_btn, hud._empty_slots[0], hud._empty_slots[1]]
		_check(portrait.end.x <= stats.position.x + 1.0, "portrait left of stats")
		_check(hero.encloses(portrait) and hero.encloses(stats), "portrait/stats inside hero")
		var first: Rect2 = slots[0].get_global_rect()
		_check(stats.end.x <= first.position.x + 1.0, "stats left of slots")
		var prev_end := -1.0
		for s in slots:
			var sr: Rect2 = s.get_global_rect()
			_check(absf(sr.size.x - first.size.x) < 0.5 and absf(sr.size.y - first.size.y) < 0.5, "equal slot sizes")
			_check(sr.position.x >= prev_end, "slots do not overlap")
			_check(sr.position.y == first.position.y and hero.encloses(sr), "slots aligned in hero")
			prev_end = sr.end.x
		_check(hud._stop_btn.get_global_rect().position.x >= prev_end, "Stop outside the four slots")
		_check(hud._empty_slots[0].disabled and hud._empty_slots[1].disabled, "empty slots inert")
		var hpr: Rect2 = hud._hp_bar.get_global_rect()
		var mpr: Rect2 = hud._mana_bar.get_global_rect()
		_check(hpr.position.y >= first.end.y and mpr.position.y >= hpr.end.y, "bars below slots")
		_check(hud._hp_bar.get_global_rect().size.x >= first.size.x * 4.0, "bar spans slots")
		_check(hud.get_item_slots().find_children("Slot*", "Panel", true, false).size() == 6, "six item slots")

		# Click blocking.
		_check(hud.pointer_over_ui(hero.get_center()), "pointer blocked in hero")
		_check(hud.pointer_over_ui(rects["items"].get_center()), "pointer blocked on items")
		_check(hud.pointer_over_ui(mini.get_center()), "pointer blocked on minimap")
		_check(not hud.pointer_over_ui(Vector2(vs.x * 0.5, vs.y * 0.4)), "world open")

		# Item toggle collapses the footprint and stops blocking.
		hud.show_items = false
		for i in 3:
			await process_frame
		_check(not hud.get_item_slots().visible, "show_items=false hides items")
		_check(not hud.pointer_over_ui(rects["items"].get_center()) or hud.get_node("Root/HeroPanel").get_global_rect().has_point(rects["items"].get_center()), "hidden items do not block")
		_check(screen.encloses(hud._bottom.get_global_rect()) and hud.get_minimap().visible, "hero/minimap stay after hiding items")
		hud.show_items = true
		for i in 3:
			await process_frame
		_check(hud.get_item_slots().visible, "show_items=true restores items")
		var again: Rect2 = hud.get_item_slots().get_global_rect()
		_check(again.size.x > 0.0 and not again.intersects(hud._bottom.get_global_rect()), "items reflow after restore")

		hud.show_message("A very long message that should wrap rather than extend beyond the viewport width. ".repeat(4))
		for i in 3:
			await process_frame
		var t: Rect2 = hud._toast_panel.get_global_rect()
		_check(screen.encloses(t), "toast inside %s: %s" % [size, t])
		print(size, " hero=", hero, " items=", rects["items"], " minimap=", mini, " toast=", t)

	# ---- behaviour
	var unit_scene = load("res://units/hawkRider/hawk_rider_unit.tscn")
	var caster = unit_scene.instantiate()
	var ally = unit_scene.instantiate()
	for unit in [caster, ally]:
		unit.effects_enabled = false
		root.add_child(unit)
		unit.set_physics_process(false)
	hud.set_selection([caster])
	_check(not hud._bolt_btn.disabled and not hud._melter_btn.disabled, "ready spell buttons enabled")
	_check(hud._hp_label.text.begins_with("Health") and hud._mana_label.text.begins_with("Mana"), "bar labels")
	_check(caster.issue_cast_melter(caster.global_position), "start channel for HUD test")
	hud._refresh()
	_check(hud._melter_btn.disabled and hud._melter_btn.cooldown_text == "30", "channel shows cooldown immediately")
	_check(hud._melter_btn.cooldown_overlay.visible and hud._melter_btn.cooldown_fraction > 0.99, "melter overlay full")
	_check(hud._bolt_btn.disabled, "other spell unavailable during channel")
	caster.issue_stop()
	caster.bolt_cooldown_remaining = 60.0
	hud._refresh()
	_check(hud._bolt_btn.disabled and hud._bolt_btn.cooldown_text == "60", "Bolt cooldown countdown")
	_check(hud._melter_btn.disabled and hud._melter_btn.cooldown_text == "30", "Melter cooldown survives interruption in HUD")
	hud.set_selection([caster, ally])
	_check(not hud._bolt_btn.disabled and not hud._melter_btn.disabled, "ready selected ally enables spell buttons")
	_check(hud._bolt_btn.hotkey == "RMB" and hud._melter_btn.hotkey == "Q", "ready group shows shortcuts")
	_check(hud._hp_label.text.contains("(total)") and hud._lead_label.text == "Lead unit", "group totals and lead stats marked")
	hud.set_selection([caster])
	caster.advance_simulation(30.0)
	hud._refresh()
	_check(hud._bolt_btn.disabled and hud._bolt_btn.cooldown_text == "30", "Bolt countdown ticks")
	_check(not hud._melter_btn.disabled and not hud._melter_btn.cooldown_overlay.visible, "Melter button reenabled at expiry")
	caster.advance_simulation(30.0)
	hud._refresh()
	_check(not hud._bolt_btn.disabled, "Bolt button reenabled at expiry")
	_check(hud._stat_values["damage"].text != "-" and hud._stat_values["move"].text != "-", "stats shown")

	# Stats popup: hover opens, stays inside the screen, blocks UI.
	var vs2: Vector2 = hud.get_viewport().get_visible_rect().size
	hud._stats_hover = true
	hud._refresh()
	_check(hud.is_stats_popup_open(), "popup opens on hover")
	var pr: Rect2 = hud._stats_popup.get_global_rect()
	_check(Rect2(Vector2.ZERO, vs2).encloses(pr), "popup on screen %s" % pr)
	_check(hud.pointer_over_ui(pr.get_center()), "popup blocks pointer")
	_check(hud._stats_popup_label.text.contains("Vision") and hud._stats_popup_label.text.contains("Melter"), "popup content")
	hud._stats_hover = false
	hud._stats_focus = true
	hud._refresh()
	_check(hud.is_stats_popup_open(), "popup opens on focus")
	hud._stats_focus = false
	hud._refresh()
	_check(not hud.is_stats_popup_open(), "popup closes")

	# Missing ability resources are handled safely.
	caster.bolt = null
	hud._refresh()
	_check(hud._bolt_btn.disabled and not hud._bolt_btn.cooldown_overlay.visible, "missing Bolt resource disabled")
	_check(hud._stats_popup_text().contains("not installed"), "popup notes missing ability")
	caster.melter = null
	hud._refresh()
	_check(hud._melter_btn.disabled, "missing Melter resource disabled")

	hud.set_selection([])
	_check(hud._bolt_btn.disabled and hud._melter_btn.disabled and hud._stop_btn.disabled, "no selection disables spells")
	_check(hud._title.text == "Nothing selected" and hud._stat_values["damage"].text == "-", "no selection clears panel")
	caster.free()
	ally.free()
	hud.set_selection([caster])  # freed unit must not crash
	print("hud layout failures: ", _fail)
	quit(1 if _fail > 0 else 0)
