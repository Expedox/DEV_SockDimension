shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, specular_disabled, ambient_light_disabled;

// Dust motes: soft camera-facing dots that only show where a lamp shines on
// them, so they sparkle in the light cones and vanish in the dark.

uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.75);
uniform float strength = 0.6;

varying float fade;

void vertex() {
	mat4 facing = mat4(MAIN_CAM_INV_VIEW_MATRIX[0], MAIN_CAM_INV_VIEW_MATRIX[1], MAIN_CAM_INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * facing * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	fade = COLOR.a;
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	ALBEDO = tint;
	ALPHA = clamp(1.0 - dot(d, d), 0.0, 1.0) * fade * strength;
}

void light() {
	// Ignore the facing: a mote scatters light the same way from every side.
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION / PI;
}
