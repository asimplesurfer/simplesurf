// Medidor de nitro "ojo de buey": una ventanita redonda con agua adentro (el
// nitro: cuanto más hay, más alta) y un aro de tres tramos alrededor (las
// cargas de turbo listas). La superficie del agua se mueve con el surfista:
// la HUD le pasa la inclinación (al doblar), el rebote (saltos y caídas),
// cuánto se agita, las gotas que salta al caer, la espuma, el chorrito al
// ganar nitro, el remolino del turbo, el pulso del aro y el hervor de la
// barra llena.
shader_type canvas_item;

uniform vec2 size = vec2(120.0, 120.0);
// Nivel del agua (0 vacío, 1 lleno).
uniform float level : hint_range(0.0, 1.0) = 0.5;
// Pendiente de la superficie (positiva: más alta a la derecha).
uniform float slope = 0.0;
// Rebote de la superficie (en radios, positivo hacia arriba).
uniform float bob = 0.0;
// Cuánto se agita (alto de las ondas, en radios).
uniform float ripple = 0.03;
uniform vec3 color : source_color = vec3(0.25, 0.85, 1.0);
// Brillo (turbo, llena) y destello al ganar nitro.
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// Burbujas (con turbo y con la barra llena).
uniform float bubbles : hint_range(0.0, 1.0) = 0.0;
// Cargas listas (0..3) y cuánto falta para la próxima (0..1).
uniform float charges = 0.0;
uniform float charge_part = 0.0;
uniform float charge_count = 3.0;
uniform vec3 ring_color : source_color = vec3(1.0);
// Gotas en el aire (al caer fuerte): xy = posición (centro 0, lado 1), z =
// radio, w = cuánto se ven.
uniform vec4 drops[4];
// Espuma acumulada en la superficie (0..1, después de golpes y curvas).
uniform float foam : hint_range(0.0, 1.0) = 0.0;
// Chorrito que cae desde arriba al ganar nitro (0..1).
uniform float stream : hint_range(0.0, 1.0) = 0.0;
// Remolino del turbo (0..1): el agua baja girando.
uniform float swirl : hint_range(0.0, 1.0) = 0.0;
// Pulso del tramo del aro que se acaba de completar (0..1) y cuál es.
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_seg = 0.0;
// Hervor de la barra llena (0..1).
uniform float boil : hint_range(0.0, 1.0) = 0.0;
// De noche: el agua brilla en los bordes (bioluminiscencia).
uniform float night : hint_range(0.0, 1.0) = 0.0;

const float WATER_R = 0.36;
const float RING_R = 0.445;
const float RING_W = 0.04;
const vec3 GLOW_NIGHT = vec3(0.45, 1.0, 0.85);

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// Altura de la superficie en x (sin el remolino).
float surface_at(float px_x, float t) {
	float x = px_x / WATER_R;
	float h = (level * 2.0 - 1.0) * WATER_R + bob * WATER_R + slope * px_x;
	h += ripple * WATER_R * (sin(x * 4.0 + t * 2.6) * 0.7 + sin(x * 7.0 - t * 3.9) * 0.3);
	// Hervor: tiembla rápido y en ondas chicas.
	h += boil * WATER_R * 0.035 * (sin(x * 17.0 + t * 19.0) * 0.6 + sin(x * 29.0 - t * 27.0) * 0.4);
	// Remolino: la superficie se hunde en el medio como un embudo.
	h -= swirl * WATER_R * 0.28 * exp(-x * x * 5.0);
	return mix(-WATER_R * 1.3, h, smoothstep(0.0, 0.02, level));
}

void fragment() {
	float s = min(size.x, size.y);
	vec2 p = (UV * size - size * 0.5) / s;   // centro (0,0), 1 = lado
	p.y = -p.y;                               // arriba positivo
	float r = length(p);
	float px = 1.0 / s;                       // un píxel
	float t = TIME;
	vec4 col = vec4(0.0);

	// --- Ventana: fondo oscuro translúcido.
	float inside = 1.0 - smoothstep(WATER_R - px, WATER_R + px, r);
	col = mix(col, vec4(0.03, 0.1, 0.18, 0.62), inside);

	// --- Agua.
	float surf = surface_at(p.x, t);
	float depth = surf - p.y;                 // >0: debajo de la superficie
	float water = smoothstep(-px, px, depth) * inside;
	float has_water = step(0.001, level);
	// Burbujas (turbo, y muchas más hirviendo).
	float bub = 0.0;
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		float on = step(fi, 4.0 + boil * 4.5);
		float bx = (hash(fi) - 0.5) * WATER_R * 1.3;
		float spd = (0.15 + hash(fi + 3.0) * 0.1) * (1.0 + boil * 2.0);
		float by = -WATER_R + fract(t * spd + hash(fi + 7.0)) * WATER_R * 2.0;
		float br = 0.012 + boil * 0.004 * hash(fi + 5.0);
		bub += on * (1.0 - smoothstep(br - px, br + px, length(p - vec2(bx + sin(t * 4.0 + fi) * 0.006, by))))
			* step(by, surf - 0.02);
	}
	// Ola de atrás: más alta, desfasada, más clara y transparente.
	float back_surf = surf + 0.035 + ripple * WATER_R * 0.8 * sin(p.x / WATER_R * 3.0 - t * 2.1 + 1.7);
	float back = smoothstep(-px, px, back_surf - p.y) * (1.0 - water) * inside * has_water;
	col = mix(col, vec4(mix(color, vec3(1.0), 0.25), 1.0), back * 0.38);
	// Degradé suave y banda de luz bajo la superficie.
	vec3 wcol = mix(color * 1.04, color * 0.8, clamp(depth / (WATER_R * 1.6), 0.0, 1.0));
	wcol = mix(wcol, mix(color, vec3(1.0), 0.45), (1.0 - smoothstep(0.012, 0.05, depth)) * 0.5);
	// Remolino: vetas claras que giran hacia el centro del embudo.
	if (swirl > 0.0) {
		vec2 q = p - vec2(0.0, surf - WATER_R * 0.15);
		float a = atan(q.y, q.x);
		float rr = length(q);
		float streak = smoothstep(0.82, 1.0, sin(a * 3.0 + rr * 45.0 - t * 9.0));
		wcol = mix(wcol, vec3(1.0), streak * swirl * 0.25 * (1.0 - smoothstep(0.05, WATER_R, rr)));
	}
	wcol = mix(wcol, vec3(1.0), clamp(bub, 0.0, 1.0) * bubbles * 0.45 + flash * 0.2);
	// De noche: brillo en los bordes del agua (contra el vidrio y en la superficie).
	float edge = smoothstep(WATER_R - 0.05, WATER_R, r) + (1.0 - smoothstep(0.0, 0.04, depth));
	wcol = mix(wcol, GLOW_NIGHT, clamp(edge, 0.0, 1.0) * night * (0.45 + 0.15 * sin(t * 1.7 + p.x * 9.0)));
	col = mix(col, vec4(wcol, 1.0), water);
	// Línea de la superficie; con espuma, más gruesa y despareja.
	// Espuma: una franja blanca más gruesa debajo de la línea, despareja y suave.
	float foam_w = foam * (2.0 + 1.0 * sin(p.x * 22.0 + t * 2.0) + 0.6 * sin(p.x * 41.0 - t * 3.0));
	float foam_band = (1.0 - smoothstep(foam_w * px, (foam_w + 1.5) * px, depth)) * step(0.0, depth) * inside * has_water;
	col = mix(col, vec4(1.0), foam_band * 0.75);
	float line = (1.0 - smoothstep(0.0, 1.5 * px, abs(depth) - 0.7 * px)) * inside * has_water;
	col = mix(col, vec4(mix(vec3(1.0), GLOW_NIGHT, night * 0.6), 1.0), line);

	// Chorrito: cae de arriba hasta la superficie, se afina al terminar.
	if (stream > 0.0) {
		float sx = 0.04 + sin(p.y * 30.0 + t * 12.0) * 0.004;
		float w = 0.016 * stream;
		float in_stream = (1.0 - smoothstep(w - px, w + px, abs(p.x - sx))) * step(surf, p.y) * inside;
		col = mix(col, vec4(mix(color, vec3(1.0), 0.35), 1.0), in_stream);
		// Salpicadura donde pega.
		float hit = (1.0 - smoothstep(0.0, 0.035 * stream, length(p - vec2(sx, surf)))) * inside * has_water;
		col = mix(col, vec4(1.0), hit * 0.8);
	}
	// Gotas en el aire.
	for (int i = 0; i < 4; i++) {
		vec4 d = drops[i];
		if (d.w <= 0.0) {
			continue;
		}
		float dd = length(p - d.xy);
		float drop = (1.0 - smoothstep(d.z - px, d.z + px, dd)) * d.w * inside;
		col = mix(col, vec4(mix(color, vec3(1.0), 0.3), 1.0), drop);
	}
	// Borde de la ventana: fino y blanco.
	float rim = 1.0 - smoothstep(0.0, 1.6 * px, abs(r - WATER_R) - 0.8 * px);
	col = mix(col, vec4(1.0, 1.0, 1.0, 0.9), rim);

	// --- Aro de las cargas: tres tramos con una separación.
	float ang = atan(p.x, p.y);               // 0 arriba, sentido horario
	float a01 = fract(ang / 6.2831853 + 1.0);
	float seg = floor(a01 * charge_count);
	float in_seg = fract(a01 * charge_count);
	float gap = 0.06;
	// El tramo recién completado late: se ensancha y se aleja un poco.
	float beat = pulse * step(abs(seg - pulse_seg), 0.5);
	float ring_r = RING_R + beat * 0.02;
	float ring_w = RING_W * (1.0 + beat * 0.9);
	float on_ring = (1.0 - smoothstep(ring_w * 0.5 - px, ring_w * 0.5 + px, abs(r - ring_r)))
		* smoothstep(gap * 0.5, gap * 0.5 + 0.02, in_seg) * smoothstep(gap * 0.5, gap * 0.5 + 0.02, 1.0 - in_seg);
	float ready = step(seg + 0.5, charges);
	float partial = step(charges, seg + 0.5) * step(seg - 0.5, charges)
		* step((in_seg - gap * 0.5) / (1.0 - gap), charge_part);
	vec3 rc = mix(ring_color, color, glow * 0.7);
	rc = mix(rc, vec3(1.0), beat * 0.6);
	float ring_a = mix(0.22, 1.0, max(ready, partial * 0.75));
	float ring_shadow = (1.0 - smoothstep(RING_W * 0.5, RING_W * 0.5 + 0.015, abs(r - RING_R))) * 0.1;
	col = mix(col, vec4(0.0, 0.0, 0.0, 1.0), ring_shadow * (1.0 - col.a));
	col.a = max(col.a, ring_shadow);
	col = mix(col, vec4(rc, 1.0), on_ring * ring_a);
	col.a = max(col.a, on_ring * ring_a);
	// Destello alrededor del tramo que late.
	float halo = (1.0 - smoothstep(0.0, 0.05, abs(r - ring_r))) * beat * 0.5
		* step(abs(seg - pulse_seg), 0.5) * (1.0 - on_ring);
	col = mix(col, vec4(1.0), halo);
	col.a = max(col.a, halo);
	// Aura con turbo / llena.
	float aura = (1.0 - smoothstep(RING_R, RING_R + 0.06, r)) * smoothstep(WATER_R, RING_R, r) * glow * 0.35;
	col = mix(col, vec4(color, 1.0), aura * (1.0 - on_ring));
	col.a = max(col.a, aura);
	COLOR = col;
}
