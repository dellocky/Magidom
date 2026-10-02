shader_type canvas_item;

// Cinematic framing overlay: corner vignette, faint letterbox fade
// and a whisper of scanline texture. Outputs black with variable alpha
// so it darkens whatever is already drawn beneath.

uniform float aspect   = 1.777;
uniform float vignette : hint_range(0.0, 1.0) = 0.9;
uniform float scanline : hint_range(0.0, 1.0) = 0.12;

void fragment() {
	vec2 uv = UV;

	vec2 v = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
	float vig = smoothstep(0.46, 0.98, length(v)) * vignette;

	// Subtle top/bottom fade for a filmic feel.
	float letter = (1.0 - smoothstep(0.0, 0.10, uv.y)) + smoothstep(0.90, 1.0, uv.y);

	float scan = smoothstep(0.5, 0.72, sin(uv.y * 900.0) * 0.5 + 0.5) * scanline * 0.5;

	float a = clamp(vig + letter * 0.22 + scan, 0.0, 0.95);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}