// Contorno negro del público (como el de los personajes): la malla un poco
// más grande, de atrás, con el mismo movimiento. De lejos se apaga (en figuras
// tan chicas, el contorno solo suma ruido).
shader_type spatial;
render_mode unshaded, cull_front;

#include "res://world/pieces/lib/crowd_motion.gdshaderinc"

uniform float width = 0.016;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = crowd_move(VERTEX, UV, INSTANCE_CUSTOM, crowd_excite(origin), TIME);
	float far = distance(origin, (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	VERTEX = v + NORMAL * width * (1.0 - smoothstep(35.0, 80.0, far));
}

void fragment() {
	ALBEDO = vec3(0.0);
}
