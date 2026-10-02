shader_type canvas_item;

// Arcane aurora backdrop for the Magidom main menu.
// Layered sine ribbons + fbm distortion flowing across a deep gradient,
// with a soft center glow, a cursor-driven halo, vignette and grain.

uniform vec3 col_deep    : source_color = vec3(0.020, 0.012, 0.075);
uniform vec3 col_mid     : source_color = vec3(0.110, 0.039, 0.188);
uniform vec3 col_violet  : source_color = vec3(0.478, 0.239, 0.969);
uniform vec3 col_magenta : source_color = vec3(0.769, 0.239, 0.549);
uniform vec3 col_gold    : source_color = vec3(0.992, 0.733, 0.259);

uniform float time_speed      : hint_range(0.0, 0.5) = 0.05;
uniform float aurora_strength : hint_range(0.0, 2.0) = 1.0;
uniform float mouse_strength  : hint_range(0.0, 2.0) = 1.0;
uniform vec2  mouse           = vec2(0.5, 0.5);
uniform float aspect          = 1.777;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p = p * 2.03 + vec2(11.7, 5.3);
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y);
	float t = TIME * time_speed;

	// Base vertical gradient — deep to mid, easing toward the horizon.
	float base = 0.45 + 0.25 * sin(uv.y * 3.14159 + 0.5);
	vec3 col = mix(col_deep, col_mid, clamp(base, 0.0, 1.0));

	// Flowing aurora ribbons concentrated around the mid band.
	float cover = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 q = vec2(p.x * (0.6 + fi * 0.25),
		              p.y * (1.6 + fi * 0.5) + t * (1.0 + fi * 0.35));
		float w = 0.5 + 0.5 * sin(q.y + fbm(q + vec2(fi * 7.3, 0.0)) * 2.6 + fi * 2.19);
		float band = smoothstep(0.30, 0.85, w) * (1.0 - smoothstep(0.85, 1.0, w));
		float height_mask = exp(-pow((uv.y - (0.35 + 0.12 * sin(t + fi))) / 0.30, 2.0));
		float strength = (0.55 - fi * 0.12) * height_mask;
		vec3 bc = mix(col_violet, col_magenta, fi * 0.5);
		if (i == 1) { bc = mix(bc, col_gold, 0.5); }
		col += bc * band * strength * aurora_strength;
		cover += band * height_mask;
	}
	col += col_mid * cover * 0.12;

	// Soft center glow behind the menu column, slowly breathing.
	float cd = length(p - vec2(0.5 * aspect, 0.5));
	float glow = exp(-cd * cd * 2.4) * (0.34 + 0.08 * sin(TIME * 0.9));
	col += mix(col_violet, col_gold, 0.25) * glow * 0.5;

	// Cursor halo.
	float md = length(p - vec2(mouse.x * aspect, mouse.y));
	float mg = exp(-md * md * 4.0) * mouse_strength;
	col += col_violet * mg * 0.55;
	col += col_gold * mg * 0.12;

	// Vignette.
	vec2 vp = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
	float vig = smoothstep(1.15, 0.35, length(vp));
	col *= mix(0.35, 1.0, vig);

	// Fine grain to reduce banding.
	float g = hash21(uv * vec2(1920.0, 1080.0) + fract(TIME) * 821.0) - 0.5;
	col += g * 0.012;

	COLOR = vec4(col, 1.0);
}