// Agua falsa: un plano subdividido cuyos vértices suben y bajan.
// La fórmula es la misma que wave_definition.gd (no cambiar una sin la otra).
shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 wave_0; // xy = dirección, z = amplitud, w = longitud de onda
uniform vec4 wave_1;
uniform vec4 wave_2;
uniform vec4 wave_3;
uniform float speed_scale = 1.0;
uniform float wave_time = 0.0; // lo actualiza water.gd cada frame

// Olas grandes (ver swell.gd). a = (centro.x, centro.z, dir.x, dir.z); b = (amplitud, ancho, medio largo, borde)
uniform vec4 swell_a0; uniform vec4 swell_b0;
uniform vec4 swell_a1; uniform vec4 swell_b1;
uniform vec4 swell_a2; uniform vec4 swell_b2;
uniform vec4 swell_a3; uniform vec4 swell_b3;
uniform vec4 swell_a4; uniform vec4 swell_b4;
uniform vec4 swell_a5; uniform vec4 swell_b5;
uniform vec4 swell_a6; uniform vec4 swell_b6;
uniform vec4 swell_a7; uniform vec4 swell_b7;
// Isla (x, z, radio): las olas grandes se apagan cerca de la orilla. Radio 0 = sin isla.
uniform vec3 island = vec3(0.0);
// Pista (centro x, centro z, radio de adentro, radio de afuera). 0 = sin pista.
uniform vec4 track_band = vec4(0.0);
uniform vec3 outside_color : source_color = vec3(0.02, 0.17, 0.34);

uniform vec3 deep_color : source_color = vec3(0.02, 0.24, 0.48);
uniform vec3 shallow_color : source_color = vec3(0.08, 0.48, 0.7);
uniform vec3 foam_color : source_color = vec3(0.93, 0.98, 1.0);
uniform float foam_height = 0.42;

varying float v_height;
// 0..1: qué tan cerca de la cresta de una ola grande está el punto (para la espuma).
varying float v_crest;
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

void add_swell(vec4 a, vec4 b, vec2 p, inout float h, inout vec2 g, inout float crest) {
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
	float edge = b.w;
	if (aw >= half_len || abs(u) > width * 4.0) {
		return;
	}
	float gauss = exp(-(u * u) / (width * width));
	float t = clamp((aw - (half_len - edge)) / edge, 0.0, 1.0);
	float e = 1.0 - t * t * (3.0 - 2.0 * t);
	float de = -6.0 * t * (1.0 - t) / edge;
	h += amp * gauss * e;
	crest = max(crest, gauss * e * smoothstep(0.3, 1.2, amp));
	float dh_du = amp * (-2.0 * u / (width * width)) * gauss * e;
	float dh_dw = amp * gauss * de * sign(w);
	g += dir * dh_du + perp * dh_dw;
}

float island_fade(vec2 p) {
	if (island.z <= 0.0) {
		return 1.0;
	}
	float d = distance(p, island.xy);
	return smoothstep(island.z + 4.0, island.z + 28.0, d);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = 0.0;
	vec2 g = vec2(0.0);
	float crest = 0.0;
	add_wave(wave_0, world.xz, h, g);
	add_wave(wave_1, world.xz, h, g);
	add_wave(wave_2, world.xz, h, g);
	add_wave(wave_3, world.xz, h, g);
	float ambient_h = h;
	float sh = 0.0;
	vec2 sg = vec2(0.0);
	add_swell(swell_a0, swell_b0, world.xz, sh, sg, crest);
	add_swell(swell_a1, swell_b1, world.xz, sh, sg, crest);
	add_swell(swell_a2, swell_b2, world.xz, sh, sg, crest);
	add_swell(swell_a3, swell_b3, world.xz, sh, sg, crest);
	add_swell(swell_a4, swell_b4, world.xz, sh, sg, crest);
	add_swell(swell_a5, swell_b5, world.xz, sh, sg, crest);
	add_swell(swell_a6, swell_b6, world.xz, sh, sg, crest);
	add_swell(swell_a7, swell_b7, world.xz, sh, sg, crest);
	float fade = island_fade(world.xz);
	h += sh * fade;
	g += sg * fade;
	crest *= fade;
	VERTEX.y += h;
	NORMAL = normalize(vec3(-g.x, 1.0, -g.y));
	v_height = ambient_h;
	v_crest = crest;
	v_world = world + vec3(0.0, h, 0.0);
}

void fragment() {
	vec3 col = mix(deep_color, shallow_color, smoothstep(-0.5, 0.5, v_height));
	float foam = smoothstep(foam_height, foam_height + 0.1, v_height);
	// Olas grandes: un poco más claras y con espuma solo arriba de la cresta.
	col = mix(col, shallow_color * 1.15, v_crest * 0.6);
	foam = max(foam, smoothstep(0.82, 0.95, v_crest));
	col = mix(col, foam_color, foam * 0.7);

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
