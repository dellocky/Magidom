shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

// Ribbon lightning bolts: UV.x runs along the bolt, UV.y across it.

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float intensity = 3.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float across = clamp(abs(UV.y * 2.0 - 1.0), 0.0, 1.0);
	float core = pow(1.0 - across, 6.0);
	float halo = pow(1.0 - across, 1.8);
	float ends = pow(max(sin(UV.x * 3.14159), 0.0), 0.5);
	float flick = 0.8 + 0.2 * sin(TIME * 90.0 + UV.x * 20.0);
	vec3 col = edge_color.rgb * halo * 0.7 + core_color.rgb * core;
	ALBEDO = col * intensity * fade * ends * flick;
	ALPHA = clamp(halo * ends * fade, 0.0, 1.0);
}
