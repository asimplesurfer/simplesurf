shader_type spatial;
// La ola tubo, pintada como el agua del mar (water.gdshader): con la luz de la
// escena, el reflejo del cielo, el turquesa de las olas grandes, la luz que
// atraviesa la parte fina y la espuma con el mismo grano. Los colores son los
// del agua en ese momento (TubeWave los copia del material del agua: cambian
// con la hora y la tormenta).
// UV.x: zona del corte (0 = la cara lejos, 1 = la punta del labio, 2 = el fin
// de la espalda). UV.y: metros a lo largo del tubo. UV2.x: altura (m) sobre el
// agua; UV2.y: qué tan cerrado está el tubo ahí (0 abierto, 1 tubo).
render_mode specular_schlick_ggx, cull_disabled, shadows_disabled;

#include "res://effects/shaders/noise.gdshaderinc"

// Los mismos que el agua (se copian del material del agua).
uniform vec3 deep_color : source_color = vec3(0.03, 0.2, 0.34);
uniform vec3 shallow_color : source_color = vec3(0.08, 0.35, 0.48);
uniform vec3 wave_color : source_color = vec3(0.14, 0.55, 0.6);
uniform vec3 glow_color : source_color = vec3(0.25, 0.95, 0.8);
uniform float glow_strength = 0.25;
uniform vec3 foam_color : source_color = vec3(0.93, 0.98, 1.0);
uniform vec3 sky_tint : source_color = vec3(0.6, 0.76, 0.86);
uniform float sky_reflect = 0.42;

uniform float back_s = 0.0;
uniform float front_s = 30.0;
// 0..1: qué tan cerca está la salida (más luz adentro).
uniform float exit_light = 0.0;
// 0..1: la ola se desarma (se vuelve espuma).
uniform float collapse = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = VERTEX;
}

void fragment() {
	float zone = UV.x;
	float s = UV.y;
	float h = UV2.x;
	float closed = UV2.y;
	float t = TIME;
	vec2 wp = v_world.xz;
	// La ola es una sola lámina doblada en el labio: de un lado la normal mira
	// hacia adentro de la ola. Siempre hacia la cámara (si no, la luz y el
	// reflejo del cielo la dejan gris).
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	float front_side = 1.0 - step(1.0, zone);
	// Como una ola grande del mar: abajo el agua de siempre, el cuerpo turquesa.
	float body = smoothstep(0.2, 2.2, h);
	// Abajo, el azul del mar tal como se ve (más vivo que el color crudo del
	// agua: al mar lo aclara el reflejo del cielo, que de frente no hay).
	vec3 sea = mix(shallow_color, wave_color, 0.35) * 1.4;
	vec3 col = mix(shallow_color * 1.3, sea, smoothstep(0.0, 0.8, h));
	float patches = fx_noise(wp * 0.035 + vec2(t * 0.01, 0.0));
	col = mix(col, col * vec3(0.85, 1.05, 1.08), patches * 0.5);
	col = mix(col, wave_color * 1.25, body * 0.8);
	// Luz que atraviesa la parte fina (cerca de la cresta y en el labio): un
	// turquesa más claro y transparente (mezclado, no sumado: sin neón).
	float thin = clamp(smoothstep(2.2, 5.6, h) + smoothstep(0.8, 0.97, zone), 0.0, 1.0) * front_side;
	vec3 lit_water = mix(wave_color, glow_color, 0.45) * 1.15;
	col = mix(col, lit_water, thin * 0.6);
	// Adentro del tubo, bajo el labio, un poco más oscuro (la sombra del labio).
	col *= mix(1.0, 0.85, front_side * smoothstep(0.55, 0.85, zone) * closed);
	// El agua sube por la pared: vetas finas de espuma a lo largo del tubo.
	float lane = h * 3.2 - t * 1.6 + fx_noise(vec2(s * 0.05, 7.0)) * 2.0;
	float vein = (1.0 - smoothstep(0.02, 0.07, abs(fract(lane) - 0.5)))
		* step(0.45, fx_noise(vec2(s * 0.08 - t * 0.4, floor(lane))));
	float streak = vein * smoothstep(0.6, 2.2, h) * front_side * 0.35;

	// Reflejo del cielo en ángulos rasantes (como el mar).
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 4.0);
	// (Adentro del tubo menos: si no, el techo se ve lavado.)
	col = mix(col, sky_tint, fresnel * sky_reflect * mix(1.0, 0.3, front_side * closed));

	// Espuma con el grano del mar: la punta del labio (borde que se deshace),
	// donde ya rompió (atrás) y al desarmarse.
	float n1 = fx_noise(wp * 0.9 + vec2(t * 0.35, t * 0.2));
	float n2 = fx_noise(wp * 2.3 - vec2(t * 0.25, t * 0.4));
	float grain = n1 * 0.65 + n2 * 0.35;
	float lip_band = smoothstep(0.93, 0.99, zone) * (1.0 - smoothstep(1.03, 1.1, zone)) * smoothstep(0.3, 0.7, closed);
	float foam = lip_band * smoothstep(0.2, 0.5, grain + lip_band * 0.45);
	float churn = fx_noise(vec2(s * 0.9 + t * 3.0, zone * 7.0 - t * 2.0));
	float broken = step(churn, 1.25 * (1.0 - smoothstep(back_s - 6.0, back_s + 2.0, s)) - 0.05) * step(0.1, h);
	float crumble = step(churn, collapse * 1.6) * step(0.05, h);
	foam = max(foam, max(broken, crumble));
	foam = max(foam, streak);
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0) * 0.9);

	// Destellos del sol, como en el mar.
	float sparkle = step(0.95, fx_noise(wp * 3.5 + vec2(t * 0.9, -t * 0.7)))
		* step(0.7, fx_noise(wp * 1.3 - t * 0.5));
	sparkle *= (1.0 - clamp(foam, 0.0, 1.0)) * (0.3 + fresnel * 1.5) * (1.0 - front_side * closed * 0.7);

	// Luz de la salida: ilumina el interior de adelante (solo adentro del tubo).
	float near_exit = smoothstep(front_s - 30.0 + 10.0 * exit_light, front_s - 12.0, s) * front_side * closed;

	// La luz de la escena le da volumen, pero sin que la cara en sombra quede
	// gris: una parte del color va siempre (como el agua, que nunca es oscura).
	ALBEDO = col * 0.5;
	EMISSION = col * 0.55 + vec3(sparkle * 0.7) + glow_color * near_exit * (0.06 + 0.2 * exit_light) * (1.0 - clamp(foam, 0.0, 1.0));
	// Más difusa que el mar: una superficie tan grande y lisa con el brillo del
	// mar se vuelve un manchón blanco a contraluz.
	ROUGHNESS = mix(0.55, 0.8, clamp(foam, 0.0, 1.0));
	SPECULAR = 0.2;
}
