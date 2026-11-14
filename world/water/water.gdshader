// Agua falsa: un plano subdividido cuyos vértices suben y bajan.
// La fórmula es la misma que wave_definition.gd (no cambiar una sin la otra).
shader_type spatial;
// cull_disabled: la cresta que se curva puede quedar "dada vuelta".
render_mode specular_schlick_ggx, cull_disabled;

#include "res://effects/shaders/noise.gdshaderinc"

uniform vec4 wave_0; // xy = dirección, z = amplitud, w = longitud de onda
uniform vec4 wave_1;
uniform vec4 wave_2;
uniform vec4 wave_3;
uniform float speed_scale = 1.0;
uniform float wave_time = 0.0; // lo actualiza water.gd cada frame

// Olas grandes (ver swell.gd). a = (centro.x, centro.z, dir.x, dir.z); b = (amplitud, ancho, medio largo, rompiente 0..1)
uniform vec4 swell_a0; uniform vec4 swell_b0;
uniform vec4 swell_a1; uniform vec4 swell_b1;
uniform vec4 swell_a2; uniform vec4 swell_b2;
uniform vec4 swell_a3; uniform vec4 swell_b3;
uniform vec4 swell_a4; uniform vec4 swell_b4;
uniform vec4 swell_a5; uniform vec4 swell_b5;
uniform vec4 swell_a6; uniform vec4 swell_b6;
uniform vec4 swell_a7; uniform vec4 swell_b7;
// Ola constante (ver ring_wave.gd). a = (centro.x, centro.z, radio, ancho); b = (amplitud, base, lóbulos, fase)
uniform vec4 ring_a = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 ring_b = vec4(0.0);
// Islas (x, z, radio): las olas grandes se apagan cerca de cada orilla.
uniform vec3 islands[16];
uniform int island_count = 0;
// Pista (centro x, centro z, radio de adentro, radio de afuera). 0 = sin pista.
uniform vec4 track_band = vec4(0.0);
uniform vec3 outside_color : source_color = vec3(0.03, 0.15, 0.27);

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

// Para que el oleaje no forme un enrejado que se repite, cada onda se tuerce
// (sus crestas se curvan) y crece y baja por zonas (series de olas), cada una
// distinto. Mismos números que wave_definition.gd.
const vec2 WARP_A[4] = vec2[](vec2(0.023, 0.031), vec2(-0.033, 0.017), vec2(0.027, -0.026), vec2(-0.019, -0.035));
const vec2 WARP_B[4] = vec2[](vec2(-0.029, 0.021), vec2(0.018, 0.034), vec2(-0.031, -0.022), vec2(0.036, -0.012));
const vec2 GROUP[4] = vec2[](vec2(0.011, 0.014), vec2(-0.016, 0.008), vec2(0.009, -0.015), vec2(-0.013, -0.012));
const float SEED[4] = float[](0.0, 2.1, 4.3, 1.2);

void add_wave(vec4 w, int i, vec2 p, inout float h, inout vec2 g) {
	if (w.w <= 0.0) {
		return;
	}
	float k = 6.28318530718 / w.w;
	float omega = sqrt(9.8 * k) * speed_scale;
	float wa = 0.22 * w.w;
	float s1 = dot(p, WARP_A[i]) + SEED[i];
	float s2 = dot(p, WARP_B[i]) + SEED[i] * 1.37;
	vec2 q = p + wa * vec2(sin(s1), sin(s2));
	float phase = k * dot(w.xy, q) - omega * wave_time;
	vec2 dphase = k * (w.xy + w.x * wa * cos(s1) * WARP_A[i] + w.y * wa * cos(s2) * WARP_B[i]);
	float sg = dot(p, GROUP[i]) + SEED[i] * 1.7;
	float m = 0.65 + 0.35 * sin(sg);
	vec2 dm = 0.35 * cos(sg) * GROUP[i];
	h += w.z * m * sin(phase);
	g += w.z * (dm * sin(phase) + m * cos(phase) * dphase);
}

// Ola grande: una loma que avanza en `dir`. La parte de arriba se corre hacia
// adelante (la cara de adelante queda empinada y la cresta sobresale como un
// labio). Al llegar a su máximo, "rompe": el labio se curva más y aparece
// espuma. La altura (lo que usa la física) es la misma de swell.gd; el corrimiento
// es solo visual.
void add_swell(vec4 a, vec4 b, vec2 p, inout float h, inout vec2 g, inout vec2 disp,
		inout float body, inout float lip, inout float grow) {
	float amp = b.x;
	float width = b.y;
	if (width <= 0.0) {
		return;
	}
	vec2 dir = a.zw;
	vec2 perp = vec2(-dir.y, dir.x);
	vec2 rel = p - a.xy;
	float u = dot(rel, dir);
	float w = dot(rel, perp);
	float aw = abs(w);
	float half_len = b.z;
	float breaking = b.w;
	float edge = 8.0;
	if (aw >= half_len || abs(u) > width * 4.0) {
		return;
	}
	float t = clamp((aw - (half_len - edge)) / edge, 0.0, 1.0);
	float e0 = 1.0 - t * t * (3.0 - 2.0 * t);
	// "Se viene": franja oscura donde va a subir la ola, desde que nace (sin
	// altura todavía) hasta que llega a su máximo.
	float band = exp(-(u * u) / (width * width * 2.2)) * e0;
	// Solo mientras todavía está baja: al levantarse pasa a turquesa.
	grow = max(grow, band * (1.0 - breaking) * (1.0 - smoothstep(0.4, 1.6, b.x)));
	float gauss = exp(-(u * u) / (width * width));
	float e = 1.0 - t * t * (3.0 - 2.0 * t);
	float de = -6.0 * t * (1.0 - t) / edge;
	float n = gauss * e;
	float dn_du = (-2.0 * u / (width * width)) * gauss * e;
	h += amp * n;
	// Corrimiento de la cresta hacia adelante (más fuerte cuando rompe).
	float lean = (0.35 + 0.95 * breaking) * amp;
	float n2 = n * n;
	disp += dir * (lean * n2 * n);
	float stretch = max(1.0 + lean * 3.0 * n2 * dn_du, 0.12);
	// Pendiente que se ve (la cara de adelante, apretada, queda más empinada).
	float dh_du = amp * dn_du / stretch;
	float dh_dw = amp * gauss * de * sign(w);
	g += dir * dh_du + perp * dh_dw;
	float strength = smoothstep(0.3, 1.2, amp);
	// Cuerpo turquesa: aparece a medida que la ola gana altura.
	body = max(body, n * strength * (0.4 + 0.6 * breaking));
	// Espuma: arriba del labio y cayendo por la cara de adelante.
	float crest_foam = smoothstep(0.8, 0.97, n);
	float face_foam = smoothstep(0.5, 0.8, n) * smoothstep(0.0, width * 0.35, u);
	lip = max(lip, breaking * strength * max(crest_foam, face_foam * 0.6));
}

void add_ring(vec2 p, inout float h, inout vec2 g, inout float body, inout float lip) {
	float amp = ring_b.x;
	if (amp <= 0.0) {
		return;
	}
	vec2 rel = p - ring_a.xy;
	float r = length(rel);
	float width = ring_a.w;
	float d = r - ring_a.z;
	if (abs(d) > width * 4.0 || r < 0.001) {
		return;
	}
	float base = ring_b.y;
	float lobes = ring_b.z;
	float x = lobes * atan(rel.y, rel.x) + ring_b.w;
	float c = 0.5 + 0.5 * cos(x);
	float c5 = c * c * c * c * c;
	float peak = c5 * c;            // SHARPNESS = 6 (igual que ring_wave.gd)
	float dpeak = 6.0 * c5 * (-0.5 * sin(x)) * lobes;
	float gauss = exp(-(d * d) / (width * width));
	float m = base + (1.0 - base) * peak;
	h += amp * m * gauss;
	float n = gauss * m;
	body = max(body, n * smoothstep(0.3, 1.2, amp));
	lip = max(lip, smoothstep(0.82, 0.95, n) * smoothstep(0.3, 1.2, amp));
	vec2 radial = rel / r;
	vec2 tangential = vec2(-radial.y, radial.x);
	float dh_dr = amp * m * (-2.0 * d / (width * width)) * gauss;
	float dh_da = amp * (1.0 - base) * dpeak * gauss;
	g += radial * dh_dr + tangential * (dh_da / r);
}

float island_fade(vec2 p) {
	float fade = 1.0;
	for (int i = 0; i < 16; i++) {
		if (i >= island_count) {
			break;
		}
		float d = distance(p, islands[i].xy);
		fade *= smoothstep(islands[i].z + 4.0, islands[i].z + 28.0, d);
	}
	return fade;
}

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
	float h = 0.0;
	vec2 g = vec2(0.0);
	add_wave(wave_0, 0, world.xz, h, g);
	add_wave(wave_1, 1, world.xz, h, g);
	add_wave(wave_2, 2, world.xz, h, g);
	add_wave(wave_3, 3, world.xz, h, g);
	float ambient_h = h;
	float sh = 0.0;
	vec2 sg = vec2(0.0);
	vec2 disp = vec2(0.0);
	float body = 0.0;
	float lip = 0.0;
	float grow = 0.0;
	add_swell(swell_a0, swell_b0, world.xz, sh, sg, disp, body, lip, grow);
	add_swell(swell_a1, swell_b1, world.xz, sh, sg, disp, body, lip, grow);
	add_swell(swell_a2, swell_b2, world.xz, sh, sg, disp, body, lip, grow);
	add_swell(swell_a3, swell_b3, world.xz, sh, sg, disp, body, lip, grow);
	add_swell(swell_a4, swell_b4, world.xz, sh, sg, disp, body, lip, grow);
	add_swell(swell_a5, swell_b5, world.xz, sh, sg, disp, body, lip, grow);
	add_swell(swell_a6, swell_b6, world.xz, sh, sg, disp, body, lip, grow);
	add_swell(swell_a7, swell_b7, world.xz, sh, sg, disp, body, lip, grow);
	add_ring(world.xz, sh, sg, body, lip);
	float fade = island_fade(world.xz);
	h += sh * fade;
	g += sg * fade;
	disp *= fade;
	VERTEX.y += h;
	VERTEX.xz += disp;
	NORMAL = normalize(vec3(-g.x, 1.0, -g.y));
	v_height = ambient_h;
	v_body = body * fade;
	v_lip = lip * fade;
	v_grow = grow * fade;
	v_world = world + vec3(disp.x, h, disp.y);
}

void fragment() {
	float t = wave_time;
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
		col = mix(col, outside_color, outside * 0.55);
	}

	ALBEDO = col;
	EMISSION = vec3(sparkle * 0.7);
	ROUGHNESS = mix(0.26, 0.7, clamp(foam, 0.0, 1.0));
	SPECULAR = 0.38;
}
