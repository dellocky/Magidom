shader_type spatial;
render_mode diffuse_burley;

uniform bool fog_enabled = false;
uniform sampler2D visibility_mask : filter_linear, repeat_disable;
uniform vec4 map_bounds = vec4(-50.0, -50.0, 100.0, 100.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 grid_uv = world_pos.xz / 5.0;
	vec2 footprint = max(fwidth(grid_uv), vec2(0.0001));
	vec2 grid_dist = abs(fract(grid_uv - 0.5) - 0.5) / footprint;
	float grid = 1.0 - min(min(grid_dist.x, grid_dist.y), 1.0);
	float border = smoothstep(47.5, 49.0, max(abs(world_pos.x), abs(world_pos.z)));
	float centre = 1.0 - smoothstep(0.015, 0.06, abs(world_pos.x));
	ALBEDO = mix(vec3(0.055, 0.085, 0.11), vec3(0.105, 0.16, 0.19), grid * 0.6);
	ALBEDO = mix(ALBEDO, vec3(0.09, 0.3, 0.38), border * 0.6);
	EMISSION = vec3(0.035, 0.10, 0.13) * (grid * 0.2 + border + centre * 0.6);
	if (fog_enabled) {
		vec2 uv = (world_pos.xz - map_bounds.xy) / map_bounds.zw;
		vec2 sight = texture(visibility_mask, uv).rg;
		float visibility = mix(0.0, 0.22, sight.g);
		visibility = mix(visibility, 1.0, sight.r);
		ALBEDO *= visibility;
		EMISSION *= visibility;
	}
	ROUGHNESS = 0.92;
}
