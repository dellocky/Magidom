shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Flat ground ring on a PlaneMesh, optionally filled with a swirling pattern.

uniform vec4 color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float size_m = 4.0;
uniform float radius_m = 1.5;
uniform float thickness_m = 0.12;
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float spiral : hint_range(0.0, 1.0) = 0.0;
uniform float spin = 3.0;
uniform float intensity = 1.2;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * size_m;
	float d = length(p);
	float aa = 0.05;
	float off = abs(d - radius_m);
	float line = 1.0 - smoothstep(thickness_m * 0.5 - aa, thickness_m * 0.5 + aa, off);
	float halo = exp(-off * 4.0) * 0.35;
	float alpha = max(line, halo * 0.5);
	float inside = 1.0 - smoothstep(radius_m - 0.1, radius_m, d);
	float ang = atan(p.y, p.x);
	float s = 0.5 + 0.5 * sin(ang * 6.0 + d / max(radius_m, 0.01) * 10.0 - TIME * spin);
	float pat = s * s;
	float disk = inside * fill * mix(1.0, 0.25 + 0.75 * pat, spiral) * (0.4 + 0.6 * d / max(radius_m, 0.01));
	alpha = max(alpha, disk);
	vec3 col = mix(color.rgb, vec3(1.0), line * 0.35 * spiral);
	ALBEDO = col * intensity;
	ALPHA = clamp(alpha * color.a * fade, 0.0, 1.0);
}
