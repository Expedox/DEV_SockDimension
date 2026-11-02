shader_type spatial;

// Old, stained concrete with saw-cut joints and a braided rag rug under the pile.

#include "res://shaders/cellar_noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.44, 0.42, 0.38);
uniform vec3 dark_color : source_color = vec3(0.28, 0.26, 0.24);
uniform vec3 rug_a : source_color = vec3(0.6, 0.3, 0.22);
uniform vec3 rug_b : source_color = vec3(0.74, 0.58, 0.32);
uniform vec3 rug_c : source_color = vec3(0.36, 0.45, 0.4);
uniform vec3 rug_d : source_color = vec3(0.8, 0.74, 0.62);
uniform vec2 rug_center = vec2(0.0);
uniform float rug_radius = 8.0;
uniform float braid_width = 0.62;
uniform float joint_spacing = 4.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Small-scale relief of the bare concrete: pits and trowel grain.
float concrete_height(vec2 p) {
	float grain = cellar_fbm(p * 9.0, 3);
	float pits = smoothstep(0.72, 0.8, cellar_fbm(p * 23.0 + 5.0, 2));
	return grain * 0.6 - pits * 0.5;
}

vec3 rug_strand(float pick) {
	return pick < 1.0 ? rug_a : (pick < 2.0 ? rug_b : (pick < 3.0 ? rug_c : rug_d));
}

void fragment() {
	vec2 p = world_pos.xz;
	float pixel = length(fwidth(p));

	// Concrete: broad mottling, warped water stains and a dusty sheen.
	float mottle = cellar_fbm(p * 0.18, 4);
	float stains = cellar_warped(p * 0.32);
	float ring_stain = smoothstep(0.03, 0.0, abs(cellar_warped(p * 0.21 + 11.0) - 0.62)) * 0.5;
	vec3 color = mix(dark_color, base_color, smoothstep(0.25, 0.75, mottle));
	color = mix(color, dark_color * 0.82, smoothstep(0.55, 0.8, stains) * 0.65);
	color *= 1.0 - ring_stain * 0.25;

	// Fade fine detail with distance so it does not shimmer.
	float detail = 1.0 - smoothstep(0.02, 0.12, pixel);
	float h = concrete_height(p);
	color *= 1.0 + (h - 0.3) * 0.22 * detail;
	color *= 0.97 + 0.06 * cellar_hash1(floor(p * 140.0)) * detail;

	// Saw-cut joints, antialiased.
	vec2 cell = abs(fract(p / joint_spacing) - 0.5) * joint_spacing;
	float to_joint = joint_spacing * 0.5 - max(cell.x, cell.y);
	float joint_px = max(pixel * 0.7, 0.004);
	float joint = 1.0 - smoothstep(0.006, 0.006 + joint_px, to_joint);
	float joint_edge = 1.0 - smoothstep(0.0, 0.06, to_joint);
	color *= 1.0 - 0.6 * joint - 0.12 * joint_edge;

	float roughness = mix(0.88, 0.62, smoothstep(0.5, 0.8, stains));

	// Bump from the concrete height, sampled with small offsets.
	float e = 0.004;
	float hx = concrete_height(p + vec2(e, 0.0));
	float hz = concrete_height(p + vec2(0.0, e));
	vec2 slope = vec2(hx - h, hz - h) / e * 0.0025 * detail;
	vec3 bump = normalize(vec3(-slope.x, 1.0, -slope.y));

	// Rag rug: coiled braids, each made of three twisted strands.
	vec2 from_center = p - rug_center;
	float dist = length(from_center);
	float edge_wobble = (cellar_gnoise(vec2(atan(from_center.y, from_center.x) * 6.0, 0.0)) * 0.04);
	float rug_edge = rug_radius + edge_wobble;
	float inside = 1.0 - smoothstep(rug_edge - pixel, rug_edge + pixel, dist);
	// Soft contact shadow just outside the rug, it sits a little above the floor.
	color *= 1.0 - 0.35 * smoothstep(0.25, 0.0, dist - rug_edge) * (1.0 - inside);

	if (inside > 0.0) {
		float ring = dist / braid_width;
		float band = floor(ring);
		float v = fract(ring);
		float angle = atan(from_center.y, from_center.x);
		float u = angle * dist / braid_width;
		float across = abs(v - 0.5);
		// Strand lobes lean one way on the inner half and the other way on the outer half.
		float lean = (v - 0.5) * 1.3;
		float s = u * 1.25 + abs(lean);
		float lobe = floor(s);
		float sf = fract(s);
		// Each braid has a main colour; one of its three strands is a neighbouring colour.
		float band_hash = cellar_hash1(vec2(band, 3.0));
		float main_pick = floor(band_hash * 4.0);
		float strand = mod(lobe + band, 3.0);
		float palette = strand < 1.0 ? mod(main_pick + 1.0 + floor(cellar_hash1(vec2(band, 9.0)) * 3.0), 4.0) : main_pick;
		vec3 rug = rug_strand(palette);
		rug *= 0.92 + 0.12 * cellar_hash1(vec2(lobe, band)) + (strand - 1.0) * 0.04;

		float lobe_shape = sin(sf * PI) * sqrt(max(1.0 - across * across * 4.0, 0.0));
		float braid_detail = 1.0 - smoothstep(0.03, 0.1, pixel);
		float shade = mix(0.85, 0.68 + 0.36 * lobe_shape, braid_detail);
		float groove = smoothstep(0.0, 0.1, v) * smoothstep(1.0, 0.9, v);
		// Dark gaps where one strand tucks under the next.
		groove *= mix(1.0, smoothstep(0.0, 0.12, sf) * smoothstep(1.0, 0.88, sf), 0.6);
		shade *= mix(0.85, 0.6 + 0.4 * groove, braid_detail);
		float fiber = cellar_fbm(vec2(u * 10.0 + v * 3.0, v * 30.0), 3);
		float lint = cellar_fbm(p * 30.0, 2);
		rug *= shade * (0.8 + 0.35 * fiber * braid_detail) * (0.92 + 0.12 * lint);

		// Lobes tilt the normal so the braid catches the lamp light.
		vec3 rug_bump = normalize(vec3(
				cos(sf * PI) * 0.35 * braid_detail * cos(angle) - (v - 0.5) * 0.5 * braid_detail * cos(angle),
				1.0,
				cos(sf * PI) * 0.35 * braid_detail * sin(angle) - (v - 0.5) * 0.5 * braid_detail * sin(angle)));

		color = mix(color, rug, inside);
		roughness = mix(roughness, 0.97, inside);
		bump = normalize(mix(bump, rug_bump, inside));
	}

	ALBEDO = color;
	ROUGHNESS = roughness;
	SPECULAR = mix(0.35, 0.15, inside);
	NORMAL = normalize((VIEW_MATRIX * vec4(bump, 0.0)).xyz);
}
