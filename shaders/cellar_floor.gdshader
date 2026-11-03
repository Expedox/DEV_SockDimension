shader_type spatial;

// Old, stained concrete with saw-cut joints. Kept calm so the socks stand out.

#include "res://shaders/cellar_noise.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.44, 0.42, 0.38);
uniform vec3 dark_color : source_color = vec3(0.28, 0.26, 0.24);
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

	ALBEDO = color;
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(bump, 0.0)).xyz);
}
