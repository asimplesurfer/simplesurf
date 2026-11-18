// Reflejo de cada foco en el mar, como se ve de verdad de noche: una estela
// suave que sale de debajo del foco y viene hacia la cámara, apenas movida por
// las ondas. Es lo que hace que la luz parezca estar sobre el
// agua y no pintada encima.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float strength = 0.6;
// Ancho de la estela (m) y cuánto se estira hacia la cámara.
uniform float width = 1.4;
uniform float max_length = 30.0;

varying vec4 v_c;
varying float v_along;
varying vec3 v_world;

void vertex() {
	v_c = INSTANCE_CUSTOM;
	vec3 center = MODEL_MATRIX[3].xyz;
	vec2 to_cam = CAMERA_POSITION_WORLD.xz - center.xz;
	float dist = max(length(to_cam), 0.01);
	vec2 dir = to_cam / dist;
	vec2 across = vec2(-dir.y, dir.x);
	// Cada foco con su largo (parecido, no igual).
	float r = fract(sin(INSTANCE_CUSTOM.a * 91.7) * 4375.85);
	float len = clamp(dist * 0.45, 3.0, max_length) * (0.55 + 0.45 * r);
	// El quad va de -0.5 a 0.5: x es el ancho, y lo largo (desde el foco).
	v_along = VERTEX.y + 0.5;
	// Más ancha lejos del foco (las ondas la abren).
	float w = width * (0.6 + v_along * 1.2);
	vec2 p = center.xz + across * VERTEX.x * w + dir * v_along * len;
	v_world = vec3(p.x, center.y, p.y);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(v_world, 1.0)).xyz;
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float core = exp(-across * across * 2.0) * (1.0 - across);
	// Fuerte cerca del foco y se apaga hacia la cámara.
	float fade = smoothstep(0.0, 0.06, v_along) * pow(1.0 - v_along, 1.6);
	// Las ondas la mueven apenas: una ondulación lenta y suave (sin cortes).
	float wave = 0.8 + 0.2 * sin(v_along * 9.0 - TIME * 1.1 + v_c.a * 6.2831);
	float broken = wave;
	// El color del foco, apenas lavado.
	vec3 col = mix(v_c.rgb, vec3(1.0, 0.93, 0.8), 0.3);
	ALBEDO = col * core * fade * broken * strength;
}
