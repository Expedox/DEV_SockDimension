shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// INSTANCE_CUSTOM layout, written by SockSet.custom_data():
// r = base palette index / 255
// g = accent palette index / 255
// b = (pattern * 16 + count) / 255
// a = length scale / 2

const int PATTERN_STRIPES = 1;
const int PATTERN_DOTS = 2;
const int PATTERN_TOE_HEEL = 3;
const int PATTERN_CUFF_RINGS = 4;

uniform vec3 palette[32];
uniform vec3 leg_vector;
uniform float heel_v = 0.42;
uniform float cuff_band = 0.1;
uniform float toe_start = 0.86;
uniform float crumple = 0.012;
uniform float knit_strength = 0.1;

varying flat vec3 v_base;
varying flat vec3 v_accent;
varying flat int v_pattern;
varying flat int v_count;

void vertex() {
	int packed = int(round(INSTANCE_CUSTOM.b * 255.0));
	v_base = palette[int(round(INSTANCE_CUSTOM.r * 255.0))];
	v_accent = palette[int(round(INSTANCE_CUSTOM.g * 255.0))];
	v_pattern = packed / 16;
	v_count = packed % 16;

	// Longer or shorter leg, keeping the box centered.
	float scale = INSTANCE_CUSTOM.a * 2.0;
	VERTEX += leg_vector * (scale - 1.0) * (UV2.y - 0.5);

	// Soft per-sock wrinkle so a pile does not look stamped.
	float phase = float(INSTANCE_ID) * 1.618;
	VERTEX.y += crumple * sin(VERTEX.x * 13.0 + phase) * cos(VERTEX.z * 11.0 + phase * 2.0);
}

float band(float x, float width, float aa) {
	float d = abs(fract(x) - 0.5);
	return 1.0 - smoothstep(width - aa, width + aa, d);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float v_aa = fwidth(v);
	float accent = 0.0;

	if (v_pattern == PATTERN_STRIPES) {
		float x = (v - cuff_band) / (toe_start - cuff_band) * float(v_count);
		float inside = step(cuff_band, v) * step(v, toe_start);
		accent = band(x, 0.22, v_aa * float(v_count)) * inside;
	} else if (v_pattern == PATTERN_DOTS) {
		float columns = float(v_count) * 2.0;
		vec2 grid = vec2(u * columns, v * columns * 2.8);
		grid.x += 0.5 * mod(floor(grid.y), 2.0);
		float aa = max(fwidth(grid.y), 0.02);
		float d = length(fract(grid) - 0.5);
		accent = (1.0 - smoothstep(0.27 - aa, 0.27 + aa, d)) * step(cuff_band, v);
	} else if (v_pattern == PATTERN_TOE_HEEL) {
		float toe = smoothstep(toe_start - v_aa, toe_start + v_aa, v);
		float du = min(u, 1.0 - u) / 0.3;
		float d = length(vec2(du, (v - heel_v) / 0.085));
		accent = max(toe, 1.0 - smoothstep(1.0 - v_aa * 8.0, 1.0 + v_aa * 8.0, d));
	} else if (v_pattern == PATTERN_CUFF_RINGS) {
		float zone = cuff_band * 2.2;
		float x = v / zone * float(v_count);
		accent = band(x, 0.26, v_aa * float(v_count) / zone) * step(v, zone);
	}

	vec3 color = mix(v_base, v_accent, accent);

	// Knit: fine ribs on the cuff, a soft weave elsewhere, faded out with distance.
	float fade = 1.0 - smoothstep(0.02, 0.08, fwidth(u) * 8.0);
	float cuff = 1.0 - step(cuff_band, v);
	float rib = sin(u * TAU * 16.0);
	float weave = sin(u * TAU * 32.0) * sin(v * TAU * 90.0);
	color *= 1.0 + knit_strength * fade * mix(weave, rib * 2.0, cuff);

	// Inside of the opening.
	if (v < 0.0) {
		color *= 0.15;
	}

	ALBEDO = color;
	ROUGHNESS = 1.0;
	RIM = 0.25;
	RIM_TINT = 0.6;
}
