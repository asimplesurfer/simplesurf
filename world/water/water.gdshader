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

uniform vec3 deep_color : source_color = vec3(0.02, 0.24, 0.48);
uniform vec3 shallow_color : source_color = vec3(0.08, 0.48, 0.7);
uniform vec3 foam_color : source_color = vec3(0.93, 0.98, 1.0);
uniform float foam_height = 0.42;
// Cuadrícula sutil para que se note la malla y la velocidad.
uniform vec3 grid_color : source_color = vec3(0.55, 0.85, 0.95);
uniform float grid_size = 4.0;
uniform float grid_strength = 0.3;
uniform float grid_fade_distance = 60.0;

varying float v_height;
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

void add_swell(vec4 a, vec4 b, vec2 p, inout float h, inout vec2 g) {
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
	float dh_du = amp * (-2.0 * u / (width * width)) * gauss * e;
	float dh_dw = amp * gauss * de * sign(w);
	g += dir * dh_du + perp * dh_dw;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = 0.0;
	vec2 g = vec2(0.0);
	add_wave(wave_0, world.xz, h, g);
	add_wave(wave_1, world.xz, h, g);
	add_wave(wave_2, world.xz, h, g);
	add_wave(wave_3, world.xz, h, g);
	add_swell(swell_a0, swell_b0, world.xz, h, g);
	add_swell(swell_a1, swell_b1, world.xz, h, g);
	add_swell(swell_a2, swell_b2, world.xz, h, g);
	add_swell(swell_a3, swell_b3, world.xz, h, g);
	add_swell(swell_a4, swell_b4, world.xz, h, g);
	add_swell(swell_a5, swell_b5, world.xz, h, g);
	VERTEX.y += h;
	NORMAL = normalize(vec3(-g.x, 1.0, -g.y));
	v_height = h;
	v_world = world + vec3(0.0, h, 0.0);
}

void fragment() {
	vec3 col = mix(deep_color, shallow_color, smoothstep(-0.5, 0.5, v_height));
	float foam = smoothstep(foam_height, foam_height + 0.1, v_height);
	col = mix(col, foam_color, foam * 0.7);

	vec2 gp = v_world.xz / grid_size;
	vec2 gw = max(fwidth(gp), vec2(0.0001));
	vec2 gl = abs(fract(gp - 0.5) - 0.5) / gw;
	float line = 1.0 - clamp(min(gl.x, gl.y), 0.0, 1.0);
	float fade = 1.0 - smoothstep(grid_fade_distance * 0.5, grid_fade_distance, distance(v_world, CAMERA_POSITION_WORLD));
	col = mix(col, grid_color, line * grid_strength * fade);

	ALBEDO = col;
	ROUGHNESS = 0.55;
	SPECULAR = 0.2;
}
