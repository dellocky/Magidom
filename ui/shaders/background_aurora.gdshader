shader_type canvas_item;

// Quiet navy atmosphere with blue aether and a lighter cursor-driven wake.
uniform vec3 col_deep : source_color = vec3(0.016, 0.035, 0.075);
uniform vec3 col_mid : source_color = vec3(0.035, 0.095, 0.180);
uniform vec3 col_azure : source_color = vec3(0.12, 0.40, 0.72);
uniform vec3 col_ice : source_color = vec3(0.42, 0.73, 1.0);
uniform float time_speed : hint_range(0.0, 0.5) = 0.05;
uniform float aurora_strength : hint_range(0.0, 2.0) = 0.65;
uniform float mouse_strength : hint_range(0.0, 2.0) = 1.0;
uniform vec2 mouse = vec2(0.72, 0.48);
uniform float aspect = 1.777;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), f.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		value += amplitude * vnoise(p);
		p = p * 2.03 + vec2(11.7, 5.3);
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 p = vec2(UV.x * aspect, UV.y);
	float t = TIME * time_speed;
	float right_weight = smoothstep(0.18, 0.92, UV.x);
	float cloud = fbm(p * 3.4 + vec2(-t * 0.3, t * 0.18));
	vec3 col = mix(col_deep, col_mid, (0.15 + 0.5 * cloud) * (0.45 + right_weight));

	// Mist gathers beneath the seal; the navigation side remains quiet.
	float mist = exp(-pow((UV.y - 0.66 + cloud * 0.18) * 4.0, 2.0));
	col += col_azure * mist * cloud * 0.18 * right_weight * aurora_strength;
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float ribbon = UV.y - 0.53 - fi * 0.17 + sin(p.x * 2.1 + t + fi) * 0.08;
		ribbon += (cloud - 0.5) * 0.26;
		col += col_azure * exp(-ribbon * ribbon * 360.0) * right_weight * 0.065 * aurora_strength;
	}

	// Sparse, gently drifting motes rather than a noisy star field.
	vec2 star_grid = p * 95.0 + vec2(t * 0.3, -t * 0.5);
	vec2 cell = floor(star_grid);
	float seed = hash21(cell);
	float star = (1.0 - smoothstep(0.02, 0.12, length(fract(star_grid) - 0.5)));
	star *= step(0.982, seed) * (0.55 + 0.45 * sin(TIME * 0.6 + seed * 120.0));
	col += col_ice * star * 0.32 * (0.25 + right_weight);

	// Apply after ambient shading so the light blue wake is visible on the left too.
	vec2 cursor_delta = p - vec2(mouse.x * aspect, mouse.y);
	float distance_squared = dot(cursor_delta, cursor_delta);
	float halo = exp(-distance_squared * 19.0);
	float core = exp(-distance_squared * 100.0);
	float wake = fbm(cursor_delta * 9.0 + vec2(t, -t * 1.7));
	col += col_ice * (halo * 0.15 + core * 0.12 + halo * wake * 0.13) * mouse_strength;

	float vignette = smoothstep(0.25, 1.2, length((UV - 0.5) * vec2(1.1, 1.0)));
	col *= 1.0 - vignette * 0.25;
	float grain = hash21(FRAGCOORD.xy) - 0.5;
	COLOR = vec4(col + grain * 0.003, 1.0);
}
