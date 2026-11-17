// Contorno negro del público (como el de los personajes): la malla un poco
// más grande, de atrás, con el mismo movimiento.
shader_type spatial;
render_mode unshaded, cull_front;

#include "res://world/pieces/lib/crowd_motion.gdshaderinc"

uniform float jump = 0.0;
uniform float width = 0.016;

void vertex() {
	VERTEX = crowd_move(VERTEX, UV, INSTANCE_CUSTOM, jump, TIME) + NORMAL * width;
}

void fragment() {
	ALBEDO = vec3(0.0);
}
