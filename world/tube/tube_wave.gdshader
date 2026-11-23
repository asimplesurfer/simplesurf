shader_type spatial;
render_mode cull_disabled, unshaded, shadows_disabled;
// La ola tubo, con los colores del mar del juego (planos, con espuma blanca).
// UV.x: zona del corte (0 = la cara lejos, 1 = la punta del labio, 2 = el fin
// de la espalda). UV.y: metros a lo largo del tubo. UV2.x: altura (m) sobre el
// agua; UV2.y: qué tan cerrado está el tubo ahí (0 abierto, 1 tubo).
// - luz falsa según hacia dónde mira la superficie (la ola tiene volumen);
// - el agua se aclara hacia arriba (fina, al trasluz) y sube por la pared en rayas;
// - espuma en la punta del labio y en la cresta; adentro, más oscuro;
// - adelante, la luz de la salida ilumina el interior;
// - atrás, la ola ya rompió: espuma.

uniform vec3 base_color : source_color = vec3(0.16, 0.42, 0.66);
uniform vec3 face_color : source_color = vec3(0.18, 0.62, 0.74);
uniform vec3 thin_color : source_color = vec3(0.45, 0.86, 0.86);
uniform vec3 back_color : source_color = vec3(0.22, 0.55, 0.78);
uniform vec3 foam_color : source_color = vec3(0.95, 0.99, 1.0);
uniform vec3 glow_color : source_color = vec3(1.0, 0.96, 0.8);
uniform vec3 sun_dir = vec3(0.4, 0.75, 0.5);
uniform float back_s = 0.0;
uniform float front_s = 30.0;
uniform float exit_light = 0.0;
uniform float flow = 18.0;
uniform float brightness = 1.0;

varying vec3 world_n;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// La malla está en coordenadas del mundo.
	world_n = NORMAL;
}

void fragment() {
	float zone = UV.x;
	float s = UV.y;
	float h = UV2.x;
	float closed = UV2.y;
	vec3 n = normalize(world_n);
	if (!FRONT_FACING) {
		n = -n;
	}
	// Cara y techo (zona < 1) o espalda (zona > 1).
	float front_side = 1.0 - step(1.0, zone);
	vec3 col = mix(base_color, face_color, smoothstep(0.3, 2.5, h));
	col = mix(col, thin_color, smoothstep(2.8, 5.5, h) * front_side);
	// La espalda: más clara arriba, con franjas suaves a lo largo (el agua que sube).
	float back_bands = noise(vec2(s * 0.12, zone * 10.0 + TIME * 0.4));
	vec3 back = mix(back_color, face_color, smoothstep(2.0, 6.5, h) * 0.6 + back_bands * 0.15);
	col = mix(col, back, 1.0 - front_side);
	// El agua sube por la pared: rayas claras que corren hacia arriba.
	float streak = noise(vec2(s * 0.45 + TIME * flow * 0.03, h * 2.2 - TIME * 3.0));
	col = mix(col, thin_color, step(0.74, streak) * smoothstep(0.8, 2.5, h) * front_side * 0.6);
	// Luz falsa: más clara mirando al sol, más oscura en sombra.
	float light = 0.86 + 0.24 * clamp(dot(n, normalize(sun_dir)), 0.0, 1.0);
	col *= light;
	// Adentro del tubo (el techo y la pared tapados por el labio), más oscuro.
	float under_lip = front_side * smoothstep(0.55, 0.85, zone) * closed;
	col *= mix(1.0, 0.78, under_lip);
	// Espuma: la punta del labio (una franja pareja, con el borde de adentro
	// irregular y moviéndose).
	float edge = 0.965 + 0.025 * noise(vec2(s * 0.8 - TIME * 1.8, TIME * 0.5));
	float lip = step(edge, zone) * (1.0 - step(1.045, zone)) * smoothstep(0.3, 0.7, closed);
	// Atrás la ola ya rompió: manchas de espuma que se van comiendo la ola.
	float churn = noise(vec2(s * 0.9 + TIME * 3.0, zone * 7.0 - TIME * 2.0));
	float broken = step(churn, 1.25 * (1.0 - smoothstep(back_s - 6.0, back_s + 2.0, s)) - 0.05) * step(0.1, h);
	float foam_k = clamp(max(lip, broken), 0.0, 1.0);
	col = mix(col, foam_color * (0.9 + 0.1 * light), foam_k);
	// Luz de la salida: ilumina el interior de adelante.
	float near_exit = smoothstep(front_s - 30.0 + 10.0 * exit_light, front_s - 10.0, s) * front_side;
	col += glow_color * near_exit * (0.18 + 0.45 * exit_light) * (1.0 - foam_k);
	ALBEDO = col * brightness;
}
