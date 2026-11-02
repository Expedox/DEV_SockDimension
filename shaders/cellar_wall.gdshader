shader_type spatial;

// Whitewashed brick with a painted band along the bottom.

uniform vec3 brick_color : source_color = vec3(0.85, 0.81, 0.72);
uniform vec3 mortar_color : source_color = vec3(0.72, 0.68, 0.59);
uniform vec3 band_color : source_color = vec3(0.31, 0.44, 0.41);
uniform float band_height = 1.1;
uniform vec2 brick_size = vec2(0.6, 0.22);

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = abs(NORMAL);
}

void fragment() {
	// Bricks run along whichever horizontal axis the wall follows.
	float along = world_normal.x > world_normal.z ? world_pos.z : world_pos.x;
	vec2 uv = vec2(along, world_pos.y) / brick_size;
	float row = floor(uv.y);
	uv.x += mod(row, 2.0) * 0.5;
	vec2 id = floor(uv);
	vec2 f = fract(uv);
	vec2 edge = min(f, 1.0 - f) * brick_size;
	float mortar = 1.0 - smoothstep(0.006, 0.016, min(edge.x, edge.y));

	vec3 color = mix(brick_color * (0.93 + 0.1 * hash(id)), mortar_color, mortar);
	float blotch = noise(vec2(along, world_pos.y) * 1.3);
	color *= 0.92 + 0.12 * blotch;

	float edge_line = world_pos.y + (noise(vec2(along * 3.0, 0.0)) - 0.5) * 0.012;
	float band = 1.0 - smoothstep(band_height - 0.004, band_height + 0.004, edge_line);
	color = mix(color, band_color * (0.92 + 0.1 * blotch) * (1.0 - 0.18 * mortar), band);

	ALBEDO = color;
	ROUGHNESS = mix(0.9, 0.5, band);
	SPECULAR = 0.3;
}
