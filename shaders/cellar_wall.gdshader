shader_type spatial;

// Limewashed brick, painted band along the bottom, damp and grime near the floor.

#include "res://shaders/cellar_noise.gdshaderinc"

uniform vec3 brick_color : source_color = vec3(0.85, 0.81, 0.72);
uniform vec3 mortar_color : source_color = vec3(0.72, 0.68, 0.59);
uniform vec3 band_color : source_color = vec3(0.31, 0.44, 0.41);
uniform vec3 grime_color : source_color = vec3(0.3, 0.24, 0.18);
uniform float band_height = 1.1;
uniform vec2 brick_size = vec2(0.6, 0.22);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	// Bricks run along whichever horizontal axis the wall follows.
	vec3 an = abs(world_normal);
	bool faces_x = an.x > an.z;
	float along = faces_x ? world_pos.z : world_pos.x;
	vec2 wall = vec2(along, world_pos.y);
	float pixel = length(fwidth(wall));

	vec2 uv = wall / brick_size;
	float row = floor(uv.y);
	uv.x += mod(row, 2.0) * 0.5 + (cellar_hash1(vec2(row, 1.0)) - 0.5) * 0.15;
	vec2 id = floor(uv);
	vec2 f = fract(uv);
	vec2 edge = min(f, 1.0 - f) * brick_size;
	float to_mortar = min(edge.x, edge.y);
	float mortar_w = 0.009 + cellar_gnoise(wall * 9.0) * 0.003;
	float mortar = 1.0 - smoothstep(mortar_w, mortar_w + max(pixel, 0.004), to_mortar);

	float brick_tint = cellar_hash1(id);
	vec3 brick = brick_color * (0.9 + 0.12 * brick_tint);
	// Limewash is thinner in places, the warmer brick shows through.
	float wash = cellar_fbm(wall * 2.2 + id * 0.37, 3);
	brick = mix(brick * vec3(0.95, 0.8, 0.7), brick, smoothstep(0.25, 0.45, wash));
	vec3 color = mix(brick, mortar_color, mortar);
	color *= 0.94 + 0.08 * cellar_fbm(wall * 5.0, 2);

	// Painted band with a hand-painted top edge and chipped spots.
	float edge_line = world_pos.y + cellar_gnoise(vec2(along * 3.0, 0.0)) * 0.01;
	float band = 1.0 - smoothstep(band_height - 0.004, band_height + 0.004, edge_line);
	float chips = smoothstep(0.75, 0.77, cellar_fbm(wall * vec2(1.2, 2.0) + 20.0, 4));
	band *= 1.0 - chips;
	vec3 painted = band_color * (0.9 + 0.12 * wash) * (1.0 - 0.2 * mortar);
	color = mix(color, painted, band);

	// Rising damp and grime: strongest at the floor, ragged upper edge.
	float damp_top = 0.4 + 0.9 * cellar_warped(vec2(along * 0.3, 0.0));
	float damp = smoothstep(damp_top, 0.0, world_pos.y) * 0.7;
	float streaks = smoothstep(0.55, 0.85, cellar_fbm(vec2(along * 1.5, world_pos.y * 0.15), 3))
			* smoothstep(4.5, 1.5, world_pos.y) * 0.25;
	color = mix(color, grime_color, damp + streaks);
	// Darker towards the ceiling corner where the lamps do not reach.
	color *= mix(1.0, 0.8, smoothstep(3.5, 6.0, world_pos.y));

	// Bump: bricks bulge, mortar sits back. Built in world space then turned to view space.
	vec2 slope = vec2(
			smoothstep(0.1, 0.0, f.x) - smoothstep(0.9, 1.0, f.x),
			smoothstep(0.25, 0.0, f.y) - smoothstep(0.75, 1.0, f.y)) * 0.35 * (1.0 - mortar) * (1.0 - band * 0.6);
	float detail = 1.0 - smoothstep(0.02, 0.08, pixel);
	slope *= detail;
	vec3 n = normalize(world_normal);
	vec3 tangent = faces_x ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 bumped = normalize(n - tangent * slope.x - up * slope.y);

	ALBEDO = color;
	ROUGHNESS = mix(0.92, 0.6, band) + damp * 0.05;
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
}
