shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

// White-blue electrical plasma for spheres/cylinders. Noise is sampled in
// world-scaled local space so features keep their size when a mesh is scaled.

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.25, 0.6, 1.0, 1.0);
uniform float intensity = 1.5;
uniform float activity = 1.0;
uniform float rim_power = 2.0;
uniform float rim_invert : hint_range(0.0, 1.0) = 0.0;
uniform float noise_scale = 1.2;
uniform vec3 flow = vec3(0.0, -2.0, 0.0);
uniform float top_fade : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;

varying vec3 wpos;
varying float vy;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash31(i), hash31(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 3; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(7.1, 3.7, 1.3);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	wpos = VERTEX * s;
	vy = VERTEX.y + 0.5;
}

void fragment() {
	float ndv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float center = pow(ndv, rim_power);
	float rim = pow(1.0 - ndv, rim_power);
	float shape = mix(center, rim, rim_invert);
	float t = TIME + time_offset;
	vec3 p = wpos * noise_scale + flow * t;
	float n = fbm(p);
	float n2 = fbm(p * 1.7 + vec3(0.0, t * 1.3, 0.0) + 11.0);
	// Thin bright veins where the noise field crosses its midpoint.
	float vein = pow(clamp(1.0 - abs(n - 0.5) * 5.0, 0.0, 1.0), 3.0);
	float vein2 = pow(clamp(1.0 - abs(n2 - 0.5) * 7.0, 0.0, 1.0), 3.0);
	float glow = shape * (0.55 + 0.45 * n);
	float arcs = (vein + 0.6 * vein2) * activity * (0.35 + shape);
	float e = glow + arcs;
	vec3 col = mix(edge_color.rgb, core_color.rgb, clamp(shape * 0.8 + arcs * 0.7, 0.0, 1.0));
	float topf = mix(1.0, 1.0 - smoothstep(0.55, 1.0, vy), top_fade);
	ALBEDO = col * e * intensity * fade * topf;
	ALPHA = clamp(e * fade * topf, 0.0, 1.0);
}
