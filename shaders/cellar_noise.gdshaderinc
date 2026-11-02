// Shared noise for the cellar shaders. Gradient noise with a quintic fade,
// so stains stay round instead of showing the diagonal facets of value noise.

vec2 cellar_hash2(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.xx + q.yz) * q.zy) * 2.0 - 1.0;
}

float cellar_hash1(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// Returns roughly -1..1.
float cellar_gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(cellar_hash2(i), f);
	float b = dot(cellar_hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(cellar_hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(cellar_hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return 1.4 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Returns roughly 0..1.
float cellar_fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float total = 0.0;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * cellar_gnoise(p);
		total += amplitude;
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.07 + vec2(17.3, 9.1);
		amplitude *= 0.5;
	}
	return value / total * 0.5 + 0.5;
}

// Organic blotches: fbm sampled through a slowly warped domain.
float cellar_warped(vec2 p) {
	vec2 warp = vec2(cellar_fbm(p + vec2(3.1, 7.4), 3), cellar_fbm(p + vec2(8.3, 1.7), 3));
	return cellar_fbm(p + (warp - 0.5) * 2.4, 4);
}
