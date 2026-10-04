extends Control
## Non-interactive overlay: projected health/mana bars above living RTS units
## and the drag-selection rectangle. Never consumes mouse input.

const FRIENDLY := Color(0.38, 0.82, 1.0)
const ENEMY := Color(1.0, 0.47, 0.40)
const MANA := Color(0.50, 0.44, 1.0)
const ANCHOR_OFFSET := Vector3.UP * 2.6

var marquee_rect := Rect2()
var marquee_active := false
var bar_width := 56.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	_draw_unit_bars()
	if marquee_active:
		var r := marquee_rect.abs()
		draw_rect(r, Color(0.30, 0.78, 1.0, 0.12), true)
		draw_rect(r, Color(0.60, 0.92, 1.0, 0.95), false, 1.5)


func _draw_unit_bars() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var view := get_viewport_rect().grow(60.0)
	for u in get_tree().get_nodes_in_group("rts_units"):
		if not is_instance_valid(u) or not (u is Node3D):
			continue
		if u.has_method("is_alive") and not u.is_alive():
			continue
		var world: Vector3 = u.global_position + ANCHOR_OFFSET
		if cam.is_position_behind(world):
			continue
		var p: Vector2 = cam.unproject_position(world)
		if not view.has_point(p):
			continue
		var st = u.get("stats")
		var max_hp := 1.0
		var max_mana := 1.0
		if st != null:
			max_hp = maxf(float(st.get("max_health")), 1.0)
			max_mana = maxf(float(st.get("max_mana")), 1.0)
		var hp := clampf(float(u.get("health")) / max_hp, 0.0, 1.0)
		var mp := clampf(float(u.get("mana")) / max_mana, 0.0, 1.0)
		var col := ENEMY if int(u.get("team")) == 1 else FRIENDLY
		var sel := bool(u.get("selected"))
		var w := bar_width
		var x := p.x - w * 0.5
		var y := p.y
		draw_rect(Rect2(x - 1.5, y - 1.5, w + 3.0, 13.0), Color(0.01, 0.03, 0.06, 0.82), true)
		draw_rect(Rect2(x, y, w, 7.0), Color(0.10, 0.14, 0.2, 0.95), true)
		draw_rect(Rect2(x, y, w * hp, 7.0), col, true)
		draw_rect(Rect2(x, y + 8.0, w, 3.0), Color(0.10, 0.12, 0.22, 0.95), true)
		draw_rect(Rect2(x, y + 8.0, w * mp, 3.0), MANA, true)
		var edge := Color(1, 1, 1, 0.95) if sel else col.darkened(0.35)
		draw_rect(Rect2(x - 1.5, y - 1.5, w + 3.0, 13.0), edge, false, 1.0)
