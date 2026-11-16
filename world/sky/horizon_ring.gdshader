// Siluetas del anillo de islas lejanas: sin luz, del color de la isla del
// cielo arriba y fundidas con el horizonte abajo (bruma), así parecen islas
// lejanas apoyadas sobre el mar.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
#include "res://world/sky/horizon.gdshaderinc"
uniform vec3 island_color : source_color = vec3(0.42, 0.68, 0.66);

varying float v_far;
varying float v_up;
varying vec3 v_world;

void vertex() {
	// COLOR.r: 0 = la fila de adelante (más cerca y nítida), 1 = la de atrás.
	// COLOR.g: 0 abajo, 1 arriba de la silueta.
	v_far = COLOR.r;
	v_up = COLOR.g;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 h = horizon_at(v_world.xz - CAMERA_POSITION_WORLD.xz);
	vec3 top = mix(island_color, island_color * 1.25, v_up);
	// Las de atrás, casi del color del horizonte; abajo, bruma sobre el mar.
	float haze = mix(0.38, 0.78, v_far);
	haze = mix(haze, 1.0, (1.0 - smoothstep(0.0, 0.35, v_up)) * 0.6);
	ALBEDO = mix(top, h, haze);
}
