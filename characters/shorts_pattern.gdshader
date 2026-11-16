// Estampado del short pintado sobre la tela (sin relieve): color plano como el
// resto del personaje. Las coordenadas son cilíndricas alrededor del eje de cada
// pieza (cadera o pierna del short), con `ring` celdas por vuelta (entero, así no
// se corta atrás).
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 base_color : source_color = vec3(0.08, 0.19, 0.42);
uniform vec3 color1 : source_color = vec3(1.0);
uniform vec3 color2 : source_color = vec3(1.0, 0.82, 0.25);
uniform int pattern = 0;
// Celdas alrededor de la pieza (par).
uniform float ring = 14.0;
// Altura en el personaje: y = offset + y_local * scale.
uniform float y_offset = 0.8;
uniform float y_scale = 1.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + vec2(17.3, 5.1)));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = i.x + i.y * 57.0 + i.z * 113.0;
	float a = fract(sin(n) * 43758.5);
	float b = fract(sin(n + 1.0) * 43758.5);
	float c = fract(sin(n + 57.0) * 43758.5);
	float d = fract(sin(n + 58.0) * 43758.5);
	float e = fract(sin(n + 113.0) * 43758.5);
	float g = fract(sin(n + 114.0) * 43758.5);
	float h = fract(sin(n + 170.0) * 43758.5);
	float k = fract(sin(n + 171.0) * 43758.5);
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

// Celda (u, v) que se repite cada `period` en u (para que no se corte atrás).
vec2 cell_id(vec2 c, float period) {
	return vec2(mod(c.x, period), c.y);
}

// Forma de flor (pétalos) de radio r en coordenadas polares.
float flower(vec2 q, float r, float petals) {
	float a = atan(q.y, q.x);
	return length(q) - r * (0.62 + 0.38 * abs(cos(a * petals * 0.5)));
}

float star(vec2 q, float r) {
	float a = atan(q.y, q.x) + 1.5708;
	float k = abs(fract(a / 1.2566 ) - 0.5) * 2.0;
	return length(q) - r * mix(0.45, 1.0, k * k);
}

void fragment() {
	float ang = atan(lp.x, lp.z) / 6.28318 + 0.5; // 0..1 alrededor
	float u = ang * ring; // celdas alrededor
	float v = lp.y * y_scale / 0.126; // celdas para arriba
	float cy = y_offset + lp.y * y_scale; // altura en el personaje
	vec3 col = base_color;
	if (pattern == 1) {
		// Flores chicas de cinco pétalos, con el centro del segundo color.
		vec2 c = vec2(u * 0.5, v * 0.5);
		vec2 id = floor(c);
		vec2 j = hash2(cell_id(id, ring * 0.5)) * 0.4 + 0.3;
		vec2 q = fract(c) - j;
		if (length(q) < 0.08) col = color2;
		else if (flower(q, 0.3, 5.0) < 0.0) col = color1;
	} else if (pattern == 2) {
		// Lunares.
		vec2 c = vec2(u * 0.5, v * 0.5);
		if (mod(floor(c.y), 2.0) > 0.5) c.x += 0.5;
		vec2 q = fract(c) - 0.5;
		if (length(q) < 0.2) col = color1;
	} else if (pattern == 3) {
		// Rayas horizontales de dos colores.
		float b = fract(v * 0.25);
		if (b < 0.22) col = color1;
		else if (b > 0.5 && b < 0.72) col = color2;
	} else if (pattern == 4) {
		// Hawaiano: flores grandes de los dos colores, con hojas.
		vec2 c = vec2(u * 0.5, v * 0.5);
		vec2 id = floor(c);
		vec2 h = hash2(cell_id(id, ring * 0.5));
		vec2 q = fract(c) - (h * 0.2 + 0.4);
		vec2 lq = fract(c + vec2(0.5, 0.5)) - 0.5;
		lq = vec2(lq.x * 0.8 + lq.y * 0.6, -lq.x * 0.6 + lq.y * 0.8);
		if (length(lq * vec2(1.0, 2.6)) < 0.26) col = mix(base_color, vec3(0.12, 0.55, 0.3), 0.75);
		if (length(q) < 0.08) col = vec3(1.0, 0.85, 0.3);
		else if (flower(q, 0.42, 5.0) < 0.0) col = h.x > 0.5 ? color1 : color2;
	} else if (pattern == 5) {
		// Tie-dye: espiral alrededor del frente.
		float a = ang * 6.28318 - 3.14159;
		vec2 q = vec2(a * 2.2, (cy - 0.85) * 6.0);
		float r = length(q);
		float sp = r * 2.2 - atan(q.y, q.x) * 1.0 + noise3(lp * 9.0) * 1.6;
		float b = fract(sp / 3.0);
		col = b < 0.33 ? color1 : (b < 0.66 ? color2 : base_color);
	} else if (pattern == 6) {
		// Tres franjas: arriba el primer color, en el medio el segundo, abajo el short.
		if (cy > 0.97) col = color1;
		else if (cy > 0.8) col = color2;
	} else if (pattern == 7) {
		// Cuadros (tipo mantel): donde se cruzan las franjas, el segundo color.
		bool hx = fract(u * 0.5) < 0.5;
		bool hy = fract(v * 0.5) < 0.5;
		if (hx && hy) col = color2;
		else if (hx || hy) col = color1;
	} else if (pattern == 8) {
		// Olas.
		float w = v * 0.5 + 0.22 * sin(u * 0.5 * 6.28318);
		float b = fract(w * 0.5);
		if (b < 0.25) col = color1;
		else if (b > 0.36 && b < 0.44) col = color2;
	} else if (pattern == 9) {
		// Rayas verticales de dos colores.
		float b = fract(u * 0.25);
		if (b < 0.22) col = color1;
		else if (b > 0.5 && b < 0.72) col = color2;
	} else if (pattern == 10) {
		// Estrellas.
		vec2 c = vec2(u * 0.5, v * 0.5);
		if (mod(floor(c.y), 2.0) > 0.5) c.x += 0.5;
		vec2 id = floor(c);
		vec2 q = fract(c) - 0.5;
		if (star(q, 0.36) < 0.0) col = mod(id.x + id.y, 2.0) > 0.5 ? color1 : color2;
	} else if (pattern == 11) {
		// Llamas que suben desde abajo.
		float x = u * 0.5;
		float t = abs(fract(x) - 0.5) * 2.0;
		float tongue = pow(1.0 - t, 1.6);
		float edge = 0.62 + 0.24 * tongue + 0.04 * sin(x * 7.0);
		if (cy < edge - 0.07) col = color2;
		else if (cy < edge) col = color1;
	} else if (pattern == 12) {
		// Camuflaje: manchas.
		float n = noise3(lp * 7.0 + vec3(3.1)) * 0.65 + noise3(lp * 15.0) * 0.35;
		if (n > 0.58) col = color1;
		else if (n < 0.4) col = color2;
	} else if (pattern == 13) {
		// Zigzag.
		float w = v * 0.5 + abs(fract(u * 0.5) - 0.5);
		float b = fract(w * 0.5);
		if (b < 0.2) col = color1;
		else if (b > 0.42 && b < 0.56) col = color2;
	}
	ALBEDO = col;
}
