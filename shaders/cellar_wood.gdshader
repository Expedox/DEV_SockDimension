shader_type spatial;

// Old softwood boards: grain along one axis, plank seams, darker with age.

#include "res://shaders/cellar_noise.gdshaderinc"

uniform vec3 wood_color : source_color = vec3(0.42, 0.29, 0.2);
uniform vec3 wood_dark : source_color = vec3(0.25, 0.17, 0.11);
uniform float plank_width = 0.18;
// 0 = grain along world X, 1 = along world Z, 2 = along world Y.
uniform int grain_axis = 0;
uniform bool seams = true;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 an = abs(world_normal);
	float along = grain_axis == 0 ? world_pos.x : (grain_axis == 1 ? world_pos.z : world_pos.y);
	// The across coordinate is whichever remaining axis lies in this face.
	float across;
	if (grain_axis == 2) {
		across = an.x > an.z ? world_pos.z : world_pos.x;
	} else {
		float other = grain_axis == 0 ? world_pos.z : world_pos.x;
		across = an.y > 0.5 ? other : world_pos.y;
	}
	float pixel = length(fwidth(vec2(along, across)));

	float plank = floor(across / plank_width);
	float in_plank = fract(across / plank_width);
	float offset = cellar_hash1(vec2(plank, 7.0)) * 20.0;

	float rings = cellar_fbm(vec2(along * 0.6 + offset, across * 14.0), 3);
	float grain = sin((across * 60.0 + rings * 9.0)) * 0.5 + 0.5;
	float fibres = cellar_fbm(vec2(along * 1.5 + offset, across * 120.0), 2);
	vec3 color = mix(wood_dark, wood_color, 0.45 + 0.35 * grain * (1.0 - smoothstep(0.02, 0.1, pixel)) + 0.2 * fibres);
	color *= 0.85 + 0.25 * cellar_hash1(vec2(plank, 2.0));
	// Knots now and then.
	vec2 knot_cell = vec2(floor(along / 1.3), plank);
	vec2 knot_at = vec2((knot_cell.x + 0.2 + 0.6 * cellar_hash1(knot_cell)) * 1.3, (plank + 0.5) * plank_width);
	float knot = smoothstep(0.035, 0.0, length((vec2(along, across) - knot_at) * vec2(0.45, 1.0)))
			* step(0.6, cellar_hash1(knot_cell + 3.0));
	color = mix(color, wood_dark * 0.6, knot);

	if (seams) {
		float seam_px = max(pixel, 0.003);
		float seam = 1.0 - smoothstep(0.0, seam_px * 1.5, min(in_plank, 1.0 - in_plank) * plank_width);
		color *= 1.0 - 0.65 * seam;
	}

	ALBEDO = color;
	ROUGHNESS = 0.8 - 0.1 * grain;
	SPECULAR = 0.25;
}
