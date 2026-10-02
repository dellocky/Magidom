shader_type canvas_item;

// A self-contained arcane seal: etched rings, runic marks and a faceted core.
uniform vec3 line_color : source_color = vec3(0.27, 0.62, 0.94);
uniform vec3 core_color : source_color = vec3(0.67, 0.87, 1.0);

float stroke(float distance_to_line, float width, float aa) {
	return 1.0 - smoothstep(width, width + aa, abs(distance_to_line));
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	return length(p - a - ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float aa = max(fwidth(radius), 0.001);
	float t = TIME * 0.025;
	float lines = stroke(radius - 0.73, 0.0015, aa) * 0.48;
	lines += stroke(radius - 0.76, 0.001, aa) * 0.3;
	lines += stroke(radius - 0.57, 0.0015, aa) * 0.65;
	lines += stroke(radius - 0.55, 0.001, aa) * 0.2;

	float ticks = pow(max(cos((angle + t) * 72.0), 0.0), 18.0);
	lines += ticks * smoothstep(0.77, 0.78, radius) * (1.0 - smoothstep(0.81, 0.82, radius)) * 0.5;
	float arcs = smoothstep(-0.2, 0.2, sin(angle * 3.0 - t * 2.0));
	lines += stroke(radius - 0.86, 0.002, aa) * arcs * 0.4;

	// Twelve geometric glyphs, each in its own rotating ring sector.
	float sector = TAU / 12.0;
	float local_angle = mod(angle + t + sector * 0.5, sector) - sector * 0.5;
	vec2 glyph = vec2(sin(local_angle) * radius, radius - 0.65);
	float rune = stroke(segment(glyph, vec2(-0.018, -0.025), vec2(0.0, 0.024)), 0.0015, aa);
	rune += stroke(segment(glyph, vec2(0.0, 0.024), vec2(0.018, -0.025)), 0.0015, aa);
	rune += stroke(segment(glyph, vec2(-0.025, -0.004), vec2(0.025, -0.004)), 0.0015, aa);
	lines += rune * 0.65;

	// Interlocking triangles rotate independently of the outer etchings.
	for (int i = 0; i < 6; i++) {
		float a = float(i) * TAU / 6.0 - t * 0.6;
		float b = a + TAU / 3.0;
		vec2 start = vec2(cos(a), sin(a)) * 0.535;
		vec2 end = vec2(cos(b), sin(b)) * 0.535;
		lines += stroke(segment(p, start, end), 0.001, aa) * 0.26;
		lines += (1.0 - smoothstep(0.003, 0.010, length(p - start))) * 0.9;
	}

	// Tall diamond core, with a lit edge and two contrasting facets.
	vec2 crystal = p - vec2(0.0, sin(TIME * 0.65) * 0.014);
	float diamond = abs(crystal.x) / 0.115 + abs(crystal.y) / 0.285;
	float fill = 1.0 - smoothstep(0.985, 1.0, diamond);
	float edge = stroke(diamond - 1.0, 0.009, aa * 7.0);
	float seam = stroke(segment(crystal, vec2(0.0, -0.285), vec2(0.0, 0.285)), 0.0015, aa);
	seam += stroke(segment(crystal, vec2(-0.115, 0.0), vec2(0.115, 0.0)), 0.001, aa);
	float bloom = exp(-dot(crystal, crystal) * 16.0);
	float facet = mix(0.10, 0.33, step(0.0, crystal.x)) * fill;
	vec3 color = line_color * (lines + bloom * 0.13 + facet);
	color += core_color * (edge * 0.9 + seam * fill * 0.45);
	float alpha = clamp(lines * 0.75 + bloom * 0.18 + fill * 0.8 + edge + seam * fill, 0.0, 1.0);
	COLOR = vec4(color, alpha);
}
