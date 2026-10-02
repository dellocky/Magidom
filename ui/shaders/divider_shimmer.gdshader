shader_type canvas_item;

// Gold-to-violet divider with a sweeping highlight and rounded ends.

uniform vec3 tint_a : source_color = vec3(0.478, 0.239, 0.969);
uniform vec3 tint_b : source_color = vec3(0.992, 0.733, 0.259);
uniform float speed = 0.6;

void fragment() {
	vec2 uv = UV;

	vec3 col = mix(tint_a, tint_b, uv.x);

	// Moving bright sweep.
	float sweep = fract(uv.x - TIME * speed);
	float sheen = smoothstep(0.0, 0.35, sweep) * (1.0 - smoothstep(0.35, 1.0, sweep));
	col += vec3(1.0) * sheen * 0.5;

	// Fade the tips so the bar reads as a pill.
	float endfade = smoothstep(0.0, 0.12, uv.x) * (1.0 - smoothstep(0.88, 1.0, uv.x));
	col = mix(vec3(0.0), col, endfade);

	COLOR = vec4(col, 1.0);
}