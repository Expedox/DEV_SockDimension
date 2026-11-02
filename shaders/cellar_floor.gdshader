shader_type spatial;

// Stained concrete with expansion joints and a braided rug under the pile.

uniform vec3 base_color : source_color = vec3(0.44, 0.42, 0.38);
uniform vec3 dark_color : source_color = vec3(0.28, 0.26, 0.24);
uniform vec3 rug_a : source_color = vec3(0.7, 0.33, 0.25);
uniform vec3 rug_b : source_color = vec3(0.88, 0.7, 0.36);
uniform vec3 rug_c : source_color = vec3(0.31, 0.5, 0.55);
uniform vec2 rug_center = vec2(0.0);
uniform float rug_radius = 8.0;
uniform float joint_spacing = 4.0;

varying vec3 world_pos;

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

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += amplitude * noise(p);
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + vec2(17.0, 9.0);
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float stains = fbm(p * 0.35);
	float grain = fbm(p * 7.0);
	vec3 color = mix(dark_color, base_color, smoothstep(0.3, 0.7, stains));
	color *= 0.9 + 0.2 * grain;

	vec2 cell = abs(fract(p / joint_spacing) - 0.5) * joint_spacing;
	float joint = smoothstep(joint_spacing * 0.5 - 0.02, joint_spacing * 0.5 - 0.008, max(cell.x, cell.y));
	color *= 1.0 - 0.55 * joint;
	float roughness = mix(0.82, 0.55, smoothstep(0.45, 0.7, stains));

	vec2 from_center = p - rug_center;
	float dist = length(from_center);
	float wobble = noise(p * 1.4) * 0.05;
	if (dist < rug_radius + wobble) {
		// Concentric braids; the angle term gives each ring its plaited look.
		float ring = dist * 2.2;
		float band = floor(ring);
		float angle = atan(from_center.y, from_center.x);
		float plait = sin(angle * (10.0 + band * 9.0) + band * 2.0 + fract(ring) * 3.0);
		float pick = mod(band, 3.0);
		vec3 rug = pick < 1.0 ? rug_a : (pick < 2.0 ? rug_b : rug_c);
		float groove = smoothstep(0.0, 0.12, fract(ring)) * smoothstep(1.0, 0.88, fract(ring));
		rug *= 0.62 + 0.38 * groove;
		rug *= 0.88 + 0.12 * plait;
		rug *= 0.92 + 0.16 * grain;
		color = rug;
		roughness = 0.95;
		joint = 0.0;
	}

	ALBEDO = color;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
}
