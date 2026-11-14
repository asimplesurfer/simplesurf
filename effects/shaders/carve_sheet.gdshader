// Pared de agua al girar rápido, en estilo cartoon (como el resto del juego):
// formas nítidas en dos tonos (blanco al centro, celeste en el borde), un labio
// de espuma arriba y gotas que se desprenden de la punta. Nada borroso.
// UV.x = de un lado al otro, UV.y = distancia desde la tabla (0..1).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://effects/shaders/noise.gdshaderinc"

uniform vec3 foam : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 water : source_color = vec3(0.62, 0.9, 1.0);
uniform float intensity = 1.0;
uniform float flow_time = 0.0;

void fragment() {
	float s = UV.y;
	float t = abs(UV.x * 2.0 - 1.0);
	float flow = flow_time * 6.0;
	// Manchas grandes que corren hacia afuera (el cuerpo del agua).
	float body = fx_noise(vec2(UV.x * 5.0, s * 2.5 - flow));
	float detail = fx_noise(vec2(UV.x * 13.0, s * 7.0 - flow * 1.4));
	float n = body * 0.7 + detail * 0.3;
	// La forma: llena cerca de la tabla, se rompe en pedazos hacia la punta.
	float edge_soft = 0.04;
	float cut = 0.25 + 0.5 * s + 0.35 * t * t;
	float shape = smoothstep(cut - edge_soft, cut + edge_soft, n + 0.35 * (1.0 - s));
	shape *= 1.0 - smoothstep(0.8, 1.0, t);
	shape *= smoothstep(0.0, 0.06, s);
	shape *= 1.0 - smoothstep(0.75 * intensity + 0.1, 0.75 * intensity + 0.25, s);
	// Dos tonos: el centro de cada mancha blanco, el borde celeste.
	float core = smoothstep(cut + 0.12, cut + 0.16, n + 0.35 * (1.0 - s));
	// Labio de espuma: una franja blanca arriba de la pared (UV.x cerca del borde de arriba).
	vec3 col = mix(water, foam, core);
	ALBEDO = col;
	ALPHA = shape * mix(0.75, 0.95, core) * clamp(intensity * 1.6, 0.0, 1.0);
}
