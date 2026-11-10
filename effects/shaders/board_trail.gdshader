// Estela de la tabla: cinta sobre el agua con bordes blancos que se abren y
// desvanecen, y espuma al centro cerca de la tabla.
// UV.x = de un borde al otro (0..1), UV.y = edad (0 = recién hecha, 1 = por desaparecer).
// COLOR.a = intensidad (más al girar y al derrapar).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://effects/shaders/noise.gdshaderinc"

uniform vec3 color : source_color = vec3(0.93, 0.98, 1.0);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = abs(UV.x * 2.0 - 1.0);
	float age = UV.y;
	// Dos líneas en los bordes, como la "V" que deja la tabla.
	float edge = smoothstep(0.5, 0.88, u) * (1.0 - smoothstep(0.9, 1.0, u));
	// Espuma en el centro, solo cerca de la tabla.
	float center = (1.0 - u) * 0.55 * (1.0 - smoothstep(0.0, 0.45, age));
	float n = fx_noise(v_world.xz * 2.2);
	float n2 = fx_noise(v_world.xz * 7.5);
	float a = max(edge, center) * (0.45 + 0.55 * n) * (0.65 + 0.35 * n2);
	a *= 1.0 - smoothstep(0.35, 1.0, age);
	ALBEDO = color;
	ALPHA = clamp(a * COLOR.a * 1.3, 0.0, 1.0);
}
