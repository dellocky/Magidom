shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Progressively drawn stroke: UV.x is the distance along the stroke, UV.y across.

uniform vec4 color : source_color = vec4(0.2, 1.0, 0.35, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float intensity = 1.6;

void fragment() {
	if (UV.x > progress) {
		discard;
	}
	float across = clamp(abs(UV.y * 2.0 - 1.0), 0.0, 1.0);
	float body = 1.0 - smoothstep(0.65, 1.0, across);
	float tip = smoothstep(0.25, 0.0, progress - UV.x) * step(progress, 0.999);
	vec3 col = mix(color.rgb, vec3(0.85, 1.0, 0.9), tip * 0.8 + (1.0 - across) * 0.25);
	ALBEDO = col * intensity;
	ALPHA = body * fade * color.a;
}
