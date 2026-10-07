shader_type canvas_item;

// Animated mana-pool fill. A glowing band flows left-to-right inside the filled
// region, the leading edge blooms, and a subtle vertical sheen rolls upward.
// `fill` is the fraction to fill (0..1); the HUD drives it each frame.

uniform vec4 core_color : source_color = vec4(0.28, 0.52, 1.0, 1.0);
uniform vec4 hi_color : source_color = vec4(0.5, 0.92, 1.0, 1.0);
uniform float fill : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	float x = UV.x;
	float edge = smoothstep(fill - 0.006, fill + 0.006, x);

	// Horizontal flowing shimmer.
	float flow = 0.5 + 0.5 * sin(x * 20.0 - TIME * 2.6);
	vec3 col = mix(core_color.rgb, hi_color.rgb, flow);
	col *= 0.82 + 0.18 * flow;

	// Bright leading edge at the fill boundary.
	float lead = exp(-abs(x - fill) * 260.0);
	col += hi_color.rgb * lead;

	// Slow vertical sheen.
	float sheen = 0.5 + 0.5 * sin((UV.y - 0.5) * 6.283185 + TIME * 1.4);
	col += hi_color.rgb * sheen * 0.12;

	vec3 empty = vec3(0.028, 0.055, 0.10);
	COLOR = vec4(mix(empty, col, edge), mix(0.55, 1.0, edge));
}