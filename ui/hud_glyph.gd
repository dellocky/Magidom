extends Control
## Placeholder geometric glyph (no external art). kind: damage | armor | move |
## bolt | melter | empty. Draws inside the largest centred square and never
## takes mouse input.

var kind: String = "empty":
	set(v):
		kind = v
		queue_redraw()
var color: Color = Color.WHITE:
	set(v):
		color = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(14, 14)


func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 1.0:
		return
	var o := (size - Vector2(side, side)) * 0.5
	var w := maxf(1.5, side * 0.12)
	match kind:
		"damage":
			draw_line(_p(o, side, 0.18, 0.82), _p(o, side, 0.82, 0.18), color, w)
			draw_colored_polygon(PackedVector2Array([_p(o, side, 0.72, 0.06), _p(o, side, 0.94, 0.06), _p(o, side, 0.94, 0.28)]), color)
			draw_line(_p(o, side, 0.22, 0.52), _p(o, side, 0.48, 0.78), color, w)
		"armor":
			draw_colored_polygon(PackedVector2Array([
				_p(o, side, 0.5, 0.04), _p(o, side, 0.90, 0.20), _p(o, side, 0.84, 0.62),
				_p(o, side, 0.5, 0.96), _p(o, side, 0.16, 0.62), _p(o, side, 0.10, 0.20)]), color)
			draw_line(_p(o, side, 0.5, 0.18), _p(o, side, 0.5, 0.80), Color(0, 0, 0, 0.45), w * 0.6)
		"move":
			draw_polyline(PackedVector2Array([_p(o, side, 0.14, 0.2), _p(o, side, 0.48, 0.5), _p(o, side, 0.14, 0.8)]), color, w)
			draw_polyline(PackedVector2Array([_p(o, side, 0.5, 0.2), _p(o, side, 0.86, 0.5), _p(o, side, 0.5, 0.8)]), color, w)
		"bolt":
			draw_colored_polygon(PackedVector2Array([
				_p(o, side, 0.62, 0.02), _p(o, side, 0.18, 0.56), _p(o, side, 0.46, 0.56),
				_p(o, side, 0.34, 0.98), _p(o, side, 0.84, 0.38), _p(o, side, 0.56, 0.38), _p(o, side, 0.74, 0.02)]), color)
		"melter":
			var c := o + Vector2(side, side) * 0.5
			draw_arc(c, side * 0.44, 0.0, TAU, 28, color, w)
			draw_arc(c, side * 0.26, 0.0, TAU, 20, color, w * 0.8)
			draw_circle(c, side * 0.09, color)
			draw_line(_p(o, side, 0.5, 0.0), _p(o, side, 0.5, 0.12), color, w * 0.8)
			draw_line(_p(o, side, 0.5, 0.88), _p(o, side, 0.5, 1.0), color, w * 0.8)
		"buff":
			# Two rising chevrons: a speed/buff mark.
			draw_polyline(PackedVector2Array([_p(o, side, 0.24, 0.78), _p(o, side, 0.42, 0.46), _p(o, side, 0.60, 0.78)]), color, w)
			draw_polyline(PackedVector2Array([_p(o, side, 0.56, 0.90), _p(o, side, 0.74, 0.58), _p(o, side, 0.92, 0.90)]), color, w)
		"whack":
			# Open palm with three motion lines: a melee slap.
			draw_line(_p(o, side, 0.18, 0.70), _p(o, side, 0.18, 0.30), color, w)
			draw_line(_p(o, side, 0.36, 0.70), _p(o, side, 0.36, 0.30), color, w)
			draw_line(_p(o, side, 0.55, 0.70), _p(o, side, 0.55, 0.30), color, w)
			draw_line(_p(o, side, 0.62, 0.70), _p(o, side, 0.62, 0.30), color, w)
			draw_line(_p(o, side, 0.12, 0.30), _p(o, side, 0.68, 0.30), color, w)
			draw_arc(_p(o, side, 0.40, 0.30), side * 0.28, PI, TAU, 12, color, w)
		"baneling":
			# Eight-spike starburst with a hot centre: a detonation.
			var c := o + Vector2(side, side) * 0.5
			draw_circle(c, side * 0.10, color)
			for i in 8:
				var angle: float = TAU * float(i) / 8.0
				draw_line(c, c + Vector2(cos(angle), sin(angle)) * side * 0.42, color, w)
		_:
			draw_rect(Rect2(o + Vector2(side, side) * 0.22, Vector2(side, side) * 0.56), color, false, 1.0)


func _p(o: Vector2, side: float, x: float, y: float) -> Vector2:
	return o + Vector2(x, y) * side
