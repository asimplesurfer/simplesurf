shader_type canvas_item;
// Fondo del menú de pausa: el juego se sigue viendo atrás (en vivo), pero
// fuera de foco y lleno de luz, como una toma de cine desenfocada a contraluz:
// las luces se expanden, los colores se corren y se mezclan, grandes manchas
// de color se mueven despacio y hay luces redondas fuera de foco que titilan.
// El panel del menú se dibuja encima, sin pasar por acá: queda nítido.
//
// `amount` va de 0 (la pantalla tal cual) a 1 (el efecto completo); el menú lo
// anima al abrir y al cerrar, así el foco "se va" y "vuelve" de a poco.
//
// Lee la pantalla con mipmaps: el motor los arma ya suavizados, así un
// desenfoque enorme sale con pocas muestras (también en la web). Está hecho
// para gastar poco: unas 16 lecturas de la pantalla por píxel y cuentas
// baratas (sin senos para los números al azar).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Radio del desenfoque, en fracción del alto de la pantalla (igual en
// cualquier resolución).
uniform float blur_size = 0.045;
// Resplandor: desde qué brillo las luces se expanden, y cuánto.
uniform float bloom_threshold = 0.32;
uniform float bloom = 1.5;
// Soft focus: una copia mucho más desenfocada se suma "en pantalla" (aclara
// sin quemar), como un filtro de difusión delante de la lente.
uniform float glow = 0.3;
// Destello horizontal de las luces fuertes (como una lente de cine).
uniform float streak = 0.35;
// Grandes manchas de color que flotan despacio (toman el color de la escena).
uniform float leaks = 0.5;
// Luces redondas fuera de foco: cuántas (0..1) y qué tan fuertes.
uniform float bokeh_density = 0.42;
uniform float bokeh = 1.0;
// Colores más vivos (1 = como están) y un poco más de contraste.
uniform float saturation = 1.6;
uniform float contrast = 0.25;
// Difusión cromática: cada color sale de un lugar apenas distinto y se derrama
// sobre los vecinos.
uniform float bleed = 0.02;
// La imagen ondula despacio, como luz a través de un vidrio mojado.
uniform float flow = 0.03;
// Tono de cine: sombras hacia violeta, luces hacia rosa durazno.
uniform vec3 shadow_tint : source_color = vec3(0.30, 0.16, 0.60);
uniform vec3 light_tint : source_color = vec3(1.0, 0.66, 0.56);
uniform float tint = 0.45;
// Bordes un poco más oscuros: da profundidad y deja leer el menú.
uniform float vignette = 0.28;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

// Desenfoque suave: un mipmap (que ya viene desenfocado) en el centro y cuatro
// alrededor, en cruz girada: borran los "cuadrados" del mipmap. Con un mipmap
// un poco más chico, 5 muestras alcanzan para lo que antes llevaba 10.
vec3 soft(vec2 uv, float lod, vec2 radius) {
	vec3 c = textureLod(screen_tex, uv, lod).rgb * 2.0;
	c += textureLod(screen_tex, uv + vec2(0.92, 0.38) * radius, lod).rgb;
	c += textureLod(screen_tex, uv + vec2(-0.38, 0.92) * radius, lod).rgb;
	c += textureLod(screen_tex, uv + vec2(-0.92, -0.38) * radius, lod).rgb;
	c += textureLod(screen_tex, uv + vec2(0.38, -0.92) * radius, lod).rgb;
	return c / 6.0;
}

// Cuatro números al azar (0..1) por celda, sin senos (más barato).
vec4 hash4(vec2 p) {
	vec4 p4 = fract(p.xyxy * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

// Ruido suave de dos valores (para que la imagen ondule).
vec2 noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 a = hash4(i).xy;
	vec2 b = hash4(i + vec2(1.0, 0.0)).xy;
	vec2 c = hash4(i + vec2(0.0, 1.0)).xy;
	vec2 d = hash4(i + vec2(1.0, 1.0)).xy;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// El mismo tono, bien saturado y a pleno brillo (para teñir las luces).
vec3 vivid(vec3 c) {
	vec3 s = max(mix(vec3(dot(c, LUMA)), c, 2.2), 0.0);
	return s / max(max(s.r, max(s.g, s.b)), 0.05);
}

// Paleta de las luces: rosa, violeta, cian y ámbar.
vec3 light_hue(float h) {
	if (h < 0.25) {
		return vec3(1.0, 0.36, 0.74);
	} else if (h < 0.5) {
		return vec3(0.62, 0.42, 1.0);
	} else if (h < 0.75) {
		return vec3(0.32, 0.88, 1.0);
	}
	return vec3(1.0, 0.74, 0.36);
}

// Hombro suave: lo que pasa de `s` se acerca al blanco sin quemarse de golpe.
vec3 shoulder(vec3 c, float s) {
	vec3 over = max(c - s, 0.0);
	return min(c, vec3(s)) + (1.0 - s) * (1.0 - exp(-over / (1.0 - s)));
}

// Luz suave (como la capa de Photoshop): tiñe sin aplastar el contraste.
vec3 soft_light(vec3 base, vec3 blend) {
	return (1.0 - 2.0 * blend) * base * base + 2.0 * blend * base;
}

// Una capa de luces redondas fuera de foco. `p` está en celdas (cada celda
// puede tener una luz); cada luz da vueltas y titila a su ritmo, y mezcla un
// color de la paleta con el de la escena (`scene`). `soft_edge`: qué tan
// difuso es el borde.
//
// Cada luz se aleja como mucho 0,9 celdas del centro de la suya (0,2 de
// corrimiento + 0,28 de vuelta + 0,42 de radio), así que alcanza con mirar
// las 4 celdas más cercanas (no las 9 de alrededor).
vec3 bokeh_layer(vec2 p, float seed, float t, vec3 scene, float soft_edge) {
	vec2 first = floor(p - 0.5);
	vec3 acc = vec3(0.0);
	for (int y = 0; y <= 1; y++) {
		for (int x = 0; x <= 1; x++) {
			vec2 c = first + vec2(float(x), float(y));
			vec4 h = hash4(c + seed);
			if (h.x > bokeh_density) {
				continue;
			}
			// Cada luz da vueltas a su ritmo alrededor de su lugar (además de
			// lo que se mueve la capa entera): nunca queda quieta.
			float speed = 0.35 + h.w * 0.6;
			vec2 orbit = vec2(sin(t * speed + h.y * 6.283), cos(t * speed * 0.8 + h.z * 6.283)) * 0.28;
			vec2 center = c + 0.5 + (h.yz - 0.5) * 0.4 + orbit;
			float r = mix(0.2, 0.42, h.w);
			vec2 to = p - center;
			float d2 = dot(to, to);
			if (d2 >= r * r) {
				continue;
			}
			float d = sqrt(d2);
			// Disco con el borde apenas más brillante (como el de una lente).
			float disc = 1.0 - smoothstep(r * (1.0 - soft_edge), r, d);
			float rim = smoothstep(r * 0.5, r * 0.95, d) * disc;
			float twinkle = 0.5 + 0.5 * sin(t * (0.8 + h.y * 1.6) + h.z * 6.283);
			vec3 hue = mix(scene, light_hue(fract(h.x * 7.31 + h.w)), 0.5);
			acc += (disc * 0.65 + rim * 0.45) * twinkle * hue;
		}
	}
	return acc;
}

// Manchas grandes de luz de color que flotan por la pantalla (mezclan su color
// con el de la escena en cada punto, `scene`).
vec3 light_leaks(vec2 uv, float aspect, float t, vec3 scene) {
	vec2 p = uv * vec2(aspect, 1.0);
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 c = vec2(
			aspect * (0.5 + 0.5 * sin(t * (0.17 + 0.05 * fi) + fi * 1.9)),
			0.5 + 0.45 * cos(t * (0.13 + 0.04 * fi) + fi * 2.7)
		);
		float r = 0.3 + 0.1 * sin(t * 0.4 + fi * 1.3);
		vec2 d = p - c;
		float g = exp(-dot(d, d) / (r * r));
		acc += g * mix(light_hue(fi * 0.25 + 0.01), scene, 0.35);
	}
	return acc;
}

void fragment() {
	float k = clamp(amount, 0.0, 1.0);
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	// Ancho / alto, para que lo redondo salga redondo.
	float aspect = px.y / px.x;
	float t = TIME;

	// La imagen ondula: dos ruidos lentos desplazan dónde se lee la pantalla.
	vec2 warp = noise2(uv * vec2(2.2 * aspect, 2.2) + vec2(t * 0.14, t * 0.11)) - 0.5;
	vec2 wuv = uv + warp * flow * k;

	// Radio del desenfoque en píxeles y el mipmap que le corresponde.
	float r_px = blur_size * k / px.y;
	float lod = log2(max(r_px * 0.5, 1.0));
	vec2 radius = r_px * px;

	vec3 base = soft(wuv, lod + 0.6, radius * 0.55);

	// Difusión cromática: el rojo se corre hacia un lado y el azul hacia el
	// otro (la dirección gira despacio), más desenfocados que el resto.
	float ang = t * 0.3 + (uv.x - uv.y) * 1.5;
	vec2 dir = vec2(cos(ang) / aspect, sin(ang)) * bleed * k;
	float lod_b = lod + 1.0;
	base.r = mix(base.r, textureLod(screen_tex, wuv + dir, lod_b).r, 0.5 * k);
	base.b = mix(base.b, textureLod(screen_tex, wuv - dir, lod_b).b, 0.5 * k);

	// Una copia mucho más desenfocada: para el resplandor y el soft focus.
	vec3 wide = soft(wuv, lod + 2.3, radius * 1.6);
	float wl = dot(wide, LUMA);

	vec3 col = base;
	// Bloom: lo que pasa del umbral se expande y suma luz (con su color).
	float knee = max(wl - bloom_threshold, 0.0) / max(wl, 0.001);
	vec3 bright = mix(vec3(dot(wide * knee, LUMA)), wide * knee, 1.5);
	col += max(bright, 0.0) * bloom * k;
	// Soft focus: la copia desenfocada "en pantalla" (aclara sin quemar).
	col = 1.0 - (1.0 - col) * (1.0 - wide * glow * k);

	// Destello horizontal: las luces fuertes se estiran hacia los costados.
	float o1 = 0.05 / aspect;
	float o2 = 0.13 / aspect;
	vec3 line = (textureLod(screen_tex, vec2(wuv.x + o1, wuv.y), lod + 2.0).rgb
		+ textureLod(screen_tex, vec2(wuv.x - o1, wuv.y), lod + 2.0).rgb) * 0.75
		+ (textureLod(screen_tex, vec2(wuv.x + o2, wuv.y), lod + 2.0).rgb
		+ textureLod(screen_tex, vec2(wuv.x - o2, wuv.y), lod + 2.0).rgb) * 0.5;
	line /= 2.5;
	float ll = dot(line, LUMA);
	col += vivid(line) * max(ll - 0.55, 0.0) * streak * k;

	// Manchas grandes de color que flotan (se suman "en pantalla").
	vec3 scene_light = vivid(wide);
	vec3 leak = light_leaks(uv, aspect, t, scene_light);
	col = 1.0 - (1.0 - col) * (1.0 - clamp(leak * leaks * k, 0.0, 1.0));

	// Luces redondas fuera de foco, en tres capas que suben a distinto ritmo
	// (las grandes, más difusas). Más fuertes donde la escena brilla.
	vec2 bp = uv * vec2(aspect, 1.0);
	vec3 spots = bokeh_layer(bp * 7.0 + vec2(sin(t * 0.3) * 0.4, t * 0.3), 0.0, t, scene_light, 0.2) * 0.45
		+ bokeh_layer(bp * 4.0 + vec2(t * 0.06, t * 0.16), 11.0, t, scene_light, 0.3) * 0.6
		+ bokeh_layer(bp * 2.2 + vec2(-t * 0.04, t * 0.08), 23.0, t, scene_light, 0.55) * 0.5;
	float lit = mix(0.3, 1.0, smoothstep(0.2, 0.75, wl));
	col += spots * lit * bokeh * k * 0.5;

	// Colores vivos y mezclados, con un poco más de contraste.
	float l = dot(col, LUMA);
	col = max(mix(vec3(l), col, mix(1.0, saturation, k)), 0.0);
	vec3 cc = clamp(col, 0.0, 1.0);
	col = mix(col, col + (cc * cc * (3.0 - 2.0 * cc) - cc), contrast * k);
	// Tono de cine: violeta en las sombras, durazno en las luces.
	vec3 tone = mix(shadow_tint, light_tint, smoothstep(0.1, 0.9, l));
	col = mix(col, soft_light(clamp(col, 0.0, 1.0), tone), tint * k);

	// Que las luces fuertes se acerquen al blanco sin quemarse.
	col = mix(col, shoulder(col, 0.75), k);

	// Viñeta: bordes y esquinas más oscuros.
	vec2 v = (uv - 0.5) * vec2(1.0, 1.15);
	float vig = 1.0 - smoothstep(0.25, 0.85, length(v)) * vignette;
	col *= mix(1.0, vig, k);

	// Grano finito: evita los "escalones" en los degradés tan suaves.
	float grain = hash4(FRAGCOORD.xy + fract(t * 7.0) * 61.0).x - 0.5;
	col += grain * (2.5 / 255.0) * k;

	COLOR = vec4(col, 1.0);
}
