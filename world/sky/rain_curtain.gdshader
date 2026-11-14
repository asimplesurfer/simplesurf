// Cortina de lluvia: un cilindro alrededor de la cámara con gotas que bajan.
// Dos cortinas a distinta distancia (y las gotas 3D de cerca) dan profundidad;
// la niebla apaga las de lejos.
// rain_time va de 0 a 1 y vuelve a 0 sin salto (las velocidades son enteras),
// así nunca hay números grandes que rompan el dibujo después de mucho rato.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float rain_time = 0.0;
uniform float columns = 90.0;
uniform float rows = 10.0;
uniform vec4 tint : source_color = vec4(0.78, 0.83, 0.9, 0.35);

float h(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 uv = vec2(UV.x * columns, UV.y * rows);
	uv.x += uv.y * 0.12;
	float c = mod(floor(uv.x), columns);
	float r = h(c + 0.5);
	float speed = 2.0 + floor(r * 3.0);
	float y = uv.y - rain_time * speed + r * 7.0;
	float cell = floor(y);
	float f = y - cell;
	float x = fract(uv.x) - 0.5 - (h(c + 3.7) - 0.5) * 0.4;
	// Rayas cortas y nítidas (las largas y borrosas parecen niebla, no lluvia).
	float line = 1.0 - smoothstep(0.015, 0.04, abs(x));
	float body = smoothstep(0.0, 0.5, f / 0.09) * (1.0 - step(0.09, f));
	float on = step(0.45, h(c * 1.31 + mod(cell, 32.0) * 7.13));
	float a = line * body * on * tint.a;
	// Se apaga arriba y abajo (no se ven los bordes del cilindro).
	a *= smoothstep(0.0, 0.2, UV.y) * (1.0 - smoothstep(0.7, 0.95, UV.y));
	ALBEDO = tint.rgb;
	ALPHA = a;
}
