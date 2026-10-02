shader_type canvas_item;

// A fine azure rule with a slow ice-blue highlight.
uniform vec3 tint_a : source_color = vec3(0.24, 0.57, 0.88);
uniform vec3 tint_b : source_color = vec3(0.08, 0.22, 0.40);
uniform float speed = 0.12;

void fragment() {
	float sweep = fract(TIME * speed) * 1.5 - 0.25;
	float sheen = exp(-pow((UV.x - sweep) * 12.0, 2.0));
	vec3 col = mix(tint_a, tint_b, UV.x) + vec3(0.35, 0.55, 0.7) * sheen * 0.35;
	COLOR = vec4(col, 1.0 - smoothstep(0.75, 1.0, UV.x));
}
