// Agua falsa: un plano subdividido cuyos vértices suben y bajan.
// La fórmula es la misma que wave_definition.gd (no cambiar una sin la otra).
shader_type spatial;
// cull_disabled: la cresta que se curva puede quedar "dada vuelta".
render_mode specular_schlick_ggx, cull_disabled;

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
uniform vec3 outside_color : source_color = vec3(0.02, 0.17, 0.34);

uniform vec3 deep_color : source_color = vec3(0.02, 0.24, 0.48);
uniform vec3 shallow_color : source_color = vec3(0.08, 0.48, 0.7);
uniform vec3 foam_color : source_color = vec3(0.93, 0.98, 1.0);
uniform float foam_height = 0.42;
uniform vec3 wave_color : source_color = vec3(0.1, 0.68, 0.72);

varying float v_height;
// 0..1: cuerpo de una ola grande (para el color turquesa de la ola).
varying float v_body;
// 0..1: espuma de la ola que rompe (labio y cara).
varying float v_lip;
// 0..1: ola que todavía está creciendo ("se viene").
varying float v_grow;
varying vec3 v_world;

void add_wave(vec4 w, vec2 p, inout float h, inout vec2 g) {
	if (w.w <= 0.0) {
		return;
	}
	float k = 6.28318530718 / w.w;
	float omega = sqrt(9.8 * k) * speed_scale;
	float phase = k * dot(w.xy, p) - omega * wave_time;
	h += w.z * sin(phase);
	g += w.xy * (w.z * k * cos(phase));
}

// Ola grande: una loma que avanza en `dir`. La parte de arriba se corre hacia
// adelante (la cara de adelante queda empinada y la cresta sobresale como un
// labio). Al llegar a su máximo, "rompe": el labio se curva más y aparece
// espuma. La altura (lo que usa la física) es la misma de swell.gd; el corrimiento
// es solo visual.
void add_swell(vec4 a, vec4 b, vec2 p, inout float h, inout vec2 g, inout vec2 disp,
		inout float body, inout float lip, inout float grow) {
	float amp = b.x;
	if (amp <= 0.0) {
		return;
	}
	vec2 dir = a.zw;
	vec2 perp = vec2(-dir.y, dir.x);
	vec2 rel = p - a.xy;
	float u = dot(rel, dir);
	float w = dot(rel, perp);
	float aw = abs(w);
	float width = b.y;
	float half_len = b.z;
	float breaking = b.w;
	float edge = 8.0;
	if (aw >= half_len || abs(u) > width * 4.0) {
		return;
	}
	float gauss = exp(-(u * u) / (width * width));
	float t = clamp((aw - (half_len - edge)) / edge, 0.0, 1.0);
	float e = 1.0 - t * t * (3.0 - 2.0 * t);
	float de = -6.0 * t * (1.0 - t) / edge;
	float n = gauss * e;
	float dn_du = (-2.0 * u / (width * width)) * gauss * e;
	h += amp * n;
	// Corrimiento de la cresta hacia adelante (más fuerte cuando rompe).
	float lean = (0.45 + 1.35 * breaking) * amp;
	float n2 = n * n;
	disp += dir * (lean * n2 * n);
	float stretch = max(1.0 + lean * 3.0 * n2 * dn_du, 0.12);
	// Pendiente que se ve (la cara de adelante, apretada, queda más empinada).
	float dh_du = amp * dn_du / stretch;
	float dh_dw = amp * gauss * de * sign(w);
	g += dir * dh_du + perp * dh_dw;
	float strength = smoothstep(0.3, 1.2, amp);
	body = max(body, n * strength);
	grow = max(grow, n * strength * (1.0 - breaking));
	// Espuma: arriba del labio y cayendo por la cara de adelante.
	float crest_foam = smoothstep(0.62, 0.92, n);
	float face_foam = smoothstep(0.25, 0.7, n) * smoothstep(0.0, width * 0.5, u);
	lip = max(lip, breaking * strength * max(crest_foam, face_foam * 0.8));
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

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = 0.0;
	vec2 g = vec2(0.0);
	add_wave(wave_0, world.xz, h, g);
	add_wave(wave_1, world.xz, h, g);
	add_wave(wave_2, world.xz, h, g);
	add_wave(wave_3, world.xz, h, g);
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
	vec3 col = mix(deep_color, shallow_color, smoothstep(-0.5, 0.5, v_height));
	float foam = smoothstep(foam_height, foam_height + 0.1, v_height);
	// Olas grandes: cuerpo turquesa (se ve la ola de lejos). Mientras crece
	// ("se viene") es más oscura y sin espuma; al llegar al máximo rompe y se
	// llena de espuma arriba y en la cara.
	col = mix(col, wave_color, v_body * 0.75);
	col = mix(col, wave_color * 0.7, v_grow * 0.35);
	foam = max(foam, v_lip);
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0) * 0.85);

	// Fuera de la pista, el agua más oscura (con un borde suave).
	if (track_band.w > 0.0) {
		float d = distance(v_world.xz, track_band.xy);
		float out_inner = 1.0 - smoothstep(track_band.z - 3.0, track_band.z - 0.5, d);
		float out_outer = smoothstep(track_band.w + 0.5, track_band.w + 3.0, d);
		float outside = max(out_inner, out_outer);
		col = mix(col, outside_color, outside * 0.55);
	}

	ALBEDO = col;
	ROUGHNESS = 0.55;
	SPECULAR = 0.2;
}
