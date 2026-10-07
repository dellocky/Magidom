shader_type canvas_item;

uniform sampler2D visibility_mask : filter_linear, repeat_disable;
uniform bool fog_enabled = true;
uniform vec4 map_bounds = vec4(-50.0, -50.0, 100.0, 100.0);

void fragment() {
	vec2 world = map_bounds.xy + UV * map_bounds.zw;
	vec2 grid_uv = world / 5.0;
	vec2 footprint = max(fwidth(grid_uv), vec2(0.0001));
	vec2 grid_dist = abs(fract(grid_uv - 0.5) - 0.5) / footprint;
	float grid = 1.0 - min(min(grid_dist.x, grid_dist.y), 1.0);
	float border = smoothstep(47.5, 49.0, max(abs(world.x), abs(world.y)));
	float centre = 1.0 - smoothstep(0.25, 0.8, abs(world.x));
	vec3 terrain = mix(vec3(0.065, 0.11, 0.14), vec3(0.13, 0.23, 0.26), grid * 0.55);
	terrain = mix(terrain, vec3(0.19, 0.38, 0.43), max(border * 0.8, centre * 0.5));
	vec2 sight = texture(visibility_mask, UV).rg;
	float visibility = fog_enabled ? mix(sight.g * 0.24, 1.0, sight.r) : 1.0;
	COLOR = vec4(terrain * visibility, 1.0);
}
