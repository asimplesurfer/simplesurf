shader_type spatial;
render_mode cull_disabled, unshaded, shadows_disabled;
// La ola tubo, con el estilo del agua del juego (colores planos, espuma
// blanca). UV.x: dónde está en el corte (0 = abajo del lado abierto, 1 = la
// punta del labio); UV.y: metros a lo largo del tubo.
// - el agua sube por la pared (rayas que corren hacia arriba);
// - el labio es espuma blanca, con borde irregular;
// - adelante, la luz de la salida ilumina el interior (más cerca, más fuerte);
// - atrás, la ola ya rompió: espuma.

uniform vec4 deep : source_color = vec4(0.04, 0.30, 0.46, 1.0);
uniform vec4 face : source_color = vec4(0.16, 0.68, 0.78, 1.0);
uniform vec4 thin : source_color = vec4(0.55, 0.92, 0.90, 1.0);
uniform vec4 foam : source_color = vec4(0.95, 0.99, 1.0, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.97, 0.82, 1.0);
// Tramo dibujado (m): desde la espuma de atrás hasta la salida.
uniform float back_s = 0.0;
uniform float front_s = 30.0;
// 0..1: qué tan cerca está la salida (más luz).
uniform float exit_light = 0.0;
// Velocidad del tubo (m/s): las rayas corren con el agua.
uniform float flow = 18.0;
// Día 1; de noche, más oscuro.
uniform float brightness = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float t = UV.x;
	float s = UV.y;
	// Colores por altura: hondo abajo, turquesa en la cara, fino (casi
	// transparente al sol) cerca del labio.
	vec3 col = mix(deep.rgb, face.rgb, smoothstep(0.05, 0.42, t));
	col = mix(col, thin.rgb, smoothstep(0.5, 0.82, t));
	// El agua sube por la pared: rayas que corren hacia arriba y hacia atrás.
	float streak = noise(vec2(s * 0.35 + TIME * flow * 0.02, t * 14.0 - TIME * 2.2));
	col = mix(col, thin.rgb, step(0.72, streak) * smoothstep(0.25, 0.5, t) * 0.55);
	// Espuma en el labio (borde irregular que se mueve).
	float edge = 0.86 + 0.05 * (noise(vec2(s * 0.8 - TIME * 1.5, TIME * 0.7)) - 0.5) * 2.0;
	float lip = step(edge, t);
	// Espuma de la base (donde la ola junta agua abajo, del lado abierto).
	float base_foam = step(t, 0.06 + 0.04 * noise(vec2(s * 0.6 + TIME * 2.0, 3.0)));
	// Atrás la ola ya rompió: espuma que avanza.
	float broken = 1.0 - smoothstep(back_s + 1.0, back_s + 5.0 + 2.0 * noise(vec2(t * 8.0, TIME * 3.0)), s);
	float foam_k = max(max(lip, base_foam * 0.8), broken);
	col = mix(col, foam.rgb, foam_k);
	// Luz de la salida: ilumina el interior de adelante (más cerca, más fuerte).
	float near_exit = smoothstep(front_s - 14.0 - 10.0 * (1.0 - exit_light), front_s, s);
	col += glow.rgb * near_exit * (0.25 + 0.55 * exit_light) * (1.0 - foam_k * 0.5);
	// Adentro se ve un poco más oscuro (sombra del labio), afuera normal.
	float inside = FRONT_FACING ? 0.0 : 1.0;
	col *= mix(1.0, 0.82, inside * (1.0 - near_exit));
	// Plano (como el resto del juego): sin luces, solo el color.
	ALBEDO = col * brightness;
}
