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
// La ola que está rompiendo en tubo (ver swell.gd, peel_w): (punto de rotura
// a lo ancho, hacia dónde avanza ±1, largo del tubo abierto, -).
uniform vec4 barrel = vec4(-1.0e9, 1.0, 22.0, 0.0);
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
const float TUBE_RX = 0.55;
const float TUBE_RY = 0.48;
const float TUBE_THICK = 0.1;
const float TUBE_END_ANGLE = -0.35;
const float TUBE_LAND_ANGLE = -1.2;
const float TUBE_BACK_ANGLE = 2.44;
const float TUBE_WALL_BACK = 0.5;
const float TUBE_FLOOR_Y = 0.1;
const float TUBE_REACH = 3.0;
const vec4 TUBE_S = vec4(0.3, 0.35, 0.55, 0.72);
const float TUBE_STEEP = 0.25;
const float BARREL_THROAT = 14.0;
const float BARREL_COLLAPSE = 16.0;
const float BARREL_DROP = 0.6;
const float TUBE_FOOT = 0.4;
// La punta del labio, derecha aunque la malla quede en diagonal (swell.gd).
const float TUBE_TIP_BAND = 0.78;
const float TUBE_TIP_RAMP = 1.2;

// El punto u0 de la cara de adelante en la forma de tubo: (adelante, altura).
// fill: cuánto se llenó el hueco (donde el tubo ya se cayó).
vec2 tube_point(float u0, float a, float width, float curl, float land, float fill) {
	float full_lean = 1.3 * a;
	// Cuánto salió el labio (0: recién la pared; 1: cerrado).
	float sw = smoothstep(0.0, 1.0, (curl - TUBE_STEEP) / (1.0 - TUBE_STEEP));
	float rx = TUBE_RX * a * sw;
	float ry = TUBE_RY * a * sw;
	float rxi = (TUBE_RX - TUBE_THICK) * a * sw * (1.0 - fill);
	float ryi = (TUBE_RY - TUBE_THICK) * a * sw * (1.0 - fill);
	float end_angle = mix(1.5707963, mix(TUBE_END_ANGLE, TUBE_LAND_ANGLE, land), sw);
	// La punta, derecha (ver TUBE_TIP_BAND).
	float tip = (TUBE_S.x + TUBE_S.y) * 0.5 * TUBE_REACH * width;
	float d = u0 - tip;
	float ad = abs(d);
	if (ad < TUBE_TIP_BAND + TUBE_TIP_RAMP) {
		u0 = tip + sign(d) * max(ad - TUBE_TIP_BAND, 0.0) * (TUBE_TIP_BAND + TUBE_TIP_RAMP) / TUBE_TIP_RAMP;
	}
	float s = u0 / (TUBE_REACH * width);
	vec2 c = vec2(full_lean + 0.05 * a * sw, a - ry);
	if (s <= TUBE_S.x) {
		float ang = mix(1.5707963, end_angle, s / TUBE_S.x);
		return c + vec2(cos(ang) * rx, sin(ang) * ry);
	}
	if (s <= TUBE_S.y) {
		float k = (s - TUBE_S.x) / (TUBE_S.y - TUBE_S.x);
		return c + vec2(cos(end_angle) * mix(rx, rxi, k), sin(end_angle) * mix(ry, ryi, k));
	}
	if (s <= TUBE_S.z) {
		float ang2 = mix(end_angle, TUBE_BACK_ANGLE, (s - TUBE_S.y) / (TUBE_S.z - TUBE_S.y));
		return c + vec2(cos(ang2) * rxi, sin(ang2) * ryi);
	}
	vec2 top = c + vec2(cos(TUBE_BACK_ANGLE) * rxi, sin(TUBE_BACK_ANGLE) * ryi);
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
vec2 swell_profile(float u0, float amp, float width, float breaking, float curl, float land, float fill, float e) {
	float n = exp(-(u0 * u0) / (width * width)) * e;
	float lean = (0.35 + 0.95 * breaking) * amp;
	float off = lean * n * n * n;
	float hh = amp * n;
	if (curl <= 0.0 || u0 <= 0.0 || u0 >= TUBE_REACH * width) {
		return vec2(off, hh);
	}
	// Hacia las puntas el tubo se achica (más bajo) pero sigue abierto: la boca.
	vec2 t = tube_point(u0, amp, width, curl, land, fill);
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
		inout float body, inout float lip, inout float grow, inout float tube, inout vec3 tube_n,
		inout vec2 flow) {
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
	// Rompe de a poco a lo largo de la cresta (ver swell.gd barrel_at): adelante
	// del punto de rotura, el hombro y la garganta; detrás, el tubo abierto y
	// más atrás la ola que se cae (más baja, con espuma).
	float fall = 0.0;
	float land = 0.0;
	float fill = 0.0;
	if (curl > 0.0) {
		float ps = (w - barrel.x) * barrel.y;
		land = smoothstep(0.0, barrel.z + BARREL_COLLAPSE * 0.5, -ps);
		if (ps > 0.0) {
			curl *= 1.0 - smoothstep(0.0, BARREL_THROAT, ps);
		} else {
			// Se cae: el hueco se llena (bulto de espuma) y después baja.
			float q = 1.0 - smoothstep(-barrel.z - BARREL_COLLAPSE, -barrel.z, ps);
			fall = q * curl;
			fill = smoothstep(0.0, 0.5, q);
			curl *= 1.0 - smoothstep(0.45, 1.0, q);
		}
	}
	float drop = 1.0 - BARREL_DROP * fall;
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
	// Pendiente que se ve en la ola normal (la cara de adelante, apretada por
	// el corrimiento de la cresta, queda más empinada).
	float lean = (0.35 + 0.95 * breaking) * amp;
	float n2 = n * n;
	float stretch = max(1.0 + lean * 3.0 * n2 * dn_du, 0.12);
	float dh_du = amp * dn_du / stretch * drop;
	if (curl > 0.0) {
		// Cerrándose en tubo: la forma de swell_profile; la pendiente, de dos puntos.
		vec2 pr = swell_profile(u, amp, width, breaking, curl, land, fill, e);
		// Cuánto es parte del tubo (labio, techo por adentro y pared): para
		// pintarlo como agua que deja pasar la luz.
		float ts = u / (TUBE_REACH * width);
		if (u > 0.0 && ts < TUBE_S.w) {
			// Todo en el labio; bajando por la pared se va apagando.
			tube = max(tube, smoothstep(0.0, TUBE_STEEP, curl) * e * (1.0 - smoothstep(TUBE_S.z, TUBE_S.w, ts)));
		}
		vec2 pr2 = swell_profile(u + 0.3, amp, width, breaking, curl, land, fill, e);
		h += pr.y * drop;
		disp += dir * pr.x;
		float dx = 0.3 + pr2.x - pr.x;
		float dy = (pr2.y - pr.y) * drop;
		// La normal de verdad (del lado que miraba arriba antes de curvarse):
		// por adentro del labio mira hacia abajo y en la pared hacia adelante.
		// Con la pendiente sola (que siempre mira arriba) quedaban al revés.
		vec2 cn = vec2(-dy, dx);
		cn = dot(cn, cn) > 1.0e-6 ? normalize(cn) : vec2(1.0, 0.0);
		// Solo donde el agua está parada o dada vuelta (el resto, la pendiente).
		float tw = smoothstep(0.0, TUBE_STEEP, curl) * e * (1.0 - smoothstep(0.2, 0.6, cn.y));
		tube_n += (vec3(dir.x, 0.0, dir.y) * cn.x + vec3(0.0, cn.y, 0.0)) * tw;
		dx = abs(dx) < 0.05 ? (dx < 0.0 ? -0.05 : 0.05) : dx;
		// Mientras recién empieza a cerrarse, la de la ola normal (la de dos
		// puntos se da vuelta en el pliegue chico del labio y queda oscura).
		dh_du = mix(dh_du, clamp(dy / dx, -8.0, 8.0), smoothstep(0.0, TUBE_STEEP, curl));
	} else {
		h += amp * n * drop;
		// Corrimiento de la cresta hacia adelante (más fuerte cuando rompe).
		disp += dir * (lean * n2 * n);
	}
	float dh_dw = amp * gauss * de * sign(w);
	g += dir * dh_du + perp * dh_dw;
	float strength = smoothstep(0.3, 1.2, amp);
	// Cuerpo turquesa: aparece a medida que la ola gana altura.
	body = max(body, n * strength * (0.4 + 0.6 * breaking));
	// Espuma: arriba del labio y cayendo por la cara de adelante.
	float crest_foam = smoothstep(0.8, 0.97, n);
	float face_foam = smoothstep(0.5, 0.8, n) * smoothstep(0.0, width * 0.35, u);
	// En el tubo, la espuma queda solo en el borde del labio y donde cae (el
	// resto del labio es agua que deja pasar la luz).
	float in_tube = 0.0;
	float edge_foam = 0.0;
	if (curl > 0.0 && u > 0.0) {
		float k_t = smoothstep(0.0, TUBE_STEEP, curl);
		float ts2 = u / (TUBE_REACH * width);
		in_tube = k_t * (1.0 - smoothstep(TUBE_S.w, TUBE_S.w + 0.06, ts2));
		float sw2 = smoothstep(0.0, 1.0, (curl - TUBE_STEEP) / (1.0 - TUBE_STEEP));
		// El borde del labio (la punta) y, cuando ya baja hasta el agua
		// (land), el agua justo debajo de la punta.
		edge_foam = sw2 * e * max(
			smoothstep(TUBE_S.x - 0.07, TUBE_S.x, ts2) * (1.0 - smoothstep(TUBE_S.y, TUBE_S.y + 0.03, ts2)),
			smoothstep(TUBE_S.w + 0.02, TUBE_S.w + 0.04, ts2) * (1.0 - smoothstep(TUBE_S.w + 0.07, TUBE_S.w + 0.11, ts2)) * 0.8 * land);
		// Para las vetas del agua que corre por el tubo (ver water.gdshader):
		// a lo ancho de la ola y cuánto falta hasta la punta del labio.
		flow = vec2(w, u - (TUBE_S.x + TUBE_S.y) * 0.5 * TUBE_REACH * width);
	}
	lip = max(lip, breaking * strength * max(crest_foam, face_foam * 0.6) * (1.0 - in_tube * 0.9));
	lip = max(lip, edge_foam * strength);
	// La ola que se cayó detrás del tubo: espuma blanca.
	lip = max(lip, fall * strength * smoothstep(0.05, 0.3, n));
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
// del labio y ola que crece (para los colores). tube_n: en un tubo, la normal
// donde el agua está parada o dada vuelta (el largo es cuánto pesa, 0..1);
// flow: dónde está en el tubo (a lo ancho, hasta la punta del labio).
void water_surface(vec2 p, out float h, out vec2 g, out vec2 disp, out float ambient_h,
		out float body, out float lip, out float grow, out float tube, out vec3 tube_n, out vec2 flow) {
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
	tube_n = vec3(0.0);
	flow = vec2(0.0);
	add_swell(swell_a0, swell_b0, p, sh, sg, disp, body, lip, grow, tube, tube_n, flow);
	add_swell(swell_a1, swell_b1, p, sh, sg, disp, body, lip, grow, tube, tube_n, flow);
	add_swell(swell_a2, swell_b2, p, sh, sg, disp, body, lip, grow, tube, tube_n, flow);
	add_swell(swell_a3, swell_b3, p, sh, sg, disp, body, lip, grow, tube, tube_n, flow);
	add_swell(swell_a4, swell_b4, p, sh, sg, disp, body, lip, grow, tube, tube_n, flow);
	add_swell(swell_a5, swell_b5, p, sh, sg, disp, body, lip, grow, tube, tube_n, flow);
	add_swell(swell_a6, swell_b6, p, sh, sg, disp, body, lip, grow, tube, tube_n, flow);
	add_swell(swell_a7, swell_b7, p, sh, sg, disp, body, lip, grow, tube, tube_n, flow);
	add_ring(p, sh, sg, body, lip);
	float fade = island_fade(p);
	h += sh * fade;
	g += sg * fade;
	disp *= fade;
	body *= fade;
	lip *= fade;
	grow *= fade;
	tube *= fade;
	tube_n *= fade;
}
