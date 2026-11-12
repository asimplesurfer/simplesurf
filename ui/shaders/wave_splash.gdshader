// Salir de atravesar una ola, como agua que te pega en la cara:
//  1. El golpe: una cortina de agua y espuma tapa la pantalla (wash: 1 -> 0 rápido).
//  2. Gotas grandes en la "lente" que chorrean hacia abajo dejando un rastro y
//     distorsionan la imagen (drops: 1 -> 0 en ~1 s).
//  3. Un poco borroso y con tono de agua mientras dura.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// Fuerza del golpe de agua (cortina de espuma).
uniform float wash : hint_range(0.0, 1.0) = 0.0;
// Cuántas gotas quedan (y cuánto se distorsiona).
uniform float drops : hint_range(0.0, 1.0) = 0.0;
// Tiempo desde el golpe (s): las gotas se deslizan.
uniform float elapsed = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + seed);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

// Gotas que chorrean: columnas con una gota cada una, que cae a su propia
// velocidad y deja un rastro arriba. Devuelve (desvío de la imagen, brillo).
vec3 drip_layer(vec2 uv, float aspect, float cols, float layer) {
	vec2 p = vec2(uv.x * cols * aspect, uv.y);
	float col = floor(p.x);
	float h = hash(vec2(col, layer));
	if (h < 0.35) {
		return vec3(0.0);
	}
	float x = fract(p.x) - 0.5 - (hash(vec2(col, layer + 3.0)) - 0.5) * 0.5;
	float speed = mix(0.15, 0.55, hash(vec2(col, layer + 7.0)));
	float start = hash(vec2(col, layer + 11.0)) * 0.7;
	float y_drop = start + speed * elapsed * elapsed * 1.6 + 0.05 * elapsed;
	float size = mix(0.06, 0.12, hash(vec2(col, layer + 13.0)));
	// La gota: elipse (un poco más alta que ancha). x está en ancho de columna:
	// una columna mide 1/cols de la altura de la pantalla.
	vec2 d = vec2((x / cols) / (size * 0.75), (uv.y - y_drop) / size);
	float r = length(d);
	float drop = 1.0 - smoothstep(0.7, 1.0, r);
	// El rastro, arriba de la gota: fino y cortado.
	float trail_y = clamp((y_drop - uv.y) / 0.35, 0.0, 1.0);
	float trail = (1.0 - smoothstep(0.03, 0.08, abs(x / cols) / size)) * step(0.0, y_drop - uv.y) * (1.0 - trail_y)
		* step(0.45, noise(vec2(col * 3.0, uv.y * 40.0)));
	vec2 offset = -d * drop * 0.035 + vec2(x * trail * 0.02, 0.0);
	float shine = drop * smoothstep(0.35, 0.9, r) + trail * 0.3;
	return vec3(offset, shine);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	vec3 a = drip_layer(uv, aspect, 7.0, 1.0);
	vec3 b = drip_layer(uv, aspect, 11.0, 2.0);
	vec2 offset = (a.xy + b.xy) * drops;
	float shine = (a.z + b.z) * drops;

	// Ondulación general del agua sobre la lente (fuerte en el golpe).
	vec2 wobble = vec2(fbm(uv * 6.0 + elapsed * 2.0), fbm(uv * 6.0 + 9.0 - elapsed * 2.0)) - 0.5;
	offset += wobble * 0.04 * wash;

	// Borroso (más en el golpe).
	float blur = 0.012 * wash + 0.003 * drops;
	vec3 col = vec3(0.0);
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			col += texture(screen_tex, uv + offset + vec2(float(i), float(j)) * blur).rgb;
		}
	}
	col /= 9.0;

	// Tono de agua.
	col = mix(col, col * vec3(0.7, 0.92, 1.05) + vec3(0.03, 0.1, 0.15), 0.5 * max(wash, drops * 0.4));
	// Brillo de las gotas.
	col += vec3(0.4) * shine;

	// La cortina de espuma: manchas blancas que se abren desde el centro hacia afuera.
	float foam_noise = fbm(uv * vec2(5.0 * aspect, 5.0) + seed);
	float edge = length((uv - 0.5) * vec2(aspect, 1.0));
	float cover = smoothstep(1.0 - wash * 1.25, 1.0 - wash * 1.25 + 0.25, foam_noise + edge * 0.35);
	col = mix(col, vec3(0.92, 0.97, 1.0), cover * wash);

	COLOR = vec4(col, 1.0);
}
