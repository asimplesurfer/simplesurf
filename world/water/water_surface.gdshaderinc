// La superficie del agua: las olas de fondo, las olas grandes (Swell), la ola
// constante (RingWave) y cómo se apagan cerca de las islas. La usa el shader
// del agua (lo que se ve) y la prueba que la compara con la física en GDScript
// (WaveDefinition, Swell, RingWave, Water): tests/water_match.gd. Si se cambia
// algo acá, hay que cambiarlo allá (y la prueba avisa si no coinciden).
uniform vec4 wave_0; // xy = dirección, z = amplitud, w = longitud de onda
uniform vec4 wave_1;
uniform vec4 wave_2;
uniform vec4 wave_3;
uniform float speed_scale = 1.0;
// Fase de cada onda de fondo (0..2π), calculada por water.gd con precisión
// doble: el shader nunca recibe un tiempo grande.
uniform float wave_phase_0 = 0.0;
uniform float wave_phase_1 = 0.0;
uniform float wave_phase_2 = 0.0;
uniform float wave_phase_3 = 0.0;
// Reloj de los efectos (espuma, destellos, lluvia): da la vuelta cada 20 min.
uniform float fx_time = 0.0;

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
// Tierra con forma (islas tropicales): cuánto quedan las olas grandes en
// cada punto (1 mar abierto, 0 sobre la isla). land_rect = (x, z de la
// esquina; ancho, largo); ancho 0 = sin máscara. Ver Water.set_land.
uniform sampler2D land_mask : filter_linear, repeat_disable;
uniform vec4 land_rect = vec4(0.0);

// Para que el oleaje no forme un enrejado que se repite, cada onda se tuerce
// (sus crestas se curvan) y crece y baja por zonas (series de olas), cada una
// distinto. Mismos números que wave_definition.gd.
const vec2 WARP_A[4] = vec2[](vec2(0.023, 0.031), vec2(-0.033, 0.017), vec2(0.027, -0.026), vec2(-0.019, -0.035));
const vec2 WARP_B[4] = vec2[](vec2(-0.029, 0.021), vec2(0.018, 0.034), vec2(-0.031, -0.022), vec2(0.036, -0.012));
const vec2 GROUP[4] = vec2[](vec2(0.011, 0.014), vec2(-0.016, 0.008), vec2(0.009, -0.015), vec2(-0.013, -0.012));
const float SEED[4] = float[](0.0, 2.1, 4.3, 1.2);

void add_wave(vec4 w, int i, float wave_phase, vec2 p, inout float h, inout vec2 g) {
	if (w.w <= 0.0) {
		return;
	}
	float k = 6.28318530718 / w.w;
	float wa = 0.22 * w.w;
	float s1 = dot(p, WARP_A[i]) + SEED[i];
	float s2 = dot(p, WARP_B[i]) + SEED[i] * 1.37;
	vec2 q = p + wa * vec2(sin(s1), sin(s2));
	float phase = k * dot(w.xy, q) - wave_phase;
	vec2 dphase = k * (w.xy + w.x * wa * cos(s1) * WARP_A[i] + w.y * wa * cos(s2) * WARP_B[i]);
	float sg = dot(p, GROUP[i]) + SEED[i] * 1.7;
	float m = 0.65 + 0.35 * sin(sg);
	vec2 dm = 0.35 * cos(sg) * GROUP[i];
	h += w.z * m * sin(phase);
	g += w.z * (dm * sin(phase) + m * cos(phase) * dphase);
}

// Forma del tubo de una ola grande que se cierra (modo trucos): igual en
// swell.gd (profile y tube_point). En veces la altura de la ola.
const float TUBE_R = 0.5;
const float TUBE_THICK = 0.15;
const float TUBE_END_ANGLE = -0.7;
const float TUBE_BACK_ANGLE = 2.62;
const float TUBE_WALL_BACK = 0.4;
const float TUBE_FLOOR_Y = 0.12;
const float TUBE_REACH = 3.0;
const vec4 TUBE_S = vec4(0.25, 0.3, 0.5, 0.7);
const float TUBE_STEEP = 0.25;
const float TUBE_FOOT = 0.35;

// El punto u0 de la cara de adelante en la forma de tubo: (adelante, altura).
vec2 tube_point(float u0, float a, float width, float curl) {
	float full_lean = 1.3 * a;
	// Cuánto salió el labio (0: recién la pared; 1: cerrado).
	float sw = smoothstep(0.0, 1.0, (curl - TUBE_STEEP) / (1.0 - TUBE_STEEP));
	float r = TUBE_R * a * sw;
	float r_in = (TUBE_R - TUBE_THICK) * a * sw;
	float end_angle = mix(1.5707963, TUBE_END_ANGLE, sw);
	float s = u0 / (TUBE_REACH * width);
	vec2 c = vec2(full_lean, a - r);
	if (s <= TUBE_S.x) {
		float ang = mix(1.5707963, end_angle, s / TUBE_S.x);
		return c + vec2(cos(ang), sin(ang)) * r;
	}
	if (s <= TUBE_S.y) {
		float rr = mix(r, r_in, (s - TUBE_S.x) / (TUBE_S.y - TUBE_S.x));
		return c + vec2(cos(end_angle), sin(end_angle)) * rr;
	}
	if (s <= TUBE_S.z) {
		float ang2 = mix(end_angle, TUBE_BACK_ANGLE, (s - TUBE_S.y) / (TUBE_S.z - TUBE_S.y));
		return c + vec2(cos(ang2), sin(ang2)) * r_in;
	}
	vec2 top = c + vec2(cos(TUBE_BACK_ANGLE), sin(TUBE_BACK_ANGLE)) * r_in;
	vec2 base = vec2(full_lean - (TUBE_WALL_BACK * sw - 0.15 * (1.0 - sw)) * a, TUBE_FLOOR_Y * a);
	// La cara es cóncava: baja empinada y se curva hasta el agua de adelante.
	vec2 foot = base + vec2(TUBE_FOOT * a, 0.0);
	if (s <= TUBE_S.w) {
		float t = (s - TUBE_S.z) / (TUBE_S.w - TUBE_S.z);
		return top * (1.0 - t) * (1.0 - t) + base * 2.0 * t * (1.0 - t) + foot * t * t;
	}
	float ue = TUBE_REACH * width;
	float ne = exp(-(ue * ue) / (width * width));
	vec2 end_p = vec2(ue + full_lean * ne * ne * ne, a * ne);
	return mix(foot, end_p, (s - TUBE_S.w) / (1.0 - TUBE_S.w));
}

// Cómo se dibuja el punto u0 de la loma: (corrimiento hacia adelante, altura).
// Con tubo (curl), la cara de adelante se vuelve labio, piso y cara.
vec2 swell_profile(float u0, float amp, float width, float breaking, float curl, float e) {
	float n = exp(-(u0 * u0) / (width * width)) * e;
	float lean = (0.35 + 0.95 * breaking) * amp;
	float off = lean * n * n * n;
	float hh = amp * n;
	if (curl <= 0.0 || u0 <= 0.0 || u0 >= TUBE_REACH * width) {
		return vec2(off, hh);
	}
	// Hacia las puntas el tubo se achica (más bajo) pero sigue abierto: la boca.
	vec2 t = tube_point(u0, amp, width, curl);
	t.y *= e;
	float k = smoothstep(0.0, TUBE_STEEP, curl);
	float x = mix(u0 + off, t.x, k);
	return vec2(x - u0, mix(hh, t.y, k));
}

// Ola grande: una loma que avanza en `dir`. La parte de arriba se corre hacia
// adelante (la cara de adelante queda empinada y la cresta sobresale como un
// labio). Al llegar a su máximo, "rompe": el labio se curva más y aparece
// espuma. La altura (lo que usa la física) es la misma de swell.gd; el corrimiento
// es solo visual.
void add_swell(vec4 a, vec4 b, vec2 p, inout float h, inout vec2 g, inout vec2 disp,
		inout float body, inout float lip, inout float grow, inout float tube) {
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
	// b.w: lo que rompió (0..1); más de 1: ya rompió y se cierra en tubo (1 + curl).
	float breaking = min(b.w, 1.0);
	float curl = max(b.w - 1.0, 0.0);
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
	float dh_du;
	if (curl > 0.0) {
		// Cerrándose en tubo: la forma de swell_profile; la pendiente, de dos puntos.
		vec2 pr = swell_profile(u, amp, width, breaking, curl, e);
		// Cuánto es parte del tubo (labio, techo por adentro y pared): para
		// pintarlo como agua que deja pasar la luz.
		float ts = u / (TUBE_REACH * width);
		if (u > 0.0 && ts < TUBE_S.w) {
			// Todo en el labio; bajando por la pared se va apagando.
			tube = max(tube, smoothstep(0.0, TUBE_STEEP, curl) * e * (1.0 - smoothstep(TUBE_S.z, TUBE_S.w, ts)));
		}
		vec2 pr2 = swell_profile(u + 0.3, amp, width, breaking, curl, e);
		h += pr.y;
		disp += dir * pr.x;
		float dx = 0.3 + pr2.x - pr.x;
		dx = abs(dx) < 0.05 ? (dx < 0.0 ? -0.05 : 0.05) : dx;
		dh_du = clamp((pr2.y - pr.y) / dx, -8.0, 8.0);
	} else {
		h += amp * n;
		// Corrimiento de la cresta hacia adelante (más fuerte cuando rompe).
		float lean = (0.35 + 0.95 * breaking) * amp;
		float n2 = n * n;
		disp += dir * (lean * n2 * n);
		float stretch = max(1.0 + lean * 3.0 * n2 * dn_du, 0.12);
		// Pendiente que se ve (la cara de adelante, apretada, queda más empinada).
		dh_du = amp * dn_du / stretch;
	}
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
	if (land_rect.z > 0.0) {
		vec2 uv = (p - land_rect.xy) / land_rect.zw;
		if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
			fade *= textureLod(land_mask, uv, 0.0).r;
		}
	}
	return fade;
}


// La superficie en el punto p (x, z del mundo): altura (h), pendiente (g),
// corrimiento horizontal del labio de las olas grandes (disp), la altura de
// las olas de fondo solas (ambient_h), y cuánto hay de cuerpo de ola, espuma
// del labio y ola que crece (para los colores).
void water_surface(vec2 p, out float h, out vec2 g, out vec2 disp, out float ambient_h,
		out float body, out float lip, out float grow, out float tube) {
	h = 0.0;
	g = vec2(0.0);
	add_wave(wave_0, 0, wave_phase_0, p, h, g);
	add_wave(wave_1, 1, wave_phase_1, p, h, g);
	add_wave(wave_2, 2, wave_phase_2, p, h, g);
	add_wave(wave_3, 3, wave_phase_3, p, h, g);
	ambient_h = h;
	float sh = 0.0;
	vec2 sg = vec2(0.0);
	disp = vec2(0.0);
	body = 0.0;
	lip = 0.0;
	grow = 0.0;
	tube = 0.0;
	add_swell(swell_a0, swell_b0, p, sh, sg, disp, body, lip, grow, tube);
	add_swell(swell_a1, swell_b1, p, sh, sg, disp, body, lip, grow, tube);
	add_swell(swell_a2, swell_b2, p, sh, sg, disp, body, lip, grow, tube);
	add_swell(swell_a3, swell_b3, p, sh, sg, disp, body, lip, grow, tube);
	add_swell(swell_a4, swell_b4, p, sh, sg, disp, body, lip, grow, tube);
	add_swell(swell_a5, swell_b5, p, sh, sg, disp, body, lip, grow, tube);
	add_swell(swell_a6, swell_b6, p, sh, sg, disp, body, lip, grow, tube);
	add_swell(swell_a7, swell_b7, p, sh, sg, disp, body, lip, grow, tube);
	add_ring(p, sh, sg, body, lip);
	float fade = island_fade(p);
	h += sh * fade;
	g += sg * fade;
	disp *= fade;
	body *= fade;
	lip *= fade;
	grow *= fade;
	tube *= fade;
}
