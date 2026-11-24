// Agua falsa: un plano subdividido cuyos vértices suben y bajan.
// La forma de la superficie está en water_surface.gdshaderinc (la misma que la física).
shader_type spatial;
// cull_disabled: la cresta que se curva puede quedar "dada vuelta".
render_mode specular_schlick_ggx, cull_disabled;

#include "res://effects/shaders/noise.gdshaderinc"

#include "res://world/water/water_surface.gdshaderinc"
// Pista (centro x, centro z, radio de adentro, radio de afuera). 0 = sin pista.
uniform vec4 track_band = vec4(0.0);
uniform vec3 outside_color : source_color = vec3(0.03, 0.15, 0.27);
// Pista con curvas: máscara vista desde arriba (1 = pista) sobre el rectángulo
// track_mask_rect (x, z de la esquina; ancho, largo). Ancho 0 = sin máscara.
uniform sampler2D track_mask : filter_linear, repeat_disable;
uniform vec4 track_mask_rect = vec4(0.0);
// Cuánto se oscurece el agua fuera de la pista.
uniform float outside_strength = 0.8;
// Bruma: lejos, el agua se vuelve del color del horizonte en esa dirección
// (el mismo que el cielo, ver horizon.gdshaderinc): llega a ese color antes de
// que termine el agua, así no se ve el borde ni desde un salto alto.
#include "res://world/sky/horizon.gdshaderinc"
// (Empieza detrás del anillo de islas lejanas, así quedan apoyadas sobre mar
// azul y no sobre una franja blanca.)
uniform vec2 haze_range = vec2(445.0, 515.0);
// Antes, el mar lejano: el agua se va a este celeste con bruma (el del cielo)
// entre estas distancias, y recién después se funde con el horizonte.
uniform vec3 far_sea_color : source_color = vec3(0.4, 0.72, 0.84);
uniform vec2 far_sea_range = vec2(150.0, 320.0);
// La niebla del agua la calcula este shader y la escribe en FOG (se aplica
// igual que la del Environment, después de la luz): de cerca es la misma de
// siempre; lejos se va al mar con bruma y al horizonte, no a una franja blanca.
// Densidad y color de la niebla del Environment (los pone Horizon).
uniform float fog_density = 0.0045;
// El mar de la zona media (de la pista al horizonte) no es liso: sombras de
// nubes que pasan, el camino de brillo del sol y algunos arrecifes con espuma.
// Solo desde MID_START metros (cerca de la pista el agua queda como siempre).
uniform vec3 sun_dir = vec3(0.4, 0.6, 0.7);
// 1 con sol, 0 con tormenta (no hay brillo del sol).
uniform float sun_glitter = 1.0;
uniform vec3 reef_color : source_color = vec3(0.33, 0.78, 0.76);
const vec2 MID_START = vec2(70.0, 150.0);
uniform vec3 fog_tint : source_color = vec3(0.93, 0.9, 0.96);

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
// Luces de las guirnaldas (de noche; ver Water.add_lamp): iluminan el agua y
// las olas (la cara que mira a la luz se aclara) y se reflejan en ellas.
// lamps: xyz posición, w alcance (m). lamp_colors: rgb color, a fuerza.
uniform int lamp_count = 0;
uniform vec4 lamps[64];
uniform vec4 lamp_colors[64];

varying float v_height;
// 0..1: cuerpo de una ola grande (para el color turquesa de la ola).
varying float v_body;
// 0..1: espuma de la ola que rompe (labio y cara).
varying float v_lip;
// 0..1: ola que todavía está creciendo ("se viene"): el agua se oscurece donde
// se va a levantar, aunque todavía no tenga altura.
varying float v_grow;
// Parte de una ola cerrada en tubo (labio, techo por adentro y pared).
varying float v_tube;
varying vec2 v_flow;
varying vec3 v_world;

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
	float h;
	vec2 g;
	vec2 disp;
	float ambient_h;
	float body;
	float lip;
	float grow;
	float tube;
	vec3 tube_n;
	vec2 flow;
	water_surface(world.xz, h, g, disp, ambient_h, body, lip, grow, tube, tube_n, flow);
	// Lejos del centro del plano el agua se aplana (después vienen los anillos
	// enormes hasta el horizonte, que no pueden seguir las olas).
	float calm = 1.0 - smoothstep(95.0, 125.0, distance(world.xz, NODE_POSITION_WORLD.xz));
	h *= calm;
	g *= calm;
	disp *= calm;
	body *= calm;
	lip *= calm;
	grow *= calm;
	tube *= calm;
	ambient_h *= calm;
	tube_n *= calm;
	VERTEX.y += h;
	VERTEX.xz += disp;
	NORMAL = normalize(vec3(-g.x, 1.0, -g.y));
	// Tubo: donde el agua está parada o dada vuelta, su normal de verdad.
	float tn = length(tube_n);
	if (tn > 0.001) {
		vec3 m = mix(NORMAL, tube_n / tn, min(tn, 1.0));
		NORMAL = dot(m, m) > 1.0e-6 ? normalize(m) : NORMAL;
	}
	v_height = ambient_h;
	v_body = body;
	v_lip = lip;
	v_grow = grow;
	v_tube = tube;
	v_flow = flow;
	v_world = world + vec3(disp.x, h, disp.y);
}

void fragment() {
	float t = fx_time;
	// Coordenadas de las texturas (manchas, espuma, brillos): las del mar.
	// En el tubo hay agua de costado y dada vuelta: se suma la altura, así la
	// textura no se estira en las paredes y se ve igual que en el resto.
	vec2 wp = v_world.xz + vec2(v_world.y) * 0.8 * v_tube;
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
	float fresnel = pow(1.0 - facing, 4.0) * (1.0 - 0.6 * v_tube);
	col = mix(col, sky_tint, fresnel * sky_reflect);
	// Tubo: el agua del labio es fina y deja pasar la luz (un poco más clara).
	// Por adentro es la misma agua que por afuera (ver BACKLIGHT más abajo).
	if (v_tube > 0.0) {
		col = mix(col, mix(wave_color, glow_color, 0.2), v_tube * 0.2);
	}

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
	// Tubo: el agua sube por la pared, pasa por el techo y sale por la punta
	// del labio (y por afuera también corre hacia la punta): vetas finas a lo
	// largo de ese camino, que se mueven hacia la punta.
	if (v_tube > 0.01) {
		float f = abs(v_flow.y) * 0.1 + t * 0.8;
		float vein = fx_noise(vec2(v_flow.x * 1.1, f));
		float vein2 = fx_noise(vec2(v_flow.x * 2.2 + 3.1, f * 1.6 + 1.3));
		float veins = max(smoothstep(0.67, 0.71, vein), smoothstep(0.7, 0.73, vein2) * 0.6);
		foam = max(foam, veins * v_tube * v_tube * 0.45);
	}
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
	float outside = 1.0;
	if (track_band.w > 0.0) {
		float d = distance(v_world.xz, track_band.xy);
		// Degradado de TRACK_FADE metros entre el agua de la pista y la de afuera.
		float out_inner = 1.0 - smoothstep(track_band.z - 16.0, track_band.z - 0.5, d);
		float out_outer = smoothstep(track_band.w + 0.5, track_band.w + 16.0, d);
		outside = max(out_inner, out_outer);
		col = mix(col, outside_color, outside * outside_strength);
	} else if (track_mask_rect.z > 0.0) {
		vec2 uv = (v_world.xz - track_mask_rect.xy) / track_mask_rect.zw;
		float inside = 0.0;
		if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
			inside = texture(track_mask, uv).r;
		}
		// La máscara ya trae el degradado (ver Water.set_track_path).
		outside = 1.0 - smoothstep(0.0, 1.0, inside);
		col = mix(col, outside_color, outside * outside_strength);
	}

	vec3 to_far = v_world - CAMERA_POSITION_WORLD;
	float far_d = length(to_far.xz);
	vec3 h_col = horizon_at(to_far.xz);
	// Tres capas, una sobre otra: niebla de siempre, mar lejano y horizonte.
	float a1 = 1.0 - exp(-fog_density * length(to_far));
	float a2 = smoothstep(far_sea_range.x, far_sea_range.y, far_d) * 0.85;
	float haze = smoothstep(haze_range.x, haze_range.y, far_d);
	vec3 c2 = mix(far_sea_color, h_col, 0.45);

	// --- Zona media: le da vida y escala al mar entre la pista y el horizonte.
	float mid = smoothstep(MID_START.x, MID_START.y, far_d) * (1.0 - haze);
	if (mid > 0.0) {
		// Sombras de nubes: manchas grandes y suaves que se mueven con el viento.
		vec2 wind = vec2(t * 0.9, t * 0.35);
		float cloud = fx_noise((wp + wind) * 0.006) * 0.7 + fx_noise((wp + wind) * 0.015 + 7.3) * 0.3;
		float shade = 1.0 - 0.42 * smoothstep(0.46, 0.7, cloud) * mid;
		// Arrecifes: unas pocas manchas turquesa (mar bajito), con espuma en el
		// borde donde rompe el mar. Solo fuera de la pista.
		float reef_n = fx_noise(wp * 0.0045 + vec2(17.3, 4.1)) * 0.75 + fx_noise(wp * 0.02 + 3.7) * 0.25;
		float reef = smoothstep(0.64, 0.68, reef_n) * outside * mid;
		float edge = (smoothstep(0.6, 0.64, reef_n) - smoothstep(0.64, 0.68, reef_n)) * outside * mid;
		float surf = step(0.45, fx_noise(wp * 0.25 + vec2(t * 0.6, t * 0.2)));
		vec3 shallow_mid = mix(c2, reef_color, 0.75);
		// Camino de brillo del sol: el reflejo del sol en un mar picado.
		vec3 view = normalize(to_far);
		vec2 ripple = vec2(fx_noise(wp * 0.45 + t * 0.7), fx_noise(wp * 0.45 - t * 0.6 + 9.1)) - 0.5;
		vec3 n = normalize(vec3(ripple.x * 0.35, 1.0, ripple.y * 0.35));
		// Con un sol "bajo" en la misma dirección: la franja se estira hasta el
		// horizonte (con el sol alto, el reflejo caería cerca, sobre la pista).
		vec3 low_sun = normalize(vec3(sun_dir.x, 0.12, sun_dir.z));
		float glint = pow(max(dot(reflect(view, n), low_sun), 0.0), 60.0);
		glint *= step(0.55, fx_noise(wp * 1.6 + vec2(t * 0.8, -t * 0.5))) * mid * sun_glitter;
		// Se aplica al agua y a la niebla de mar lejano (que de lejos la tapa).
		col = mix(col, reef_color, reef * 0.55) * shade;
		c2 = mix(c2, shallow_mid, reef) * shade;
		col = mix(col, foam_color, edge * surf * 0.8);
		c2 = mix(c2, foam_color, edge * surf * 0.7);
		c2 += vec3(1.0, 0.94, 0.82) * glint * 1.6;
		sparkle += glint * 1.5;
	}
	float keep = (1.0 - a1) * (1.0 - a2) * (1.0 - haze);
	// El motor pasa el color de su niebla en lineal; acá llega como se ve
	// (sRGB): se convierte para que de cerca quede igual que antes.
	vec3 near_fog = pow(fog_tint, vec3(2.2));
	vec3 fog_rgb = near_fog * a1 * (1.0 - a2) * (1.0 - haze) + c2 * a2 * (1.0 - haze) + h_col * haze;
	float fog_a = 1.0 - keep;
	// Por dentro de una ola que se cerró en tubo (la cara de atrás del agua):
	// agua vista desde adentro, un poco más oscura y sin la niebla del horizonte
	// (si no, las paredes lejanas del tubo se pintaban de cielo).
	vec3 fog_col = fog_a > 0.0001 ? fog_rgb / fog_a : near_fog;
	if (!FRONT_FACING) {
		fog_a *= 0.25;
	}
	FOG = vec4(fog_col, fog_a);
	ALBEDO = col;
	// El labio y la pared del tubo son finos: el sol pasa a través (por
	// adentro no quedan en sombra, como en una ola de verdad).
	BACKLIGHT = col * v_tube * 0.9;
	EMISSION = vec3(sparkle * 0.7 * (1.0 - haze));
	if (lamp_count > 0) {
		vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		// Una onda chica y lenta para que el reflejo se estire y se mueva (sin puntitos).
		vec2 rp = vec2(fx_noise(wp * 0.6 + t * 0.35), fx_noise(wp * 0.6 - t * 0.3 + 5.3)) - 0.5;
		vec3 ns = normalize(nw + vec3(rp.x, 0.0, rp.y) * 0.4);
		vec3 vw = normalize(CAMERA_POSITION_WORLD - v_world);
		vec3 lit = vec3(0.0);
		vec3 shine = vec3(0.0);
		for (int i = 0; i < lamp_count; i++) {
			vec3 to_l = lamps[i].xyz - v_world;
			float d = length(to_l);
			float reach = lamps[i].w;
			if (d > reach * 1.8) {
				continue;
			}
			vec3 l = to_l / d;
			vec3 c = pow(lamp_colors[i].rgb, vec3(2.2)) * lamp_colors[i].a;
			float att = clamp(1.0 - d / reach, 0.0, 1.0);
			att *= att;
			// Difusa "envuelta": la cara de la ola que mira a la luz se aclara,
			// pero la de atrás no queda negra.
			float diffuse = clamp(dot(nw, l) * 0.7 + 0.3, 0.0, 1.0);
			lit += c * att * diffuse;
			// Reflejo: depende de hacia dónde mira la superficie, no tanto de lo
			// cerca que esté la luz (así se estira hacia la cámara como en el mar).
			float spec = pow(max(dot(reflect(-l, ns), vw), 0.0), 70.0);
			shine += c * spec * (1.0 - smoothstep(reach, reach * 1.8, d));
		}
		// La luz aclara el color del agua (azul más claro y un poco cálido, no
		// marrón) y el reflejo se suma dorado.
		float keep_lamp = (1.0 - clamp(foam, 0.0, 1.0) * 0.4) * (1.0 - haze);
		EMISSION += (col * lit * 4.0 + lit * 0.03 + mix(shine, vec3(dot(shine, vec3(0.33))), 0.3) * 0.8) * keep_lamp;
	}
	ROUGHNESS = mix(0.26, 0.7, clamp(foam, 0.0, 1.0));
	SPECULAR = 0.38;
	// Adentro del tubo (pasando la punta del labio) sin el reflejo fuerte del
	// sol (con la normal mirando hacia adentro quedaban manchas blancas).
	float inner = v_tube * smoothstep(-0.5, 1.5, v_flow.y);
	ROUGHNESS = mix(ROUGHNESS, 0.75, inner);
	SPECULAR = mix(SPECULAR, 0.15, inner);
}
