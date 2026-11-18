// Medidor de nitro "ojo de buey": una ventanita redonda con agua adentro (el
// nitro: cuanto más hay, más alta) y un aro de tres tramos alrededor (las
// cargas de turbo listas). La superficie del agua se mueve con el surfista:
// la HUD le pasa la inclinación (al doblar), el rebote (saltos y caídas) y
// cuánto se agita (velocidad, golpes).
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
// Brillo (turbo, llena) y destello blanco al ganar nitro.
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// Burbujas (con turbo).
uniform float bubbles : hint_range(0.0, 1.0) = 0.0;
// Cargas listas (0..3) y cuánto falta para la próxima (0..1).
uniform float charges = 0.0;
uniform float charge_part = 0.0;
uniform float charge_count = 3.0;
uniform vec3 ring_color : source_color = vec3(1.0);

const float WATER_R = 0.36;
const float RING_R = 0.445;
const float RING_W = 0.04;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	float s = min(size.x, size.y);
	vec2 p = (UV * size - size * 0.5) / s;   // centro (0,0), 1 = lado
	p.y = -p.y;                               // arriba positivo
	float r = length(p);
	float px = 1.0 / s;                       // un píxel
	vec4 col = vec4(0.0);

	// --- Ventana: fondo oscuro translúcido.
	float inside = 1.0 - smoothstep(WATER_R - px, WATER_R + px, r);
	col = mix(col, vec4(0.03, 0.1, 0.18, 0.62), inside);

	// --- Agua: un solo color plano y una línea blanca fina en la superficie.
	// Lo que se mueve es la superficie (inclinación, rebote y una onda suave).
	float x = p.x / WATER_R;
	float surf = (level * 2.0 - 1.0) * WATER_R + bob * WATER_R + slope * p.x;
	float t = TIME;
	surf += ripple * WATER_R * (sin(x * 4.0 + t * 2.6) * 0.7 + sin(x * 7.0 - t * 3.9) * 0.3);
	// Vacío del todo: sin agua.
	surf = mix(-WATER_R * 1.3, surf, smoothstep(0.0, 0.02, level));
	float depth = surf - p.y;                 // >0: debajo de la superficie
	float water = smoothstep(-px, px, depth) * inside;
	// Burbujas (con turbo): pocas y chicas, del mismo color pero más claras.
	float bub = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float bx = (hash(fi) - 0.5) * WATER_R * 1.3;
		float by = -WATER_R + fract(t * (0.15 + hash(fi + 3.0) * 0.1) + hash(fi + 7.0)) * WATER_R * 2.0;
		float br = 0.012;
		bub += (1.0 - smoothstep(br - px, br + px, length(p - vec2(bx, by)))) * step(by, surf - 0.02);
	}
	vec3 wcol = mix(color, vec3(1.0), clamp(bub, 0.0, 1.0) * bubbles * 0.45 + flash * 0.6);
	col = mix(col, vec4(wcol, 1.0), water);
	float line = (1.0 - smoothstep(0.0, 1.5 * px, abs(depth) - 0.7 * px)) * inside * step(0.001, level);
	col = mix(col, vec4(1.0), line);
	// Borde de la ventana: fino y blanco.
	float rim = 1.0 - smoothstep(0.0, 1.6 * px, abs(r - WATER_R) - 0.8 * px);
	col = mix(col, vec4(1.0, 1.0, 1.0, 0.9), rim);

	// --- Aro de las cargas: tres tramos con una separación.
	float ang = atan(p.x, p.y);               // 0 arriba, sentido horario
	float a01 = fract(ang / 6.2831853 + 1.0);
	float seg = floor(a01 * charge_count);
	float in_seg = fract(a01 * charge_count);
	float gap = 0.06;
	float on_ring = (1.0 - smoothstep(RING_W * 0.5 - px, RING_W * 0.5 + px, abs(r - RING_R)))
		* smoothstep(gap * 0.5, gap * 0.5 + 0.02, in_seg) * smoothstep(gap * 0.5, gap * 0.5 + 0.02, 1.0 - in_seg);
	// Listo: lleno y claro. El que se está cargando: se completa de a poco.
	float ready = step(seg + 0.5, charges);
	float partial = step(charges, seg + 0.5) * step(seg - 0.5, charges)
		* step((in_seg - gap * 0.5) / (1.0 - gap), charge_part);
	vec3 rc = mix(ring_color, color, glow * 0.7);
	float ring_a = mix(0.22, 1.0, max(ready, partial * 0.75));
	// Sombra suave debajo del aro (que se lea sobre el agua clara).
	float ring_shadow = (1.0 - smoothstep(RING_W * 0.5, RING_W * 0.5 + 0.015, abs(r - RING_R))) * 0.1;
	col = mix(col, vec4(0.0, 0.0, 0.0, 1.0), ring_shadow * (1.0 - col.a));
	col.a = max(col.a, ring_shadow);
	col = mix(col, vec4(rc, 1.0), on_ring * ring_a);
	col.a = max(col.a, on_ring * ring_a);
	// Aura con turbo / llena.
	float aura = (1.0 - smoothstep(RING_R, RING_R + 0.06, r)) * smoothstep(WATER_R, RING_R, r) * glow * 0.35;
	col = mix(col, vec4(color, 1.0), aura * (1.0 - on_ring));
	col.a = max(col.a, aura);
	COLOR = col;
}
