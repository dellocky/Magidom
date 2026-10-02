shader_type canvas_item;

// Restrained navy framing, without black letterboxing or heavy scanlines.
uniform float aspect = 1.777;
uniform float vignette : hint_range(0.0, 1.0) = 0.22;
uniform float scanline : hint_range(0.0, 1.0) = 0.025;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(min(aspect, 1.8), 1.0);
	float edge = smoothstep(0.38, 1.1, length(p)) * vignette;
	float scan = (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159)) * scanline;
	COLOR = vec4(0.008, 0.018, 0.045, clamp(edge + scan, 0.0, 0.5));
}
