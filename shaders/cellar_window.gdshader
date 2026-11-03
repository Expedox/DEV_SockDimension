shader_type spatial;

// Night sky behind a cellar window, with rain running down the glass.

uniform vec3 sky : source_color = vec3(0.5, 0.61, 0.77);
uniform float glow = 1.4;
uniform float rain = 1.0;
uniform float streaks = 26.0;
uniform float speed = 0.35;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float column = floor(uv.x * streaks);
	float offset = hash(column);
	float fall = fract(uv.y * 1.5 - TIME * speed * (0.6 + offset) + offset * 7.0);
	float width = 1.0 - abs(fract(uv.x * streaks) - 0.5) * 2.0;
	// A drop with a thin trail above it; only some columns carry water.
	float drop = smoothstep(0.82, 1.0, fall) * smoothstep(0.55, 0.9, width);
	float trail = smoothstep(0.3, 1.0, fall) * smoothstep(0.75, 1.0, width) * 0.35;
	float wet = (drop + trail) * step(0.45, hash(column + 13.0)) * rain;
	// Water bends the light: drops look darker in the middle, brighter at the rim.
	vec3 color = sky * (1.0 - wet * 0.45) + vec3(0.9, 0.95, 1.0) * drop * 0.25 * rain;
	ALBEDO = sky * 0.4;
	EMISSION = color * glow;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
}
