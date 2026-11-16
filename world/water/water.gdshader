// Agua falsa: un plano subdividido cuyos vértices suben y bajan.
// La forma de la superficie está en water_surface.gdshaderinc (la misma que la física).
shader_type spatial;
// cull_disabled: la cresta que se curva puede quedar "dada vuelta".
render_mode specular_schlick_ggx, cull_disabled;

#include "res://effects/shaders/noise.gdshaderinc"

#include "res://world/water/water_surface.gdshaderinc"
// Pista (centro x, centro z, radio de adentro, radio de afuera). 0 = sin pista.
uniform vec4 track_band = vec4(0.0);
uniform vec3 outside_color : source_color = vec3(0.03, 0.15, 0.27);
// Pista con curvas: máscara vista desde arriba (1 = pista) sobre el rectángulo
// track_mask_rect (x, z de la esquina; ancho, largo). Ancho 0 = sin máscara.
uniform sampler2D track_mask : filter_linear, repeat_disable;
uniform vec4 track_mask_rect = vec4(0.0);
// Cuánto se oscurece el agua fuera de la pista.
uniform float outside_strength = 0.8;
// Bruma: lejos, el agua se vuelve del color del horizonte (llega a ese color
// donde termina lo que ve la cámara, así no se nota el borde).
uniform vec3 haze_color : source_color = vec3(0.93, 0.9, 0.96);
uniform vec2 haze_range = vec2(170.0, 310.0);

uniform vec3 deep_color : source_color = vec3(0.03, 0.2, 0.34);
uniform vec3 shallow_color : source_color = vec3(0.08, 0.35, 0.48);
uniform vec3 foam_color : source_color = vec3(0.93, 0.98, 1.0);
uniform float foam_height = 0.42;
uniform vec3 wave_color : source_color = vec3(0.14, 0.55, 0.6);
// Agua donde se está por levantar una ola (más oscura, como una sombra).
uniform vec3 rising_color : source_color = vec3(0.02, 0.14, 0.28);
// Luz que atraviesa la parte fina de la ola (cerca de la cresta).
uniform vec3 glow_color : source_color = vec3(0.25, 0.95, 0.8);
uniform float glow_strength = 0.25;
// Color del cielo que se refleja en ángulos rasantes.
uniform vec3 sky_tint : source_color = vec3(0.6, 0.76, 0.86);
// Cuánto refleja el cielo en ángulos rasantes (la tormenta usa 0,6).
uniform float sky_reflect = 0.42;
// Lluvia pegando en el mar (0 = no llueve): circulitos que se abren donde cae
// una gota, con un puntito de salpicadura al principio.
uniform float rain_ripples = 0.0;

varying float v_height;
// 0..1: cuerpo de una ola grande (para el color turquesa de la ola).
varying float v_body;
// 0..1: espuma de la ola que rompe (labio y cara).
varying float v_lip;
// 0..1: ola que todavía está creciendo ("se viene"): el agua se oscurece donde
// se va a levantar, aunque todavía no tenga altura.
varying float v_grow;
varying vec3 v_world;

// Una capa de gotas: en cada celda cae una gota cada tanto (en un lugar y
// momento al azar) y abre un anillo que se desvanece.
float rain_layer(vec2 p, float t, float cell, float seed) {
	vec2 g = p / cell;
	vec2 id = floor(g);
	vec2 f = g - id;
	float h1 = fx_hash(id + seed);
	float h2 = fx_hash(id + seed + 17.3);
	float h3 = fx_hash(id + seed + 41.7);
	vec2 c = vec2(0.2) + 0.6 * vec2(h1, h2);
	float life = fract(t * (0.8 + 0.5 * h3) + h3 * 7.0);
	float d = length(f - c);
	float r = 0.06 + life * 0.38;
	float ring = (1.0 - smoothstep(0.0, 0.028, abs(d - r))) * (1.0 - life) * (1.0 - life);
	float splash = (1.0 - smoothstep(0.0, 0.07, d)) * (1.0 - smoothstep(0.0, 0.14, life));
	return max(ring, splash);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h;
	vec2 g;
	vec2 disp;
	float ambient_h;
	float body;
	float lip;
	float grow;
	water_surface(world.xz, h, g, disp, ambient_h, body, lip, grow);
	// Lejos del centro del plano el agua se aplana (después vienen los anillos
	// enormes hasta el horizonte, que no pueden seguir las olas).
	float calm = 1.0 - smoothstep(95.0, 125.0, distance(world.xz, NODE_POSITION_WORLD.xz));
	h *= calm;
	g *= calm;
	disp *= calm;
	body *= calm;
	lip *= calm;
	grow *= calm;
	ambient_h *= calm;
	VERTEX.y += h;
	VERTEX.xz += disp;
	NORMAL = normalize(vec3(-g.x, 1.0, -g.y));
	v_height = ambient_h;
	v_body = body;
	v_lip = lip;
	v_grow = grow;
	v_world = world + vec3(disp.x, h, disp.y);
}

void fragment() {
	float t = fx_time;
	vec2 wp = v_world.xz;
	// Color base: valles profundos, crestas claras.
	vec3 col = mix(deep_color, shallow_color, smoothstep(-0.5, 0.5, v_height));
	// Manchas suaves de color (el mar no es de un solo tono).
	float patches = fx_noise(wp * 0.035 + vec2(t * 0.01, 0.0));
	col = mix(col, col * vec3(0.85, 1.05, 1.08), patches * 0.5);
	// Olas grandes: cuerpo turquesa (se ve la ola de lejos). Mientras crece
	// ("se viene") es más oscura y sin espuma; al llegar al máximo rompe y se
	// llena de espuma arriba y en la cara.
	col = mix(col, rising_color, v_grow * 0.55);
	col = mix(col, wave_color, v_body * 0.75);
	// Luz que atraviesa la parte fina de la ola, cerca de la cresta.
	col += glow_color * v_body * v_body * glow_strength;

	// Reflejo del cielo en ángulos rasantes (fresnel): el mar de lejos brilla.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 4.0);
	col = mix(col, sky_tint, fresnel * sky_reflect);

	// Espuma con textura: se deshace en bordes irregulares y se mueve.
	float n1 = fx_noise(wp * 0.9 + vec2(t * 0.35, t * 0.2));
	float n2 = fx_noise(wp * 2.3 - vec2(t * 0.25, t * 0.4));
	float grain = n1 * 0.65 + n2 * 0.35;
	float crest = smoothstep(foam_height - 0.05, foam_height + 0.2, v_height);
	// Solo en algunas zonas (que se mueven despacio), así no se ve un patrón.
	crest *= smoothstep(0.22, 0.6, fx_noise(wp * 0.025 + vec2(t * 0.03, -t * 0.02)));
	float foam = crest * smoothstep(0.62, 0.8, grain + crest * 0.25);
	float lip = clamp(v_lip, 0.0, 1.0);
	foam = max(foam, lip * smoothstep(0.15, 0.45, grain + lip * 0.5));
	// Vetas finas de espuma que flotan en el agua (marcan el movimiento).
	float streak = smoothstep(0.78, 0.82, fx_noise(wp * vec2(0.18, 0.6) + vec2(t * 0.05, 0.0)));
	foam = max(foam, streak * 0.35 * (1.0 - v_body));
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0) * 0.9);

	// Lluvia: gotas pegando en el agua (solo cerca: de lejos no se distinguen).
	if (rain_ripples > 0.0) {
		float near = 1.0 - smoothstep(18.0, 40.0, distance(v_world, CAMERA_POSITION_WORLD));
		if (near > 0.0) {
			float tt = mod(t, 600.0);
			float drops = max(rain_layer(wp, tt, 1.4, 0.0), rain_layer(wp + 0.7, tt * 1.13, 1.1, 5.0));
			col = mix(col, foam_color, drops * near * rain_ripples * 0.4);
		}
	}

	// Destellos del sol: puntitos que titilan.
	float sparkle = step(0.95, fx_noise(wp * 3.5 + vec2(t * 0.9, -t * 0.7)))
		* step(0.7, fx_noise(wp * 1.3 - t * 0.5));
	sparkle *= (1.0 - clamp(foam, 0.0, 1.0)) * (0.3 + fresnel * 1.5);

	// Fuera de la pista, el agua más oscura (con un borde suave).
	if (track_band.w > 0.0) {
		float d = distance(v_world.xz, track_band.xy);
		float out_inner = 1.0 - smoothstep(track_band.z - 3.0, track_band.z - 0.5, d);
		float out_outer = smoothstep(track_band.w + 0.5, track_band.w + 3.0, d);
		float outside = max(out_inner, out_outer);
		col = mix(col, outside_color, outside * outside_strength);
	} else if (track_mask_rect.z > 0.0) {
		vec2 uv = (v_world.xz - track_mask_rect.xy) / track_mask_rect.zw;
		float inside = 0.0;
		if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
			inside = texture(track_mask, uv).r;
		}
		float outside = 1.0 - smoothstep(0.25, 0.75, inside);
		col = mix(col, outside_color, outside * outside_strength);
	}

	float haze = smoothstep(haze_range.x, haze_range.y, distance(v_world, CAMERA_POSITION_WORLD));
	col = mix(col, haze_color, haze);
	ALBEDO = col;
	EMISSION = vec3(sparkle * 0.7 * (1.0 - haze));
	ROUGHNESS = mix(0.26, 0.7, clamp(foam, 0.0, 1.0));
	SPECULAR = 0.38;
}
