shader_type spatial;
render_mode cull_disabled;

// Moulded plastic laundry basket: rows of slots with solid rims.

uniform vec3 color : source_color = vec3(0.25, 0.56, 0.71);
uniform vec2 slots = vec2(26.0, 6.0);
uniform float rim = 0.14;

void fragment() {
	vec2 uv = vec2(UV.x, UV.y) * slots;
	vec2 f = abs(fract(uv) - 0.5);
	float hole = step(f.x, 0.3) * step(f.y, 0.34);
	float solid = step(UV.y, rim) + step(1.0 - rim, UV.y);
	ALPHA = max(1.0 - hole, solid);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = color;
	ROUGHNESS = 0.45;
	SPECULAR = 0.5;
}
