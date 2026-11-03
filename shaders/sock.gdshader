shader_type spatial;
render_mode cull_back;

// Knitted sock. Geometry and UV layout come from SockMesh: UV.x runs around the tube
// in meters (0 on the back edge), UV.y along it in meters from the cuff edge.
//
// INSTANCE_CUSTOM, written by SockSet.custom_data():
// r = base palette index / 255
// g = accent palette index / 255
// b = (pattern * 16 + count) / 255
// a = 1 when heel and toe are knitted in the accent color, +2 while the sock is aimed at

// Same order as "patterns" in data/socks.json.
const int PATTERN_STRIPES = 1;
const int PATTERN_DOTS = 2;
const int PATTERN_CUFF_RINGS = 3;
const int PATTERN_ARGYLE = 4;
// Rare easter-egg designs, knitted like intarsia motifs.
const int PATTERN_HEARTS = 5;
const int PATTERN_STARS = 6;
const int PATTERN_ZIGZAG = 7;
const int PATTERN_SNOWFLAKES = 8;
const int PATTERN_RAINBOW = 9;
const int PATTERN_PAWS = 10;

uniform vec3 palette[32];

// Per shape, set by SockMesh (meters along UV.y).
uniform float sock_length = 0.5;
uniform float heel_at = 0.2;
uniform float toe_at = 0.45;
uniform float rib_length = 0.1;
uniform float pattern_end = 0.45;

// From "knit" in data/socks.json.
uniform float stitch_width = 0.0034;
uniform float row_height = 0.0027;
uniform float yarn_depth = 0.0009;
uniform float rib_stitches = 4.0;
uniform float heather = 0.07;
uniform float crumple = 0.006;
uniform float sheen = 0.35;
uniform float wrap = 0.15;
uniform float drape = 0.03;
uniform float fold_shade = 0.35;
uniform float highlight_glow = 0.5;
uniform float highlight_rim = 1.6;

varying flat vec3 v_base;
varying flat vec3 v_accent;
varying flat int v_pattern;
varying flat int v_count;
varying flat float v_heel_toe;
varying flat float v_highlight;
varying float v_fold;

void vertex() {
	int packed = int(round(INSTANCE_CUSTOM.b * 255.0));
	v_base = palette[int(round(INSTANCE_CUSTOM.r * 255.0))];
	v_accent = palette[int(round(INSTANCE_CUSTOM.g * 255.0))];
	v_pattern = packed / 16;
	v_count = packed % 16;
	v_highlight = step(1.5, INSTANCE_CUSTOM.a);
	v_heel_toe = INSTANCE_CUSTOM.a - 2.0 * v_highlight;

	// Soft per-sock folds, so a pile does not look stamped. Normal follows the fold.
	float p = float(INSTANCE_ID) * 1.618;
	vec2 k1 = vec2(17.0 + 6.0 * fract(p), 13.0);
	vec2 k2 = vec2(9.0, 21.0 + 5.0 * fract(p * 3.1));
	float a1 = VERTEX.x * k1.x + p;
	float b1 = VERTEX.z * k1.y + p * 2.0;
	float a2 = VERTEX.x * k2.x + VERTEX.z * k2.y + p * 5.0;
	float f = sin(a1) * cos(b1) + 0.5 * sin(a2);
	// Folds and drape only ever lift the cloth in world space. The body is a flat
	// box, so anything pushed downward would sink into the floor or other socks.
	// Smooth sign, so a tumbling sock does not pop when it turns over.
	float up = clamp(MODEL_MATRIX[1].y / max(length(MODEL_MATRIX[1].xyz), 0.0001) * 4.0, -1.0, 1.0);
	vec2 grad = vec2(
		k1.x * cos(a1) * cos(b1) + 0.5 * k2.x * cos(a2),
		-k1.y * sin(a1) * sin(b1) + 0.5 * k2.y * cos(a2)
	) * crumple * up * 0.5;
	// Each sock sags or arches a little over what it lies on, so it is not a flat strip.
	float bow = up * drape * (0.6 + 0.4 * fract(p * 2.17));
	float r2 = dot(VERTEX.xz, VERTEX.xz);
	float sag = 1.0 - exp(-r2 / 0.03);
	grad += VERTEX.xz * (bow * exp(-r2 / 0.03) * 2.0 / 0.03);
	VERTEX.y += up * (f + 1.5) * 0.5 * crumple + bow * sag;
	NORMAL = normalize(NORMAL + vec3(-grad.x, 0.0, -grad.y) * NORMAL.y);
	// Fold valleys on the face we look at are darker; +1 ridge, -1 valley.
	v_fold = clamp(f * sign(NORMAL.y) / 1.2, -1.0, 1.0) * abs(NORMAL.y);
}

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// One knit stitch is a V of two slanted yarn legs. 0 between legs, 1 on top of a leg.
float knit_v(vec2 st) {
	vec2 c = fract(st);
	float lx = abs(c.x - 0.5) * 2.0;
	float y = fract(c.y - lx * 0.55);
	vec2 q = vec2((lx - 0.5) / 0.6, (y - 0.5) / 0.68);
	return max(1.0 - dot(q, q), 0.0);
}

// Purl side: horizontal bumps, sitting lower.
float purl(vec2 st) {
	vec2 c = fract(st + vec2(0.0, 0.5));
	vec2 q = vec2((c.x - 0.5) / 0.75, (c.y - 0.5) / 0.4);
	return max(1.0 - dot(q, q), 0.0) * 0.55 - 0.35;
}

// Yarn height at a stitch position; rib is the k/p column pattern of the cuff.
float yarn(vec2 st, float rib, float detail) {
	float col = mod(floor(st.x), rib_stitches);
	bool knit_col = col < rib_stitches * 0.5;
	float fine = knit_v(st);
	if (rib > 0.5 && !knit_col) {
		fine = purl(st);
	}
	// Coarse rib ridges stay visible further away than single stitches.
	float ridge = rib * (0.5 + 0.5 * cos(TAU * (st.x - rib_stitches * 0.25) / rib_stitches));
	return mix(0.45, fine, detail) + ridge * 0.9;
}

float band(float x, float half_width, float aa) {
	return 1.0 - smoothstep(half_width - aa, half_width + aa, x);
}

float dot2(vec2 v) {
	return dot(v, v);
}

// Heart with its tip at y = 0 and the lobes near y = 1.
float sd_heart(vec2 p) {
	p.x = abs(p.x);
	if (p.y + p.x > 1.0) {
		return sqrt(dot2(p - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
	}
	return sqrt(min(dot2(p - vec2(0.0, 1.0)), dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

// Five-pointed star, outer radius r, inner share rf, one point up.
float sd_star5(vec2 p, float r, float rf) {
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-k1.x, k1.y);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// Six arms with two side branches each, radius 1.
float sd_snowflake(vec2 p, float width) {
	float r = length(p);
	float a = atan(p.y, p.x);
	a = abs(mod(a + PI / 6.0, PI / 3.0) - PI / 6.0);
	vec2 q = r * vec2(cos(a), sin(a));
	float arm = sd_segment(q, vec2(0.0), vec2(1.0, 0.0));
	float branch = sd_segment(q, vec2(0.55, 0.0), vec2(0.55, 0.0) + 0.32 * vec2(0.5, 0.866));
	return min(arm, branch) - width;
}

// Main pad and four toes, toes up.
float sd_paw(vec2 p) {
	float pad = (length((p - vec2(0.0, -0.22)) / vec2(0.4, 0.32)) - 1.0) * 0.32;
	float toes = min(
		min(length(p - vec2(-0.55, 0.28)), length(p - vec2(0.55, 0.28))),
		min(length(p - vec2(-0.21, 0.62)), length(p - vec2(0.21, 0.62)))
	) - 0.18;
	return min(pad, toes);
}

// Motif grid: local position in the motif's own units (y toward the cuff),
// every other row shifted half a cell so the motifs stagger like knitwear.
vec2 motif_cell(vec2 m, float start, vec2 cell, float size, out vec2 id) {
	vec2 g = vec2(m.x, m.y - start) / cell;
	g.x += 0.5 * mod(floor(g.y), 2.0);
	id = floor(g);
	vec2 local = (fract(g) - 0.5) * cell;
	return vec2(local.x, -local.y) / size;
}

// Rainbow stripes in their own colors; rgb plus how much of it shows.
vec4 rainbow_color(vec2 m, float aa) {
	float start = min(rib_length, 0.03);
	float inside = step(start, m.y) * step(m.y, pattern_end);
	// count 1: thin rainbow bands with base color between, 2: the whole sock in rainbow.
	float row = v_count < 2 ? 0.0065 : 0.016;
	float gap = v_count < 2 ? 4.0 : 0.0;
	float x = (m.y - start) / row;
	float step_index = mod(floor(x), 6.0 + gap);
	vec3 colors[6] = vec3[](
		vec3(0.74, 0.15, 0.16), vec3(0.88, 0.46, 0.16), vec3(0.91, 0.76, 0.2),
		vec3(0.25, 0.55, 0.25), vec3(0.17, 0.33, 0.68), vec3(0.43, 0.25, 0.58)
	);
	float show = step(step_index, 5.5) * inside;
	return vec4(colors[int(min(step_index, 5.0))], show);
}

// x: share of accent color, y: share of the light line color (argyle only).
vec2 pattern_mask(vec2 m, float aa) {
	float s = m.x;
	float d = m.y;
	float count = float(v_count);
	float start = min(rib_length, 0.03);
	if (v_pattern == PATTERN_STRIPES) {
		float span = (pattern_end - start) / count;
		float x = (d - start) / span;
		float half_width = min(span * 0.22, 0.014);
		float inside = step(start, d) * step(d, pattern_end);
		return vec2(band(abs(fract(x) - 0.5) * span, half_width, aa) * inside, 0.0);
	}
	if (v_pattern == PATTERN_DOTS) {
		float spacing = count < 1.5 ? 0.017 : 0.03;
		float radius = count < 1.5 ? 0.0038 : 0.0075;
		vec2 g = vec2(s, d - start) / spacing;
		g.x += 0.5 * mod(floor(g.y), 2.0);
		float dist = length(fract(g) - 0.5) * spacing;
		float inside = step(start, d) * step(d, pattern_end);
		return vec2(band(dist, radius, aa) * inside, 0.0);
	}
	if (v_pattern == PATTERN_CUFF_RINGS) {
		float period = 0.016;
		float x = (d - 0.007) / period;
		float inside = step(0.0, x) * step(x, count);
		return vec2(band(abs(fract(x) - 0.5) * period, 0.0042, aa) * inside, 0.0);
	}
	if (v_pattern == PATTERN_ARGYLE) {
		vec2 size = count < 1.5 ? vec2(0.034, 0.05) : vec2(0.05, 0.075);
		vec2 g = vec2(s, d - start) / size;
		vec2 f = abs(fract(g) - 0.5);
		float diamond = band(f.x + f.y, 0.5, aa / size.x);
		float cell = mod(floor(g.x) + floor(g.y), 2.0);
		float inside = step(start, d) * step(d, pattern_end);
		// Diamonds alternate accent and base, crossed by thin diagonal lines.
		float accent = mix(1.0 - diamond, diamond, cell);
		vec2 h = abs(fract(g + 0.5) - 0.5);
		float line = band(abs(h.x - h.y) * size.x, 0.0012, aa);
		return vec2(accent, line) * inside;
	}
	float inside = step(start, d) * step(d, pattern_end);
	vec2 id;
	if (v_pattern == PATTERN_HEARTS) {
		float size = count < 1.5 ? 0.022 : 0.032;
		vec2 p = motif_cell(m, start, vec2(size * 1.9), size, id);
		return vec2(band(sd_heart(p + vec2(0.0, 0.5)) * size, 0.0, aa) * inside, 0.0);
	}
	if (v_pattern == PATTERN_STARS) {
		float size = count < 1.5 ? 0.015 : 0.022;
		vec2 p = motif_cell(m, start, vec2(size * 2.9, size * 2.6), size, id);
		return vec2(band(sd_star5(p, 1.0, 0.45) * size, 0.0, aa) * inside, 0.0);
	}
	if (v_pattern == PATTERN_ZIGZAG) {
		// Chevrons around the leg; 1 thin lines, 2 bold two-tone bands.
		float period = count < 1.5 ? 0.028 : 0.042;
		float rows = count < 1.5 ? 0.026 : 0.042;
		float half_width = count < 1.5 ? 0.0032 : rows * 0.25;
		float wave = abs(fract(s / period) - 0.5) * period * 0.8;
		float y = d - start - wave;
		float dist = abs(fract(y / rows) - 0.5) * rows;
		return vec2(band(dist, half_width, aa) * inside, 0.0);
	}
	if (v_pattern == PATTERN_SNOWFLAKES) {
		float size = count < 1.5 ? 0.02 : 0.028;
		vec2 p = motif_cell(m, start, vec2(size * 2.5), size, id);
		float width = 0.0026 / size;
		float flake = band(sd_snowflake(p, width) * size, 0.0, aa);
		// Small accent dots between the flakes, like a Nordic jumper.
		vec2 q = motif_cell(m + vec2(size * 1.25, size * 1.25), start, vec2(size * 2.5), size, id);
		float dot_mark = band(length(q) * size, 0.0024, aa);
		return vec2(max(flake, dot_mark) * inside, 0.0);
	}
	if (v_pattern == PATTERN_PAWS) {
		float size = count < 1.5 ? 0.034 : 0.04;
		vec2 p = motif_cell(m, start, vec2(size * 2.4, size * 2.2), size, id);
		// Prints turn a little left and right, like a trail.
		float turn = (mod(id.y, 2.0) < 0.5 ? 0.3 : -0.3);
		p = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * p;
		return vec2(band(sd_paw(p) * size, 0.0, aa) * inside, 0.0);
	}
	return vec2(0.0);
}

float heel_toe_mask(vec2 m, float aa) {
	float toe = smoothstep(toe_at - aa, toe_at + aa, m.y);
	// Heel cup, an oval around the back edge at the bend.
	vec2 q = vec2(m.x / 0.06, (m.y - heel_at) / 0.055);
	float heel = band(length(q), 1.0, aa / 0.055);
	return max(toe, heel);
}

void fragment() {
	vec2 m = UV;
	vec2 cell_size = vec2(stitch_width, row_height);
	vec2 st = m / cell_size;
	vec2 fw = fwidth(st);
	float px = max(fw.x, fw.y);
	// 1 while single stitches are bigger than a pixel, 0 once they blur together.
	float detail = 1.0 - smoothstep(0.15, 0.5, px);
	float rib_view = 1.0 - smoothstep(0.15, 0.5, fw.x / rib_stitches);
	float rib = step(0.0, m.y) * step(m.y, rib_length) * rib_view;

	// Close up, colors change per stitch like real colorwork; far away, smooth edges.
	vec2 stitch_center = (floor(st) + 0.5) * cell_size;
	vec2 pm = mix(m, stitch_center, detail);
	float aa = mix(max(fwidth(m.x), fwidth(m.y)), 0.00001, detail);

	vec2 mask = pattern_mask(pm, aa);
	vec3 color = mix(v_base, v_accent, mask.x);
	color = mix(color, vec3(0.62, 0.6, 0.55), mask.y * 0.85);
	if (v_pattern == PATTERN_RAINBOW) {
		vec4 rainbow = rainbow_color(pm, aa);
		color = mix(color, rainbow.rgb, rainbow.a);
	}
	if (v_heel_toe > 0.5) {
		color = mix(color, v_accent, heel_toe_mask(pm, aa));
	}

	// Yarn relief: height, its slope for the normal, and dark gaps between stitches.
	float h = yarn(st, rib, detail);
	float e = 0.08;
	float hx = (yarn(st + vec2(e, 0.0), rib, detail) - yarn(st - vec2(e, 0.0), rib, detail)) / (2.0 * e);
	float hy = (yarn(st + vec2(0.0, e), rib, detail) - yarn(st - vec2(0.0, e), rib, detail)) / (2.0 * e);
	vec2 slope = vec2(hx / stitch_width, hy / row_height) * yarn_depth * max(detail, rib * 0.6);
	NORMAL = normalize(NORMAL - TANGENT * slope.x - BINORMAL * slope.y);

	float gaps = mix(0.86, 0.66 + 0.34 * clamp(h, 0.0, 1.0), detail);
	gaps *= 1.0 - 0.18 * rib * (1.0 - clamp(h, 0.0, 1.0));
	// Melange yarn: every stitch a little lighter or darker.
	float tone = 1.0 + heather * (hash12(floor(st)) - 0.5) * 2.0 * detail;
	// The faint line where the toe cap starts.
	float seam = 1.0 - 0.22 * detail * band(abs(m.y - toe_at), row_height * 0.6, row_height * 0.3);
	color *= gaps * tone * seam;

	// Inside the opening.
	color *= mix(1.0, 0.22, smoothstep(0.0, -0.008, m.y));

	ALBEDO = color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
	// Soft occlusion in fold valleys and inside the opening; also dims direct light a bit.
	AO = clamp(1.0 - fold_shade * (0.5 - 0.5 * v_fold), 0.0, 1.0) * mix(1.0, 0.4, smoothstep(0.0, -0.01, m.y));
	AO_LIGHT_AFFECT = 0.45;

	// Aimed sock: soft warm glow plus a bright rim, so it stands out from its neighbours.
	if (v_highlight > 0.5) {
		float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		float pulse = 0.85 + 0.15 * sin(TIME * 5.0);
		vec3 warm = vec3(1.0, 0.86, 0.55);
		EMISSION = (mix(color, warm, 0.6) * highlight_glow + warm * edge * highlight_rim) * pulse;
	}
}

// Cloth light: wrapped diffuse for the soft look of fabric, a fuzzy sheen at grazing angles.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diffuse = max((ndl + wrap) / (1.0 + wrap), 0.0);
	DIFFUSE_LIGHT += diffuse * ATTENUATION * LIGHT_COLOR / PI;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float lit = clamp(ndl + 0.5, 0.0, 1.0);
	SPECULAR_LIGHT += rim * lit * sheen * ATTENUATION * LIGHT_COLOR / PI * mix(ALBEDO, vec3(1.0), 0.35);
}
