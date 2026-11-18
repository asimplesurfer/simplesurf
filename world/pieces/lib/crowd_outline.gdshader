// Contorno negro del público (como el de los personajes): la malla un poco
// más grande, de atrás, con el mismo movimiento. Bien marcado: de lejos se
// ensancha un poco para que siga viéndose como una línea (si no, parece que
// no tuvieran contorno).
shader_type spatial;
render_mode unshaded, cull_front;

#include "res://world/pieces/lib/crowd_motion.gdshaderinc"

uniform float width = 0.02;
// Cuánto se ensancha por metro de distancia a la cámara, y el máximo.
uniform float width_per_m = 0.0008;
uniform float max_width = 0.065;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = crowd_move(VERTEX, UV, INSTANCE_CUSTOM, crowd_excite(origin), TIME);
	float far = distance(origin, (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	VERTEX = v + NORMAL * min(width + far * width_per_m, max_width);
}

void fragment() {
	ALBEDO = vec3(0.0);
}
