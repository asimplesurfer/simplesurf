// Tabla con su diseño pintado arriba (sin piezas encima). La tabla es una
// cápsula a lo largo de Y (en su malla), aplastada en Z: la cara de arriba es la
// que mira hacia -Z, y la punta está en -Y.
shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform vec3 board_color : source_color = vec3(1.0, 0.95, 0.8);
uniform vec3 color1 : source_color = vec3(0.89, 0.32, 0.23);
uniform vec3 color2 : source_color = vec3(0.18, 0.68, 0.61);
uniform int design = 0;
// Medio ancho y medio largo de la tabla (en su malla).
uniform float half_w = 0.5;
uniform float half_l = 1.8;

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

float flower(vec2 q, float r, float petals) {
	float a = atan(q.y, q.x);
	return length(q) - r * (0.62 + 0.38 * abs(cos(a * petals * 0.5)));
}

float star(vec2 q, float r) {
	float a = atan(q.y, q.x) + 1.5708;
	float k = abs(fract(a / 1.2566) - 0.5) * 2.0;
	return length(q) - r * mix(0.45, 1.0, k * k);
}

void fragment() {
	// x: de -1 a 1 a lo ancho; t: de -1 (punta) a 1 (cola). p: en metros de tabla
	// (a lo ancho, a lo largo), para formas redondas.
	float x = lp.x / half_w;
	float t = lp.y / half_l;
	vec2 p = vec2(lp.x, lp.y);
	vec3 col = board_color;
	bool top = -ln.z > 0.35;
	if (top) {
		if (design == 1) {
			// Dos rayas a lo largo.
			if (abs(t) < 0.8) {
				if (abs(x + 0.24) < 0.07) col = color1;
				else if (abs(x - 0.08) < 0.07) col = color2;
			}
		} else if (design == 2) {
			// Raya al medio con dos filetes.
			if (abs(t) < 0.78) {
				if (abs(x) < 0.14) col = color1;
				else if (abs(abs(x) - 0.22) < 0.03) col = color2;
			}
		} else if (design == 3) {
			// Punta pintada con una línea.
			float e = length(vec2(x / 0.72, (t + 0.66) / 0.32));
			if (e < 1.0) col = color1;
			else if (abs(t + 0.3) < 0.025 && abs(x) < 0.8) col = color2;
		} else if (design == 4) {
			// Lunares.
			vec2 c = vec2(lp.x, lp.y) / (half_w * 0.5);
			if (mod(floor(c.y), 2.0) > 0.5) c.x += 0.5;
			vec2 id = floor(c);
			vec2 q = fract(c) - 0.5;
			if (length(q) < 0.22 && abs(t) < 0.85) col = mod(id.x + id.y, 2.0) > 0.5 ? color1 : color2;
		} else if (design == 5) {
			// Llamas desde la cola hacia la punta.
			float k = abs(fract(x * 1.5 + 0.5) - 0.5) * 2.0;
			float edge = 0.55 - 0.55 * pow(1.0 - k, 1.5) + 0.03 * sin(x * 13.0);
			if (t > edge + 0.18) col = color2;
			else if (t > edge) col = color1;
		} else if (design == 6) {
			// Tres franjas de lado a lado (con la tabla, tres colores: rasta en roja).
			if (abs(t + 0.2) < 0.1) col = color1;
			else if (abs(t) < 0.1) col = color2;
		} else if (design == 7) {
			// Cuadros.
			vec2 c = vec2(x * 2.5, t * 7.0);
			if (abs(x) < 0.85 && abs(t) < 0.9) col = mod(floor(c.x) + floor(c.y), 2.0) > 0.5 ? color1 : color2;
		} else if (design == 8) {
			// Olas a lo ancho.
			float w = t * 5.0 + 0.35 * sin(x * 6.28318);
			float b = fract(w);
			if (abs(t) < 0.85) {
				if (b < 0.28) col = color1;
				else if (b > 0.4 && b < 0.5) col = color2;
			}
		} else if (design == 9) {
			// Rayo a lo largo.
			float k = fract(t * 1.6 + 0.25);
			float path = (abs(k - 0.5) * 2.0 - 0.5) * 0.7;
			float d = abs(x - path);
			if (abs(t) < 0.8) {
				if (d < 0.11) col = color1;
				else if (d < 0.19) col = color2;
			}
		} else if (design == 10) {
			// Tie-dye: espiral desde el centro.
			vec2 q = vec2(lp.x, lp.y * 0.7);
			float sp = length(q) * 11.0 - atan(q.y, q.x) * 1.0 + noise2(p * 6.0) * 1.4;
			float b = fract(sp / 3.0);
			col = b < 0.33 ? color1 : (b < 0.66 ? color2 : board_color);
		} else if (design == 11) {
			// Estrellas.
			vec2 c = vec2(lp.x, lp.y) / (half_w * 0.62);
			if (mod(floor(c.y), 2.0) > 0.5) c.x += 0.5;
			vec2 id = floor(c);
			vec2 q = fract(c) - 0.5;
			if (abs(t) < 0.85 && star(q, 0.38) < 0.0) col = mod(id.x + id.y, 2.0) > 0.5 ? color1 : color2;
		} else if (design == 12) {
			// Mitad y mitad, con un filete al medio.
			if (abs(x) < 0.05) col = color2;
			else if (x < 0.0) col = color1;
		} else if (design == 13) {
			// Flor hawaiana grande y dos chicas.
			vec2 q = vec2(lp.x, lp.y - half_l * 0.2) / half_w;
			vec2 q2 = vec2(lp.x + half_w * 0.25, lp.y + half_l * 0.45) / half_w;
			vec2 q3 = vec2(lp.x - half_w * 0.3, lp.y + half_l * 0.62) / half_w;
			if (length(q) < 0.13) col = color2;
			else if (flower(q, 0.8, 5.0) < 0.0) col = color1;
			else if (length(q2) < 0.07 || length(q3) < 0.06) col = color1;
			else if (flower(q2, 0.32, 5.0) < 0.0 || flower(q3, 0.26, 5.0) < 0.0) col = color2;
		} else if (design == 14) {
			// Zigzag en franja al medio.
			float z = t * 4.0 + abs(fract(x * 1.5) - 0.5);
			if (abs(t) < 0.5) {
				float b = fract(z);
				if (b < 0.3) col = color1;
				else if (b > 0.5 && b < 0.7) col = color2;
			}
		}
	}
	ALBEDO = col;
	ROUGHNESS = 0.8;
}
