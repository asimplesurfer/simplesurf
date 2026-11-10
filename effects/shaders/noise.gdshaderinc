// Ruido simple compartido por los efectos de agua.
float fx_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float fx_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fx_hash(i);
	float b = fx_hash(i + vec2(1.0, 0.0));
	float c = fx_hash(i + vec2(0.0, 1.0));
	float d = fx_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
