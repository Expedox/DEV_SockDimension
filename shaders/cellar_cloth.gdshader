shader_type spatial;
render_mode cull_disabled;

// Laundry hanging on the line: soft vertical folds and a fine weave.

#include "res://shaders/cellar_noise.gdshaderinc"

uniform vec3 color : source_color = vec3(0.8, 0.75, 0.68);
uniform float folds = 5.0;
uniform float depth = 0.03;
uniform float seed = 0.0;

void vertex() {
	// UV.y is 0 at the line, so the folds open up towards the bottom hem.
	float open = 0.3 + 0.7 * UV.y;
	float wave = sin(UV.x * folds * TAU + seed) + 0.4 * sin(UV.x * folds * 2.3 * TAU + seed * 1.7);
	VERTEX.z += wave * depth * open;
	float slope = (cos(UV.x * folds * TAU + seed) * folds * TAU) * depth * open;
	NORMAL = normalize(vec3(-slope * 0.15, 0.0, 1.0));
}

void fragment() {
	vec2 weave_uv = UV * vec2(260.0, 300.0);
	float weave = (sin(weave_uv.x) * sin(weave_uv.y)) * 0.5 + 0.5;
	float pixel = length(fwidth(weave_uv));
	weave = mix(weave, 0.5, smoothstep(0.5, 2.0, pixel));
	vec3 c = color * (0.9 + 0.12 * weave) * (0.92 + 0.1 * cellar_fbm(UV * 6.0 + seed, 2));
	// Damp, darker hem.
	c *= 1.0 - 0.15 * smoothstep(0.75, 1.0, UV.y);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
	BACKLIGHT = c * 0.35;
}
