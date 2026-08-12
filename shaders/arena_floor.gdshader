shader_type canvas_item;
// "Neon Ops" arena floor — dark tactical base, 64 px grid with a brighter
// major line every 4th cell, radial vignette toward the edges, and a very
// subtle scanline shimmer. Pure math, GL Compatibility safe (no textures,
// no derivatives, no unsupported built-ins).

uniform vec4 base_color : source_color = vec4(0.0509804, 0.0666667, 0.0901961, 1.0); // #0D1117
uniform vec4 line_color : source_color = vec4(0.105882, 0.141176, 0.188235, 1.0);    // #1B2430
uniform vec4 vignette_color : source_color = vec4(0.0196078, 0.027451, 0.0392157, 1.0); // #05070A
uniform vec2 rect_size = vec2(1152.0, 648.0);
uniform float grid_size = 64.0;
uniform float line_width = 1.5;
uniform float major_every = 4.0;
uniform float major_boost = 1.7;
uniform float vignette_strength = 0.35;
uniform float shimmer_strength = 0.015; // < 2% luminance
uniform float shimmer_speed = 1.2;

void fragment() {
	vec2 p = UV * rect_size;

	// Distance to the nearest grid line on each axis.
	vec2 cell = mod(p, grid_size);
	vec2 dist = min(cell, vec2(grid_size) - cell);
	float half_w = line_width * 0.5;
	float lx = 1.0 - smoothstep(half_w, half_w + 1.0, dist.x);
	float ly = 1.0 - smoothstep(half_w, half_w + 1.0, dist.y);

	// Every 4th line is slightly brighter (major grid).
	float ix = floor(p.x / grid_size + 0.5);
	float iy = floor(p.y / grid_size + 0.5);
	float major_x = 1.0 - step(0.5, mod(ix, major_every));
	float major_y = 1.0 - step(0.5, mod(iy, major_every));
	lx *= mix(1.0, major_boost, major_x);
	ly *= mix(1.0, major_boost, major_y);
	float line_amt = max(lx, ly);

	vec3 col = mix(base_color.rgb, line_color.rgb, min(line_amt, 1.0));
	// Push major lines a touch past the base line color.
	col += line_color.rgb * max(line_amt - 1.0, 0.0) * 0.6;

	// Subtle scanline shimmer.
	col *= 1.0 + shimmer_strength * sin(p.y * 0.12 + TIME * shimmer_speed);

	// Radial vignette darkening toward the arena edges.
	float d = distance(UV, vec2(0.5));
	float v = smoothstep(0.25, 0.85, d) * vignette_strength;
	col = mix(col, vignette_color.rgb, v);

	COLOR = vec4(col, 1.0);
}
