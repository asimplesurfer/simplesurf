// Lluvia de tormenta sobre la vista: tres capas de gotas en diagonal (cerca,
// medio, lejos) que caen a distinta velocidad, con un velo gris y el
// relámpago encima. Es un rectángulo por vista, así cada pantalla tiene la suya.
shader_type canvas_item;

uniform float intensity = 1.0;
// Inclinación por el viento.
uniform float wind = 0.28;
uniform float flash = 0.0;
uniform vec4 veil : source_color = vec4(0.12, 0.15, 0.2, 0.16);

float h(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// Una capa de gotas: columnas con gotas largas que bajan.
float drops(vec2 uv, float cols, float speed, float len, float width, float t) {
	uv.x += uv.y * wind;
	vec2 p = vec2(uv.x * cols, uv.y * cols * 0.12);
	float c = floor(p.x);
	float r = h(c + 0.37);
	p.y -= t * speed * (0.75 + 0.5 * r) + r * 17.0;
	float cell = floor(p.y);
	float f = fract(p.y);
	float x = fract(p.x) - 0.5 - (h(c + cell * 3.1) - 0.5) * 0.5;
	float line = 1.0 - smoothstep(width * 0.4, width, abs(x));
	float body = smoothstep(0.0, 0.05, f) * (1.0 - smoothstep(len * 0.6, len, f));
	float on = step(0.3, h(c * 1.7 + cell * 7.13));
	return line * body * on;
}

void fragment() {
	vec2 px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = vec2(UV.x * px.x / px.y, UV.y);
	float t = TIME;
	float a = drops(uv, 46.0, 9.0, 0.5, 0.09, t) * 0.65;
	a = max(a, drops(uv + vec2(0.31, 0.0), 90.0, 13.0, 0.35, 0.12, t) * 0.38);
	a = max(a, drops(uv + vec2(0.71, 0.0), 160.0, 18.0, 0.3, 0.16, t) * 0.32);
	a *= intensity;
	vec3 rain = vec3(0.82, 0.87, 0.95);
	vec4 col = vec4(veil.rgb, veil.a * intensity);
	col = mix(col, vec4(rain, 1.0), a);
	col.rgb = mix(col.rgb, vec3(0.92, 0.95, 1.0), flash * 0.5);
	col.a = max(col.a, flash * 0.18);
	COLOR = col;
}
